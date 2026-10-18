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
  windowMinimize: 'launcher:window:minimize',
  windowToggleMaximize: 'launcher:window:toggle-maximize',
  windowClose: 'launcher:window:close',
  windowIsMaximized: 'launcher:window:is-maximized',
  // main -> window
  jobProgress: 'launcher:event:job',
  gamesChanged: 'launcher:event:games',
  catalogChanged: 'launcher:event:catalog',
  communityChanged: 'launcher:event:community',
  updaterState: 'launcher:event:updater',
  windowMaximized: 'launcher:event:window-maximized'
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
  /** `url`: where to download it, when this system cannot update the launcher by itself (macOS without signing). */
  | { state: 'available'; version: string; url?: string }
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
  /** The window has no system title bar, so the page draws its own buttons and calls these. */
  windowMinimize(): Promise<void>
  /** Maximizes the window, or puts it back when it is already maximized. */
  windowToggleMaximize(): Promise<void>
  windowClose(): Promise<void>
  windowIsMaximized(): Promise<boolean>

  onJob(listener: (progress: JobProgress) => void): () => void
  onGamesChanged(listener: (games: GameInstall[]) => void): () => void
  onCatalogChanged(listener: (catalog: Catalog) => void): () => void
  onCommunityChanged(listener: (community: CommunityCatalog) => void): () => void
  onUpdater(listener: (state: UpdaterState) => void): () => void
  /** True when the window becomes maximized, false when it is put back. */
  onWindowMaximized(listener: (maximized: boolean) => void): () => void
}
