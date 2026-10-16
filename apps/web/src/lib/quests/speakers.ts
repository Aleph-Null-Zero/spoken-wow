/**
 * Writing who speaks a line, outside the import: a speaker a player's contribution brought in
 * (contributions/accept.ts), and one an admin added by hand from the explorer.
 *
 * Both are rows the importer (tts_cli/corpus_db.py) keeps when it replaces every extracted
 * speaker, marked by "contributionId" (migration 0034) or "addedBy" (0076), and both take an
 * `ord` from ORD_FLOOR up. `ord` is unique per language, the extract numbers its own rows 0..n
 * on every import, and the export lists rows in `ord` order, so these always come after it.
 *
 * A speaker is written to the line, never to a voice's id (`{lineId}~{voice}`): the catalogue
 * gives each NPC its own voice's line from the speakers of the plain one.
 */
import type { PoolClient } from "pg";

import { answersQuestMomentSql } from "@/lib/contributions/naming";
import { noVoice } from "@/lib/contributions/speaker";
import { inTransaction } from "@/lib/db";
import { BASE_LANG, type Lang } from "@/lib/lang";
import type { NpcRowKind } from "@/lib/npc/npc";
import { getResolution, type NpcResolution } from "@/lib/npc/store";
import type { Roster } from "@/lib/voices/roster";
import { loadRoster } from "@/lib/voices/roster-store";

export const ORD_FLOOR = 1_000_000;

/**
 * Who speaks, as a speaker row spells it. `race` and `gender` are the ones its voice's files are
 * named by (migration 0071's voice table), not the NPC's type: a gameobject reads as the
 * narrator, as every one the extract wrote does.
 */
export type Speaker = {
  npcId: number;
  npcName: string | null;
  npcType: NpcRowKind;
  race: string;
  gender: string;
  flavor: string | null;
  /** "" while no voice reads the NPC's type; nothing here writes such a speaker. */
  voice: string;
};

/**
 * The speaker an NPC's answer makes, or null when it has no type. With no voice for its type,
 * race and gender stay the NPC's own, which is what noVoice names.
 */
export function speakerFromResolution(
  resolution: NpcResolution,
  roster: Roster,
  fallbackName: string | null = null,
): Speaker | null {
  if (!resolution.race) return null;
  const voice = roster.voiceFor(resolution.race, resolution.gender, resolution.flavor);
  const family = voice ? roster.familyOf(voice) : null;
  return {
    npcId: resolution.npcId,
    npcName: resolution.npcName ?? fallbackName,
    npcType: resolution.npcKind,
    race: family?.race ?? resolution.race,
    gender: family?.gender ?? resolution.gender ?? "",
    flavor: resolution.flavor,
    voice: voice ?? "",
  };
}

/** The speaker an NPC's answer in `npc` makes, or null when it has no type. */
export async function speakerOf(npcType: NpcRowKind, npcId: number): Promise<Speaker | null> {
  const [resolution, roster] = await Promise.all([getResolution(npcType, npcId), loadRoster()]);
  return resolution ? speakerFromResolution(resolution, roster) : null;
}

/** One writer per moment past this point, keyed by the moment's id. */
export async function lockLine(client: PoolClient, lineId: string): Promise<void> {
  await client.query(`select pg_advisory_xact_lock(hashtext('quest_line:' || $1))`, [lineId]);
}

/** A speaker row, marked by the contribution or the admin it came from. */
export async function insertSpeaker(
  client: PoolClient,
  row: {
    lineId: string;
    variant: number;
    lang: Lang;
    speaker: Speaker;
    contributionId?: number | null;
    addedBy?: string | null;
  },
): Promise<void> {
  // One writer at a time past this point, so two writes can never pick the same `ord`.
  await client.query(`select pg_advisory_xact_lock(hashtext('quest_line_speaker.contributed_ord'))`);
  const { speaker } = row;
  await client.query(
    `insert into "quest_line_speaker"
       ("lineId", "variant", "lang", "ord", "npcType", "npcId", "npcName", "race", "gender",
        "flavor", "voice", "contributionId", "addedBy")
     select $1, $2, $3,
            greatest(coalesce(max("ord") + 1, 0), $4),
            $5, $6, $7, $8, $9, $10, $11, $12, $13
       from "quest_line_speaker" where "lang" = $3`,
    [
      row.lineId, row.variant, row.lang, ORD_FLOOR, speaker.npcType, speaker.npcId,
      speaker.npcName ?? `npc ${speaker.npcId}`, speaker.race, speaker.gender, speaker.flavor,
      speaker.voice, row.contributionId ?? null, row.addedBy ?? null,
    ],
  );
}

export type SpeakerRow = {
  lineId: string;
  variant: number;
  lang: string;
  npcType: string;
  npcId: number;
  addedBy: string | null;
};

/**
 * Every speaker row of a moment's lines (the plain one and its `:m`/`:f`), English's first and
 * each language's in `ord` order.
 */
