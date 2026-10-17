/**
 * Accepting a correction as another wording of its quest moment (correction.ts acceptAsWording),
 * against a real Postgres.
 *
 * Needs DATABASE_URL and migrations applied. The quest, its lines and the NPCs are made by the
 * test itself under ids far past any real one, and torn down after with everything accepting wrote.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { closeDb, db } from "@/lib/db";
import { upsertResolution } from "@/lib/npc/store";
import { corpus } from "@/lib/quests/catalogue";

import { acceptAsWording } from "./correction";
import { lineStates } from "./known";

const ACCEPTER = "test-contributions-wording";
const quest = 2_000_000_000 - Math.floor(Math.random() * 1_000_000);
const npcId = 960_000_000 + Math.floor(Math.random() * 1_000_000);
const otherNpc = npcId + 1;
const moment = `q:${quest}:accept`;
const ip = `test-${Math.random().toString(36).slice(2, 10)}`;

async function contribution(locale: string, text: string, meta: Record<string, string> = {}): Promise<number> {
  const { rows } = await db().query<{ id: number }>(
    `insert into "contribution" ("source", "key", "locale", "raw", "dedup", "text", "ip", "meta")
     values ('quests', $1, $2, 'raw', $3, $4, $5, $6::jsonb) returning "id"`,
    [
      `${quest}:accept`,
      locale,
      `${ip}-${Math.random().toString(36).slice(2, 10)}`,
      text,
      ip,
      JSON.stringify({ quest: String(quest), event: "accept", title: "Test", kind: "creature", npc: `${npcId} Test Speaker`, ...meta }),
    ],
  );
  return rows[0].id;
}

beforeAll(async () => {
  await db().query(
    `insert into "user" ("id", "name", "email", "emailVerified")
     values ($1, 'Test Wording Accepter', $2, false)
     on conflict ("id") do nothing`,
    [ACCEPTER, `${ACCEPTER}@example.invalid`],
  );
  await upsertResolution({
    npcKind: "creature",
    npcId,
    npcName: "Test Speaker",
    race: "orc",
    gender: "female",
    flavor: "standard",
    provenance: "moderator",
    confirmed: true,
    doubtful: false,
    modelFileId: null,
    sex: null,
    creatureType: null,
    build: null,
    note: null,
    resolvedBy: ACCEPTER,
  });
  await db().query(
    `insert into "quest_line"
       ("lineId", "variant", "lang", "version", "isCurrent", "origin", "source", "questId", "fileName",
        "text", "originalText", "localeText")
     values ($1, 0, 'enUS', 1, true, 'extracted', 'accept', $2, $3, 'Hello, adventurer.', 'Hello, $n.', null),
            ($1, 0, 'deDE', 1, true, 'extracted', 'accept', $2, $3, 'Hallo, $N.', 'Hello, $n.', 'Hallo, $N.')`,
    [moment, quest, `${quest}-accept`],
  );
  await db().query(
    `insert into "quest_line_speaker"
       ("lineId", "variant", "lang", "ord", "npcType", "npcId", "npcName", "race", "gender", "flavor", "voice")
     select $1, 0, 'enUS', greatest(coalesce(max("ord") + 1, 0), 1000000), 'creature', $2, 'Other Speaker',
            'dwarf', 'male', null, 'dwarf-male'
       from "quest_line_speaker" where "lang" = 'enUS'`,
    [moment, otherNpc],
  );
});

afterAll(async () => {
  const lines = `q:${quest}:accept%`;
  await db().query(
    `delete from "activity" where "lineId" like $1
        or ("kind" = 'contribution.resolved'
            and "subject" in (select "id"::text from "contribution" where "ip" = $2))`,
    [lines, ip],
  );
  await db().query(`delete from "quest_line_speaker" where "lineId" like $1`, [lines]);
  await db().query(`delete from "contribution" where "ip" = $1`, [ip]);
  await db().query(`delete from "quest_line" where "lineId" like $1`, [lines]);
  await db().query(`delete from "entity_name" where "kind" = 'quest' and "entityId" = $1`, [String(quest)]);
  await db().query(`delete from "npc" where "npcId" between $1 and $2`, [npcId, otherNpc]);
  await db().query(`delete from "user" where "id" = $1`, [ACCEPTER]);
  await closeDb();
});

describe("acceptAsWording", () => {
  it("adds an English text as the moment's next wording, spoken by its NPC", async () => {
    const id = await contribution("enUS", "Oh, you are back, $N.");
    const outcome = await acceptAsWording(id, ACCEPTER);
    expect(outcome.ok && outcome.contribution.status).toBe("accepted");

    const { rows } = await db().query(
      `select "lineId", "fileName", "text", "originalText", "origin", "generatable"
         from "quest_line" where "lineId" = $1 and "lang" = 'enUS' and "isCurrent"`,
      [`${moment}:w1`],
    );
    expect(rows).toEqual([
      {
        lineId: `${moment}:w1`,
        fileName: `${quest}-accept-w1`,
        text: "Oh, you are back, Adventurer.",
        originalText: "Oh, you are back, $N.",
        origin: "contributed",
        generatable: true,
      },
    ]);
    const { rows: speakers } = await db().query(
      `select "npcId", "contributionId" from "quest_line_speaker" where "lineId" = $1`,
      [`${moment}:w1`],
    );
    expect(speakers).toEqual([{ npcId, contributionId: id }]);

    // Its text is now a wording the moment has, so the row leaves the corrections tab.
    const [state] = await lineStates([
      { source: "quests", locale: "enUS", text: "Oh, you are back, $N.", meta: { quest: String(quest), event: "accept" } },
    ]);
    expect(state.kind).toBe("known");
  });

  it("is a line of the explorer, in its quest", async () => {
    const lines = (await corpus("enUS")).lines;
    expect(lines.some((line) => line.lineId === `${moment}:w1` && line.fileName === `${quest}-accept-w1`)).toBe(true);
  });

  it("numbers past every wording in any language", async () => {
    const id = await contribution("deDE", "Ah, Ihr seid zurück.");
    const outcome = await acceptAsWording(id, ACCEPTER);
    expect(outcome.ok).toBe(true);
    const { rows } = await db().query(
      `select "localeText", "originalText" from "quest_line" where "lineId" = $1 and "lang" = 'deDE' and "isCurrent"`,
      [`${moment}:w2`],
    );
    expect(rows).toEqual([{ localeText: "Ah, Ihr seid zurück.", originalText: "Ah, Ihr seid zurück." }]);
  });

  it("only flips the status when its wording is already written", async () => {
    const id = await contribution("enUS", "Back again, are you?");
    expect((await acceptAsWording(id, ACCEPTER)).ok).toBe(true);
    await db().query(`update "contribution" set "status" = 'new' where "id" = $1`, [id]);
    const again = await acceptAsWording(id, ACCEPTER);
    expect(again.ok && again.contribution.status).toBe("accepted");
    const { rows } = await db().query(
      `select "lineId" from "quest_line" where "lineId" like $1 and "lang" = 'enUS' order by "lineId"`,
      [`${moment}:w%`],
    );
    // w1 from the first test, w3 here; the resend wrote no w4.
    expect(rows.map((row) => row.lineId)).toEqual([`${moment}:w1`, `${moment}:w3`]);
  });

  it("refuses a text the moment already has", async () => {
    const id = await contribution("enUS", "Hello, $n.");
    const outcome = await acceptAsWording(id, ACCEPTER);
    expect(!outcome.ok && outcome.reason).toBe("not-a-correction");
  });

  it("refuses a contribution whose NPC has no answer", async () => {
    const id = await contribution("enUS", "Who are you?", { npc: `${otherNpc + 1} Nobody` });
    const outcome = await acceptAsWording(id, ACCEPTER);
    expect(!outcome.ok && outcome.reason).toBe("needs-speaker");
  });
});
