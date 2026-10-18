import { useMemo, useState, type ReactNode } from 'react'
import type { Product, ProductStatus, Section } from '@shared/types'
import { BASE_LANGUAGE, LANGUAGES, languageName } from '@shared/products'
import { jobBusy, latestOf, releasesFor, statusOf } from '../catalog'
import { EmptyGames } from '../components/EmptyGames'
import { GameSelect } from '../components/GameSelect'
import { IconAlert, IconCheck, IconDownload, IconLink, IconX } from '../components/Icons'
import { JobBar } from '../components/JobBar'
import { formatBytes } from '../format'
import { jobKey, useGame, useStore } from '../store'
import { S } from '../strings'

const SECTIONS: Section[] = ['quests', 'zones', 'books']

export function VoicePacksPage(): ReactNode {
  const { state, actions } = useStore()
  const game = useGame()
  const [confirmAll, setConfirmAll] = useState(false)
  const pre = state.settings.includePrereleases

  const voices = useMemo(() => state.products.filter((p) => p.kind === 'voices'), [state.products])
  const released = (p: Product): boolean => releasesFor(state.catalog, p.id, pre).length > 0
  const withRelease = new Set(voices.filter(released).map((p) => p.lang))
  const chosen = state.settings.voiceLanguage || BASE_LANGUAGE
  const chips = LANGUAGES.filter((l) => withRelease.has(l.code) || l.code === chosen)

  if (!game) return <EmptyGames />

  const inLang = voices.filter((p) => p.lang === chosen)
  const statusFor = (p: Product): ProductStatus | undefined => statusOf(state, game.id, p.id)
  const english = chosen === BASE_LANGUAGE

  // Everything of the language that is not installed. English takes the one "All quests"
  // bundle instead of its four split packs.
  const todo = inLang.filter((p) => {
    if (!released(p)) return false
    if (english && p.section === 'quests' && p.pack !== 'all') return false
    const s = statusFor(p)
    if (s?.state === 'linked' || jobBusy(state.jobs[jobKey(game.id, p.id)])) return false
    return (s?.state ?? 'not-installed') === 'not-installed'
  })
  const totalBytes = todo.reduce((sum, p) => sum + (latestOf(state, game.id, p.id)?.assetSize ?? 0), 0)
  const lang = languageName(chosen)
  const installAll = (): void => {
    setConfirmAll(false)
    void (async () => {
      for (const p of todo) await actions.install(game.id, p.id)
    })()
  }

  return (
    <div className="page">
      <div className="page-head">
        <h1>{S.voices.title}</h1>
        <GameSelect inline />
      </div>

      <div className="chips" role="group" aria-label={S.voices.languages}>
        {chips.map((l) => (
          <button
            key={l.code}
            type="button"
            className="chip"
            aria-pressed={chosen === l.code}
            onClick={() => {
              setConfirmAll(false)
              void actions.setSettings({ voiceLanguage: l.code })
            }}
          >
            {l.name}
          </button>
        ))}
      </div>

      {voices.length === 0 || inLang.length === 0 || !inLang.some(released) ? (
        <p className="card pad muted">
          {S.common.notReleased}. {S.voices.nothingReleased}
        </p>
      ) : (
        <div className="sections">
          {SECTIONS.map((section) => {
            const all = inLang.filter((p) => p.section === section)
            const some = all.filter(released)
            const rows = some.length > 0 ? some : all.slice(0, 1)
            if (rows.length === 0) return null
            const bundle = rows.filter((p) => p.pack === 'all' || p.pack === undefined)
            const split = rows.filter((p) => p.pack && p.pack !== 'all')
            const meta = S.voices.sections[section]
            return (
              <section key={section} className="card section" aria-labelledby={`sec-${section}`}>
                <header className="section-head">
                  <h2 id={`sec-${section}`}>{meta.title}</h2>
                  <p>{meta.text}</p>
                </header>
                <ul className="list">
                  {bundle.map((p) => (
                    <PackRow key={p.id} product={p} gameId={game.id} writable={game.writable} />
                  ))}
                  {split.length > 0 && (
                    <li className="row-label" aria-hidden="true">
                      {S.voices.splitHint}
                    </li>
                  )}
                  {split.map((p) => (
                    <PackRow key={p.id} product={p} gameId={game.id} writable={game.writable} />
                  ))}
                </ul>
              </section>
            )
          })}
        </div>
      )}

      {chips.some((c) => c.code === chosen && withRelease.has(c.code)) && (
        <footer className="install-all">
          {confirmAll ? (
            <div className="confirm confirm-wide" role="alertdialog" aria-label={S.voices.installAll(lang)}>
              <p>{S.voices.confirmAll(todo.length, `~${formatBytes(totalBytes)}`, lang)}</p>
              <div className="confirm-actions">
                <button type="button" className="btn btn-primary" onClick={installAll}>
                  {S.voices.confirmInstall}
                </button>
                <button type="button" className="btn" onClick={() => setConfirmAll(false)}>
                  {S.common.cancel}
                </button>
              </div>
            </div>
          ) : (
            <button type="button" className="btn btn-primary btn-lg" disabled={todo.length === 0 || !game.writable} onClick={() => setConfirmAll(true)}>
              <IconDownload size={18} />
              {todo.length === 0 ? S.voices.allInstalled(lang) : S.voices.installAll(lang)}
            </button>
          )}
        </footer>
      )}
    </div>
  )
}

