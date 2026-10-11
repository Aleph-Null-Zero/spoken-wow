# One NPC id, several races: splitting by body

Written on 2026-10-11, alongside the split by sex (migration 0072, `npc_sex`). The split by sex
covers most cases, but some creatures come in more than one race under one id. This note records
what vmangos holds, how the sex split treats those creatures today, and the plan for doing it
properly. Nothing here is built yet.

## What vmangos has

`creature_template` gives a creature up to four displays (`display_id1-4`, drawn by
`display_probability1-4`). Each display's `db_CreatureDisplayInfoExtra` row names a race and a
sex. **199 creatures** have displays of more than one race. **7 of them speak**, with 52 lines
between them:

| id | NPC | lines | voiced as (spoken_dev) | displays (weight) |
|---|---|---|---|---|
| 16788 | Festival Flamekeeper | 17 | tauren-female-shaman | tauren ♀, troll ♂, human ♀, dwarf ♂ (1 each) |
| 10475 | Scholomance Student | 9 | not answered | human ♀ 30, human ♂ 30, gnome ♂ 20 |
| 14849 | Darkmoon Faire Carnie | 8 | human-male-standard | human ♂, night elf ♀, undead ♂, orc ♀ (25 each) |
| 10043 | Ribbly's Crony | 6 | tauren-male | tauren ♂ ×2, troll ♂ ×2 |
| 15906 | Ironforge Reveler | 5 | dwarf-male-standard | dwarf ♂/♀, gnome ♂/♀ (25 each) |
| 15908 | Orgrimmar Reveler | 5 | orc-male-standard | orc ♂/♀, troll ♂/♀ (25 each) |
| 15106 | Frostwolf Emissary | 2 | orc-male-guard | orc ♂/♀, tauren ♂/♀ (1 each) |

They are mostly holiday and event NPCs. A faction made of different creature ids, such as Caer
Darrow's humans and undead, is already fine: every id has its own answer. Only one id with
several races is a problem.

To re-run the count: group `tts_cli/sql_queries.query_creature_displays()` by entry, keep the
entries with more than one `DisplayRaceID`, and join them to `quest_line_speaker` for the ones
that speak.

## What the sex split does with them today

`tts_cli/npc_sexes.py` gives each sex the race of its likeliest display, with ties going to the
lowest slot:

- **Split by sex:** the two Revelers, the Emissary, the Carnie and the Flamekeeper.
  - A gnome Ironforge Reveler speaks with the dwarf's voice.
  - A troll Orgrimmar Reveler speaks with the orc's.
  - The Carnie's undead man speaks with the human man's.
- **Not split:**
  - The Scholomance Student, because it has no answer yet.
  - Ribbly's Crony, because every display is a man, so it stays tauren.

Until the plan below exists, a moderator can pick the best fitting voice for each sex on
`/npcs`.

## The plan: split by body, not by sex

A body is a race and a sex, as `db_CreatureDisplayInfoExtra` names them. Splitting by body is
the sex split with race added to the key. The variant mechanism (`{stem}-{voice}`, a sex keeps
the line's own file until its voice has audio) carries over unchanged.

1. **Rows.** Key the per-NPC answers on `(npcKind, npcId, race, sex)` instead of
   `(npcKind, npcId, sex)`: either widen `npc_sex` into an `npc_body` table, or add `race` to its
   primary key. The catalogue's left join gains the race, and a split NPC's line is voiced once
   per body rather than once per sex.
2. **Extract.** `npc_sexes.py` becomes `npc_bodies`: one row per distinct (race, sex) among a
   creature's displays, and a creature splits when it has more than one body. Its flavor is
   read from that body's greeting sound, as each sex's is now.
3. **Packs.** Key the per-sex tables (`GossipFileLookupByNPCSex`, `QuestFileLookupByNPCSex`,
   `FollowupLookupByNPCSex`) on a body instead of a sex.
   - The body key could be the race-sex string, e.g. `"gnome-male"`, or the model file id. The
     model id is what the addon can actually read.
   - `NPCSexByNPCID` becomes the body each unsplit creature is voiced as.
4. **Addon.** `UnitRace` answers only for players, so the addon must find the body from the
   NPC's model.
   - Contributions already read the model file id (`meta.model`), and the site maps model ids to
     race and gender (`apps/web/src/lib/npc/character-models.json`). The packs would ship that
     map, or key by model id directly.
   - `Utils:GetSexForGUID` becomes `GetBodyForGUID`. It needs a unit token on screen, as the
     sex lookup does now.
   - Reading a model means a hidden PlayerModel frame and `SetUnit`, which costs more than
     `UnitSex`, so cache the result per GUID.
5. **Contributions.** `split.ts` and `known.ts` compare the observed body (from `meta.model`)
   with the voiced one, not just the sex.

## Cost and timing

Rough size: a few days across migration, extract, catalogue, build tables, addon and intake.
That is for 52 lines that mostly play during holidays.

The cheap moment is **before the per-sex pack tables ship in a release**. Once a released pack
carries `*ByNPCSex`, the addon must keep reading them, and the body tables would sit beside them
for good. Before release, the sex tables can simply be renamed and re-keyed.
