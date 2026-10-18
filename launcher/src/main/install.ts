// Install, update and remove a product on one game. The rules (PLAN.md): never touch a linked
// folder, extract to staging first, move the old folder to a backup, roll back on any failure,
// never touch anything but the product's own folder names.
import fs from 'node:fs'
import path from 'node:path'
import { pipeline } from 'node:stream/promises'
import yauzl from 'yauzl'
import type { GameInstall, JobPhase, JobProgress, Product, ReleaseInfo } from '../shared/types'
import { SPOKEN_FOLDERS } from '../shared/products'
import { downloadAsset, zipPathFor } from './download'
import { PlainError, errorCode, formatBytes, isAbortError, sleep, throwIfAborted } from './errors'
import {
  LINKED_MESSAGE,
  allowedFolders,
  canWrite,
  checkEntryPath,
  ensureFreeSpace,
  isGameRunning,
  isInside,
  isLinked,
  volumeOf
} from './guard'
import { getRecord, loadState, log, removeRecord, setRecord, updateState } from './state'

export const WORK_DIR = '.spoken-launcher'

export interface FsOps {
  rename(from: string, to: string): Promise<void>
  rm(target: string): Promise<void>
  cp(from: string, to: string): Promise<void>
}

async function renameWithRetry(from: string, to: string): Promise<void> {
  for (let attempt = 1; ; attempt++) {
    try {
      await fs.promises.rename(from, to)
      return
    } catch (err) {
      const code = errorCode(err)
      if (attempt >= 4 || (code !== 'EPERM' && code !== 'EBUSY' && code !== 'EACCES')) throw err
      await sleep(200 * attempt)
    }
  }
}

const defaultOps: FsOps = {
  rename: renameWithRetry,
  rm: (target) => fs.promises.rm(target, { recursive: true, force: true, maxRetries: 3, retryDelay: 150 }),
  cp: (from, to) => fs.promises.cp(from, to, { recursive: true, errorOnExist: true, force: false })
}

export interface JobContext {
  jobId: string
  /** The launcher's data folder (state.json lives there). */
  dataPath: string
  downloadsPath: string
  keepDownloads: boolean
  signal?: AbortSignal
  emit: (progress: JobProgress) => void
  userAgent?: string
  fetchImpl?: typeof fetch
  attempts?: number
  backoffMs?: number
  /** Replaces the file operations (tests). */
  ops?: Partial<FsOps>
  /** Replaces the running-game check (tests). */
  isRunning?: () => Promise<boolean>
}

export interface JobResult {
  version?: string
  folders: string[]
  /** Old folders of this product, no longer in the zip, that were moved to the backup. */
  removed: string[]
  gameRunning: boolean
  message: string
}

// ---------------------------------------------------------------- helpers

export function workDir(game: GameInstall): string {
  return path.join(game.addOnsPath, WORK_DIR)
}

export function backupDirFor(game: GameInstall, productId: string): string {
  return path.join(workDir(game), 'backup', productId)
}

async function exists(p: string): Promise<boolean> {
  try {
    await fs.promises.lstat(p)
    return true
  } catch {
    return false
  }
}

async function moveDir(from: string, to: string, ops: FsOps): Promise<void> {
  try {
    await ops.rename(from, to)
  } catch (err) {
    if (errorCode(err) !== 'EXDEV') throw err
    await ops.cp(from, to)
    await ops.rm(from)
  }
}

function reporter(game: GameInstall, product: Product, ctx: JobContext, action: 'install' | 'uninstall', version?: string) {
  let received = 0
  let total = 0
  let bps = 0
  return {
    set(r: number, t: number, s: number): void {
      received = r
      total = t
      bps = s
    },
    send(phase: JobPhase, message?: string): void {
      ctx.emit({
        jobId: ctx.jobId,
        gameId: game.id,
        productId: product.id,
        action,
        phase,
        received,
        total,
        bytesPerSecond: phase === 'downloading' ? bps : 0,
        ...(version ? { version } : {}),
        ...(message ? { message } : {})
      })
    }
  }
}

function doneMessage(running: boolean, createdNew: boolean, removed: boolean): string {
  const base = 'Reload the game (/reload) or restart it to use it.'
  if (removed) return running ? 'The game is running. Reload the game (/reload) or restart it to apply this.' : 'Removed. Reload the game (/reload) or restart it if it is open.'
  if (running && createdNew) return 'The game is running. Restart it to load the new files.'
  return running ? `The game is running. ${base}` : base
}

