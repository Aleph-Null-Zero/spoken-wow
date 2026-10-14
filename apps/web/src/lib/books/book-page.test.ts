/**
 * book_page holds every page book_line has, in the same place.
 *
 * Needs DATABASE_URL and migrations applied (0074).
 */
import { afterAll, describe, expect, it } from "vitest";

import { closeDb, db } from "@/lib/db";

afterAll(closeDb);

describe("book_page", () => {
  it("has a row for every page book_line had when the migration ran", async () => {
    // Other suites insert book_line rows of their own afterwards; those are not the migration's.
    const { rows } = await db().query<{ missing: number }>(
      `with applied as (
         select applied_at from "schema_migrations" where "name" = '0074_book_page.sql'
       )
       select count(*) filter (where not exists (select 1 from "book_page" p where p."lineId" = l."lineId"))::int as "missing"
         from (select distinct "lineId" from "book_line", applied
                where "createdAt" <= applied.applied_at) l`,
    );
    expect(rows[0].missing).toBe(0);
  });

  it("places each extracted page where its English row does", async () => {
    const { rows } = await db().query<{ moved: number }>(
      `select count(*)::int as "moved" from "book_line" b join "book_page" p using ("lineId")
        where b."lang" = 'enUS' and b."isCurrent"
          and (p."bookId" <> b."bookId"::text or p."pageNumber" <> b."pageNumber"
               or p."pageTextId" <> b."pageId")`,
    );
    expect(rows[0].moved).toBe(0);
  });

  it("refuses two live pages at one place in one book", async () => {
    const bookId = `test-${Math.random().toString(36).slice(2)}`;
    await db().query(`insert into "book_page" ("lineId", "bookId", "pageNumber") values ($1, $2, 1)`, [`b:n${bookId}a`, bookId]);
    await expect(
      db().query(`insert into "book_page" ("lineId", "bookId", "pageNumber") values ($1, $2, 1)`, [`b:n${bookId}b`, bookId]),
    ).rejects.toThrow(/book_page_place/);
    await db().query(`delete from "book_page" where "bookId" = $1`, [bookId]);
  });
});
