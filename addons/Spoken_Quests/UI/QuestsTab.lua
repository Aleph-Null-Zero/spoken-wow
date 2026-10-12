-- The quests in Azeroth's Compendium, the window Spoken Books and Spoken Zones carry: every quest
-- this character's race and class may take, by zone, with class, profession, event and other
-- quests apart. A quest is found once this character has started it: completed, or in its quest
-- log, which is marked in progress on its row and its page. Until then it is greyed and does not
-- open, unless Unlock Unstarted Quests is on.
--
-- The list is the Compendium's cards: a banner for each continent, holding a card for each zone
-- (with its city as a small card inside it), a card for each zone on no continent, a banner for
-- the battlegrounds, then a banner each for Classes, Professions, Events and Other, holding a
-- small card for each class, profession, event or other kind of quest. A
-- card says how many of its quests are completed and how many in progress, with a bar. Inside a
-- place, the quests that follow one another (`prev` in the data) are a small card for their chain,
-- named after the first of them; the rest are rows of their own. A chain's page lists its quests
-- in order with the start of each one's offer.
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
                         -- | { chain = key, ids = { id... } } | nil
local landed             -- the selection made for the player, where they stood; any other they chose
local expandedZone
local continentOpen = { [1414] = true, [1415] = true }
local groupOpen = {}
local sectionOpen = {}

