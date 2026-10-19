// Turns the GitHub release list into the per-product catalog the window shows.
import path from 'node:path'
import type { Catalog, Product, ReleaseInfo } from '../shared/types'
import { PRODUCTS, versionOfTag } from '../shared/products'
import { compareVersions, isPrerelease } from '../shared/version'
import type { GithubAsset, GithubRelease } from './github'
import { readJsonFile, writeJsonAtomic } from './state'

export function emptyCatalog(): Catalog {
  return { fetchedAt: null, offline: false, releases: {} }
}

function pickAsset(release: GithubRelease, product: Product): GithubAsset | undefined {
  const re = new RegExp(product.assetPattern)
  return (release.assets ?? []).find(
    (a) =>
      a &&
      typeof a.name === 'string' &&
      re.test(a.name) &&
      typeof a.browser_download_url === 'string' &&
      typeof a.size === 'number' &&
      (a.state === undefined || a.state === 'uploaded')
  )
}

function cleanDigest(d: unknown): string | undefined {
  return typeof d === 'string' && /^sha256:[0-9a-f]{64}$/i.test(d) ? d.toLowerCase() : undefined
}

function toInfo(release: GithubRelease, product: Product): ReleaseInfo | null {
  if (release.draft || typeof release.tag_name !== 'string') return null
  const version = versionOfTag(release.tag_name, product.tagPrefix)
  if (!version || compareVersions(version, version) === null) return null
  const asset = pickAsset(release, product)
  if (!asset) return null
  const digest = cleanDigest(asset.digest)
  return {
    productId: product.id,
    tag: release.tag_name,
    version,
    prerelease: release.prerelease === true || isPrerelease(version),
    publishedAt: release.published_at ?? release.created_at ?? '',
    notes: typeof release.body === 'string' ? release.body : '',
    assetName: asset.name,
    assetSize: asset.size,
    assetUrl: asset.browser_download_url,
    ...(digest ? { digest } : {}),
    htmlUrl: typeof release.html_url === 'string' ? release.html_url : ''
  }
}

/** Newest first; at equal versions a stable release comes before a pre-release, then the later date. */
function compareReleases(a: ReleaseInfo, b: ReleaseInfo): number {
  const v = compareVersions(b.version, a.version) ?? 0
  if (v !== 0) return v
  if (a.prerelease !== b.prerelease) return a.prerelease ? 1 : -1
  return b.publishedAt.localeCompare(a.publishedAt)
}

export function buildCatalog(
  releases: GithubRelease[],
  meta: { fetchedAt: string | null; offline?: boolean; error?: string }
): Catalog {
  const out: Record<string, ReleaseInfo[]> = {}
  for (const product of PRODUCTS) {
    const list: ReleaseInfo[] = []
    for (const r of releases) {
      if (!r || typeof r !== 'object') continue
      const info = toInfo(r, product)
      if (info) list.push(info)
    }
    if (list.length > 0) out[product.id] = list.sort(compareReleases)
  }
  return {
    fetchedAt: meta.fetchedAt,
    offline: meta.offline === true,
    ...(meta.error ? { error: meta.error } : {}),
    releases: out
  }
}

/** The newest release of a product; a pre-release only when allowed. */
export function latestFor(catalog: Catalog, productId: string, includePrereleases: boolean): ReleaseInfo | undefined {
  const list = catalog.releases[productId] ?? []
  return list.find((r) => includePrereleases || !(r.prerelease || isPrerelease(r.version)))
}

function catalogFile(dataPath: string): string {
  return path.join(dataPath, 'catalog.json')
}

export function loadCatalog(dataPath: string): Catalog {
  const raw = readJsonFile<Partial<Catalog> | null>(catalogFile(dataPath), null)
  if (!raw || typeof raw !== 'object' || typeof raw.releases !== 'object' || raw.releases === null) return emptyCatalog()
  return {
    fetchedAt: typeof raw.fetchedAt === 'string' ? raw.fetchedAt : null,
    offline: raw.offline === true,
    ...(typeof raw.error === 'string' ? { error: raw.error } : {}),
    releases: raw.releases as Record<string, ReleaseInfo[]>
  }
}

export function saveCatalog(dataPath: string, catalog: Catalog): void {
  writeJsonAtomic(catalogFile(dataPath), catalog)
}
