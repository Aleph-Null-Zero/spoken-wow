"""The import's NPC answers against the npc table: a moderator's answer stays unless doubtful."""
import os

import pytest

from tts_cli.corpus_db import _import_npcs

NPC_ID = 987_654_321


@pytest.fixture
def cur():
    url = os.environ.get("DATABASE_URL")
    if not url:
        pytest.skip("needs DATABASE_URL and the web migrations")
    psycopg2 = pytest.importorskip("psycopg2")
    try:
        conn = psycopg2.connect(url)
    except psycopg2.OperationalError:
        pytest.skip("needs a reachable DATABASE_URL")
    with conn.cursor() as cur:
        cur.execute("""select to_regclass('"npc"')""")
        if cur.fetchone()[0] is None:
            pytest.skip("needs the web migrations")
        # Every import here also deletes corpus rows the file lacks: rolled back below.
        yield cur
    conn.rollback()
    conn.close()


def answer(cur, npc_id):
    cur.execute("""select "race", "gender", "flavor", "provenance", "doubtful" from "npc"
                    where "npcKind" = 'creature' and "npcId" = %s""", (npc_id,))
    return cur.fetchone()


def seed(cur, npc_id, flavor, provenance, doubtful=False):
    cur.execute("""insert into "npc" ("npcKind", "npcId", "race", "gender", "flavor",
                                      "provenance", "confirmed", "doubtful")
                   values ('creature', %s, 'human', 'male', %s, %s, true, %s)""",
                (npc_id, flavor, provenance, doubtful))


def test_a_moderators_answer_stays_and_is_reported(cur):
    seed(cur, NPC_ID, "warrior", "moderator")
    kept = _import_npcs(cur, [("creature", NPC_ID, "human", "male", "official", "moderator", False)])
    assert answer(cur, NPC_ID) == ("human", "male", "warrior", "moderator", False)
    assert kept == [("creature", NPC_ID, ("human", "male", "warrior", "moderator"),
                     ("human", "male", "official", "moderator"))]


def test_a_doubtful_moderators_answer_gives_way_to_the_file(cur):
    seed(cur, NPC_ID, "warrior", "moderator", doubtful=True)
    kept = _import_npcs(cur, [("creature", NPC_ID, "human", "male", "official", "corpus", False)])
    assert answer(cur, NPC_ID) == ("human", "male", "official", "corpus", False)
    assert kept == []


def test_the_extract_still_updates_its_own_answer(cur):
    seed(cur, NPC_ID, "warrior", "corpus")
    kept = _import_npcs(cur, [("creature", NPC_ID, "human", "male", "official", "corpus", False)])
    assert answer(cur, NPC_ID) == ("human", "male", "official", "corpus", False)
    assert kept == []


def test_the_same_answer_is_not_reported(cur):
    seed(cur, NPC_ID, "warrior", "moderator")
    assert _import_npcs(cur, [("creature", NPC_ID, "human", "male", "warrior", "moderator", False)]) == []
