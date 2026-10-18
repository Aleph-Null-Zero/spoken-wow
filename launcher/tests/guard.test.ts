import fs from 'node:fs'
import path from 'node:path'
import { describe, expect, it } from 'vitest'
import { productById, SPOKEN_FOLDERS } from '../src/shared/products'
import { isAllowedExternalUrl, isAllowedOpenPath } from '../src/main/external'
import {
  allowedFolders,
  canWrite,
  canWriteQuick,
  checkEntryPath,
  ensureFreeSpace,
  isInside,
  isLinked,
  isWowProcess,
  parseTasklist,
  refuseLinked
} from '../src/main/guard'
import { tmpDir, write } from './helpers'

describe('checkEntryPath', () => {
  const allowed = ['Spoken', 'Spoken_Places']
  const cases: [string, boolean, string?][] = [
    ['Spoken/Spoken.toc', true],
    ['Spoken/sub/deep/file.lua', true],
    ['Spoken_Places/', true],
    ['Spoken/', true],
    ['../evil.txt', false],
    ['Spoken/../../evil.txt', false],
    ['Spoken/../Spoken_Places/x', false],
    ['/etc/passwd', false],
    ['/Spoken/x', false],
    ['C:/Windows/x.dll', false],
    ['c:evil', false],
    ['Spoken\\..\\evil.txt', false],
    ['Spoken\\file.lua', false],
    ['Spoken/a\0b', false],
    ['Spoken//x', false],
    ['Spoken/./x', false],
    ['Spoken/x:stream', false],
    ['Spoken/x.', false],
    ['Spoken/x ', false],
    ['Spoken/CON<', false],
    ['spoken/Spoken.toc', false],
    ['WTF/Account/x.lua', false],
    ['Other/Other.toc', false],
    ['README.txt', false],
    ['Spoken', false],
    ['', false]
  ]
  for (const [name, ok] of cases) {
    it(`${ok ? 'accepts' : 'refuses'} ${JSON.stringify(name)}`, () => {
      expect(checkEntryPath(name, allowed).ok).toBe(ok)
    })
  }

  it('splits the path and flags directories', () => {
    const r = checkEntryPath('Spoken/a/b.lua', allowed)
    expect(r).toEqual({ ok: true, segments: ['Spoken', 'a', 'b.lua'], directory: false })
    const d = checkEntryPath('Spoken/a/', allowed)
    expect(d).toEqual({ ok: true, segments: ['Spoken', 'a'], directory: true })
  })
})

describe('allowedFolders', () => {
  it('uses the product folders for a voice pack and the Spoken list for Spoken', () => {
    expect(allowedFolders(productById('zones-audio')!)).toEqual(['SpokenZonesAudio'])
    expect(allowedFolders(productById('quests-audio')!)).toHaveLength(4)
    expect(allowedFolders(productById('spoken')!)).toEqual(SPOKEN_FOLDERS)
  })
})

describe('isInside', () => {
  it('accepts the folder itself and children, refuses siblings and escapes', () => {
    const root = path.resolve('somewhere', 'AddOns')
    expect(isInside(root, root)).toBe(true)
    expect(isInside(root, path.join(root, 'Spoken', 'x'))).toBe(true)
    expect(isInside(root, path.join(root, '..', 'WTF'))).toBe(false)
    expect(isInside(root, `${root}-other`)).toBe(false)
  })
})

describe('isLinked', () => {
  it('is false for a plain folder and a missing path', async () => {
    const dir = tmpDir()
    fs.mkdirSync(path.join(dir, 'real'))
    expect(await isLinked(path.join(dir, 'real'))).toBe(false)
    expect(await isLinked(path.join(dir, 'missing'))).toBe(false)
  })

  it('is true for a junction and for a folder inside a linked parent chain only when it is the link itself', async () => {
    const dir = tmpDir()
    const target = path.join(dir, 'checkout')
    fs.mkdirSync(path.join(target, 'inner'), { recursive: true })
    const link = path.join(dir, 'AddOns-link')
    fs.symlinkSync(target, link, 'junction')
    expect(await isLinked(link)).toBe(true)
    // `inner` is a plain folder that happens to be reached through a junction: it is not itself linked.
    expect(await isLinked(path.join(link, 'inner'))).toBe(false)
  })

  it('refuseLinked throws in plain words', async () => {
    const dir = tmpDir()
    const target = path.join(dir, 't')
    fs.mkdirSync(target)
    fs.symlinkSync(target, path.join(dir, 'Spoken'), 'junction')
    await expect(refuseLinked(path.join(dir, 'Spoken'))).rejects.toThrow(/linked to a development checkout/)
  })
})

