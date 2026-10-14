/**
 * Which page a books contribution is, and what accepting it would do.
 *
 * The envelope names no page: its key is the checksum of the text on screen. So the page is
 * found the way a person would find it, most certain first -- the item or object the client
 * read it from, the same words in any language, then the title and page number the client
 * showed -- and where two candidates remain, nothing is guessed. A moderator's answer, stored on
 * the contribution, overrides all of it.
 *
 * Computed against the corpus as it stands, never stored: once a new book's first page is
 * accepted, its other pages find it by title.
 */
import { normaliseText } from "@books-tools/lib/text.mjs";

import type { PoolClient } from "pg";

import { db } from "@/lib/db";

export type BookCorpusPage = {
  lineId: string;
  bookId: string;
  pageNumber: number;
  ownerKind: "object" | "item" | null;
  ownerIds: number[];
  /** lang -> current text */
  texts: Map<string, string>;
  /** lang -> the title a client in that language shows: the owner's entity_name, else the page's own */
  titles: Map<string, string>;
};
export type BookCorpus = { pages: BookCorpusPage[] };

export type BookMatchInput = {
  locale: string;
  text: string | null;
  meta: Record<string, string>;
  matchLineId: string | null;
  matchBookId: string | null;
  matchPageNumber: number | null;
  matchNewBook: boolean;
};

export type BookMatchResult =
  | { kind: "known"; lineId: string; via: MatchVia }
  | { kind: "correction"; lineId: string; current: string; via: MatchVia }
  | { kind: "translation"; lineId: string; via: MatchVia }
  | { kind: "new-page"; bookId: string; pageNumber: number; via: MatchVia }
  | { kind: "new-book"; title: string; pageNumber: number; via: MatchVia }
  | { kind: "ambiguous"; candidates: string[] };
export type MatchVia = "moderator" | "owner" | "text" | "title" | "none";

const normal = (text: string) => (normaliseText(text) as string).trim();

function pageNumberOf(meta: Record<string, string>): number {
  const number = Number(meta.number);
  return Number.isInteger(number) && number > 0 ? number : 1;
}

function onPage(page: BookCorpusPage, row: BookMatchInput, via: MatchVia): BookMatchResult {
  const current = page.texts.get(row.locale);
  if (current === undefined) return { kind: "translation", lineId: page.lineId, via };
  if (row.text !== null && normal(current) === normal(row.text)) return { kind: "known", lineId: page.lineId, via };
  return { kind: "correction", lineId: page.lineId, current, via };
}

function inBook(corpus: BookCorpus, bookId: string, pageNumber: number, row: BookMatchInput, via: MatchVia): BookMatchResult {
  const page = corpus.pages.find((p) => p.bookId === bookId && p.pageNumber === pageNumber);
  return page ? onPage(page, row, via) : { kind: "new-page", bookId, pageNumber, via };
}

export function matchBook(row: BookMatchInput, corpus: BookCorpus): BookMatchResult {
  const pageNumber = row.matchPageNumber ?? pageNumberOf(row.meta);
  const title = row.meta.book?.trim() ?? "";

  if (row.matchLineId) {
    const page = corpus.pages.find((p) => p.lineId === row.matchLineId);
    if (page) return onPage(page, row, "moderator");
  }
  if (row.matchBookId) return inBook(corpus, row.matchBookId, pageNumber, row, "moderator");
  if (row.matchNewBook) return { kind: "new-book", title, pageNumber, via: "moderator" };

  // 1. What the client read it from.
  for (const [kind, field] of [["item", "item"], ["object", "object"]] as const) {
    const id = Number(row.meta[field]);
    if (!Number.isInteger(id) || id <= 0) continue;
    const books = new Set(corpus.pages.filter((p) => p.ownerKind === kind && p.ownerIds.includes(id)).map((p) => p.bookId));
    if (books.size === 1) return inBook(corpus, [...books][0], pageNumber, row, "owner");
  }

  // 2. The same words, in any language.
  if (row.text) {
    const said = normal(row.text);
    const same = corpus.pages.filter((p) => [...p.texts.values()].some((t) => normal(t) === said));
    if (same.length === 1) return onPage(same[0], row, "text");
    if (same.length > 1) {
      // The same words in this language on one page is that page, whatever else repeats them.
      const own = same.filter((p) => p.texts.has(row.locale) && normal(p.texts.get(row.locale)!) === said);
      if (own.length === 1) return onPage(own[0], row, "text");
      return { kind: "ambiguous", candidates: same.map((p) => p.lineId).sort() };
    }
  }

  // 3. The title and page number, in this language.
  if (title) {
    const books = [...new Set(corpus.pages.filter((p) => p.titles.get(row.locale) === title).map((p) => p.bookId))].sort();
    if (books.length === 1) return inBook(corpus, books[0], pageNumber, row, "title");
    if (books.length > 1) return { kind: "ambiguous", candidates: books };
  }

  // 4. Nothing has it.
  return { kind: "new-book", title, pageNumber, via: "none" };
}

/** Every live page with each language's current words and the title its clients show. */
export async function loadBookCorpus(client?: Pick<PoolClient, "query">): Promise<BookCorpus> {
  const q = client ?? db();
  const { rows } = await q.query<{
    lineId: string; bookId: string; pageNumber: number; ownerKind: "object" | "item" | null;
    ownerIds: number[] | null; lang: string | null; text: string | null; title: string | null; ownerName: string | null;
  }>(
    `select p."lineId", p."bookId", p."pageNumber", p."ownerKind", p."ownerIds",
            l."lang", l."text", l."title",
            (select n."name" from "entity_name" n
              where n."kind" = case p."ownerKind" when 'object' then 'gameobject' else 'item' end
                and n."entityId" = p."ownerIds"[1]::text and n."lang" = l."lang" and n."isCurrent") as "ownerName"
       from "book_page" p
       left join "book_line" l on l."lineId" = p."lineId" and l."isCurrent"
      where p."aliasOf" is null`,
  );
  const pages = new Map<string, BookCorpusPage>();
  for (const row of rows) {
    let page = pages.get(row.lineId);
    if (!page) {
      page = { lineId: row.lineId, bookId: row.bookId, pageNumber: row.pageNumber, ownerKind: row.ownerKind,
        ownerIds: row.ownerIds ?? [], texts: new Map(), titles: new Map() };
      pages.set(row.lineId, page);
    }
    if (row.lang && row.text !== null) page.texts.set(row.lang, row.text);
    const title = row.ownerName ?? row.title;
    if (row.lang && title) page.titles.set(row.lang, title);
  }
  return { pages: [...pages.values()] };
}
