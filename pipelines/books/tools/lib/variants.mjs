// The pages a server shows in other words than the corpus has, as aliases of the corpus page.
//
// The addon finds a page by a checksum of its text (Reader.lua). Forever's page_text holds some
// pages in words the corpus does not have: a spelling corrected, a sentence rewritten, a page
// given another id in its chain. Those pages were neither read aloud nor counted as found. An
// alias is the checksum of the server's text and the corpus page it stands for; the packs are
// keyed on the page id, so its clip plays, in the corpus's words.
//
// Pure, so the choices are tested without a database. tools/variants.mjs reads the inputs.

import { pageChecksum } from "./naming.mjs";
import { flatWords, normaliseText } from "./text.mjs";

/** What the client fills in ($N, $g): no checksum of the stored page matches what it shows. */
const SUBSTITUTION = /\$(?![Bb])[A-Za-z]/;

/** A server's stand-in for a page it has no text for, which is no page's words. */
const PLACEHOLDER = /^missing (wdb data|text)\.?$/i;

/**
 * The world DB's spawned objects that show a page: text objects (type 9) by the page in Data0, and
 * goobers (type 10), such as the Ameth'Aran tablets in Darkshore, by the page they open in Data7.
 * Spawned only: an object nothing places is a page no player is shown.
 */
export const OBJECTS_SQL = `SELECT t.entry, t.name, IF(t.type = 9, t.Data0, t.Data7) AS page FROM gameobject_template t
  WHERE ((t.type = 9 AND t.Data0 > 0) OR (t.type = 10 AND t.Data7 > 0))
    AND EXISTS (SELECT 1 FROM gameobject g WHERE g.id = t.entry)`;

const STRING = String.raw`"((?:[^"\\]|\\.)*)"`;

/** A Lua string literal's contents, as quote in lua.mjs writes them. */
export function unquote(body) {
  return body.replace(/\\(\d{3}|.)/g, (_, escape) => (/^\d{3}$/.test(escape) ? String.fromCharCode(Number(escape)) : escape));
}

function section(source, start, end) {
  const from = source.indexOf(start);
  if (from < 0) throw new Error(`Books.lua has no ${start.trim()}`);
  return source.slice(from, end ? source.indexOf(end, from) : undefined);
}

/**
 * The corpus as the addon looks pages up in it, read from the committed Books.lua: the export is
 * what players have, and the corpus itself is in Postgres on the site.
 */
export function readBooksLua(source) {
  const index = new Map();
  let byNumber;
  for (const line of section(source, "\tindex = {", "\tloose = {").split(/\r?\n/)) {
    const title = line.match(new RegExp(`^\\t\\t\\[${STRING}\\] = \\{$`));
    if (title) {
      byNumber = new Map();
      index.set(unquote(title[1]), byNumber);
      continue;
    }
    const number = line.match(/^\t\t\t\[(\d+)\] = \{ (.*) \},$/);
    if (number && byNumber) {
      byNumber.set(Number(number[1]), new Map([...number[2].matchAll(/\[(\d+)\] = (\d+)/g)].map((m) => [Number(m[1]), Number(m[2])])));
    }
  }
  const loose = new Map([...section(source, "\tloose = {", "\tpages = {").matchAll(/\[(\d+)\] = (\d+),/g)]
    .map((m) => [Number(m[1]), Number(m[2])]));
  const pages = new Map();
  for (const m of section(source, "\tpages = {", "\tbooks = {").matchAll(new RegExp(`\\[(\\d+)\\] = \\{ book = (\\d+), number = (\\d+), text = ${STRING} \\}`, "g"))) {
    pages.set(Number(m[1]), { book: Number(m[2]), number: Number(m[3]), text: unquote(m[4]) });
  }
  const books = new Map();
  for (const m of section(source, "\tbooks = {").matchAll(new RegExp(`\\[(\\d+)\\] = \\{ title = ${STRING}, pages = \\{ ([\\d, ]+) \\} \\}`, "g"))) {
    books.set(Number(m[1]), { title: unquote(m[2]), pages: m[3].split(",").map(Number) });
  }
  return corpusOf({ index, loose, pages, books });
}

/** The lookup tables, and what Reader.lua's PageByWords builds from the captions. */
export function corpusOf({ index, loose, pages, books }) {
  const words = new Map();
  const byWords = new Map();
  for (const [id, page] of pages) {
    const flat = flatWords(page.text);
    words.set(id, flat);
    if (flat) byWords.set(flat, byWords.has(flat) && byWords.get(flat) !== id ? null : id);
  }
  const keys = new Set();
  for (const byNumber of index.values()) for (const sums of byNumber.values()) for (const sum of sums.keys()) keys.add(sum);
  return { index, loose, pages, books, words, byWords, keys };
}

