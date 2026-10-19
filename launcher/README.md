# Spoken Launcher

A small app for Windows, macOS and Linux that installs and updates the Spoken addon and its voice
packs for World of Warcraft: Forever, Classic Era and Anniversary. It finds your game, shows what
is installed and what is new, and installs, updates or removes it with one button. It has no
account, no login and no tracking. The only network traffic is GitHub (the release list, Spoken
and the launcher's own updates) and spoken-packs.rusty.one (the voice packs, updated file by file).

The plan and the rules the installer follows are in [PLAN.md](PLAN.md).

## Install

Download the file for your system from the newest release named `launcher-latest` or
`launcher/v...` on the [releases page](https://github.com/rusty-key/spoken-wow/releases).

Windows: run `Spoken-Launcher-Setup-<version>.exe`. If SmartScreen asks, choose "More info", then
"Run anyway". The launcher updates itself after that.

macOS: open `Spoken-Launcher-<version>-mac-arm64.dmg` (Apple silicon) or `-mac-x64.dmg` (Intel) and
drag the app to Applications. The app is signed and updates itself from there. If macOS says it
cannot verify the app, open System Settings → Privacy & Security and choose Open Anyway (once).
Version 0.1.1 and older were not signed: macOS calls them damaged. Run this once in Terminal to
open one, or download the newest version instead:

    xattr -dr com.apple.quarantine "/Applications/Spoken Launcher.app"

Linux: download `Spoken-Launcher-<version>-linux.AppImage`, make it runnable and start it:

    chmod +x Spoken-Launcher-*-linux.AppImage
    ./Spoken-Launcher-*-linux.AppImage

The AppImage updates itself. On Ubuntu 24.04 and later the window may not open because AppArmor
blocks the browser sandbox. Start it with `--no-sandbox` in that case; this turns the sandbox off for
that run. The `.tar.gz` build works too but does not update itself.

## Where it looks for the game

Windows: the registry, Battle.net's install list, the usual `Program Files` folders and every fixed
drive.

macOS: `/Applications/World of Warcraft`, `~/Applications/World of Warcraft` and the same two
places on every mounted volume.

Linux: the game runs under Wine, so it looks inside Wine prefixes: `$WINEPREFIX`, `~/.wine`,
`~/Games/*`, and the prefixes of Lutris, Bottles, Steam (Proton) and Heroic.

If your game is somewhere else, press "Add Game Folder" and choose it. You can choose the game
folder, one of its `_classic_era_`, `_classic_beta_` or `_anniversary_` folders, or the
`Interface/AddOns` folder.

## Run it from source

You need Node 22 and npm. Work in this folder (`launcher/`):

    npm ci
    npm run dev          # the app, with live reload
    npm run dev:web      # only the window in a browser, with made-up data, for design work
    npm test             # unit tests
    npm run typecheck

## Build the installers

Each installer is built on its own system, because electron-builder cannot make a macOS app on
Windows or Linux:

    npm run dist:win     # on Windows: release/Spoken-Launcher-Setup-<version>.exe
    npm run dist:mac     # on macOS: .dmg and .zip for x64 and arm64
    npm run dist:linux   # on Linux: .AppImage and .tar.gz

The files and the `latest*.yml` update feed files land in `release/`. Releases are built by GitHub
Actions (`.github/workflows/launcher.yml`) when a tag like `launcher/v0.1.0` is pushed.

## Where it keeps its data

The data folder holds the settings, the record of what was installed, the downloads and the log:

| System | Folder |
| --- | --- |
| Windows | `%APPDATA%\Spoken Launcher` |
| macOS | `~/Library/Application Support/Spoken Launcher` |
| Linux | `~/.config/Spoken Launcher` |

The log is `logs/launcher.log` in that folder, and the last older log is `launcher.log.1`. The
launcher also keeps a hidden `.spoken-launcher` folder inside each game's `Interface/AddOns` folder
for working files and for the backup of what an update replaced. It never touches `WTF` or any addon
it did not install.
