import type { LauncherApi } from '@shared/api'

let current: LauncherApi | null = null

/** The preload's api, or the fake one when the page runs in a plain browser. */
export async function loadApi(): Promise<LauncherApi> {
  if (current) return current
  if (window.launcher) {
    current = window.launcher
  } else {
    const { createMockApi } = await import('./mock/api')
    current = createMockApi()
  }
  return current
}

export function api(): LauncherApi {
  if (!current) throw new Error('The launcher api is not loaded yet')
  return current
}

/** The text of an error from the main process, without Electron's "Error invoking remote method" prefix. */
export function errorText(e: unknown): string {
  const raw = e instanceof Error ? e.message : String(e)
  return raw.replace(/^Error invoking remote method '[^']+': (?:Error: )?/, '')
}
