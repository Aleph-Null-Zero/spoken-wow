// How the window's frame differs per platform. No electron imports, so it can be tested.

export interface WindowChrome {
  titleBarStyle: 'hidden' | 'hiddenInset'
  /** false: no system frame at all. Set on Linux so a desktop frame is never drawn next to the page's own buttons. */
  frame?: boolean
  /** macOS only: where the system's red, yellow and green buttons sit. The page's top bar is about 68 px tall. */
  trafficLightPosition?: { x: number; y: number }
  /** Whether the page draws its own minimize, maximize and close buttons. */
  pageDrawsButtons: boolean
}

/**
 * Windows and Linux: no system frame, the page draws the buttons. macOS: the system's three
 * buttons stay, inset into the page's top bar, and the page hides its own.
 */
export function windowChrome(platform: NodeJS.Platform): WindowChrome {
  if (platform === 'darwin') {
    return { titleBarStyle: 'hiddenInset', trafficLightPosition: { x: 22, y: 27 }, pageDrawsButtons: false }
  }
  if (platform === 'linux') return { titleBarStyle: 'hidden', frame: false, pageDrawsButtons: true }
  return { titleBarStyle: 'hidden', pageDrawsButtons: true }
}
