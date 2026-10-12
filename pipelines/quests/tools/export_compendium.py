"""Every quest, for the Quests tab of Azeroth's Compendium.

Writes addons/Spoken_Quests/Data/Compendium.lua: each quest the corpus holds, with its English
title, where it is, and who can take it. Its words are Data/QuestText.lua's
(tools/export_quest_text.py).

- The quests are the corpus's (corpus/corpus.json.gz): the ones the voice packs were made from.
- Where: the zone the quest belongs to, as the quest log files it (QuestSortID: an AreaTable
  zone, or a dungeon, which counts as the zone its entrance is in), else where its giver stands
  (the corpus's spawns). A quest of a class, a profession or a season is filed under that
  instead (a negative QuestSortID), named as the client names it, in every language.
- Who: the races and classes allowed to take it (quest_template.AllowableRaces,
  quest_template_addon.AllowableClasses) are read from a TrinityCore world DB (the Forever
  repack's), which the vmangos extraction does not keep. Where the DB opens a quest to every
  race, it is one side's if corpus/factions.json says so, else if the quest before it in its
  chain is (quest_races below).
- Chains: the quest before each one in its storyline (`prev`), from the same DB's
  quest_template_addon (chain_links below), so the tab can group a zone's quests into their chains.
- The zones are uiMapIDs, from the client's own map tables (wago.tools, cached in cache/):
  Forever's, which add its zones and quest sorts to Era's (Mount Hyjal, Zephras Isle, Darkspear
  Islands, Riverglades, Camping, The High Order). Era's fill in anything Forever's lack.

With the repack's server up:  make quests-compendium

Without it, `make quests-compendium ARGS=--no-db` keeps every quest the file already has as it is
and adds the corpus's quests it lacks: each placed where its giver stands, and open to the races
of the side corpus/factions.json gives it (to everyone where it gives none). A later run with
the database files them as the quest log does.
"""
import argparse
import csv
import gzip
import json
import os
import re
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
QUESTS = os.path.dirname(HERE)
sys.path.insert(0, QUESTS)

from tts_cli.quest_text import in_game, lua_string  # noqa: E402

ROOT = os.path.normpath(os.path.join(QUESTS, "..", ".."))
CORPUS = os.path.join(QUESTS, "corpus", "corpus.json.gz")
FACTIONS = os.path.join(QUESTS, "corpus", "factions.json")
OUT = os.path.join(ROOT, "addons", "Spoken_Quests", "Data", "Compendium.lua")
CACHE = os.path.join(HERE, "cache")
# Forever's client (wago.tools' wow_classic_beta), and Classic Era's. With Era's alone, Forever's
# own zones and sorts resolve to nothing, even where the DB names them.
BUILD = "1.60.1.70338"
ERA_BUILD = "1.15.9.69109"
LOCALES = ["deDE", "esES", "esMX", "frFR", "ptBR", "ruRU", "koKR", "zhCN", "zhTW", "itIT"]

# The dungeons, under the zone their entrance is in (as the books' places have them).
INSTANCE_ZONE = {
    33: 1421, 34: 1453, 36: 1436, 43: 1413, 47: 1413, 48: 1440, 70: 1418, 90: 1426, 109: 1435,
    129: 1413, 189: 1420, 209: 1446, 229: 1427, 230: 1427, 249: 1445, 289: 1422, 309: 1434,
    329: 1423, 349: 1443, 389: 1454, 409: 1427, 429: 1444, 469: 1427, 509: 1451, 531: 1451, 533: 1423,
}
# The corpus's quest lines.
SOURCES = ["accept", "progress", "complete"]
# The races by side, as AllowableRaces bits (ChrRaces.PlayableRaceBit): Human, Dwarf, Night Elf,
# Gnome and High Order Skyborne; Orc, Undead, Tauren, Troll and Windshaper Skyborne. Classic's
# eight are bits 0-7 (race id less one), Forever's Skyborne 32 and 33.
CLASSIC_RACES = 0xFF
SIDE_RACES = {"alliance": 1 | 4 | 8 | 64 | 1 << 32, "horde": 2 | 16 | 32 | 128 | 1 << 33}
PLAYABLE_RACES = SIDE_RACES["alliance"] | SIDE_RACES["horde"]


