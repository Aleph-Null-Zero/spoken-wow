// The launcher's logic without electron: what ipc.ts exposes to the window. Holds the game list,
// the settings and the catalog, and runs jobs.
import path from 'node:path'
import { CHANNELS, type AddGameResult, type InstallOptions } from '../shared/api'
import type { Catalog, GameInstall, JobProgress, ProductStatus, ReleaseInfo, Settings, Snapshot } from '../shared/types'
import { PRODUCTS, productById } from '../shared/products'
import { buildCatalog, latestFor, loadCatalog, saveCatalog } from './catalog'
import { PlainError } from './errors'
import { addGame, removeGame, scanGames } from './games'
import { fetchReleases } from './github'
import { installProduct, uninstallProduct, type FsOps } from './install'
import { JobManager } from './jobs'
import { loadSettings, loadState, log, sanitizeSettings, saveSettings } from './state'
import { computeStatuses } from './status'

export interface ServiceOptions {
  dataPath: string
  appVersion: string
  /** Sends an event to every window. */
  send: (channel: string, payload: unknown) => void
  fetchImpl?: typeof fetch
  /** Replaces the registry and default-folder search (tests). */
  autoPaths?: string[]
  isRunning?: () => Promise<boolean>
  ops?: Partial<FsOps>
  backoffMs?: number
  apiBase?: string
}

/** A catalog fetched less than this long ago is not fetched again unless forced. */
const FRESH_MS = 5 * 60 * 1000

export class LauncherService {
  games: GameInstall[] = []
  settings: Settings
  catalog: Catalog
  readonly jobs: JobManager
  private refreshing: Promise<Catalog> | null = null
  /** Settles when the first scan is done; handlers wait for it. Never rejects. */
  ready: Promise<void> = Promise.resolve()

  constructor(private opts: ServiceOptions) {
    this.settings = loadSettings(opts.dataPath)
    this.catalog = loadCatalog(opts.dataPath)
    this.jobs = new JobManager((p: JobProgress) => opts.send(CHANNELS.jobProgress, p))
  }

  get dataPath(): string {
    return this.opts.dataPath
  }

  downloadsPath(): string {
    return this.settings.downloadsPath || path.join(this.opts.dataPath, 'downloads')
  }

  /** Starts the first scan; `ready` settles when it ends. */
  init(): Promise<void> {
    this.ready = this.scan().then(
      () => undefined,
      (err) => log('First scan failed:', err)
    )
    return this.ready
  }

  snapshot(): Snapshot {
    return {
      games: this.games,
      settings: this.settings,
      catalog: this.catalog,
      products: PRODUCTS,
      appVersion: this.opts.appVersion,
      dataPath: this.opts.dataPath
    }
  }

  // ---------------------------------------------------------------- games

  async scan(): Promise<GameInstall[]> {
    this.games = await scanGames(this.opts.dataPath, this.opts.autoPaths ? { autoPaths: this.opts.autoPaths } : {})
    this.opts.send(CHANNELS.gamesChanged, this.games)
    return this.games
  }

  requireGame(gameId: string): GameInstall {
    const g = this.games.find((x) => x.id === gameId)
    if (!g) throw new Error('Unknown game')
    return g
  }

  async addGame(input: string): Promise<AddGameResult> {
    const res = await addGame(this.opts.dataPath, input)
    if (res.error || res.games.length === 0) return { error: res.error ?? 'That folder could not be added.' }
    await this.scan()
    const first = res.games[0]!
    return { game: this.games.find((g) => g.id === first.id) ?? first }
  }

  removeGame(gameId: string): GameInstall[] {
    const g = this.requireGame(gameId)
    removeGame(this.opts.dataPath, g)
    this.games = this.games.filter((x) => x.id !== gameId)
    if (this.settings.lastGameId === gameId) this.setSettings({ lastGameId: '' })
    this.opts.send(CHANNELS.gamesChanged, this.games)
    return this.games
  }

  // ---------------------------------------------------------------- catalog

  refreshCatalog(force = false): Promise<Catalog> {
    if (this.refreshing) return this.refreshing
    if (!force && this.catalog.fetchedAt && !this.catalog.offline) {
      const age = Date.now() - Date.parse(this.catalog.fetchedAt)
      if (age >= 0 && age < FRESH_MS) return Promise.resolve(this.catalog)
    }
    this.refreshing = this.doRefresh().finally(() => {
      this.refreshing = null
    })
    return this.refreshing
  }

