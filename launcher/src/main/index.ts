// Spoken Launcher: main process. No telemetry of any kind: the only network traffic is the GitHub
// release list, the asset downloads and the launcher's own update.
import path from 'node:path'
import { app, BrowserWindow, session, shell } from 'electron'
import { CHANNELS } from '../shared/api'
import { isAllowedExternalUrl } from './external'
import { registerIpc } from './ipc'
import { LauncherService } from './service'
import { initLog, log } from './state'
import { isOurPage as isOurPageUrl, type AppPage } from './trust'
import { startUpdater } from './updater'

app.setName('Spoken Launcher')
if (process.platform === 'win32') app.setAppUserModelId('one.rusty.spoken.launcher')

const BACKGROUND = '#0b0f17'
const DEV_URL = process.env.ELECTRON_RENDERER_URL

let service: LauncherService | null = null
let mainWindow: BrowserWindow | null = null

function broadcast(channel: string, payload: unknown): void {
  for (const win of BrowserWindow.getAllWindows()) {
    if (!win.isDestroyed() && !win.webContents.isDestroyed()) win.webContents.send(channel, payload)
  }
}

function contentSecurityPolicy(): string {
  if (DEV_URL) {
    // The dev server needs inline scripts (React refresh) and a websocket.
    return [
      "default-src 'self'",
      "img-src 'self' data:",
      "style-src 'self' 'unsafe-inline'",
      "script-src 'self' 'unsafe-inline'",
      `connect-src 'self' ws://localhost:* http://localhost:*`
    ].join('; ')
  }
  // The same policy as the meta tag in src/renderer/index.html (script and connect fall back to default-src).
  return ["default-src 'self'", "style-src 'self' 'unsafe-inline'", "img-src 'self' data:"].join('; ')
}

const PAGE: AppPage = { devUrl: DEV_URL, indexHtml: path.join(__dirname, '../renderer/index.html') }

function isOurPage(url: string): boolean {
  return isOurPageUrl(url, PAGE)
}

function setUpSession(): void {
  const csp = contentSecurityPolicy()
  session.defaultSession.webRequest.onHeadersReceived((details, callback) => {
    if (!isOurPage(details.url)) return callback({ responseHeaders: details.responseHeaders })
    callback({ responseHeaders: { ...details.responseHeaders, 'Content-Security-Policy': [csp] } })
  })
  session.defaultSession.setPermissionRequestHandler((_wc, _permission, callback) => callback(false))
  session.defaultSession.setPermissionCheckHandler(() => false)
}

function createWindow(): BrowserWindow {
  const win = new BrowserWindow({
    width: 1180,
    height: 760,
    minWidth: 980,
    minHeight: 620,
    backgroundColor: BACKGROUND,
    show: false,
    title: 'Spoken Launcher',
    autoHideMenuBar: true,
    titleBarStyle: 'hidden',
    titleBarOverlay: { color: BACKGROUND, symbolColor: '#9aa4b5', height: 40 },
    webPreferences: {
      preload: path.join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      webSecurity: true
    }
  })
  win.removeMenu()

  win.once('ready-to-show', () => win.show())
  win.webContents.on('did-fail-load', (_e, code, description) => {
    log(`Window failed to load (${code}): ${description}`)
    if (!win.isDestroyed()) win.show()
  })

  // Links open in the browser, only when they are GitHub's; nothing opens a new window.
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (isAllowedExternalUrl(url)) void shell.openExternal(url)
    return { action: 'deny' }
  })
  // The window shows its own page and nothing else: every other navigation, redirect or frame is blocked.
  const block = (event: { preventDefault: () => void }, url: string): void => {
    if (isOurPage(url)) return
    event.preventDefault()
    if (isAllowedExternalUrl(url)) void shell.openExternal(url)
  }
  win.webContents.on('will-navigate', block)
  win.webContents.on('will-redirect', block)
  win.webContents.on('will-frame-navigate', (details) => block(details, details.url))
  win.webContents.on('will-attach-webview', (event) => event.preventDefault())

  if (DEV_URL) void win.loadURL(DEV_URL)
  else void win.loadFile(PAGE.indexHtml)
  return win
}

if (!app.requestSingleInstanceLock()) {
  app.quit()
} else {
  app.on('second-instance', () => {
    if (!mainWindow || mainWindow.isDestroyed()) return
    if (mainWindow.isMinimized()) mainWindow.restore()
    mainWindow.focus()
  })

  app.on('window-all-closed', () => app.quit())

  // Quitting with a job running: stop it and wait for its rollback first, so the quit (and an
  // update installed on quit) never lands in the middle of swapping folders.
  let quitting = false
  app.on('before-quit', (event) => {
    if (quitting || !service || service.jobs.active().length === 0) return
    quitting = true
    event.preventDefault()
    log('Quit requested while a job is running: stopping it first.')
    void service.jobs
      .cancelAll()
      .catch((err) => log('Stopping jobs failed:', err))
      .finally(() => app.quit())
  })

  void app.whenReady().then(() => {
    const dataPath = app.getPath('userData')
    initLog(dataPath)
    log(`Spoken Launcher ${app.getVersion()} starting (Electron ${process.versions.electron}).`)

    setUpSession()
    service = new LauncherService({ dataPath, appVersion: app.getVersion(), send: broadcast })
    registerIpc(service, PAGE)
    void service.init()

    mainWindow = createWindow()

    if (service.settings.checkOnStart) {
      void service.ready.then(() => service?.refreshCatalog(false)).catch((err) => log('Catalog refresh failed:', err))
      void service.ready.then(() => service?.refreshCommunity(false)).catch((err) => log('Community refresh failed:', err))
    }
    const svc = service
    void startUpdater({
      isPackaged: app.isPackaged,
      autoUpdateLauncher: () => svc.settings.autoUpdateLauncher,
      send: (state) => broadcast(CHANNELS.updaterState, state)
    })
  })
}
