import fs from 'node:fs'
import path from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { productById } from '../src/shared/products'
import type { GameInstall } from '../src/shared/types'
import { cleanLeftovers } from '../src/main/cleanup'
import { PlainError } from '../src/main/errors'
import { backupDirFor, type JobContext } from '../src/main/install'
import { parseIndex, parseManifest, type ChannelManifest } from '../src/main/packs-remote'
import { loadPackState, savePackState } from '../src/main/packs-state'
import { blobDir, syncPacks } from '../src/main/packs-sync'
import { getRecord, loadState } from '../src/main/state'
import { channelFixture, channelKeys, serveChannel, type PackSpec } from './channel-helpers'
import { collect, makeGame, sha256, tmpDir, write, type TestServer } from './helpers'

let server: TestServer | null = null
afterEach(async () => {
  await server?.close()
  server = null
})

const keys = channelKeys()
const PACK = 'SpokenZonesAudio_deDE'
const product = productById('zones-audio-deDE')!
const v1: PackSpec = { packId: PACK, rev: '20261018T000000Z', files: { [`${PACK}.toc`]: 'toc', 'Sounds/1.ogg': 'one', 'Sounds/2.ogg': 'two' } }
const v2: PackSpec = { packId: PACK, rev: '20261019T000000Z', files: { [`${PACK}.toc`]: 'toc', 'Sounds/1.ogg': 'ONE!', 'Sounds/3.ogg': 'three' } }

async function channel(spec: PackSpec, hook?: Parameters<typeof serveChannel>[1]): Promise<{ manifest: ChannelManifest; base: string; server: TestServer }> {
  const fx = channelFixture(keys, [spec])
  const s = await serveChannel(fx, hook)
  server = s
  const index = parseIndex(JSON.stringify(fx.index))
  return { manifest: parseManifest(fx.manifestSigned[PACK]!, PACK, index.packs[PACK]!), base: s.base, server: s }
}

function ctx(data: string, extra: Partial<JobContext> = {}): JobContext {
  return { jobId: 'job1', dataPath: data, downloadsPath: tmpDir(), keepDownloads: false, emit: collect().emit, backoffMs: 1, attempts: 2, isRunning: async () => false, ...extra }
}

function folderFiles(game: GameInstall): Record<string, string> {
  const root = path.join(game.addOnsPath, PACK)
  const out: Record<string, string> = {}
  const walk = (rel: string): void => {
    for (const e of fs.readdirSync(path.join(root, rel), { withFileTypes: true })) {
      const p = rel ? `${rel}/${e.name}` : e.name
      if (e.isDirectory()) walk(p)
      else out[p] = fs.readFileSync(path.join(root, p), 'utf8')
    }
  }
  walk('')
  return out
}

const blobRequests = (s: TestServer) => s.requests.filter((r) => r.url.startsWith('/blobs/')).length

