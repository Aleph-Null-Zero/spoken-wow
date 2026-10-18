import { useState, type ReactNode } from 'react'
import type { GameInstall } from '@shared/types'
import { releasesFor, statusOf } from '../catalog'
import { EmptyGames } from '../components/EmptyGames'
import { Select } from '../components/Controls'
import { GameCard } from '../components/GameCard'
import { formatDate } from '../format'
import { Markdown } from '../markdown'
import { useStore, type State } from '../store'
import { S } from '../strings'

type Filter = 'all' | 'with' | 'without'
type Sort = 'installed' | 'name'

const hasSpoken = (state: State, g: GameInstall): boolean => (statusOf(state, g.id, 'spoken')?.state ?? 'not-installed') !== 'not-installed'

export function HomePage(): ReactNode {
  const { state, actions } = useStore()
  const [filter, setFilter] = useState<Filter>('all')
  const [sort, setSort] = useState<Sort>('installed')
  if (state.games.length === 0) return <EmptyGames />

  const counts = {
    all: state.games.length,
    with: state.games.filter((g) => hasSpoken(state, g)).length,
    without: state.games.filter((g) => !hasSpoken(state, g)).length
  }
  const shown = state.games
    .filter((g) => filter === 'all' || (filter === 'with') === hasSpoken(state, g))
    .sort((a, b) => {
      if (sort === 'installed') {
        const d = Number(hasSpoken(state, b)) - Number(hasSpoken(state, a))
        if (d) return d
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
    <div className="page">
      <div className="page-head">
        <h1>{S.home.title}</h1>
        <Select label={S.home.sort} value={sort} onChange={(v) => setSort(v as Sort)} inline>
          <option value="installed">{S.home.sortInstalled}</option>
          <option value="name">{S.home.sortName}</option>
        </Select>
      </div>
      <div className="home-layout">
        <nav className="filters" aria-label={S.home.filters}>
          {filters.map((f) => (
            <button key={f.id} type="button" className="filter" aria-pressed={filter === f.id} onClick={() => setFilter(f.id)}>
              <span>{f.label}</span>
              <span className="filter-count">{counts[f.id]}</span>
            </button>
          ))}
        </nav>
        <div className="home-main">
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
            <section className="card whats-new" aria-labelledby="whats-new-title">
              <div className="whats-new-head">
                <h2 id="whats-new-title">{S.home.whatsNew}</h2>
                <span className="version-pill">{newest.version}</span>
                {newest.prerelease && <span className="tag tag-warn">{S.spoken.prerelease}</span>}
                <span className="muted">{formatDate(newest.publishedAt)}</span>
                <button type="button" className="link whats-new-more" onClick={() => actions.navigate('spoken', state.games[0]?.id, 'changelog')}>
                  {S.home.readAll}
                </button>
              </div>
              <div className="whats-new-notes">
                <Markdown text={newest.notes || S.spoken.noNotes} />
              </div>
            </section>
          )}
        </div>
      </div>
    </div>
  )
}
