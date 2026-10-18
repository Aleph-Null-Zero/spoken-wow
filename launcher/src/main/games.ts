// Finds World of Warcraft installs: the registry, Battle.net's product list, the usual folders,
// and folders the player added by hand. One GameInstall per flavor folder.
import { execFile } from 'node:child_process'
import { createHash } from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import type { Flavor, GameInstall } from '../shared/types'
import { canWriteQuick } from './guard'
import { loadState, log, updateState } from './state'

// ---------------------------------------------------------------- tables

/** Flavor folder name (lower case) -> flavor, in the order installs are listed. */
const FLAVOR_FOLDERS: [string, Flavor][] = [
  ['_retail_', 'retail'],
  ['_classic_', 'classic'],
  ['_classic_era_', 'classic_era'],
  ['_anniversary_', 'anniversary'],
  ['_classic_ptr_', 'classic_ptr'],
  ['_classic_beta_', 'classic_beta'],
  ['_xptr_', 'xptr'],
  ['_ptr_', 'ptr'],
  ['_beta_', 'beta']
]

export function flavorOfFolder(name: string): Flavor | null {
  const lower = name.toLowerCase()
  return FLAVOR_FOLDERS.find(([n]) => n === lower)?.[1] ?? null
}

/** The product code Blizzard uses for each flavor, for when no `.flavor.info` says. */
const DEFAULT_PRODUCT: Record<Flavor, string> = {
  retail: 'wow',
  classic: 'wow_classic',
  classic_era: 'wow_classic_era',
  anniversary: 'wow_anniversary',
  classic_ptr: 'wow_classic_ptr',
  classic_beta: 'wow_classic_beta',
  xptr: 'wowxptr',
  ptr: 'wowt',
  beta: 'wow_beta',
  unknown: ''
}

const LABELS: Record<string, string> = {
  wow_classic_beta: 'WoW: Forever',
  wow_classic_era: 'WoW: Classic Era',
  wow_anniversary: 'WoW: Anniversary',
  wow_classic: 'WoW: Classic',
  wow: 'WoW: Retail',
  wow_classic_ptr: 'WoW: Classic PTR',
  wow_classic_era_ptr: 'WoW: Classic PTR',
  wow_ptr: 'WoW: Retail PTR',
  wowt: 'WoW: Retail PTR',
  wowxptr: 'WoW: Retail PTR',
  wow_beta: 'WoW: Beta'
}

export function labelFor(product: string): string {
  return LABELS[product.toLowerCase()] ?? 'WoW'
}

/** First 12 hex digits of sha1 of the lower-cased root. */
export function gameIdFor(root: string): string {
  return createHash('sha1').update(root.toLowerCase()).digest('hex').slice(0, 12)
}

// ---------------------------------------------------------------- Blizzard's files

/** `.build.info`: pipe-separated, header names look like `Branch!STRING:0`. One object per row. */
export function parseBuildInfo(text: string): Record<string, string>[] {
  const lines = text
    .replace(/^\uFEFF/, '')
    .split(/\r?\n/)
    .filter((l) => l.trim() !== '')
  const head = lines[0]
  if (!head) return []
  const names = head.split('|').map((h) => h.split('!')[0]!.trim())
  const rows: Record<string, string>[] = []
  for (const line of lines.slice(1)) {
    const cells = line.split('|')
    const row: Record<string, string> = {}
    names.forEach((n, i) => {
      row[n] = (cells[i] ?? '').trim()
    })
    rows.push(row)
  }
  return rows
}

/** `.flavor.info`: a header line, then the product code (`wow_classic_beta`). */
export function parseFlavorInfo(text: string): string | undefined {
  const lines = text
    .replace(/^\uFEFF/, '')
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l !== '')
  const value = lines.length >= 2 ? lines[1] : lines[0] && !lines[0].includes('!') ? lines[0] : undefined
  return value && /^[A-Za-z0-9_]+$/.test(value) ? value : undefined
}

async function readText(file: string): Promise<string | null> {
  try {
    return await fs.promises.readFile(file, 'utf8')
  } catch {
    return null
  }
}

async function isDir(p: string): Promise<boolean> {
  try {
    return (await fs.promises.stat(p)).isDirectory()
  } catch {
    return false
  }
}

/** The real-cased names inside a folder, or null. */
async function names(p: string): Promise<string[] | null> {
  try {
    return await fs.promises.readdir(p)
  } catch {
    return null
  }
}

// ---------------------------------------------------------------- one flavor folder