function packName(p: Product): string {
  if (p.section === 'quests' && p.lang === BASE_LANGUAGE && p.pack) return S.voices.packNames[p.pack]
  return S.voices.sections[p.section ?? 'quests'].title
}

function PackRow({ product, gameId, writable }: { product: Product; gameId: string; writable: boolean }): ReactNode {
  const { state, actions } = useStore()
  const [confirm, setConfirm] = useState(false)
  const status = statusOf(state, gameId, product.id)
  const latest = latestOf(state, gameId, product.id)
  const job = state.jobs[jobKey(gameId, product.id)]
  const busy = jobBusy(job)
  const s = status?.state ?? 'not-installed'
  const present = s !== 'not-installed'

  const badge =
    s === 'up-to-date' ? (
      <span className="badge badge-ok">
        <IconCheck size={13} />
        {S.voices.badge.installed}
      </span>
    ) : s === 'update-available' ? (
      <span className="badge badge-warn">
        <IconAlert size={13} />
        {S.voices.badge.update}
      </span>
    ) : s === 'linked' ? (
      <span className="badge badge-dev">
        <IconLink size={13} />
        {S.voices.badge.linked}
      </span>
    ) : s === 'ahead' ? (
      <span className="badge badge-ok">{S.voices.badge.ahead}</span>
    ) : s === 'unknown' ? (
      <span className="badge badge-muted">{S.voices.badge.unknown}</span>
    ) : null

  const install = (): void => void actions.install(gameId, product.id)

  let action: ReactNode
  if (busy) {
    action = <JobBar job={job} size="sm" onCancel={() => actions.cancel(job.jobId)} />
  } else if (!latest && !present) {
    action = <span className="muted">{S.common.notReleased}</span>
  } else if (confirm) {
    action = (
      <span className="inline-confirm">
        <span>{S.voices.confirmRemove}</span>
        <button
          type="button"
          className="btn btn-danger btn-sm"
          onClick={() => {
            setConfirm(false)
            void actions.uninstall(gameId, product.id)
          }}
        >
          {S.common.remove}
        </button>
        <button type="button" className="btn btn-sm" onClick={() => setConfirm(false)}>
          {S.common.keep}
        </button>
      </span>
    )
  } else if (s === 'linked') {
    action = null
  } else {
    action = (
      <span className="row-buttons">
        {s === 'not-installed' && (
          <button type="button" className="btn btn-primary btn-sm" disabled={!writable} onClick={install}>
            {S.voices.install}
          </button>
        )}
        {s === 'update-available' && (
          <button type="button" className="btn btn-primary btn-sm" disabled={!writable} onClick={install}>
            {S.voices.update}
          </button>
        )}
        {present && (
          <button type="button" className="btn btn-sm" disabled={!writable} onClick={() => setConfirm(true)}>
            {S.common.remove}
          </button>
        )}
      </span>
    )
  }

  return (
    <li className="row pack-row">
      <div className="row-main">
        <span className="row-title">{packName(product)}</span>
        <span className="row-text">
          {latest ? `${formatBytes(latest.assetSize)} · ` : ''}
          {present && status?.installedVersion ? S.voices.installedVersion(status.installedVersion) : S.voices.notInstalled}
          {s === 'update-available' && latest ? ` → ${latest.version}` : ''}
        </span>
        {job?.phase === 'error' && (
          <span className="row-error" role="alert">
            <IconAlert size={14} />
            {job.message ?? S.jobs.error}
            <button type="button" className="link" onClick={job.action === 'uninstall' ? () => void actions.uninstall(gameId, product.id) : install}>
              {S.common.retry}
            </button>
            <button type="button" className="icon-btn icon-btn-sm" aria-label={S.common.dismiss} onClick={() => actions.dismissJob(jobKey(gameId, product.id))}>
              <IconX size={13} />
            </button>
          </span>
        )}
      </div>
      {!busy && badge}
      <div className="row-action">{action}</div>
    </li>
  )
}