/**
 * The page Reader.lua's PageOnScreen finds for this text under this title and number, or null:
 * the checksum under the title and number, then alone where no other page has it, then the
 * words, as in PageByWords. The marked checksum is left out: the index is keyed on the plain one.
 */
export function lookup(corpus, title, number, raw, variants = new Map()) {
  const sum = pageChecksum(raw);
  const byNumber = corpus.index.get(title)?.get(number);
  const hit = byNumber?.get(sum) ?? corpus.loose.get(sum) ?? variants.get(sum);
  if (hit !== undefined && hit !== null) return hit;

  const words = flatWords(normaliseText(raw));
  if (!words) return null;
  let best = null;
  for (const id of new Set(byNumber?.values() ?? [])) {
    if (corpus.words.get(id) === words && (best === null || id < best)) best = id;
  }
  return best ?? corpus.byWords.get(words) ?? null;
}

/**
 * The aliases for the pages the server shows that the reader does not find, and why each of the
 * rest is left.
 *
 * The page an alias stands for is the server's page id where the corpus has it, else the page at
 * the same place in the readable the chain starts in: Neeka's Report runs 711-712-713-714 on the
 * server and 711-791-792-793 in the corpus. Left out: a page whose text holds what the client
 * fills in, as the player's name; a page with no words or a placeholder's; and words the corpus has for another
 * page, which are another readable's (Lady Mara Fordragon's plaque under the White Stag's page
 * 2304) and are found by PageByWords already where only one page has them.
 *
 * @param owners the chains the server shows: { title, pages: [{ id, text }] }, title being the
 *   name of the object or item that opens it
 * @returns aliases (checksum -> page id), and left ({ title, number, id, why })
 */
export function variantsOf(corpus, owners) {
  const claims = new Map();
  const left = [];
  const pageBook = new Map();
  for (const [id, page] of corpus.pages) pageBook.set(id, page.book);

  const sorted = [...owners].sort((a, b) => (a.pages[0]?.id ?? 0) - (b.pages[0]?.id ?? 0) || a.title.localeCompare(b.title));
  for (const owner of sorted) {
    const book = corpus.books.get(pageBook.get(owner.pages[0]?.id));
    owner.pages.forEach(({ id, text }, i) => {
      const number = i + 1;
      if (lookup(corpus, owner.title, number, text) !== null) return;
      const leave = (why) => left.push({ title: owner.title, number, id, why });
      const page = corpus.pages.has(id) ? id : book?.pages[i];
      if (page === undefined) return leave("no page of the corpus");
      if (SUBSTITUTION.test(text)) return leave("the client fills in the player's name or gender");
      const words = flatWords(normaliseText(text));
      if (!words) return leave("no words");
      if (PLACEHOLDER.test(words)) return leave("a placeholder");
      if (corpus.byWords.has(words) && corpus.words.get(page) !== words) return leave("the words of another page");
      const sum = pageChecksum(text);
      if (corpus.keys.has(sum)) return leave("the checksum of another page");
      if (!claims.has(sum)) claims.set(sum, new Set());
      claims.get(sum).add(page);
    });
  }

  const aliases = new Map();
  for (const [sum, pages] of claims) {
    // Two pages with these words: guessing between them narrates the wrong one's clip.
    if (pages.size === 1) aliases.set(sum, [...pages][0]);
    else left.push({ title: null, number: null, id: [...pages].join("/"), why: "one text for two pages" });
  }
  return { aliases, left };
}

/** Data/Variants.lua. */
export function variantsLua(aliases, corpus) {
  const lines = [...aliases].sort(([sa, a], [sb, b]) => a - b || sa - sb).map(([sum, id]) => {
    const page = corpus.pages.get(id);
    const title = corpus.books.get(page.book)?.title ?? "";
    return `\t\t[${sum}] = ${id}, -- ${title.replace(/[\r\n]+/g, " ")}, page ${page.number}`;
  });
  return `-- AUTO-GENERATED by pipelines/books/tools/variants.mjs. Do not edit by hand.
--
-- Pages a server shows in other words than Books.lua has for them, by the checksum of the
-- server's words: a spelling corrected, a sentence rewritten, a page given another id. Each is
-- the corpus page it stands for, so the reader finds it and counts it found, and the pack plays
-- that page's clip, in the corpus's words. Made from Books.lua and a TrinityCore world DB (the
-- Forever repack's; PLACES_MYSQL_*). Regenerate with:  make books-variants

if SpokenBooksData then
\tSpokenBooksData.variants = {
${lines.join("\n")}
\t}
end
`;
}
