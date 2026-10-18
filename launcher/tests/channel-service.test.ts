import fs from 'node:fs'
import path from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { CHANNELS } from '../src/shared/api'
import type { JobProgress } from '../src/shared/types'
import { LauncherService } from '../src/main/service'
import { loadPackState } from '../src/main/packs-state'
import { channelFixture, channelKeys, serveChannel, type PackSpec } from './channel-helpers'
import { makeGame, tmpDir, toc, write, type TestServer } from './helpers'

let server: TestServer | null = null
afterEach(async () => {
  await server?.close()
  server = null
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
})
