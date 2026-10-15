# Gossip

Spoken Gossip (`addons/Spoken_Gossip`) reads what an NPC says when the player talks to them:
the gossip page, and the greeting a quest giver opens with. It is a module of Spoken, ships in
`Spoken-<v>.zip` with Quests, Readables and Places, and needs Spoken (`## Dependencies: Spoken`).
Players see it as Gossip on Spoken's module list and as its own page under Spoken's settings.

The voices are the quests packs. A gossip line is a file in the Gossip pack (English) or in a
language's one pack (`SpokenQuestsAudio_<lang>`). There is no sound pack of its own, and the
lines are made on the site's gossip explorer (`/gossip`), next to the quest lines
(`docs/quests/README.md`).

## Files

| File | What it does |
| --- | --- |
| `Environment.lua` | Makes `SpokenGossipEnv`, a table that reads through to the dialogue core's `VoiceOver` table. Returns without defining it when the core is missing. |
| `Gossip.lua` | The two windows it reads (`QUEST_GREETING`, `GOSSIP_SHOW`), their events and hooks, the rules for when a line plays, Stop When Gossip Closes, the test line and diagnostics, and `TakeOverFromQuests`. |
| `Player.lua` | Registers the `gossip` source with Spoken and hands lines to its queue. |
| `Options.lua` | The AceConfig table behind `/spg` and the old options window. |
| `UI/SettingsPanel.lua` | The Gossip page under Spoken's settings. |
| `UI/PlayButton.lua` | The Listen button on the NPC windows. |
| `DialogueUI.lua` | `DialogueUIReader`, what Spoken Quests' DialogueUI bridge asks for a greeting or gossip page. |
| `EasterEggs.lua`, `Sounds/og-thrall.mp3` | The original Thrall recording, played in place of the pack's when its setting is on. |
| `Gossip/<lang>.lua`, `Gossip/Aliases.lua` | Generated. Every line's text in the client's language, and the files one moment is also recorded under. |
| `Strings.lua`, `Locale/` | The module's words. Buttons, Report and Contribute use Spoken's strings. |

## The dialogue core

Quests and Gossip read lines the same way, so what they share lives in Spoken's `Dialogue/`
folder and runs in one environment, the global `VoiceOver` table. Each module has an environment
of its own on top of it (`SpokenGossipEnv`), so the names `Addon`, `Player`, `Options` and `L`
never meet the other module's.

| File | What it does |
| --- | --- |
| `Environment.lua` | The `VoiceOver` table. The name stays: every sound pack calls into it. |
| `DataModules.lua` | Finds the voice packs by their `.toc` keys, finds a line's file in them, and fills in its path, length, pack and language. |
| `Language.lua` | The voice language and the fallback language, and the order a line is looked for in. |
| `FuzzySearch.lua` | The word-overlap match that finds a line from the words on screen. |
| `Enums.lua`, `Utils.lua`, `Debug.lua`, `Compat.lua` | Sound events and GUID types, helpers, the debug record, and the client differences both modules need. |
| `ReportButton.lua`, `Present.lua` | The Report address and its copy box, and how a clip shows on Spoken's windows. |
| `PlayButton.lua` | The Listen button that each module places on its own windows. |
| `Contribute.lua`, `ContributeButton.lua` | The Contribute button and the envelope it sends. Loaded by `Contribute.xml` on Blizzard's clients only. |

## How a line is read

1. The client opens a window. Gossip hears `QUEST_GREETING` or `GOSSIP_SHOW` on its event frame,
   and also hooks the windows' `OnShow` and `QuestFrame_OnEvent`, because the globals that hold
   the text can lag the event. Each signal waits 0.1 s and the last one for a window wins.
2. In the frame the window opens, `MuteGreetingAhead` cuts the NPC's own spoken greeting, but
   only where a pack has a line for this speaker and the settings say it will be read. Any
   other NPC keeps its own voice.
3. `GetNPCGossipTextHash` finds the line from the speaker and the words. It looks in the
   tables written in the client's language first (the module's `Gossip/<lang>.lua`, then the
   packs'), and only if no pack in that language knows the NPC does it try the others. The
   closest match by shared words wins.
4. `PrepareSound` finds the file in the voice language, then the fallback language, trying the
   line's aliases and the player's `m-` or `f-` variant, and applies the Thrall recording if
   that setting is on.
5. The line is queued on the `gossip` source with priority `low`. A greeting waits for the
   NPC's own greeting to finish where Game Greeting First is on. With DialogueUI's window up,
   the read waits until the window is fully shown.

When the player picks an option, the next page is read whatever Read Greetings says: the
once-per settings hold back only the greeting an NPC opens with. The page is labelled with the
option picked.

## Settings

All are on Gossip's page under Spoken's settings, in the profile chosen on Spoken's own page
(`SpokenGossipSettings`).

- Read Greetings: Every Time, Once for Quest Givers, Once per NPC (the default) or Never. Once
  for Quest Givers holds back a repeat only where the NPC has quests. At Never nothing reads
  itself and the NPC windows show a Listen button.
- Stop When Gossip Closes. Closing the gossip window stops its line. Closing the quest frame
  also stops a greeting, but never a quest's own line.
- Original Thrall Speech.
- Forget Greetings Heard. Every NPC greets this character again. It matters only for the two
  once-per settings. Heard greetings are kept per character in `hasSeenGossipForNPC`, keyed by
  the NPC's GUID, and marked when the line starts playing.
- The module's switch, the voice packs and Play a Test Line, as on every module page.

Spoken's own page holds the voice language, the fallback and Game Greeting First.

## Commands

`/spokengossip` and `/spg` run AceConfig commands: `read` reads the open window, `test` plays
Thrall's line, `diagnostics` prints the client, the setting and the packs that hold gossip,
and `options` opens the page. `/spgread` is the same as `/spg read`. `/sp settings` opens
Spoken's page.

## Where the text and the packs come from

- Each client language but English has its gossip text in `Gossip/<lang>.lua`. Forever's `.toc`
  loads only the client's own with `[AllowLoadTextLocale]`.
- `docs/quests/README.md` explains how the lines, their BroadcastText ids and the aliases are
  made: "Gossip text for every client" and "Which greeting a text is".
- The Report address for a greeting is `…/quests/r/npc/{creatureID}`, and a gameobject has
  `…/quests/r/object/{objectID}`. The Contribute button appears where no pack has the line.

## Moving from Quests

Gossip used to be part of Spoken Quests. On a character's first login `TakeOverFromQuests` copies
each profile's greeting settings, each character's heard greetings and which profile each
character uses. Autoplay off there becomes Never here, and a player who had switched Quests off
gets Gossip off. It runs once.
