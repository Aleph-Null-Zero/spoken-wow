// Installs, updates and repairs voice packs from the launcher channel: download the blobs an
// installed folder lacks, build the new folder in staging from hard links (the unchanged files of
// the installed folder and the new blobs), and swap it in with install.ts's journaled folder swap.
// Spec: docs/superpowers/specs/2026-10-18-launcher-delta-packs-design.md
import { createHash } from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { Readable } from 'node:stream'
import { pipeline } from 'node:stream/promises'
import type { GameInstall, JobPhase, Product } from '../shared/types'
import { sha256OfFile } from './download'
import { PlainError, formatBytes, isAbortError, sleep, throwIfAborted } from './errors'
import { LINKED_MESSAGE, ensureFreeSpace, isGameRunning, isLinked } from './guard'
import { applyChanges, backupDirFor, checkWritable, defaultOps, doneMessage, pruneBackups, refuseUnresolved, workDir, type FsOps, type JobContext, type JobResult } from './install'
import { channelTag } from './packs-catalog'
import { listLocal, planPack, type PackPlan } from './packs-plan'
import type { ChannelManifest } from './packs-remote'
import { savePackState, loadPackState, type PackFileState } from './packs-state'
import { log, setRecord, updateState } from './state'

export interface SyncInput {
  product: Product
  /** One per folder of the product, in the product's folder order. */
  manifests: ChannelManifest[]
  /** The channel's base URL, ending in `/`. */
  baseUrl: string
  /** Hash every file, whatever the state says. */
  repair?: boolean
  /** Replaces `fs.promises.link` (tests). */
  link?: (from: string, to: string) => Promise<void>
}

const PARALLEL = 12
const MARGIN = 64 * 1024 * 1024

export function blobDir(game: GameInstall): string {
  return path.join(workDir(game), 'blobs')
}

const segments = (p: string): string[] => p.split('/')

/**
 * Runs `fn` over `items`, `limit` at a time. The first failure calls `onFail` and stops new work; every
 * running worker is waited for before the first error is thrown, so nothing runs on after this returns.
 */
