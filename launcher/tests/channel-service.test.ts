import fs from 'node:fs'
import path from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { CHANNELS } from '../src/shared/api'
import type { JobProgress } from '../src/shared/types'
import { LauncherService } from '../src/main/service'
import { loadPackState } from '../src/main/packs-state'
import { channelFixture, channelKeys, serveChannel, type PackSpec } from './channel-helpers'
import { makeGame, serveBuffer, sha256, startServer, tmpDir, toc, write, yazlZip, type TestServer } from './helpers'

let server: TestServer | null = null
let extra: TestServer | null = null
afterEach(async () => {
  await server?.close()
  await extra?.close()
  server = null
  extra = null
})

const keys = channelKeys()
const PACK = 'SpokenZonesAudio_deDE'
const spec: PackSpec = { packId: PACK, rev: '20261018T000000Z', files: { [`${PACK}.toc`]: 'toc', 'Sounds/1.ogg': 'one' }, requires: '3.0.0' }

async function setup(options: { spoken?: string; requires?: string } = {}) {
  const game = await makeGame(tmpDir())
  if (options.spoken) write(path.join(game.addOnsPath, 'Spoken', 'Spoken.toc'), toc('Spoken', options.spoken))
  const s = await serveChannel(channelFixture(keys, [{ ...spec, ...(options.requires ? { requires: options.requires } : {}) }]))
  server = s
  const github = (async (url: string, init?: RequestInit) =>
    String(url).startsWith('https://api.github.com/') ? new Response('[]', { status: 200, headers: { 'content-type': 'application/json' } }) : fetch(url, init)) as unknown as typeof fetch
  const sent: { channel: string; payload: unknown }[] = []
  const svc = new LauncherService({
    dataPath: tmpDir(), appVersion: '0.1.0', send: (channel, payload) => sent.push({ channel, payload }),
    fetchImpl: github, autoPaths: [game.root], isRunning: async () => false, backoffMs: 1,
    packsBaseUrl: s.base, packsPublicKey: keys.publicKey
  })
  await svc.init()
  await svc.refreshCatalog(true)
  return { svc, game, sent }
}

function waitFor(sent: { channel: string; payload: unknown }[], jobId: string): Promise<JobProgress> {
  return new Promise((resolve, reject) => {
    const started = Date.now()
    const t = setInterval(() => {
      const last = sent.filter((s) => s.channel === CHANNELS.jobProgress && (s.payload as JobProgress).jobId === jobId).map((s) => s.payload as JobProgress).at(-1)
      if (last && ['done', 'error', 'cancelled'].includes(last.phase)) {
        clearInterval(t)
        resolve(last)
      } else if (Date.now() - started > 10000) {
        clearInterval(t)
        reject(new Error('timeout'))
      }
    }, 10)
  })
}

