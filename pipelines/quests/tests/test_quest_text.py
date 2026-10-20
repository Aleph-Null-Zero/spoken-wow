import re
import shutil
import subprocess
from pathlib import Path

import pytest

import json

from tts_cli.corpus import load_corpus
from tts_cli.quest_text import in_game, left_out, lua_string, quest_text, removed_quests, render

QUESTS = Path(__file__).resolve().parent.parent
QUEST_TEXT_LUA = QUESTS.parent.parent / "addons" / "Spoken_Quests" / "Data" / "QuestText.lua"
#: Players' names that contributed text carried where the game says $n: the first eight fixed by
#: hand, the rest by the site's own export.
PLAYER_NAMES = ["Aranvielle", "Sladkiy", "Marabi", "Rhett", "Ukko", "Reli", "Drakath", "Thank you Dead",
                "Orangequake", "Ingmmar", "Spineblast", "Saixgone", "Zaelriel", "Xeph", "Busch", "Samelyn",
                "Raton", "Naanariel", "Gei", "Shamfor", "Theinn", "Vall", "Venator", "Archnatum", "Quantum",
                "Gort", "Johnathon", "Eraina", "Ulvarg", "Thay", "Gehrfik", "Gryma", "Gad", "Nattyrav",
                "Sparkled", "Sneaky", "Illbean", "Leif", "Qiy", "Cory", "Hans", "Turq", "Zurk", "Dovahshark",
                "Vanyel"]


def _line(quest, source, text, npc=288, gender=None, title="Growling Gut"):
    line_id = f"q:{quest}:{source}" + (f":{gender}" if gender else "")
    return {"lineId": line_id, "source": source, "questId": quest, "questTitle": title,
            "npcId": npc, "originalText": text, "playerGender": gender}


def test_each_quest_keeps_its_offer_and_completion_and_not_its_progress():
    corpus = {"lines": [_line(5, "accept", "Find my pack."), _line(5, "progress", "Not yet?"),
                        _line(5, "complete", "You found it!")]}
    assert quest_text(corpus) == {5: {"accept": "Find my pack.", "complete": "You found it!"}}


def test_a_quest_with_only_its_progress_shows_it_as_its_offer():
    corpus = {"lines": [_line(98888, "progress", "Back so soon?"),
                        _line(6, "progress", "Not yet?"), _line(6, "complete", "Done!")]}
    assert quest_text(corpus) == {98888: {"accept": "Back so soon?"}, 6: {"complete": "Done!"}}


def test_gossip_and_follow_up_lines_are_not_a_quest_s_words():
    corpus = {"lines": [_line(5, "accept", "Find my pack."), _line(5, "followup", "Thanks!"),
                        dict(_line(0, "gossip", "Move along."), questId=None)]}
    assert quest_text(corpus) == {5: {"accept": "Find my pack."}}


def test_the_placeholders_are_kept_for_the_addon_to_fill():
    text = "Hello, $N the $c.$B$BMy $gbrother:sister;, a $R, needs you."
    assert quest_text({"lines": [_line(5, "accept", text)]})[5]["accept"] == text


def test_a_gendered_pair_is_one_text():
    corpus = {"lines": [_line(60, "accept", "Hello, $ggood sir:my lady;!", gender="m"),
                        _line(60, "accept", "Hello, $ggood sir:my lady;!", gender="f")]}
    assert quest_text(corpus) == {60: {"accept": "Hello, $ggood sir:my lady;!"}}


def test_where_givers_differ_the_words_most_of_them_say():
    corpus = {"lines": [_line(7795, "complete", "Fantastic.", npc=1),
                        _line(7795, "complete", "With all the donations...", npc=2),
                        _line(7795, "complete", "With all the donations...", npc=3)]}
    assert quest_text(corpus)[7795]["complete"] == "With all the donations..."


def test_a_tie_goes_to_the_words_the_corpus_has_first():
    corpus = {"lines": [_line(172, "accept", "Lord Ebonlocke sent me.", npc=271),
                        _line(172, "accept", "You're willing to help us?", npc=271),
                        _line(172, "accept", "You're willing to help us?", npc=14451),
                        _line(172, "accept", "Lord Ebonlocke sent me.", npc=14451)]}
    assert quest_text(corpus)[172]["accept"] == "Lord Ebonlocke sent me."


def test_an_ignored_line_has_no_words():
    corpus = {"lines": [_line(5, "accept", "Find my pack."), _line(5, "complete", "You found it!")]}
    assert quest_text(corpus, {"q:5:accept"}) == {5: {"complete": "You found it!"}}


def test_a_quest_the_compendium_leaves_out_has_no_words(tmp_path):
    overrides = tmp_path / "compendium_overrides.json"
    overrides.write_text(json.dumps({"quests": [
        {"id": 236, "remove": True, "source": "removed in the beta"},
        {"ids": [708, 909], "remove": True, "source": "old copies"},
        {"id": 5, "title": "Growling Gut", "source": "a title"}]}), encoding="utf-8")
    assert removed_quests(str(overrides)) == {236, 708, 909}
    assert removed_quests(str(tmp_path / "none.json")) == set()
    corpus = {"lines": [_line(5, "accept", "Find my pack."), _line(236, "accept", "Wait for word.")]}
    assert set(quest_text(corpus, removed={236})) == {5}


