// The launcher's logic without electron: what ipc.ts exposes to the window. Holds the game list,
// the settings and the catalog, and runs jobs.
import path from 'node:path'
import { CHANNELS, type AddGameResult, type ClearDownloadsResult, type InstallOptions } from '../shared/api'
import { isSupportedFlavor, type Catalog, type CommunityCatalog, type GameInstall, type JobProgress, type Product, type ProductStatus, type ReleaseInfo, type Settings, type Snapshot } from '../shared/types'
import { PRODUCTS } from '../shared/products'
import { buildCatalog, latestFor, loadCatalog, saveCatalog } from './catalog'
import { COMMUNITY_PREFIX, communityProduct, communityRelease, fetchCommunity, isCommunityProductId, loadCommunity, saveCommunity } from './community'
import { PlainError } from './errors'
import { checkDownloadsPath } from './guard'
import { cleanLeftovers, clearDownloads } from './cleanup'
import { addGame, notSupportedMessage, removeGame, scanGames } from './games'
import { fetchReleases } from './github'
import { installProduct, recoverInterrupted, uninstallProduct, type FsOps } from './install'
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
  /** Replaces the community registry url (tests). */
  communityUrl?: string
}

/** A catalog fetched less than this long ago is not fetched again unless forced. */
const FRESH_MS = 5 * 60 * 1000

export class LauncherService {
  games: GameInstall[] = []
  settings: Settings
  catalog: Catalog
  readonly jobs: JobManager
  private refreshing: Promise<Catalog> | null = null
  private refreshingCommunity: Promise<CommunityCatalog> | null = null
  community: CommunityCatalog
  /** Settles when the first scan is done; handlers wait for it. Never rejects. */
  ready: Promise<void> = Promise.resolve()

  constructor(private opts: ServiceOptions) {
    this.settings = loadSettings(opts.dataPath)
    this.catalog = loadCatalog(opts.dataPath)
    this.community = loadCommunity(opts.dataPath)
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
    this.ready = this.scan()
      .then(async () => {
        // A swap cut short by a crash is undone first, then every leftover is cleared.
        for (const game of this.games) {
          const failed = await recoverInterrupted(game)
          if (failed.length > 0) log(`Could not restore ${failed.join(', ')} on ${game.label}; the backup is kept.`)
        }
        await cleanLeftovers(this.games, this.downloadsPath())
      })
      .then(
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
      community: this.community,
      products: PRODUCTS,
      appVersion: this.opts.appVersion,
      dataPath: this.opts.dataPath,
      platform: process.platform === 'darwin' ? 'darwin' : process.platform === 'win32' ? 'win32' : 'linux'
    }
  }

  // ---------------------------------------------------------------- games

