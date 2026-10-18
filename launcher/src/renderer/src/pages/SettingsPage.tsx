import { useState, type ReactNode } from 'react'
import { api, errorText } from '../api'
import { Switch } from '../components/Controls'
import { useAddGame } from '../components/EmptyGames'
import { IconExternal, IconFolder, IconPlus, IconRefresh } from '../components/Icons'
import { useStore } from '../store'
import { REPO_URL, S, SITE_URL } from '../strings'

export function SettingsPage(): ReactNode {
  const { state, actions } = useStore()
  const { settings } = state
  const { add, scan, error, busy, scanning } = useAddGame()
  const [downloadError, setDownloadError] = useState('')
  const set = (patch: Parameters<typeof actions.setSettings>[0]): void => void actions.setSettings(patch).catch(() => undefined)

  const changeDownloads = async (): Promise<void> => {
    setDownloadError('')
    try {
      const path = await api().pickFolder()
      if (path) await actions.setSettings({ downloadsPath: path })
    } catch (e) {
      setDownloadError(errorText(e))
    }
  }

  return (
    <div className="page page-narrow">
      <div className="page-head">
        <h1>{S.settings.title}</h1>
      </div>

      <section className="card setting-card" aria-labelledby="set-folders">
        <header className="section-head">
          <h2 id="set-folders">{S.settings.folders}</h2>
          <p>{S.settings.foldersText}</p>
        </header>
        {state.games.length === 0 ? (
          <p className="muted pad-x">{S.settings.noFolders}</p>
        ) : (
          <ul className="list">
            {state.games.map((g) => (
              <li key={g.id} className="row">
                <div className="row-main">
                  <span className="row-title">{g.label}</span>
                  <span className="row-text ellipsis" title={g.root}>
                    {g.root}
                  </span>
                </div>
                <span className={`badge ${g.source === 'auto' ? 'badge-muted' : 'badge-info'}`}>{g.source === 'auto' ? S.settings.auto : S.settings.manual}</span>
                <span className="row-buttons">
                  <button type="button" className="btn btn-sm" onClick={() => void api().openPath(g.root)}>
                    <IconFolder size={14} />
                    {S.common.open}
                  </button>
                  {g.source === 'manual' && (
                    <button type="button" className="btn btn-sm" onClick={() => void actions.removeGame(g.id)}>
                      {S.common.remove}
                    </button>
                  )}
                </span>
              </li>
            ))}
          </ul>
        )}
        <div className="setting-actions">
          <button type="button" className="btn btn-primary" onClick={add} disabled={busy}>
            <IconPlus size={16} />
            {S.empty.add}
          </button>
          <button type="button" className="btn" onClick={scan} disabled={scanning} aria-busy={scanning}>
            <IconRefresh size={16} className={scanning ? 'is-spinning' : ''} />
            {S.empty.scan}
          </button>
        </div>
        {error && (
          <p className="text-error pad-x" role="alert">
            {error}
          </p>
        )}
      </section>

      <section className="card setting-card" aria-labelledby="set-updates">
        <header className="section-head">
          <h2 id="set-updates">{S.settings.updates}</h2>
        </header>
        <div className="switches">
          <Switch checked={settings.includePrereleases} onChange={(v) => set({ includePrereleases: v })} label={S.settings.prereleases} text={S.settings.prereleasesText} />
          <Switch checked={settings.checkOnStart} onChange={(v) => set({ checkOnStart: v })} label={S.settings.checkOnStart} text={S.settings.checkOnStartText} />
          <Switch checked={settings.autoUpdateLauncher} onChange={(v) => set({ autoUpdateLauncher: v })} label={S.settings.autoUpdate} text={S.settings.autoUpdateText} />
        </div>
      </section>

      <section className="card setting-card" aria-labelledby="set-downloads">
        <header className="section-head">
          <h2 id="set-downloads">{S.settings.downloads}</h2>
        </header>
        <div className="path-row">
          <div className="row-main">
            <span className="field-label">{S.settings.downloadsFolder}</span>
            <span className={`path ellipsis${settings.downloadsPath ? '' : ' is-default'}`} title={settings.downloadsPath || state.dataPath}>
              {settings.downloadsPath || S.settings.appFolder}
            </span>
          </div>
          <span className="row-buttons">
            <button type="button" className="btn btn-sm" onClick={() => void changeDownloads()}>
              {S.common.change}
            </button>
            <button type="button" className="btn btn-sm" onClick={() => void api().openPath(settings.downloadsPath || state.dataPath)}>
              {S.common.open}
            </button>
            {settings.downloadsPath && (
              <button type="button" className="link" onClick={() => set({ downloadsPath: '' })}>
                {S.settings.useDefault}
              </button>
            )}
          </span>
        </div>
        {downloadError && (
          <p className="text-error pad-x" role="alert">
            {downloadError}
          </p>
        )}
        <div className="switches">
          <Switch checked={settings.keepDownloads} onChange={(v) => set({ keepDownloads: v })} label={S.settings.keepZips} text={S.settings.keepZipsText} />
        </div>
      </section>

      <section className="card setting-card" aria-labelledby="set-about">
        <header className="section-head">
          <h2 id="set-about">{S.settings.about}</h2>
        </header>
        <dl className="about">
          <dt>{S.settings.version}</dt>
          <dd>{state.appVersion || '-'}</dd>
          <dt>{S.settings.dataPath}</dt>
          <dd className="ellipsis" title={state.dataPath}>
            {state.dataPath || '-'}
          </dd>
        </dl>
        <div className="setting-actions">
          <button type="button" className="btn" onClick={() => void api().openLogs()}>
            <IconFolder size={16} />
            {S.settings.openLogs}
          </button>
          <button type="button" className="btn" onClick={() => void api().openExternal(REPO_URL)}>
            <IconExternal size={16} />
            {S.settings.repository}
          </button>
          <button type="button" className="btn" onClick={() => void api().openExternal(SITE_URL)}>
            <IconExternal size={16} />
            {S.settings.site}
          </button>
        </div>
      </section>
    </div>
  )
}
