"""The Compendium's hand corrections (corpus/compendium_overrides.json), applied last by
export_compendium.py: each moves, retitles, links, restricts or drops a quest, or names a chain."""
import gzip
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

from export_compendium import (OVERRIDES, apply_overrides, chain_names, corpus_quests, load_overrides,  # noqa: E402
                               quest_line)


def _rec(title, zones=(), sort=None, prev=None, races=0, classes=0):
    return {"title": title, "zones": list(zones), "sort": sort, "prev": prev, "races": races, "classes": classes}


def _records():
    return {1: _rec("First", [1429]), 2: _rec("Second", [1429], prev=1), 3: _rec("Third", [1436], prev=2),
            4: _rec("Elsewhere", sort=284)}


def test_a_correction_moves_retitles_and_restricts_a_quest():
    records = _records()
    apply_overrides(records, [{"id": 4, "zones": [1453], "title": "Moved", "races": 77, "source": "wiki"}])
    assert records[4] == _rec("Moved", [1453], races=77)


def test_a_sort_takes_a_quest_out_of_its_zones_and_none_leaves_it_nowhere():
    records = _records()
    apply_overrides(records, [{"ids": [1, 3], "sort": "winterveil", "source": "wiki"},
                              {"id": 4, "sort": 0, "source": "wiki"}])
    assert (records[1]["zones"], records[1]["sort"]) == ([], "winterveil")
    assert (records[4]["zones"], records[4]["sort"]) == ([], None)


def test_corrections_apply_in_order_the_later_last():
    records = _records()
    apply_overrides(records, [{"id": 4, "title": "One", "source": "a"}, {"id": 4, "title": "Two", "source": "b"}])
    assert records[4]["title"] == "Two"


def test_a_link_is_set_or_cut():
    records = _records()
    apply_overrides(records, [{"id": 4, "prev": 3, "source": "wiki"}, {"id": 2, "prev": 0, "source": "wiki"}])
    assert records[4]["prev"] == 3 and records[2]["prev"] is None


def test_a_quest_dropped_is_passed_through_by_the_quests_after_it():
    records = _records()
    apply_overrides(records, [{"id": 2, "remove": True, "source": "removed in the beta"}])
    assert 2 not in records and records[3]["prev"] == 1


def test_a_correction_for_a_quest_the_corpus_lacks_is_reported_not_applied():
    records = _records()
    notes = apply_overrides(records, [{"id": 99, "zones": [1429], "source": "wiki"}])
    assert 99 not in records and notes == ["99: not in the corpus (wiki)"]


def test_a_link_closing_a_loop_is_refused():
    with pytest.raises(ValueError):
        apply_overrides(_records(), [{"id": 1, "prev": 3, "source": "wiki"}])


def test_a_chain_is_named_on_its_first_quest_from_any_of_its_quests():
    records = _records()
    names, notes = chain_names(records, [{"quest": 3, "name": 2, "source": "wiki"}])
    assert names == {1: 2} and notes == []


def test_a_name_in_words_carries_its_translations():
    names, _ = chain_names(_records(), [{"quest": 1, "name": "The Story", "names": {"deDE": "Die Geschichte"},
                                         "source": "wiki"}])
    assert names == {1: {"enUS": "The Story", "deDE": "Die Geschichte"}}
    line = quest_line(1, "First", zones=[1429], name=names[1])
    assert line == '\t\t[1] = { "First", zones = { 1429 }, name = { "The Story", deDE = "Die Geschichte" } },'


def test_the_quest_line_names_a_chain_by_a_quest_and_files_a_group_by_its_word():
    assert quest_line(1, "First", zones=[1429], name=2) == '\t\t[1] = { "First", zones = { 1429 }, name = 2 },'
    assert quest_line(5, "Gift", group="winterveil") == '\t\t[5] = { "Gift", sort = "winterveil" },'


def test_an_entry_without_a_source_or_with_an_unknown_field_is_refused(tmp_path):
    for entry in ({"id": 1, "zones": [1429]}, {"id": 1, "zone": [1429], "source": "wiki"},
                  {"zones": [1429], "source": "wiki"}):
        path = tmp_path / "overrides.json"
        path.write_text(json.dumps({"quests": [entry]}), encoding="utf-8")
        with pytest.raises(ValueError):
            load_overrides(str(path))


def test_the_committed_corrections_are_well_formed_and_each_has_a_source():
    overrides = load_overrides(OVERRIDES)
    assert all(entry["source"].strip() for entry in overrides["quests"] + overrides["chains"])


def test_a_dungeon_files_a_quest_in_the_zone_of_its_entrance_and_the_line_says_which():
    records = _records()
    apply_overrides(records, [{"id": 4, "dungeon": 230, "source": "wiki"}])
    assert (records[4]["zones"], records[4]["sort"], records[4]["dungeon"]) == ([1427], None, 230)
    assert quest_line(4, "Elsewhere", zones=[1427], dungeon=230) == \
        '\t\t[4] = { "Elsewhere", zones = { 1427 }, dungeon = 230 },'


def test_the_index_leaves_out_a_quest_every_line_of_which_is_ignored(tmp_path):
    lines = [{"lineId": "q:8514:accept", "source": "accept", "questId": 8514, "questTitle": "Tally"},
             {"lineId": "q:5:accept", "source": "accept", "questId": 5, "questTitle": "Growling Gut"},
             {"lineId": "q:1:accept", "source": "accept", "questId": 1, "questTitle": "The Chow Quest"}]
    corpus, ignored = tmp_path / "corpus.json.gz", tmp_path / "ignored.json"
    with gzip.open(corpus, "wt", encoding="utf-8") as f:
        json.dump({"lines": lines}, f)
    ignored.write_text(json.dumps({"ignored": [{"lineId": "q:8514:accept", "reason": "a tally"}]}),
                       encoding="utf-8")
    quests, _, _ = corpus_quests(str(corpus), str(ignored))
    assert set(quests) == {5}
