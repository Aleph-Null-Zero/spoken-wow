// What the launcher last put in each voice pack folder of a game: the channel rev and, per file,
// its hash with the size and mtime it had then, so an unchanged file is never read again.
import fs from 'node:fs'
import path from 'node:path'
import type { GameInstall } from '../shared/types'
import { workDir } from './install'
import { readJsonFile, writeJsonAtomic } from './state'

export interface PackFileState {
  sha256: string
  size: number
  mtimeMs: number
}

export interface PackState {
  packId: string
  rev: string
  files: Record<string, PackFileState>
}

export function packStatePath(game: GameInstall, packId: string): string {
  return path.join(workDir(game), 'packs', `${packId}.json`)
}

export function loadPackState(game: GameInstall, packId: string): PackState | null {
  const raw = readJsonFile<unknown>(packStatePath(game, packId), null) as Partial<PackState> | null
  if (!raw || raw.packId !== packId || typeof raw.rev !== 'string' || typeof raw.files !== 'object' || raw.files === null) return null
  const files: Record<string, PackFileState> = {}
  for (const [p, x] of Object.entries(raw.files as Record<string, Partial<PackFileState> | null>)) {
    if (x && typeof x.sha256 === 'string' && typeof x.size === 'number' && typeof x.mtimeMs === 'number') files[p] = { sha256: x.sha256, size: x.size, mtimeMs: x.mtimeMs }
  }
  return { packId, rev: raw.rev, files }
}

export function savePackState(game: GameInstall, state: PackState): void {
  const file = packStatePath(game, state.packId)
  fs.mkdirSync(path.dirname(file), { recursive: true })
  writeJsonAtomic(file, state)
}

export function dropPackState(game: GameInstall, packId: string): void {
  fs.rmSync(packStatePath(game, packId), { force: true })
}