/** A GameInstall for a flavor folder, or null when it holds no Interface or WTF folder and no Wow*.exe. */
export async function describeFlavorFolder(flavorPath: string, source: 'auto' | 'manual'): Promise<GameInstall | null> {
  const root = path.resolve(flavorPath)
  const entries = await names(root)
  if (!entries) return null
  const holdsGame = entries.some((n) => /^(interface|wtf)$/i.test(n) || /^wow.*\.exe$/i.test(n))
  if (!holdsGame) return null

  const flavorFolder = path.basename(root)
  const flavor = flavorOfFolder(flavorFolder) ?? 'unknown'

  const fromFlavorFile = parseFlavorInfo((await readText(path.join(root, '.flavor.info'))) ?? '')
  const product = fromFlavorFile ?? DEFAULT_PRODUCT[flavor]

  let gameVersion: string | undefined
  const buildText =
    (await readText(path.join(path.dirname(root), '.build.info'))) ?? (await readText(path.join(root, '.build.info')))
  if (buildText && product) {
    const row = parseBuildInfo(buildText).find((r) => r.Product?.toLowerCase() === product.toLowerCase())
    if (row?.Version) gameVersion = row.Version
  }

  const addOnsPath = path.join(root, 'Interface', 'AddOns')
  return {
    id: gameIdFor(root),
    root,
    addOnsPath,
    flavorFolder,
    flavor,
    product,
    label: labelFor(product),
    ...(gameVersion ? { gameVersion } : {}),
    source,
    writable: await canWriteQuick(addOnsPath)
  }
}

export const NOT_WOW_MESSAGE =
  'This does not look like a World of Warcraft folder. Choose the game folder (the one that holds _retail_ or _classic_), a game version folder such as _retail_, or its Interface\\AddOns folder.'

/**
 * Turns a folder the player (or the registry) named into flavor folders: a game folder gives
 * every flavor it holds, a flavor folder or an AddOns folder gives that one.
 */
export async function resolveGamePath(input: string, source: 'auto' | 'manual'): Promise<{ games: GameInstall[]; error?: string }> {
  const cleaned = typeof input === 'string' ? input.trim().replace(/^"(.*)"$/, '$1') : ''
  if (cleaned === '') return { games: [], error: 'Choose a folder first.' }
  const abs = path.resolve(cleaned)
  if (!(await isDir(abs))) return { games: [], error: 'That folder does not exist.' }

  const base = path.basename(abs).toLowerCase()
  const parent = path.dirname(abs)
  let candidates: string[] = []

  if (base === 'addons' && path.basename(parent).toLowerCase() === 'interface') {
    candidates = [path.dirname(parent)]
  } else if (base === 'interface') {
    candidates = [parent]
  } else if (flavorOfFolder(base)) {
    candidates = [abs]
  } else {
    const entries = (await names(abs)) ?? []
    for (const [folder] of FLAVOR_FOLDERS) {
      const real = entries.find((n) => n.toLowerCase() === folder)
      if (real) candidates.push(path.join(abs, real))
    }
    if (candidates.length === 0 && entries.some((n) => n.toLowerCase() === 'interface')) candidates = [abs]
  }

  const games: GameInstall[] = []
  for (const c of candidates) {
    const g = await describeFlavorFolder(c, source)
    if (g && !games.some((x) => x.id === g.id)) games.push(g)
  }
  return games.length > 0 ? { games } : { games: [], error: NOT_WOW_MESSAGE }
}

// ---------------------------------------------------------------- where to look

function run(file: string, args: string[], timeout = 6000): Promise<string | null> {
  return new Promise((resolve) => {
    execFile(file, args, { timeout, windowsHide: true, maxBuffer: 4 * 1024 * 1024 }, (err, stdout) => {
      resolve(err ? null : String(stdout))
    })
  })
}

/** Paths from `reg query ... /v InstallPath` output. */
export function parseRegQuery(output: string): string[] {
  const out: string[] = []
  for (const line of output.split(/\r?\n/)) {
    const m = /^\s*InstallPath\s+REG_(?:EXPAND_)?SZ\s+(.+?)\s*$/i.exec(line)
    if (m) out.push(m[1]!)
  }
  return out
}

/** Install paths in Battle.net's `product.db` (protobuf, but the paths are plain text). */
export function parseProductDb(data: Buffer): string[] {
  const text = data.toString('latin1')
  const found = new Set<string>()
  const re = /[A-Za-z]:[\\/][\x20-\x7e]{0,240}?World of Warcraft/g
  let m: RegExpExecArray | null
  while ((m = re.exec(text))) found.add(m[0])
  return [...found]
}

