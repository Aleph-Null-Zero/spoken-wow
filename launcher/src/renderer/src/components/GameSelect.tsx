import type { ReactNode } from 'react'
import { useGame, useStore } from '../store'
import { S } from '../strings'
import { Select } from './Controls'

/** The game picker shared by the Spoken and Voice packs pages. */
export function GameSelect({ inline = false }: { inline?: boolean }): ReactNode {
  const { state, actions } = useStore()
  const game = useGame()
  return (
    <Select label={S.common.game} value={game?.id ?? ''} onChange={actions.selectGame} inline={inline}>
      {state.games.map((g) => (
        <option key={g.id} value={g.id}>
          {g.label}
          {g.gameVersion ? ` (${g.gameVersion})` : ''}
        </option>
      ))}
    </Select>
  )
}
