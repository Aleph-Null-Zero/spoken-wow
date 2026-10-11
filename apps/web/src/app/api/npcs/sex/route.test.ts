/**
 * An admin's answer for one sex of an NPC, and splitting or unsplitting it. Modelled on
 * api/npcs/route.test.ts.
 *
 * Needs DATABASE_URL and migrations applied.
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

import { closeDb, db } from "@/lib/db";
import { getSexes, upsertResolution } from "@/lib/npc/store";

const RESOLVER = "test-npcs-sex-route";

vi.mock("@/lib/generation/authz", () => ({
  requireAdmin: async () => ({ lang: "enUS", session: { user: { id: RESOLVER } }, denied: null }),
}));

import { POST } from "./route";

const npcId = 900_000_000 + Math.floor(Math.random() * 99_999_999);

beforeAll(async () => {
  await db().query(
    `insert into "user" ("id", "name", "email", "emailVerified") values ($1, 'Test Resolver', $2, false)
     on conflict ("id") do nothing`,
    [RESOLVER, `${RESOLVER}@example.invalid`],
  );
});

beforeEach(async () => {
  await upsertResolution({
    npcKind: "creature", npcId, npcName: null, race: "human", gender: "male", flavor: "official",
    provenance: "corpus", confirmed: true, doubtful: false, modelFileId: null, sex: null,
    creatureType: null, build: null, note: null, resolvedBy: null,
  });
});

afterEach(async () => {
  await db().query(`delete from "npc" where "npcId" = $1`, [npcId]);
  await db().query(`delete from "activity" where "actorId" = $1`, [RESOLVER]);
});

afterAll(async () => {
  await db().query(`delete from "user" where "id" = $1`, [RESOLVER]);
  await closeDb();
});

function post(body: Record<string, unknown>): Promise<Response> {
  return POST(new Request("https://example.com/api/npcs/sex", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ npcKind: "creature", npcId, ...body }),
  }));
}

describe("POST /api/npcs/sex", () => {
  it("splits an NPC, its own sex keeping its answer and the other doubtful", async () => {
    const response = await post({ action: "split" });
    expect(response.status).toBe(200);
    expect((await getSexes("creature", npcId)).map((row) => [row.sex, row.race, row.provenance, row.doubtful])).toEqual([
      [2, "human", "moderator", false],
      [3, "human", "moderator", true],
    ]);
  });

  it("answers one sex, and refuses a flavor the roster has no voice for", async () => {
    await post({ action: "split" });
    expect((await post({ sex: 3, race: "human", flavor: "warrior" })).status).toBe(200);
    expect((await getSexes("creature", npcId))[1]).toMatchObject({ gender: "female", flavor: "warrior", doubtful: false });
    expect((await post({ sex: 3, race: "human", flavor: "nonsense" })).status).toBe(400);
  });

  it("unsplits an NPC", async () => {
    await post({ action: "split" });
    await post({ action: "unsplit" });
    expect(await getSexes("creature", npcId)).toEqual([]);
  });

  it("refuses a gameobject and a sex that is not a man's or a woman's", async () => {
    expect((await post({ npcKind: "gameobject", action: "split" })).status).toBe(400);
    expect((await post({ sex: 1, race: "human", flavor: "official" })).status).toBe(400);
  });
});