describe('syncPacks', () => {
  it('installs a pack from nothing and records it', async () => {
    const game = await makeGame(tmpDir())
    const data = tmpDir()
    const { manifest, base } = await channel(v1)
    await syncPacks(game, { product, manifests: [manifest], baseUrl: base }, ctx(data))
    expect(folderFiles(game)).toEqual(v1.files)
    expect(loadPackState(game, PACK)?.rev).toBe(v1.rev)
    expect(getRecord(loadState(data), game.id, product.id)?.tag).toBe(`channel/${v1.rev}`)
    expect(fs.readdirSync(blobDir(game))).toEqual([])
  })

  it('updates by fetching only the changed and new files, and drops the removed one', async () => {
    const game = await makeGame(tmpDir())
    const data = tmpDir()
    const first = await channel(v1)
    await syncPacks(game, { product, manifests: [first.manifest], baseUrl: first.base }, ctx(data))
    await first.server.close()
    const second = await channel(v2)
    await syncPacks(game, { product, manifests: [second.manifest], baseUrl: second.base }, ctx(data, { jobId: 'job2' }))
    expect(folderFiles(game)).toEqual(v2.files)
    expect(blobRequests(second.server)).toBe(2)
    expect(fs.existsSync(path.join(backupDirFor(game, product.id), PACK, 'Sounds', '2.ogg'))).toBe(true)
  })

  it('adopts a folder another client installed, downloading nothing it already has', async () => {
    const game = await makeGame(tmpDir())
    for (const [p, text] of Object.entries(v1.files)) write(path.join(game.addOnsPath, PACK, ...p.split('/')), text)
    const { manifest, base, server: s } = await channel(v1)
    await syncPacks(game, { product, manifests: [manifest], baseUrl: base }, ctx(tmpDir()))
    expect(blobRequests(s)).toBe(0)
    expect(loadPackState(game, PACK)?.rev).toBe(v1.rev)
  })

  it('a repair finds a file damaged behind the state', async () => {
    const game = await makeGame(tmpDir())
    const data = tmpDir()
    const { manifest, base, server: s } = await channel(v1)
    await syncPacks(game, { product, manifests: [manifest], baseUrl: base }, ctx(data))
    const clip = path.join(game.addOnsPath, PACK, 'Sounds', '1.ogg')
    // A whole-second mtime survives utimes exactly (a file system's sub-millisecond part would not), so the damage can keep it.
    fs.utimesSync(clip, 1_790_000_000, 1_790_000_000)
    const recorded = loadPackState(game, PACK)!
    recorded.files['Sounds/1.ogg']!.mtimeMs = fs.statSync(clip).mtimeMs
    savePackState(game, recorded)
    fs.writeFileSync(clip, 'ONE')
    fs.utimesSync(clip, 1_790_000_000, 1_790_000_000)
    await syncPacks(game, { product, manifests: [manifest], baseUrl: base }, ctx(data, { jobId: 'job2' }))
    expect(fs.readFileSync(clip, 'utf8')).toBe('ONE')
    await syncPacks(game, { product, manifests: [manifest], baseUrl: base, repair: true }, ctx(data, { jobId: 'job3' }))
    expect(fs.readFileSync(clip, 'utf8')).toBe('one')
    expect(blobRequests(s)).toBe(3 + 1)
  })

  it('a blob that keeps arriving wrong fails the job and leaves the install untouched', async () => {
    const game = await makeGame(tmpDir())
    const data = tmpDir()
    const first = await channel(v1)
    await syncPacks(game, { product, manifests: [first.manifest], baseUrl: first.base }, ctx(data))
    await first.server.close()
    const bad = sha256(Buffer.from('three'))
    const second = await channel(v2, (req, res) => {
      if (req.url !== `/blobs/${bad}`) return false
      res.writeHead(200, { 'Content-Length': 5 })
      res.end('THREE')
      return true
    })
    await expect(syncPacks(game, { product, manifests: [second.manifest], baseUrl: second.base }, ctx(data, { jobId: 'job2' }))).rejects.toThrow(PlainError)
    expect(folderFiles(game)).toEqual(v1.files)
    expect(second.server.requests.filter((r) => r.url === `/blobs/${bad}`).length).toBe(2)
  })

  it('reuses a blob already downloaded by an earlier, interrupted job', async () => {
    const game = await makeGame(tmpDir())
    const { manifest, base, server: s } = await channel(v1)
    write(path.join(blobDir(game), sha256(Buffer.from('one'))), 'one')
    await syncPacks(game, { product, manifests: [manifest], baseUrl: base }, ctx(tmpDir()))
    expect(blobRequests(s)).toBe(2)
  })

  it('downloads a clip used at two paths once and places it at both', async () => {
    const game = await makeGame(tmpDir())
    const spec: PackSpec = { ...v1, files: { [`${PACK}.toc`]: 'toc', 'Sounds/a.ogg': 'same', 'Sounds/b.ogg': 'same' } }
    const { manifest, base, server: s } = await channel(spec)
    await syncPacks(game, { product, manifests: [manifest], baseUrl: base }, ctx(tmpDir()))
    expect(folderFiles(game)).toEqual(spec.files)
    expect(blobRequests(s)).toBe(2)
  })

  it('copies when the drive refuses hard links', async () => {
    const game = await makeGame(tmpDir())
    const { manifest, base } = await channel(v1)
    const link = async (): Promise<void> => {
      throw Object.assign(new Error('not supported'), { code: 'EPERM' })
    }
    await syncPacks(game, { product, manifests: [manifest], baseUrl: base, link }, ctx(tmpDir()))
    expect(folderFiles(game)).toEqual(v1.files)
  })

  it('a folder held open by the game fails with nothing changed', async () => {
    const game = await makeGame(tmpDir())
    const data = tmpDir()
    const first = await channel(v1)
    await syncPacks(game, { product, manifests: [first.manifest], baseUrl: first.base }, ctx(data))
    await first.server.close()
    const second = await channel(v2)
    const rename = async (): Promise<void> => {
      throw Object.assign(new Error('busy'), { code: 'EBUSY' })
    }
    await expect(syncPacks(game, { product, manifests: [second.manifest], baseUrl: second.base }, ctx(data, { jobId: 'job2', ops: { rename } }))).rejects.toThrow(/Nothing was changed/)
    expect(folderFiles(game)).toEqual(v1.files)
  })
})

describe('cleanLeftovers', () => {
  it('removes downloaded blobs nobody used for a week', async () => {
    const game = await makeGame(tmpDir())
    const old = path.join(blobDir(game), 'a'.repeat(64))
    const fresh = path.join(blobDir(game), 'b'.repeat(64))
    write(old, 'x')
    write(fresh, 'y')
    const weekAgo = new Date(Date.now() - 8 * 24 * 3600 * 1000)
    fs.utimesSync(old, weekAgo, weekAgo)
    await cleanLeftovers([game], tmpDir())
    expect(fs.existsSync(old)).toBe(false)
    expect(fs.existsSync(fresh)).toBe(true)
  })
})
