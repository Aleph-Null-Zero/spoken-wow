# Spoken Launcher: plan

A small Windows app that installs and updates Spoken and its voice packs. Open it, see what is
installed and what is new, press a button. No account, no login, no store.

Built from scratch. The AI VoiceOver launcher was looked at for what it offers (game list,
per-game addon page, voice-pack browser, "in development" list, patch notes), not for its code.
This one keeps the parts a player needs and drops the rest (Patreon login, YouTube, collector,
reports, CurseForge catalog, other addons).

## What it does

1. Finds the World of Warcraft installs Spoken runs on (Forever, Classic Era, Anniversary) and lets
   the player add a folder by hand. Retail, Classic, the PTRs and betas are never listed.
2. For each install, shows whether Spoken is installed, which version, and whether a newer one
   exists on GitHub.
3. Installs, updates, repairs and removes Spoken (one zip: Spoken and its modules).
4. Lists the voice packs by language (Quests, Places, Readables), with sizes, and installs,
   updates and removes them. Packs are 0.3 to 1.5 GB, so downloads resume and show progress.
5. Shows what is new (the release notes) before updating.
6. Keeps itself up to date.

It never touches `WTF`, saved variables, or any folder it did not install.

## Where the files come from

GitHub Releases of `rusty-key/spoken-wow` (public, no token). Product tags, from
`scripts/lib/packs.mjs`:

| Product | Tag | Asset | Folders |
| --- | --- | --- | --- |
| Spoken | `spoken/vX.Y.Z` | `Spoken-X.Y.Z.zip` | `Spoken`, `Spoken_Conversations`, `Spoken_Places`, `Spoken_Readables`, `Spoken_NPCs`, `SpokenContributions` |
| Quests voices, English, all | `quests-audio/vX` | `SpokenQuestsAudioAll-X.zip` (1.4 GB) | the four split folders |
| Quests voices, English, split | `quests-audio-{alliance,horde,shared,gossip}/vX` | | `SpokenQuestsAudio<Side>` |
| Quests voices, a language | `quests-audio-<lang>/vX` | | `SpokenQuestsAudio_<lang>` |
| Places voices | `zones-audio[-<lang>]/vX` | `SpokenZonesAudio[_<lang>]-X.zip` | `SpokenZonesAudio[_<lang>]` |
| Readables voices | `books-audio[-<lang>]/vX` | | `SpokenBooksAudio[_<lang>]` |

A pre-release (`-alpha`, `-beta`) is offered only when "Include pre-releases" is on. The launcher
reads the installed version from each folder's `.toc` (`## Version:`) and keeps its own record of
what it put where (`state.json`), so removing a pack removes exactly its folders.

The catalog (which products exist, in which languages, with which folders) is a table in the
app. The versions, sizes, notes and download URLs come from the GitHub API at run time, cached
by ETag so the unauthenticated limit (60 requests an hour) is not a problem. Offline, the app
opens with the last catalog and says so.

## Which games

From `publishers/spoken/spoken.md`: Spoken is made and tested on Forever (`_classic_beta_`) and
installs on Classic Era (`_classic_era_`) and Anniversary (`_anniversary_`). Those three are
`SUPPORTED_FLAVORS` in `src/shared/types.ts`, and the only ones the scan looks for. Any other
flavor folder (Retail, Classic, PTRs, betas) is not listed; adding one by hand is refused with
"Spoken runs on WoW: Forever, Classic Era and Anniversary. <folder> is not one of them.", and a
saved game of such a flavor from an earlier run is dropped on load (nothing on disk is touched).
The service keeps a cheap refusal as a second check. The 1.12, 2.4.3 and 3.3.5 clients have no Blizzard folders and
are out of scope: they take Spoken Quests' own zips from Releases.

## Community voice packs

A COMMUNITY page lists voice packs players made. The list is `community/packs.json` in the repo
(`CommunityPack` in `src/shared/types.ts`), fetched from
`https://raw.githubusercontent.com/rusty-key/spoken-wow/master/community/packs.json`, ETag-cached,
and kept offline. A player shares a pack by opening a pull request that adds an entry, so a
maintainer has looked at it; `community/README.md` says how.

- Product id `community/<pack id>`, installed as the one folder `SpokenCommunity_<pack id>`. It never
  replaces an official pack's folder.
- The registry is untrusted input: ids, folders, urls and sizes are validated; the url must be an
  https GitHub release asset; `sha256` is required and checked after the download.
- The zip may hold only that one folder. A pack carries Lua, so the page says so before the first
  install ("Packs from the community are not made or checked by Spoken's authors").
- Rows show title, author, language, section, size, version, license, a link to the author's page,
  and Install / Update / Remove, filtered by language and section.
- Spoken does not load these folders yet: its pack discovery knows the official names only.
  That is addon work, tracked in `spoken-later.txt`. Until then the page says "Needs a newer Spoken to play these".

## Site map