def table(name, locale="enUS", build=BUILD):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"{name}-{locale}-{build}.csv")
    if not os.path.exists(path):
        url = f"https://wago.tools/db2/{name}/csv?build={build}&locale={locale}"
        request = urllib.request.Request(url, headers={"User-Agent": "curl/8.0"})
        with urllib.request.urlopen(request) as response, open(path, "wb") as out:
            out.write(response.read())
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def zone_assignments(uimap_rows, assign_rows):
    """The UiMapAssignment rows of zone maps (UiMap Type 3), and the zone of each area they name."""
    uimap = {int(r["ID"]): r for r in uimap_rows}
    assigns = [a for a in assign_rows if uimap.get(int(a["UiMapID"]), {}).get("Type") == "3"]
    area_zone = {}
    for a in assigns:
        if int(a["AreaID"]) > 0:
            area_zone.setdefault(int(a["AreaID"]), int(a["UiMapID"]))
    return assigns, area_zone


def sort_names(rows_by_locale):
    """{sort: {locale: name}} from each build's QuestSort, the first build's first: a name the
    first leaves out or empty is the next's."""
    sorts = {}
    for locale, builds in rows_by_locale.items():
        for rows in builds:
            for r in rows:
                if r["SortName_lang"]:
                    sorts.setdefault(int(r["ID"]), {}).setdefault(locale, r["SortName_lang"])
    return sorts


class Maps:
    """The client's zones: which an area is in, and which a point stands in. Forever's tables, then
    Era's for an area or a point Forever's do not place."""

    def __init__(self, builds=(BUILD, ERA_BUILD)):
        self.assign_sets, self.area_zone, self.areas = [], {}, {}
        for build in builds:
            assigns, area_zone = zone_assignments(table("UiMap", build=build), table("UiMapAssignment", build=build))
            self.assign_sets.append(assigns)
            for area, zone in area_zone.items():
                self.area_zone.setdefault(area, zone)
            for r in table("AreaTable", build=build):
                self.areas.setdefault(int(r["ID"]), r)

    def zone_of_area(self, area):
        for _ in range(4):
            if not area:
                return None
            if area in self.area_zone:
                return self.area_zone[area]
            row = self.areas.get(area)
            if row and int(row["ContinentID"]) in INSTANCE_ZONE:
                return INSTANCE_ZONE[int(row["ContinentID"])]
            area = int(row["ParentAreaID"]) if row else 0
        return None

    def zone_at(self, mapid, x, y):
        if mapid in INSTANCE_ZONE:
            return INSTANCE_ZONE[mapid]
        for assigns in self.assign_sets:
            best = None
            for a in assigns:
                if int(a["MapID"]) != mapid:
                    continue
                x0, y0, x1, y1 = (float(a["Region_0"]), float(a["Region_1"]), float(a["Region_3"]), float(a["Region_4"]))
                if min(x0, x1) <= x <= max(x0, x1) and min(y0, y1) <= y <= max(y0, y1):
                    size = abs(x1 - x0) * abs(y1 - y0)
                    if best is None or size < best[0]:
                        best = (size, int(a["UiMapID"]))
            if best:
                return best[1]
        return None

    def giver_zones(self, giver, spawns):
        zones = []
        for s in spawns.get(giver, []):
            z = self.zone_at(int(s["map"]), float(s["x"]), float(s["y"]))
            if z and z not in zones:
                zones.append(z)
        return zones


def corpus_quests():
    """{questID: {"title"}}, who each quest is placed by ("creature:id"), and the spawns. That is
    its giver, or for a quest the corpus has no offer of, whoever it is handed in to."""
    corpus = json.load(gzip.open(CORPUS, "rt", encoding="utf-8"))
    quests, givers, enders = {}, {}, {}
    for line in corpus["lines"]:
        qid, source = line.get("questId"), line.get("source")
        if not qid or source not in SOURCES or not in_game(qid, line.get("questTitle")):
            continue
        quests.setdefault(qid, {"title": line.get("questTitle") or str(qid)})
        if line.get("npcId") and line.get("npcType"):
            npc = f'{line["npcType"]}:{line["npcId"]}'
            if source == "accept":
                givers.setdefault(qid, npc)
            else:
                enders.setdefault(qid, npc)
    for qid, npc in enders.items():
        givers.setdefault(qid, npc)
    return quests, givers, corpus.get("spawns", {})