-- The quests filed under no zone, apart from Azeroth's: by what their QuestSort is. Any other sort
-- goes under Other, with the quests that have no place at all.
local SECTIONS = {
    { key = "classes", label = "QUESTS_SECTION_CLASSES",
        sorts = { [61] = true, [81] = true, [82] = true, [141] = true, [161] = true, [162] = true, [261] = true,
            [262] = true, [263] = true } },
    { key = "professions", label = "QUESTS_SECTION_PROFESSIONS",
        sorts = { [24] = true, [101] = true, [121] = true, [181] = true, [182] = true, [201] = true, [264] = true,
            [304] = true, [324] = true } },
    { key = "events", label = "QUESTS_SECTION_EVENTS",
        sorts = { [22] = true, [364] = true, [365] = true, [366] = true, [368] = true, [369] = true } },
    { key = "other", label = "QUESTS_SECTION_OTHER" },
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

-- Every quest this character may take, by where it is: index.zones[mapID], index.sorts[sort],
-- index.elsewhere, and `all`. Built once: neither the data nor the character's race and class
-- change in a session.
local index
function Index()
    if index then return index end
    index = { zones = {}, sorts = {}, elsewhere = {}, all = {}, zoned = {} }
    local named = _G.SpokenQuestsCompendium and SpokenQuestsCompendium.sorts or {}
    for id, quest in pairs(Quests()) do
        if Allowed(quest) then
            index.all[id] = true
            if quest.zones and #quest.zones > 0 then
                index.zoned[id] = true
                for _, mapID in ipairs(quest.zones) do
                    index.zones[mapID] = index.zones[mapID] or {}
                    table.insert(index.zones[mapID], id)
                end
            -- A sort the data has no name for has no row of its own to go under.
            elseif quest.sort and named[quest.sort] then
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
-- as cards of their own after the continents, as the Zones tab lists them. Not a map this client
-- has never heard of: Forever's on Era would lead nowhere.
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

-- Found out of all, and how many of the found are in progress.
local function Tally(set)
    local found, total, going = 0, 0, 0
    for id in pairs(set) do
        total = total + 1
        if Found(id) then found = found + 1 end
        if InProgress(id) then going = going + 1 end
    end
    return found, total, going
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
    return not (OnlyFound() and not Found(id)) and (filter == "" or Matches(Title(id)) or Matches(english))
end

-- What a class, profession, event or other kind of quest shows on its card.
local SORT_ICON = [[Interface\Icons\INV_Scroll_03]]

-- A card's numbers: the completed (its share and its bar) out of all, and how many more are in
-- progress. Its badge: a zone's painting, a chain's storyline mark, a scroll for the rest.
local function Card(item, found, total, going)
    local done = found - going
    local sub = L.QUESTS_CARD_FMT:format(done, total)
    if going > 0 then sub = sub .. " · " .. L.QUESTS_CARD_GOING_FMT:format(going) end
    item.style = "card"
    item.count, item.total = done, total
    if item.kind == "zone" then
        if Spoken and Spoken.ZoneIcon then item.icon, item.iconCrop = Spoken:ZoneIcon(item.mapID) end
    elseif item.kind == "chain" then
        item.story = true
    else
        item.icon = SORT_ICON
    end
    item.sub = sub
    item.ratio = total > 0 and done / total or 0
    item.tick = total > 0 and done == total
    item.none = found == 0
    return item
end

-- A chain's quests in one place, under a small card named after the first of them.
local function ChainRows(where, first, ids, nest)
    InOrder(ids)
    local key = where .. ":" .. first
    local label = Title(ids[1], filter == "")
    local found, total, going = Tally(SetOf(ids))
    if OnlyFound() and found == 0 then return {} end
    local named = filter ~= "" and Matches(label)
    local inside = {}
    if chainOpen[key] or filter ~= "" then
        for _, id in ipairs(ids) do
            if named and not (OnlyFound() and not Found(id)) or Shows(id) then
                table.insert(inside, QuestRow(id, nest + 1))
            end
        end
    end
    if filter ~= "" and #inside == 0 then return {} end
    local rows = { Card({ kind = "chain", small = true, key = key, ids = ids, label = label, nest = nest,
        open = #inside > 0 }, found, total, going) }
    for _, row in ipairs(inside) do table.insert(rows, row) end
    return rows
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
            table.insert(groups, { first = first, ids = members, name = Title(InOrder(members)[1]) })
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

-- A zone's card, and under it when it is open its city's small card, its chains and its quests.
local function ZoneRows(mapID, nest, small)
    local found, total, going = Tally(QuestsIn(mapID))
    if OnlyFound() and found == 0 then return {} end
    local open = expandedZone == mapID or C.CITY_IN[expandedZone] == mapID
    local inside = {}
    if open or filter ~= "" then
        for city, around in pairs(C.CITY_IN) do
            if around == mapID and Index().zones[city] then
                for _, row in ipairs(ZoneRows(city, nest + 1, true)) do table.insert(inside, row) end
            end
        end
        Leaves(Index().zones[mapID], nest + 1, inside, "z" .. mapID)
    end
    if filter ~= "" and #inside == 0 and not Matches(C.MapName(mapID)) then return {} end
    local rows = { Card({ kind = "zone", small = small, mapID = mapID, label = C.MapName(mapID), nest = nest,
        open = (open or filter ~= "") and #inside > 0 }, found, total, going) }
    for _, row in ipairs(inside) do table.insert(rows, row) end
    return rows
end

-- A sort's small card in its section's banner (Mage, Cooking, Lunar Festival), or Place Unknown's.
local function GroupRows(kind, key, label, ids)
    if not ids or #ids == 0 then return {} end
    local found, total, going = Tally(SetOf(ids))
    if OnlyFound() and found == 0 then return {} end
    local leaves = {}
    if groupOpen[key] or filter ~= "" then Leaves(ids, 1, leaves, "s" .. key) end
    if filter ~= "" and #leaves == 0 then return {} end
    local rows = { Card({ kind = kind, small = true, key = key, label = label, nest = 0, open = #leaves > 0 },
        found, total, going) }
    for _, row in ipairs(leaves) do table.insert(rows, row) end
    return rows
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
    if total == 0 or (OnlyFound() and found == 0) then return {} end
    local searching = filter ~= ""
    local inside = {}
    local function Add(rows) for _, row in ipairs(rows) do table.insert(inside, row) end end
    if searching or sectionOpen[section.key] then
        for _, sort in ipairs(sorts) do Add(GroupRows("sort", sort, SortName(sort), Index().sorts[sort])) end
        if section.key == "other" then Add(GroupRows("elsewhere", "elsewhere", L.QUESTS_ELSEWHERE, Index().elsewhere)) end
    end
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

-- The battlegrounds' banner, their cards inside.
local function BattlegroundRows()
    local zones = Battlegrounds()
    local set = {}
    for _, mapID in ipairs(zones) do QuestsIn(mapID, set) end
    local found, total, going = Tally(set)
    if total == 0 or (OnlyFound() and found == 0) then return {} end
    local searching = filter ~= ""
    local inside = {}
    if searching or sectionOpen.battlegrounds then
        for _, mapID in ipairs(zones) do
            for _, row in ipairs(ZoneRows(mapID, 0)) do table.insert(inside, row) end
        end
    end
    if searching and #inside == 0 then return {} end
    local rows = { { style = "banner", kind = "section", key = "battlegrounds", label = L.QUESTS_SECTION_BATTLEGROUNDS,
        count = found - going, found = found, total = total, open = #inside > 0 } }
    for _, row in ipairs(inside) do table.insert(rows, row) end
    return rows
end

-- A banner for each continent, its zones' cards inside; the zones on none as cards of their own;
-- the battlegrounds' banner; then a banner for each section.
local function BuildRows()
    local out = {}
    local function Add(rows) for _, row in ipairs(rows) do table.insert(out, row) end end
    local searching = filter ~= ""
    for _, continent in ipairs(Continents()) do
        local zones = ZonesOn(continent)
        local set = {}
        for _, mapID in ipairs(zones) do QuestsIn(mapID, set) end
        local found, total, going = Tally(set)
        local rows = {}
        if searching or continentOpen[continent] then
            for _, mapID in ipairs(zones) do
                for _, row in ipairs(ZoneRows(mapID, 0)) do table.insert(rows, row) end
            end
        end
        if not (OnlyFound() and found == 0) and (not searching or #rows > 0) then
            table.insert(out, { style = "banner", kind = "continent", mapID = continent, label = C.MapName(continent),
                count = found - going, found = found, total = total, open = #rows > 0 })
            Add(rows)
        end
    end
    for _, mapID in ipairs(LooseZones()) do Add(ZoneRows(mapID, 0)) end
    Add(BattlegroundRows())
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
    return selection.mapID ~= nil and selection.mapID == row.mapID
end

-- A chain's page marks each quest as its row does: the quest log's gold tick once completed, the
-- quest mark while under way, a padlock until started. Where the client has not got the atlases,
-- the checkbox's tick and no padlock.
local TICK = "|TInterface\\Buttons\\UI-CheckBox-Check:0|t "
local function AtlasMark(atlas, height, width, fallback)
    if C and C.HasAtlas and C.HasAtlas(atlas) then return ("|A:%s:%d:%d|a "):format(atlas, height, width) end
    return fallback
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

local function Words(id)
    local parts = {}
    for _, moment in ipairs(MOMENTS) do
        local text = PartText(id, moment)
        if text then
            table.insert(parts, L[HEADINGS[moment]])
            table.insert(parts, text)
        end
    end
    return #parts > 0 and table.concat(parts, "\n\n") or L.QUEST_NO_TEXT
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

-- What the player is given to play one moment of a quest, named for its giver as the quest log's
-- Play names it.
local function SoundData(id, moment, origin)
    local DataModules, Enums = VO.DataModules, VO.Enums
    local kind, giver = DataModules:GetQuestLogQuestGiverTypeAndID(id)
    local name = giver and DataModules:GetObjectName(kind, giver) or Title(id)
    local guid = giver and Enums.GUID:CanHaveID(kind) and VO.Utils:MakeGUID(kind, giver) or nil
    return { event = EVENTS[moment], questID = id, title = Title(id), name = name, unitGUID = guid,
        text = PartText(id, moment), origin = origin }
end

-- Play on a quest's page: what is said when it is offered, under way and handed in, as far as the
-- voice packs have it, named for its giver as the quest log's Play names it.
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
            if Voiced(id, moment) then
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

-- In progress, before where it is: the line is cut short where a quest is given in several zones.
local function Subtitle(id)
    if InProgress(id) then return IN_PROGRESS_MARK .. L.QUEST_IN_PROGRESS .. " • " .. Where(id) end
    return Where(id)
end

-- Where the next sentence of `text` ends after `from`: a full stop, a question or an exclamation,
-- the Latin or the Chinese.
local SENTENCE_ENDS = { "[%.!%?]+[\"']?%s", "。", "！", "？" }
local function SentenceEnd(text, from)
    local best
    for _, pattern in ipairs(SENTENCE_ENDS) do
        local _, stop = text:find(pattern, from)
        if stop and (not best or stop < best) then best = stop end
    end
    return best
end

-- The first sentence of an offer, and the next with it where the first is short; cut at a word
-- (or, in a language without spaces, at a whole letter) with an ellipsis where they run long.
local EXCERPT_SHORT, EXCERPT_MOST = 90, 260
local function Excerpt(text)
    text = Trim((text:gsub("%s+", " ")))
    local stop = SentenceEnd(text, 1)
    if stop and stop < EXCERPT_SHORT then stop = SentenceEnd(text, stop + 1) or stop end
    local excerpt = Trim(stop and text:sub(1, stop) or text)
    if #excerpt <= EXCERPT_MOST then return excerpt end
    -- Back to where a letter starts, so the cut never splits one.
    local n = EXCERPT_MOST
    while n > 0 and excerpt:byte(n + 1) >= 0x80 and excerpt:byte(n + 1) < 0xC0 do n = n - 1 end
    local head = excerpt:sub(1, n)
    return (head:match("^(.*%S)%s") or head) .. "…"
end

-- A chain's quests in the order they are taken: each one's mark and title, "Not started" under one
-- not started yet, and the start of its offer where it can be read; a blank line between them.
local function ChainText(ids)
    local blocks = {}
    for _, id in ipairs(ids) do
        local mark
        if Completed(id) then
            mark = AtlasMark("questlog-icon-checkmark-yellow", 14, 17, TICK)
        elseif InProgress(id) then
            mark = IN_PROGRESS_MARK
        else
            mark = AtlasMark("LFG-lock", 16, 13, "")
        end
        local lines = { mark .. Title(id) }
        if not Found(id) then table.insert(lines, L.QUEST_NOT_STARTED) end
        if Found(id) or Unlocked() then
            local offer = PartText(id, "accept")
            if offer then table.insert(lines, Excerpt(offer)) end
        end
        table.insert(blocks, table.concat(lines, "\n"))
    end
    return table.concat(blocks, "\n\n")
end

-- What Play plays on a chain's page: the first quest of it that can be read and a pack voices.
local function ChainTarget(ids)
    for _, id in ipairs(ids) do
        if (Found(id) or Unlocked()) and PLAY.has(id) then return id end
    end
end

local function ShowEntry()
    if not page then return end
    if not selection then
        page:Show({ title = L.COMPENDIUM_QUESTS, subtitle = Count(Index().all), text = L.QUESTS_PICK })
        return
    end
    if selection.chain then
        local ids = selection.ids
        page:Show({ title = Title(ids[1]), subtitle = Count(SetOf(ids)), text = ChainText(ids), target = ChainTarget(ids) })
        return
    end
    if selection.quest then
        local id = selection.quest
        if not Found(id) and not Unlocked() then
            page:Show({ title = Title(id), subtitle = Where(id), text = L.QUEST_NOT_FOUND })
            return
        end
        page:Show({ title = Title(id), subtitle = Subtitle(id), text = Words(id), target = id })
        return
    end
    if selection.section == "battlegrounds" then
        local set = {}
        for _, mapID in ipairs(Battlegrounds()) do QuestsIn(mapID, set) end
        page:Show({ title = L.QUESTS_SECTION_BATTLEGROUNDS, subtitle = Count(set), text = L.QUESTS_PICK })
        return
    end
    if selection.section then
        for _, section in ipairs(SECTIONS) do
            if section.key == selection.section then
                page:Show({ title = L[section.label], subtitle = Count((SectionSet(section.key))), text = L.QUESTS_PICK })
            end
        end
        return
    end
    if selection.sort then
        page:Show({ title = SortName(selection.sort), subtitle = Count(SetOf(Index().sorts[selection.sort])),
            text = L.QUESTS_PICK })
        return
    end
    if selection.group == "elsewhere" then
        page:Show({ title = L.QUESTS_ELSEWHERE, subtitle = Count(SetOf(Index().elsewhere)), text = L.QUESTS_PICK })
        return
    end
    local set = {}
    if selection.mapID == C.WORLD then
        set = Index().zoned
    elseif selection.mapID == 1414 or selection.mapID == 1415 then
        for _, mapID in ipairs(ZonesOn(selection.mapID)) do QuestsIn(mapID, set) end
    else
        QuestsIn(selection.mapID, set)
    end
    page:Show({ title = C.MapName(selection.mapID), subtitle = Count(set), text = L.QUESTS_PICK })
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
        if filter == "" then chainOpen[row.key] = not chainOpen[row.key] end
        selection = { chain = row.key, ids = row.ids }
    elseif row.kind == "section" then
        if filter == "" then sectionOpen[row.key] = not sectionOpen[row.key] end
        selection = { section = row.key }
    elseif row.kind == "sort" or row.kind == "elsewhere" then
        if filter == "" then groupOpen[row.key] = not groupOpen[row.key] end
        selection = row.kind == "sort" and { sort = row.key } or { group = "elsewhere" }
    elseif filter ~= "" then
        selection = { mapID = row.mapID }
    elseif row.kind == "continent" then
        continentOpen[row.mapID] = not continentOpen[row.mapID]
        selection = { mapID = row.mapID }
    else
        if expandedZone == row.mapID or C.CITY_IN[expandedZone] == row.mapID then
            expandedZone = C.CITY_IN[row.mapID]
        else
            expandedZone = row.mapID
        end
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

-- Open what holds a zone's card: the battlegrounds' banner, or its continent's.
local function OpenAround(zone)
    if IS_BATTLEGROUND[zone] then
        sectionOpen.battlegrounds = true
        return
    end
    local continent = C.ContinentOf(C.CITY_IN[zone] or zone)
    if continent then continentOpen[continent] = true end
end

-- Choose where the player stands: their zone, opened, else the first continent. The tab never
-- shows a page with nothing chosen.
local function LandOnPlayer()
    local zone = PlayerZone()
    if zone then
        selection = { mapID = zone }
        expandedZone = zone
        OpenAround(zone)
    else
        local first = Continents()[1]
        selection = first and { mapID = first } or nil
    end
    landed = selection
end

function QuestsTab:Refresh(scrollToSelection)
    if not list then return end
    ReadCompleted()
    ReadLog()
    if not selection then
        LandOnPlayer()
        scrollToSelection = true
    end
    local items = list:Render()
    if scrollToSelection and selection then list:ScrollToSelection(items) end
    ShowEntry()
    if self.MarkHeard then self:MarkHeard(list, items, page, selection and selection.quest) end
end

local function Build(panel)
    list = C.NewList(panel, {
        search = L.QUESTS_SEARCH,
        none = L.QUESTS_NONE,
        only = L.QUESTS_FOUND_ONLY,
        onlyGet = OnlyFound,
        onlySet = function(on) Global().FoundOnly = on end,
        build = BuildRows,
        isSelected = IsSelected,
        onClick = OnClick,
        onSearch = function(text)
            filter = text
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
    -- One line, cut short: a quest given in several zones names them all.
    if page.sub.SetWordWrap then page.sub:SetWordWrap(false) end
    if page.sub.SetMaxLines then page.sub:SetMaxLines(1) end
    if type(pageInset.NineSlice) == "table" and pageInset.NineSlice.SetFrameLevel then
        pageInset.NineSlice:SetFrameLevel(holder:GetFrameLevel() + 5)
    end
    panel.page = page
    QuestsTab.panel = panel
end

--- Whether `questID` can be opened in the tab: it is there, its part is on, and it lists the quest.
function QuestsTab:Has(questID)
    return C ~= nil and C:Tab("quests") ~= nil and VO.Addon:IsPartOn() and questID ~= nil and Quests()[questID] ~= nil
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

--- The quest before `questID` in its chain, where this character has started it and a voice pack
--- has what is said when it is handed in: what Previously plays. Nil otherwise.
function QuestsTab:Previous(questID)
    local prev = questID and Prev(questID)
    if not prev or not StartedNow(prev) or not Voiced(prev, "complete") then return nil end
    return prev
end

--- Play one moment of a quest, `moment` "accept", "progress" or "complete", as the tab's Play
--- plays each; or stop it where it is playing. Returns whether it is playing now.
function QuestsTab:TogglePart(questID, moment, origin)
    local clips = Clips(questID, moment)
    if #clips > 0 then
        for _, clip in ipairs(clips) do VO.Player:Remove(clip) end
        return false
    end
    if not Voiced(questID, moment) then return false end
    VO.Player:PlayNow(SoundData(questID, moment, origin))
    return true
end

function QuestsTab:IsPartPlaying(questID, moment)
    return #Clips(questID, moment) > 0
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
            expandedZone = zone
            OpenAround(zone)
            chain = ChainKey(questID, "z" .. zone, Index().zones[zone])
        else
            local named = quest.sort and SpokenQuestsCompendium.sorts[quest.sort]
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
