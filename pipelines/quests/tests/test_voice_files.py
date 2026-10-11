from tts_cli.build import build_tables, locale_tables
from tts_cli.ignores import ignored_files
from tts_cli.voice_files import npc_voices, stored_stems, with_voice_files


def line(npc_id, voice, line_id="q:109:accept", file_name="109-accept", source="accept",
         npc_type="creature"):
    return {"lineId": line_id, "source": source, "questId": 109, "questTitle": "Report",
            "npcId": npc_id, "npcName": f"NPC {npc_id}", "npcType": npc_type,
            "voice": voice, "fileName": file_name, "originalText": "Go to Gryan.",
            "generatable": True}


def npc(npc_id, race, gender, flavor, provenance="corpus", npc_type="creature"):
    # The voice the site reads the answer with (voice_for), as the export writes it.
    voice = "-".join(part for part in (race, gender, flavor) if part) if race else None
    return {"npcType": npc_type, "npcId": npc_id, "race": race, "gender": gender,
            "flavor": flavor, "provenance": provenance, "voice": voice}


CORPUS = {
    "lines": [
        line(1, "human-male-official"),
        line(2, "human-male-official"),
        line(3, "human-male-official"),
        line(4, "human-male-official"),
        line(5, "human-male-official", line_id="g:abc", file_name="abc", source="gossip"),
    ],
    "npcs": [
        npc(1, "human", "male", "official"),
        npc(2, "human", "male", "warrior"),
        npc(3, "human", "male", None),
        npc(4, None, None, None, provenance="none"),
        npc(5, "human", "male", "warrior"),
    ],
}


def test_an_npc_voice_is_the_one_its_answer_names_not_one_built_from_it():
    corpus = {"lines": [], "npcs": [dict(npc(1, "gameobject", None, None, npc_type="gameobject"),
                                         voice="narrator-male")]}
    assert npc_voices(corpus) == {("gameobject", 1): "narrator-male"}


def test_an_npc_voice_is_its_answer_and_none_where_nothing_is_known():
    assert npc_voices(CORPUS) == {
        ("creature", 1): "human-male-official",
        ("creature", 2): "human-male-warrior",
        ("creature", 3): "human-male",
        ("creature", 5): "human-male-warrior",
    }


def test_an_npc_speaks_its_own_voices_file_once_the_store_has_it():
    stems = stored_stems(["quests/109-accept.mp3", "quests/109-accept-human-male-warrior.mp3",
                          "gossip/abc-human-male-warrior.mp3"])
    rows = [(row["npcId"], row["lineId"], row["fileName"])
            for row in with_voice_files(CORPUS, stems)["lines"]]
    assert rows == [
        (1, "q:109:accept", "109-accept"),
        (2, "q:109:accept~human-male-warrior", "109-accept-human-male-warrior"),
        # No flavor, so no file anybody could have made: the line's own until it gets one.
        (3, "q:109:accept", "109-accept"),
        (4, "q:109:accept", "109-accept"),
        (5, "g:abc~human-male-warrior", "abc-human-male-warrior"),
    ]


def test_an_npc_keeps_the_lines_own_file_while_its_voice_has_no_audio():
    rows = with_voice_files(CORPUS, stored_stems(["quests/109-accept.mp3"]))["lines"]
    assert [row["lineId"] for row in rows[:4]] == ["q:109:accept"] * 4


def test_the_addon_finds_a_givers_own_voice_by_the_moments_file():
    stems = stored_stems(["quests/109-accept-human-male-warrior.mp3"])
    tables = build_tables(with_voice_files(CORPUS, stems))
    assert tables["npc_quest_file_lookups"] == (
        "QuestFileLookupByNPCID", {"109-accept": {2: "109-accept-human-male-warrior"}})
    assert tables["object_quest_file_lookups"] == ("QuestFileLookupByObjectID", {})


def test_a_line_in_another_voice_is_ignored_with_its_line():
    stems = stored_stems(["quests/109-accept-human-male-warrior.mp3"])
    corpus = with_voice_files(CORPUS, stems)
    ignored = {"q:109:accept": "a test quest"}
    assert build_tables(corpus, ignored)["npc_quest_file_lookups"][1] == {}
    assert "quests/109-accept-human-male-warrior.mp3" in ignored_files(corpus, ignored)


def test_a_speaker_written_in_another_voice_still_moves_off_the_first_speakers_file():
    corpus = {
        "lines": [line(1, "human-male-official"), line(2, "human-male-warrior")],
        "npcs": CORPUS["npcs"],
    }
    stems = stored_stems(["quests/109-accept-human-male-warrior.mp3"])
    rows = [(row["npcId"], row["fileName"]) for row in with_voice_files(corpus, stems)["lines"]]
    assert rows == [(1, "109-accept"), (2, "109-accept-human-male-warrior")]