export async function momentSpeakers(client: PoolClient, moment: string): Promise<SpeakerRow[]> {
  const { rows } = await client.query<SpeakerRow>(
    `select "lineId", "variant", "lang", "npcType", "npcId", "addedBy" from "quest_line_speaker"
      where ${answersQuestMomentSql(`"lineId"`, "$1")}
      order by "lang" <> $2, "ord"`,
    [moment, BASE_LANG],
  );
  return rows;
}

/**
 * Whether the NPC is one of a moment's speakers. With no kind (an envelope that names none) it
 * is matched by id alone, as idOnlyResolution answers it. accept.ts's momentHasSpeaker asks the
 * same in SQL, for a page of rows at once.
 */
export function speaksMoment(rows: SpeakerRow[], npcId: number, npcKind: string | null): boolean {
  return rows.some((row) => row.npcId === npcId && (!npcKind || row.npcType === npcKind));
}

/**
 * Makes `speaker` one more speaker of the moment, beside the ones it has: on each of its lines
 * (both player-gender sides of a split one) and each variant, in the language its speakers are
 * in. That is English's wherever English has any, since the catalogue reads only English's
 * speakers of such a line, and otherwise the first language that wrote one.
 *
 * Returns "spoken" when the NPC already speaks it, "unknown" when the moment has no speaker to
 * stand beside -- a line is in the explorer only through its speakers -- and "added" otherwise.
 * The caller holds the moment's lock, and passes the moment's speakers when it already read them.
 */
export async function addToMoment(
  client: PoolClient,
  moment: string,
  speaker: Speaker,
  mark: { contributionId?: number | null; addedBy?: string | null },
  rows?: SpeakerRow[],
): Promise<"added" | "spoken" | "unknown"> {
  rows ??= await momentSpeakers(client, moment);
  if (rows.length === 0) return "unknown";
  if (speaksMoment(rows, speaker.npcId, speaker.npcType)) return "spoken";

  const lang = rows[0].lang as Lang;
  const targets = new Map<string, { lineId: string; variant: number }>();
  for (const row of rows) {
    if (row.lang === lang) targets.set(`${row.lineId}|${row.variant}`, { lineId: row.lineId, variant: row.variant });
  }
  for (const target of targets.values()) await insertSpeaker(client, { ...target, lang, speaker, ...mark });
  return "added";
}

export type AddOutcome =
  | { ok: true; speaker: Speaker }
  | { ok: false; reason: "unknown-line" | "spoken" | "no-voice"; message: string };

/**
 * An admin adds an NPC as one more speaker of a line, from the explorer. The NPC must already
 * be answered (`npc`) with a type a voice reads: a speaker is written with its voice, and the
 * catalogue gives it its own voice's line from there.
 */
export async function addSpeaker(args: {
  moment: string;
  npcType: NpcRowKind;
  npcId: number;
  addedBy: string;
}): Promise<AddOutcome> {
  const speaker = await speakerOf(args.npcType, args.npcId);
  if (!speaker?.voice) {
    return { ok: false, reason: "no-voice", message: speaker ? noVoice(speaker) : "This NPC has no type yet" };
  }
  const outcome = await inTransaction(async (client) => {
    await lockLine(client, args.moment);
    return addToMoment(client, args.moment, speaker, { addedBy: args.addedBy });
  });
  if (outcome === "unknown") return { ok: false, reason: "unknown-line", message: "unknown line" };
  if (outcome === "spoken") return { ok: false, reason: "spoken", message: "This NPC already speaks the line" };
  return { ok: true, speaker };
}

export type RemoveOutcome =
  | { ok: true; removed: number; npcName: string | null }
  | { ok: false; reason: "extracted"; message: string };

/**
 * Takes back a speaker an admin added. Only those: the extract's speakers are the dump's, and a
 * contribution's go with the contribution.
 */
export async function removeSpeaker(args: {
  moment: string;
  npcType: NpcRowKind;
  npcId: number;
}): Promise<RemoveOutcome> {
  const params = [args.moment, args.npcType, args.npcId];
  const ofNpc = `${answersQuestMomentSql(`"lineId"`, "$1")} and "npcType" = $2 and "npcId" = $3`;
  return inTransaction(async (client): Promise<RemoveOutcome> => {
    await lockLine(client, args.moment);
    const extracted = await client.query(
      `select 1 from "quest_line_speaker" where ${ofNpc} and "addedBy" is null limit 1`,
      params,
    );
    if (extracted.rowCount) {
      return { ok: false, reason: "extracted", message: "Only a speaker added by hand can be removed" };
    }
    const { rows: removed } = await client.query<{ npcName: string | null }>(
      `delete from "quest_line_speaker" where ${ofNpc} and "addedBy" is not null returning "npcName"`,
      params,
    );
    return { ok: true, removed: removed.length, npcName: removed[0]?.npcName ?? null };
  });
}
