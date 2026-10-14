/**
 * Accepting a correction: a quest line the corpus has, sent back by a player's client with
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
 * to speak in that language. A template that branches on the player's gender is two lines in
 * either language: saveQuestText splits a translation, and correctEnglish an English line.
 *
 * Not one transaction with the status flip: the two writers own theirs, and both are
 * idempotent -- the same text again spends no version and logs nothing -- so an accept that
 * fails after the text is written is simply sent again.
 */
import "server-only";

import { recordActivity } from "@/lib/activity/store";
import { db } from "@/lib/db";
import { BASE_LANG, isLang } from "@/lib/lang";
import { branchesOnPlayerGender } from "@/lib/player-words";
import { englishMomentLines, rewriteEnglish } from "@/lib/quests/english-rewrite";
import { OverrideError } from "@/lib/quests/override";
import { QuestTextConflict, QuestTextMissing, saveQuestText } from "@/lib/quests/text";

import { lineStates } from "./known";
import { momentOf } from "./naming";
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
  if (contribution.source !== "quests" || !contribution.text || !isLang(lang)) {
    return { ok: false, reason: "not-a-correction", message: "Only a quest line sent in a site language is a correction." };
  }

  const [state] = await lineStates([contribution]);
  if (state.kind !== "changed") {
    return {
      ok: false,
      reason: "not-a-correction",
      message: "The corpus no longer has a different text for this line -- nothing to correct.",
    };
  }

  try {
    if (lang === BASE_LANG) {
      const refusal = await correctEnglish(momentOf(state.lineId), state.variant, contribution.text, id, userId);
      if (refusal) return refusal;
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
    if (error instanceof OverrideError || error instanceof QuestTextMissing || error instanceof QuestTextConflict) {
      return { ok: false, reason: "malformed", message: error.message };
    }
    throw error;
  }

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

/**
 * An English correction, written to every line the moment has (quests/english-rewrite.ts).
 *
 * A template without `$G` for a moment split by player gender is refused: the client resolves
 * `$G` before sending (Contribute.lua's Detemplate does not restore it) and the envelope does
 * not say which reader sent it, so the text is one side's words with no telling which.
 */
async function correctEnglish(
  moment: string,
  variant: number,
  template: string,
  contributionId: number,
  userId: string,
): Promise<Extract<CorrectionOutcome, { ok: false }> | null> {
  const rows = await englishMomentLines(moment, variant);
  if (rows.length === 0) {
    return { ok: false, reason: "not-a-correction", message: `${moment} is not a line the corpus has` };
  }

  const text = spokenFromTemplate(template);
  if (rows.some((row) => row.playerGender !== null) && !branchesOnPlayerGender(text)) {
    return {
      ok: false,
      reason: "malformed",
      message: "This line has a side for each player gender, and the correction is one player's words. Edit it in the explorer.",
    };
  }
  await rewriteEnglish(rows, variant, {
    text,
    originalText: template,
    userId,
    contributionId,
    note: correctionNote(contributionId),
  });
  return null;
}
