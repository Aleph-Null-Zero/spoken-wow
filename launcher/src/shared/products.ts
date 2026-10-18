// What the launcher can install, as a table. The names follow scripts/lib/packs.mjs in the repo:
// a release tag is `<product id>/v<version>`, English's folders are the plain names and a
// language's are those plus `_<lang>`. Which of these have a release is the catalog's business.
import type { Product, QuestsPack, Section } from './types'

export const BASE_LANGUAGE = 'enUS'

/** Languages in the order the Voice Packs page lists them, named in their own language. */
export const LANGUAGES: { code: string; name: string }[] = [
  { code: 'enUS', name: 'English' },
  { code: 'deDE', name: 'Deutsch' },
  { code: 'esES', name: 'Español (España)' },
  { code: 'esMX', name: 'Español (Latinoamérica)' },
  { code: 'frFR', name: 'Français' },
  { code: 'itIT', name: 'Italiano' },
  { code: 'ptBR', name: 'Português (Brasil)' },
  { code: 'ruRU', name: 'Русский' },
  { code: 'koKR', name: '한국어' },
  { code: 'zhCN', name: '简体中文' },
  { code: 'zhTW', name: '繁體中文' }
]

export function languageName(code: string): string {
  return LANGUAGES.find((l) => l.code === code)?.name ?? code
}

const SIDES: Record<Exclude<QuestsPack, 'all'>, string> = {
  alliance: 'Alliance',
  horde: 'Horde',
  shared: 'Shared',
  gossip: 'Gossip'
}

const SECTION_TITLE: Record<Section, string> = {
  quests: 'Quests',
  zones: 'Places',
  books: 'Readables'
}

const SECTION_BLURB: Record<Section, string> = {
  quests: 'Every quest, spoken as you read it, and the gossip of the people who give them.',
  zones: 'The story of each zone, dungeon and place, told as you arrive.',
  books: 'Books, letters and notes read aloud when you open them.'
}

const SIDE_BLURB: Record<QuestsPack, string> = {
  all: 'Everything in one download: Alliance, Horde, Shared and Gossip.',
  alliance: 'Quests only the Alliance sees.',
  horde: 'Quests only the Horde sees.',
  shared: 'Quests both sides share.',
  gossip: 'What the people of the world say when you talk to them.'
}

function zip(base: string): string {
  return `^${base}-\\d.*\\.zip$`
}

function voices(section: Section, lang: string, pack: QuestsPack): Product {
  const english = lang === BASE_LANGUAGE
  let id: string
  let folder: string
  let base: string
  if (section === 'quests') {
    if (english) {
      id = pack === 'all' ? 'quests-audio' : `quests-audio-${pack}`
      folder = pack === 'all' ? '' : `SpokenQuestsAudio${SIDES[pack as Exclude<QuestsPack, 'all'>]}`
      base = pack === 'all' ? 'SpokenQuestsAudioAll' : folder
    } else {
      id = `quests-audio-${lang}`
      folder = `SpokenQuestsAudio_${lang}`
      base = folder
    }
  } else {
    const name = section === 'zones' ? 'SpokenZonesAudio' : 'SpokenBooksAudio'
    id = `${section}-audio${english ? '' : `-${lang}`}`
    folder = english ? name : `${name}_${lang}`
    base = folder
  }
  // English's "all" is a bundle holding the four split packs' folders, as the store installs them.
  const folders =
    section === 'quests' && english && pack === 'all'
      ? Object.values(SIDES).map((s) => `SpokenQuestsAudio${s}`)
      : [folder]
  const title = `${SECTION_TITLE[section]} voices`
  return {
    id,
    kind: 'voices',
    title,
    description: section === 'quests' && english ? SIDE_BLURB[pack] : SECTION_BLURB[section],
    section,
    lang,
    pack: section === 'quests' ? pack : undefined,
    tagPrefix: id,
    folders,
    assetPattern: zip(base)
  }
}

const SPOKEN: Product = {
  id: 'spoken',
  kind: 'addon',
  title: 'Spoken',
  description: 'Reads the game aloud: quests, gossip, places and readables. One queue, one narrator, one settings window.',
  tagPrefix: 'spoken',
  folders: null,
  assetPattern: zip('Spoken')
}

function build(): Product[] {
  const out: Product[] = [SPOKEN]
  for (const { code } of LANGUAGES) {
    if (code === BASE_LANGUAGE) {
      for (const pack of ['all', 'alliance', 'horde', 'shared', 'gossip'] as QuestsPack[]) out.push(voices('quests', code, pack))
    } else {
      out.push(voices('quests', code, 'all'))
    }
    // Italian has quests voices only, so far: its other packs have no release and do not show.
    out.push(voices('zones', code, 'all'), voices('books', code, 'all'))
  }
  return out
}

/** Every product the launcher knows. A pack with no release yet is simply not shown. */
export const PRODUCTS: Product[] = build()

export function productById(id: string): Product | undefined {
  return PRODUCTS.find((p) => p.id === id)
}

/** The folders of every voice pack and Spoken's known ones: the only names the installer may touch. */
export const SPOKEN_FOLDERS = [
  'Spoken',
  'Spoken_Quests',
  'Spoken_Conversations',
  'Spoken_Places',
  'Spoken_Readables',
  'Spoken_NPCs',
  'SpokenContributions'
]

/** `spoken/v3.5.0` -> `3.5.0`; null when the tag is not `<prefix>/v<version>`. */
export function versionOfTag(tag: string, prefix: string): string | null {
  const lead = `${prefix}/v`
  return tag.startsWith(lead) ? tag.slice(lead.length) : null
}