def chain_links(rows, known):
    """{questID: the quest before it in its storyline}, for the quests in `known`.

    `rows` is quest_template_addon as {questID: {"prev", "next", "group", "breadcrumb"}}:
    - PrevQuestID > 0: that quest must be handed in first, so it comes before. A negative one only
      has to be in the log at the time; that quest is not over yet, so it is not "before".
    - NextQuestID: this quest opens that one, which comes after it where it names no PrevQuestID
      of its own. Several quests opening the same one (an ExclusiveGroup: any one of them, or all
      of them) leave the lowest id as the one before.
    - BreadcrumbForQuestId: a breadcrumb leads to its quest, which comes after it where nothing
      else does.
    A quest the corpus lacks is passed through to the one before it, and a link that would close a
    loop is dropped, so every chain has a first quest.
    """
    before = {}
    for qid, row in rows.items():
        if (row.get("prev") or 0) > 0:
            before[qid] = row["prev"]
    for kind in ("next", "breadcrumb"):
        opened = {}
        for qid, row in sorted(rows.items()):
            target = row.get(kind) or 0
            if target > 0 and target != qid:
                opened.setdefault(target, qid)
        for target, qid in opened.items():
            before.setdefault(target, qid)

    def known_before(qid):
        seen = {qid}
        step = before.get(qid)
        while step is not None and step not in known:
            if step in seen:
                return None
            seen.add(step)
            step = before.get(step)
        return step

    links = {}
    for qid in sorted(known):
        step = known_before(qid)
        if step is None or step == qid:
            continue
        # Up from the quest before: reaching this one again means the link closes a loop.
        up, steps = step, 0
        while up is not None and up != qid and steps <= len(links):
            up, steps = links.get(up), steps + 1
        if up != qid:
            links[qid] = step
    return links


def playable_races(mask):
    """The playable races a race mask (PlayableRaceBit, as Forever's client has it) lets take a
    quest, 0 for anyone. The bits kept are all below 2^53, so a Lua number holds the mask exactly."""
    races = mask & PLAYABLE_RACES
    return 0 if races == PLAYABLE_RACES else races


def db_races(mask):
    """A DB AllowableRaces as Forever's client has the quest's races.

    The DB's masks are retail's 64 bits, many written before the Skyborne. A mask naming every
    Classic race is anyone, whatever it says of the races past them: the client has the DB's 0xFF
    and 0xFFFFFFFF as everyone. A mask of one side's Classic races is that side's Skyborne too, as
    the client has the DB's 0x4D and 0xB2.
    """
    races = mask & PLAYABLE_RACES
    if races & CLASSIC_RACES == CLASSIC_RACES:
        return 0
    for side in SIDE_RACES.values():
        if races & CLASSIC_RACES == side & CLASSIC_RACES:
            races |= side
    return playable_races(races)


def side_of(races):
    """The side a race mask is wholly on ("alliance" or "horde"), else None."""
    for side, mask in SIDE_RACES.items():
        if races and not races & ~mask:
            return side
    return None


def gates(rows):
    """{questID: the quests that open it}, from quest_template_addon as chain_links reads it: its
    PrevQuestID, else every quest whose NextQuestID names it (an ExclusiveGroup's alternatives, or
    all of them). A breadcrumb opens nothing: its quest can be taken without it."""
    out, opened = {}, {}
    for qid, row in rows.items():
        if (row.get("prev") or 0) > 0:
            out[qid] = {row["prev"]}
        target = row.get("next") or 0
        if target > 0 and target != qid:
            opened.setdefault(target, set()).add(qid)
    for target, qids in opened.items():
        out.setdefault(target, qids)
    return out


def quest_races(masks, sides, opened_by):
    """{questID: the races that may take it, 0 for anyone}, for the quests of `masks`
    ({questID: its race mask as the client has it: db_races of the DB's AllowableRaces}).

    - The DB's mask, where it limits who may take the quest.
    - Else the side corpus/factions.json gives the quest (its giver's): the DB leaves AllowableRaces
      0 or all for most quests that only one side's giver hands out.
    - Else the side of the quests that open it (`opened_by`, from gates), where they are all one
      side's: a follow-up the DB opens to everyone is still reached only through them. A quest one
      side's quest and the other's both open (The Stone Watcher, after either Seeing What Happens)
      stays open to both. A quest the corpus lacks is passed through to the quests opening it.
    """
    own = {qid: playable_races(mask) or SIDE_RACES.get(sides.get(str(qid)), 0) for qid, mask in masks.items()}
    races = {}

    def side_before(qid, seen):
        found = set()
        for gate in opened_by.get(qid, ()):
            if gate in seen:
                return None
            side = side_of(of(gate, seen)) if gate in own else side_before(gate, seen | {gate})
            if side is None:
                return None
            found.add(side)
        return found.pop() if len(found) == 1 else None

    def of(qid, seen=frozenset()):
        if qid not in races:
            races[qid] = own[qid] or SIDE_RACES.get(side_before(qid, seen | {qid}), 0)
        return races[qid]

    for qid in own:
        of(qid)
    return races


