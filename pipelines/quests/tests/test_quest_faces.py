"""Which creature gets a face on the Quests tab (export_quest_faces.py)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

from export_quest_faces import drawable, faces  # noqa: E402


def test_a_display_the_client_has_with_its_model_is_drawable():
    displays = [{"ID": "100", "ModelID": "7"}, {"ID": "101", "ModelID": "8"}]
    assert drawable(displays, [{"ID": "7"}]) == {100}


def test_a_creature_with_one_model_the_client_has_gets_it():
    assert faces({1: {100}}, {100}) == {1: 100}


def test_a_creature_whose_model_the_client_lacks_gets_none():
    assert faces({1: {46093}}, {100}) == {}


def test_a_creature_with_several_models_gets_none_even_when_the_client_lacks_all_but_one():
    assert faces({1: {100, 46093}}, {100}) == {}