// ---------------------------------------------------------------- swapping folders in and out

interface Change {
  folder: string
  /** The extracted folder to move in; none means only remove the current one. */
  staged?: string
}

type Phase = 'start' | 'backingUp' | 'backedUp' | 'placing' | 'placed'
interface Journal {
  folder: string
  hadOld: boolean
  phase: Phase
}

/**
 * Moves each current folder to the backup, then each staged folder in. Any failure puts every
 * folder back as it was. Returns the folders that did not exist before.
 */
async function applyChanges(
  addOns: string,
  backupDir: string,
  changes: Change[],
  ops: FsOps,
  signal?: AbortSignal
): Promise<{ created: string[] }> {
  // The previous backup of this product is replaced.
  await ops.rm(backupDir)
  await fs.promises.mkdir(backupDir, { recursive: true })

  const journal: Journal[] = []
  try {
    for (const change of changes) {
      throwIfAborted(signal)
      const target = path.join(addOns, change.folder)
      const entry: Journal = { folder: change.folder, hadOld: await exists(target), phase: 'start' }
      journal.push(entry)
      if (entry.hadOld) {
        entry.phase = 'backingUp'
        await moveDir(target, path.join(backupDir, change.folder), ops)
        entry.phase = 'backedUp'
      }
      if (change.staged) {
        entry.phase = 'placing'
        await moveDir(change.staged, target, ops)
        entry.phase = 'placed'
      }
    }
  } catch (err) {
    const failed = await rollback(addOns, backupDir, journal, ops)
    if (isAbortError(err)) throw err
    log('Install failed, rolled back:', err)
    const why = err instanceof Error ? err.message : String(err)
    const hint = errorCode(err) === 'EPERM' || errorCode(err) === 'EBUSY' || errorCode(err) === 'EACCES'
      ? ' A file may be in use: close the game and anything else that has the add-on open, then try again.'
      : ''
    if (failed.length > 0) {
      throw new PlainError(
        `Something went wrong (${why}) and ${failed.join(', ')} could not be put back. The previous version is in ${backupDir}.${hint}`
      )
    }
    throw new PlainError(`Nothing was changed: ${why}.${hint}`)
  }
  return { created: journal.filter((j) => !j.hadOld).map((j) => j.folder) }
}

async function rollback(addOns: string, backupDir: string, journal: Journal[], ops: FsOps): Promise<string[]> {
  const failed: string[] = []
  for (const entry of [...journal].reverse()) {
    const target = path.join(addOns, entry.folder)
    const saved = path.join(backupDir, entry.folder)
    try {
      if (!entry.hadOld) {
        if (entry.phase === 'placing' || entry.phase === 'placed') await ops.rm(target)
      } else if (entry.phase === 'start' || entry.phase === 'backingUp') {
        if (await exists(target)) await ops.rm(saved)
        else await moveDir(saved, target, ops)
      } else {
        await ops.rm(target)
        await moveDir(saved, target, ops)
      }
    } catch (err) {
      log(`Rollback of ${entry.folder} failed:`, err)
      failed.push(entry.folder)
    }
  }
  return failed
}

// ---------------------------------------------------------------- extraction

function openZip(file: string): Promise<yauzl.ZipFile> {
  return new Promise((resolve, reject) => {
    yauzl.open(file, { lazyEntries: true, autoClose: true, validateEntrySizes: true, strictFileNames: true }, (err, zf) =>
      err || !zf ? reject(err ?? new Error('cannot open zip')) : resolve(zf)
    )
  })
}

function openEntry(zf: yauzl.ZipFile, entry: yauzl.Entry): Promise<NodeJS.ReadableStream> {
  return new Promise((resolve, reject) => {
    zf.openReadStream(entry, (err, stream) => (err || !stream ? reject(err ?? new Error('cannot read entry')) : resolve(stream)))
  })
}

const BAD_ZIP = 'The downloaded zip file is damaged or holds unsafe paths, so nothing was installed.'

