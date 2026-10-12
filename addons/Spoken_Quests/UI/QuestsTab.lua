-- The quests in Azeroth's Compendium, the window Spoken Books and Spoken Zones carry: every quest
-- this character's race and class may take, by zone, then by class, profession or season. A quest
-- is found once this character has completed it; until then it is greyed and does not open,
-- unless Unlock Uncompleted Quests is on.
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
local selection          -- { quest = id } | { mapID = id } | { sort = id } | { group = "elsewhere" } | nil
local landed             -- the selection made for the player, where they stood; any other they chose
local expandedZone
local worldOpen = true
local continentOpen = { [1414] = true, [1415] = true }
local groupOpen = {}
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

-- AllowableRaces and AllowableClasses are bit masks, bit (id - 1).
local function Has(mask, id)
    if not id or id < 1 then return true end
    return math.floor(mask / 2 ^ (id - 1)) % 2 == 1
end

local function Allowed(quest)
    if quest.races then
        local _, _, race = UnitRace("player")
        if not Has(quest.races, race) then return false end
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

local function Found(id)
    if completed then return completed[id] == true end
    local ask = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    return ask ~= nil and ask(id) and true or false
end

local function Matches(text)
    return filter == "" or (text and string.find(string.lower(text), filter, 1, true) ~= nil)
end

-- Every quest this character may take, by where it is: index.zones[mapID], index.sorts[sort],
-- index.elsewhere, and `all`. Built once: neither the data nor the character's race and class
-- change in a session.
local index
local function Index()
    if index then return index end
    index = { zones = {}, sorts = {}, elsewhere = {}, all = {} }
    for id, quest in pairs(Quests()) do
        if Allowed(quest) then
            index.all[id] = true
            if quest.zones and #quest.zones > 0 then
                for _, mapID in ipairs(quest.zones) do
                    index.zones[mapID] = index.zones[mapID] or {}
                    table.insert(index.zones[mapID], id)
                end
            elseif quest.sort then
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

-- The zones on `continent` with quests, cities left to the zone around them.
local function ZonesOn(continent)
    local out, listed = {}, {}
    for mapID in pairs(Index().zones) do
        local zone = C.CITY_IN[mapID] or mapID
        if not listed[zone] and C.ContinentOf(zone) == continent then
            listed[zone] = true
            table.insert(out, zone)
        end
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

local function Tally(set)
    local found, total = 0, 0
    for id in pairs(set) do
        total = total + 1
        if Found(id) then found = found + 1 end
    end
    return found, total
end

--------------------------------------------------------------------------------
-- The rows
--------------------------------------------------------------------------------

-- Sorted as they are drawn: a title the client has only just given may move.
local function Leaves(ids, depth, into)
    local sorted = {}
    for i, id in ipairs(ids or {}) do sorted[i] = id end
    table.sort(sorted, function(a, b)
        local ta, tb = Title(a), Title(b)
        if ta == tb then return a < b end
        return ta < tb
    end)
    for _, id in ipairs(sorted) do
        local english = Quests()[id] and Quests()[id][1]
        if not (OnlyFound() and not Found(id)) and (filter == "" or Matches(Title(id)) or Matches(english)) then
            table.insert(into, { kind = "quest", leaf = true, quest = id, label = Title(id, filter == ""),
                depth = depth, locked = not Found(id) and not Unlocked() })
        end
    end
end

