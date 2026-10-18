// The launcher's own update, through electron-updater's generic provider. The feed is a release
// tagged `launcher-latest` whose assets (latest.yml and the installer) each launcher release
// replaces, so the repo's other releases (spoken/, *-audio/) never get in the way.
// Does nothing when the app is not packaged or the player switched it off; it never throws.
import type { UpdaterState } from '../shared/api'
import { log } from './state'

export const FEED_URL = 'https://github.com/rusty-key/spoken-wow/releases/download/launcher-latest'

export interface UpdaterOptions {
  isPackaged: boolean
  autoUpdateLauncher: () => boolean
  send: (state: UpdaterState) => void
}

type Updater = (typeof import('electron-updater'))['autoUpdater']

let opts: UpdaterOptions | null = null
let updater: Updater | null = null
let last: UpdaterState = { state: 'idle' }
/** The check in progress was started by the player, not by the launcher on its own. */
let userTriggered = false

export function updaterState(): UpdaterState {
  return last
}

function publish(state: UpdaterState): void {
  last = state
  try {
    opts?.send(state)
  } catch (err) {
    log('Updater state not sent:', err)
  }
}

/** A failed check is only shown when the player asked for it (or a download had begun); otherwise it is logged and the state goes back to idle. */
function failed(reason: unknown): void {
  log('Launcher update failed:', reason)
  if (userTriggered || last.state === 'downloading') {
    publish({ state: 'error', message: 'Could not check for a newer launcher. Check your connection and try again.' })
  } else publish({ state: 'idle' })
}

async function load(): Promise<Updater | null> {
  if (updater) return updater
  const mod = await import('electron-updater')
  const u = mod.autoUpdater ?? (mod as unknown as { default?: typeof mod }).default?.autoUpdater
  if (!u) return null
  u.setFeedURL({ provider: 'generic', url: FEED_URL })
  u.autoDownload = true
  u.autoInstallOnAppQuit = true
  u.logger = {
    info: (m?: unknown) => log('updater:', m),
    warn: (m?: unknown) => log('updater warn:', m),
    error: (m?: unknown) => log('updater error:', m),
    debug: () => undefined
  }
  u.on('checking-for-update', () => publish({ state: 'checking' }))
  u.on('update-available', (info) => publish({ state: 'available', version: String(info.version) }))
  u.on('update-not-available', () => publish({ state: 'idle' }))
  u.on('download-progress', (p) => publish({ state: 'downloading', percent: Math.round(p.percent) }))
  u.on('update-downloaded', (info) => publish({ state: 'ready', version: String(info.version) }))
  u.on('error', failed)
  updater = u
  return u
}

async function check(byPlayer: boolean): Promise<void> {
  userTriggered = byPlayer
  try {
    const u = await load()
    if (!u) return failed('electron-updater has no autoUpdater')
    await u.checkForUpdates()
  } catch (err) {
    failed(err)
  }
}

/** Called once at start: checks when the player has not switched it off and the app is installed. */
export async function startUpdater(options: UpdaterOptions): Promise<void> {
  opts = options
  publish({ state: 'idle' })
  if (!options.isPackaged || !options.autoUpdateLauncher()) return
  await check(false)
}

/** A check the player asked for: failures are reported as `error`. Not wired to a channel yet. */
export async function checkForLauncherUpdate(): Promise<void> {
  if (!opts) return
  if (!opts.isPackaged) {
    publish({ state: 'error', message: 'The launcher can only update itself when it is installed.' })
    return
  }
  await check(true)
}
