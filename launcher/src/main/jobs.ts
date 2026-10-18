// Runs install and uninstall jobs: one at a time per game folder, the rest wait in a queue.
import { randomUUID } from 'node:crypto'
import type { JobProgress } from '../shared/types'
import { isAbortError, plainMessage } from './errors'
import { log } from './state'

export interface JobSpec {
  gameId: string
  productId: string
  action: 'install' | 'uninstall'
  /** The work. Emits its own progress and `done`; throws to fail. */
  run: (ctx: { jobId: string; signal: AbortSignal; emit: (p: JobProgress) => void }) => Promise<void>
  version?: string
}

interface Job {
  id: string
  spec: JobSpec
  controller: AbortController
  state: 'queued' | 'running' | 'finished'
}

const KEEP_MS = 10 * 60 * 1000

export class JobManager {
  private queues = new Map<string, Job[]>()
  private running = new Set<string>()
  private jobs = new Map<string, Job>()
  private last = new Map<string, { progress: JobProgress; at: number }>()

  constructor(private broadcast: (p: JobProgress) => void) {}

  /** Queues a job and returns its id. The same product on the same game while one is waiting or running gives that job's id. */
  enqueue(spec: JobSpec): string {
    this.prune()
    for (const j of this.jobs.values()) {
      if (
        j.state !== 'finished' &&
        j.spec.gameId === spec.gameId &&
        j.spec.productId === spec.productId &&
        j.spec.action === spec.action
      ) {
        return j.id
      }
    }
    const job: Job = { id: randomUUID(), spec, controller: new AbortController(), state: 'queued' }
    this.jobs.set(job.id, job)
    const q = this.queues.get(spec.gameId) ?? []
    q.push(job)
    this.queues.set(spec.gameId, q)
    this.publish(job, 'queued', q.length > 1 || this.running.has(spec.gameId) ? 'Waiting for another job on this game' : undefined)
    void this.pump(spec.gameId)
    return job.id
  }

  /** Stops a job: a queued one is dropped, a running one is aborted. */
  cancel(jobId: string): boolean {
    const job = this.jobs.get(jobId)
    if (!job || job.state === 'finished') return false
    if (job.state === 'queued') {
      const q = this.queues.get(job.spec.gameId) ?? []
      this.queues.set(
        job.spec.gameId,
        q.filter((j) => j !== job)
      )
      job.state = 'finished'
      this.publish(job, 'cancelled', 'Cancelled.')
      return true
    }
    job.controller.abort()
    return true
  }

  /** The newest progress event of a job, for a while after it ends. */
  lastProgress(jobId: string): JobProgress | undefined {
    return this.last.get(jobId)?.progress
  }

  /** Jobs that are waiting or running. */
  active(): string[] {
    return [...this.jobs.values()].filter((j) => j.state !== 'finished').map((j) => j.id)
  }

  private publish(job: Job, phase: JobProgress['phase'], message?: string): void {
    this.emit(job, {
      jobId: job.id,
      gameId: job.spec.gameId,
      productId: job.spec.productId,
      action: job.spec.action,
      phase,
      received: 0,
      total: 0,
      bytesPerSecond: 0,
      ...(job.spec.version ? { version: job.spec.version } : {}),
      ...(message ? { message } : {})
    })
  }

  private emit(job: Job, progress: JobProgress): void {
    this.last.set(job.id, { progress, at: Date.now() })
    try {
      this.broadcast(progress)
    } catch (err) {
      log('Could not send job progress:', err)
    }
  }

  private async pump(gameId: string): Promise<void> {
    if (this.running.has(gameId)) return
    const q = this.queues.get(gameId) ?? []
    const job = q.shift()
    if (!job) return
    this.running.add(gameId)
    job.state = 'running'
    let ended = false
    try {
      await job.spec.run({
        jobId: job.id,
        signal: job.controller.signal,
        emit: (p) => {
          if (p.phase === 'done') ended = true
          this.emit(job, p)
        }
      })
      if (!ended) this.publish(job, 'done')
    } catch (err) {
      if (isAbortError(err) || job.controller.signal.aborted) {
        this.publish(job, 'cancelled', 'Cancelled.')
      } else {
        log(`Job ${job.spec.action} ${job.spec.productId} failed:`, err)
        this.publish(job, 'error', plainMessage(err))
      }
    } finally {
      job.state = 'finished'
      this.running.delete(gameId)
      void this.pump(gameId)
    }
  }

  private prune(): void {
    const now = Date.now()
    for (const [id, v] of this.last) {
      if (now - v.at > KEEP_MS && this.jobs.get(id)?.state === 'finished') {
        this.last.delete(id)
        this.jobs.delete(id)
      }
    }
  }
}
