// The checks that run before the installer changes anything: linked folders, allowed names,
// safe zip paths, free space, write access, a running game.
import { execFile } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import type { Product } from '../shared/types'
import { SPOKEN_FOLDERS } from '../shared/products'
import { PlainError, formatBytes } from './errors'

// ---------------------------------------------------------------- linked folders

function samePath(a: string, b: string): boolean {
  const x = path.resolve(a)
  const y = path.resolve(b)
  return process.platform === 'win32' ? x.toLowerCase() === y.toLowerCase() : x === y
}

/**
 * True when `p` is a symlink or a Windows junction. A junction is not always reported by lstat,
 * so the real path is compared with where the path says it is (its parent's real path plus its
 * own name). A missing path is not linked.
 */
export async function isLinked(p: string): Promise<boolean> {
  let st: fs.Stats
  try {
    st = await fs.promises.lstat(p)
  } catch {
    return false
  }
  if (st.isSymbolicLink()) return true
  try {
    const real = await fs.promises.realpath(p)
    const parentReal = await fs.promises.realpath(path.dirname(p))
    return !samePath(real, path.join(parentReal, path.basename(p)))
  } catch {
    // Cannot resolve it: do not treat it as a plain folder.
    return true
  }
}

export const LINKED_MESSAGE = 'This folder is linked to a development checkout. The launcher will not change it.'

// ---------------------------------------------------------------- allowed names

/** The folder names a product may install: voice packs' own, Spoken's list. */
export function allowedFolders(product: Product): string[] {
  return product.folders ?? SPOKEN_FOLDERS
}

export type EntryCheck = { ok: true; segments: string[]; directory: boolean } | { ok: false; reason: string }

