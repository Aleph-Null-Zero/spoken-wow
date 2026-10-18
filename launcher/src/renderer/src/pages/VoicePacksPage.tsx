import { useMemo, useState, type ReactNode } from 'react'
import type { Product, ProductStatus, Section } from '@shared/types'
import { BASE_LANGUAGE, LANGUAGES, languageName } from '@shared/products'
import { jobBusy, latestOf, releasesFor, statusOf } from '../catalog'
import { NoGame } from '../components/EmptyGames'
import { GameSelect } from '../components/GameSelect'
import { IconDownload } from '../components/Icons'
import { PackRow } from '../components/PackRow'
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

  if (!game) return <NoGame />

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
                    <VoiceRow key={p.id} product={p} gameId={game.id} writable={game.writable} />
                  ))}
                  {split.length > 0 && (
                    <li className="row-label" aria-hidden="true">
                      {S.voices.splitHint}
                    </li>
                  )}
                  {split.map((p) => (
                    <VoiceRow key={p.id} product={p} gameId={game.id} writable={game.writable} />
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

function VoiceRow({ product, gameId, writable }: { product: Product; gameId: string; writable: boolean }): ReactNode {
  const { state } = useStore()
  const status = statusOf(state, gameId, product.id)
  const latest = latestOf(state, gameId, product.id)
  const s = status?.state ?? 'not-installed'
  const present = s !== 'not-installed'
  return (
    <PackRow
      gameId={gameId}
      productId={product.id}
      writable={writable}
      released={!!latest}
      title={packName(product)}
      text={
        <>
          {latest ? `${formatBytes(latest.assetSize)} · ` : ''}
          {present && status?.installedVersion ? S.voices.installedVersion(status.installedVersion) : S.voices.notInstalled}
          {s === 'update-available' && latest ? ` → ${latest.version}` : ''}
        </>
      }
    />
  )
}