local function ZoneRows(mapID, depth)
    local found, total = Tally(QuestsIn(mapID))
    if OnlyFound() and found == 0 then return {} end
    local open = expandedZone == mapID or C.CITY_IN[expandedZone] == mapID
    local inside = {}
    if open or filter ~= "" then
        for city, around in pairs(C.CITY_IN) do
            if around == mapID and Index().zones[city] then
                for _, row in ipairs(ZoneRows(city, depth + 1)) do table.insert(inside, row) end
            end
        end
        Leaves(Index().zones[mapID], depth + 1, inside)
    end
    if filter ~= "" and #inside == 0 and not Matches(C.MapName(mapID)) then return {} end
    local rows = { { kind = "zone", mapID = mapID, label = C.MapName(mapID), depth = depth,
        count = found, total = total, open = (open or filter ~= "") and #inside > 0 } }
    for _, row in ipairs(inside) do table.insert(rows, row) end
    return rows
end

local function GroupRows(kind, key, label, ids)
    if not ids or #ids == 0 then return {} end
    local found, total = Tally(SetOf(ids))
    if OnlyFound() and found == 0 then return {} end
    local leaves = {}
    if groupOpen[key] or filter ~= "" then Leaves(ids, 2, leaves) end
    if filter ~= "" and #leaves == 0 then return {} end
    local rows = { { kind = kind, key = key, depth = 1, label = label, count = found, total = total, open = #leaves > 0 } }
    for _, row in ipairs(leaves) do table.insert(rows, row) end
    return rows
end

local function BuildRows()
    local out = {}
    local function Add(rows) for _, row in ipairs(rows) do table.insert(out, row) end end
    local searching = filter ~= ""
    local continents = {}
    for _, continent in ipairs(C.CONTINENTS) do
        local zones = ZonesOn(continent)
        if #zones > 0 then
            local set = {}
            for _, mapID in ipairs(zones) do QuestsIn(mapID, set) end
            local found, total = Tally(set)
            local rows = {}
            if searching or continentOpen[continent] then
                for _, mapID in ipairs(zones) do
                    for _, row in ipairs(ZoneRows(mapID, 2)) do table.insert(rows, row) end
                end
            end
            if not (OnlyFound() and found == 0) and (not searching or #rows > 0) then
                table.insert(continents, { kind = "continent", mapID = continent, label = C.MapName(continent), depth = 1,
                    count = found, total = total, open = searching and #rows > 0 or (not searching and continentOpen[continent]),
                    rows = rows })
            end
        end
    end
    table.sort(continents, function(a, b) return a.label < b.label end)
    local found, total = Tally(Index().all)
    table.insert(out, { kind = "world", mapID = C.WORLD, label = C.MapName(C.WORLD), depth = 0, count = found,
        total = total, open = searching or worldOpen })
    if not (searching or worldOpen) then return out end
    for _, continent in ipairs(continents) do
        table.insert(out, continent)
        if continent.open then Add(continent.rows) end
    end
    local sorts = {}
    for sort in pairs(Index().sorts) do table.insert(sorts, sort) end
    table.sort(sorts, function(a, b) return SortName(a) < SortName(b) end)
    for _, sort in ipairs(sorts) do Add(GroupRows("sort", sort, SortName(sort), Index().sorts[sort])) end
    Add(GroupRows("elsewhere", "elsewhere", L.QUESTS_ELSEWHERE, Index().elsewhere))
    return out
end

local function IsSelected(row)
    if not selection then return false end
    if row.kind == "quest" then return selection.quest == row.quest end
    if row.kind == "sort" then return selection.sort == row.key end
    if row.kind == "elsewhere" then return selection.group == "elsewhere" end
    return selection.mapID == row.mapID and not selection.quest
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

local function Clips(id)
    local out = {}
    for _, clip in ipairs(VO.Player:Queued()) do
        if clip.questID == id and (clip.event == EVENTS.accept or clip.event == EVENTS.progress
            or clip.event == EVENTS.complete) then
            table.insert(out, clip)
        end
    end
    return out
end

local function Voiced(id, moment)
    return VO.DataModules:PrepareSound({ event = EVENTS[moment], questID = id }) and true or false
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
        local DataModules, Enums = VO.DataModules, VO.Enums
        local kind, giver = DataModules:GetQuestLogQuestGiverTypeAndID(id)
        local name = giver and DataModules:GetObjectName(kind, giver) or Title(id)
        local guid = giver and Enums.GUID:CanHaveID(kind) and VO.Utils:MakeGUID(kind, giver) or nil
        for _, moment in ipairs(MOMENTS) do
            if Voiced(id, moment) then
                local soundData = { event = EVENTS[moment], questID = id, title = Title(id), name = name,
                    unitGUID = guid, text = PartText(id, moment), origin = "Azeroth's Compendium" }
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
    return L.QUESTS_FOUND_FMT:format(Tally(set))
end

local function ShowEntry()
    if not page then return end
    if not selection then
        page:Show({ title = L.COMPENDIUM_QUESTS, subtitle = Count(Index().all), text = L.QUESTS_PICK })
        return
    end
    if selection.quest then
        local id = selection.quest
        if not Found(id) and not Unlocked() then
            page:Show({ title = Title(id), subtitle = Where(id), text = L.QUEST_NOT_FOUND })
            return
        end
        page:Show({ title = Title(id), subtitle = Where(id), text = Words(id), target = id })
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
        set = Index().all
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
    elseif row.kind == "sort" or row.kind == "elsewhere" then
        if filter == "" then groupOpen[row.key] = not groupOpen[row.key] end
        selection = row.kind == "sort" and { sort = row.key } or { group = "elsewhere" }
    elseif filter ~= "" then
        selection = { mapID = row.mapID }
    elseif row.kind == "world" then
        worldOpen = not worldOpen
        selection = { mapID = C.WORLD }
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

-- Choose where the player stands: their zone, opened, else the whole world. The tab never shows
-- a page with nothing chosen.
local function LandOnPlayer()
    local zone = PlayerZone()
    if zone then
        selection = { mapID = zone }
        expandedZone = zone
        worldOpen = true
        local continent = C.ContinentOf(C.CITY_IN[zone] or zone)
        if continent then continentOpen[continent] = true end
    else
        selection = { mapID = C.WORLD }
    end
    landed = selection
end

function QuestsTab:Refresh(scrollToSelection)
    if not list then return end
    ReadCompleted()
    if not selection then
        LandOnPlayer()
        scrollToSelection = true
    end
    local items = list:Render()
    if scrollToSelection and selection then list:ScrollToSelection(items) end
    ShowEntry()
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

--- Open the quests, on `questID` when one is given: chosen, with what holds it opened.
function QuestsTab:Open(questID)
    if not C then return end
    local quest = questID and Quests()[questID]
    if quest then
        selection = { quest = questID }
        worldOpen = true
        local zone = quest.zones and quest.zones[1]
        if zone then
            expandedZone = zone
            local continent = C.ContinentOf(C.CITY_IN[zone] or zone)
            if continent then continentOpen[continent] = true end
        else
            groupOpen[quest.sort or "elsewhere"] = true
        end
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
        -- Unlock Uncompleted Quests, on Spoken's page.
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
        "QUEST_DATA_LOAD_RESULT" }) do
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
