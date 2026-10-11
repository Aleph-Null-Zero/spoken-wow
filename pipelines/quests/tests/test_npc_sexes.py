"""Which NPCs are split by sex, and who each sex is (tts_cli/npc_sexes.py)."""
from tts_cli.npc_sexes import npc_sexes


def npc(npc_id, race="human", gender="male", npc_type="creature"):
    return {"npcType": npc_type, "npcId": npc_id, "race": race, "gender": gender, "flavor": None}


def answers(rows):
    return [(row["npcId"], row["sex"], row["race"], row["gender"], row["flavor"], row["voice"])
            for row in rows]


def test_a_creature_drawn_as_both_sexes_is_split_with_each_sexs_voice():
    displays = [(68, 1, 50, 1, 0, "HumanMaleOfficialNPCGreetings"),
                (68, 2, 50, 1, 1, "HumanFemaleOfficialNPCGreetings")]
    assert answers(npc_sexes(displays, [npc(68)])) == [
        (68, 2, "human", "male", "official", "human-male-official"),
        (68, 3, "human", "female", "official", "human-female-official"),
    ]


def test_a_creature_of_one_sex_is_not_split():
    displays = [(1, 1, 50, 1, 0, "HumanMaleOfficialNPCGreetings"),
                (1, 2, 50, 1, 0, "HumanMaleWarriorNPCGreetings")]
    assert npc_sexes(displays, [npc(1)]) == []


def test_a_sex_is_its_likeliest_displays_race_and_the_flavor_its_displays_name_most():
    displays = [(2, 1, 10, 1, 1, "HumanFemaleStandardNPCGreetings"),
                (2, 2, 20, 4, 1, "NightElfFemalePriestessNPCGreeti"),
                (2, 3, 15, 4, 1, "NightElfFemaleStandardNPCGreeti"),
                (2, 4, 30, 1, 0, "HumanMaleStandardNPCGreetings")]
    assert answers(npc_sexes(displays, [npc(2)]))[1] == \
        (2, 3, "nightelf", "female", "priestess", "nightelf-female-priestess")


def test_even_odds_are_what_vmangos_leaves_as_no_probability_at_all():
    displays = [(3, 1, 0, 1, 1, "HumanFemaleWarriorNPCGreetings"),
                (3, 2, 0, 1, 1, "HumanFemaleStandardNPCGreetings"),
                (3, 3, 0, 1, 1, "HumanFemaleStandardNPCGreetings"),
                (3, 4, 0, 1, 0, None)]
    assert answers(npc_sexes(displays, [npc(3)])) == [
        # No greeting sound: no flavor, and the import gives the default, doubtful.
        (3, 2, "human", "male", None, "human-male"),
        (3, 3, "human", "female", "standard", "human-female-standard"),
    ]


def test_only_a_creature_with_a_humanoid_answer_is_split():
    displays = [(4, 1, 1, 1, 0, None), (4, 2, 1, 1, 1, None)]
    assert npc_sexes(displays, [npc(4, race="model-29", gender=None),
                                npc(4, race="gameobject", gender=None, npc_type="gameobject")]) == []