/** Streams every entry into `dest`; refuses anything outside `allowed`. */
export async function extractZip(
  zipFile: string,
  dest: string,
  allowed: readonly string[],
  signal: AbortSignal | undefined,
  onBytes: (zipBytesDone: number) => void
): Promise<void> {
  let zf: yauzl.ZipFile
  try {
    zf = await openZip(zipFile)
  } catch (err) {
    log('Zip open failed:', err)
    throw new PlainError(BAD_ZIP)
  }
  await fs.promises.mkdir(dest, { recursive: true })
  let done = 0

  async function handle(entry: yauzl.Entry): Promise<void> {
    throwIfAborted(signal)
    const name = entry.fileName
    if (/^__MACOSX(\/|$)/.test(name)) return
    const check = checkEntryPath(name, allowed)
    if (!check.ok) {
      log(`Zip entry refused (${check.reason}): ${JSON.stringify(name)}`)
      const outside = check.reason === 'folder not allowed' || check.reason === 'file outside a folder'
      throw new PlainError(
        outside
          ? `The zip holds a file or folder the launcher may not install (${name.split('/')[0]}), so nothing was installed.`
          : BAD_ZIP
      )
    }
    const mode = (entry.externalFileAttributes >>> 16) & 0o170000
    if (mode === 0o120000) throw new PlainError(BAD_ZIP)
    if (check.directory) return
    const target = path.resolve(dest, ...check.segments)
    if (!isInside(dest, target) || target === path.resolve(dest)) throw new PlainError(BAD_ZIP)
    await fs.promises.mkdir(path.dirname(target), { recursive: true })
    const src = await openEntry(zf, entry)
    try {
      await pipeline(src, fs.createWriteStream(target, { flags: 'wx' }), signal ? { signal } : {})
    } catch (err) {
      if (errorCode(err) === 'EEXIST') throw new PlainError(BAD_ZIP)
      throw err
    }
    done += entry.compressedSize
    onBytes(done)
  }

  await new Promise<void>((resolve, reject) => {
    let finished = false
    const fail = (err: unknown): void => {
      if (finished) return
      finished = true
      try {
        zf.close()
      } catch {
        /* already closed */
      }
      reject(err)
    }
    zf.on('error', (err) => {
      log('Zip read failed:', err)
      fail(new PlainError(BAD_ZIP))
    })
    zf.on('end', () => {
      if (finished) return
      finished = true
      resolve()
    })
    zf.on('entry', (entry: yauzl.Entry) => {
      handle(entry).then(() => {
        if (!finished) zf.readEntry()
      }, fail)
    })
    zf.readEntry()
  })
}

/** Checks what was extracted against what the product should hold. Returns its folders. */
async function verifyStaged(product: Product, dir: string): Promise<string[]> {
  const entries = await fs.promises.readdir(dir, { withFileTypes: true })
  const names = entries.filter((e) => e.isDirectory()).map((e) => e.name)
  if (names.length === 0 || names.length !== entries.length) throw new PlainError('The zip file does not hold the folders it should, so nothing was installed.')
  if (product.folders) {
    const missing = product.folders.filter((f) => !names.includes(f))
    const extra = names.filter((n) => !product.folders!.includes(n))
    if (missing.length > 0 || extra.length > 0) {
      throw new PlainError(
        `The zip file does not hold the expected folders${missing.length ? ` (missing ${missing.join(', ')})` : ''}, so nothing was installed.`
      )
    }
  } else {
    if (!names.includes('Spoken')) throw new PlainError('The zip file has no Spoken folder, so nothing was installed.')
    const stray = names.filter((n) => !SPOKEN_FOLDERS.includes(n))
    if (stray.length > 0) throw new PlainError(`The zip holds a folder the launcher may not install (${stray[0]}), so nothing was installed.`)
  }
  if (!product.folders) {
    // Spoken's folders must each be a loadable add-on; a voice pack's tocs are not required here.
    for (const n of names) {
      if (!(await exists(path.join(dir, n, `${n}.toc`)))) {
        throw new PlainError(`The zip file is incomplete (${n}\\${n}.toc is missing), so nothing was installed.`)
      }
    }
  }
  const order = product.folders ?? SPOKEN_FOLDERS
  return names.sort((a, b) => order.indexOf(a) - order.indexOf(b))
}

// ---------------------------------------------------------------- install

