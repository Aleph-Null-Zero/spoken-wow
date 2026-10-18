// Resumable download of one release asset to `<dir>/<name>.zip.part`, renamed to `.zip` when it
// is complete, the right size and (when GitHub gave one) the right sha256.
import { createHash, type Hash } from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { Readable } from 'node:stream'
import { CancelledError, PlainError, formatBytes, isAbortError, sleep, throwIfAborted } from './errors'
import { log } from './state'

export interface DownloadOptions {
  url: string
  /** Where the file goes; created when missing. */
  dir: string
  /** File name without extension, e.g. `quests-audio-1.2.0`. */
  baseName: string
  expectedSize: number
  /** `sha256:<hex>`. */
  digest?: string
  signal?: AbortSignal
  onProgress?: (received: number, total: number, bytesPerSecond: number) => void
  /** Called before the checksum of a large file is computed. */
  onVerify?: () => void
  userAgent?: string
  fetchImpl?: typeof fetch
  /** Attempts on a network error (default 3). */
  attempts?: number
  /** First wait between attempts in ms (default 1000, doubled each time). */
  backoffMs?: number
}

export interface DownloadResult {
  file: string
  /** Bytes fetched in this run (0 when a finished file was reused). */
  fetched: number
}

export function zipPathFor(dir: string, baseName: string): string {
  return path.join(dir, `${baseName}.zip`)
}

const MISMATCH =
  'The downloaded file does not match what GitHub published, so it was deleted. Try again; if it keeps happening, check your connection.'

function wantedHash(digest: string | undefined): string | null {
  const m = digest ? /^sha256:([0-9a-f]{64})$/i.exec(digest) : null
  return m ? m[1]!.toLowerCase() : null
}

export async function sha256OfFile(file: string, signal?: AbortSignal): Promise<string> {
  const hash = createHash('sha256')
  const stream = fs.createReadStream(file, { highWaterMark: 1024 * 1024 })
  try {
    for await (const chunk of stream) {
      hash.update(chunk as Buffer)
      throwIfAborted(signal)
    }
  } finally {
    stream.destroy()
  }
  return hash.digest('hex')
}

async function sizeOf(file: string): Promise<number> {
  try {
    return (await fs.promises.stat(file)).size
  } catch {
    return 0
  }
}

async function removeQuiet(file: string): Promise<void> {
  await fs.promises.rm(file, { force: true }).catch(() => undefined)
}

class Retryable extends Error {}

/** Checks a finished file; deletes it and throws in plain words when it is wrong. */
async function verifyFile(file: string, opts: DownloadOptions, hash: Hash | null): Promise<void> {
  const size = await sizeOf(file)
  if (opts.expectedSize > 0 && size !== opts.expectedSize) {
    await removeQuiet(file)
    log(`Download size mismatch: got ${size}, expected ${opts.expectedSize}.`)
    throw new PlainError(MISMATCH)
  }
  const want = wantedHash(opts.digest)
  if (want) {
    let got: string
    if (hash) got = hash.digest('hex')
    else {
      opts.onVerify?.()
      got = await sha256OfFile(file, opts.signal)
    }
    if (got !== want) {
      await removeQuiet(file)
      log('Download checksum mismatch.')
      throw new PlainError(MISMATCH)
    }
  }
}

