import assert from "node:assert/strict";
import { test } from "node:test";

import { isTemplateCopy, typeOf } from "./places.mjs";

test("a difficulty or test copy of a creature is not a source", () => {
  assert.equal(isTemplateCopy("Alliance Sentinel (1)"), true);
  assert.equal(isTemplateCopy("Frostwolf Bowman (3)"), true);
  assert.equal(isTemplateCopy("Commander Dardosh <old> (1)"), true);
  assert.equal(isTemplateCopy("Lieutenant Murp <old>"), true);
});

test("a creature's own template is a source", () => {
  assert.equal(isTemplateCopy("Alliance Sentinel"), false);
  assert.equal(isTemplateCopy("Defias Messenger"), false);
  assert.equal(isTemplateCopy(undefined), false);
});

const SCROLL = "interface/icons/inv_scroll_03.blp";
const TABLET = "interface/icons/inv_misc_stonetablet_05.blp";
const NOTE = "interface/icons/inv_misc_note_01.blp";
const BOOK = "interface/icons/inv_misc_book_09.blp";

test("a carried readable whose title names its form is that form, whatever its icon", () => {
  assert.equal(typeOf({ title: "Maybell's Love Letter", icons: [SCROLL] }), "letter");
  assert.equal(typeOf({ title: "Crystallized Note", icons: [TABLET] }), "note");
  assert.equal(typeOf({ title: "Kodo Skin Scroll", icons: [NOTE] }), "scroll");
  assert.equal(typeOf({ title: "Weatherworn Parchment", icons: [SCROLL] }), "note");
});

test("a plural is not a form: Jordan's Weapon Notes is a letter by its icon", () => {
  assert.equal(typeOf({ title: "Jordan's Weapon Notes", icons: ["interface/icons/inv_letter_02.blp"] }), "letter");
});

test("a carried readable whose title names no form goes by its icon, then its title", () => {
  assert.equal(typeOf({ title: "Lorgalis Manuscript", icons: [NOTE] }), "note");
  assert.equal(typeOf({ title: "The Story of Morgan Ladimore", icons: [BOOK] }), "book");
  assert.equal(typeOf({ title: "Green Hills of Stranglethorn - Page 1", icons: [] }), "note");
  assert.equal(typeOf({ title: "William's Shipment", icons: [] }), "other");
});

test("a readable in the world goes by its name and its pages", () => {
  assert.equal(typeOf({ title: "Eliza's Tombstone", world: true }), "grave");
  assert.equal(typeOf({ title: "Pteradon Skeleton", world: true }), "exhibit");
  assert.equal(typeOf({ title: "Aftermath of the Second War", world: true, pages: 6 }), "book");
  assert.equal(typeOf({ title: "Kurdran Wildhammer", world: true }), "plaque");
});
