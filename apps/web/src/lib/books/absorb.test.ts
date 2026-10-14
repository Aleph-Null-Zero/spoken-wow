/**
 * absorb() against a real Postgres: the books pipeline has no database harness, so the
 * test lives where the web suite can run it.
 *
 * Needs DATABASE_URL and migrations applied.
 */
import { afterAll, afterEach, beforeEach, describe, expect, it } from "vitest";

import { closeDb, db } from "@/lib/db";
import { absorb } from "@books-tools/lib/absorb.mjs";

const n = 800_000_000 + Math.floor(Math.random() * 90_000_000);
const REAL = `b:${n}`;
const MINTED = `b:ntest${n}`;
const MINTED_FILE = `ntest${n}`;

async function line(lineId: string, lang: string, version: number, isCurrent: boolean, text: string) {
  await db().query(
    `insert into "book_line"
       ("lineId", "lang", "version", "isCurrent", "origin", "title", "text")
     values ($1, $2, $3, $4, 'extracted', 'T', $5)`,
    [lineId, lang, version, isCurrent, text],
  );
}

async function take(lineId: string, file: string, lang: string) {
  await db().query(
    `insert into "take" ("source", "lang", "file", "lineId", "version", "isCurrent", "origin", "bytes")
     values ('books', $3, $2, $1, 1, true, 'generated', 1)`,
    [lineId, file, lang],
  );
}

async function clean() {
  const ids = [REAL, MINTED];
  await db().query(`delete from "contribution" where "source" = 'books' and "key" like $1`, [`absorb-${n}%`]);
  for (const table of ["take", "report", "recording"]) {
    await db().query(`delete from "${table}" where "lineId" = any($1)`, [ids]);
  }
  await db().query(`delete from "book_line" where "lineId" = any($1)`, [ids]);
  await db().query(`update "book_page" set "aliasOf" = null where "lineId" = any($1)`, [ids]);
  await db().query(`delete from "book_page" where "lineId" = any($1)`, [ids]);
}

beforeEach(async () => {
  await clean();
  await db().query(
    `insert into "book_page" ("lineId", "pageTextId", "bookId", "pageNumber")
     values ($1, $3::int, $3::int::text, 1), ($2, null, $4, 1)`,
    [REAL, MINTED, n, `ntest${n}`],
  );
  await line(REAL, "enUS", 1, true, "Elf travellers:");
  await line(REAL, "esES", 1, true, "Trotamundos de los elfos:");
  await line(MINTED, "esES", 1, false, "Old wording");
  await line(MINTED, "esES", 2, true, "Trotamundos de los elfos:");
  await line(MINTED, "frFR", 1, true, "Voyageurs elfes:");
  await take(REAL, String(n), "esES");
  await take(MINTED, MINTED_FILE, "esES");
  await db().query(
    `insert into "report" ("source", "lang", "lineId", "category", "body")
     values ('books', 'esES', $1, 'other', 'x')`,
    [MINTED],
  );
  await db().query(
    `insert into "recording" ("source", "lang", "file", "lineId", "version", "format", "archiveFile", "bytes", "durationSec", "credit")
     values ('books', 'esES', $2, $1, 1, 'mp3', 'a', 1, 1, 'c')`,
    [MINTED, MINTED_FILE],
  );
  await db().query(
    `insert into "contribution" ("source", "key", "raw", "dedup", "matchLineId")
     values ('books', $1, 'r', $1, $2)`,
    [`absorb-${n}`, MINTED],
  );
});

afterEach(clean);
afterAll(closeDb);

describe("absorb", () => {
  it("moves a minted page's texts, takes, reports, recordings and matches to the real page", async () => {
    const client = await db().connect();
    try {
      await client.query("begin");
      await absorb(client, { from: MINTED, to: REAL });
      await client.query("commit");
    } finally {
      client.release();
    }

    const q = async (sql: string, p: unknown[]) => (await db().query(sql, p)).rows;
    expect(await q(`select count(*)::int as c from "book_line" where "lineId" = $1`, [MINTED])).toEqual([{ c: 0 }]);

    // The real page's own current text is unchanged; the minted one's is history; the
    // language the real page lacked is now current.
    const es = await q(
      `select "version", "isCurrent", "text" from "book_line" where "lineId" = $1 and "lang" = 'esES' order by "version"`,
      [REAL],
    );
    expect(es).toEqual([
      { version: 1, isCurrent: true, text: "Trotamundos de los elfos:" },
      { version: 2, isCurrent: false, text: "Old wording" },
      { version: 3, isCurrent: false, text: "Trotamundos de los elfos:" },
    ]);
    expect(await q(`select "isCurrent" from "book_line" where "lineId" = $1 and "lang" = 'frFR'`, [REAL])).toEqual([
      { isCurrent: true },
    ]);

    // Two takes were current for one (lineId, lang): the newer stays, both keep their file.
    const takes = await q(`select "file", "isCurrent" from "take" where "lineId" = $1 order by "id"`, [REAL]);
    expect(takes).toEqual([
      { file: String(n), isCurrent: false },
      { file: MINTED_FILE, isCurrent: true },
    ]);
    expect(await q(`select count(*)::int as c from "report" where "lineId" = $1`, [REAL])).toEqual([{ c: 1 }]);
    expect(await q(`select count(*)::int as c from "recording" where "lineId" = $1`, [REAL])).toEqual([{ c: 1 }]);
    expect(await q(`select "matchLineId" from "contribution" where "key" = $1`, [`absorb-${n}`])).toEqual([
      { matchLineId: REAL },
    ]);
    expect(await q(`select "aliasOf" from "book_page" where "lineId" = $1`, [MINTED])).toEqual([{ aliasOf: REAL }]);
  });
});