const BAD_CHARS = /[\0<>:"|?*\x01-\x1f]/

/**
 * Checks one zip entry name. Entry names use `/`. Refuses `..`, absolute paths, drive letters,
 * backslashes, NUL and other characters Windows reads specially, and any first segment that is
 * not an allowed folder name (exact case). A trailing `/` marks a directory entry.
 */
export function checkEntryPath(name: string, allowed: readonly string[]): EntryCheck {
  if (typeof name !== 'string' || name.length === 0) return { ok: false, reason: 'empty name' }
  if (name.includes('\\')) return { ok: false, reason: 'backslash' }
  if (name.includes('\0')) return { ok: false, reason: 'NUL' }
  if (name.startsWith('/')) return { ok: false, reason: 'absolute path' }
  if (/^[A-Za-z]:/.test(name)) return { ok: false, reason: 'drive letter' }
  const directory = name.endsWith('/')
  const segments = (directory ? name.slice(0, -1) : name).split('/')
  for (const s of segments) {
    if (s === '') return { ok: false, reason: 'empty segment' }
    if (s === '.' || s === '..') return { ok: false, reason: 'relative segment' }
    if (BAD_CHARS.test(s)) return { ok: false, reason: 'special character' }
    if (/[. ]$/.test(s)) return { ok: false, reason: 'trailing dot or space' }
  }
  if (!allowed.includes(segments[0]!)) return { ok: false, reason: 'folder not allowed' }
  if (!directory && segments.length < 2) return { ok: false, reason: 'file outside a folder' }
  return { ok: true, segments, directory }
}

/** True when `child` is `parent` or inside it (no `..` escape). */
export function isInside(parent: string, child: string): boolean {
  const rel = path.relative(path.resolve(parent), path.resolve(child))
  if (rel === '') return true
  return !rel.startsWith('..') && !path.isAbsolute(rel)
}

// ---------------------------------------------------------------- disk

async function nearestExisting(p: string): Promise<string> {
  let cur = path.resolve(p)
  for (;;) {
    try {
      await fs.promises.access(cur)
      return cur
    } catch {
      const up = path.dirname(cur)
      if (up === cur) return cur
      cur = up
    }
  }
}

async function freeSpace(dir: string): Promise<number> {
  const at = await nearestExisting(dir)
  const s = await fs.promises.statfs(at)
  return Number(s.bavail) * Number(s.bsize)
}

/** The volume a path lives on, so two folders on one drive can be checked together. */
export async function volumeOf(dir: string): Promise<string> {
  const at = await nearestExisting(dir)
  const st = await fs.promises.stat(at)
  return String(st.dev)
}

/** Throws in plain words when `dir`'s drive has less than `needed` bytes free. */
export async function ensureFreeSpace(dir: string, needed: number, what = 'this'): Promise<void> {
  let free: number
  try {
    free = await freeSpace(dir)
  } catch {
    return // cannot tell: let the write fail if it must
  }
  if (free < needed) {
    const drive = path.parse(path.resolve(dir)).root.replace(/[\\/]+$/, '') || dir
    throw new PlainError(
      `Not enough free space on ${drive} for ${what}: about ${formatBytes(needed)} needed, ${formatBytes(free)} free.`
    )
  }
}

/** Cheap write check for scans: the nearest existing parent is a folder and not marked read-only. Creates nothing. */
export async function canWriteQuick(dir: string): Promise<boolean> {
  const at = await nearestExisting(dir)
  try {
    if (!(await fs.promises.stat(at)).isDirectory()) return false
    await fs.promises.access(at, fs.constants.W_OK)
    return true
  } catch {
    return false
  }
}

/** Whether a file can really be created in `dir` (or its nearest existing parent). */
export async function canWrite(dir: string): Promise<boolean> {
  const at = await nearestExisting(dir)
  try {
    if (!(await fs.promises.stat(at)).isDirectory()) return false
  } catch {
    return false
  }
  const probe = path.join(at, `.spoken-launcher-write-test-${process.pid}-${Date.now()}`)
  try {
    await fs.promises.writeFile(probe, '')
    await fs.promises.rm(probe, { force: true })
    return true
  } catch {
    return false
  }
}

/**
 * The reason a downloads folder cannot be used, in plain words, or null when it can. It must be a
 * full local path that exists or can be created, and not inside a game's AddOns or WTF folder.
 */
export function checkDownloadsPath(value: string, games: readonly { root: string; addOnsPath: string }[]): string | null {
  if (value === '') return null
  if (value.includes('\0') || value.length > 240) return 'That is not a usable folder name for downloads.'
  if (/^[\\/]{2}/.test(value)) return 'Network folders (\\\\server\\share) cannot be used for downloads. Choose a folder on a local drive.'
  if (!path.isAbsolute(value)) return 'Choose a full folder path for downloads, such as D:\\Downloads.'
  const abs = path.resolve(value)
  for (const g of games) {
    if (isInside(g.addOnsPath, abs) || isInside(path.join(g.root, 'WTF'), abs)) {
      return "Downloads cannot be kept inside a game's AddOns or WTF folder."
    }
  }
  let at = abs
  for (;;) {
    try {
      const st = fs.statSync(at)
      if (!st.isDirectory()) return at === abs ? 'That path is a file, not a folder.' : 'That folder cannot be created: a file is in the way.'
      fs.accessSync(at, fs.constants.W_OK)
      return null
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'ENOENT') return 'The launcher cannot write to that folder.'
      const up = path.dirname(at)
      if (up === at) return 'That drive does not exist.'
      at = up
    }
  }
}

// ---------------------------------------------------------------- running game

/** Process names from `tasklist /FO CSV /NH` output. */
export function parseTasklist(output: string): string[] {
  const names: string[] = []
  for (const line of output.split(/\r?\n/)) {
    const m = /^"([^"]+)"/.exec(line.trim())
    if (m) names.push(m[1]!)
  }
  return names
}

/** `Wow.exe`, `WowClassic.exe`, `WowB.exe`, `WowClassicT.exe`, ...: starts with Wow, ends .exe. */
export function isWowProcess(name: string): boolean {
  return /^wow.*\.exe$/i.test(name)
}

/** Whether any World of Warcraft client is running. The flavor is accepted for the caller's sake; the exe names differ too much to tell which client it is. */
export function isGameRunning(_flavor?: string): Promise<boolean> {
  if (process.platform !== 'win32') return Promise.resolve(false)
  return new Promise((resolve) => {
    execFile('tasklist', ['/FO', 'CSV', '/NH'], { timeout: 8000, windowsHide: true, maxBuffer: 8 * 1024 * 1024 }, (err, stdout) => {
      if (err) return resolve(false)
      resolve(parseTasklist(String(stdout)).some(isWowProcess))
    })
  })
}