def test_a_lines_player_gender_versions_move_together_once_both_files_exist():
    rows = [line(2, "human-male-official", line_id="q:109:accept:m", file_name="m-109-accept"),
            line(2, "human-male-official", line_id="q:109:accept:f", file_name="f-109-accept")]
    corpus = {"lines": rows, "npcs": CORPUS["npcs"]}
    one = stored_stems(["quests/m-109-accept-human-male-warrior.mp3"])
    for order in (rows, rows[::-1]):
        voiced = with_voice_files({**corpus, "lines": order}, one)["lines"]
        assert [row["fileName"] for row in voiced] == [row["fileName"] for row in order]
    both = stored_stems(["quests/m-109-accept-human-male-warrior.mp3",
                         "quests/f-109-accept-human-male-warrior.mp3"])
    assert [row["fileName"] for row in with_voice_files(corpus, both)["lines"]] == [
        "m-109-accept-human-male-warrior", "f-109-accept-human-male-warrior"]


def test_a_greetings_and_a_follow_ups_lookups_name_each_speakers_own_file():
    corpus = {
        "lines": [
            line(5, "human-male-official", line_id="g:abc:m", file_name="m-abc", source="gossip"),
            line(1, "human-male-official", line_id="g:abc:m", file_name="m-abc", source="gossip"),
            line(5, "human-male-official", line_id="f:4377:human-male-official",
                 file_name="4377-human-male-official", source="followup"),
        ],
        "npcs": CORPUS["npcs"],
    }
    stems = stored_stems(["gossip/m-abc-human-male-warrior.mp3",
                          "followup/4377-human-male-official-human-male-warrior.mp3"])
    tables = build_tables(with_voice_files(corpus, stems))
    assert tables["npc_gossip_file_lookups"][1] == {
        5: {"Go to Gryan.": "abc-human-male-warrior"},
        1: {"Go to Gryan.": "abc"},
    }
    assert tables["followup_lookups"][1] == {
        5: {4377: "4377-human-male-official-human-male-warrior"},
    }


def test_a_languages_greeting_reaches_each_speakers_own_file():
    corpus = {"lines": [line(5, "human-male-official", line_id="g:abc", file_name="abc",
                             source="gossip")], "npcs": CORPUS["npcs"]}
    voiced = with_voice_files(corpus, stored_stems(["gossip/abc-human-male-warrior.mp3"]))
    rows = [{"lineId": "g:abc", "originalText": "Go to Gryan.", "localeText": "Geh zu Gryan."}]
    tables = locale_tables(voiced, rows)
    assert tables["npc_gossip_file_lookups"][1] == {5: {"Geh zu Gryan.": "abc-human-male-warrior"}}



def test_a_gendered_greeting_keeps_one_file_for_both_players_until_both_have_the_voice():
    rows = [line(5, "human-male-official", line_id="g:abc:m", file_name="m-abc", source="gossip"),
            line(5, "human-male-official", line_id="g:abc:f", file_name="f-abc", source="gossip")]
    one = stored_stems(["gossip/m-abc-human-male-warrior.mp3"])
    for order in (rows, rows[::-1]):
        tables = build_tables(with_voice_files({"lines": order, "npcs": CORPUS["npcs"]}, one))
        assert tables["npc_gossip_file_lookups"][1] == {5: {"Go to Gryan.": "abc"}}
    both = stored_stems(["gossip/m-abc-human-male-warrior.mp3",
                         "gossip/f-abc-human-male-warrior.mp3"])
    tables = build_tables(with_voice_files({"lines": rows, "npcs": CORPUS["npcs"]}, both))
    assert tables["npc_gossip_file_lookups"][1] == {5: {"Go to Gryan.": "abc-human-male-warrior"}}


def test_a_greeting_looked_up_by_name_names_the_lines_own_file_whatever_the_row_order():
    rows = [line(5, "human-male-official", line_id="g:abc", file_name="abc", source="gossip"),
            line(1, "human-male-official", line_id="g:abc", file_name="abc", source="gossip")]
    stems = stored_stems(["gossip/abc-human-male-warrior.mp3"])
    for order in (rows, rows[::-1]):
        named = [{**row, "npcName": "Stormwind Guard"} for row in order]
        tables = build_tables(with_voice_files({"lines": named, "npcs": CORPUS["npcs"]}, stems))
        assert tables["npc_name_gossip_file_lookups"][1] == {"Stormwind Guard": {"Go to Gryan.": "abc"}}


def test_a_language_whose_own_text_is_one_line_reaches_its_voice_by_the_plain_file():
    rows = [line(5, "human-male-official", line_id="g:abc:m", file_name="m-abc", source="gossip"),
            line(5, "human-male-official", line_id="g:abc:f", file_name="f-abc", source="gossip")]
    tables = build_tables(with_voice_files({"lines": rows, "npcs": CORPUS["npcs"]},
                                           stored_stems(["gossip/abc-human-male-warrior.mp3"])))
    assert tables["npc_gossip_file_lookups"][1] == {5: {"Go to Gryan.": "abc-human-male-warrior"}}


