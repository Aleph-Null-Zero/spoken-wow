// Books.lua + a TrinityCore world DB -> addons/Spoken_Readables/Data/Variants.lua.
//
// Every chain the server can show (a spawned text object, an item the client has with a page),
// read the way Reader.lua reads it. A page the reader does not find gets an alias to the corpus
// page it stands for (lib/variants.mjs says which, and which are left). The world DB is the
// Forever repack's by default, read with places.mjs's PLACES_MYSQL_* variables, and the items
// come from Forever's client (ItemSparse, wago.tools), as places.mjs takes them.
//
// Committed, as Books.lua and Places.lua are: the addon builds on a clone with no database.

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

import mysql from "mysql2/promise";

import { loadEnv } from "../../lib/env.mjs";
import { FOREVER_BUILD, wagoTable } from "../../lib/wago.mjs";
import { walk } from "./lib/chains.mjs";
import { OBJECTS_SQL, readBooksLua, variantsLua, variantsOf } from "./lib/variants.mjs";

await loadEnv("books");

const BOOKS = fileURLToPath(new URL("../../../addons/Spoken_Readables/Data/Books.lua", import.meta.url));
const OUT = fileURLToPath(new URL("../../../addons/Spoken_Readables/Data/Variants.lua", import.meta.url));
const BUILD = process.env.PLACES_BUILD ?? FOREVER_BUILD;

const corpus = readBooksLua(await readFile(BOOKS, "utf8"));
if (corpus.pages.size === 0) throw new Error(`no pages read from ${BOOKS}`);

const db = await mysql.createConnection({
  host: process.env.PLACES_MYSQL_HOST ?? "127.0.0.1",
  port: Number(process.env.PLACES_MYSQL_PORT ?? 3317),
  user: process.env.PLACES_MYSQL_USER ?? "root",
  password: process.env.PLACES_MYSQL_PASSWORD ?? "",
  database: process.env.PLACES_MYSQL_DATABASE ?? "world",
});

let pages;
let objects;
try {
  [pages] = await db.query("SELECT ID AS entry, Text AS text, NextPageID AS nextPage FROM page_text");
  [objects] = await db.query(OBJECTS_SQL);
} finally {
  await db.end();
}

const byEntry = new Map(pages.map((page) => [Number(page.entry), { ...page, entry: Number(page.entry), nextPage: Number(page.nextPage) }]));
const owners = [];
const add = (title, firstPage) => {
  const chain = walk(firstPage, byEntry);
  if (chain.length) owners.push({ title, pages: chain.map((page) => ({ id: page.entry, text: page.text ?? "" })) });
};
for (const row of objects) add(row.name, Number(row.page));
for (const row of await wagoTable("ItemSparse", { build: BUILD })) {
  if (Number(row.PageID || 0) > 0) add(row.Display_lang, Number(row.PageID));
}

const { aliases, left } = variantsOf(corpus, owners);
await mkdir(dirname(OUT), { recursive: true });
await writeFile(OUT, variantsLua(aliases, corpus));

// Only the corpus's readables: the server's pages the corpus never had are not this file's.
const ours = left.filter((entry) => entry.why !== "no page of the corpus");
console.log(`${owners.length} chains, ${aliases.size} aliases; ${ours.length} pages of the corpus's readables left:`);
for (const entry of ours) console.log(`  ${entry.title ?? ""} ${entry.number ?? ""} (page ${entry.id}): ${entry.why}`);
console.log(`wrote ${OUT}`);
