-- The quests in Azeroth's Compendium, the window Spoken Books and Spoken Zones carry: every quest
-- this character's race and class may take. A quest is found once this character has started it:
-- completed, or in its quest log, which is marked in progress on its row and its page. Until then
-- it is greyed and does not open, unless Unlock Unstarted Quests is on.
--
-- The list is the Compendium's banners, cards and lines. Banners are for continents and types:
-- one for each continent, Other Lands for the zones on no continent, Battlegrounds, then the
-- sections Classes, Professions, Holidays and Events and Other. Cards are for places alone: a
-- zone, its city, a dungeon. Everything else is a line of the list with what it holds under it: a
-- class, profession, holiday or other kind of quest and Place Unknown in a section's banner, a
-- zone's Dungeons and Raids where it has several (a card for each dungeon under it; a zone with
-- one has that dungeon's card), and a chain, the quests that follow one another (`prev` in the
-- data), with the same name in every zone it crosses. The rest are the leaves, a row each.
-- Every card and banner counts its quests completed out of all and those in progress; Voiced Only
-- leaves the quests no voice pack has out of the counts as it does out of the list.
--
-- The page shows what is chosen. A quest's is its title, where it is and its words, with Play
-- where a voice pack has it, or L.QUEST_NOT_FOUND where it does not open. Its hand-in waits until
-- it is completed, unless Unlock Unstarted Quests is on. A banner's, card's or
-- chain's is its name, where it is and its count on one line, and L.QUESTS_PICK, the quests being
-- on the left to choose. The sections and Place Unknown are no place: their line is the count.
--
-- A search lists what matches under what holds it. Where it matches the name of a banner, a card
-- or a chain, everything inside that one is listed.
--
-- On a client in another language, the words and title each quest's window showed are kept for
-- the whole account and shown over the English.
--
-- Not under setfenv(1, VoiceOver): the frames are built here, and the client's mixins are looked
-- up in the calling function's environment.

local ADDON_NAME, ns = ...
local VO = VoiceOver

local QuestsTab = {}
VO.QuestsTab = QuestsTab

local L = VO.L
local C

-- The words' size, for UI/TextView.lua: Spoken Zones' where it is installed, so every tab of the
-- Compendium reads alike.
function ns:Get(key)
    if key == "fontSize" then
        return (SpokenZonesSettings and SpokenZonesSettings.fontSize) or 12
    end
end

local list, page
local selection          -- { quest = id } | { mapID = id } | { sort = id } | { group = "elsewhere" }
                         -- | { chain = key, ids = { id... }, first = id, where = key } | nil
local landed             -- the selection made for the player, where they stood; any other they chose
local openZones = {}     -- [mapID] = true: a zone's or city's card, opened
local continentOpen = { [1414] = true, [1415] = true }
local groupOpen = {}
local sectionOpen = {}

-- The quests filed under no zone, apart from Azeroth's: by what their QuestSort is. Any other sort
-- goes under Other, with the quests that have no place at all.
local SECTIONS = {
    { key = "classes", label = "QUESTS_SECTION_CLASSES",
        sorts = { [61] = true, [81] = true, [82] = true, [141] = true, [161] = true, [162] = true, [261] = true,
            [262] = true, [263] = true } },
    -- Camping (666) with them: nearly all its quests are Camping 101 for one profession or another.
    { key = "professions", label = "QUESTS_SECTION_PROFESSIONS",
        sorts = { [24] = true, [101] = true, [121] = true, [181] = true, [182] = true, [201] = true, [264] = true,
            [304] = true, [324] = true, [666] = true } },
    { key = "events", label = "QUESTS_SECTION_EVENTS",
        sorts = { [22] = true, [284] = true, [364] = true, [365] = true, [366] = true, [368] = true, [369] = true,
            winterveil = true, hallowsend = true, loveisintheair = true, harvestfestival = true } },
    { key = "other", label = "QUESTS_SECTION_OTHER" },
}

-- The tab's own names: for the groups the client has no QuestSort for (a word in the data), and
-- for two whose client name says too little. Special (284) holds Children's Week alone, and
-- Reputation (367) the Commendation Signets' hand-ins.
local GROUP_NAMES = {
    [284] = "QUESTS_GROUP_CHILDRENS_WEEK", [367] = "QUESTS_GROUP_COMMENDATIONS",
    winterveil = "QUESTS_GROUP_WINTER_VEIL", hallowsend = "QUESTS_GROUP_HALLOWS_END",
    loveisintheair = "QUESTS_GROUP_LOVE_IS_IN_THE_AIR", harvestfestival = "QUESTS_GROUP_HARVEST_FESTIVAL",
    argentdawn = "QUESTS_GROUP_ARGENT_DAWN", library = "QUESTS_GROUP_LIBRARY",
}

-- The battlegrounds, under a banner of their own after the continents, whatever map the client
-- hangs them under: Forever's newer client puts Alterac Valley in Hillsbrad Foothills, its older
-- one under Azeroth, where no continent's list reached them.
local BATTLEGROUNDS = { 1459, 1460, 1461, 2524 } -- Alterac Valley, Warsong Gulch, Arathi Basin, Darkspear Islands
local IS_BATTLEGROUND = {}
for _, mapID in ipairs(BATTLEGROUNDS) do IS_BATTLEGROUND[mapID] = true end

local function SectionOf(sort)
    for _, section in ipairs(SECTIONS) do
        if section.sorts and section.sorts[sort] then return section.key end
    end
    return "other"
end
local filter = ""

local MOMENTS = { "accept", "progress", "complete" }
local HEADINGS = { accept = "QUEST_PART_ACCEPT", progress = "QUEST_PART_PROGRESS", complete = "QUEST_PART_COMPLETE" }

--------------------------------------------------------------------------------
-- What there is
--------------------------------------------------------------------------------

local function Quests()
    local data = _G.SpokenQuestsCompendium
    return data and data.quests or {}
end

local function English(id)
    return _G.SpokenQuestsText and SpokenQuestsText[id] or {}
end

local function Locale()
    return GetLocale and GetLocale() or "enUS"
end

local function Global()
    local db = VO.Addon.db and VO.Addon.db.global
    if not db then return {} end
    db.Compendium = db.Compendium or {}
    return db.Compendium
end

local function Unlocked()
    return Global().UnlockUnfound == true
end

local function OnlyFound()
    return Global().FoundOnly == true
end

-- Voiced Only, after Started Only in the filter menu: the quests no installed voice pack has a part
-- of are left out, and with them any card or banner left with nothing.
local function OnlyVoiced()
    return Global().VoicedOnly == true
end

-- Whether a voice pack has a part of a quest, as its page's Play finds one.
local AnyVoiced

-- The words and titles kept in this client's language, by quest: { title, accept = { text, sex } ... }.
-- None on an English client: the English shipped is what it would keep.
local function Kept()
    if Locale() == "enUS" then return nil end
    local db = VO.Addon.db and VO.Addon.db.global
    if not db then return nil end
    db.CompendiumText = db.CompendiumText or {}
    db.CompendiumText[Locale()] = db.CompendiumText[Locale()] or {}
    return db.CompendiumText[Locale()]
end