def test_a_language_whose_own_text_is_two_lines_reaches_its_voice_once_both_have_it():
    rows = [line(5, "human-male-official", line_id="g:abc", file_name="abc", source="gossip")]
    corpus = {"lines": rows, "npcs": CORPUS["npcs"]}
    one = stored_stems(["gossip/m-abc-human-male-warrior.mp3"])
    assert build_tables(with_voice_files(corpus, one))["npc_gossip_file_lookups"][1] == {
        5: {"Go to Gryan.": "abc"}}
    both = stored_stems(["gossip/m-abc-human-male-warrior.mp3", "gossip/f-abc-human-male-warrior.mp3"])
    assert build_tables(with_voice_files(corpus, both))["npc_gossip_file_lookups"][1] == {
        5: {"Go to Gryan.": "abc-human-male-warrior"}}


def test_a_languages_greeting_joins_english_by_moment_whatever_its_own_shape():
    corpus = {"lines": [line(5, "human-male-official", line_id="g:abc:m", file_name="m-abc",
                             source="gossip")], "npcs": CORPUS["npcs"]}
    rows = [{"lineId": "g:abc", "originalText": "Go to Gryan.", "localeText": "Geh zu Gryan."}]
    tables = locale_tables(corpus, rows)
    assert tables["npc_gossip_file_lookups"][1] == {5: {"Geh zu Gryan.": "abc"}}


def sex(npc_id, value, race, flavor):
    gender = {2: "male", 3: "female"}[value]
    return {"npcType": "creature", "npcId": npc_id, "sex": value, "race": race, "gender": gender,
            "flavor": flavor, "provenance": "corpus", "voice": f"{race}-{gender}-{flavor}"}


GUARD = {
    "lines": [
        line(68, "human-male-official", line_id="g:abc", file_name="abc", source="gossip"),
        line(68, "human-male-official"),
        line(68, "human-male-official", line_id="q:109:progress", file_name="109-progress",
             source="progress"),
        line(7, "human-male-official", line_id="g:abc", file_name="abc", source="gossip"),
    ],
    "npcs": [npc(68, "human", "male", "official"), npc(7, "human", "female", "official")],
    "npcSexes": [sex(68, 2, "human", "official"), sex(68, 3, "human", "official")],
}


def test_a_split_npc_speaks_a_line_per_sex_the_other_sexs_once_its_file_is_stored():
    stems = stored_stems(["gossip/abc.mp3", "gossip/abc-human-female-official.mp3",
                          "quests/109-accept.mp3"])
    rows = [(row["npcId"], row.get("npcSex"), row["lineId"])
            for row in with_voice_files(GUARD, stems)["lines"]]
    assert rows == [
        (68, 2, "g:abc"),
        (68, 3, "g:abc~human-female-official"),
        (68, 2, "q:109:accept"),
        # Not stored yet: the man's file until it is.
        (68, 3, "q:109:accept"),
        # Never voiced, so never split.
        (68, None, "q:109:progress"),
        # Somebody else's NPC is as it was.
        (7, None, "g:abc~human-female-official"),
    ]


def test_a_split_npcs_line_is_found_by_its_own_stem_and_each_sex_asked_after():
    stems = stored_stems(["gossip/abc.mp3", "gossip/abc-human-female-official.mp3",
                          "quests/109-accept.mp3", "quests/109-accept-human-female-official.mp3"])
    tables = build_tables(with_voice_files(GUARD, stems))
    assert tables["npc_gossip_file_lookups"][1][68] == {"Go to Gryan.": "abc"}
    assert tables["npc_sex_gossip_file_lookups"][1] == {
        68: {2: {"abc": "abc"}, 3: {"abc": "abc-human-female-official"}}}
    assert tables["npc_sex_quest_file_lookups"][1] == {
        "109-accept": {68: {2: "109-accept", 3: "109-accept-human-female-official"}}}
    # The giver table an older addon reads still names no voice for the split NPC.
    assert tables["npc_quest_file_lookups"][1] == {}
    # Every other creature's sex, for the addon to notice a voice of the wrong one.
    assert tables["npc_sex_lookups"][1] == {7: 3}


def test_a_split_npcs_follow_up_is_a_file_per_sex_and_the_mans_without_one():
    followup = line(68, "human-male-official", line_id="f:4377:human-male-official",
                    file_name="4377-human-male-official", source="followup")
    corpus = {**GUARD, "lines": [followup]}
    stems = stored_stems(["followup/4377-human-male-official.mp3",
                          "followup/4377-human-male-official-human-female-official.mp3"])
    tables = build_tables(with_voice_files(corpus, stems))
    assert tables["followup_lookups"][1] == {68: {4377: "4377-human-male-official"}}
    assert tables["npc_sex_followup_lookups"][1] == {68: {4377: {
        2: "4377-human-male-official", 3: "4377-human-male-official-human-female-official"}}}


def test_a_split_npcs_line_in_a_client_locale_is_its_own_stem():
    stems = stored_stems(["gossip/abc-human-female-official.mp3"])
    rows = [{"lineId": "g:abc", "originalText": "Go to Gryan.", "localeText": "Geht zu Gryan."}]
    tables = locale_tables(with_voice_files(GUARD, stems), rows)
    assert tables["npc_gossip_file_lookups"][1][68] == {"Geht zu Gryan.": "abc"}
