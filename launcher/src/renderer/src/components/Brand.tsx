import type { CSSProperties, ReactNode } from 'react'
import type { Flavor } from '@shared/types'
import icon from '../assets/spoken.png'
import artAnniversary from '../assets/art-anniversary.jpg'
import artEra from '../assets/art-era.jpg'
import artForever from '../assets/art-forever.jpg'
import { flavorLook } from '../catalog'

// The art is drawn from the project's own zone icons
// (Zephras Isle, Darkspear Islands, Riverglades), enlarged and blurred; see THIRD_PARTY.md.
const ART: Record<Flavor, string> = {
  classic_beta: artForever,
  classic_era: artEra,
  anniversary: artAnniversary
}

function look(flavor: Flavor): CSSProperties {
  const l = flavorLook(flavor)
  return { '--g-from': l.from, '--g-to': l.to, '--g-glow': l.glow, '--g-art': `url(${ART[flavor]})` } as CSSProperties
}

/** Our own game logo: the game's name in a display face with a gold gradient, over the Spoken emblem. */
export function Wordmark({ flavor, size = 'lg' }: { flavor: Flavor; size?: 'lg' | 'sm' }): ReactNode {
  const l = flavorLook(flavor)
  return (
    <div className={`wordmark wordmark-${size}`} style={{ ...look(flavor), '--wm-len': l.title.length } as CSSProperties} role="img" aria-label={`Spoken ${l.name}`}>
      <img className="wm-emblem" src={icon} alt="" width={64} height={64} />
      <span className="wm-kicker" aria-hidden="true">
        {l.kicker}
      </span>
      <span className="wm-title" aria-hidden="true">
        {l.title}
      </span>
      <span className="wm-rule" aria-hidden="true" />
    </div>
  )
}

/** The small round emblem of a game in the strip. */
export function GameIcon({ flavor }: { flavor: Flavor }): ReactNode {
  return (
    <span className="game-icon" style={look(flavor)} aria-hidden="true">
      <img src={icon} alt="" width={14} height={14} />
    </span>
  )
}

/** The picture of a game card: faded art with the small wordmark over it. */
export function CardArt({ flavor }: { flavor: Flavor }): ReactNode {
  return (
    <div className="card-art" style={look(flavor)}>
      <div className="card-art-img" />
      <Wordmark flavor={flavor} size="sm" />
    </div>
  )
}

/** A wide strip of art for the hero card, fading into the panel on its right. */
export function HeroArt({ flavor }: { flavor: Flavor }): ReactNode {
  return (
    <div className="hero-art" style={look(flavor)} aria-hidden="true">
      <div className="hero-art-img" />
      <img src={icon} alt="" width={72} height={72} />
    </div>
  )
}

/** The key art behind a page: very faded, in the upper left corner only, gone before the content starts. */
export function Backdrop({ flavor, compact = false }: { flavor: Flavor; compact?: boolean }): ReactNode {
  return (
    <div className={`backdrop${compact ? ' backdrop-compact' : ''}`} style={look(flavor)} aria-hidden="true">
      <div className="backdrop-art" />
      <div className="backdrop-glow" />
    </div>
  )
}