-- The client's title once it has one, else the English; asked for once where it is not loaded,
-- and the list drawn again when it arrives (QUEST_DATA_LOAD_RESULT).
local titles, asked = {}, {}
local function Title(id, ask)
    if titles[id] then return titles[id] end
    local kept = Kept()
    local title = kept and kept[id] and kept[id].title
    if not title and Locale() ~= "enUS" and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        title = C_QuestLog.GetTitleForQuestID(id)
        if (type(title) ~= "string" or title == "") and ask and not asked[id] and C_QuestLog.RequestLoadQuestByID then
            asked[id] = true
            C_QuestLog.RequestLoadQuestByID(id)
        end
    end
    if type(title) == "string" and title ~= "" then
        titles[id] = title
        return title
    end
    local quest = Quests()[id]
    return quest and quest[1] or tostring(id)
end

local function SortName(sort)
    if GROUP_NAMES[sort] then return L[GROUP_NAMES[sort]] end
    local data = _G.SpokenQuestsCompendium
    local names = data and data.sorts and data.sorts[sort]
    if not names then return tostring(sort) end
    return names[Locale()] or names[1]
end

-- AllowableRaces and AllowableClasses are bit masks, bit (id - 1), save the races in `bits`:
-- Skyborne's (race ids 95 and 96) are PlayableRaceBit 32 and 33. Tested with arithmetic, since
-- bit.band is 32-bit.
local RACE_BITS = { [95] = 32, [96] = 33 }
local function Has(mask, id, bits)
    if not id or id < 1 then return true end
    return math.floor(mask / 2 ^ (bits and bits[id] or id - 1)) % 2 == 1
end

local function Allowed(quest)
    if quest.races then
        local _, _, race = UnitRace("player")
        if not Has(quest.races, race, RACE_BITS) then return false end
    end
    if quest.classes then
        local _, _, class = UnitClass("player")
        if not Has(quest.classes, class) then return false end
    end
    return true
end

-- What the game says this character has completed, read again on each refresh: the whole list
-- where the client gives one, else asked quest by quest.
local completed
local function ReadCompleted()
    completed = nil
    local ids = C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs and C_QuestLog.GetAllCompletedQuestIDs()
    if type(ids) == "table" then
        completed = {}
        for _, id in ipairs(ids) do completed[id] = true end
        return
    end
    local done = GetQuestsCompleted and GetQuestsCompleted()
    if type(done) == "table" then
        completed = {}
        for id, yes in pairs(done) do
            if yes then completed[id] = true end
        end
    end
end

local function Completed(id)
    if completed then return completed[id] == true end
    local ask = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    return ask ~= nil and ask(id) and true or false
end

-- The quests in this character's quest log, read again on each refresh.
local inLog = {}
local Index
local function ReadLog()
    local log, listed = {}, 0
    local modern = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo
    local entries, quests
    if modern then
        entries, quests = C_QuestLog.GetNumQuestLogEntries()
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        entries, quests = GetNumQuestLogEntries()
    end
    for i = 1, entries or 0 do
        local id, header
        if modern then
            local info = C_QuestLog.GetInfo(i)
            id, header = info and info.questID, info and info.isHeader
        else
            local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
            id, header = questID, isHeader
        end
        if not header and type(id) == "number" and id > 0 then
            log[id] = true
            listed = listed + 1
        end
    end
    -- Classic's log does not list the quests under a header the player has collapsed.
    if type(quests) == "number" and listed < quests and C_QuestLog and C_QuestLog.IsOnQuest then
        for id in pairs(Index().all) do
            if C_QuestLog.IsOnQuest(id) then log[id] = true end
        end
    end
    local changed = false
    for id in pairs(log) do if not inLog[id] then changed = true end end
    for id in pairs(inLog) do if not log[id] then changed = true end end
    inLog = log
    return changed
end

local function InProgress(id)
    return inLog[id] == true and not Completed(id)
end

local function Found(id)
    return Completed(id) or inLog[id] == true
end

local function Matches(text)
    return filter == "" or (text and string.find(string.lower(text), filter, 1, true) ~= nil)
end

-- Set while the rows inside a container whose name the search matches are built: all it holds is
-- listed, not only what matches.
local whole = false

-- Whether the search leaves out what does not match it, where the rows are being built.
local function Filtering()
    return filter ~= "" and not whole
end

-- The rows `build` returns, everything it holds listed where `named` (the search matches the
-- container's name).
local function Whole(named, build)
    local before = whole
    whole = before or named
    local rows = build()
    whole = before
    return rows
end

-- Set while the cards under a banner whose name the search matches are built: each is listed,
-- closed or open as the player left it, and opens and closes on a click as it does unsearched. A
-- continent's every quest at once would be too long a list to read.
local shut = false

-- Whether a search opens the cards being built.
local function Searched()
    return filter ~= "" and not shut
end

-- What a search opened and the player closed again with a click, by row; a new search opens all.
local searchClosed = {}

-- A card's rows: the card, and what it holds unless the player closed it during this search.
local function Rows(card, inside, key)
    card.closeKey = key
    if Searched() and searchClosed[key] then
        card.open = false
        return { card }
    end
    local rows = { card }
    for _, row in ipairs(inside) do table.insert(rows, row) end
    return rows
end

-- While a search opens everything it finds, a click on an open card closes it, and opens it again.
local function SearchFold(row)
    if filter == "" or row.shut or not row.closeKey then return false end
    searchClosed[row.closeKey] = not searchClosed[row.closeKey] or nil
    return true
end

-- As Whole, for a banner: its cards listed, each as the player left it.
local function Listed(named, build)
    local before = shut
    shut = before or named
    local rows = Whole(named, build)
    shut = before
    return rows
end

-- Every quest this character may take, by where it is: index.zones[mapID], index.sorts[sort],
-- index.elsewhere, and `all`. Built once: neither the data nor the character's race and class
-- change in a session.
local index
function Index()
    if index then return index end
    index = { zones = {}, sorts = {}, elsewhere = {}, all = {} }
    local named = _G.SpokenQuestsCompendium and SpokenQuestsCompendium.sorts or {}
    for id, quest in pairs(Quests()) do
        if Allowed(quest) then
            index.all[id] = true
            if quest.zones and #quest.zones > 0 then
                for _, mapID in ipairs(quest.zones) do
                    index.zones[mapID] = index.zones[mapID] or {}
                    table.insert(index.zones[mapID], id)
                end
            -- A sort the data and the tab have no name for has no row of its own to go under.
            elseif quest.sort and (named[quest.sort] or GROUP_NAMES[quest.sort]) then
                index.sorts[quest.sort] = index.sorts[quest.sort] or {}
                table.insert(index.sorts[quest.sort], id)
            else
                table.insert(index.elsewhere, id)
            end
        end
    end
    return index
end

local function ByName(a, b)
    local na, nb = C.MapName(a), C.MapName(b)
    if na == nb then return a < b end
    return na < nb
end

-- The zones on `continent` with quests, cities left to the zone around them and battlegrounds to
-- their banner.
local function ZonesOn(continent)
    local out, listed = {}, {}
    for mapID in pairs(Index().zones) do
        local zone = C.CITY_IN[mapID] or mapID
        if not listed[zone] and not IS_BATTLEGROUND[zone] and C.ContinentOf(zone) == continent then
            listed[zone] = true
            table.insert(out, zone)
        end
    end
    table.sort(out, ByName)
    return out
end

-- The zones with quests on no continent (Forever's Zephras Isle, whose map hangs under Azeroth),
-- under a banner of their own after the continents, as the Zones tab lists them. Not a map this
-- client has never heard of: Forever's on Era would lead nowhere.
local function LooseZones()
    local out = {}
    for mapID in pairs(Index().zones) do
        if not C.CITY_IN[mapID] and not IS_BATTLEGROUND[mapID] and not C.ContinentOf(mapID)
            and not (C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID) == nil) then
            table.insert(out, mapID)
        end
    end
    table.sort(out, ByName)
    return out
end

-- The battlegrounds with quests, by name.
local function Battlegrounds()
    local out = {}
    for _, mapID in ipairs(BATTLEGROUNDS) do
        if Index().zones[mapID] then table.insert(out, mapID) end
    end
    table.sort(out, ByName)
    return out
end

-- Every quest under `mapID`, its city's included, each once.
local function QuestsIn(mapID, into)
    into = into or {}
    for _, id in ipairs(Index().zones[mapID] or {}) do into[id] = true end
    for city, around in pairs(C.CITY_IN) do
        if around == mapID then QuestsIn(city, into) end
    end
    return into
end

local function SetOf(ids)
    local set = {}
    for _, id in ipairs(ids or {}) do set[id] = true end
    return set
end

-- Found out of all, and how many of the found are in progress. Of what is listed: under Voiced
-- Only, the quests no pack has are left out of the count as they are of the rows.
local function Tally(set)
    local found, total, going = 0, 0, 0
    local voicedOnly = OnlyVoiced()
    for id in pairs(set) do
        if not voicedOnly or AnyVoiced(id) then
            total = total + 1
            if Found(id) then found = found + 1 end
            if InProgress(id) then going = going + 1 end
        end
    end
    return found, total, going
end

-- Whether a card or banner counting `found` of `total` is left out: Started Only with none
-- started, or Voiced Only with none voiced.
local function Unlisted(found, total)
    return (OnlyFound() and found == 0) or (OnlyVoiced() and total == 0)
end

-- The gossip window's mark for a quest under way, before the title of one in progress.
local IN_PROGRESS_MARK = "|TInterface\\GossipFrame\\ActiveQuestIcon:0|t "

--------------------------------------------------------------------------------
-- The chains
--------------------------------------------------------------------------------

-- A chain is the quests linked by `prev` in the data (the quest before each in its storyline),
-- known by its first quest. The client has no chain of its own to ask.
local function Prev(id)
    local quest = Quests()[id]
    local prev = quest and quest.prev
    return prev and Quests()[prev] and prev or nil
end

local hasNext
local function InChain(id)
    if not hasNext then
        hasNext = {}
        for _, quest in pairs(Quests()) do
            if quest.prev then hasNext[quest.prev] = true end
        end
    end
    return Prev(id) ~= nil or hasNext[id] == true
end

-- The first quest of `id`'s chain, and how many come before `id` in it. The data has no loops, but
-- a hand-edited file could: the walk stops where it has been.
local firstOf, stepsOf = {}, {}
local function First(id)
    if firstOf[id] then return firstOf[id], stepsOf[id] end
    local at, steps, seen = id, 0, { [id] = true }
    while Prev(at) and not seen[Prev(at)] do
        at = Prev(at)
        seen[at] = true
        steps = steps + 1
    end
    firstOf[id], stepsOf[id] = at, steps
    return at, steps
end

-- A chain's name: the one the data gives its first quest (`name`: a quest's id, whose title the
-- client gives in its own language, or words by language), else the first quest's title. The
-- same in every zone the chain crosses, where each zone's card holds only its quests there.
local function ChainName(first, ask)
    local quest = Quests()[first]
    local name = quest and quest.name
    if type(name) == "number" and Quests()[name] then return Title(name, ask) end
    if type(name) == "table" then return name[Locale()] or name[1] end
    return Title(first, ask)