def side_leaks(races, links):
    """[(questID, the quest before it)] where the one before is one side's and the quest is not
    that side's alone: a chain leaking to the other side. The audit's leak check."""
    return [(qid, prev) for qid, prev in sorted(links.items())
            if side_of(races.get(prev, 0)) and side_of(races.get(qid, 0)) != side_of(races.get(prev, 0))]


def quest_line(qid, title, zones=(), group=None, races=0, classes=0, prev=None):
    parts = [lua_string(title)]
    if zones:
        parts.append("zones = { %s }" % ", ".join(str(z) for z in zones))
    if group:
        parts.append(f"sort = {group}")
    if prev:
        parts.append(f"prev = {prev}")
    # Every race or class, or none named, is anyone, and goes unsaid. Classes are Classic's nine
    # (bits by id less one); the DB's "all" is every bit set.
    races = playable_races(races)
    if races:
        parts.append(f"races = {races}")
    classes = classes & 0x5DF
    if classes and classes != 0x5DF:
        parts.append(f"classes = {classes}")
    return f"\t\t[{qid}] = {{ {', '.join(parts)} }},"


def render(quest_lines, sort_lines):
    return f"""-- AUTO-GENERATED by pipelines/quests/tools/export_compendium.py. Do not edit by hand.
--
-- Every quest the voice packs were made from, for the Quests tab of Azeroth's Compendium:
-- {{ English title, zones = {{ uiMapID... }} or sort = a QuestSort (a class, a profession, a
-- season), races and classes = who may take it (bit masks: a race's PlayableRaceBit, Skyborne's
-- 32 and 33, and a class's id less one; absent for anyone), prev = the quest before it in its
-- chain }}. The words are Data/QuestText.lua's. Regenerate with the Forever
-- repack's world DB up:
--   make quests-compendium
-- or, adding only the corpus's new quests, without it:  make quests-compendium ARGS=--no-db
--
-- A global rather than a private namespace: a data file cannot reach into the addon's environment.

SpokenQuestsCompendium = {{
\tversion = 1,

\tquests = {{
{chr(10).join(line for _, line in sorted(quest_lines.items()))}
\t}},

\tsorts = {{
{chr(10).join(line for _, line in sorted(sort_lines.items()))}
\t}},
}}
"""


ENTRY = re.compile(r"^\t\t\[(-?\d+)\] = \{ .* \},$")


def read_existing(path):
    """The quest and sort lines of a file this wrote, as they are."""
    quest_lines, sort_lines, into = {}, {}, None
    with open(path, encoding="utf-8") as f:
        for line in f.read().splitlines():
            if line == "\tquests = {":
                into = quest_lines
            elif line == "\tsorts = {":
                into = sort_lines
            elif line == "\t},":
                into = None
            elif into is not None and ENTRY.match(line):
                into[int(ENTRY.match(line).group(1))] = line
    return quest_lines, sort_lines


def without_db(args):
    quests, givers, spawns = corpus_quests()
    quest_lines, sort_lines = read_existing(args.out)
    with open(FACTIONS, encoding="utf-8") as f:
        sides = json.load(f).get("sides", {})
    maps = Maps()
    added = placed = 0
    for qid in sorted(set(quests) - set(quest_lines)):
        zones = maps.giver_zones(givers[qid], spawns) if qid in givers else []
        races = SIDE_RACES.get(sides.get(str(qid)), 0)
        quest_lines[qid] = quest_line(qid, quests[qid]["title"], zones, races=races)
        added += 1
        placed += 1 if zones else 0
    return quest_lines, sort_lines, f"{added} quests added, {placed} of them placed by their giver"


