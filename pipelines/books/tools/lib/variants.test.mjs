import assert from "node:assert/strict";
import { test } from "node:test";

import { booksLua } from "./lua.mjs";
import { pageChecksum } from "./naming.mjs";
import { flatWords } from "./text.mjs";
import { OBJECTS_SQL, lookup, readBooksLua, unquote, variantsLua, variantsOf } from "./variants.mjs";

// A corpus in the shape export.mjs writes, read back the way variants.mjs reads Books.lua.
const ROWS = [
  { pageId: 711, bookId: 711, pageNumber: 1, pageCount: 3, title: "Neeka's Report", text: "Helgrum, my compliments." },
  { pageId: 791, bookId: 711, pageNumber: 2, pageCount: 3, title: "Neeka's Report", text: "I will describe the surrounding lands." },
  { pageId: 792, bookId: 711, pageNumber: 3, pageCount: 3, title: "Neeka's Report", text: "Dark Iron dwarves inhabit a barracks." },
  { pageId: 2294, bookId: 2294, pageNumber: 1, pageCount: 1, title: "Lady Mara Fordragon", text: "Lady Mara Fordragon\nHigh Clerist of Stormwind" },
  { pageId: 2304, bookId: 2301, pageNumber: 1, pageCount: 1, title: "The White Stag and the Moon", text: "The clever moon made a bargain." },
  { pageId: 66, bookId: 64, pageNumber: 1, pageCount: 1, title: "The Story of Morgan Ladimore", text: "The cemetary was quiet. <He wept>" },
];
const corpus = readBooksLua(booksLua(ROWS));

test("Books.lua reads back as the corpus it was written from", () => {
  assert.equal(corpus.pages.get(66).text, "The cemetary was quiet.\nHe wept");
  assert.deepEqual(corpus.books.get(711).pages, [711, 791, 792]);
  assert.equal(corpus.index.get("Neeka's Report").get(2).get(pageChecksum(ROWS[1].text)), 791);
  assert.equal(unquote(String.raw`a\"b\\c\010d`), 'a"b\\c\nd');
});

test("flat words ignore the layout, and a caption flattens as its page does", () => {
  assert.equal(flatWords("One.  Two\n\nthree"), "One. Two three");
  assert.equal(flatWords("The cemetary was quiet. <He wept>"), flatWords(corpus.pages.get(66).text));
  assert.equal(flatWords("Fish &amp; chips"), "Fish & chips");
});

test("the lookup finds a page by checksum, then by its words with the layout ignored", () => {
  assert.equal(lookup(corpus, "Neeka's Report", 2, "I will describe the surrounding lands."), 791);
  assert.equal(lookup(corpus, "Neeka's Report", 2, "I will describe$Bthe surrounding  lands."), 791);
  assert.equal(lookup(corpus, "Neeka's Report", 3, "Darkiron dwarves inhabit a barracks."), null);
});

const owners = [
  { title: "Neeka's Report", pages: [
    { id: 711, text: "Helgrum, my compliments." },
    { id: 712, text: "I will describe the surrounding lands." },
    { id: 713, text: "Darkiron dwarves inhabit a barracks." },
  ] },
  { title: "The White Stag and the Moon", pages: [{ id: 2304, text: "Lady Mara Fordragon$BHigh Clerist of Stormwind" }] },
  { title: "The Story of Morgan Ladimore", pages: [{ id: 66, text: "The cemetery was quiet. <He wept>" }] },
];

test("a page the server words differently is an alias of its own page", () => {
  const { aliases } = variantsOf(corpus, owners);
  assert.equal(aliases.get(pageChecksum("The cemetery was quiet. <He wept>")), 66);
});

test("a page the server keeps under an id the corpus lacks stands for the page at its place in the readable", () => {
  const { aliases } = variantsOf(corpus, owners);
  assert.equal(aliases.get(pageChecksum("Darkiron dwarves inhabit a barracks.")), 792);
});

test("another readable's words on a reused page id are no alias of that page", () => {
  const { aliases } = variantsOf(corpus, owners);
  assert.equal([...aliases.values()].includes(2304), false);
  assert.equal(lookup(corpus, "The White Stag and the Moon", 1, owners[1].pages[0].text), 2294);
});

test("pages the alias cannot be right for are left, each with why", () => {
  const { aliases, left } = variantsOf(corpus, [
    { title: "The Story of Morgan Ladimore", pages: [{ id: 66, text: "Hello, $N. The cemetery." }] },
    { title: "Book", pages: [{ id: 66, text: "<HTML><BODY><IMG src=\"x\"/></BODY></HTML>" }] },
    { title: "The Story of Morgan Ladimore", pages: [{ id: 66, text: "Missing WDB data." }] },
    { title: "Bloody Note", pages: [{ id: 10322, text: "A cult attack." }] },
  ]);
  assert.equal(aliases.size, 0);
  assert.deepEqual(left.map((entry) => entry.why), [
    "no words",
    "the client fills in the player's name or gender",
    "a placeholder",
    "no page of the corpus",
  ]);
});

test("one server text claimed by two pages is dropped rather than guessed", () => {
  const { aliases, left } = variantsOf(corpus, [
    { title: "The Story of Morgan Ladimore", pages: [{ id: 66, text: "Same words." }] },
    { title: "Neeka's Report", pages: [{ id: 711, text: "Same words." }] },
  ]);
  assert.equal(aliases.size, 0);
  assert.equal(left.at(-1).why, "one text for two pages");
});

test("Variants.lua names each alias's readable and page", () => {
  const lua = variantsLua(new Map([[123, 792]]), corpus);
  assert.match(lua, /SpokenBooksData\.variants = \{\n\t\t\[123\] = 792, -- Neeka's Report, page 3\n\t\}/);
});

test("the objects read are text objects by Data0 and page-showing goobers by Data7, spawned only", () => {
  assert.match(OBJECTS_SQL, /IF\(t\.type = 9, t\.Data0, t\.Data7\) AS page/);
  assert.match(OBJECTS_SQL, /WHERE \(\(t\.type = 9 AND t\.Data0 > 0\) OR \(t\.type = 10 AND t\.Data7 > 0\)\)/);
  assert.match(OBJECTS_SQL, /EXISTS \(SELECT 1 FROM gameobject g WHERE g\.id = t\.entry\)/);
});
