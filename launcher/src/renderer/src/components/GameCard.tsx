import type { ReactNode } from 'react'
import type { GameInstall } from '@shared/types'
import { jobBusy, langTag, statusOf } from '../catalog'
import { jobKey, useStore } from '../store'
import { S } from '../strings'
import { JobBar } from './JobBar'
import { IconAlert, IconX } from './Icons'
import { Poster } from './Poster'
import { SpokenStatus } from './SpokenStatus'

export function GameCard({ game }: { game: GameInstall }): ReactNode {
  const { state, actions } = useStore()
  const status = statusOf(state, game.id, 'spoken')
  const spokenState = status?.state ?? 'not-installed'
  const job = state.jobs[jobKey(game.id, 'spoken')]
  const busy = jobBusy(job)

  const voice = (state.statuses[game.id] ?? []).filter((s) => s.productId !== 'spoken' && s.state !== 'not-installed')
  const langs = [
    ...new Set(
      voice.map((s) => state.products.find((p) => p.id === s.productId)?.lang).filter((l): l is string => !!l)
    )
  ]
  const updates = voice.filter((s) => s.state === 'update-available').length

  const primary =
    spokenState === 'not-installed'
      ? { text: S.home.installSpoken, run: () => void actions.install(game.id, 'spoken') }
      : spokenState === 'update-available'
        ? { text: S.home.update, run: () => void actions.install(game.id, 'spoken') }
        : { text: S.home.manage, run: () => actions.navigate('spoken', game.id) }
  const canInstall = game.writable && !!status?.latest

  return (
    <article className="card game-card">
      <button type="button" className="poster-button" aria-label={S.home.openSpoken(game.label)} onClick={() => actions.navigate('spoken', game.id)}>
        <Poster flavor={game.flavor} label={game.label} />
      </button>
      <div className="game-card-body">
        <h2 className="game-name">{game.label}</h2>
        <p className="game-version">{game.gameVersion ? `Game version ${game.gameVersion}` : game.flavorFolder}</p>

        {busy ? (
          <div className="game-job">
            <JobBar job={job} size="sm" onCancel={() => actions.cancel(job.jobId)} />
          </div>
        ) : (
          <>
            <SpokenStatus status={status} />
            {job?.phase === 'error' && (
              <p className="status status-error" role="alert">
                <IconAlert size={15} />
                <span>{job.message ?? S.jobs.error}</span>
                <button type="button" className="icon-btn icon-btn-sm" aria-label={S.common.dismiss} onClick={() => actions.dismissJob(jobKey(game.id, 'spoken'))}>
                  <IconX size={13} />
                </button>
              </p>
            )}
            {job?.phase === 'done' && job.message && <p className="status status-ok-text">{job.message}</p>}
          </>
        )}

        <div className="flags">
          {voice.length > 0 ? (
            <>
              <span className="flag">{S.home.voicePacks(voice.length)}</span>
              {langs.map((l) => (
                <span key={l} className="tag">
                  {langTag(l)}
                </span>
              ))}
            </>
          ) : (
            <span className="flag flag-muted">{S.home.noVoice}</span>
          )}
        </div>
        {updates > 0 && <p className="flag-line">{S.home.packUpdates(updates)}</p>}
        {!game.writable && <p className="flag-line flag-line-red">{S.common.readOnly}</p>}

        <div className="game-actions">
          {!busy && (
            <button
              type="button"
              className="btn btn-primary"
              disabled={primary.text !== S.home.manage && !canInstall}
              onClick={primary.run}
            >
              {primary.text}
            </button>
          )}
          <button type="button" className="btn" onClick={() => actions.navigate('voices', game.id)}>
            {S.home.voicePacksButton}
          </button>
        </div>
      </div>
    </article>
  )
}