async function eachLimit<T>(items: T[], limit: number, fn: (item: T) => Promise<void>, onFail: () => void): Promise<void> {
  let next = 0
  let failure: { err: unknown } | null = null
  const worker = async (): Promise<void> => {
    while (!failure && next < items.length) {
      const item = items[next++]!
      try {
        await fn(item)
      } catch (err) {
        if (!failure) {
          failure = { err }
          onFail()
        }
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker))
  if (failure) throw (failure as { err: unknown }).err
}

/** Downloads one blob to `dest`, through `.part`, renamed only when its size and hash are right. */
async function fetchBlob(url: string, dest: string, sha: string, size: number, ctx: JobContext, onBytes: (n: number) => void): Promise<void> {
  const attempts = ctx.attempts ?? 3
  let wait = ctx.backoffMs ?? 1000
  const part = `${dest}.part`
  for (let attempt = 1; ; attempt++) {
    throwIfAborted(ctx.signal)
    let got = 0
    try {
      const res = await (ctx.fetchImpl ?? fetch)(url, {
        headers: ctx.userAgent ? { 'User-Agent': ctx.userAgent } : {},
        ...(ctx.signal ? { signal: ctx.signal } : {})
      })
      if (!res.ok || !res.body) throw new Error(`HTTP ${res.status}`)
      const hash = createHash('sha256')
      const body = Readable.fromWeb(res.body as never)
      body.on('data', (chunk: Buffer) => {
        hash.update(chunk)
        got += chunk.length
        onBytes(chunk.length)
      })
      await pipeline(body, fs.createWriteStream(part))
      if (got !== size || hash.digest('hex') !== sha) throw new Error('checksum mismatch')
      await fs.promises.rename(part, dest)
      return
    } catch (err) {
      onBytes(-got)
      await fs.promises.rm(part, { force: true }).catch(() => undefined)
      if (isAbortError(err)) throw err
      if (attempt >= attempts) {
        log(`Blob ${sha} failed:`, err)
        throw new PlainError('A voice file could not be downloaded intact. Check your connection and try again; what was already downloaded is kept.')
      }
      await sleep(wait, ctx.signal)
      wait *= 2
    }
  }
}

export async function syncPacks(game: GameInstall, input: SyncInput, ctx: JobContext): Promise<JobResult> {
  const { product, manifests } = input
  const ops: FsOps = { ...defaultOps, ...ctx.ops }
  const link = input.link ?? ((from: string, to: string) => fs.promises.link(from, to))
  const revs = manifests.map((m) => m.rev)
  const shown = [...revs].sort().at(-1) ?? ''
  const emit = (phase: JobPhase, received: number, total: number, bytesPerSecond = 0, message?: string): void =>
    ctx.emit({ jobId: ctx.jobId, gameId: game.id, productId: product.id, action: input.repair ? 'repair' : 'install', phase, received, total, bytesPerSecond, version: shown, ...(message ? { message } : {}) })

  throwIfAborted(ctx.signal)
  await checkWritable(game)
  await refuseUnresolved(game, ops)

  // Every folder is planned before anything is downloaded.
  emit('verifying', 0, 0, 0, 'Checking your files')
  const plans: { manifest: ChannelManifest; plan: PackPlan; target: string }[] = []
  for (const manifest of manifests) {
    const target = path.join(game.addOnsPath, manifest.packId)
    if (await isLinked(target)) throw new PlainError(`${manifest.packId}: ${LINKED_MESSAGE}`)
    const plan = await planPack(manifest, loadPackState(game, manifest.packId), await listLocal(target), (p) => sha256OfFile(path.join(target, ...segments(p)), ctx.signal), !input.repair)
    plans.push({ manifest, plan, target })
  }

  const blobs = blobDir(game)
  await fs.promises.mkdir(blobs, { recursive: true })
  const wanted = new Map<string, number>()
  for (const { plan } of plans) for (const f of plan.fetch) wanted.set(f.sha256, f.size)
  // A blob kept from an interrupted job is whole: it was renamed into place only after its hash checked out.
  const missing: [string, number][] = []
  for (const [sha, size] of wanted) {
    const file = path.join(blobs, sha)
    const have = await fs.promises.stat(file).then((st) => st.size, () => -1)
    // Size alone is not proof: a rename that was never flushed can leave the right size with the wrong bytes.
    if (have === size && (await sha256OfFile(file, ctx.signal).catch((err: unknown) => {
      if (isAbortError(err)) throw err
      return ''
    })) === sha) continue
    if (have >= 0) await fs.promises.rm(file, { force: true })
    missing.push([sha, size])
  }
  const total = missing.reduce((n, [, size]) => n + size, 0)
  await ensureFreeSpace(game.addOnsPath, total + MARGIN, `${product.title} (${formatBytes(total)})`)

  let received = 0
  let lastSent = 0
  const started = Date.now()
  emit('downloading', 0, total)
  // The workers run under their own signal, so a failed blob stops the others before the job reports its error.
  const stop = new AbortController()
  const onOuterAbort = (): void => stop.abort()
  if (ctx.signal?.aborted) stop.abort()
  ctx.signal?.addEventListener('abort', onOuterAbort, { once: true })
  const dlCtx: JobContext = { ...ctx, signal: stop.signal }
  try {
    await eachLimit(
      missing,
      PARALLEL,
      ([sha, size]) =>
        fetchBlob(`${input.baseUrl}blobs/${sha}`, path.join(blobs, sha), sha, size, dlCtx, (n) => {
          if (stop.signal.aborted) return
          received += n
          const now = Date.now()
          if (now - lastSent > 100) {
            lastSent = now
            emit('downloading', received, total, received / Math.max(1, (now - started) / 1000))
          }
        }),
      () => stop.abort()
    )
  } finally {
    ctx.signal?.removeEventListener('abort', onOuterAbort)
  }

  const stagingJob = path.join(workDir(game), 'staging', ctx.jobId.replace(/[^\w.-]/g, '_'))
  try {
    emit('extracting', total, total)
    await fs.promises.rm(stagingJob, { recursive: true, force: true })
    for (const { manifest, plan, target } of plans) {
      const staged = path.join(stagingJob, manifest.packId)
      await fs.promises.mkdir(staged, { recursive: true })
      const fetched = new Set(plan.fetch.map((f) => f.path))
      for (const f of manifest.files) {
        throwIfAborted(ctx.signal)
        const from = fetched.has(f.path) ? path.join(blobs, f.sha256) : path.join(target, ...segments(f.path))
        const to = path.join(staged, ...segments(f.path))
        await fs.promises.mkdir(path.dirname(to), { recursive: true })
        try {
          await link(from, to)
        } catch {
          await fs.promises.copyFile(from, to)
        }
      }
    }

    emit('installing', total, total)
    const { created } = await applyChanges(
      game,
      product.id,
      plans.map(({ manifest }) => ({ folder: manifest.packId, staged: path.join(stagingJob, manifest.packId) })),
      ops,
      ctx.signal
    )

    for (const { manifest, target } of plans) {
      const files: Record<string, PackFileState> = {}
      for (const f of manifest.files) {
        const st = await fs.promises.stat(path.join(target, ...segments(f.path)))
        files[f.path] = { sha256: f.sha256, size: st.size, mtimeMs: st.mtimeMs }
      }
      savePackState(game, { packId: manifest.packId, rev: manifest.rev, files })
    }
    const folders = manifests.map((m) => m.packId)
    updateState(ctx.dataPath, (s) => setRecord(s, game.id, product.id, { version: shown, folders, installedAt: new Date().toISOString(), tag: channelTag(revs) }))
    for (const sha of wanted.keys()) await fs.promises.rm(path.join(blobs, sha), { force: true }).catch(() => undefined)
    log(`Synced ${product.id} on ${game.label}: ${wanted.size} files fetched (${formatBytes(total)}), revs ${revs.join(', ')}.`)

    const running = await (ctx.isRunning ?? (() => isGameRunning(game.flavor)))()
    // A channel pack can always be fetched again, and the kept backup shares hard links with the live files, which a
    // playing game can hold open on Windows. Removing it now leaves the next run nothing to delete; a failure is fine.
    await ops.rm(backupDirFor(game, product.id)).catch(() => undefined)
    await pruneBackups(game, product.id)
    const message = (input.repair ? 'Repaired. ' : '') + doneMessage(running, created.length > 0, false)
    emit('done', total, total, 0, message)
    return { version: shown, folders, removed: [], gameRunning: running, message }
  } finally {
    await fs.promises.rm(stagingJob, { recursive: true, force: true }).catch(() => undefined)
    await fs.promises.rmdir(path.join(workDir(game), 'staging')).catch(() => undefined)
  }
}
