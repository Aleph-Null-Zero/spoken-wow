import type { CSSProperties, ReactNode } from 'react'
import type { Flavor } from '@shared/types'
import icon from '../assets/spoken.png'
import { flavorLook } from '../catalog'

function style(flavor: Flavor): CSSProperties {
  const look = flavorLook(flavor)
  return { '--p-from': look.from, '--p-to': look.to, '--p-glow': look.glow } as CSSProperties
}

/** The game art of a card: the Spoken icon over a gradient tinted for the flavor, with its name. */
export function Poster({ flavor, label }: { flavor: Flavor; label: string }): ReactNode {
  const look = flavorLook(flavor)
  return (
    <div className="poster" style={style(flavor)}>
      <div className="poster-glow" />
      <img className="poster-icon" src={icon} alt="" width={80} height={80} />
      <div className="poster-names">
        <span className="poster-game">World of Warcraft</span>
        <span className="poster-flavor">{look.name}</span>
      </div>
      <span className="sr-only">{label}</span>
    </div>
  )
}

/** The small header of the Spoken page's rail. */
export function MiniPoster({ flavor, label, version }: { flavor: Flavor; label: string; version?: string }): ReactNode {
  const look = flavorLook(flavor)
  return (
    <div className="mini-poster" style={style(flavor)}>
      <div className="poster-glow" />
      <img src={icon} alt="" width={56} height={56} />
      <div className="mini-poster-text">
        <span className="poster-flavor">{look.name}</span>
        <span className="mini-poster-sub">{version ? `${label} · ${version}` : label}</span>
      </div>
    </div>
  )
}