/** Downloads (or resumes) the asset and returns the finished `.zip`. */
export async function downloadAsset(opts: DownloadOptions): Promise<DownloadResult> {
  const doFetch = opts.fetchImpl ?? fetch
  await fs.promises.mkdir(opts.dir, { recursive: true })
  const zip = zipPathFor(opts.dir, opts.baseName)
  const part = `${zip}.part`
  const attempts = opts.attempts ?? 3

  // A finished file kept from an earlier run: reuse it when it is still good.
  if ((await sizeOf(zip)) > 0) {
    try {
      await verifyFile(zip, opts, null)
      opts.onProgress?.(opts.expectedSize, opts.expectedSize, 0)
      return { file: zip, fetched: 0 }
    } catch (err) {
      if (isAbortError(err)) throw err
      // verifyFile removed it; fetch it again.
    }
  }

  let fetched = 0
  let lastError: unknown
  for (let attempt = 1; attempt <= attempts; attempt++) {
    throwIfAborted(opts.signal)
    try {
      await attemptOnce()
      return { file: zip, fetched }
    } catch (err) {
      if (!(err instanceof Retryable)) throw err
      lastError = err
      log(`Download attempt ${attempt} failed: ${err.message}`)
      if (attempt < attempts) await sleep((opts.backoffMs ?? 1000) * 2 ** (attempt - 1), opts.signal)
    }
  }
  throw new PlainError(
    `The download stopped before it finished (${lastError instanceof Error ? lastError.message : 'network error'}). The part that arrived is kept; press the button again to continue.`
  )

  async function attemptOnce(): Promise<void> {
    let existing = await sizeOf(part)
    if (opts.expectedSize > 0 && existing > opts.expectedSize) {
      await removeQuiet(part)
      existing = 0
    }

    if (opts.expectedSize > 0 && existing === opts.expectedSize) {
      await finish(null)
      return
    }

    const headers: Record<string, string> = {
      'User-Agent': opts.userAgent ?? 'SpokenLauncher',
      Accept: 'application/octet-stream'
    }
    if (existing > 0) headers.Range = `bytes=${existing}-`

    let res: Response
    try {
      res = await doFetch(opts.url, { headers, redirect: 'follow', signal: opts.signal })
    } catch (err) {
      if (opts.signal?.aborted) throw new CancelledError()
      throw new Retryable(err instanceof Error ? err.message : String(err))
    }

    if (res.status === 416) {
      await res.body?.cancel().catch(() => undefined)
      if (existing > 0 && (opts.expectedSize <= 0 || existing === opts.expectedSize)) {
        await finish(null)
        return
      }
      await removeQuiet(part)
      throw new Retryable('the server did not accept the resume request')
    }
    if (res.status >= 500 || res.status === 429) {
      await res.body?.cancel().catch(() => undefined)
      throw new Retryable(`server answered ${res.status}`)
    }
    if (res.status !== 200 && res.status !== 206) {
      await res.body?.cancel().catch(() => undefined)
      throw new PlainError(
        res.status === 404
          ? 'GitHub no longer has this file. Refresh the list and try again.'
          : `GitHub refused the download (${res.status}).`
      )
    }
    if (!res.body) throw new Retryable('empty answer')

    let flags: 'a' | 'w' = 'a'
    let hash: Hash | null = null
    if (res.status === 206) {
      const m = /^bytes (\d+)-/.exec(res.headers.get('content-range') ?? '')
      if (!m || Number(m[1]) !== existing) {
        await res.body.cancel().catch(() => undefined)
        await removeQuiet(part)
        throw new Retryable('the server resumed at the wrong place')
      }
      if (existing === 0) hash = createHash('sha256')
    } else {
      // 200: the server ignored the range (or there was none): start the file again.
      flags = 'w'
      existing = 0
      hash = createHash('sha256')
    }

    const lengthHeader = Number(res.headers.get('content-length'))
    const total =
      opts.expectedSize > 0
        ? opts.expectedSize
        : Number.isFinite(lengthHeader) && lengthHeader > 0
          ? existing + lengthHeader
          : 0

    const fh = await fs.promises.open(part, flags)
    let received = existing
    let lastTick = Date.now()
    let lastBytes = received
    let speed = 0
    let lastReport = 0
    const report = (force: boolean): void => {
      const now = Date.now()
      if (!force && now - lastReport < 100) return
      const dt = now - lastTick
      if (dt >= 250) {
        const inst = ((received - lastBytes) * 1000) / dt
        speed = speed === 0 ? inst : speed * 0.7 + inst * 0.3
        lastTick = now
        lastBytes = received
      }
      lastReport = now
      opts.onProgress?.(received, total, Math.round(speed))
    }

    let streamError: unknown = null
    try {
      const stream = Readable.fromWeb(res.body as never)
      for await (const chunk of stream) {
        const buf = chunk as Buffer
        await fh.write(buf)
        hash?.update(buf)
        received += buf.length
        report(false)
        if (opts.signal?.aborted) {
          stream.destroy()
          throw new CancelledError()
        }
      }
    } catch (err) {
      streamError = err
    } finally {
      await fh.close().catch(() => undefined)
    }
    report(true)
    fetched += received - existing

    if (streamError) {
      if (opts.signal?.aborted || isAbortError(streamError)) throw new CancelledError()
      throw new Retryable(streamError instanceof Error ? streamError.message : String(streamError))
    }

    const size = await sizeOf(part)
    if (opts.expectedSize > 0 && size < opts.expectedSize) throw new Retryable(`the connection closed after ${formatBytes(size)}`)
    // `hash` covers the whole file only when it was started at byte 0 and nothing was skipped.
    await finish(hash)
  }

  async function finish(hash: Hash | null): Promise<void> {
    await verifyFile(part, opts, hash)
    await fs.promises.rename(part, zip)
  }
}