```
Spoken Launcher
|- HOME
|    My games: one card per install (name, game version, Spoken status, voice packs, button)
|    What's new: the latest Spoken release notes
|    Empty state: "No World of Warcraft found" + Add folder
|- SPOKEN                      (per game: a game picker at the top of the left rail)
|    Left rail: game picker, installed version, channel, Install / Update, menu (open folder,
|               repair, remove), install path
|    Tabs: Modules (each folder and its state) | Changelog (every release, newest first)
|- VOICE PACKS                 (per game)
|    Language chips; sections Quests, Places, Readables; a row per pack (size, installed
|    version, state, Install / Update / Remove, progress); "Install everything in <language>"
|- COMMUNITY                    (per game)
|    Packs from players: filters, a row per pack, a notice about who made them, "Share your pack"
|- SETTINGS
|    Game folders (list, Add, Remove, Rescan)
|    Updates (include pre-releases, check on start, launcher auto-update)
|    Downloads (cache folder, keep downloaded zips)
|    About (versions, links, open log folder)
```

Top bar, as in Battle.net: logo at the left, uppercase tabs with a blue underline on the active
one, a refresh button and the launcher version at the right. Dark navy window, blue primary
button, yellow for "update available", green tick for "up to date", muted grey for "not
installed". No Blizzard art or logos: the cards use the Spoken icon on a gradient.

## Architecture

Electron, TypeScript, React, built with electron-vite, packaged with electron-builder (NSIS
installer, per-user, no admin) and updated with electron-updater from GitHub Releases
(`launcher/vX` tags). Electron because the reference is one, the repo is Node already, and a
download manager with a UI needs nothing the platform lacks.

```
launcher/
  src/shared/      types and the IPC contract (the one file both sides import)
  src/main/        main process
    games.ts         discover installs; read .build.info / .flavor.info; persist added folders
    github.ts        releases, ETag cache, rate-limit handling
    catalog.ts       the product table; resolve latest release and asset per product
    download.ts      resumable download to a .part file, progress, size and digest check
    install.ts       extract (zip-slip safe), stage, swap, back up, roll back, uninstall
    guard.ts         refuse junctions and symlinks, warn when the game is running, disk space
    state.ts         state.json (what was installed where), settings.json
    ipc.ts           the handlers
    updater.ts       the launcher's own update
  src/preload/     contextBridge: the typed api, nothing else
  src/renderer/    React: pages, components, one small store
  tests/           vitest: discovery, catalog, download, install, guard
```

Rules the installer keeps:

- A folder that is a junction or a symlink is a developer's checkout: refuse, say so, never
  replace it. (This machine has one: `AddOns\spoken-wow` and the Spoken folders link into a
  repo.)
- Extract to `AddOns\.spoken-launcher\staging\<id>`, then move each folder in. The old folder
  moves to `.spoken-launcher\backup\<id>` first and comes back if anything fails. Every step is
  written to `staging\journal.json` first, so a crash is undone at the next start (and before the
  next job). The backup that stays after a successful job is that job's own; every other product's
  backup on that game is deleted then. If a rollback fails, the error names the backup folder and
  the next change on that game is refused until it is restored.
- A zip is read before it is unpacked: official packs may unpack to 6 GB in 200,000 files,
  community packs to 2 GB in 20,000.
- A resume sends `If-Range` with the ETag or date saved beside the `.part`; if the server answers
  200 the download starts again. The downloaded file is named by game, so two games never share one.
- At start: interrupted swaps are undone, `staging` is emptied, and `.part` files nobody resumed
  for a week are removed. Quitting with a job running stops it and waits for its rollback.
- Zip entries are checked: no `..`, no absolute paths, nothing outside the allowed folder
  names for that product.
- A download is a `.part` file with a `Range` resume; done only when the size matches and, when
  GitHub gives a `sha256` digest for the asset, the digest matches.
- Free space is checked before a download (size plus the extracted size).
- If `Wow*.exe` is running, installing is allowed but says "reload or restart the game".
- Nothing runs elevated. A game folder the user cannot write to is reported with the reason.

## Phases

1. Core and contract: types, discovery, GitHub, catalog, download, install, guard, state, with tests.
2. Window: shell, navigation, Home, Spoken, Voice Packs, Settings, in the Battle.net style.
3. Polish: empty and error states, offline, progress and cancel, keyboard focus, high-DPI.
4. Package: icon, NSIS installer, auto-update, a release workflow for `launcher/v*` tags.

Out of scope for now: macOS, other addons, a login, translations of the launcher itself (English
first; strings are in one file so the languages can follow), anything that sends data anywhere.

## Launcher releases

A tag `launcher/vX.Y.Z` builds the installer, publishes it as that tag's release, and refreshes
the `launcher-latest` release (`latest.yml` and the installer, replaced each time) so installed
launchers can update. They read it through electron-updater's generic provider at
`https://github.com/rusty-key/spoken-wow/releases/download/launcher-latest`, not the GitHub
provider, because the GitHub provider takes the repo's newest release and that is usually a
`spoken/` or `*-audio/` tag. A workflow for this is a later task.

## Checks

`npm test` (vitest) for the core, `npm run typecheck`, and a manual pass in the running window
with a throw-away AddOns folder. Not part of the repo's CI or its pnpm workspace: the launcher has
its own `package-lock.json` and its own folder, `launcher/`.
