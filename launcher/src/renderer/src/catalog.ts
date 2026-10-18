// Small readers over the snapshot: releases, statuses, flavors, languages.
import type { Catalog, Flavor, JobProgress, ProductStatus, ReleaseInfo } from '@shared/types'
import { compareVersions } from '@shared/version'
import { languageName } from '@shared/products'
import type { State } from './store'

/** The releases of a product the player may see, newest first. */
export function releasesFor(catalog: Catalog, productId: string, includePrereleases: boolean): ReleaseInfo[] {
  const list = (catalog.releases[productId] ?? []).filter((r) => includePrereleases || !r.prerelease)
  return [...list].sort((a, b) => -(compareVersions(a.version, b.version) ?? 0))
}

export function statusOf(state: State, gameId: string, productId: string): ProductStatus | undefined {
  return state.statuses[gameId]?.find((s) => s.productId === productId)
}

/** The newest release for a product on a game: the status's, else the catalog's. */
export function latestOf(state: State, gameId: string, productId: string): ReleaseInfo | undefined {
  return statusOf(state, gameId, productId)?.latest ?? releasesFor(state.catalog, productId, state.settings.includePrereleases)[0]
}

export interface FlavorLook {
  name: string
  /** CSS colours for the poster: [top-left, middle, glow]. */
  from: string
  to: string
  glow: string
}

const LOOKS: Record<Flavor, FlavorLook> = {
  classic_beta: { name: 'Forever', from: '#12706b', to: '#0b2e3b', glow: '#e0b04a' },
  classic_era: { name: 'Classic Era', from: '#8a531f', to: '#33200f', glow: '#f0a24a' },
  anniversary: { name: 'Anniversary', from: '#8a2f4a', to: '#2e1020', glow: '#f2b36a' },
  classic: { name: 'Classic', from: '#7d3b24', to: '#2f1712', glow: '#e8804a' },
  classic_ptr: { name: 'Classic PTR', from: '#5f32a3', to: '#26164a', glow: '#b48bff' },
  retail: { name: 'Retail', from: '#1c5ab0', to: '#0d2650', glow: '#4aa3ff' },
  ptr: { name: 'PTR', from: '#5f32a3', to: '#26164a', glow: '#b48bff' },
  xptr: { name: 'PTR', from: '#5f32a3', to: '#26164a', glow: '#b48bff' },
  beta: { name: 'Beta', from: '#6a2fa0', to: '#2a1450', glow: '#c48bff' },
  unknown: { name: 'World of Warcraft', from: '#3a4a68', to: '#182236', glow: '#8fa6d0' }
}

export const flavorLook = (flavor: Flavor): FlavorLook => LOOKS[flavor] ?? LOOKS.unknown

const TAGS: Record<string, string> = {
  enUS: 'EN',
  deDE: 'DE',
  esES: 'ES',
  esMX: 'MX',
  frFR: 'FR',
  itIT: 'IT',
  ptBR: 'PT',
  ruRU: 'RU',
  koKR: 'KO',
  zhCN: 'ZH-CN',
  zhTW: 'ZH-TW'
}

export const langTag = (code: string): string => TAGS[code] ?? code.toUpperCase()
export { languageName }

type ActiveJob = JobProgress & { phase: 'queued' | 'downloading' | 'verifying' | 'extracting' | 'installing' }

/** A job that is still going: it takes the place of a button. */
export function jobBusy(job: JobProgress | undefined): job is ActiveJob {
  return !!job && job.phase !== 'done' && job.phase !== 'error' && job.phase !== 'cancelled'
}
