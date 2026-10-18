import type { ReactNode } from 'react'
import icon from '../assets/spoken.png'
import { formatTime } from '../format'
import { useGame, useStore, useSupportedGames, type Page } from '../store'
import { S } from '../strings'
import { flavorLook } from '../catalog'
import { GameIcon } from './Brand'
import { IconGear, IconPlus, IconRefresh } from './Icons'

const TABS: { page: Page; label: string }[] = [
  { page: 'home', label: S.tabs.home },
  { page: 'spoken', label: S.tabs.spoken },
  { page: 'voices', label: S.tabs.voices },
  { page: 'community', label: S.tabs.community }
]

export function TopBar(): ReactNode {
  const { state, actions } = useStore()
  const { catalog } = state
  const tip = state.refreshing
    ? S.common.loading
    : catalog.offline
      ? S.refresh.offline
      : catalog.fetchedAt
        ? S.refresh.last(formatTime(catalog.fetchedAt))
        : S.refresh.idle
  return (
    <header className="topbar">
      <button type="button" className="brand" aria-label={`${S.appName}: ${S.tabs.home}`} onClick={() => actions.navigate('home')}>
        <img src={icon} alt="" width={30} height={30} />
      </button>
      <nav className="tabs-main" aria-label="Main">
        {TABS.map((t) => (
          <button key={t.page} type="button" className="tab" aria-current={state.page === t.page ? 'page' : undefined} onClick={() => actions.navigate(t.page)}>
            {t.label}
          </button>
        ))}
      </nav>
      <div className="topbar-right">
        <button
          type="button"
          className={`icon-btn${state.refreshing ? ' is-spinning' : ''}`}
          data-tip={tip}
          aria-label={`${S.refresh.label}. ${tip}`}
          aria-busy={state.refreshing}
          disabled={state.refreshing}
          onClick={() => void actions.refresh()}
        >
          <IconRefresh size={18} />
        </button>
        {state.appVersion && <span className="topbar-version">v{state.appVersion}</span>}
        <button type="button" className="tab tab-gear" aria-current={state.page === 'settings' ? 'page' : undefined} onClick={() => actions.navigate('settings')}>
          <IconGear size={16} />
          {S.tabs.settings}
        </button>
      </div>
    </header>
  )
}

/** The games as icon tiles under the top bar; the one the game pages show is underlined. */
export function GamesStrip(): ReactNode {
  const { state, actions } = useStore()
  const games = useSupportedGames()
  const game = useGame()
  if (!state.ready || state.page === 'settings') return null
  const onGamePage = state.page === 'spoken' || state.page === 'voices' || state.page === 'community'
  return (
    <nav className="strip" aria-label={S.home.title}>
      <span className="strip-label">{S.home.title}</span>
      {games.map((g) => {
        const active = onGamePage && g.id === game?.id
        return (
          <button
            key={g.id}
            type="button"
            className="strip-tile"
            aria-label={g.label}
            aria-current={active ? 'true' : undefined}
            onClick={() => {
              actions.selectGame(g.id)
              if (!onGamePage) actions.navigate('spoken', g.id)
            }}
          >
            <GameIcon flavor={g.flavor} />
            <span className="strip-tip" aria-hidden="true">
              <small>{flavorLook(g.flavor).kicker}</small>
              <span>{flavorLook(g.flavor).title}</span>
            </span>
          </button>
        )
      })}
      <button type="button" className="strip-tile strip-add" aria-label={S.strip.add} onClick={() => actions.navigate('settings')}>
        <IconPlus size={18} />
        <span className="strip-tip" aria-hidden="true">
          {S.strip.add}
        </span>
      </button>
    </nav>
  )
}

export function Banners(): ReactNode {
  const { state } = useStore()
  const { updater, catalog } = state
  return (
    <>
      {catalog.offline && (
        <div className="banner banner-warn" role="status">
          {S.banners.offline}
        </div>
      )}
      {updater.state === 'ready' && (
        <div className="banner banner-info" role="status">
          {S.banners.updateReady(updater.version)}
        </div>
      )}
      {updater.state === 'downloading' && (
        <div className="banner banner-info" role="status">
          {S.banners.updating(Math.round(updater.percent))}
        </div>
      )}
    </>
  )
}
