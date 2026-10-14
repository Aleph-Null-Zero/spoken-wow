/**
 * Accepting a correction: a quest line or book page the corpus has, sent back by a player's client with
 * different text (known.ts's "changed"), taken as what the line now speaks.
 *
 * It is the explorer's text edit done in one click, not resolve's accept: that writes a line
 * that is missing (accept.ts), and this line is not. So it writes what the explorer's editor
 * would -- an English line's spoken rewrite (line_override, keyed by its file), another
 * language's new text version -- and marks the contribution accepted. The printed text the
 * correction was compared on (originalText, localeText) is left as the extract had it, as an
 * editor's fix leaves it: it is what names the file and what the addon matches on. The row
 * stays on the corrections tab, accepted (known.ts's tabOf).
 *
 * Both writes say where the text came from: the activity log names the contribution, and a
 * translation's version carries it in its note. line_override has no column for it.
 *
 * The English text is the template made spoken (tokens.ts), as accept.ts writes a contributed
 * line; another language keeps its $N, $C and $R, as accept does, for player-words.ts
 * to speak in that language.
 *
 * A book page is written as an editor's save of that language's text (a new 'edited' version).
 * Unlike a quest line, its text is what the row is compared on, so once accepted the row is
 * known, and tabOf lists it with the accepted contributions.
 *
 * Not one transaction with the status flip: the two writers own theirs, and both are
 * idempotent -- the same text again spends no version and logs nothing -- so an accept that
 * fails after the text is written is simply sent again. A book page so written already reads
 * as known; its current version carrying this contribution's note is what lets the resend
 * flip the status alone.
 */
import "server-only";

import { recordActivity } from "@/lib/activity/store";
import { audioRelPath } from "@/lib/audio";
import { BookConflict, BookMissing, saveBookText } from "@/lib/books/text";
import type { CorpusLine } from "@/lib/corpus";
import { db } from "@/lib/db";
import { BASE_LANG, isLang, type Lang } from "@/lib/lang";
import { OverrideError, validateOverride } from "@/lib/quests/override";
import { writeOverride } from "@/lib/quests/overrides";
import { QuestTextConflict, QuestTextMissing, saveQuestText } from "@/lib/quests/text";

import { lineStates } from "./known";
import { CONTRIBUTION_COLUMNS, type Contribution } from "./store";
import { spokenFromTemplate } from "./tokens";

export type CorrectionOutcome =
  | { ok: true; contribution: Contribution }
  | { ok: false; reason: "not-found" }
  | { ok: false; reason: "not-a-correction" | "malformed"; message: string };

/** The note a translation's version carries, so its history says where the text came from. */
export function correctionNote(contributionId: number): string {
  return `correction from the game, contribution #${contributionId}`;
}

export async function acceptCorrection(id: number, userId: string): Promise<CorrectionOutcome> {
  const { rows } = await db().query<Contribution>(
    `select ${CONTRIBUTION_COLUMNS} from "contribution" where "id" = $1`,
    [id],
  );
  const contribution = rows[0];
  if (!contribution) return { ok: false, reason: "not-found" };
  const lang = contribution.locale;
  if ((contribution.source !== "quests" && contribution.source !== "books") || !contribution.text || !isLang(lang)) {
    return {
      ok: false,
      reason: "not-a-correction",
      message: "Only a quest line or a book page sent in a site language is a correction.",
    };
  }

  const [state] = await lineStates([contribution]);
  if (state.kind === "known" && contribution.source === "books" && contribution.status !== "accepted"
      && (await bookCorrectionWritten(id, lang))) {
    return markAccepted(contribution, lang, userId);
  }
  if (state.kind !== "changed") {
    return {
      ok: false,
      reason: "not-a-correction",
      message: "The corpus no longer has a different text for this line -- nothing to correct.",
    };
  }

  try {
    if (contribution.source === "books") {
      await saveBookText({ lineId: state.lineId, text: contribution.text, note: correctionNote(id), editedBy: userId, lang });
    } else if (lang === BASE_LANG) {
      const { rows: lines } = await db().query<Pick<CorpusLine, "source" | "fileName">>(
        `select "source", "fileName" from "quest_line"
          where "lineId" = $1 and "variant" = $2 and "lang" = $3 and "isCurrent"`,
        [state.lineId, state.variant, BASE_LANG],
      );
      if (!lines[0]) {
        return { ok: false, reason: "not-a-correction", message: `${state.lineId} is not a line the corpus has` };
      }
      const draft = validateOverride({
        file: audioRelPath(lines[0]),
        lineId: state.lineId,
        text: spokenFromTemplate(contribution.text),
      });
      await writeOverride(draft.file, draft.lineId, draft.text, userId, id);
    } else {
      await saveQuestText({
        lineId: state.lineId,
        variant: state.variant,
        lang,
        text: contribution.text,
        note: correctionNote(id),
        editedBy: userId,
        contribution: id,
      });
    }
  } catch (error) {
    if (
      error instanceof OverrideError ||
      error instanceof QuestTextMissing ||
      error instanceof QuestTextConflict ||
      error instanceof BookMissing ||
      error instanceof BookConflict
    ) {
      return { ok: false, reason: "malformed", message: error.message };
    }
    throw error;
  }

  return markAccepted(contribution, lang, userId);
}

/**
 * Whether this contribution's correction is already the page's current text in its language:
 * the text was saved and the status flip after it failed, so the row now reads as known.
 */
async function bookCorrectionWritten(id: number, lang: string): Promise<boolean> {
  const { rowCount } = await db().query(
    `select 1 from "book_line" where "note" = $1 and "lang" = $2 and "isCurrent"`,
    [correctionNote(id), lang],
  );
  return (rowCount ?? 0) > 0;
}

async function markAccepted(contribution: Contribution, lang: Lang, userId: string): Promise<CorrectionOutcome> {
  const { id } = contribution;
  const client = await db().connect();
  try {
    await client.query("begin");
    const updated = await client.query<Contribution>(
      `update "contribution"
          set "status" = 'accepted', "resolvedBy" = $2, "updatedAt" = now()
        where "id" = $1
        returning ${CONTRIBUTION_COLUMNS}`,
      [id, userId],
    );
    await recordActivity(
      {
        kind: "contribution.resolved",
        lang,
        source: contribution.source,
        subject: String(id),
        actorId: userId,
        detail: { status: "accepted", key: contribution.key, correction: true },
      },
      client,
    );
    await client.query("commit");
    return { ok: true, contribution: updated.rows[0] };
  } catch (error) {
    await client.query("rollback").catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}