describe('the channel through the service', () => {
  it('offers, installs and removes a channel pack', async () => {
    const { svc, game, sent } = await setup({ spoken: '3.0.0' })
    const before = (await svc.statuses(game.id)).find((s) => s.productId === 'zones-audio-deDE')
    expect(before?.state).toBe('not-installed')
    expect(before?.latest?.tag).toBe(`channel/${spec.rev}`)

    const done = await waitFor(sent, svc.install(game.id, 'zones-audio-deDE'))
    expect(done.phase).toBe('done')
    expect(fs.readFileSync(path.join(game.addOnsPath, PACK, 'Sounds', '1.ogg'), 'utf8')).toBe('one')
    expect((await svc.statuses(game.id)).find((s) => s.productId === 'zones-audio-deDE')?.state).toBe('up-to-date')

    const removed = await waitFor(sent, svc.uninstall(game.id, 'zones-audio-deDE'))
    expect(removed.phase).toBe('done')
    expect(loadPackState(game, PACK)).toBeNull()
  })

  it('says which Spoken a pack needs, and refuses when none is released', async () => {
    const { svc, game, sent } = await setup({ spoken: '3.0.0', requires: '3.1.0' })
    expect((await svc.statuses(game.id)).find((s) => s.productId === 'zones-audio-deDE')?.needsSpoken).toBe('3.1.0')
    const failed = await waitFor(sent, svc.install(game.id, 'zones-audio-deDE'))
    expect(failed.phase).toBe('error')
    expect(failed.message).toMatch(/needs Spoken 3.1.0/)
  })

  it('keeps one job running through the Spoken install it needs', async () => {
    const game = await makeGame(tmpDir())
    write(path.join(game.addOnsPath, 'Spoken', 'Spoken.toc'), toc('Spoken', '3.0.0'))
    const zip = await yazlZip([
      { name: 'Spoken/Spoken.toc', data: toc('Spoken', '3.1.0') },
      { name: 'Spoken/Spoken.lua', data: 'x' }
    ])
    extra = await startServer((req, res) => serveBuffer(req, res, zip))
    const releases = [
      {
        tag_name: 'spoken/v3.1.0', draft: false, prerelease: false, published_at: '2026-10-01T00:00:00Z', body: '', html_url: '',
        assets: [{ name: 'Spoken-3.1.0.zip', size: zip.length, browser_download_url: `${extra.url}/Spoken-3.1.0.zip`, digest: `sha256:${sha256(zip)}`, state: 'uploaded' }]
      }
    ]
    const s = await serveChannel(channelFixture(keys, [{ ...spec, requires: '3.1.0' }]))
    server = s
    const fetchImpl = (async (url: string, init?: RequestInit) =>
      String(url).startsWith('https://api.github.com/') ? new Response(JSON.stringify(releases), { status: 200, headers: { 'content-type': 'application/json' } }) : fetch(url, init)) as unknown as typeof fetch
    const sent: { channel: string; payload: unknown }[] = []
    const svc = new LauncherService({
      dataPath: tmpDir(), appVersion: '0.1.0', send: (channel, payload) => sent.push({ channel, payload }),
      fetchImpl, autoPaths: [game.root], isRunning: async () => false, backoffMs: 1, packsBaseUrl: s.base, packsPublicKey: keys.publicKey
    })
    await svc.init()
    await svc.refreshCatalog(true)
    const clip = path.join(game.addOnsPath, PACK, 'Sounds', '1.ogg')
    let clipAtDone: boolean | null = null
    const jobId = svc.install(game.id, 'zones-audio-deDE')
    const watch = setInterval(() => {
      const ev = sent.filter((e) => e.channel === CHANNELS.jobProgress && (e.payload as JobProgress).jobId === jobId)
      if (clipAtDone === null && ev.some((e) => (e.payload as JobProgress).phase === 'done')) clipAtDone = fs.existsSync(clip)
    }, 1)
    const done = await waitFor(sent, jobId)
    clearInterval(watch)
    expect(done.phase).toBe('done')
    const events = sent.filter((e) => e.channel === CHANNELS.jobProgress && (e.payload as JobProgress).jobId === jobId).map((e) => e.payload as JobProgress)
    expect(events.filter((e) => e.phase === 'done')).toHaveLength(1)
    expect(events.at(-1)?.phase).toBe('done')
    expect(events.every((e) => e.productId === 'zones-audio-deDE')).toBe(true)
    expect(fs.existsSync(clip)).toBe(true)
    expect(clipAtDone).toBe(true)
    expect(fs.readFileSync(path.join(game.addOnsPath, 'Spoken', 'Spoken.toc'), 'utf8')).toMatch(/3\.1\.0/)
  })

  it('gives up on a channel that never answers, and still updates the GitHub catalog', async () => {
    const game = await makeGame(tmpDir())
    server = await startServer(() => undefined)
    const releases = [
      { tag_name: 'spoken/v3.1.0', draft: false, prerelease: false, published_at: '2026-10-01T00:00:00Z', body: '', html_url: '', assets: [{ name: 'Spoken-3.1.0.zip', size: 1, browser_download_url: 'http://127.0.0.1:9/x.zip' }] }
    ]
    const fetchImpl = (async (url: string, init?: RequestInit) =>
      String(url).startsWith('https://api.github.com/') ? new Response(JSON.stringify(releases), { status: 200, headers: { 'content-type': 'application/json' } }) : fetch(url, init)) as unknown as typeof fetch
    const svc = new LauncherService({
      dataPath: tmpDir(), appVersion: '0.1.0', send: () => undefined, fetchImpl, autoPaths: [game.root], isRunning: async () => false,
      packsBaseUrl: `${server.url}/`, packsPublicKey: keys.publicKey, packsTimeoutMs: 200
    })
    await svc.init()
    const started = Date.now()
    const catalog = await svc.refreshCatalog(true)
    expect(Date.now() - started).toBeLessThan(1000)
    expect(catalog.releases['spoken']?.length).toBe(1)
  })
})
