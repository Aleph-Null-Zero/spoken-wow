"""Which NPCs come in both sexes under one id, and who each sex is.

Each sex is the race of its likeliest display, and the flavor its displays of that race name
most, weighted by probability. A sex whose displays name no flavor gets none; the import gives
it its race-gender's default, marked doubtful.
"""
from __future__ import annotations

from collections import defaultdict
from typing import NamedTuple

from tts_cli.consts import GENDER_DICT, RACE_DICT
from tts_cli.flavors import busiest, flavor_from_sound_name, voice_name

#: UnitSex's answer for each DisplaySexID: what the addon reports and npc_sex is keyed on.
UNIT_SEX = {0: 2, 1: 3}
#: The gender each UnitSex is voiced in.
SEX_GENDER = {UNIT_SEX[sex_id]: gender for sex_id, gender in GENDER_DICT.items()}
#: The UnitSex a gender is drawn as.
GENDER_SEX = {gender: sex for sex, gender in SEX_GENDER.items()}


class Display(NamedTuple):
    slot: int
    weight: int
    race: str
    sex_id: int
    sound: str | None


def npc_sexes(display_rows, npcs) -> list:
    """The corpus's `npcSexes` for the creatures among `npcs` that come in both sexes.

    `display_rows` are (entry, slot, probability, DisplayRaceID, DisplaySexID, npc_sound_name).
    Only a creature with a humanoid answer is split: a model slot or a generic type has no sex.
    """
    displays = defaultdict(list)
    for entry, slot, probability, race_id, sex_id, sound in display_rows:
        race = RACE_DICT.get(int(race_id))
        if race and int(sex_id) in UNIT_SEX:
            displays[int(entry)].append(Display(int(slot), int(probability or 0), race,
                                                int(sex_id), sound))

    split = []
    for npc in npcs:
        if npc["npcType"] != "creature" or npc.get("gender") not in ("male", "female"):
            continue
        rows = displays.get(npc["npcId"], [])
        if len({row.sex_id for row in rows}) < 2:
            continue
        # vmangos leaves every probability 0 for a creature drawn at even odds.
        even = not any(row.weight for row in rows)
        rows = [row._replace(weight=1) for row in rows] if even else rows
        for sex_id in sorted(UNIT_SEX):
            mine = [row for row in rows if row.sex_id == sex_id]
            race = min(mine, key=lambda row: (-row.weight, row.slot)).race
            gender = GENDER_DICT[sex_id]
            tally = defaultdict(int)
            for row in mine:
                flavor = flavor_from_sound_name(row.sound, f"{race}-{gender}") if row.race == race else None
                if flavor:
                    tally[flavor] += row.weight
            flavor = busiest(tally)
            split.append({"npcType": "creature", "npcId": npc["npcId"], "sex": UNIT_SEX[sex_id],
                          "race": race, "gender": gender, "flavor": flavor,
                          "provenance": "corpus", "voice": voice_name(race, gender, flavor)})
    return split
