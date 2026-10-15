/**
 * The sound packs as the landing page offers them: one per section per language, with where
 * each can be downloaded.
 *
 * THE SAME LIST AS publishers/ (read by scripts/lib/packs.mjs), restated here as a literal
 * because the standalone server ships without that directory. packs.test.ts fails if the two
 * drift, the way lang.test.ts guards the language list.
 *
 * English quests are listed once, as the All pack: on GitHub that is the bundle holding the four
 * split packs' folders, and on CurseForge, where the All project is a meta addon, the page links
 * the four split packs themselves (`split`).
 */
import type { Lang } from "@/lib/lang";

export type Section = "quests" | "zones" | "books";

export type Pack = {
  section: Section;
  lang: Lang;
  /** The CurseForge (and, where it exists, Wago) slug, or null for a pack only on GitHub. */
  curseforge: string | null;
  /** The GitHub release tag prefix, `<release>/vX.Y.Z`. */
  release: string;
  /**
   * The packs CurseForge splits this one into, linked instead of `curseforge` itself: quests
   * only. English's All project there is a meta addon holding no audio, and a language's
   * one-folder quests pack is on GitHub alone.
   */
  split?: readonly { label: string; slug: string }[];
};

export const PACKS: readonly Pack[] = [
  {
    section: "quests",
    lang: "enUS",
    curseforge: "spoken-quests-audio-all",
    release: "quests-audio",
    split: [
      { label: "Alliance", slug: "spoken-quests-audio-alliance" },
      { label: "Horde", slug: "spoken-quests-audio-horde" },
      { label: "Shared", slug: "spoken-quests-audio-shared" },
      { label: "Gossip", slug: "spoken-quests-audio-gossip" },
    ],
  },
  {
    section: "quests",
    lang: "deDE",
    curseforge: null,
    release: "quests-audio-deDE",
    split: [
      { label: "Alliance", slug: "german-spoken-quests-alliance" },
      { label: "Horde", slug: "german-spoken-quests-horde" },
      { label: "Shared", slug: "german-spoken-quests-shared" },
      { label: "Gossip", slug: "german-spoken-quests-gossip" },
    ],
  },
  {
    section: "quests",
    lang: "esES",
    curseforge: null,
    release: "quests-audio-esES",
    split: [
      { label: "Alliance", slug: "spanish-eu-spoken-quests-alliance" },
      { label: "Horde", slug: "spanish-eu-spoken-quests-horde" },
      { label: "Shared", slug: "spanish-eu-spoken-quests-shared" },
      { label: "Gossip", slug: "spanish-eu-spoken-quests-gossip" },
    ],
  },
  {
    section: "quests",
    lang: "esMX",
    curseforge: null,
    release: "quests-audio-esMX",
    split: [
      { label: "Alliance", slug: "spanish-al-spoken-quests-alliance" },
      { label: "Horde", slug: "spanish-al-spoken-quests-horde" },
      { label: "Shared", slug: "spanish-al-spoken-quests-shared" },
      { label: "Gossip", slug: "spanish-al-spoken-quests-gossip" },
    ],
  },
  {
    section: "quests",
    lang: "frFR",
    curseforge: null,
    release: "quests-audio-frFR",
    split: [
      { label: "Alliance", slug: "french-spoken-quests-alliance" },
      { label: "Horde", slug: "french-spoken-quests-horde" },
      { label: "Shared", slug: "french-spoken-quests-shared" },
      { label: "Gossip", slug: "french-spoken-quests-gossip" },
    ],
  },
  {
    section: "quests",
    lang: "itIT",
    curseforge: null,
    release: "quests-audio-itIT",
    split: [
      { label: "Quests", slug: "italian-spoken-quests" },
      { label: "Gossip", slug: "italian-spoken-quests-gossip" },
    ],
  },
  {
    section: "quests",
    lang: "ptBR",
    curseforge: null,
    release: "quests-audio-ptBR",
    split: [
      { label: "Quests", slug: "portuguese-spoken-quests" },
      { label: "Gossip", slug: "portuguese-spoken-quests-gossip" },
    ],
  },
  {
    section: "quests",
    lang: "ruRU",
    curseforge: null,
    release: "quests-audio-ruRU",
    split: [
      { label: "Quests", slug: "russian-spoken-quests" },
      { label: "Gossip", slug: "russian-spoken-quests-gossip" },
    ],
  },
  {
    section: "quests",
    lang: "koKR",
    curseforge: null,
    release: "quests-audio-koKR",
    split: [
      { label: "Quests", slug: "korean-spoken-quests" },
      { label: "Gossip", slug: "korean-spoken-quests-gossip" },
    ],
  },
  {
    section: "quests",
    lang: "zhCN",
    curseforge: null,
    release: "quests-audio-zhCN",
    split: [
      { label: "Quests", slug: "chinese-simplified-spoken-quests" },
      { label: "Gossip", slug: "chinese-simplified-spoken-quests-gossip" },
    ],
  },
  {
    section: "quests",
    lang: "zhTW",
    curseforge: null,
    release: "quests-audio-zhTW",
    split: [
      { label: "Quests", slug: "chinese-traditional-spoken-quests" },
      { label: "Gossip", slug: "chinese-traditional-spoken-quests-gossip" },
    ],
  },

  {
    section: "zones",
    lang: "enUS",
    curseforge: "spoken-zones-audio",
    release: "zones-audio",
  },
  {
    section: "zones",
    lang: "deDE",
    curseforge: "spoken-zones-audio-dede",
    release: "zones-audio-deDE",
  },
  {
    section: "zones",
    lang: "esES",
    curseforge: "spoken-zones-audio-eses",
    release: "zones-audio-esES",
  },
  {
    section: "zones",
    lang: "esMX",
    curseforge: "spoken-zones-audio-esmx",
    release: "zones-audio-esMX",
  },
  {
    section: "zones",
    lang: "frFR",
    curseforge: "spoken-zones-audio-frfr",
    release: "zones-audio-frFR",
  },
  {
    section: "zones",
    lang: "ptBR",
    curseforge: "spoken-zones-audio-ptbr",
    release: "zones-audio-ptBR",
  },
  {
    section: "zones",
    lang: "ruRU",
    curseforge: "spoken-zones-audio-ruru",
    release: "zones-audio-ruRU",
  },
  {
    section: "zones",
    lang: "koKR",
    curseforge: "spoken-zones-audio-kokr",
    release: "zones-audio-koKR",
  },
  {
    section: "zones",
    lang: "zhCN",
    curseforge: "spoken-zones-audio-zhcn",
    release: "zones-audio-zhCN",
  },
  {
    section: "zones",
    lang: "zhTW",
    curseforge: "spoken-zones-audio-zhtw",
    release: "zones-audio-zhTW",
  },

  {
    section: "books",
    lang: "enUS",
    curseforge: "spoken-books-audio",
    release: "books-audio",
  },
  {
    section: "books",
    lang: "deDE",
    curseforge: "spoken-books-audio-dede",
    release: "books-audio-deDE",
  },
  {
    section: "books",
    lang: "esES",
    curseforge: "spoken-books-audio-eses",
    release: "books-audio-esES",
  },
  {
    section: "books",
    lang: "esMX",
    curseforge: "spoken-books-audio-esmx",
    release: "books-audio-esMX",
  },
  {
    section: "books",
    lang: "frFR",
    curseforge: "spoken-books-audio-frfr",
    release: "books-audio-frFR",
  },
  {
    section: "books",
    lang: "ruRU",
    curseforge: "spoken-books-audio-ruru",
    release: "books-audio-ruRU",
  },
  {
    section: "books",
    lang: "ptBR",
    curseforge: "spoken-books-audio-ptbr",
    release: "books-audio-ptBR",
  },
  {
    section: "books",
    lang: "koKR",
    curseforge: "spoken-books-audio-kokr",
    release: "books-audio-koKR",
  },
  {
    section: "books",
    lang: "zhCN",
    curseforge: "spoken-books-audio-zhcn",
    release: "books-audio-zhCN",
  },
  {
    section: "books",
    lang: "zhTW",
    curseforge: "spoken-books-audio-zhtw",
    release: "books-audio-zhTW",
  },
];

/** The pack for a section in a language, or undefined where none has been built. */
export function packFor(section: Section, lang: Lang): Pack | undefined {
  return PACKS.find((pack) => pack.section === section && pack.lang === lang);
}
