// The contract between the window and the main process. The preload exposes `LauncherApi` as
// `window.launcher`; the main process answers each channel.
import type { Catalog, CommunityCatalog, GameInstall, JobProgress, ProductStatus, Settings, Snapshot } from './types'

export const CHANNELS = {
  snapshot: 'launcher:snapshot',
  scanGames: 'launcher:games:scan',
  addGame: 'launcher:games:add',
  removeGame: 'launcher:games:remove',
  refreshCatalog: 'launcher:catalog:refresh',
  refreshCommunity: 'launcher:community:refresh',
  statuses: 'launcher:statuses',
  install: 'launcher:install',
  uninstall: 'launcher:uninstall',
  cancel: 'launcher:cancel',
  setSettings: 'launcher:settings:set',
  pickFolder: 'launcher:pick-folder',
  openPath: 'launcher:open-path',
  openExternal: 'launcher:open-external',
  openLogs: 'launcher:open-logs',
  checkLauncherUpdate: 'launcher:updater:check',
  clearDownloads: 'launcher:downloads:clear',
  // main -> window
  jobProgress: 'launcher:event:job',
  gamesChanged: 'launcher:event:games',
  catalogChanged: 'launcher:event:catalog',
  communityChanged: 'launcher:event:community',
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
  /** Put the installed version back: the same download and install, over what is there. Ignores `version`. */
  repair?: boolean
}

export interface ClearDownloadsResult {
  /** Zip and part files deleted from the downloads folder. */
  files: number
  bytes: number
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
  /** Reads the community registry (ETag-cached). A pack installs, updates and uninstalls through
   *  the ordinary `install`/`uninstall`/`statuses` with the product id `community/<pack id>`. */
  refreshCommunity(force?: boolean): Promise<CommunityCatalog>
  /** What is installed and what is new, for each product, on one game. */
  statuses(gameId: string): Promise<ProductStatus[]>
  /** Starts a download and install; the progress comes through `onJob`. Returns the job id. */
  install(gameId: string, productId: string, options?: InstallOptions): Promise<string>
  /** Removes the folders the launcher installed for a product. */
  uninstall(gameId: string, productId: string): Promise<string>
  cancel(jobId: string): Promise<void>
  setSettings(patch: Partial<Settings>): Promise<Settings>
  /** The system folder picker; null when cancelled. */
  pickFolder(): Promise<string | null>
  openPath(path: string): Promise<void>
  openExternal(url: string): Promise<void>
  openLogs(): Promise<void>
  /** Asks for a newer launcher now. Progress and failures come through `onUpdater`. */
  checkLauncherUpdate(): Promise<void>
  /** Deletes the downloaded zips (and half-finished ones) kept in the downloads folder. Refused while a job runs. */
  clearDownloads(): Promise<ClearDownloadsResult>

  onJob(listener: (progress: JobProgress) => void): () => void
  onGamesChanged(listener: (games: GameInstall[]) => void): () => void
  onCatalogChanged(listener: (catalog: Catalog) => void): () => void
  onCommunityChanged(listener: (community: CommunityCatalog) => void): () => void
  onUpdater(listener: (state: UpdaterState) => void): () => void
}