  private async doRefresh(): Promise<Catalog> {
    const res = await fetchReleases({
      dataPath: this.opts.dataPath,
      appVersion: this.opts.appVersion,
      ...(this.opts.fetchImpl ? { fetchImpl: this.opts.fetchImpl } : {}),
      ...(this.opts.apiBase ? { apiBase: this.opts.apiBase } : {})
    })
    // When the request failed and nothing was cached, keep what the catalog already held.
    const keepOld = res.offline && res.releases.length === 0
    const next = keepOld
      ? { ...this.catalog, offline: true, ...(res.error ? { error: res.error } : {}) }
      : buildCatalog(res.releases, {
          fetchedAt: res.fetchedAt,
          offline: res.offline,
          ...(res.error ? { error: res.error } : {})
        })
    this.catalog = next
    try {
      saveCatalog(this.opts.dataPath, next)
    } catch (err) {
      log('Could not save the catalog:', err)
    }
    this.opts.send(CHANNELS.catalogChanged, next)
    return next
  }

  // ---------------------------------------------------------------- statuses

  async statuses(gameId: string): Promise<ProductStatus[]> {
    const game = this.requireGame(gameId)
    return computeStatuses(game, this.catalog, this.settings, loadState(this.opts.dataPath))
  }

  // ---------------------------------------------------------------- jobs

  private pickRelease(productId: string, version?: string): ReleaseInfo | undefined {
    if (version) return (this.catalog.releases[productId] ?? []).find((r) => r.version === version)
    return latestFor(this.catalog, productId, this.settings.includePrereleases)
  }

  private jobContext(jobId: string, signal: AbortSignal, emit: (p: JobProgress) => void) {
    return {
      jobId,
      dataPath: this.opts.dataPath,
      downloadsPath: this.downloadsPath(),
      keepDownloads: this.settings.keepDownloads,
      signal,
      emit,
      userAgent: `SpokenLauncher/${this.opts.appVersion}`,
      ...(this.opts.fetchImpl ? { fetchImpl: this.opts.fetchImpl } : {}),
      ...(this.opts.ops ? { ops: this.opts.ops } : {}),
      ...(this.opts.isRunning ? { isRunning: this.opts.isRunning } : {}),
      ...(this.opts.backoffMs !== undefined ? { backoffMs: this.opts.backoffMs } : {})
    }
  }

  install(gameId: string, productId: string, options?: InstallOptions): string {
    const game = this.requireGame(gameId)
    const product = productById(productId)
    if (!product) throw new Error('Unknown product')
    const wanted = options?.version
    const release = this.pickRelease(productId, wanted)
    return this.jobs.enqueue({
      gameId,
      productId,
      action: 'install',
      ...(release ? { version: release.version } : {}),
      run: async (ctx) => {
        if (!release) {
          throw new PlainError(
            wanted
              ? `Version ${wanted} of ${product.title} is not in the list of releases.`
              : this.catalog.fetchedAt
                ? `There is no release of ${product.title} to install yet.`
                : 'The list of releases has not been loaded yet. Check your connection, press refresh and try again.'
          )
        }
        await installProduct(game, product, release, this.jobContext(ctx.jobId, ctx.signal, ctx.emit))
      }
    })
  }

  uninstall(gameId: string, productId: string): string {
    const game = this.requireGame(gameId)
    const product = productById(productId)
    if (!product) throw new Error('Unknown product')
    return this.jobs.enqueue({
      gameId,
      productId,
      action: 'uninstall',
      run: async (ctx) => {
        await uninstallProduct(game, product, this.jobContext(ctx.jobId, ctx.signal, ctx.emit))
      }
    })
  }

  cancel(jobId: string): void {
    this.jobs.cancel(jobId)
  }

  // ---------------------------------------------------------------- settings

  getSettings(): Settings {
    return this.settings
  }

  setSettings(patch: Partial<Settings>): Settings {
    const clean: Partial<Settings> = {}
    const merged = sanitizeSettings(patch, this.settings)
    for (const key of Object.keys(patch) as (keyof Settings)[]) {
      if (key in merged) (clean as Record<string, unknown>)[key] = merged[key]
    }
    if (typeof clean.downloadsPath === 'string' && clean.downloadsPath !== '' && !path.isAbsolute(clean.downloadsPath)) {
      delete clean.downloadsPath
    }
    this.settings = { ...this.settings, ...clean }
    try {
      saveSettings(this.opts.dataPath, this.settings)
    } catch (err) {
      log('Could not save the settings:', err)
    }
    return this.settings
  }
}
