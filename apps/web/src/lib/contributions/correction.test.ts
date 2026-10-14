/**
 * correction.ts, against a real Postgres.
 *
 * Needs DATABASE_URL and migrations applied. The quest lines are made by the test itself, under
 * a quest id far past any real one, and torn down after with everything accepting wrote.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { closeDb, db } from "@/lib/db";
import { createContribution } from "./store";

import { acceptCorrection, correctionNote } from "./correction";
import { lineStates } from "./known";

const ACCEPTER = "test-contributions-correction";
const quest = 2_000_000_000 - Math.floor(Math.random() * 1_000_000);
const lineId = `q:${quest}:accept`;
const file = `quests/${quest}-accept.mp3`;
const ip = `test-${Math.random().toString(36).slice(2, 10)}`;

async function contribution(locale: string, text: string, event = "accept"): Promise<number> {
  const { rows } = await db().query<{ id: number }>(
    `insert into "contribution" ("source", "key", "locale", "raw", "dedup", "text", "ip", "meta")
     values ('quests', $1, $2, 'raw', $3, $4, $5, $6::jsonb) returning "id"`,
    [
      `${quest}:${event}`,
      locale,
      `${ip}-${Math.random().toString(36).slice(2, 10)}`,
      text,
      ip,
      JSON.stringify({ quest: String(quest), event, title: "Test" }),
    ],
  );
  return rows[0].id;
}

beforeAll(async () => {
  await db().query(
    `insert into "user" ("id", "name", "email", "emailVerified")
     values ($1, 'Test Accepter', $2, false)
     on conflict ("id") do nothing`,
    [ACCEPTER, `${ACCEPTER}@example.invalid`],
  );
  await db().query(
    `insert into "quest_line"
       ("lineId", "variant", "lang", "version", "isCurrent", "origin", "source", "fileName",
        "text", "originalText", "localeText")
     values ($1, 0, 'enUS', 1, true, 'extracted', 'accept', $2, 'Hello, adventurer.', 'Hello, $n.', null),
            ($1, 0, 'deDE', 1, true, 'extracted', 'accept', $2, 'Hallo, $N.', 'Hello, $n.', 'Hallo, $N.')`,
    [lineId, `${quest}-accept`],
  );
});

afterAll(async () => {
  await db().query(
    `delete from "activity" where "lineId" = $1
        or ("kind" = 'contribution.resolved'
            and "subject" in (select "id"::text from "contribution" where "ip" = $2))`,
    [lineId, ip],
  );
  await db().query(`delete from "contribution" where "ip" = $1`, [ip]);
  await db().query(`delete from "line_override" where "file" = $1`, [file]);
  await db().query(`delete from "quest_line" where "lineId" = $1`, [lineId]);
  await db().query(`delete from "user" where "id" = $1`, [ACCEPTER]);
  await closeDb();
});

describe("acceptCorrection", () => {
  it("writes an English correction as the line's spoken override and accepts it", async () => {
    const id = await contribution("enUS", "Greetings, $N.");
    const outcome = await acceptCorrection(id, ACCEPTER);
    expect(outcome.ok && outcome.contribution.status).toBe("accepted");

    const { rows } = await db().query(`select "lineId", "text" from "line_override" where "file" = $1`, [file]);
    expect(rows).toEqual([{ lineId, text: "Greetings, Adventurer." }]);

    const { rows: logged } = await db().query(
      `select "detail" from "activity" where "kind" = 'override.set' and "subject" = $1`,
      [file],
    );
    expect(logged[0].detail.contribution).toBe(id);

    // The printed text is untouched, so the row is still a correction.
    const [state] = await lineStates([{ source: "quests", locale: "enUS", text: "Greetings, $N.", meta: { quest: String(quest), event: "accept" } }]);
    expect(state.kind).toBe("changed");
  });

  it("writes a translation's correction as a new version, noted as one", async () => {
    const id = await contribution("deDE", "Guten Tag, $N.");
    const outcome = await acceptCorrection(id, ACCEPTER);
    expect(outcome.ok && outcome.contribution.status).toBe("accepted");

    const { rows } = await db().query(
      `select "version", "text", "localeText", "note" from "quest_line"
        where "lineId" = $1 and "lang" = 'deDE' and "isCurrent"`,
      [lineId],
    );
    expect(rows).toEqual([{ version: 2, text: "Guten Tag, $N.", localeText: "Hallo, $N.", note: correctionNote(id) }]);
  });

  it("refuses a contribution the corpus does not differ from", async () => {
    const id = await contribution("enUS", "Hello, $N.");
    const outcome = await acceptCorrection(id, ACCEPTER);
    expect(outcome.ok).toBe(false);
    expect(!outcome.ok && outcome.reason).toBe("not-a-correction");
    const { rows } = await db().query(`select "status" from "contribution" where "id" = $1`, [id]);
    expect(rows[0].status).toBe("new");
  });

  it("answers not-found for an id that is not there", async () => {
    expect(await acceptCorrection(999_999_999, ACCEPTER)).toEqual({ ok: false, reason: "not-found" });
  });
});

describe("acceptCorrection: a books page", () => {
  const base = 900_000_000 + Math.floor(Math.random() * 90_000_000);
  const page = `b:${base}`;
  const english = `Words one ${base}.`;
  const dedups: string[] = [];

  beforeAll(async () => {
    await db().query(
      `insert into "book_page" ("lineId", "pageTextId", "bookId", "pageNumber", "ownerKind", "ownerIds")
       values ($1, $2, $3, 1, 'object', $4)`,
      [page, base, String(base), [base]],
    );
    await db().query(
      `insert into "book_line" ("lineId", "lang", "version", "isCurrent", "origin", "title", "text")
       values ($1, 'enUS', 1, true, 'extracted', $2, $3), ($1, 'esES', 1, true, 'extracted', $4, 'Viejo texto.')`,
      [page, `Tome ${base}`, english, `Libro ${base}`],
    );
  });

  afterAll(async () => {
    await db().query(
      `delete from "activity" where "kind" = 'contribution.resolved'
          and "subject" in (select "id"::text from "contribution" where "dedup" = any($1::text[]))`,
      [dedups],
    );
    await db().query(`delete from "contribution" where "dedup" = any($1::text[])`, [dedups]);
    await db().query(`delete from "book_line" where "lineId" = $1`, [page]);
    await db().query(`delete from "book_page" where "lineId" = $1`, [page]);
    await db().query(`delete from "entity_name" where "kind" = 'gameobject' and "entityId" = $1`, [String(base)]);
  });

  async function booksRow(text: string): Promise<number> {
    const dedup = `correction-test-${Math.random().toString(36).slice(2)}`;
    dedups.push(dedup);
    await createContribution({
      source: "books", key: dedup, locale: "esES", build: "1.15.7/61582", text,
      meta: { page: dedup, book: `Libro ${base}`, number: "1" },
      raw: `raw:${dedup}`, dedup, body: null, name: null, email: null, userId: null, ip: null,
    });
    const { rows } = await db().query<{ id: number }>(`select "id" from "contribution" where "dedup" = $1`, [dedup]);
    return rows[0].id;
  }

  async function versions() {
    const { rows } = await db().query(
      `select "version", "text", "origin", "note" from "book_line"
        where "lineId" = $1 and "lang" = 'esES' order by "version"`,
      [page],
    );
    return rows;
  }

  it("accepts a books correction as the page's new words, and the same words are then known", async () => {
    const id = await booksRow(english);
    expect(await acceptCorrection(id, ACCEPTER)).toMatchObject({ ok: true });
    expect(await versions()).toEqual([
      { version: 1, text: "Viejo texto.", origin: "extracted", note: null },
      { version: 2, text: english, origin: "edited", note: correctionNote(id) },
    ]);
    const [state] = await lineStates([{ source: "books", locale: "esES", text: english, meta: {} }]);
    expect(state).toEqual({ kind: "known" });
  });

  it("changes nothing when accepted a second time with the same text", async () => {
    const id = await booksRow(english);
    const before = await versions();
    // The corpus already says it, so the second accept is refused and writes no version.
    expect(await acceptCorrection(id, ACCEPTER)).toMatchObject({ ok: false, reason: "not-a-correction" });
    expect(await versions()).toEqual(before);
  });
});
