import { useState, type ReactNode } from 'react'
import type { GameInstall } from '@shared/types'
import { releasesFor, statusOf } from '../catalog'
import { HeroArt } from '../components/Brand'
import { EmptyGames } from '../components/EmptyGames'
import { Select } from '../components/Controls'
import { GameCard } from '../components/GameCard'
import { formatDate } from '../format'
import { Markdown } from '../markdown'
import { useGame, useStore, useSupportedGames, type State } from '../store'
import { S } from '../strings'

type Filter = 'all' | 'with' | 'without'
type Sort = 'installed' | 'name'

const hasSpoken = (state: State, g: GameInstall): boolean => (statusOf(state, g.id, 'spoken')?.state ?? 'not-installed') !== 'not-installed'

export function HomePage(): ReactNode {
  const { state, actions } = useStore()
  const games = useSupportedGames()
  const current = useGame()
  const [filter, setFilter] = useState<Filter>('all')
  const [sort, setSort] = useState<Sort>('installed')
  if (games.length === 0) return <EmptyGames />

  const counts = {
    all: games.length,
    with: games.filter((g) => hasSpoken(state, g)).length,
    without: games.filter((g) => !hasSpoken(state, g)).length
  }
  const shown = games
    .filter((g) => filter === 'all' || (filter === 'with') === hasSpoken(state, g))
    .sort((a, b) => {
      if (sort === 'installed') {
        const e = Number(hasSpoken(state, b)) - Number(hasSpoken(state, a))
        if (e) return e
      }
      return a.label.localeCompare(b.label)
    })
  const filters: { id: Filter; label: string }[] = [
    { id: 'all', label: S.home.filterAll },
    { id: 'with', label: S.home.filterWith },
    { id: 'without', label: S.home.filterWithout }
  ]
  const newest = releasesFor(state.catalog, 'spoken', state.settings.includePrereleases)[0]

  return (
    <div className="page scroll">
      <div className="page-inner">
        <div className="page-head">
          <h1>{S.home.title}</h1>
          <div className="pill-row">
            <nav className="pills" aria-label={S.home.filters}>
              {filters.map((f) => (
                <button key={f.id} type="button" className="pill" aria-pressed={filter === f.id} onClick={() => setFilter(f.id)}>
                  {f.label}
                  <span className="pill-count">{counts[f.id]}</span>
                </button>
              ))}
            </nav>
            <Select label={S.home.sort} value={sort} onChange={(v) => setSort(v as Sort)} inline>
              <option value="installed">{S.home.sortInstalled}</option>
              <option value="name">{S.home.sortName}</option>
            </Select>
          </div>
        </div>

        {shown.length > 0 ? (
          <div className="game-grid">
            {shown.map((g) => (
              <GameCard key={g.id} game={g} />
            ))}
          </div>
        ) : (
          <p className="muted">{S.home.noMatch}</p>
        )}

        {newest && (
          <section className="hero" aria-labelledby="whats-new-title">
            <HeroArt flavor={current?.flavor ?? 'classic_beta'} />
            <div className="hero-body">
              <h2 id="whats-new-title" className="eyebrow">
                {S.home.whatsNew}
              </h2>
              <p className="hero-title">
                {newest.version}
                {newest.prerelease && <span className="tag tag-warn">{S.spoken.prerelease}</span>}
                <span className="hero-date">{formatDate(newest.publishedAt)}</span>
              </p>
              <div className="hero-notes">
                <Markdown text={newest.notes || S.spoken.noNotes} />
              </div>
              <button type="button" className="btn btn-block" onClick={() => actions.navigate('spoken', games[0]?.id, 'changelog')}>
                {S.home.readAll}
              </button>
            </div>
          </section>
        )}
      </div>
    </div>
  )
}