end

-- In the order they are taken: by how far down the chain, then by id.
local function InOrder(ids)
    table.sort(ids, function(a, b)
        local _, sa = First(a)
        local _, sb = First(b)
        if sa ~= sb then return sa < sb end
        return a < b
    end)
    return ids
end

local chainOpen = {}

--------------------------------------------------------------------------------
-- The rows
--------------------------------------------------------------------------------

local function QuestRow(id, nest)
    return { kind = "quest", leaf = true, quest = id, label = Title(id, filter == ""),
        nest = nest, locked = not Found(id) and not Unlocked(), going = InProgress(id), done = Completed(id) }
end

local function Shows(id)
    local english = Quests()[id] and Quests()[id][1]
    return not (OnlyFound() and not Found(id)) and not (OnlyVoiced() and not AnyVoiced(id))
        and (not Filtering() or Matches(Title(id)) or Matches(english))
end

-- What a class, profession, event or other kind of quest shows on its card.
local SORT_ICON = [[Interface\Icons\INV_Scroll_03]]
-- And a dungeon's or a raid's, or a zone's card of them: a key, as to a door below.
local DUNGEON_ICON = [[Interface\Icons\INV_Misc_Key_03]]

-- A card's numbers: the completed (its share and its bar) out of all, and how many more are in
-- progress. Its badge: a zone's painting, a chain's storyline mark, a scroll for the rest.
local function Card(item, found, total, going)
    local done = found - going
    -- Places are cards: zones, cities, dungeons. A kind of quest (a class, a profession, a holiday,
    -- a zone's several dungeons) and a chain are lines of the list, what they hold under them.
    local place = item.kind == "zone" or item.kind == "dungeon" or (item.kind == "dungeons" and item.place)
    item.style = place and "card" or "group"
    -- `found`, completed or under way, is what opens: a chain with one quest started has that to show.
    item.count, item.total, item.goingCount, item.found = done, total, going, found
    item.shut = shut
    if item.kind == "zone" then
        if Spoken and Spoken.ZoneIcon then item.icon, item.iconCrop = Spoken:ZoneIcon(item.mapID) end
    elseif item.kind == "chain" then
        item.story = true
    elseif item.kind == "dungeons" or item.kind == "dungeon" then
        item.icon = DUNGEON_ICON
    else
        item.icon = SORT_ICON
    end
    item.ratio = total > 0 and done / total or 0
    item.tick = total > 0 and done == total
    item.none = found == 0
    return item
end

-- A chain's quests in one place, under a card with the chain's name.
local function ChainRows(where, first, ids, nest)
    InOrder(ids)
    local key = where .. ":" .. first
    local label = ChainName(first, filter == "")
    local found, total, going = Tally(SetOf(ids))
    if Unlisted(found, total) then return {} end
    local inside = Whole(filter ~= "" and Matches(label), function()
        local out = {}
        if chainOpen[key] or Searched() then
            for _, id in ipairs(ids) do
                if Shows(id) then table.insert(out, QuestRow(id, nest + 1)) end
            end
        end
        return out
    end)
    if Filtering() and #inside == 0 then return {} end
    return Rows(Card({ kind = "chain", key = key, ids = ids, first = first, label = label, nest = nest,
        where = where, open = #inside > 0 }, found, total, going), inside, "c" .. key)
end

-- The quests in one place (`where`): each chain of two or more of them first, by name, then the
-- rest, by title. Sorted as they are drawn: a title the client has only just given may move.
local function Leaves(ids, nest, into, where)
    local chains, single = {}, {}
    for _, id in ipairs(ids or {}) do
        if InChain(id) then
            local first = First(id)
            chains[first] = chains[first] or {}
            table.insert(chains[first], id)
        else
            table.insert(single, id)
        end
    end
    local groups = {}
    for first, members in pairs(chains) do
        if #members > 1 then
            table.insert(groups, { first = first, ids = members, name = ChainName(first) })
        else
            table.insert(single, members[1])
        end
    end
    table.sort(groups, function(a, b)
        if a.name == b.name then return a.first < b.first end
        return a.name < b.name
    end)
    for _, group in ipairs(groups) do
        for _, row in ipairs(ChainRows(where, group.first, group.ids, nest)) do table.insert(into, row) end
    end
    table.sort(single, function(a, b)
        local ta, tb = Title(a), Title(b)
        if ta == tb then return a < b end
        return ta < tb
    end)
    for _, id in ipairs(single) do
        if Shows(id) then table.insert(into, QuestRow(id, nest)) end
    end
end

-- The chain `id` is listed in, where it is listed: the key of its card, or nil where it is listed
-- on its own.
local function ChainKey(id, where, ids)
    if not InChain(id) then return nil end
    local first, count = First(id), 0
    for _, other in ipairs(ids or {}) do
        if InChain(other) and First(other) == first then count = count + 1 end
    end
    return count > 1 and (where .. ":" .. first) or nil
end

-- A dungeon's or a raid's name, as the client's Map table has it in this client's language.
local function DungeonName(id)
    local data = _G.SpokenQuestsCompendium
    local names = data and data.dungeons and data.dungeons[id]
    if not names then return tostring(id) end
    return names[Locale()] or names[1]
end

-- A zone's own quests, and its dungeons' and raids' by dungeon (`dungeon` in the data: the quest
-- log files them under the dungeon, and the data under the zone of its entrance).
local function ZoneParts(mapID)
    local own, byDungeon = {}, {}
    for _, id in ipairs(Index().zones[mapID] or {}) do
        local dungeon = Quests()[id].dungeon
        if dungeon then
            byDungeon[dungeon] = byDungeon[dungeon] or {}
            table.insert(byDungeon[dungeon], id)
        else
            table.insert(own, id)
        end
    end
    return own, byDungeon
end

-- Where a dungeon's quests are listed, for their chains' keys.
local function DungeonKey(mapID, dungeon)
    return "d" .. mapID .. (dungeon and (":" .. dungeon) or "")
end

local dungeonOpen = {}

-- A zone's dungeons' and raids' quests under one card: named after the dungeon where the zone
-- has one, else Dungeons and Raids, with a card for each dungeon inside it (Blackrock Mountain's
-- four, in Searing Gorge).
local function DungeonRows(mapID, byDungeon, nest)
    local all, dungeons = {}, {}
    for dungeon, ids in pairs(byDungeon) do
        table.insert(dungeons, dungeon)
        for _, id in ipairs(ids) do table.insert(all, id) end
    end
    if #all == 0 then return {} end
    table.sort(dungeons, function(a, b)
        local na, nb = DungeonName(a), DungeonName(b)
        if na == nb then return a < b end
        return na < nb
    end)
    local found, total, going = Tally(SetOf(all))
    if Unlisted(found, total) then return {} end
    local key, searching = DungeonKey(mapID), filter ~= ""
    local label = #dungeons == 1 and DungeonName(dungeons[1]) or L.QUESTS_DUNGEONS
    local inside = Whole(searching and Matches(label), function()
        local out = {}
        if not (dungeonOpen[key] or Searched()) then return out end
        if #dungeons == 1 then
            Leaves(all, nest + 1, out, DungeonKey(mapID, dungeons[1]))
            return out
        end
        for _, dungeon in ipairs(dungeons) do
            local ids, dkey, name = byDungeon[dungeon], DungeonKey(mapID, dungeon), DungeonName(dungeon)
            local f, t, g = Tally(SetOf(ids))
            local leaves = Whole(searching and Matches(name), function()
                local rows = {}
                if dungeonOpen[dkey] or Searched() then Leaves(ids, nest + 2, rows, dkey) end
                return rows
            end)
            if not Unlisted(f, t) and not (Filtering() and #leaves == 0) then
                for _, row in ipairs(Rows(Card({ kind = "dungeon", key = dkey, ids = ids, label = name,
                    nest = nest + 1, open = #leaves > 0 }, f, t, g), leaves, "d" .. dkey)) do
                    table.insert(out, row)
                end
            end
        end
        return out
    end)
    if Filtering() and #inside == 0 then return {} end
    return Rows(Card({ kind = "dungeons", key = key, ids = all, label = label, nest = nest, place = #dungeons == 1,
        open = #inside > 0 }, found, total, going), inside, "d" .. key)
end

-- A zone's card, and under it when it is open its city's card, its dungeons' and raids'
-- card, its chains and its quests. A city's card opens on its own, and shows only while its zone is
-- open.
local function ZoneRows(mapID, nest)
    local found, total, going = Tally(QuestsIn(mapID))
    if Unlisted(found, total) then return {} end
    local open = openZones[mapID] == true
    local inside = Whole(filter ~= "" and Matches(C.MapName(mapID)), function()
        local out = {}
        if not (open or Searched()) then return out end
        for city, around in pairs(C.CITY_IN) do
            if around == mapID and Index().zones[city] then
                for _, row in ipairs(ZoneRows(city, nest + 1)) do table.insert(out, row) end
            end
        end
        local own, byDungeon = ZoneParts(mapID)
        for _, row in ipairs(DungeonRows(mapID, byDungeon, nest + 1)) do table.insert(out, row) end
        Leaves(own, nest + 1, out, "z" .. mapID)
        return out
    end)
    if Filtering() and #inside == 0 then return {} end
    return Rows(Card({ kind = "zone", mapID = mapID, label = C.MapName(mapID), nest = nest,
        open = (open or Searched()) and #inside > 0 }, found, total, going), inside, "z" .. mapID)
end

-- A sort's card in its section's banner (Mage, Cooking, Lunar Festival), or Place Unknown's.
local function GroupRows(kind, key, label, ids)
    if not ids or #ids == 0 then return {} end
    local found, total, going = Tally(SetOf(ids))
    if Unlisted(found, total) then return {} end
    local leaves = Whole(filter ~= "" and Matches(label), function()
        local out = {}
        if groupOpen[key] or Searched() then Leaves(ids, 1, out, "s" .. key) end
        return out
    end)
    if Filtering() and #leaves == 0 then return {} end
    return Rows(Card({ kind = kind, key = key, label = label, nest = 0, open = #leaves > 0 },
        found, total, going), leaves, "g" .. key)
end

-- A section's quests, and the sorts it holds.
local function SectionSet(key)
    local set, sorts = {}, {}
    for sort, ids in pairs(Index().sorts) do
        if SectionOf(sort) == key then
            table.insert(sorts, sort)
            for _, id in ipairs(ids) do set[id] = true end
        end
    end
    if key == "other" then
        for _, id in ipairs(Index().elsewhere) do set[id] = true end
    end
    table.sort(sorts, function(a, b) return SortName(a) < SortName(b) end)
    return set, sorts
end

local function SectionRows(section)
    local set, sorts = SectionSet(section.key)
    local found, total, going = Tally(set)
    if total == 0 or Unlisted(found, total) then return {} end
    local searching = filter ~= ""
    local inside = Listed(searching and Matches(L[section.label]), function()
        local out = {}
        local function Add(rows) for _, row in ipairs(rows) do table.insert(out, row) end end
        if searching or sectionOpen[section.key] then
            for _, sort in ipairs(sorts) do Add(GroupRows("sort", sort, SortName(sort), Index().sorts[sort])) end
            if section.key == "other" then Add(GroupRows("elsewhere", "elsewhere", L.QUESTS_ELSEWHERE, Index().elsewhere)) end
        end
        return out
    end)
    if searching and #inside == 0 then return {} end
    local rows = { { style = "banner", kind = "section", key = section.key, label = L[section.label],
        count = found - going, found = found, total = total, open = #inside > 0 } }
    for _, row in ipairs(inside) do table.insert(rows, row) end
    return rows
end

-- The continents with quests, by name.
local function Continents()
    local out = {}
    for _, continent in ipairs(C.CONTINENTS) do
        if #ZonesOn(continent) > 0 then table.insert(out, continent) end
    end
    table.sort(out, ByName)
    return out
end

-- A banner holding a card for each of `zones`, opened and chosen as the sections' are.
local function ZoneBanner(key, label, zones)
    local set = {}
    for _, mapID in ipairs(zones) do QuestsIn(mapID, set) end
    local found, total, going = Tally(set)
    if total == 0 or Unlisted(found, total) then return {} end
    local searching = filter ~= ""
    local inside = Listed(searching and Matches(label), function()
        local out = {}
        if searching or sectionOpen[key] then
            for _, mapID in ipairs(zones) do
                for _, row in ipairs(ZoneRows(mapID, 0)) do table.insert(out, row) end
            end
        end
        return out
    end)
    if searching and #inside == 0 then return {} end
    local rows = { { style = "banner", kind = "section", key = key, label = label,
        count = found - going, found = found, total = total, open = #inside > 0 } }
    for _, row in ipairs(inside) do table.insert(rows, row) end
    return rows
end

-- The zones' banners apart from the continents': what each holds and its name.
local ZONE_BANNERS = {
    lands = { label = "QUESTS_SECTION_LANDS", zones = function() return LooseZones() end },
    battlegrounds = { label = "QUESTS_SECTION_BATTLEGROUNDS", zones = function() return Battlegrounds() end },
}

-- A banner for each continent, its zones' cards inside; the zones on none under a banner of their
-- own; the battlegrounds' banner; then a banner for each section.
local function BuildRows()
    local out = {}
    local function Add(rows) for _, row in ipairs(rows) do table.insert(out, row) end end
    local searching = filter ~= ""
    whole, shut = false, false
    for _, continent in ipairs(Continents()) do
        local zones = ZonesOn(continent)
        local set = {}
        for _, mapID in ipairs(zones) do QuestsIn(mapID, set) end
        local found, total, going = Tally(set)
        local rows = Listed(searching and Matches(C.MapName(continent)), function()
            local out = {}
            if searching or continentOpen[continent] then
                for _, mapID in ipairs(zones) do
                    for _, row in ipairs(ZoneRows(mapID, 0)) do table.insert(out, row) end
                end
            end
            return out
        end)
        if not Unlisted(found, total) and (not searching or #rows > 0) then
            table.insert(out, { style = "banner", kind = "continent", mapID = continent, label = C.MapName(continent),
                count = found - going, found = found, total = total, open = #rows > 0 })
            Add(rows)
        end
    end
    for _, key in ipairs({ "lands", "battlegrounds" }) do
        local banner = ZONE_BANNERS[key]
        Add(ZoneBanner(key, L[banner.label], banner.zones()))
    end
    for _, section in ipairs(SECTIONS) do Add(SectionRows(section)) end
    return out
end

local function IsSelected(row)
    if not selection then return false end
    if row.kind == "quest" then return selection.quest == row.quest end
    if row.kind == "sort" then return selection.sort == row.key end
    if row.kind == "section" then return selection.section == row.key end
    if row.kind == "elsewhere" then return selection.group == "elsewhere" end
    if row.kind == "chain" then return selection.chain == row.key end
    if row.kind == "dungeons" or row.kind == "dungeon" then return selection.dungeon == row.key end
    return selection.mapID ~= nil and selection.mapID == row.mapID
end

--------------------------------------------------------------------------------
-- The words
--------------------------------------------------------------------------------

local function Sex()
    return UnitSex and UnitSex("player") or 2
end

local function Trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Plain(text)
    return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

--- A quest's words for this character, as the client fills them: the name, class and race,
--- the word for its sex out of "$G male:female;", and $B a line break.
function QuestsTab:Fill(text)
    local name = UnitName and UnitName("player") or ""
    local class = UnitClass and UnitClass("player") or ""
    local race = UnitRace and UnitRace("player") or ""
    local female = Sex() == 3
    text = text:gsub("%$[Gg]([^:;]*):([^;]*);", function(male, her) return Trim(female and her or male) end)
    text = text:gsub("%$[Bb]", "\n")
    text = text:gsub("%$[Nn]", function() return name end)
    text = text:gsub("%$[Cc]", function() return class end)
    text = text:gsub("%$[Rr]", function() return race end)
    return text
end

-- Words the client showed, made fit for another character: where the English names the player,
-- their class or race, so does what is kept.
local function Generalise(text, english)
    english = english or ""
    local words = {
        { "N", UnitName and UnitName("player") },
        { "C", UnitClass and UnitClass("player") },
        { "R", UnitRace and UnitRace("player") },
    }
    for _, each in ipairs(words) do
        local letter, word = each[1], each[2]
        if type(word) == "string" and word ~= "" and english:find("%$[" .. letter .. letter:lower() .. "]") then
            text = text:gsub(Plain(word), "$" .. letter)
        end
    end
    return text
end

-- Each moment's words: those kept in this client's language, else the English. Kept words
-- filled for the other sex are not used where the English has a word for each.
-- One part's words, in the client's language where its window was seen, or nil.
local function PartText(id, moment)
    local english = English(id)
    local kept = Kept()
    kept = kept and kept[id]
    local text
    local own = kept and kept[moment]
    if type(own) == "table" and own.text and not (own.sex ~= Sex() and (english[moment] or ""):find("%$[Gg]")) then
        text = own.text
    end
    text = text or english[moment]
    if text and text ~= "" then return QuestsTab:Fill(text) end
end


--- Keep what the open quest window shows, in this client's language.
function QuestsTab:Keep(moment, text, title)
    local id = GetQuestID and GetQuestID()
    local kept = Kept()
    if not kept or not id or id == 0 or not Quests()[id] then return end
    kept[id] = kept[id] or {}
    if type(title) == "string" and title ~= "" then
        kept[id].title = title
        titles[id] = title
    end
    if type(text) == "string" and text ~= "" then
        kept[id][moment] = { text = Generalise(text, English(id)[moment]), sex = Sex() }
    end
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local EVENTS = { accept = VO.Enums.SoundEvent.QuestAccept, progress = VO.Enums.SoundEvent.QuestProgress,
    complete = VO.Enums.SoundEvent.QuestComplete }

-- The quest's clips queued, of one moment where `moment` is given.
local function Clips(id, moment)
    local out = {}
    for _, clip in ipairs(VO.Player:Queued()) do
        if clip.questID == id and (moment and clip.event == EVENTS[moment] or not moment and (clip.event == EVENTS.accept
            or clip.event == EVENTS.progress or clip.event == EVENTS.complete)) then
            table.insert(out, clip)
        end
    end
    return out
end

local function Voiced(id, moment)
    return VO.DataModules:PrepareSound({ event = EVENTS[moment], questID = id }) and true or false
end

-- The hand-in tells how a quest ends: it shows once the quest is completed, or with Unlock
-- Unstarted Quests on, where the player chose to see everything.
local function Shows(id, moment)
    return moment ~= "complete" or Completed(id) or Unlocked()
end

-- Who says one moment of a quest: the progress and the hand-in are said by the one it is handed
-- in to (`ender`, `enderObject` in the data, absent where that is the giver), the offer by its
-- giver, as the quest log's Play names it.
local function Speaker(id, moment)
    local DataModules, Enums = VO.DataModules, VO.Enums
    local quest = moment ~= "accept" and Quests()[id]
    if quest and quest.ender then return Enums.GUID.Creature, quest.ender end
    if quest and quest.enderObject then return Enums.GUID.GameObject, quest.enderObject end
    return DataModules:GetQuestLogQuestGiverTypeAndID(id)
end

-- What the player is given to play one moment of a quest, named and pictured for who says it.
local function SoundData(id, moment, origin)
    local DataModules, Enums = VO.DataModules, VO.Enums
    local kind, speaker = Speaker(id, moment)
    local name = speaker and DataModules:GetObjectName(kind, speaker) or Title(id)
    local guid = speaker and Enums.GUID:CanHaveID(kind) and VO.Utils:MakeGUID(kind, speaker) or nil
    return { event = EVENTS[moment], questID = id, title = Title(id), name = name, unitGUID = guid,
        text = PartText(id, moment), origin = origin }
end

-- Play on a quest's page: what is said when it is offered, under way and handed in, as far as the
-- voice packs have it, named for who says it.
local PLAY = {
    has = function(id)
        for _, moment in ipairs(MOMENTS) do
            if Voiced(id, moment) then return true end
        end
        return false
    end,
    playing = function(id) return #Clips(id) > 0 end,
    -- One part, the first a pack voices: the offer, the progress and the hand-in are said at
    -- different times, not as one speech. Its words go with it, for the window to show.
    -- `queued`: behind what the queue already holds, not played at once.
    start = function(id, queued)
        for _, moment in ipairs(MOMENTS) do
            if Shows(id, moment) and Voiced(id, moment) then
                local soundData = SoundData(id, moment, "Azeroth's Compendium")
                if queued then VO.Player:Enqueue(soundData) else VO.Player:PlayNow(soundData) end
                return
            end
        end
    end,
    stop = function(id)
        for _, clip in ipairs(Clips(id)) do VO.Player:Remove(clip) end
    end,
}

-- Each part's Play and Report, on its heading's line on the page: made once, pointed at the
-- quest shown.
local partButtons = {}

local function PartPlaying(id, moment) return #Clips(id, moment) > 0 end

local function PaintPartPlay(button)
    button.pageState = button.questID and PartPlaying(button.questID, button.moment) and "stop" or "play"
    if button.SetState then button:SetState(button.pageState) end
end

local function PartButtons(moment)
    if partButtons[moment] then return partButtons[moment] end
    if not (page and Spoken and Spoken.CreateRoundButton) then return nil end
    local child = page.body.child
    local play = Spoken:CreateRoundButton(child, "play")
    play.moment = moment
    play:SetScript("OnClick", function(self)
        local id = self.questID
        if not id then return end
        if PartPlaying(id, moment) then
            for _, clip in ipairs(Clips(id, moment)) do VO.Player:Remove(clip) end
        else
            -- One part of a quest at a time: another part playing gives way.
            for _, clip in ipairs(Clips(id)) do VO.Player:Remove(clip) end
            VO.Player:PlayNow(SoundData(id, moment, "Azeroth's Compendium"))
        end
        PaintPartPlay(self)
    end)
    play:HookScript("OnEnter", function(self)
        local words = _G.SpokenEnv and _G.SpokenEnv.L
        if not (words and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self.pageState == "stop" and words.STOP or words.PLAY)
        GameTooltip:Show()
    end)
    play:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local report = Spoken:CreateRoundButton(child, "report")
    report:SetScript("OnClick", function(self)
        local id = self.questID
        local target = id and VO.ReportButton and VO.ReportButton:TargetForQuest(id, EVENTS[moment])
        -- The language the part plays in, as the quest log's Report passes it: a fallback line is
        -- an English take under another language.
        local sound = { event = EVENTS[moment], questID = id }
        local language = VO.DataModules:PrepareSound(sound) and sound.language or nil
        if target then VO.ReportButton:ShowLink(target, language) end
    end)
    report:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.OPT_REPORT_PROBLEM)
        GameTooltip:AddLine(L.OPT_REPORT_QUEST_TIP, 1, 0.8, 0.2, true)
        GameTooltip:Show()
    end)
    report:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    play:Hide()
    report:Hide()
    partButtons[moment] = { play = play, report = report }
    return partButtons[moment]
end

-- A quest's words in parts, the offer, the progress and the hand-in each under its heading, with
-- Play and Report for that part where a pack voices it; the hand-in only where it Shows. nil with
-- no words at all.
local function Parts(id)
    local parts = {}
    local reportsHidden = Spoken and Spoken.AreReportButtonsHidden and Spoken:AreReportButtonsHidden()
    for _, moment in ipairs(MOMENTS) do
        local text = Shows(id, moment) and PartText(id, moment)
        if text then
            local buttons = PartButtons(moment)
            local list = {}
            if buttons then
                local voiced = Voiced(id, moment)
                buttons.play.questID, buttons.report.questID = id, id
                buttons.report:SetShown(voiced and not reportsHidden)
                buttons.play:SetShown(voiced)
                PaintPartPlay(buttons.play)
                list = { buttons.report, buttons.play }
            end
            table.insert(parts, { heading = L[HEADINGS[moment]], text = text, buttons = list })
        end
    end
    return #parts > 0 and parts or nil
end

-- Asked once a refresh: Voiced Only asks it of every quest under every banner, and the packs
-- do not change while the list is drawn.
local voicedSeen = {}
AnyVoiced = function(id)
    if voicedSeen[id] == nil then voicedSeen[id] = PLAY.has(id) end
    return voicedSeen[id]
end

local function Where(id)
    local quest = Quests()[id] or {}
    if quest.zones and #quest.zones > 0 then
        local names = {}
        for _, mapID in ipairs(quest.zones) do table.insert(names, C.MapName(mapID)) end
        return table.concat(names, ", ")
    end
    if quest.sort then return SortName(quest.sort) end
    return L.QUESTS_ELSEWHERE
end

local function Count(set)
    local found, total, going = Tally(set)
    if going > 0 then return L.QUESTS_FOUND_GOING_FMT:format(found - going, total, going) end
    return L.QUESTS_FOUND_FMT:format(found, total)
end

-- The place one level up from a zone, as the Zones tab nests them: a city's zone, a zone's
-- continent, and the world for a continent or a zone on none.
local function Above(mapID)
    for _, continent in ipairs(C.CONTINENTS) do
        if continent == mapID then return C.WORLD end
    end
    return C.CITY_IN[mapID] or C.ContinentOf(mapID) or C.WORLD
end

-- What lists a chain, from where its card is (Leaves' `where`): a zone, a dungeon, a class's,
-- profession's or event's card, or Place Unknown.
local function HolderName(where)
    local zone = where:match("^z(%d+)$")
    if zone then return C.MapName(tonumber(zone)) end
    local dungeon = where:match("^d%d+:(%d+)$")
    if dungeon then return DungeonName(tonumber(dungeon)) end
    local sort = where:match("^s(.+)$")
    if sort == "elsewhere" then return L.QUESTS_ELSEWHERE end
    if sort then return SortName(tonumber(sort) or sort) end
end

-- A page's line: where it is and its count, one line, or the count alone with nowhere to name.
local function Line(where, set)
    if not where then return Count(set) end
    return L.QUESTS_IN_FMT:format(where) .. " · " .. Count(set)
end

-- In progress, before where it is: the line is cut short where a quest is given in several zones.
local function Subtitle(id)
    if InProgress(id) then return IN_PROGRESS_MARK .. L.QUEST_IN_PROGRESS .. " • " .. Where(id) end
    return Where(id)
end

local function ShowEntry()
    if not page then return end
    if not selection then
        page:Show({ title = L.COMPENDIUM_QUESTS, subtitle = Count(Index().all), text = L.QUESTS_PICK })
        return
    end
    if selection.chain then
        local ids = selection.ids
        -- As a zone's page: its name, where it is and its count, and the quests on the left to choose.
        page:Show({ title = ChainName(selection.first or First(ids[1])),
            subtitle = Line(selection.where and HolderName(selection.where), SetOf(ids)), text = L.QUESTS_PICK })
        return
    end
    if selection.quest then
        local id = selection.quest
        if not Found(id) and not Unlocked() then
            page:Show({ title = Title(id), subtitle = Where(id), text = L.QUEST_NOT_FOUND })
            return
        end
        -- Play and Report on each part's heading, not the page's: each part is said at its own time.
        page:Show({ title = Title(id), subtitle = Subtitle(id), parts = Parts(id), text = L.QUEST_NO_TEXT })
        return
    end
    if selection.dungeon then
        -- In the zone of its entrance, whose card holds it.
        local zone = tonumber(selection.dungeon:match("^d(%d+)"))
        page:Show({ title = selection.label, subtitle = Line(zone and C.MapName(zone), SetOf(selection.ids)),
            text = L.QUESTS_PICK })
        return
    end
    local banner = selection.section and ZONE_BANNERS[selection.section]
    if banner then
        local set = {}
        for _, mapID in ipairs(banner.zones()) do QuestsIn(mapID, set) end
        page:Show({ title = L[banner.label], subtitle = Line(C.MapName(C.WORLD), set), text = L.QUESTS_PICK })
        return
    end
    -- Classes, Professions, Holidays and Events and Other are no place: their count alone.
    if selection.section then
        for _, section in ipairs(SECTIONS) do
            if section.key == selection.section then
                page:Show({ title = L[section.label], subtitle = Count((SectionSet(section.key))), text = L.QUESTS_PICK })
            end
        end
        return
    end
    if selection.sort then
        local section
        for _, each in ipairs(SECTIONS) do
            if each.key == SectionOf(selection.sort) then section = L[each.label] end
        end
        page:Show({ title = SortName(selection.sort), subtitle = Line(section, SetOf(Index().sorts[selection.sort])),
            text = L.QUESTS_PICK })
        return
    end
    if selection.group == "elsewhere" then
        page:Show({ title = L.QUESTS_ELSEWHERE, subtitle = Count(SetOf(Index().elsewhere)), text = L.QUESTS_PICK })
        return
    end
    local set = {}
    if selection.mapID == 1414 or selection.mapID == 1415 then
        for _, mapID in ipairs(ZonesOn(selection.mapID)) do QuestsIn(mapID, set) end
    else
        QuestsIn(selection.mapID, set)
    end
    page:Show({ title = C.MapName(selection.mapID), subtitle = Line(C.MapName(Above(selection.mapID)), set),
        text = L.QUESTS_PICK })
end

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

local function OnClick(row)
    if row.kind == "quest" and IsShiftKeyDown and IsShiftKeyDown() then
        PLAY.start(row.quest, true)
        return
    end
    if row.kind == "quest" then
        selection = { quest = row.quest }
    elseif row.kind == "chain" then
        if not SearchFold(row) and (filter == "" or row.shut) then chainOpen[row.key] = not chainOpen[row.key] end
        selection = { chain = row.key, ids = row.ids, first = row.first, where = row.where }
    elseif row.kind == "dungeons" or row.kind == "dungeon" then
        if not SearchFold(row) and (filter == "" or row.shut) then dungeonOpen[row.key] = not dungeonOpen[row.key] end
        selection = { dungeon = row.key, ids = row.ids, label = row.label }
    elseif row.kind == "section" then
        if filter == "" then sectionOpen[row.key] = not sectionOpen[row.key] end
        selection = { section = row.key }
    elseif row.kind == "sort" or row.kind == "elsewhere" then
        if not SearchFold(row) and (filter == "" or row.shut) then groupOpen[row.key] = not groupOpen[row.key] end
        selection = row.kind == "sort" and { sort = row.key } or { group = "elsewhere" }
    elseif filter ~= "" and not row.shut then
        SearchFold(row)
        selection = { mapID = row.mapID }
    elseif row.kind == "continent" then
        continentOpen[row.mapID] = not continentOpen[row.mapID]
        selection = { mapID = row.mapID }
    else
        -- A zone's or city's card opens and closes alone.
        openZones[row.mapID] = not openZones[row.mapID] or nil
        selection = { mapID = row.mapID }
    end
    QuestsTab:Refresh()
end

-- The zone the player stands in that has quests listed, walking up from an inn's or a cave's
-- map, or nil.
local function PlayerZone()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local steps = 0
    while map and steps < 8 do
        if Index().zones[map] then return map end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        map, steps = info and info.parentMapID, steps + 1
    end
end

-- Open what holds a zone's card: the battlegrounds' banner, its continent's, or the banner of the
-- zones on none.
local function OpenAround(zone)
    if IS_BATTLEGROUND[zone] then
        sectionOpen.battlegrounds = true
        return
    end
    local continent = C.ContinentOf(C.CITY_IN[zone] or zone)
    if continent then
        continentOpen[continent] = true
    else
        sectionOpen.lands = true
    end
end

-- Open a zone's card and, for a city, the zone's around it, leaving the others as they are.
local function OpenZone(zone)
    openZones[zone] = true
    if C.CITY_IN[zone] then openZones[C.CITY_IN[zone]] = true end
end

-- Choose where the player stands: their zone, opened, else the first continent. The tab never
-- shows a page with nothing chosen.
local function LandOnPlayer()
    local zone = PlayerZone()
    if zone then
        selection = { mapID = zone }
        OpenZone(zone)
        OpenAround(zone)
    else
        local first = Continents()[1]
        selection = first and { mapID = first } or nil
    end
    landed = selection
end

-- The chosen row brought into view. The client's scroll frame takes an offset only within the
-- range it last measured, and a list drawn for the first time has none measured yet; nor has the
-- frame a height until the window is first laid out. Either left the list at its top, the chosen
-- zone off screen: the range is measured now, and the row brought into view again a frame later.
local function ScrollToChosen(items)
    if list.scroll.UpdateScrollChildRect then list.scroll:UpdateScrollChildRect() end
    list:ScrollToSelection(items)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if filter == "" and list.items then list:ScrollToSelection(list.items) end
        end)
    end
end

function QuestsTab:Refresh(scrollToSelection)
    if not list then return end
    ReadCompleted()
    ReadLog()
    voicedSeen = {}
    if not selection then
        LandOnPlayer()
        scrollToSelection = true
    end
    local items = list:Render()
    if scrollToSelection and selection then ScrollToChosen(items) end
    ShowEntry()
end

local function Build(panel)
    list = C.NewList(panel, {
        search = L.QUESTS_SEARCH,
        none = L.QUESTS_NONE,
        only = L.QUESTS_FOUND_ONLY,
        onlyGet = OnlyFound,
        onlySet = function(on) Global().FoundOnly = on end,
        checks = { { label = L.QUESTS_VOICED_ONLY, get = OnlyVoiced, set = function(on) Global().VoicedOnly = on end } },
        build = BuildRows,
        isSelected = IsSelected,
        onClick = OnClick,
        onSearch = function(text)
            filter = text
            searchClosed = {}
            QuestsTab:Refresh()
        end,
        addScrollBar = function(scroll, child, inset) return ns:AddScrollBar(scroll, child, inset) end,
    })
    panel.Refresh = function() QuestsTab:Refresh() end
    panel.inset, panel.filterButton, panel.filterMenu, panel.noMatch = list.inset, list.filterButton, list.filterMenu, list.noMatch

    local _, right = C.Margins()
    local window = C:Window()
    local ok, pageInset = pcall(CreateFrame, "Frame", nil, panel, "InsetFrameTemplate")
    if not ok or not pageInset then pageInset = CreateFrame("Frame", nil, panel) end
    pageInset:SetPoint("TOPLEFT", list.inset, "TOPRIGHT", 6, 38)
    pageInset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -right, window.templated and 6 or 12)
    panel.pageInset = pageInset
    local holder = CreateFrame("Frame", nil, pageInset)
    holder:SetPoint("TOPLEFT", pageInset, "TOPLEFT", 3, -3)
    holder:SetPoint("BOTTOMRIGHT", pageInset, "BOTTOMRIGHT", -3, 3)
    page = C.NewPage(holder, ns, PLAY)
    -- The parts' Play show Stop while their part plays, and their Report follows Hide Report Buttons.
    if Spoken and Spoken.RegisterCallback then
        Spoken:RegisterCallback("AUDIO_CHANGED", function()
            for _, buttons in pairs(partButtons) do PaintPartPlay(buttons.play) end
        end)
        Spoken:RegisterCallback("REPORT_SETTINGS_CHANGED", function()
            if selection and selection.quest then ShowEntry() end
        end)
    end
    -- One line, cut short: a quest given in several zones names them all.
    if page.sub.SetWordWrap then page.sub:SetWordWrap(false) end
    if page.sub.SetMaxLines then page.sub:SetMaxLines(1) end
    if type(pageInset.NineSlice) == "table" and pageInset.NineSlice.SetFrameLevel then
        pageInset.NineSlice:SetFrameLevel(holder:GetFrameLevel() + 5)
    end
    panel.page = page
    QuestsTab.panel = panel
end

-- Whether this character has started `id`, asked now: what the tab last read may be from before
-- the quest was handed in.
local function StartedNow(id)
    local ask = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    if ask then
        if ask(id) then return true end
    else
        local done = GetQuestsCompleted and GetQuestsCompleted()
        if type(done) == "table" and done[id] then return true end
    end
    if C_QuestLog and C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(id) and true or false end
    return GetQuestLogIndexByID ~= nil and (GetQuestLogIndexByID(id) or 0) > 0
end

--- Whether the tab is there, its part is on, and it lists `questID` for this character's race and
--- class.
function QuestsTab:Lists(questID)
    return C ~= nil and C:Tab("quests") ~= nil and VO.Addon:IsPartOn() and questID ~= nil and Index().all[questID] == true
end

--- Whether opening the tab on `questID` shows its page: the list shows the quest (Started Only
--- leaves out one not started, Voiced Only one no pack has) and it is started, or Unlock Unstarted
--- Quests is on.
function QuestsTab:Has(questID)
    if not self:Lists(questID) then return false end
    if OnlyVoiced() and not PLAY.has(questID) then return false end
    if StartedNow(questID) then return true end
    return Unlocked() and not OnlyFound()
end

--- A quest's title in the client's language once it is known, else the English.
function QuestsTab:Title(questID)
    return Title(questID)
end

--- Open the quests, on `questID` when one is given: chosen, with what holds it opened.
function QuestsTab:Open(questID)
    if not C then return end
    local quest = questID and Quests()[questID]
    if quest then
        selection = { quest = questID }
        local zone = quest.zones and quest.zones[1]
        local chain
        if zone then
            OpenZone(zone)
            OpenAround(zone)
            local own, byDungeon = ZoneParts(zone)
            if quest.dungeon and byDungeon[quest.dungeon] then
                dungeonOpen[DungeonKey(zone)] = true
                dungeonOpen[DungeonKey(zone, quest.dungeon)] = true
                chain = ChainKey(questID, DungeonKey(zone, quest.dungeon), byDungeon[quest.dungeon])
            else
                chain = ChainKey(questID, "z" .. zone, own)
            end
        else
            local named = quest.sort and (SpokenQuestsCompendium.sorts[quest.sort] or GROUP_NAMES[quest.sort])
            local key = named and quest.sort or "elsewhere"
            groupOpen[key] = true
            sectionOpen[named and SectionOf(quest.sort) or "other"] = true
            chain = ChainKey(questID, "s" .. key, named and Index().sorts[quest.sort] or Index().elsewhere)
        end
        if chain then chainOpen[chain] = true end
    elseif selection == landed then
        -- Opened from the minimap, on where the player stands now.
        selection = nil
    end
    if list then
        list:ClearSearch()
        filter = ""
    end
    C:Open("quests")
    C:Expand()
    self:Refresh(true)
end

local function Visible()
    return QuestsTab.panel ~= nil and QuestsTab.panel:IsVisible()
end

local function OnEvent(_, event, a)
    if event == "QUEST_DETAIL" then
        QuestsTab:Keep("accept", GetQuestText and GetQuestText(), GetTitleText and GetTitleText())
    elseif event == "QUEST_PROGRESS" then
        QuestsTab:Keep("progress", GetProgressText and GetProgressText(), GetTitleText and GetTitleText())
    elseif event == "QUEST_COMPLETE" then
        QuestsTab:Keep("complete", GetRewardText and GetRewardText(), GetTitleText and GetTitleText())
    elseif event == "QUEST_TURNED_IN" then
        if Visible() then QuestsTab:Refresh() end
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
        -- QUEST_LOG_UPDATE comes with every objective done, and in bursts: the list is drawn again
        -- once, a moment after the last, and only when the quests in the log have changed.
        if not QuestsTab.logPending and Visible() and C_Timer and C_Timer.After then
            QuestsTab.logPending = true
            C_Timer.After(0.3, function()
                QuestsTab.logPending = false
                if Visible() and ReadLog() then QuestsTab:Refresh() end
            end)
        end
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        -- Titles arrive one by one: the list is drawn again once, a moment after the last.
        if asked[a] and not QuestsTab.pending and Visible() and C_Timer and C_Timer.After then
            QuestsTab.pending = true
            C_Timer.After(0.3, function()
                QuestsTab.pending = false
                QuestsTab:Refresh()
            end)
        end
    end
end

--- Add the tab to Azeroth's Compendium, where Spoken Books or Spoken Zones has loaded it.
function QuestsTab:Setup()
    C = _G.SpokenCompendium
    if not C or C:Tab("quests") or not _G.SpokenQuestsCompendium then return end
    C:Register("quests", {
        label = L.COMPENDIUM_QUESTS,
        -- The first tab, before Zones (1) and Books (2); the window takes its title from it.
        order = 0,
        title = L.COMPENDIUM_TITLE,
        build = Build,
        open = function() QuestsTab:Open() end,
        -- Come back to from another tab: where the player stands now, unless they chose here.
        onShow = function() if selection == landed then selection = nil end end,
        enabled = function() return VO.Addon:IsPartOn() end,
        -- Unlock Unstarted Quests, on Spoken's page.
        unlock = {
            get = function() return Unlocked() end,
            set = function(value)
                Global().UnlockUnfound = value and true or false
                QuestsTab:Refresh()
            end,
        },
    })
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_TURNED_IN",
        "QUEST_DATA_LOAD_RESULT", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", OnEvent)
    if self.SetupOpenButtons then self:SetupOpenButtons() end
end

-- Once the world is up: Spoken Zones, which may be the addon carrying the window, loads after this one.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    local ok, err = pcall(QuestsTab.Setup, QuestsTab)
    if not ok and VO.Debug then VO.Debug:Record("compendium-error", tostring(err)) end
end)
