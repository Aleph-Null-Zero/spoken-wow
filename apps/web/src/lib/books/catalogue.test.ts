/**
 * The catalogue lists every page book_page has, in each language, whether that language has
 * words for it or not.
 *
 * Needs DATABASE_URL and migrations applied (0074).
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { closeDb, db } from "@/lib/db";

import { catalogue, pageById } from "./catalogue";

const run = Math.random().toString(16).slice(2, 10);
const bookId = `n00000000-0000-4000-8000-${run.padEnd(12, "0")}`;
const lineId = `b:${bookId}`;

beforeAll(async () => {
  await db().query(`insert into "book_page" ("lineId", "bookId", "pageNumber") values ($1, $2, 1)`, [lineId, bookId]);
  await db().query(
    `insert into "book_line"
       ("lineId", "lang", "version", "isCurrent", "origin", "pageId", "bookId", "pageNumber",
        "pageCount", "title", "ownerKind", "ownerIds", "text")
     values ($1, 'esES', 1, true, 'contributed', 0, 0, 1, 1, 'Instrucciones', 'item', '{}', 'Trotamundos.')`,
    [lineId],
  );
});

afterAll(async () => {
  await db().query(`delete from "book_line" where "lineId" = $1`, [lineId]);
  await db().query(`delete from "book_page" where "lineId" = $1`, [lineId]);
  await closeDb();
});

describe("catalogue", () => {
  it("lists a page English lacks in English, without words", async () => {
    const page = (await catalogue("enUS")).find((p) => p.id === lineId);
    expect(page).toMatchObject({ key: bookId, pageId: null, generatable: false, missing: { text: true } });
    expect(page?.text).toBe("");
    expect(page?.title).toBe("Instrucciones");
  });

  it("lists it in its own language with its words", async () => {
    const page = (await catalogue("esES")).find((p) => p.id === lineId);
    expect(page).toMatchObject({ text: "Trotamundos.", title: "Instrucciones" });
    expect(page?.missing).toBeUndefined();
  });

  it("finds it by its key", async () => {
    expect((await pageById(bookId, "esES"))?.id).toBe(lineId);
    expect(await pageById("../x", "esES")).toBeUndefined();
  });
});
