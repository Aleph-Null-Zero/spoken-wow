import type { ReactNode } from 'react'
import { useGame, useStore, useSupportedGames } from '../store'
import { S } from '../strings'
import { Select } from './Controls'

/** The game picker shared by the Spoken, Voice packs and Community pages. */
export function GameSelect({ inline = false }: { inline?: boolean }): ReactNode {
  const { actions } = useStore()
  const game = useGame()
  const games = useSupportedGames()
  return (
    <Select label={S.common.game} value={game?.id ?? ''} onChange={actions.selectGame} inline={inline}>
      {games.map((g) => (
        <option key={g.id} value={g.id}>
          {g.label}
          {g.gameVersion ? ` (${g.gameVersion})` : ''}
        </option>
      ))}
    </Select>
  )
}
