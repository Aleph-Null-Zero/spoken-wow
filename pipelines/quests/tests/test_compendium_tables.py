"""Which client tables place the Compendium's quests (export_compendium.py): Forever's, then Era's."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import export_compendium  # noqa: E402
from export_compendium import BUILD, ERA_BUILD, Maps, sort_names  # noqa: E402


def _uimap(*ids):
    return [{"ID": str(i), "Type": "3"} for i in ids]


def _assign(uimap, area, mapid=0, region=(0, 0, 0, 0, 0, 0)):
    return {"UiMapID": str(uimap), "AreaID": str(area), "MapID": str(mapid),
            **{f"Region_{n}": str(v) for n, v in enumerate(region)}}


def _area(area, parent=0, continent=0):
    return {"ID": str(area), "ParentAreaID": str(parent), "ContinentID": str(continent)}


# Forever's tables add Zephras Isle (2521, area 15912); Era's know Elwynn Forest only. An area only
# Era's place (here 9999) stands for anything Forever's might leave out.
TABLES = {
    ("UiMap", BUILD): _uimap(1429, 2521),
    ("UiMapAssignment", BUILD): [_assign(1429, 12, 0, (-100, -100, 0, 100, 100, 0)), _assign(2521, 15912)],
    ("AreaTable", BUILD): [_area(12), _area(15912), _area(15913, parent=15912), _area(16732, continent=2998),
                           _area(16919, continent=3065)],
    ("UiMap", ERA_BUILD): _uimap(1429, 1437),
    ("UiMapAssignment", ERA_BUILD): [_assign(1429, 12), _assign(1437, 9999, 0, (200, 200, 0, 300, 300, 0))],
    ("AreaTable", ERA_BUILD): [_area(12), _area(9999)],
}


def _maps(monkeypatch):
    monkeypatch.setattr(export_compendium, "table", lambda name, locale="enUS", build=BUILD: TABLES[(name, build)])
    return Maps()


def test_a_zone_only_forever_has_places_its_quests(monkeypatch):
    maps = _maps(monkeypatch)
    assert maps.zone_of_area(15912) == 2521
    assert maps.zone_of_area(15913) == 2521


def test_eras_tables_place_what_forevers_do_not(monkeypatch):
    maps = _maps(monkeypatch)
    assert maps.zone_of_area(9999) == 1437
    assert maps.zone_at(0, 250, 250) == 1437
    assert maps.zone_at(0, 50, 50) == 1429


def test_a_sorts_name_is_forevers_and_eras_fills_what_it_lacks():
    forever = [{"ID": "666", "SortName_lang": "Camping"}, {"ID": "61", "SortName_lang": ""}]
    era = [{"ID": "61", "SortName_lang": "Warlock"}, {"ID": "666", "SortName_lang": "old"}]
    assert sort_names({"enUS": [forever, era]}) == {666: {"enUS": "Camping"}, 61: {"enUS": "Warlock"}}


def test_forevers_instanced_places_are_filed_under_the_zone_around_them(monkeypatch):
    # Excavation Site: Wetlands and The Hall of Thanes, areas of instance maps with no map of
    # their own.
    maps = _maps(monkeypatch)
    assert maps.zone_of_area(16732) == 1437
    assert maps.zone_of_area(16919) == 1455
