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

import { answersQuestMomentSql, baseLineId, momentOf } from "@/lib/contributions/naming";
import { db } from "@/lib/db";
import { BASE_LANG, type Lang } from "@/lib/lang";
import type { NpcRowKind } from "@/lib/npc/npc";
import { getResolution } from "@/lib/npc/store";
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

/** The speaker an NPC's answer in `npc` makes, or null when it has no type. */
export async function speakerOf(npcType: NpcRowKind, npcId: number): Promise<Speaker | null> {
  const resolution = await getResolution(npcType, npcId);
  if (!resolution?.race) return null;
  const roster = await loadRoster();
  const voice = roster.voiceFor(resolution.race, resolution.gender, resolution.flavor);
  const family = voice ? roster.familyOf(voice) : null;
  return {
    npcId,
    npcName: resolution.npcName,
    npcType,
    race: family?.race ?? resolution.race,
    gender: family?.gender ?? resolution.gender ?? "",
    flavor: resolution.flavor,
    voice: voice ?? "",
  };
}

/** One writer per moment past this point: accept.ts takes the same lock by the same key. */
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

type SpeakerRow = { lineId: string; variant: number; lang: string; npcType: string; npcId: number; addedBy: string | null };

/** Every speaker row of a moment's lines (the plain one and its `:m`/`:f`), in `ord` order. */
async function momentSpeakers(client: PoolClient, moment: string): Promise<SpeakerRow[]> {
  const { rows } = await client.query<SpeakerRow>(
    `select "lineId", "variant", "lang", "npcType", "npcId", "addedBy" from "quest_line_speaker"
      where ${answersQuestMomentSql(`"lineId"`, "$1")}
      order by "lang" <> $2, "ord"`,
    [moment, BASE_LANG],
  );
  return rows;
}

/**
 * Makes `speaker` one more speaker of the moment, beside the ones it has: on each of its lines
 * (both player-gender sides of a split one) and each variant, in the language its speakers are
 * in. That is English's wherever English has any, since the catalogue reads only English's
 * speakers of such a line, and otherwise the first language that wrote one.
 *
 * Returns "spoken" when the NPC already speaks it, "unknown" when the moment has no speaker to
 * stand beside -- a line is in the explorer only through its speakers -- and "added" otherwise.
 * The caller holds the moment's lock.
 */
export async function addToMoment(
  client: PoolClient,
  moment: string,
  speaker: Speaker,
  mark: { contributionId?: number | null; addedBy?: string | null },
): Promise<"added" | "spoken" | "unknown"> {
  const rows = await momentSpeakers(client, moment);
  if (rows.length === 0) return "unknown";
  if (rows.some((row) => row.npcType === speaker.npcType && row.npcId === speaker.npcId)) return "spoken";

  const lang = rows[0].lang as Lang;
  const targets = new Map<string, { lineId: string; variant: number }>();
  for (const row of rows) {
    if (row.lang === lang) targets.set(`${row.lineId}|${row.variant}`, { lineId: row.lineId, variant: row.variant });
  }
  for (const target of targets.values()) await insertSpeaker(client, { ...target, lang, speaker, ...mark });
  return "added";
}

export type AddOutcome =
  | { ok: true }
  | { ok: false; reason: "unknown-line" | "spoken" | "no-voice"; message: string };

/**
 * An admin adds an NPC as one more speaker of a line, from the explorer. The NPC must already
 * be answered (`npc`) with a type a voice reads: a speaker is written with its voice, and the
 * catalogue gives it its own voice's line from there.
 */
export async function addSpeaker(args: {
  lineId: string;
  npcType: NpcRowKind;
  npcId: number;
  addedBy: string;
}): Promise<AddOutcome> {
  const speaker = await speakerOf(args.npcType, args.npcId);
  if (!speaker?.voice) {
    return {
      ok: false,
      reason: "no-voice",
      message: speaker
        ? `No voice reads ${[speaker.race, speaker.gender, speaker.flavor].filter(Boolean).join("-")} yet`
        : "This NPC has no type yet",
    };
  }
  const moment = momentOf(baseLineId(args.lineId));

  const client = await db().connect();
  try {
    await client.query("begin");
    await lockLine(client, moment);
    const outcome = await addToMoment(client, moment, speaker, { addedBy: args.addedBy });
    await client.query("commit");
    if (outcome === "unknown") return { ok: false, reason: "unknown-line", message: "unknown line" };
    if (outcome === "spoken") return { ok: false, reason: "spoken", message: "This NPC already speaks the line" };
    return { ok: true };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

export type RemoveOutcome =
  | { ok: true; removed: number }
  | { ok: false; reason: "extracted"; message: string };

/**
 * Takes back a speaker an admin added. Only those: the extract's speakers are the dump's, and a
 * contribution's go with the contribution.
 */
export async function removeSpeaker(args: {
  lineId: string;
  npcType: NpcRowKind;
  npcId: number;
}): Promise<RemoveOutcome> {
  const moment = momentOf(baseLineId(args.lineId));
  const client = await db().connect();
  try {
    await client.query("begin");
    await lockLine(client, moment);
    const rows = (await momentSpeakers(client, moment)).filter(
      (row) => row.npcType === args.npcType && row.npcId === args.npcId,
    );
    if (rows.some((row) => row.addedBy === null)) {
      await client.query("rollback");
      return { ok: false, reason: "extracted", message: "Only a speaker added by hand can be removed" };
    }
    const { rowCount } = await client.query(
      `delete from "quest_line_speaker"
        where ${answersQuestMomentSql(`"lineId"`, "$1")} and "npcType" = $2 and "npcId" = $3
          and "addedBy" is not null`,
      [moment, args.npcType, args.npcId],
    );
    await client.query("commit");
    return { ok: true, removed: rowCount ?? 0 };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}
