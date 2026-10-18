import { contextBridge, ipcRenderer } from 'electron'
import { CHANNELS, type LauncherApi } from '../shared/api'

function listen<T>(channel: string, listener: (value: T) => void): () => void {
  const wrapped = (_event: unknown, value: T): void => listener(value)
  ipcRenderer.on(channel, wrapped)
  return () => ipcRenderer.removeListener(channel, wrapped)
}

const api: LauncherApi = {
  snapshot: () => ipcRenderer.invoke(CHANNELS.snapshot),
  scanGames: () => ipcRenderer.invoke(CHANNELS.scanGames),
  addGame: (path) => ipcRenderer.invoke(CHANNELS.addGame, path),
  removeGame: (gameId) => ipcRenderer.invoke(CHANNELS.removeGame, gameId),
  refreshCatalog: (force) => ipcRenderer.invoke(CHANNELS.refreshCatalog, force),
  statuses: (gameId) => ipcRenderer.invoke(CHANNELS.statuses, gameId),
  install: (gameId, productId, options) => ipcRenderer.invoke(CHANNELS.install, gameId, productId, options),
  uninstall: (gameId, productId) => ipcRenderer.invoke(CHANNELS.uninstall, gameId, productId),
  cancel: (jobId) => ipcRenderer.invoke(CHANNELS.cancel, jobId),
  getSettings: () => ipcRenderer.invoke(CHANNELS.getSettings),
  setSettings: (patch) => ipcRenderer.invoke(CHANNELS.setSettings, patch),
  pickFolder: () => ipcRenderer.invoke(CHANNELS.pickFolder),
  openPath: (path) => ipcRenderer.invoke(CHANNELS.openPath, path),
  openExternal: (url) => ipcRenderer.invoke(CHANNELS.openExternal, url),
  openLogs: () => ipcRenderer.invoke(CHANNELS.openLogs),
  onJob: (l) => listen(CHANNELS.jobProgress, l),
  onGamesChanged: (l) => listen(CHANNELS.gamesChanged, l),
  onCatalogChanged: (l) => listen(CHANNELS.catalogChanged, l),
  onUpdater: (l) => listen(CHANNELS.updaterState, l)
}

contextBridge.exposeInMainWorld('launcher', api)
