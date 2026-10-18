// Spoken Launcher: main process. No telemetry of any kind: the only network traffic is the GitHub
// release list, the asset downloads and the launcher's own update.
import path from 'node:path'
import { app, BrowserWindow, session, shell } from 'electron'
import { CHANNELS } from '../shared/api'
import { isAllowedExternalUrl } from './external'
import { registerIpc } from './ipc'
import { LauncherService } from './service'
import { initLog, log } from './state'
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

function isOurPage(url: string): boolean {
  if (DEV_URL) {
    try {
      return new URL(url).origin === new URL(DEV_URL).origin
    } catch {
      return false
    }
  }
  return url.startsWith('file://')
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
  win.webContents.on('will-navigate', (event, url) => {
    if (isOurPage(url)) return
    event.preventDefault()
    if (isAllowedExternalUrl(url)) void shell.openExternal(url)
  })
  win.webContents.on('will-attach-webview', (event) => event.preventDefault())

  if (DEV_URL) void win.loadURL(DEV_URL)
  else void win.loadFile(path.join(__dirname, '../renderer/index.html'))
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

  void app.whenReady().then(() => {
    const dataPath = app.getPath('userData')
    initLog(dataPath)
    log(`Spoken Launcher ${app.getVersion()} starting (Electron ${process.versions.electron}).`)

    setUpSession()
    service = new LauncherService({ dataPath, appVersion: app.getVersion(), send: broadcast })
    registerIpc(service)
    void service.init()

    mainWindow = createWindow()

    if (service.settings.checkOnStart) {
      void service.ready.then(() => service?.refreshCatalog(false)).catch((err) => log('Catalog refresh failed:', err))
    }
    const svc = service
    void startUpdater({
      isPackaged: app.isPackaged,
      autoUpdateLauncher: () => svc.settings.autoUpdateLauncher,
      send: (state) => broadcast(CHANNELS.updaterState, state)
    })
  })
}
