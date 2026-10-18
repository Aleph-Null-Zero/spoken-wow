// What the window may ask the main process to open. No electron imports, so it can be tested.
import path from 'node:path'
import { isInside } from './guard'

const EXTERNAL_HOSTS = new Set(['github.com', 'raw.githubusercontent.com', 'objects.githubusercontent.com'])

/** Only plain https links to GitHub's own hosts: no other scheme, no credentials, no odd port. */
export function isAllowedExternalUrl(value: unknown): boolean {
  if (typeof value !== 'string' || value.length > 2048) return false
  let u: URL
  try {
    u = new URL(value)
  } catch {
    return false
  }
  return u.protocol === 'https:' && EXTERNAL_HOSTS.has(u.hostname) && u.username === '' && u.password === '' && (u.port === '' || u.port === '443')
}

/** A path inside one of the folders the window may open in Explorer. */
export function isAllowedOpenPath(value: unknown, roots: readonly string[]): boolean {
  if (typeof value !== 'string' || value === '' || value.includes('\0') || value.length > 2048) return false
  if (!path.isAbsolute(value)) return false
  return roots.some((r) => r !== '' && isInside(r, value))
}