def test_one_rule_leaves_out_debris_quests_wholly_ignored_and_removals():
    corpus = {"lines": [_line(1, "accept", "Test.", title="The Chow Quest"),
                        _line(8514, "accept", "Tally: $2113w."), _line(8516, "accept", "Bring bars."),
                        _line(8516, "complete", "Tally: $2113w."), _line(236, "accept", "Wait."),
                        _line(5, "accept", "Find my pack.")]}
    ignored = {"q:8514:accept", "q:8516:complete"}
    # 8516 keeps a line no one ignored, so it is still listed, without the ignored one's words.
    assert left_out(corpus, ignored, {236}) == {1, 8514, 236}
    assert set(quest_text(corpus, ignored, {236})) == {8516, 5}


def test_the_test_quest_and_those_not_yet_implemented_are_left_out():
    corpus = {"lines": [_line(1, "accept", "$Tpunk;! NEW TEST AGAIN", title="The Chow Quest"),
                        _line(3482, "accept", "A box.", title="<NYI> <TXT> The Pocked Black Box"),
                        _line(5, "accept", "Find my pack.")]}
    assert set(quest_text(corpus)) == {5}
    assert not in_game(1, "The Chow Quest") and in_game(5, "Growling Gut")


def test_a_windows_line_break_is_one_line_break():
    assert quest_text({"lines": [_line(5, "accept", "One.\r\nTwo.")]})[5]["accept"] == "One.\nTwo."


@pytest.fixture(scope="module")
def committed():
    return load_corpus(str(QUESTS / "corpus" / "corpus.json.gz")), QUEST_TEXT_LUA.read_text(encoding="utf-8")


def test_no_quest_text_names_another_player(committed):
    corpus, lua = committed
    for name in PLAYER_NAMES:
        rx = re.compile(r"\b%s\b" % re.escape(name))
        assert not rx.search(lua), name
        assert not [line["lineId"] for line in corpus["lines"]
                    if line.get("questId") and rx.search(line["originalText"])], name


def test_the_menethil_crest_offer_says_lad_or_lass_by_the_player_s_gender(committed):
    corpus, lua = committed
    offers = {line["lineId"]: line["originalText"] for line in corpus["lines"] if line.get("questId") == 98190
              and line["source"] == "accept"}
    assert set(offers) == {"q:98190:accept:m", "q:98190:accept:f"}
    assert all("this one, $glad:lass;." in text for text in offers.values())
    assert "this one, $glad:lass;." in lua


def test_hand_ins_the_site_splits_by_the_player_s_gender_are_a_pair(committed):
    corpus, _ = committed
    ids = {line["lineId"] for line in corpus["lines"]}
    for base in ("q:3097:complete", "q:91282:complete", "g:368720c602f129b62676fcebd9b31777"):
        assert base not in ids
        assert {base + ":m", base + ":f"} <= ids
    texts = {line["lineId"]: line["text"] for line in corpus["lines"] if line.get("questId") in (3097, 91282)}
    assert "call you Lady." in texts["q:3097:complete:f"] and "sister." in texts["q:91282:complete:f"]


def test_children_s_week_offers_are_their_own_not_duskwood_s(committed):
    corpus, _ = committed
    words = quest_text(corpus)
    assert "Children's Week" in words[171]["accept"] and "Children's Week" in words[172]["accept"]
    assert "Randis had so much fun with you" in words[171]["complete"]


def test_quotes_backslashes_and_line_breaks_are_lua_escapes():
    assert lua_string('Say "hi" \\ there\nnow') == '"Say \\"hi\\" \\\\ there\\nnow"'


def test_the_file_is_lua_the_addon_can_load(tmp_path):
    texts = {7: {"complete": 'Is it "done"?'}, 5: {"complete": "Thanks, $N!", "accept": "Find it.$BGo."}}
    lua = render(texts)
    assert lua.startswith("-- AUTO-GENERATED by pipelines/quests/tools/export_quest_text.py")
    assert "make quests-compendium-text" in lua
    # Quests in id order, and each quest's words in the order a player meets them.
    assert lua.index("[5] = {") < lua.index("[7] = {")
    assert lua.index('accept = "Find it.$BGo."') < lua.index('complete = "Thanks, $N!"')
    luajit = shutil.which("luajit")
    if not luajit:
        pytest.skip("no luajit to load the file with")
    path = tmp_path / "QuestText.lua"
    path.write_text(lua, encoding="utf-8")
    result = subprocess.run([luajit, "-e", f"dofile([[{path}]]) "
                             "io.write(SpokenQuestsText[7].complete, '|', SpokenQuestsText[5].accept)"],
                            capture_output=True, text=True, check=True)
    assert result.stdout == 'Is it "done"?|Find it.$BGo.'