async function registryPaths(): Promise<string[]> {
  if (process.platform !== 'win32') return []
  const keys = [
    'HKLM\\SOFTWARE\\WOW6432Node\\Blizzard Entertainment\\World of Warcraft',
    'HKLM\\SOFTWARE\\Blizzard Entertainment\\World of Warcraft'
  ]
  const out: string[] = []
  for (const key of keys) {
    const text = await run('reg', ['query', key, '/s', '/v', 'InstallPath'])
    if (text) out.push(...parseRegQuery(text))
  }
  return out
}

async function battleNetPaths(): Promise<string[]> {
  const base = process.env.ProgramData
  if (!base) return []
  const file = path.join(base, 'Battle.net', 'Agent', 'product.db')
  try {
    const st = await fs.promises.stat(file)
    if (st.size > 8 * 1024 * 1024) return []
    return parseProductDb(await fs.promises.readFile(file))
  } catch {
    return []
  }
}

async function fixedDrives(): Promise<string[]> {
  if (process.platform !== 'win32') return []
  const text = await run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    "[IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' } | ForEach-Object { $_.Name }"
  ])
  const drives = (text ?? '')
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => /^[A-Za-z]:\\?$/.test(l))
  if (drives.length > 0) return drives.map((d) => (d.endsWith('\\') ? d : `${d}\\`))
  // PowerShell failed: probe the letters.
  const probed: string[] = []
  for (let c = 'C'.charCodeAt(0); c <= 'Z'.charCodeAt(0); c++) {
    const d = `${String.fromCharCode(c)}:\\`
    if (fs.existsSync(d)) probed.push(d)
  }
  return probed
}

/** Every folder worth looking in: registry, Battle.net, default roots, each fixed drive. */
export async function findCandidatePaths(): Promise<string[]> {
  const out: string[] = []
  out.push(...(await registryPaths()))
  out.push(...(await battleNetPaths()))
  if (process.platform === 'win32') {
    out.push('C:\\Program Files (x86)\\World of Warcraft', 'C:\\Program Files\\World of Warcraft')
    for (const d of await fixedDrives()) {
      out.push(
        path.join(d, 'World of Warcraft'),
        path.join(d, 'Games', 'World of Warcraft'),
        path.join(d, 'Program Files (x86)', 'World of Warcraft')
      )
    }
  }
  const seen = new Set<string>()
  return out.filter((p) => {
    const k = path.resolve(p).toLowerCase()
    if (seen.has(k)) return false
    seen.add(k)
    return true
  })
}

// ---------------------------------------------------------------- the list

export interface ScanOptions {
  /** Used instead of the registry and default-folder search (tests). */
  autoPaths?: string[]
}

/** Auto-found installs (minus the ones the player removed), then the manual ones. */
export async function scanGames(dataPath: string, options: ScanOptions = {}): Promise<GameInstall[]> {
  const state = loadState(dataPath)
  const hidden = new Set(state.hiddenGames)
  const found = new Map<string, GameInstall>()
  const candidates = options.autoPaths ?? (await findCandidatePaths())
  for (const p of candidates) {
    const { games } = await resolveGamePath(p, 'auto')
    for (const g of games) if (!hidden.has(g.id) && !found.has(g.id)) found.set(g.id, g)
  }
  for (const p of state.manualGames) {
    const { games } = await resolveGamePath(p, 'manual')
    for (const g of games) if (!found.has(g.id)) found.set(g.id, g)
  }
  const list = [...found.values()]
  log(`Scan found ${list.length} game install${list.length === 1 ? '' : 's'}.`)
  return list
}

/** Adds a game folder, a flavor folder or an AddOns folder; remembers each flavor folder it resolves to. */
export async function addGame(dataPath: string, input: string): Promise<{ games: GameInstall[]; error?: string }> {
  const res = await resolveGamePath(input, 'manual')
  if (res.error || res.games.length === 0) return res
  updateState(dataPath, (s) => {
    for (const g of res.games) {
      if (!s.manualGames.some((m) => m.toLowerCase() === g.root.toLowerCase())) s.manualGames.push(g.root)
      s.hiddenGames = s.hiddenGames.filter((id) => id !== g.id)
    }
  })
  return res
}

/** Takes an install off the list: a manual one is forgotten, an auto-found one is hidden. */
export function removeGame(dataPath: string, game: GameInstall): void {
  updateState(dataPath, (s) => {
    s.manualGames = s.manualGames.filter((m) => m.toLowerCase() !== game.root.toLowerCase())
    if (game.source === 'auto' && !s.hiddenGames.includes(game.id)) s.hiddenGames.push(game.id)
  })
}
