/**
 * loadBookCorpus against a real Postgres: needs DATABASE_URL with migrations applied. The rows
 * it seeds use a page id far outside any extracted page and are removed afterwards.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { closeDb, db } from "@/lib/db";

import { loadBookCorpus } from "./book-match";

const id = 960_000_000 + Math.floor(Math.random() * 30_000_000);
const lineId = `b:${id}`;
const objectLineId = `b:${id + 1}`;
const bookId = String(id);
const ownerId = id;

async function cleanup() {
  await db().query(`delete from "book_line" where "lineId" = any($1::text[])`, [[lineId, objectLineId]]);
  await db().query(`delete from "book_page" where "lineId" = $1`, [lineId]);
  await db().query(`delete from "entity_name" where "kind" = 'item' and "entityId" = $1`, [String(ownerId)]);
  await db().query(`delete from "entity_name" where "kind" = 'gameobject' and "entityId" = $1`, [String(ownerId + 1)]);
  await db().query(`delete from "book_page" where "lineId" = $1`, [objectLineId]);
}

beforeAll(async () => {
  await cleanup();
  await db().query(
    `insert into "book_page" ("lineId", "pageTextId", "bookId", "pageNumber", "ownerKind", "ownerIds")
     values ($1, $2, $3, 1, 'item', array[$2::int])`,
    [lineId, id, bookId],
  );
  for (const [lang, text, title] of [
    ["esES", "Texto en español", "Título de la página"],
    ["deDE", "Deutscher Text", "Seitentitel"],
  ]) {
    await db().query(
      `insert into "book_line" ("lineId", "lang", "version", "isCurrent", "origin", "pageId", "bookId", "pageNumber",
                                "pageCount", "title", "ownerKind", "ownerIds", "text")
       values ($1, $2, 1, true, 'extracted', $3, $3, 1, 1, $4, 'item', array[$3::int], $5)`,
      [lineId, lang, id, title, text],
    );
  }
  await db().query(
    `insert into "book_page" ("lineId", "pageTextId", "bookId", "pageNumber", "ownerKind", "ownerIds")
     values ($1, $2, $3, 1, 'object', array[$2::int])`,
    [objectLineId, id + 1, String(id + 1)],
  );
  await db().query(
    `insert into "book_line" ("lineId", "lang", "version", "isCurrent", "origin", "pageId", "bookId", "pageNumber",
                              "pageCount", "title", "ownerKind", "ownerIds", "text")
     values ($1, 'esES', 1, true, 'extracted', $2, $2, 1, 1, ' Titulo propio ', 'object', array[$2::int], 'Texto de objeto')`,
    [objectLineId, id + 1],
  );
  await db().query(
    `insert into "entity_name" ("kind", "entityId", "lang", "version", "isCurrent", "origin", "name")
     values ('gameobject', $1, 'esES', 1, true, 'extracted', ' Nombre del cofre ')`,
    [String(ownerId + 1)],
  );
  await db().query(
    `insert into "entity_name" ("kind", "entityId", "lang", "version", "isCurrent", "origin", "name")
     values ('item', $1, 'esES', 1, true, 'extracted', 'Nombre del objeto')`,
    [String(ownerId)],
  );
});

afterAll(async () => {
  await cleanup();
  await closeDb();
});

describe("loadBookCorpus", () => {
  it("collects each language's words and the title its clients show, the owner's name first", async () => {
    const page = (await loadBookCorpus()).pages.find((p) => p.lineId === lineId)!;
    expect(page).toMatchObject({ bookId, pageNumber: 1, ownerKind: "item", ownerIds: [ownerId] });
    expect(Object.fromEntries(page.texts)).toEqual({ esES: "Texto en español", deDE: "Deutscher Text" });
    expect(Object.fromEntries(page.titles)).toEqual({ esES: "Nombre del objeto", deDE: "Seitentitel" });
  });

  it("titles an object-owned page from its gameobject name, trimmed", async () => {
    const page = (await loadBookCorpus()).pages.find((p) => p.lineId === objectLineId)!;
    expect(page.ownerKind).toBe("object");
    expect(Object.fromEntries(page.titles)).toEqual({ esES: "Nombre del cofre" });
  });

  it("is read once while nothing changes, and again once a page's words do", async () => {
    const first = await loadBookCorpus();
    expect(await loadBookCorpus()).toBe(first);
    await db().query(
      `insert into "book_line" ("lineId", "lang", "version", "isCurrent", "origin", "title", "text")
       values ($1, 'frFR', 1, true, 'extracted', 'Titre', 'Texte français')`,
      [lineId],
    );
    try {
      const next = await loadBookCorpus();
      expect(next).not.toBe(first);
      expect(next.pages.find((p) => p.lineId === lineId)!.texts.get("frFR")).toBe("Texte français");
    } finally {
      await db().query(`delete from "book_line" where "lineId" = $1 and "lang" = 'frFR'`, [lineId]);
    }
  });

  it("accepts a transaction client", async () => {
    const client = await db().connect();
    try {
      expect((await loadBookCorpus(client)).pages.some((p) => p.lineId === lineId)).toBe(true);
    } finally {
      client.release();
    }
  });
});