  async scan(): Promise<GameInstall[]> {
    this.games = await scanGames(this.opts.dataPath, this.opts.autoPaths ? { autoPaths: this.opts.autoPaths } : {})
    // The game last looked at may be gone, or may be one an earlier run listed that no longer is.
    if (this.settings.lastGameId && !this.games.some((g) => g.id === this.settings.lastGameId)) this.setSettings({ lastGameId: '' })
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

  // ---------------------------------------------------------------- community

  refreshCommunity(force = false): Promise<CommunityCatalog> {
    if (this.refreshingCommunity) return this.refreshingCommunity
    if (!force && this.community.fetchedAt && !this.community.offline) {
      const age = Date.now() - Date.parse(this.community.fetchedAt)
      if (age >= 0 && age < FRESH_MS) return Promise.resolve(this.community)
    }
    this.refreshingCommunity = this.doRefreshCommunity().finally(() => {
      this.refreshingCommunity = null
    })
    return this.refreshingCommunity
  }

  private async doRefreshCommunity(): Promise<CommunityCatalog> {
    const next = await fetchCommunity({
      dataPath: this.opts.dataPath,
      appVersion: this.opts.appVersion,
      ...(this.opts.fetchImpl ? { fetchImpl: this.opts.fetchImpl } : {}),
      ...(this.opts.communityUrl ? { url: this.opts.communityUrl } : {})
    })
    this.community = next
    try {
      saveCommunity(this.opts.dataPath, next)
    } catch (err) {
      log('Could not save the community list:', err)
    }
    this.opts.send(CHANNELS.communityChanged, next)
    return next
  }

  /** The official table plus the registry's packs. */
  private allProducts(): Product[] {
    return [...PRODUCTS, ...this.community.packs.map((p) => communityProduct(p))]
  }

  /** The catalog with the registry's packs as one release each. */
  private effectiveCatalog(): Catalog {
    const releases = { ...this.catalog.releases }
    for (const p of this.community.packs) releases[COMMUNITY_PREFIX + p.id] = [communityRelease(p)]
    return { ...this.catalog, releases }
  }

  private findProduct(productId: string): Product | undefined {
    return this.allProducts().find((p) => p.id === productId)
  }

  // ---------------------------------------------------------------- statuses

  async statuses(gameId: string): Promise<ProductStatus[]> {
    const game = this.requireGame(gameId)
    const state = loadState(this.opts.dataPath)
    const products = this.allProducts()
    // A pack installed earlier and since removed from the registry still shows, so it can be removed.
    for (const id of Object.keys(state.installs[gameId] ?? {})) {
      if (isCommunityProductId(id) && !products.some((p) => p.id === id)) {
        products.push(communityProduct({ id: id.slice(COMMUNITY_PREFIX.length) }))
      }
    }
    return computeStatuses(game, this.effectiveCatalog(), this.settings, state, products)
  }

  // ---------------------------------------------------------------- jobs

  private pickRelease(productId: string, version?: string): ReleaseInfo | undefined {
    const catalog = this.effectiveCatalog()
    if (version) return (catalog.releases[productId] ?? []).find((r) => r.version === version)
    return latestFor(catalog, productId, this.settings.includePrereleases || productId.startsWith(COMMUNITY_PREFIX))
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

  /** The release of the version that is installed, for a repair. */
  private async releaseToRepair(gameId: string, product: Product): Promise<ReleaseInfo> {
    const status = (await this.statuses(gameId)).find((s) => s.productId === product.id)
    if (!status || status.installedFolders.length === 0) throw new PlainError(`${product.title} is not installed, so there is nothing to repair. Install it instead.`)
    const version = status.installedVersion
    const release = version ? this.pickRelease(product.id, version) : undefined
    if (!release) {
      throw new PlainError(
        version
          ? `Version ${version} of ${product.title} is no longer in the list of releases, so it cannot be put back. Update it instead.`
          : `The installed version of ${product.title} is not known, so it cannot be put back. Update it instead.`
      )
    }
    return release
  }

  install(gameId: string, productId: string, options?: InstallOptions): string {
    const game = this.requireGame(gameId)
    const product = this.findProduct(productId)
    if (!product) throw new Error('Unknown product')
    const refused = isSupportedFlavor(game.flavor) ? null : notSupportedMessage(game.flavorFolder)
    const repair = options?.repair === true
    const wanted = repair ? undefined : options?.version
    const release = repair ? undefined : this.pickRelease(productId, wanted)
    return this.jobs.enqueue({
      gameId,
      productId,
      action: repair ? 'repair' : 'install',
      ...(release ? { version: release.version } : {}),
      run: async (ctx) => {
        if (refused) throw new PlainError(refused)
        if (repair) {
          const again = await this.releaseToRepair(game.id, product)
          await installProduct(game, product, again, { ...this.jobContext(ctx.jobId, ctx.signal, ctx.emit), repair: true })
          return
        }
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
    let product = this.findProduct(productId)
    // A community pack that left the registry can still be removed.
    if (!product && isCommunityProductId(productId)) product = communityProduct({ id: productId.slice(COMMUNITY_PREFIX.length) })
    if (!product) throw new Error('Unknown product')
    const target = product
    const refused = isSupportedFlavor(game.flavor) ? null : notSupportedMessage(game.flavorFolder)
    return this.jobs.enqueue({
      gameId,
      productId,
      action: 'uninstall',
      run: async (ctx) => {
        if (refused) throw new PlainError(refused)
        await uninstallProduct(game, target, this.jobContext(ctx.jobId, ctx.signal, ctx.emit))
      }
    })
  }

  /** Deletes the kept zips; not while a download or install runs. */
  async clearDownloads(): Promise<ClearDownloadsResult> {
    if (this.jobs.active().length > 0) throw new PlainError('Wait for the running downloads and installs to finish first.')
    return clearDownloads(this.downloadsPath())
  }

  cancel(jobId: string): void {
    this.jobs.cancel(jobId)
  }

  // ---------------------------------------------------------------- settings

  setSettings(patch: Partial<Settings>): Settings {
    const clean: Partial<Settings> = {}
    const merged = sanitizeSettings(patch, this.settings)
    for (const key of Object.keys(patch) as (keyof Settings)[]) {
      if (key in merged) (clean as Record<string, unknown>)[key] = merged[key]
    }
    if (typeof clean.downloadsPath === 'string') {
      const problem = checkDownloadsPath(clean.downloadsPath, this.games)
      if (problem) throw new PlainError(problem)
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
