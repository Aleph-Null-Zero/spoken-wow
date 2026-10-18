import fs from 'node:fs'
import path from 'node:path'
import { describe, expect, it } from 'vitest'
import {
  addGame,
  describeFlavorFolder,
  gameIdFor,
  labelFor,
  parseBuildInfo,
  parseFlavorInfo,
  parseProductDb,
  parseRegQuery,
  removeGame,
  resolveGamePath,
  scanGames
} from '../src/main/games'
import { loadState } from '../src/main/state'
import { makeGame, tmpDir, write } from './helpers'

const BUILD_INFO =
  'Branch!STRING:0|Active!DEC:1|Build Key!HEX:16|CDN Key!HEX:16|Version!STRING:0|Product!STRING:0\r\n' +
  'us|1|aaaa|bbbb|11.2.0.62213|wow\r\n' +
  'us|1|cccc|dddd|1.60.1.70450|wow_classic_beta\r\n' +
  'us|1|eeee|ffff|1.15.7.61582|wow_classic_era\r\n'

describe('Blizzard files', () => {
  it('parses .build.info rows by header name', () => {
    const rows = parseBuildInfo(BUILD_INFO)
    expect(rows).toHaveLength(3)
    expect(rows[1]).toMatchObject({ Branch: 'us', Version: '1.60.1.70450', Product: 'wow_classic_beta' })
    expect(parseBuildInfo('')).toEqual([])
  })

  it('parses .flavor.info', () => {
    expect(parseFlavorInfo('Product Flavor!STRING:0\nwow_classic_beta')).toBe('wow_classic_beta')
    expect(parseFlavorInfo('Product Flavor!STRING:0\r\nwow_classic_era\r\n')).toBe('wow_classic_era')
    expect(parseFlavorInfo('')).toBeUndefined()
    expect(parseFlavorInfo('Product Flavor!STRING:0')).toBeUndefined()
  })

  it('labels products', () => {
    const table: [string, string][] = [
      ['wow_classic_beta', 'WoW: Forever'],
      ['wow_classic_era', 'WoW: Classic Era'],
      ['wow_classic', 'WoW: Classic'],
      ['wow', 'WoW: Retail'],
      ['wow_classic_ptr', 'WoW: Classic PTR'],
      ['wow_classic_era_ptr', 'WoW: Classic PTR'],
      ['wow_ptr', 'WoW: Retail PTR'],
      ['wow_beta', 'WoW: Beta'],
      ['something_else', 'WoW'],
      ['', 'WoW']
    ]
    for (const [code, label] of table) expect(labelFor(code)).toBe(label)
  })

  it('makes a stable, case-insensitive 12 digit id', () => {
    const a = gameIdFor('C:\\Program Files (x86)\\World of Warcraft\\_classic_beta_')
    expect(a).toMatch(/^[0-9a-f]{12}$/)
    expect(gameIdFor('c:\\program files (x86)\\world of warcraft\\_CLASSIC_BETA_')).toBe(a)
    expect(gameIdFor('C:\\other')).not.toBe(a)
  })

  it('reads install paths from reg query output and from product.db bytes', () => {
    const reg =
      '\r\nHKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\Blizzard Entertainment\\World of Warcraft\r\n' +
      '    InstallPath    REG_SZ    C:\\Program Files (x86)\\World of Warcraft\\_retail_\\\r\n\r\n'
    expect(parseRegQuery(reg)).toEqual(['C:\\Program Files (x86)\\World of Warcraft\\_retail_\\'])
    const db = Buffer.concat([Buffer.from([0x0a, 0x2a]), Buffer.from('D:\\Games\\World of Warcraft'), Buffer.from([0x12, 0x00, 0xff])])
    expect(parseProductDb(db)).toEqual(['D:\\Games\\World of Warcraft'])
  })
})