async function checkWritable(game: GameInstall): Promise<void> {
  if (!(await canWrite(game.addOnsPath))) {
    throw new PlainError(
      `The launcher cannot write to ${game.addOnsPath}. Check that the folder is not read-only and that your Windows account may change it.`
    )
  }
  await fs.promises.mkdir(game.addOnsPath, { recursive: true })
  const interfaceDir = path.dirname(game.addOnsPath)
  if (await isLinked(game.addOnsPath)) throw new PlainError(`AddOns: ${LINKED_MESSAGE}`)
  if (await isLinked(interfaceDir)) throw new PlainError(`Interface: ${LINKED_MESSAGE}`)
  if (await isLinked(workDir(game))) throw new PlainError(`${WORK_DIR}: ${LINKED_MESSAGE}`)
}

const RESERVED = new Set(['wtf', 'interface', 'addons', WORK_DIR])

/** Folders the launcher recorded for this product earlier that the new zip no longer holds: real folders only, never linked, never another product's. */
async function staleFolders(game: GameInstall, product: Product, dataPath: string, folders: string[]): Promise<string[]> {
  const state = loadState(dataPath)
  const previous = getRecord(state, game.id, product.id)?.folders ?? []
  const otherOwned = new Set(
    Object.entries(state.installs[game.id] ?? {})
      .filter(([id]) => id !== product.id)
      .flatMap(([, r]) => r.folders)
  )
  const keep = new Set(folders.map((f) => f.toLowerCase()))
  const out: string[] = []
  for (const f of previous) {
    if (!/^[A-Za-z0-9_][A-Za-z0-9_.-]*$/.test(f) || f.endsWith('.') || RESERVED.has(f.toLowerCase())) continue
    if (keep.has(f.toLowerCase()) || otherOwned.has(f) || out.includes(f)) continue
    const target = path.join(game.addOnsPath, f)
    if (!(await exists(target)) || (await isLinked(target))) continue
    if (!(await fs.promises.stat(target)).isDirectory()) continue
    out.push(f)
  }
  return out
}

function listNames(names: string[]): string {
  return names.length === 1 ? names[0]! : `${names.slice(0, -1).join(', ')} and ${names.at(-1)}`
}

async function fileSize(p: string): Promise<number> {
  try {
    return (await fs.promises.stat(p)).size
  } catch {
    return 0
  }
}