describe('disk and write checks', () => {
  it('reports not enough space in plain words', async () => {
    const dir = tmpDir()
    await expect(ensureFreeSpace(dir, 1e18, 'Test (1 EB)')).rejects.toThrow(/Not enough free space/)
    await expect(ensureFreeSpace(dir, 1024)).resolves.toBeUndefined()
  })

  it('canWrite creates and removes a probe file, using the nearest existing parent', async () => {
    const dir = tmpDir()
    expect(await canWrite(path.join(dir, 'Interface', 'AddOns'))).toBe(true)
    expect(fs.readdirSync(dir)).toEqual([])
  })

  it('canWriteQuick checks access and creates nothing', async () => {
    const dir = tmpDir()
    expect(await canWriteQuick(path.join(dir, 'Interface', 'AddOns'))).toBe(true)
    expect(fs.readdirSync(dir)).toEqual([])
    write(path.join(dir, 'file.txt'), 'x')
    expect(await canWriteQuick(path.join(dir, 'file.txt', 'sub'))).toBe(false)
    expect(await canWriteQuick(path.join(dir, 'file.txt'))).toBe(false)
  })

  it('canWrite is false when the nearest existing path is a file', async () => {
    const dir = tmpDir()
    write(path.join(dir, 'file.txt'), 'x')
    expect(await canWrite(path.join(dir, 'file.txt', 'sub'))).toBe(false)
  })
})

describe('running game', () => {
  it('reads process names from tasklist output', () => {
    const out = '"System","4","Services","0","1,000 K"\r\n"Wow.exe","1234","Console","1","2,000,000 K"\r\n"WowClassic.exe","5","Console","1","1 K"\r\n'
    expect(parseTasklist(out)).toEqual(['System', 'Wow.exe', 'WowClassic.exe'])
  })

  it('matches Wow*.exe only', () => {
    for (const n of ['Wow.exe', 'WowClassic.exe', 'WowB.exe', 'WowT.exe', 'WowClassicT.exe', 'WowClassicB.exe', 'wow-64.exe']) {
      expect(isWowProcess(n)).toBe(true)
    }
    for (const n of ['Battle.net.exe', 'Agent.exe', 'Wow.dll', 'notwow.exe', 'Wowhead Client.exe.bak']) {
      expect(isWowProcess(n)).toBe(false)
    }
  })
})

describe('what the window may open', () => {
  it('allows https links on GitHub hosts only', () => {
    expect(isAllowedExternalUrl('https://github.com/rusty-key/spoken-wow/releases')).toBe(true)
    expect(isAllowedExternalUrl('https://raw.githubusercontent.com/a/b/c')).toBe(true)
    expect(isAllowedExternalUrl('https://objects.githubusercontent.com/x')).toBe(true)
    for (const bad of [
      'http://github.com/x',
      'https://evil.com/github.com',
      'https://github.com.evil.com/',
      'https://user:pw@github.com/',
      'https://github.com:8443/',
      'file:///C:/Windows/System32/calc.exe',
      'javascript:alert(1)',
      'ms-msdt:/x',
      'not a url',
      '',
      42,
      null
    ]) {
      expect(isAllowedExternalUrl(bad)).toBe(false)
    }
  })

  it('allows paths inside the known roots only', () => {
    const roots = [path.resolve('x', 'AddOns'), path.resolve('data')]
    expect(isAllowedOpenPath(path.resolve('x', 'AddOns', 'Spoken'), roots)).toBe(true)
    expect(isAllowedOpenPath(path.resolve('data', 'logs'), roots)).toBe(true)
    expect(isAllowedOpenPath(path.resolve('x', 'AddOns', '..', 'WTF'), roots)).toBe(false)
    expect(isAllowedOpenPath(path.resolve('elsewhere'), roots)).toBe(false)
    expect(isAllowedOpenPath('relative/path', roots)).toBe(false)
    expect(isAllowedOpenPath('', roots)).toBe(false)
    expect(isAllowedOpenPath(7, roots)).toBe(false)
  })
})
