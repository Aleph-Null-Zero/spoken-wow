// The rules places.mjs applies to what it reads, kept apart from the database so they can be
// tested.

// A creature template that copies another for a difficulty or a test, as Alterac Valley's
// "Alliance Sentinel (1)" and "Commander Dardosh <old> (1)" do. Named as a source, it showed on a
// page as "Dropped by Alliance Sentinel (1)".
export function isTemplateCopy(name) {
  return / \(\d+\)$/.test(name ?? "") || /<old>/i.test(name ?? "");
}

// A title that names its own form says what it is better than its item's icon does: the game
// gave "Maybell's Love Letter" a scroll's icon and "Crystallized Note" a tablet's.
const FORM_TYPE = [
  [/journal/i, "book"], [/diary/i, "note"], [/letter|missive|envelope/i, "letter"],
  [/\bnote\b|parchment/i, "note"], [/scroll/i, "scroll"], [/tablet/i, "tablet"],
];
// Then the icon, then the rest of the title.
const ICON_TYPE = [
  [/inv_misc_book/, "book"], [/inv_letter/, "letter"], [/inv_misc_note|leatherscrap|bandage/, "note"],
  [/inv_scroll/, "scroll"], [/stonetablet|inv_misc_rune/, "tablet"],
];
const TITLE_TYPE = [
  [/page/i, "note"], [/book|tome|manual|codex|libram|guide/i, "book"],
  [/orders|report|deed|writ|plans/i, "scroll"],
];

// What a readable is. One standing in the world by its name and how many pages it has (a
// gravestone, a museum's exhibit, a book on a shelf, else a plaque or a sign); a carried one by
// the form its title names, else its item's icon, else the rest of its title.
export function typeOf({ title, pages = 1, world = false, icons = [] }) {
  if (world) {
    if (/tombstone|headstone|here lies|in loving memory|\bgrave/i.test(title)) return "grave";
    if (/skeleton|\begg\b|talon|skull of|astrolabe|catapult|armor of|relics|reliefs/i.test(title)) return "exhibit";
    if (pages > 1 || /journal/i.test(title)) return "book";
    if (/\bnote\b/i.test(title)) return "note";
    return "plaque";
  }
  for (const [pattern, type] of FORM_TYPE) if (pattern.test(title)) return type;
  for (const icon of icons) {
    for (const [pattern, type] of ICON_TYPE) if (pattern.test(icon)) return type;
  }
  for (const [pattern, type] of TITLE_TYPE) if (pattern.test(title)) return type;
  return "other";
}