def with_db(args):
    import pymysql

    quests, givers, spawns = corpus_quests()
    maps = Maps()
    db = pymysql.connect(host=args.host, port=args.port, user=args.user, password=args.password,
                         database=args.database, charset="utf8mb4")
    ids = sorted(quests)
    marks = ",".join(["%s"] * len(ids))
    with db.cursor() as cur:
        cur.execute(f"SELECT ID, QuestSortID, AllowableRaces FROM quest_template WHERE ID IN ({marks})", ids)
        for qid, sort, races in cur.fetchall():
            quests[qid]["sort"], quests[qid]["races"] = int(sort), db_races(int(races or 0))
        cur.execute(f"SELECT ID, AllowableClasses FROM quest_template_addon WHERE ID IN ({marks})", ids)
        for qid, classes in cur.fetchall():
            quests[qid]["classes"] = int(classes or 0)
        # Every quest's links, not only the corpus's: a chain can pass through a quest it lacks.
        # Breadcrumbs are a later column some world DBs do not have.
        cur.execute("SHOW COLUMNS FROM quest_template_addon LIKE 'BreadcrumbForQuestId'")
        breadcrumb = ", BreadcrumbForQuestId" if cur.fetchall() else ", 0"
        cur.execute(f"SELECT ID, PrevQuestID, NextQuestID, ExclusiveGroup{breadcrumb} FROM quest_template_addon")
        rows = {int(qid): {"prev": int(prev or 0), "next": int(nxt or 0), "group": int(group or 0),
                           "breadcrumb": int(crumb or 0)}
                for qid, prev, nxt, group, crumb in cur.fetchall()}
    db.close()
    links = chain_links(rows, set(ids))
    with open(FACTIONS, encoding="utf-8") as f:
        sides = json.load(f).get("sides", {})
    races = quest_races({qid: quests[qid].get("races", 0) for qid in ids}, sides, gates(rows))
    leaks = side_leaks(races, links)

    sorts = sort_names({locale: [table("QuestSort", locale, build) for build in (BUILD, ERA_BUILD)]
                        for locale in ["enUS"] + LOCALES})

    placed = unplaced = by_sort = 0
    quest_lines, used_sorts = {}, set()
    for qid in ids:
        q = quests[qid]
        sort = q.get("sort", 0)
        zones = []
        group = None
        if sort > 0:
            z = maps.zone_of_area(sort)
            if z:
                zones = [z]
        elif sort < 0 and -sort in sorts:
            group = -sort
            used_sorts.add(group)
        if not zones and group is None and qid in givers:
            zones = maps.giver_zones(givers[qid], spawns)
        if zones:
            placed += 1
        elif group:
            by_sort += 1
        else:
            unplaced += 1
        quest_lines[qid] = quest_line(qid, q["title"], zones, group, races[qid], q.get("classes", 0),
                                      links.get(qid))

    sort_lines = {}
    for sid in sorted(used_sorts):
        names = sorts[sid]
        locs = [f"{l} = {lua_string(names[l])}" for l in LOCALES if names.get(l) and names[l] != names.get("enUS")]
        sort_lines[sid] = f"\t\t[{sid}] = {{ {', '.join([lua_string(names.get('enUS', str(sid)))] + locs)} }},"
    return quest_lines, sort_lines, (f"{placed} in a zone, {by_sort} under a class, profession or season, "
                                     f"{unplaced} with no place; {len(used_sorts)} sorts; "
                                     f"{len(links)} after another in a chain; "
                                     f"{sum(1 for m in races.values() if m)} limited by race, "
                                     f"{len(leaks)} not on the side of the quest before them")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-db", action="store_true", help="add the corpus's new quests without a database")
    ap.add_argument("--host", default=os.environ.get("COMPENDIUM_MYSQL_HOST", "127.0.0.1"))
    ap.add_argument("--port", type=int, default=int(os.environ.get("COMPENDIUM_MYSQL_PORT", "3317")))
    ap.add_argument("--user", default=os.environ.get("COMPENDIUM_MYSQL_USER", "root"))
    ap.add_argument("--password", default=os.environ.get("COMPENDIUM_MYSQL_PASSWORD", ""))
    ap.add_argument("--database", default=os.environ.get("COMPENDIUM_MYSQL_DATABASE", "world"))
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()

    quest_lines, sort_lines, summary = (without_db if args.no_db else with_db)(args)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(render(quest_lines, sort_lines))
    print(f"{len(quest_lines)} quests: {summary}; {os.path.getsize(args.out) // 1024} KB")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
