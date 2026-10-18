// The contract between the window and the main process. The preload exposes `LauncherApi` as
// `window.launcher`; the main process answers each channel.
import type { Catalog, GameInstall, JobProgress, ProductStatus, Settings, Snapshot } from './types'

export const CHANNELS = {
  snapshot: 'launcher:snapshot',
  scanGames: 'launcher:games:scan',
  addGame: 'launcher:games:add',
  removeGame: 'launcher:games:remove',
  refreshCatalog: 'launcher:catalog:refresh',
  statuses: 'launcher:statuses',
  install: 'launcher:install',
  uninstall: 'launcher:uninstall',
  cancel: 'launcher:cancel',
  getSettings: 'launcher:settings:get',
  setSettings: 'launcher:settings:set',
  pickFolder: 'launcher:pick-folder',
  openPath: 'launcher:open-path',
  openExternal: 'launcher:open-external',
  openLogs: 'launcher:open-logs',
  // main -> window
  jobProgress: 'launcher:event:job',
  gamesChanged: 'launcher:event:games',
  catalogChanged: 'launcher:event:catalog',
  updaterState: 'launcher:event:updater'
} as const

export interface AddGameResult {
  /** The install that was added (or already known), or why not. */
  game?: GameInstall
  error?: string
}

export interface InstallOptions {
  /** A version other than the newest, e.g. to go back. */
  version?: string
}

export type UpdaterState =
  | { state: 'idle' }
  | { state: 'checking' }
  | { state: 'available'; version: string }
  | { state: 'downloading'; percent: number }
  | { state: 'ready'; version: string }
  | { state: 'error'; message: string }

export interface LauncherApi {
  /** Everything the window needs to draw its first frame. */
  snapshot(): Promise<Snapshot>
  /** Looks again for WoW installs; returns the list (manual ones kept). */
  scanGames(): Promise<GameInstall[]>
  /** Adds a folder by hand: the game folder, a flavor folder, or an AddOns folder. */
  addGame(path: string): Promise<AddGameResult>
  removeGame(gameId: string): Promise<GameInstall[]>
  /** Asks GitHub for the releases (ETag-cached); `force` skips the cache window. */
  refreshCatalog(force?: boolean): Promise<Catalog>
  /** What is installed and what is new, for each product, on one game. */
  statuses(gameId: string): Promise<ProductStatus[]>
  /** Starts a download and install; the progress comes through `onJob`. Returns the job id. */
  install(gameId: string, productId: string, options?: InstallOptions): Promise<string>
  /** Removes the folders the launcher installed for a product. */
  uninstall(gameId: string, productId: string): Promise<string>
  cancel(jobId: string): Promise<void>
  getSettings(): Promise<Settings>
  setSettings(patch: Partial<Settings>): Promise<Settings>
  /** The system folder picker; null when cancelled. */
  pickFolder(): Promise<string | null>
  openPath(path: string): Promise<void>
  openExternal(url: string): Promise<void>
  openLogs(): Promise<void>

  onJob(listener: (progress: JobProgress) => void): () => void
  onGamesChanged(listener: (games: GameInstall[]) => void): () => void
  onCatalogChanged(listener: (catalog: Catalog) => void): () => void
  onUpdater(listener: (state: UpdaterState) => void): () => void
}