describe('describeFlavorFolder', () => {
  it('reads product and version for a flavor folder', async () => {
    const base = tmpDir()
    const g = await makeGame(base)
    expect(g).toMatchObject({
      flavor: 'classic_beta',
      flavorFolder: '_classic_beta_',
      product: 'wow_classic_beta',
      label: 'WoW: Forever',
      gameVersion: '1.60.1.70450',
      source: 'manual',
      writable: true
    })
    expect(g.addOnsPath).toBe(path.join(g.root, 'Interface', 'AddOns'))
    expect(g.id).toBe(gameIdFor(g.root))
  })

  it('writes nothing into the game folder while scanning', async () => {
    const base = tmpDir()
    const g = await makeGame(base)
    const snapshot = (): string[] => {
      const out: string[] = []
      const walk = (d: string): void => {
        for (const e of fs.readdirSync(d, { withFileTypes: true })) {
          out.push(path.join(d, e.name))
          if (e.isDirectory()) walk(path.join(d, e.name))
        }
      }
      walk(base)
      return out.sort()
    }
    const before = snapshot()
    await describeFlavorFolder(g.root, 'auto')
    await scanGames(tmpDir(), { autoPaths: [path.dirname(g.root)] })
    expect(snapshot()).toEqual(before)
  })

  it('is writable when only the Interface folder is missing, and not when a file is in the way', async () => {
    const base = tmpDir()
    const g = await makeGame(base)
    fs.rmSync(path.join(g.root, 'Interface'), { recursive: true })
    fs.mkdirSync(path.join(g.root, 'WTF'), { recursive: true })
    expect((await describeFlavorFolder(g.root, 'auto'))!.writable).toBe(true)
    write(path.join(g.root, 'Interface'), 'a file')
    expect((await describeFlavorFolder(g.root, 'auto'))!.writable).toBe(false)
  })

  it('picks the build.info row of its own product', async () => {
    const base = tmpDir()
    const root = path.join(base, 'World of Warcraft')
    write(path.join(root, '.build.info'), BUILD_INFO)
    write(path.join(root, '_classic_era_', '.flavor.info'), 'Product Flavor!STRING:0\nwow_classic_era\n')
    fs.mkdirSync(path.join(root, '_classic_era_', 'Interface'), { recursive: true })
    fs.mkdirSync(path.join(root, '_retail_', 'WTF'), { recursive: true })
    const era = await describeFlavorFolder(path.join(root, '_classic_era_'), 'auto')
    expect(era).toMatchObject({ product: 'wow_classic_era', gameVersion: '1.15.7.61582', label: 'WoW: Classic Era' })
    // No .flavor.info: the product comes from the folder name.
    const retail = await describeFlavorFolder(path.join(root, '_retail_'), 'auto')
    expect(retail).toMatchObject({ product: 'wow', gameVersion: '11.2.0.62213', label: 'WoW: Retail' })
  })

  it('accepts a folder with only a Wow exe, and refuses an empty one', async () => {
    const base = tmpDir()
    write(path.join(base, '_classic_', 'WowClassic.exe'), 'x')
    fs.mkdirSync(path.join(base, '_ptr_'), { recursive: true })
    expect(await describeFlavorFolder(path.join(base, '_classic_'), 'auto')).not.toBeNull()
    expect(await describeFlavorFolder(path.join(base, '_ptr_'), 'auto')).toBeNull()
    expect(await describeFlavorFolder(path.join(base, 'missing'), 'auto')).toBeNull()
  })

  it('has no gameVersion when build.info has no row for it', async () => {
    const base = tmpDir()
    const g = await makeGame(base, { product: 'wow_classic_beta' })
    write(path.join(path.dirname(g.root), '.build.info'), BUILD_INFO.replace('wow_classic_beta', 'other'))
    const again = await describeFlavorFolder(g.root, 'auto')
    expect(again?.gameVersion).toBeUndefined()
  })
})

describe('resolveGamePath', () => {
  it('gives every flavor of a game folder, in a fixed order', async () => {
    const base = tmpDir()
    await makeGame(base, { flavorFolder: '_retail_', product: 'wow' })
    await makeGame(base, { flavorFolder: '_classic_era_', product: 'wow_classic_era' })
    const res = await resolveGamePath(path.join(base, 'World of Warcraft'), 'manual')
    expect(res.error).toBeUndefined()
    expect(res.games.map((g) => g.flavorFolder)).toEqual(['_retail_', '_classic_era_'])
  })

  it('resolves a flavor folder, an Interface folder and an AddOns folder to the same install', async () => {
    const base = tmpDir()
    const g = await makeGame(base)
    for (const p of [g.root, path.join(g.root, 'Interface'), g.addOnsPath, `"${g.addOnsPath}"`, `${g.root}${path.sep}`]) {
      const res = await resolveGamePath(p, 'manual')
      expect(res.games.map((x) => x.id)).toEqual([g.id])
    }
  })

  it('says in plain words when it is not a WoW folder', async () => {
    const base = tmpDir()
    fs.mkdirSync(path.join(base, 'Documents'))
    const res = await resolveGamePath(path.join(base, 'Documents'), 'manual')
    expect(res.games).toEqual([])
    expect(res.error).toMatch(/does not look like a World of Warcraft folder/)
    expect((await resolveGamePath(path.join(base, 'nope'), 'manual')).error).toBe('That folder does not exist.')
    expect((await resolveGamePath('   ', 'manual')).error).toBe('Choose a folder first.')
  })
})

describe('scanGames, addGame, removeGame', () => {
  it('finds auto paths, keeps manual ones and hides removed auto ones', async () => {
    const data = tmpDir()
    const base = tmpDir()
    const a = await makeGame(base, { flavorFolder: '_retail_', product: 'wow' })
    const other = tmpDir()
    const b = await makeGame(other)

    let games = await scanGames(data, { autoPaths: [path.join(base, 'World of Warcraft'), path.join(base, 'no-such-folder')] })
    expect(games.map((g) => g.id)).toEqual([a.id])
    expect(games[0]!.source).toBe('auto')

    const added = await addGame(data, path.join(other, 'World of Warcraft'))
    expect(added.games.map((g) => g.id)).toEqual([b.id])
    expect(loadState(data).manualGames).toEqual([b.root])
    games = await scanGames(data, { autoPaths: [path.join(base, 'World of Warcraft')] })
    expect(games.map((g) => g.id).sort()).toEqual([a.id, b.id].sort())
    expect(games.find((g) => g.id === b.id)!.source).toBe('manual')

    // Removing a manual one forgets it; removing an auto one hides it from the scan.
    removeGame(data, games.find((g) => g.id === b.id)!)
    removeGame(data, games.find((g) => g.id === a.id)!)
    expect(loadState(data).manualGames).toEqual([])
    expect(await scanGames(data, { autoPaths: [path.join(base, 'World of Warcraft')] })).toEqual([])
    // Adding it again brings it back.
    await addGame(data, a.root)
    expect((await scanGames(data, { autoPaths: [path.join(base, 'World of Warcraft')] })).map((g) => g.id)).toEqual([a.id])
  })

  it('returns an error string and stores nothing for a bad folder', async () => {
    const data = tmpDir()
    const res = await addGame(data, tmpDir())
    expect(res.error).toBeTruthy()
    expect(loadState(data).manualGames).toEqual([])
  })
})