export async function installProduct(
  game: GameInstall,
  product: Product,
  release: ReleaseInfo,
  ctx: JobContext
): Promise<JobResult> {
  const ops: FsOps = { ...defaultOps, ...ctx.ops }
  const rep = reporter(game, product, ctx, 'install', release.version)
  const allowed = allowedFolders(product)
  const addOns = game.addOnsPath
  const stagingJob = path.join(workDir(game), 'staging', ctx.jobId.replace(/[^\w.-]/g, '_'))
  const baseName = `${product.id}-${release.version}`.replace(/[^\w.-]/g, '_')
  const zip = zipPathFor(ctx.downloadsPath, baseName)

  rep.set(0, release.assetSize, 0)
  throwIfAborted(ctx.signal)
  await checkWritable(game)

  // Free space: the zip on the downloads drive; twice its size on the game drive (extracted copy and the move).
  const have = Math.max(await fileSize(zip), await fileSize(`${zip}.part`))
  const zipNeed = Math.max(0, release.assetSize - have)
  await fs.promises.mkdir(ctx.downloadsPath, { recursive: true })
  if ((await volumeOf(ctx.downloadsPath)) === (await volumeOf(addOns))) {
    await ensureFreeSpace(addOns, 2 * release.assetSize + zipNeed, `${product.title} (${formatBytes(release.assetSize)})`)
  } else {
    await ensureFreeSpace(addOns, 2 * release.assetSize, `${product.title} (${formatBytes(release.assetSize)})`)
    await ensureFreeSpace(ctx.downloadsPath, zipNeed, 'the download')
  }

  rep.send('downloading')
  const downloaded = await downloadAsset({
    url: release.assetUrl,
    dir: ctx.downloadsPath,
    baseName,
    expectedSize: release.assetSize,
    ...(release.digest ? { digest: release.digest } : {}),
    ...(ctx.signal ? { signal: ctx.signal } : {}),
    ...(ctx.userAgent ? { userAgent: ctx.userAgent } : {}),
    ...(ctx.fetchImpl ? { fetchImpl: ctx.fetchImpl } : {}),
    ...(ctx.attempts ? { attempts: ctx.attempts } : {}),
    ...(ctx.backoffMs !== undefined ? { backoffMs: ctx.backoffMs } : {}),
    onProgress: (received, total, bps) => {
      rep.set(received, total, bps)
      rep.send('downloading')
    },
    onVerify: () => rep.send('verifying', 'Checking the download')
  })

  try {
    throwIfAborted(ctx.signal)
    rep.set(0, release.assetSize, 0)
    rep.send('extracting')
    await fs.promises.rm(stagingJob, { recursive: true, force: true })
    let lastSent = 0
    await extractZip(downloaded.file, stagingJob, allowed, ctx.signal, (done) => {
      rep.set(done, release.assetSize, 0)
      const now = Date.now()
      if (now - lastSent > 100) {
        lastSent = now
        rep.send('extracting')
      }
    })
    const folders = await verifyStaged(product, stagingJob)

    // Look at every target before changing any.
    for (const folder of folders) {
      const target = path.join(addOns, folder)
      if (await isLinked(target)) throw new PlainError(`${folder}: ${LINKED_MESSAGE}`)
      if ((await exists(target)) && !(await fs.promises.stat(target)).isDirectory()) {
        throw new PlainError(`${folder} in the AddOns folder is a file, not a folder, so it was left alone.`)
      }
    }

    const stale = await staleFolders(game, product, ctx.dataPath, folders)

    rep.set(release.assetSize, release.assetSize, 0)
    rep.send('installing')
    const { created } = await applyChanges(
      addOns,
      backupDirFor(game, product.id),
      [...folders.map((folder) => ({ folder, staged: path.join(stagingJob, folder) })), ...stale.map((folder) => ({ folder }))],
      ops,
      ctx.signal
    )

    updateState(ctx.dataPath, (s) =>
      setRecord(s, game.id, product.id, {
        version: release.version,
        folders,
        installedAt: new Date().toISOString(),
        tag: release.tag
      })
    )
    log(`Installed ${product.id} ${release.version} on ${game.label} (${folders.join(', ')}).`)
    if (stale.length > 0) log(`Moved old folders of ${product.id} to the backup: ${stale.join(', ')}.`)

    if (!ctx.keepDownloads) await fs.promises.rm(downloaded.file, { force: true }).catch(() => undefined)
    const running = await (ctx.isRunning ?? (() => isGameRunning(game.flavor)))()
    const note = stale.length > 0 ? `Removed the old ${listNames(stale)} folder${stale.length > 1 ? 's' : ''}. ` : ''
    const message = note + doneMessage(running, created.length > 0, false)
    rep.send('done', message)
    return { version: release.version, folders, removed: stale, gameRunning: running, message }
  } finally {
    await fs.promises.rm(stagingJob, { recursive: true, force: true }).catch(() => undefined)
    await fs.promises.rmdir(path.join(workDir(game), 'staging')).catch(() => undefined)
  }
}

// ---------------------------------------------------------------- uninstall

/** Removes the folders the launcher installed for a product (or the product's own names when there is no record). */
export async function uninstallProduct(game: GameInstall, product: Product, ctx: JobContext): Promise<JobResult> {
  const ops: FsOps = { ...defaultOps, ...ctx.ops }
  const rep = reporter(game, product, ctx, 'uninstall')
  const allowed = allowedFolders(product)
  const record = getRecord(loadState(ctx.dataPath), game.id, product.id)
  const wanted = (record?.folders ?? allowed).filter((f) => allowed.includes(f))

  throwIfAborted(ctx.signal)
  await checkWritable(game)

  const present: string[] = []
  for (const folder of wanted) {
    const target = path.join(game.addOnsPath, folder)
    if (!(await exists(target))) continue
    if (await isLinked(target)) throw new PlainError(`${folder}: ${LINKED_MESSAGE}`)
    if (!(await fs.promises.stat(target)).isDirectory()) continue
    present.push(folder)
  }

  rep.send('installing', 'Removing')
  if (present.length > 0) {
    await applyChanges(
      game.addOnsPath,
      backupDirFor(game, product.id),
      present.map((folder) => ({ folder })),
      ops,
      ctx.signal
    )
  }
  updateState(ctx.dataPath, (s) => removeRecord(s, game.id, product.id))
  log(`Removed ${product.id} from ${game.label} (${present.join(', ') || 'nothing on disk'}).`)

  const running = await (ctx.isRunning ?? (() => isGameRunning(game.flavor)))()
  const message = present.length === 0 ? 'Nothing to remove: its folders are not there.' : doneMessage(running, false, true)
  rep.send('done', message)
  return { folders: present, removed: present, gameRunning: running, message }
}
