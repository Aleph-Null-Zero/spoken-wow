/**
 * known.ts, against a real Postgres.
 *
 * Needs DATABASE_URL and migrations applied. The quest lines and speakers here are made by the
 * test itself, under a quest id and an NPC id far past any real one, and torn down after.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { closeDb, db } from "@/lib/db";

import { lineStates, tabOf } from "./known";

const quest = 2_000_000_000 - Math.floor(Math.random() * 1_000_000);
const npc = quest;
const gossipId = `g:test-known-${quest}`;

async function line(lineId: string, lang: string, source: string, originalText: string, localeText: string | null) {
  await db().query(
    `insert into "quest_line"
       ("lineId", "variant", "lang", "version", "isCurrent", "origin", "source", "fileName",
        "text", "originalText", "localeText")
     values ($1, 0, $2, 1, true, 'extracted', $3, $1, $4, $4, $5)`,
    [lineId, lang, source, originalText, localeText],
  );
}

beforeAll(async () => {
  await line(`q:${quest}:accept`, "enUS", "accept", "Hello, $n.$B$BTurn right at the tree.", null);
  await line(`q:${quest}:complete:m`, "enUS", "complete", "Thank you, sir.", null);
  await line(`q:${quest}:accept`, "deDE", "accept", "Hello, $n.", "Hallo, $N. $B $B Biegt rechts ab.");
  await line(gossipId, "enUS", "gossip", "Well met, traveler.", null);
  await db().query(
    `insert into "quest_line_speaker"
       ("lineId", "variant", "lang", "ord", "npcType", "npcId", "npcName", "race", "gender", "voice")
     values ($1, 0, 'enUS', $2, 'creature', $3, 'Tester', 'human', 'male', 'human-male')`,
    [gossipId, quest, npc],
  );
});

afterAll(async () => {
  await db().query(`delete from "quest_line_speaker" where "lineId" = $1`, [gossipId]);
  await db().query(`delete from "quest_line" where "lineId" = any($1::text[])`, [
    [`q:${quest}:accept`, `q:${quest}:complete:m`, gossipId],
  ]);
  await closeDb();
});

function moment(event: string, text: string, locale = "enUS") {
  return { source: "quests" as const, locale, text, meta: { quest: String(quest), event, title: "Test" } };
}

function greeting(id: number, text: string) {
  return { source: "quests" as const, locale: "enUS", text, meta: { npc: `${id} Tester`, kind: "creature" } };
}

describe("lineStates", () => {
  it("knows a quest line the corpus has, written the client's way", async () => {
    expect(await lineStates([moment("accept", "Hello, $N.\n\nTurn right at the tree.")])).toEqual([{ kind: "known" }]);
  });

  it("finds a player-gender variant under its moment", async () => {
    expect(await lineStates([moment("complete", "Thank you, sir.")])).toEqual([{ kind: "known" }]);
  });

  it("gives the corpus text of a moment that reads differently", async () => {
    expect(await lineStates([moment("accept", "Hello, $N.\n\nTurn left at the tree.")])).toEqual([
      { kind: "changed", lineId: `q:${quest}:accept`, variant: 0, current: "Hello, $n.$B$BTurn right at the tree." },
    ]);
  });

  it("compares a translation against its own language's text", async () => {
    expect(await lineStates([moment("accept", "Hallo, $N.\n\nBiegt rechts ab.", "deDE")])).toEqual([{ kind: "known" }]);
    expect(await lineStates([moment("accept", "Hello, $N.\n\nTurn right at the tree.", "frFR")])).toEqual([
      { kind: "missing" },
    ]);
  });

  it("calls a moment the corpus lacks missing", async () => {
    expect(await lineStates([moment("progress", "Any luck?")])).toEqual([{ kind: "missing" }]);
  });

  it("knows a greeting only from the NPC that speaks it, and never calls one changed", async () => {
    expect(await lineStates([greeting(npc, "Well met, traveler."), greeting(npc, "Begone."), greeting(npc + 1, "Well met, traveler.")])).toEqual([
      { kind: "known" },
      { kind: "missing" },
      { kind: "missing" },
    ]);
  });

  it("calls a greeting missing from an NPC drawn as the sex its voice is not, until it is split", async () => {
    const woman = { ...greeting(npc, "Well met, traveler."), meta: { ...greeting(npc, "").meta, sex: "3" } };
    const man = { ...woman, meta: { ...woman.meta, sex: "2" } };
    await db().query(
      `insert into "npc" ("npcKind", "npcId", "race", "gender", "flavor", "provenance")
       values ('creature', $1, 'human', 'male', 'official', 'corpus')`,
      [npc],
    );
    try {
      expect(await lineStates([woman, man])).toEqual([{ kind: "missing" }, { kind: "known" }]);
      await db().query(
        `insert into "npc_body" ("npcKind", "npcId", "race", "sex", "flavor", "provenance")
         values ('creature', $1, 'human', 2, 'official', 'corpus'), ('creature', $1, 'human', 3, 'official', 'client')`,
        [npc],
      );
      expect(await lineStates([woman, man])).toEqual([{ kind: "known" }, { kind: "known" }]);
    } finally {
      await db().query(`delete from "npc_body" where "npcKind" = 'creature' and "npcId" = $1`, [npc]);
      await db().query(`delete from "npc" where "npcKind" = 'creature' and "npcId" = $1`, [npc]);
    }
  });

  it("calls a greeting missing from an NPC drawn as another race, until that body is split", async () => {
    // npc is answered as a human man; 119159 is a gnome man's model.
    const gnome = { ...greeting(npc, "Well met, traveler."), meta: { ...greeting(npc, "").meta, sex: "2", model: "119159" } };
    await db().query(
      `insert into "npc" ("npcKind", "npcId", "race", "gender", "flavor", "provenance")
       values ('creature', $1, 'human', 'male', 'official', 'corpus')`,
      [npc],
    );
    try {
      expect((await lineStates([gnome]))[0]).toEqual({ kind: "missing" });
      await db().query(
        `insert into "npc_body" ("npcKind", "npcId", "race", "sex", "flavor", "provenance")
         values ('creature', $1, 'human', 2, 'standard', 'corpus'), ('creature', $1, 'gnome', 2, null, 'client')`,
        [npc],
      );
      expect((await lineStates([gnome]))[0]).toEqual({ kind: "known" });
    } finally {
      await db().query(`delete from "npc_body" where "npcKind" = 'creature' and "npcId" = $1`, [npc]);
      await db().query(`delete from "npc" where "npcKind" = 'creature' and "npcId" = $1`, [npc]);
    }
  });

  it("does not take one npc_body row alone for a split", async () => {
    const woman = { ...greeting(npc, "Well met, traveler."), meta: { ...greeting(npc, "").meta, sex: "3" } };
    await db().query(
      `insert into "npc" ("npcKind", "npcId", "race", "gender", "flavor", "provenance")
       values ('creature', $1, 'human', 'male', 'official', 'corpus')`,
      [npc],
    );
    try {
      await db().query(
        `insert into "npc_body" ("npcKind", "npcId", "race", "sex", "flavor", "provenance")
         values ('creature', $1, 'human', 3, 'official', 'moderator')`,
        [npc],
      );
      expect((await lineStates([woman]))[0]).toEqual({ kind: "missing" });
    } finally {
      await db().query(`delete from "npc_body" where "npcKind" = 'creature' and "npcId" = $1`, [npc]);
      await db().query(`delete from "npc" where "npcKind" = 'creature' and "npcId" = $1`, [npc]);
    }
  });

  it("reads an unknown model as the sex alone", async () => {
    const man = { ...greeting(npc, "Well met, traveler."), meta: { ...greeting(npc, "").meta, sex: "2", model: "1" } };
    await db().query(
      `insert into "npc" ("npcKind", "npcId", "race", "gender", "flavor", "provenance")
       values ('creature', $1, 'human', 'male', 'official', 'corpus')`,
      [npc],
    );
    try {
      expect((await lineStates([man]))[0]).toEqual({ kind: "known" });
    } finally {
      await db().query(`delete from "npc" where "npcKind" = 'creature' and "npcId" = $1`, [npc]);
    }
  });

  it("leaves zones and books alone", async () => {
    expect(await lineStates([{ source: "books", locale: "enUS", text: "Page", meta: {} }])).toEqual([{ kind: "missing" }]);
  });
});

describe("tabOf", () => {
  const changed = { kind: "changed", lineId: "q:1:accept", variant: 0, current: "x" } as const;

  it("puts a changed row on the corrections tab, accepted or not", () => {
    expect(tabOf("new", changed)).toBe("corrections");
    expect(tabOf("rejected", changed)).toBe("corrections");
    expect(tabOf("accepted", changed)).toBe("corrections");
  });

  it("lists a known row nowhere while it waits, and where it was resolved once it is", () => {
    expect(tabOf("new", { kind: "known" })).toBeNull();
    expect(tabOf("accepted", { kind: "known" })).toBe("contributions");
    expect(tabOf("rejected", { kind: "known" })).toBe("contributions");
  });
});
