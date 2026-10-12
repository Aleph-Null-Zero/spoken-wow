-- The quests in Azeroth's Compendium: every quest this character's race and class may take, in a
-- card for the zone it is in under its continent's banner, or under its class, profession or
-- season; its chain a card inside, with the chain's page; a quest's page with its words, its
-- placeholders filled for the player; found once completed or in the quest log, marked in progress
-- then; Started Only, the search and Unlock Unstarted Quests; Play; and on a client in another
-- language, the words its windows showed.
-- Against the shipped data (Data/Compendium.lua, Data/QuestText.lua). Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local Expect, Failures = H.Expecter(print)
local QUESTS = here .. "/../../addons/Spoken_Quests/"
local SPOKEN = here .. "/../../addons/Spoken/"
local BOOKS = here .. "/../../addons/Spoken_Books/"

stub.SetClient("11509"); stub.ResetSound(); stub.ResetTimers(); stub.ResetFrames()
stub.world.questID = 0; stub.ShowPanel(nil)

-- Alterac Valley as Forever's newer client hangs it, in Hillsbrad Foothills; the other
-- battlegrounds and Zephras Isle under Azeroth itself.
local MAPS = { [947] = { "Azeroth" }, [1414] = { "Kalimdor", 947 }, [1415] = { "Eastern Kingdoms", 947 },
    [1429] = { "Elwynn Forest", 1415 }, [1453] = { "Stormwind City", 1415 }, [1436] = { "Westfall", 1415 },
    [1440] = { "Ashenvale", 1414 }, [1424] = { "Hillsbrad Foothills", 1415 }, [1459] = { "Alterac Valley", 1424 },
    [1460] = { "Warsong Gulch", 947 }, [1461] = { "Arathi Basin", 947 }, [2524] = { "Darkspear Islands", 947 },
    [2521] = { "Zephras Isle", 947 }, [2548] = { "Riverglades", 1415 }, [1427] = { "Searing Gorge", 1415 } }
_G.C_Map.GetMapInfo = function(id)
    local map = MAPS[id]
    return { mapType = 3, name = map and map[1] or ("Map " .. id), parentMapID = map and map[2] or nil }
end
_G.C_Texture = { GetAtlasInfo = stub.ListAtlas }
local faction = "Alliance"
_G.UnitFactionGroup = function() return faction, faction end
_G.UISpecialFrames = _G.UISpecialFrames or {}
local createFrame = _G.CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
    local frame = createFrame(kind, name, parent, template)
    if template == "PortraitFrameTemplate" then
        function frame:SetTitle(text) self.title = text end
        function frame:SetPortraitToAsset(path) self.portrait = path end
    end
    frame.template = template
    return frame
end

-- A human mage, Tester, who has completed Kobold Camp Cleanup.
local KOBOLDS, CANDLES, SHARPTALON, JENNEA = 7, 60, 2, 1860
stub.world.playerName = "Tester"
_G.UnitRace = function() return "Human", "Human", 1 end
_G.UnitClass = function() return "Mage", "MAGE", 8 end
local completed = { [KOBOLDS] = true }
_G.GetQuestsCompleted = function() return completed end

local VO = stub.LoadQuests(QUESTS, SPOKEN)
VO.Addon:OnInitialize()
local Spoken = _G.Spoken
-- The window comes with Spoken Books.
local B = {}
for _, file in ipairs({ "Locale/enUS", "UI/Layout", "UI/TextView", "UI/Compendium" }) do
    assert(loadfile(BOOKS .. file .. ".lua"))("Spoken_Books", B)
end
-- Where a quest is read: Classic Era's quest log, a zone's header then its quests, with the
-- selected quest's details beside the list, and the map's quest log of Forever, with its details
-- view.
local questLog, logQuest = {}, nil
_G.QuestLogFrame = CreateFrame("Frame", "QuestLogFrame")
_G.QuestLogDetailScrollFrame = CreateFrame("ScrollFrame", "QuestLogDetailScrollFrame", QuestLogFrame)
function QuestLogDetailScrollFrame:IsVisible() return logQuest ~= nil end
_G.GetNumQuestLogEntries = function() return #questLog + 1, #questLog end
_G.GetQuestLogTitle = function(index)
    if index == 1 then return "Elwynn Forest", 0, nil, true, false end
    local id = questLog[index - 1]
    if id then return "A quest", 1, nil, false, false, false, 0, id end
end
_G.GetQuestLogIndexByID = function(id)
    for i, logged in ipairs(questLog) do if logged == id then return i + 1 end end
    return 0
end
_G.GetQuestLogSelection = function()
    for i, id in ipairs(questLog) do if id == logQuest then return i + 1 end end
    return 0
end
_G.QuestLog_UpdateQuestDetails = function() end
_G.QuestMapFrame = CreateFrame("Frame", "QuestMapFrame")
QuestMapFrame.DetailsFrame = CreateFrame("Frame", nil, QuestMapFrame)
QuestMapFrame.DetailsFrame.BackFrame = CreateFrame("Frame", nil, QuestMapFrame.DetailsFrame)
_G.QuestMapFrame_ShowQuestDetails = function(questID) QuestMapFrame.DetailsFrame.questID = questID end
local ns = {}
for _, file in ipairs({ "Data/Compendium", "Data/QuestText", "UI/TextView", "UI/QuestsTab", "UI/OpenInCompendium" }) do
    assert(loadfile(QUESTS .. file .. ".lua"))("Spoken_Quests", ns)
end
-- The shipped data links each quest to the one before it in its chain: Lost Necklace, Pie for
-- Billy, Back to Billy, then Goldtooth. Only that chain is kept here, so the rest of the tree
-- reads as single quests; and one made up, crossing from Elwynn Forest into Westfall: The
-- Jasperlode Mine, then Westfall Stew and Goretusk Liver Pie.
local NECKLACE, PIE, BACK, GOLDTOOTH = 85, 86, 84, 87
local JASPERLODE, STEW, LIVER_PIE = 76, 36, 22
local shipped = SpokenQuestsCompendium.quests
local linked = shipped[PIE].prev == NECKLACE and shipped[BACK].prev == PIE and shipped[GOLDTOOTH].prev == BACK
-- Speak with Ruga, the breadcrumb Brutal Armor's chain starts with, names it after that quest.
local namedByHand = shipped[1823] and shipped[1823].name == 1838
for _, quest in pairs(shipped) do quest.prev, quest.name = nil, nil end
SpokenQuestsCompendium.quests[PIE].prev = NECKLACE
SpokenQuestsCompendium.quests[BACK].prev = PIE
SpokenQuestsCompendium.quests[GOLDTOOTH].prev = BACK
shipped[STEW].prev, shipped[LIVER_PIE].prev = JASPERLODE, STEW
local L, Tab = VO.L, VO.QuestsTab
Expect("the shipped data has the quests' chains, from the world DB", linked, true)
Expect("...and the names of chains given by hand, on their first quest", namedByHand, true)
local C = _G.SpokenCompendium

Expect("no tab before the world is up", C:Tab("quests"), nil)
stub.FireEvent("PLAYER_ENTERING_WORLD")
Expect("the quests are a tab of Azeroth's Compendium once it is", C:Tab("quests") ~= nil and C:Tab("quests").label, L.COMPENDIUM_QUESTS)
-- A map with no quests and nothing above it.
stub.world.playerMapID = 9999
Tab:Open()
local panel = Tab.panel
local page = panel.page
-- A page's words as one string: a quest's parts each under its heading, as one block reads.
local function PageWords()
    local parts = page.body.lastParts
    if not parts then return page.body.text["text"] end
    local out = {}
    for _, part in ipairs(parts) do
        table.insert(out, part.heading)
        table.insert(out, part.text)
    end
    return table.concat(out, "\n\n")
end
-- A part's Play and Report on a quest's page, by its heading.
local function PartButton(heading, kind)
    for _, part in ipairs(page.body.lastParts or {}) do
        if part.heading == heading then
            for _, button in ipairs(part.buttons or {}) do
                if button.kind == kind or (kind == "play" and button.moment) or (kind == "report" and not button.moment) then
                    return button
                end
            end
        end
    end
end
Expect("...and open on it", C:IsOpen("quests"), true)
Expect("...where the player's zone is not known, on the first continent, as there is no Azeroth to land on",
    page.title.text, "Eastern Kingdoms")

-- The client's scroll frame: an offset only within the range it last measured, which it measures
-- when asked or a frame after it is laid out, and no height until the window is first laid out.
local listScroll
for _, child in ipairs(panel.inset.children or {}) do
    if child.frameType == "ScrollFrame" then listScroll = child end
end
local measured = 0
local setScroll = listScroll.SetVerticalScroll
-- From the window closed and never laid out: the list at its top, no range measured, no height.
local function Unmeasured()
    C:Hide()
    listScroll.height, measured, listScroll.verticalScroll = 0, 0, 0
    function listScroll:UpdateScrollChildRect() measured = math.max(0, self.scrollChild.height - self.height) end
    function listScroll:SetVerticalScroll(v) setScroll(self, math.min(v, measured)) end
end
-- Laid out a frame after it is shown.
local function LaidOut()
    listScroll.height = 200
    stub.Advance(0.1)
end
local function Measured()
    listScroll.SetVerticalScroll, listScroll.UpdateScrollChildRect = setScroll, nil
    listScroll.height = 120
end
-- Whether the row for `mapID`, or the quest `id`, is inside the list's view.
local function InView(mapID, id)
    local found
    local function Walk(frame)
        for _, child in ipairs(frame.children or {}) do
            local item = child.shown ~= false and child.row
            if item and (mapID and item.mapID == mapID and item.style == "card" or id and item.quest == id) then found = child end
            Walk(child)
        end
    end
    Walk(panel)
    if not found then return false end
    local top, offset = -found.anchor.y, listScroll:GetVerticalScroll()
    return offset > 0 and top >= offset and top + found.height <= offset + listScroll.height
end
local ASHENVALE = 1440
Unmeasured()
stub.world.playerMapID = ASHENVALE
Tab:Open()
LaidOut()
Expect("landing on a zone far down the list, a frame later its card is in view, the list scrolled to it",
    page.title.text == "Ashenvale" and InView(ASHENVALE), true)
Measured()
stub.world.playerMapID = 1429
Tab:Open()
Expect("...on the zone the player stands in, never an empty page", page.title.text, "Elwynn Forest")
stub.world.playerMapID = nil

local rows
local function Collect(frame)
    for _, child in ipairs(frame.children or {}) do
        if child.row then table.insert(rows, child) end
        Collect(child)
    end
end
-- By each item's own name.
local function Shown()
    rows = {}
    Collect(panel)
    local labels = {}
    for _, row in ipairs(rows) do if row.shown ~= false and row.row then table.insert(labels, row.row.label) end end
    return table.concat(labels, "|")
end
local function RowFor(label)
    Shown()
    for _, row in ipairs(rows) do if row.shown ~= false and row.row and row.row.label == label then return row end end
end
-- Parts drawn for a style the row is not in now: a row reused from a card for a banner or a
-- quest must not keep the card's badge, line or bar.
local function Leftovers()
    Shown()
    local out, reused = {}, 0
    for _, row in ipairs(rows) do
        local item = row.shown ~= false and row.row
        if item then
            if row.cardParts and item.style ~= "card" then
                reused = reused + 1
                for i, part in ipairs(row.cardParts) do
                    if part.shown ~= false then table.insert(out, item.label .. " card part " .. i) end
                end
            end
            if row.bannerParts and item.style ~= "banner" then
                reused = reused + 1
                for i, part in ipairs(row.bannerParts) do
                    if part.shown ~= false then table.insert(out, item.label .. " banner part " .. i) end
                end
            end
            for i, rail in ipairs(row.rails or {}) do
                if rail.shown ~= false and i > (item.style ~= "banner" and item.nest or 0) then
                    table.insert(out, item.label .. " rail")
                end
            end
        end
    end
    return table.concat(out, ", "), reused
end
local function Click(label)
    local row = RowFor(label)
    assert(row, "no row " .. label)
    row.scripts.OnClick(row)
end
local function Has(list, label)
    return ("|" .. list .. "|"):find("|" .. label .. "|", 1, true) ~= nil
end

Expect("...the zone landed on before still open beside it", RowFor("Ashenvale").row.open
    and RowFor("Elwynn Forest").row.open, true)
-- Ashenvale closed again and Elwynn Forest chosen, open, for what follows.
Click("Ashenvale")
Click("Elwynn Forest")
Click("Elwynn Forest")

local list = Shown()
Expect("the list opens on the continents' banners, no Azeroth above them", list:find("^Eastern Kingdoms|") ~= nil
    and Has(list, "Kalimdor") and not Has(list, "Azeroth"), true)
Expect("...a banner across the list, its name as it is", RowFor("Eastern Kingdoms").row.style == "banner"
    and RowFor("Eastern Kingdoms").label.text, "Eastern Kingdoms")
Expect("...counting the quests completed out of all", RowFor("Eastern Kingdoms").count.text:match("^1/%d+$") ~= nil, true)
local banner = RowFor("Eastern Kingdoms")
Expect("...drawn as the objective tracker's campaign header, the Alliance's for an Alliance character",
    banner.headMiddle:IsShown() and banner.headMiddle.texture, "file:Objective-Header-CampaignAlliance")
Expect("...without the crest at its left end: its middle from past it", banner.headMiddle.texCoord[1], 64 / 274)
Expect("...its left end the right one turned round", banner.headLeft.texCoord[1] == banner.headRight.texCoord[2]
    and banner.headLeft.texCoord[2] == banner.headRight.texCoord[1] and banner.headLeft.texCoord[1] > banner.headLeft.texCoord[2]
    and banner.headLeft:IsShown() and banner.headRight:IsShown(), true)
Expect("...the quest log's collapse on it while open", banner.toggle.atlas, "questlog-icon-shrink")
Expect("...its numbers ending in the column a card's do", banner.count.anchor.point .. " " .. banner.count.anchor.x .. "|"
    .. RowFor("Elwynn Forest").count.anchor.point .. " " .. RowFor("Elwynn Forest").count.anchor.x, "RIGHT -12|RIGHT -12")
faction = "Horde"
Tab:Refresh()
Expect("...the Horde's for a Horde character", RowFor("Eastern Kingdoms").headMiddle.texture, "file:Objective-Header-CampaignHorde")
faction = "Alliance"
Tab:Refresh()
Expect("...each zone a card inside it", RowFor("Elwynn Forest").row.style == "card" and RowFor("Elwynn Forest").row.nest, 0)
Expect("...then a banner each for the quests no zone holds: Classes, Professions, Holidays and Events, Other",
    list:find("|Classes|Professions|Holidays and Events|Other$") ~= nil and not Has(list, "Mage")
    and RowFor("Classes").row.style == "banner", true)
local elwynn = RowFor("Elwynn Forest")
Expect("a zone's card: its quests completed out of all and the share, on one line beside its name",
    elwynn.count.text:match("^1/%d+ • %d+%%$") ~= nil, true)
Expect("...drawn as Classic's character select card", elwynn.face[5]:IsShown() and elwynn.face[5].texture,
    "file:glues-characterselect-card-singles-c60")
Expect("...its corners 16 pixels of the card drawn 11 across", elwynn.face[1].width == 11 and elwynn.face[1].texCoord[2],
    16 / 321)
-- In the world the game does not describe its login screens' art by name: the card is drawn
-- from its file all the same.
_G.C_Texture = { GetAtlasInfo = function(name) if not name:find("^glues%-") then return stub.ListAtlas(name) end end }
Tab:Refresh()
elwynn = RowFor("Elwynn Forest")
Expect("...even where the game will not name the login screen's card: drawn from its file",
    elwynn.face[5]:IsShown() and elwynn.face[5].texture, 8064271)
Expect("...and no plain fill round it", elwynn.cardFill:IsShown(), false)
_G.C_Texture = { GetAtlasInfo = stub.ListAtlas }
Tab:Refresh()
elwynn = RowFor("Elwynn Forest")
Expect("...its badge the zone's painting", elwynn.icon:IsShown() and elwynn.icon.texture, (Spoken:ZoneIcon(1429)))
Expect("...in the collections window's gold frame", elwynn.iconFrame:IsShown() and elwynn.iconFrame.atlas,
    "collections-itemborder-collected")
Expect("...in colour with some completed", elwynn.icon.desaturated, false)
Expect("...chosen, the chosen card's warm leather inside its frame", elwynn.warm:IsShown() and elwynn.warm.texture,
    "file:glues-characterselect-card-selected-c60")
Expect("...with none of the glow that card throws round itself", elwynn.lift[1]:IsShown(), false)
Expect("...in the sidebar's silver, not the card's bronze", elwynn.face[5].desaturated and elwynn.warm.desaturated, true)
Expect("...a step in from the continent's banner", elwynn.face[1].anchor.x, 20.4)
local elwynnTotal = tonumber(elwynn.count.text:match("/(%d+)"))
Expect("...the share completed after them", elwynn.count.text, "1/" .. elwynnTotal .. " • " .. math.floor(100 / elwynnTotal) .. "%")
local filled = math.max(3, elwynn.track.width / elwynnTotal)
Expect("...and its bar filled as far, never narrower than 3 so a small share shows",
    elwynn.fill:IsShown() and math.abs(elwynn.fill.width - filled) < 1e-9, true)
Expect("...with the game's yellow cut to what it fills, not squeezed", elwynn.fill.texture == "file:ui-frame-bar-fill-yellow"
    and math.abs(elwynn.fill.texCoord[2] - filled / elwynn.track.width) < 1e-9, true)
_G.BreakUpLargeNumbers = function(n) return "<" .. n .. ">" end
Tab:Refresh()
Expect("numbers written as the game writes them in the player's language, on banners and cards",
    RowFor("Eastern Kingdoms").count.text:match("^<1>/<%d+>$") ~= nil
    and RowFor("Elwynn Forest").count.text:match("^<1>/<%d+> • %d+%%$") ~= nil, true)
_G.BreakUpLargeNumbers = nil
Tab:Refresh()
elwynn = RowFor("Elwynn Forest")
Expect("...in the Pet Journal's bar frame", elwynn.barCaps[1]:IsShown() and elwynn.barCaps[1].atlas .. " "
    .. elwynn.barCaps[2].atlas .. " " .. elwynn.barCaps[3].atlas, "PetJournal-ExpBar-Left PetJournal-ExpBar-Mid PetJournal-ExpBar-Right")
Expect("...its page saying where it is and counting its quests, on one line",
    page.sub.text:match("^In Eastern Kingdoms · 1 of %d+ completed$") ~= nil, true)
local city = RowFor("Stormwind City")
Expect("a city is a card inside its zone's card", city ~= nil and city.row.style == "card" and city.row.nest, 1)
Expect("...indented under it, its card further in", city.face[1].anchor.x - elwynn.face[1].anchor.x, 16)
Expect("...with the line down the open card's contents beside it", city.rails[1]:IsShown() and city.rails[1].anchor.x, 32.4)
Expect("...not chosen, the plain card alone", city.lift[5]:IsShown(), false)
city.scripts.OnEnter(city)
Expect("...under the pointer, the hover card over it", city.lift[5]:IsShown() and city.lift[5].texture,
    "file:glues-characterselect-card-singles-hover-c60")
city.scripts.OnLeave(city)
Expect("...and gone again after", city.lift[5]:IsShown(), false)
Expect("...a quest in the zone a row, as far in", RowFor("Kobold Camp Cleanup").row.leaf and RowFor("Kobold Camp Cleanup").row.nest, 1)
-- A card under a single row: its frame, 5.4 under its row's top, as far under the row's foot as
-- a card's frame is under the frame of the card above it (3 above its foot, rows 1 apart): 7.4,
-- 2 more for each open card closed between them.
do
    Shown()
    local ordered = {}
    for _, row in ipairs(rows) do if row.shown ~= false and row.row then table.insert(ordered, row) end end
    table.sort(ordered, function(a, b) return a.anchor.y > b.anchor.y end)
    local found, wrong = 0, {}
    for i = 2, #ordered do
        local above, row = ordered[i - 1], ordered[i]
        local flat = above.row.leaf or above.row.style == "group"
        if flat and row.row.style == "card" then
            found = found + 1
            local gap = (-row.anchor.y) - (-above.anchor.y + above.height)
            local closed = math.max(0, (above.row.nest or 0) - (row.row.nest or 0))
            if math.abs(gap + 5.4 - (7.4 + 2 * closed)) > 1e-9 then table.insert(wrong, row.row.label .. " " .. gap) end
        end
    end
    Expect("a card under a single row as far from it as from a card above it", found > 0 and table.concat(wrong, ", "), "")
end
Click("Classes")
list = Shown()
Expect("...Classes opening on a class's quests under its name, this character's class only", Has(list, "Mage") and not Has(list, "Warlock"), true)
Expect("...a line of the list for it, a class being no place", RowFor("Mage").row.style, "group")
Expect("...Classes' page its count alone, being no place", page.title.text == "Classes"
    and page.sub.text:match("^%d+ of %d+ completed$") ~= nil, true)
Click("Mage")
Expect("...a class's page in Classes, with its count", page.sub.text:match("^In Classes · %d+ of %d+ completed$") ~= nil, true)
Click("Mage")
Click("Holidays and Events")
Expect("...Events on the festivals and the Darkmoon Faire", Has(Shown(), "Lunar Festival") and Has(Shown(), "Darkmoon Faire"), true)
list = Shown()
Expect("...each holiday a group of its own, Children's Week among them, where the client has Seasonal and Special",
    Has(list, "Feast of Winter Veil") and Has(list, "Hallow's End") and Has(list, "Love is in the Air")
    and Has(list, "Harvest Festival") and Has(list, "Children's Week") and not Has(list, "Seasonal")
    and not Has(list, "Special"), true)
Click("Classes")
Click("Holidays and Events")
local leftovers, reused = Leftovers()
Expect("a row drawn as a card and reused for a banner or a quest keeps none of the card's parts", leftovers, "")
Expect("...as rows were, once the list changed under them", reused > 0, true)
Click("Professions")
Expect("Professions holds Camping, whose quests are Camping 101 for one profession or another", Has(Shown(), "Camping"), true)
Click("Professions")
Click("Other")
list = Shown()
Expect("Other holds the Commendation Signets' hand-ins, the Argent Dawn's and the library books, under those names",
    Has(list, "Commendation Signets") and Has(list, "Argent Dawn") and Has(list, "Library Books")
    and not Has(list, "Reputation"), true)
Click(L.QUESTS_ELSEWHERE)
Expect("...Place Unknown's page its count alone", page.title.text == L.QUESTS_ELSEWHERE
    and page.sub.text:match("^%d+ of %d+ completed$") ~= nil, true)
Click(L.QUESTS_ELSEWHERE)
Click("Other")
Click("Kalimdor")
Expect("a continent's page is in Azeroth, with its count", page.title.text == "Kalimdor"
    and page.sub.text:match("^In Azeroth · %d+ of %d+ completed$") ~= nil, true)
Click("Kalimdor")

-- Zephras Isle is on no continent: under a banner of its own after them, closed with it. The
-- battlegrounds are under a banner of their own, Alterac Valley too, though the client hangs it in
-- Hillsbrad Foothills.
list = Shown()
Expect("the zones on no continent a banner after the continents, then the battlegrounds' banner",
    list:find("|" .. L.QUESTS_SECTION_LANDS .. "|Battlegrounds|Classes|", 1, true) ~= nil
    and RowFor(L.QUESTS_SECTION_LANDS).row.style, "banner")
Expect("...closed, Zephras Isle not shown", Has(list, "Zephras Isle"), false)
Click(L.QUESTS_SECTION_LANDS)
Expect("...opened, Zephras Isle a card inside it", RowFor("Zephras Isle") ~= nil and RowFor("Zephras Isle").row.style == "card"
    and RowFor("Zephras Isle").row.nest, 0)
Expect("...its page in Azeroth, as a continent's, counting their quests", page.title.text == L.QUESTS_SECTION_LANDS
    and page.sub.text:match("^In Azeroth · 0 of %d+ completed$") ~= nil, true)
Click(L.QUESTS_SECTION_LANDS)
Expect("...and closed again", Has(Shown(), "Zephras Isle"), false)
list = Shown()
Expect("...the battlegrounds a banner", RowFor("Battlegrounds").row.style, "banner")
Expect("...no battleground among its continent's zones", Has(list, "Alterac Valley"), false)
Click("Battlegrounds")
list = Shown()
Expect("...opening on a card for each battleground", Has(list, "Alterac Valley") and Has(list, "Warsong Gulch")
    and Has(list, "Arathi Basin") and Has(list, "Darkspear Islands") and RowFor("Alterac Valley").row.style, "card")
Expect("...its page in Azeroth, counting their quests", page.title.text == L.QUESTS_SECTION_BATTLEGROUNDS
    and page.sub.text:match("^In Azeroth · 0 of %d+ completed$") ~= nil, true)
Click("Battlegrounds")
list = Shown()
Expect("a zone opens on its quests", Has(list, "Kobold Camp Cleanup") and Has(list, "Kobold Candles"), true)
Expect("...a quest completed open to read", RowFor("Kobold Camp Cleanup").row.locked, false)
Expect("...one not completed greyed, with the padlock", RowFor("Kobold Candles").row.locked, true)

Click("Kobold Camp Cleanup")
Expect("a quest's page: its title", page.title.text, "Kobold Camp Cleanup")
Expect("...where it is", page.sub.text, "Elwynn Forest")
Expect("...on one line, cut short", page.sub.wordWrap, false)
local words = PageWords() or ""
Expect("...its words in parts, offered then handed in, each under its heading",
    page.body.lastParts ~= nil and page.body.lastParts[1].heading == L.QUEST_PART_ACCEPT
    and page.body.lastParts[#page.body.lastParts].heading == L.QUEST_PART_COMPLETE, true)
Expect("...no Play or Report in the page's corner: each part has its own", page.play:IsShown(), false)
-- The page's divider, as a client with the spellbook's art gives it.
page.body:SetPartDivider({ file = "spellbook-divider", width = 657, left = 0, right = 0.64, top = 0, bottom = 0.69 })
Click("Kobold Candles")
Click("Kobold Camp Cleanup")
Expect("...the page's divider, short, above each part but the first", not page.body.parts[1].divider:IsShown()
    and page.body.parts[2].divider:IsShown() and page.body.parts[2].divider.width <= 220, true)
Expect("...no placeholder left in them", words:find("$", 1, true), nil)
Click("Kobold Candles")
Expect("a quest not completed does not open", page.title.text, "Kobold Camp Cleanup")

-- Unlock Unstarted Quests, the switch Spoken's page shows.
C:Tab("quests").unlock.set(true)
Expect("Unlock Unstarted Quests opens it", RowFor("Kobold Candles").row.locked, false)
Click("Kobold Candles")
words = PageWords() or ""
Expect("...its words filled for the player: the word for his sex", words:find("Hello, good sir!", 1, true) ~= nil, true)
Expect("...and his name", words:find("Thanks for the candles, Tester,", 1, true) ~= nil, true)
Expect("...and a line break for $B", words:find("moment?\n\nMy brother", 1, true) ~= nil, true)
stub.world.unitSex = 3
Tab:Refresh()
Expect("...and for hers", (PageWords() or ""):find("Hello, my lady!", 1, true) ~= nil, true)
stub.world.unitSex = 2
Expect("...choosing it leaves the counts as they were", RowFor("Elwynn Forest").count.text:match("^1/") ~= nil, true)
C:Tab("quests").unlock.set(false)

-- A quest in the quest log is found too, marked in progress.
local function RowOf(id)
    Shown()
    for _, row in ipairs(rows) do if row.shown ~= false and row.row and row.row.quest == id then return row end end
end
questLog = { CANDLES }
Tab:Refresh()
Expect("a quest in the quest log opens", RowOf(CANDLES).row.locked, false)
Expect("...its row marked in progress, the quest mark before its name", RowOf(CANDLES).status:IsShown()
    and RowOf(CANDLES).status.texture .. " " .. RowOf(CANDLES).label.text, [[Interface\GossipFrame\ActiveQuestIcon]] .. " Kobold Candles")
Expect("...a completed one the quest log's gold tick", RowFor("Kobold Camp Cleanup").status:IsShown()
    and RowFor("Kobold Camp Cleanup").status.atlas .. " " .. RowFor("Kobold Camp Cleanup").label.text,
    "questlog-icon-checkmark-yellow Kobold Camp Cleanup")
Expect("...15 by 13, as every tick in the list is", RowFor("Kobold Camp Cleanup").status.width .. "x"
    .. RowFor("Kobold Camp Cleanup").status.height, "15x13")
Expect("...and its zone's card counts it in progress, apart from the completed",
    RowFor("Elwynn Forest").count.text:match("ActiveQuestIcon.-|t1 +1/%d+ • ") ~= nil, true)
RowOf(CANDLES).scripts.OnClick(RowOf(CANDLES))
Expect("its page: its title", page.title.text, "Kobold Candles")
Expect("...in progress, then where it is", page.sub.text:find(L.QUEST_IN_PROGRESS .. " • Elwynn Forest", 1, true) ~= nil, true)
Expect("...and its words", (PageWords() or ""):find("Thanks for the candles", 1, true) ~= nil, true)
Click("Elwynn Forest")
Expect("a zone's page counts it apart from the completed",
    page.sub.text:match("^In Eastern Kingdoms · 1 of %d+ completed, 1 in progress$") ~= nil, true)
Click("Elwynn Forest")
VO.Addon.db.global.Compendium.FoundOnly = true
Tab:Refresh()
Expect("Started Only keeps it", RowOf(CANDLES) ~= nil, true)
VO.Addon.db.global.Compendium.FoundOnly = false
-- The list follows the quest log while it is open, once a burst of events is over.
questLog = {}
stub.FireEvent("QUEST_REMOVED", CANDLES)
stub.FireEvent("QUEST_LOG_UPDATE")
Expect("a quest dropped from the log stays until the events settle", RowOf(CANDLES).row.locked, false)
stub.Advance(0.5)
Expect("...then is greyed again", RowOf(CANDLES).row.locked, true)
questLog = { CANDLES }
stub.FireEvent("QUEST_ACCEPTED", 1, CANDLES)
stub.Advance(0.5)
Expect("a quest accepted opens", RowOf(CANDLES).row.locked, false)
questLog = {}
Tab:Refresh()

-- Completing one in the world finds it.
completed[CANDLES] = true
Tab:Refresh()
Expect("a quest completed since opens", RowFor("Kobold Candles").row.locked, false)
Expect("...and is counted", RowFor("Elwynn Forest").count.text:match("^2/") ~= nil, true)

-- Started Only.
VO.Addon.db.global.Compendium.FoundOnly = true
Tab:Refresh()
list = Shown()
Expect("Started Only leaves out what is not started", Has(list, "Wolves Across the Border") or Has(list, "Mage"), false)
Expect("...and keeps what is", Has(list, "Kobold Candles"), true)
VO.Addon.db.global.Compendium.FoundOnly = false

-- The search: every match, with what holds it, opened.
local box
for _, child in ipairs(panel.children or {}) do if child.template == "SearchBoxTemplate" then box = child end end
box:SetText("speak with jennea")
box.hooks.OnTextChanged[1](box)
list = Shown()
Expect("a search shows what matches, under what holds it", Has(list, "Mage") and Has(list, "Speak with Jennea")
    and not Has(list, "Kobold Candles"), true)
box:SetText("sharptalon")
box.hooks.OnTextChanged[1](box)
Expect("...and never a quest of the other side", Has(Shown(), "Sharptalon's Claw"), false)
-- A search that matches what holds quests lists all it holds, as one that matches a chain's name.
local function Search(text)
    box:SetText(text)
    box.hooks.OnTextChanged[1](box)
    return Shown()
end
list = Search("westfall")
Expect("a search matching a zone's name lists all its quests, not only those whose titles match",
    Has(list, "Westfall") and Has(list, "The Killing Fields") and RowFor("Westfall").row.open, true)
Expect("...with what holds them inside it, a chain from another zone among them",
    Has(list, "The Jasperlode Mine") and Has(list, "Westfall Stew"), true)
Expect("...and no zone that does not match", Has(list, "Elwynn Forest"), false)
Click("Westfall")
Expect("...a click choosing the zone while searching, its page shown", page.title.text, "Westfall")
Expect("...and closing what the search opened, as a click does unsearched", Has(Shown(), "The Killing Fields"), false)
Click("Westfall")
list = Search("mage")
Expect("a search matching a class lists all that class's quests", Has(list, "Mage") and Has(list, "Speak with Jennea")
    and RowFor("Mage").row.open, true)
list = Search("classes")
Expect("a search matching a section's banner lists its cards, closed", Has(list, "Classes") and Has(list, "Mage")
    and not Has(list, "Speak with Jennea") and RowFor("Mage").row.open, false)
Click("Mage")
Expect("...a card among them opening on a click, as unsearched", Has(Shown(), "Speak with Jennea"), true)
Click("Mage")
Expect("...and closing on another", Has(Shown(), "Speak with Jennea"), false)
list = Search("battlegrounds")
Expect("...the battlegrounds' banner too", Has(list, "Alterac Valley") and not Has(list, "Irondeep Supplies"), true)
list = Search("kalimdor")
Expect("a search matching a continent lists its zones' cards, closed", Has(list, "Kalimdor") and Has(list, "Ashenvale")
    and not Has(list, "Elwynn Forest") and RowFor("Ashenvale").row.open, false)
Click("Ashenvale")
Expect("...a zone among them opening on a click, all its quests listed", RowFor("Ashenvale").row.open
    and #Shown() > #list, true)
Click("Ashenvale")
list = Search("blackrock depths")
Expect("a search matching a dungeon lists all its quests", Has(list, "Blackrock Depths")
    and Has(list, "A Taste of Flame") and not Has(list, "Blackrock Spire"), true)
list = Search("dungeons and raids")
Expect("...and one matching Dungeons and Raids all of a zone's dungeons", Has(list, "Blackrock Depths")
    and Has(list, "Blackrock Spire") and Has(list, "A Taste of Flame"), true)
list = Search("killing fields")
Expect("a title's match inside a zone that does not match still lists that quest alone",
    Has(list, "Westfall") and Has(list, "The Killing Fields") and not Has(list, "Goretusk Liver Pie"), true)
Click("Westfall")
Expect("...a click on the zone the search opened closes it, its quest hidden", Has(Shown(), "Westfall")
    and not Has(Shown(), "The Killing Fields") and RowFor("Westfall").row.open, false)
Click("Westfall")
Expect("...and another opens it again", Has(Shown(), "The Killing Fields"), true)
Click("Westfall")
list = Search("killing field")
Expect("...a new search opening all it finds again", Has(list, "The Killing Fields"), true)
box:SetText("")
box.hooks.OnTextChanged[1](box)

-- Chains: a zone's quests that follow one another under one card, named after the first.
Tab:Open(KOBOLDS)
local function ChainRow(label)
    Shown()
    for _, row in ipairs(rows) do
        if row.shown ~= false and row.row and row.row.kind == "chain" and row.label.text == label then return row end
    end
end
local function ClickChain(label)
    local row = ChainRow(label)
    assert(row, "no chain " .. label)
    row.scripts.OnClick(row)
end
local function RowOfQuest(id)
    Shown()
    for _, row in ipairs(rows) do if row.shown ~= false and row.row and row.row.quest == id then return row end end
end
list = Shown()
Expect("a chain is a line of the list in its zone's card, named after its first quest", ChainRow("Lost Necklace") ~= nil
    and ChainRow("Lost Necklace").row.style == "group" and ChainRow("Lost Necklace").row.nest, 1)
Expect("...its quests inside it, not beside it", RowOfQuest(NECKLACE) or Has(list, "Pie for Billy") or Has(list, "Goldtooth"), false)
Expect("...a quest in no chain still a row of its own", Has(list, "Kobold Camp Cleanup"), true)
Expect("...its plus or minus before its name, no badge", ChainRow("Lost Necklace").toggle:IsShown()
    and not ChainRow("Lost Necklace").icon:IsShown(), true)
Expect("...its quests completed out of all and the share, beside its name", ChainRow("Lost Necklace").count.text, "0/4 • 0%")
Expect("...none completed, none of the share", ChainRow("Lost Necklace").row.none
    and ChainRow("Lost Necklace").count.text:match("• (%d+)%%$"), "0")
Expect("...its bar empty", ChainRow("Lost Necklace").fill:IsShown(), false)
local zoneRow = RowFor("Westfall")
Expect("a zone with none completed: its painting greyed and darker", zoneRow ~= nil and zoneRow.row.none
    and zoneRow.icon.desaturated and zoneRow.icon.vertexColor[1], 0.7)
completed[NECKLACE], completed[PIE] = true, true
questLog = { BACK }
Tab:Refresh()
Expect("...how many are in progress before them, by the quest mark", ChainRow("Lost Necklace").count.text,
    "|TInterface\\GossipFrame\\ActiveQuestIcon:12:12:0:0|t1   2/4 • 50%")
Expect("...and no bar: one line of the list", ChainRow("Lost Necklace").fill:IsShown(), false)
Expect("...its plus counting what is under way as well as completed, so it opens as Started Only lists it",
    ChainRow("Lost Necklace").row.found == 3 and not ChainRow("Lost Necklace").toggle.desaturated, true)
ClickChain("Lost Necklace")
list = Shown()
Expect("a chain opens on its quests, in the order they are taken",
    list:find("Lost Necklace|Lost Necklace|Pie for Billy|.*Back to Billy|Goldtooth") ~= nil, true)
Expect("...rows one step further in", RowOfQuest(PIE).row.nest, 2)
Expect("...chosen, its page has the chain's name", page.title.text, "Lost Necklace")
Expect("...the zone it is listed in and its count", page.sub.text, "In Elwynn Forest · 2 of 4 completed, 1 in progress")
Expect("...and, as a zone's page, the quests on the left to choose", PageWords(), L.QUESTS_PICK)
Expect("...nothing to play on it", page.play:IsShown(), false)
completed[BACK], completed[GOLDTOOTH] = true, true
questLog = {}
Tab:Refresh()
Expect("a chain all completed gets the gold tick after its numbers, no share", ChainRow("Lost Necklace").status:IsShown()
    and ChainRow("Lost Necklace").count.text, "4/4")
Expect("...the quest log's gold tick, where a single quest's goes", ChainRow("Lost Necklace").row.tick
    and ChainRow("Lost Necklace").status.atlas, "questlog-icon-checkmark-yellow")
Expect("...at the same size", ChainRow("Lost Necklace").status.width .. "x" .. ChainRow("Lost Necklace").status.height, "15x13")
ClickChain("Lost Necklace")
Expect("...and closes again", Has(Shown(), "Pie for Billy"), false)
Tab:Open(PIE)
Expect("opened on a quest of a chain, the chain is opened to it", RowFor("Pie for Billy") ~= nil
    and RowFor("Pie for Billy").selected, true)
box:SetText("pie for")
box.hooks.OnTextChanged[1](box)
list = Shown()
Expect("a search finds a quest inside its chain", Has(list, "Pie for Billy") and ChainRow("Lost Necklace") ~= nil
    and RowOfQuest(NECKLACE), nil)
box:SetText("")
box.hooks.OnTextChanged[1](box)
for _, id in ipairs({ NECKLACE, PIE, BACK, GOLDTOOTH }) do completed[id] = nil end
VO.Addon.db.global.Compendium.FoundOnly = true
Tab:Refresh()
Expect("Started Only leaves out a chain with nothing started", ChainRow("Lost Necklace"), nil)
VO.Addon.db.global.Compendium.FoundOnly = false
Tab:Refresh()

-- A chain's name is the same in every zone it crosses: its first quest's, though that quest is in
-- another zone, or the name the data gives that quest.
Click("Westfall")
Expect("a click on a second zone's card opens it beside the open one, both open",
    RowFor("Westfall").row.open and RowFor("Elwynn Forest").row.open and Has(Shown(), "Kobold Camp Cleanup"), true)
Click("Elwynn Forest")
Expect("...and a click on one closes it alone", tostring(RowFor("Elwynn Forest").row.open) .. "|"
    .. tostring(RowFor("Westfall").row.open), "false|true")
Expect("a chain's card in a zone it crosses into has the chain's name: its first quest's, from another zone",
    ChainRow("The Jasperlode Mine") ~= nil and ChainRow("The Jasperlode Mine").row.nest == 1
    and ChainRow("Westfall Stew"), nil)
shipped[JASPERLODE].name = 64 -- The Forgotten Heirloom
Tab:Refresh()
Expect("...or the quest whose title the data names it after", ChainRow("The Forgotten Heirloom") ~= nil
    and ChainRow("The Jasperlode Mine"), nil)
shipped[JASPERLODE].name = { "Mine and Stew", deDE = "Mine und Eintopf" }
Tab:Refresh()
Expect("...or words of its own", ChainRow("Mine and Stew") ~= nil, true)
ClickChain("Mine and Stew")
Expect("...its page under that name", page.title.text, "Mine and Stew")
stub.SetLocale("deDE")
Tab:Refresh()
Expect("...in the client's language where the data has it", ChainRow("Mine und Eintopf") ~= nil, true)
stub.SetLocale("enUS")
shipped[JASPERLODE].name = nil
Tab:Refresh()
ClickChain("The Jasperlode Mine")
Click("Westfall")
Click("Elwynn Forest")

-- Play: the first part the voice packs have of the quest, with its words.
VO.DataModules:Register("TestPack", {
    SoundLengthLookupByFileName = { ["7-accept"] = 2, ["7-complete"] = 2, ["85-accept"] = 2, ["85-complete"] = 2 },
    GetSoundPath = function(_, fileName) return fileName .. ".ogg" end,
})
Click("Kobold Camp Cleanup")
local play = PartButton(L.QUEST_PART_ACCEPT, "play")
Expect("a voiced part has Play on its heading's line", play ~= nil and play:IsShown(), true)
Expect("...and Report beside it", PartButton(L.QUEST_PART_ACCEPT, "report") ~= nil
    and PartButton(L.QUEST_PART_ACCEPT, "report"):IsShown(), true)
do
    -- The page's own buttons end over the words' right edge, 36 + the bar's room from the
    -- page's right: a part's rightmost ends there too.
    local body, report = page.body, PartButton(L.QUEST_PART_ACCEPT, "report")
    local width = body.frame.width
    body.frame.width = 400
    body:SetParts(body.lastParts)
    local fromPageRight = body.frame.anchor.x - (400 - report.anchor.x)
    Expect("...ending in the column the page's own Play and Report end in",
        report.anchor.relativeTo == body.child and fromPageRight, -(36 + body:BarRoom()))
    -- A page's words start 18 down (the top fade's room); the first heading's line, 26 tall,
    -- starts 4 higher, and its buttons are centred on it.
    Expect("...the first heading's line starting a little above where a page's words do", report.anchor.y, -(18 - 4 + 13))
    body.frame.width = width
    -- Headings grow with the words' size, up to 20.
    local heading, size = body.parts[1].heading, nil
    local titleFont, get = _G.QuestTitleFont, ns.Get
    _G.QuestTitleFont = { GetFont = function() return "Fonts/MORPHEUS.TTF", 18 end }
    heading.SetFont = function(_, _, s) size = s end
    local words = 12
    ns.Get = function(self, key) if key == "fontSize" then return words end return get(self, key) end
    body:SetParts(body.lastParts)
    Expect("...a part's heading 7 larger than the words", size, 19)
    words = 18
    body:SetParts(body.lastParts)
    Expect("...and no larger than 20, under the page's title", size, 20)
    _G.QuestTitleFont, ns.Get, heading.SetFont = titleFont, get, nil
    body:SetParts(body.lastParts)
end
play.scripts.OnClick(play)
local queued = {}
for _, clip in ipairs(Spoken:GetQueue()) do table.insert(queued, clip.fileName) end
Expect("...which plays that part alone, not the hand-in after it", table.concat(queued, ","), "7-accept")
local playing = Spoken:GetQueue()[1]
Expect("...with the offer's words, for the window to show and highlight",
    playing and type(playing.text) == "string" and playing.text ~= "" and PageWords():find(playing.text, 1, true) ~= nil, true)
local function PlayTip()
    GameTooltip.text = nil
    for _, hook in ipairs(play.hooks and play.hooks.OnEnter or {}) do hook(play) end
    return GameTooltip.text
end
Expect("...its tooltip naming Stop while it plays", PlayTip(), SpokenEnv.L.STOP)
local handIn = PartButton(L.QUEST_PART_COMPLETE, "play")
handIn.scripts.OnClick(handIn)
queued = {}
for _, clip in ipairs(Spoken:GetQueue()) do table.insert(queued, clip.fileName) end
Expect("...the hand-in's Play playing the hand-in in its place", queued[1], "7-complete")
handIn.scripts.OnClick(handIn)
play.scripts.OnClick(play)
play.scripts.OnClick(play)
Expect("...and again, stops them", #VO.Player:Queued(), 0)
Expect("...its tooltip naming Play once stopped", PlayTip(), SpokenEnv.L.PLAY)
Click("Kobold Candles")
Expect("a quest no pack has has no Play", PartButton(L.QUEST_PART_ACCEPT, "play") == nil
    or not PartButton(L.QUEST_PART_ACCEPT, "play"):IsShown(), true)
Expect("...nor Report", PartButton(L.QUEST_PART_ACCEPT, "report") == nil
    or not PartButton(L.QUEST_PART_ACCEPT, "report"):IsShown(), true)
ClickChain("Lost Necklace")
completed[NECKLACE] = true
Tab:Refresh()
Expect("a chain's page has no Play, even with a voiced quest started: its quests are on the left",
    page.play:IsShown(), false)
completed[NECKLACE] = nil
ClickChain("Lost Necklace")

-- Voiced Only, after Started Only in the filter menu: the quests no voice pack has are left out,
-- with any card or banner left with nothing, and out of the counts. The test pack has Kobold Camp
-- Cleanup and Lost Necklace.
local function Menu()
    local entries = {}
    for _, info in ipairs(stub.OpenDropdown(panel.filterMenu)) do table.insert(entries, info.text) end
    return table.concat(entries, "|"), stub.OpenDropdown(panel.filterMenu)
end
Expect("the filter menu holds Started Only, then Voiced Only", (Menu()), L.QUESTS_FOUND_ONLY .. "|" .. L.QUESTS_VOICED_ONLY)
local _, choices = Menu()
choices[2].func()
list = Shown()
Expect("Voiced Only leaves out the quests no pack has", Has(list, "Kobold Candles"), false)
Expect("...and keeps those it has, in what holds them", Has(list, "Kobold Camp Cleanup") and Has(list, "Elwynn Forest")
    and ChainRow("Lost Necklace") ~= nil, true)
Expect("...leaving out a zone, a continent and a section with none", Has(list, "Westfall") or Has(list, "Kalimdor")
    or Has(list, "Classes"), false)
Expect("...each card counting only the quests it lists", RowFor("Elwynn Forest").count.text:match("^1/2 ") ~= nil
    and ChainRow("Lost Necklace").count.text, "0/1 • 0%")
Expect("...and each banner", RowFor("Eastern Kingdoms").count.text, "1/2")
Expect("...and is remembered", VO.Addon.db.global.Compendium.VoicedOnly, true)
Expect("...a started quest it leaves out not opened in the Compendium", Tab:Has(CANDLES), false)
_, choices = Menu()
choices[2].func()
Expect("...off, everything again", Has(Shown(), "Kobold Candles") and Has(Shown(), "Westfall") and Tab:Has(CANDLES), true)

-- The part switched off takes its tab away.
Spoken:SetPartOn("quests", false)
Expect("with Quests off, the tab is not offered", C:Select("quests"), nil)
Spoken:SetPartOn("quests", true)

-- Quests is the first tab, before Zones and Books, and gives the window its title.
C:Register("places", { label = "Zones", order = 1, build = function() end })
C:Register("readables", { label = "Books", order = 2, build = function() end })
Expect("Quests is the first tab", _G.SpokenCompendiumWindowTab1:GetText(), L.COMPENDIUM_QUESTS)
Expect("...Zones and Books after it", _G.SpokenCompendiumWindowTab2:GetText() .. "|" .. _G.SpokenCompendiumWindowTab3:GetText(),
    "Zones|Books")
Expect("...and the window has its title", C.window.title, L.COMPENDIUM_TITLE)

---------------------------------------------------------------- Open in Azeroth's Compendium
-- Opened on a quest: chosen, with its zone, continent or group opened, and its page shown.
local HEIRLOOM = 64
C:Hide()
Tab:Open(HEIRLOOM)
Expect("opened on a quest, the window shows the Quests tab", C:IsOpen("quests"), true)
Expect("...with the quest's zone opened to it", Has(Shown(), "The Forgotten Heirloom"), true)
Expect("...the quest chosen", RowFor("The Forgotten Heirloom").selected, true)
Expect("...and its page shown", page.title.text, "The Forgotten Heirloom")
Tab:Open(JENNEA)
Expect("a class's quest opens under its class", Has(Shown(), "Speak with Jennea") and page.title.text, "Speak with Jennea")
local IRONDEEP = 5892
Tab:Open(IRONDEEP)
Expect("a battleground's quest opens under the battlegrounds' banner", Has(Shown(), "Irondeep Supplies")
    and RowFor("Battlegrounds").row.open and page.title.text, "Irondeep Supplies")
local ashenvaleQuest
for id, quest in pairs(SpokenQuestsCompendium.quests) do
    if not ashenvaleQuest and quest.zones and quest.zones[1] == ASHENVALE and Tab:Lists(id) and not quest.dungeon then
        ashenvaleQuest = id
    end
end
Unmeasured()
Tab:Open(ashenvaleQuest)
LaidOut()
Expect("opened on a quest far down the list, a frame later its row is in view", InView(nil, ashenvaleQuest), true)
Measured()

-- A zone's dungeons' and raids' quests: a card inside its card, named after the dungeon
-- where the zone has one; in a zone with several, Dungeons and Raids, a card for each
-- dungeon inside that.
local STOCKADE, DARK_IRON = 386, 3801
Tab:Open(STOCKADE)
list = Shown()
local dungeons = RowFor("Stormwind Stockade")
Expect("opened on a dungeon's quest, its zone's card of its dungeon is opened to it", dungeons ~= nil
    and dungeons.row.style == "card" and dungeons.row.open and Has(list, "What Comes Around...") and page.title.text,
    "What Comes Around...")
Expect("...named after the zone's one dungeon, not Dungeons and Raids", Has(list, "Dungeons and Raids"), false)
Expect("...a card inside the city's card, as far in as its quests", dungeons.row.nest, 2)
Expect("...its badge a key", dungeons.icon.texture, [[Interface\Icons\INV_Misc_Key_03]])
Expect("...its quests straight inside", RowFor("What Comes Around...").row.nest, 3)
stub.SetLocale("deDE")
Tab:Refresh()
Expect("...the dungeon's name in the client's language", RowFor("Verlies von Stormwind") ~= nil, true)
stub.SetLocale("enUS")
Tab:Refresh()
Tab:Open(DARK_IRON)
list = Shown()
Expect("in a zone with several dungeons, a card for each inside Dungeons and Raids",
    Has(list, "Blackrock Depths") and Has(list, "Blackrock Spire") and RowFor("Blackrock Depths").row.style == "card"
    and RowFor("Blackrock Depths").row.nest, 2)
Expect("...the dungeon's quests inside its own card", Has(list, "Dark Iron Legacy") and RowFor("Dark Iron Legacy").row.nest >= 3, true)
Click("Blackrock Spire")
Expect("...a dungeon's page in the zone of its entrance, counting its quests", page.title.text == "Blackrock Spire"
    and page.sub.text:match("^In Searing Gorge · 0 of %d+ completed$") ~= nil, true)

-- The quest giver's window: the Compendium's tome beside its controls, for a quest the tab lists.
local giver = Tab.giverButton
stub.world.questID = KOBOLDS
stub.ShowPanel("QuestFrameDetailPanel")
stub.FireEvent("QUEST_DETAIL")
Expect("the quest giver's window has Open in Azeroth's Compendium", giver ~= nil and giver:IsShown(), true)
C:Hide()
giver.scripts.OnClick(giver)
Expect("...which opens the Compendium on that quest", C:IsOpen("quests") and page.title.text, "Kobold Camp Cleanup")
local tooltip = {}
local gameTooltip = _G.GameTooltip
_G.GameTooltip = { SetOwner = function() end, SetText = function(_, text) tooltip.title = text end,
    AddLine = function(_, text) tooltip.line = text end, Show = function() end, Hide = function() end }
for _, handler in ipairs(giver.hooks and giver.hooks.OnEnter or {}) do handler(giver) end
_G.GameTooltip = gameTooltip
Expect("...and says so", tooltip.title, L.OPEN_IN_COMPENDIUM)
stub.world.questID = 999999
stub.FireEvent("QUEST_DETAIL")
Expect("...not for a quest the tab does not list", giver:IsShown(), false)
completed[SHARPTALON] = true
stub.world.questID = SHARPTALON
stub.FireEvent("QUEST_DETAIL")
Expect("...nor for one of another race's, the list leaving it out for this character", giver:IsShown(), false)
completed[SHARPTALON] = nil
-- Offered and not started, a quest's page is the padlock: no Open, unless it would show the words.
local WOLVES = 33
stub.world.questID = WOLVES
stub.FireEvent("QUEST_DETAIL")
Expect("...nor on the offer of a quest not started, whose page is locked", giver:IsShown(), false)
C:Tab("quests").unlock.set(true)
stub.FireEvent("QUEST_DETAIL")
Expect("...but there with Unlock Unstarted Quests on", giver:IsShown() and giver.questID, WOLVES)
VO.Addon.db.global.Compendium.FoundOnly = true
stub.FireEvent("QUEST_DETAIL")
Expect("...and not with Started Only on, which leaves the quest out of the list", giver:IsShown(), false)
VO.Addon.db.global.Compendium.FoundOnly = false
C:Tab("quests").unlock.set(false)
questLog = { WOLVES }
stub.ShowPanel("QuestFrameProgressPanel")
stub.FireEvent("QUEST_PROGRESS")
Expect("...there once the quest is in the quest log", giver:IsShown() and giver.questID, WOLVES)
questLog = {}
stub.ShowPanel("QuestFrameDetailPanel")
stub.world.questID = 0
stub.ShowPanel(nil)
stub.FireEvent("QUEST_FINISHED")

-- The quest log's details, on either log.
questLog, logQuest = { HEIRLOOM, CANDLES }, HEIRLOOM
QuestLog_UpdateQuestDetails()
Tab.logButton.scripts.OnClick(Tab.logButton)
Expect("the quest log's Open on a quest in progress shows its words", page.title.text == "The Forgotten Heirloom"
    and PageWords() ~= L.QUEST_NOT_FOUND, true)
logQuest = CANDLES
QuestLog_UpdateQuestDetails()
Expect("Classic Era's quest log details have it", Tab.logButton:IsShown() and Tab.logButton.questID, CANDLES)
Tab.logButton.scripts.OnClick(Tab.logButton)
Expect("...and open the quest", page.title.text, "Kobold Candles")
questLog, logQuest = {}, nil
QuestLog_UpdateQuestDetails()
Expect("...not with no quest chosen", Tab.logButton:IsShown(), false)
questLog = { HEIRLOOM }
QuestMapFrame_ShowQuestDetails(HEIRLOOM)
Expect("the map's quest log details have it", Tab.mapButton:IsShown() and Tab.mapButton.questID, HEIRLOOM)
Spoken:SetPartOn("quests", false)
QuestMapFrame_ShowQuestDetails(HEIRLOOM)
Expect("...not with Quests off", Tab.mapButton:IsShown(), false)
Spoken:SetPartOn("quests", true)
questLog = {}
QuestMapFrame_ShowQuestDetails(HEIRLOOM)
Expect("...nor for a quest not started", Tab.mapButton:IsShown(), false)

---------------------------------------------------------------- Previously
-- Left of Open in Azeroth's Compendium, on a quest that follows one this character has started:
-- what was said when that one was handed in.
-- The test pack has Lost Necklace's hand-in, and its offer.
local previously = giver.previous
stub.world.questID = PIE
stub.ShowPanel("QuestFrameDetailPanel")
stub.FireEvent("QUEST_DETAIL")
Expect("no Previously while the quest before is not started", previously ~= nil and previously:IsShown(), false)
completed[NECKLACE] = true
stub.FireEvent("QUEST_DETAIL")
Expect("the quest giver's window has Previously once it is", previously:IsShown(), true)
Expect("...in the place of Open in Azeroth's Compendium, hidden on the offer of a quest not started",
    giver:IsShown() == false and previously.anchor ~= nil and previously.anchor.relativeTo == giver
    and previously.anchor.point, "CENTER")
C:Tab("quests").unlock.set(true)
stub.FireEvent("QUEST_DETAIL")
Expect("...left of it where it is shown", giver:IsShown() and previously.anchor.relativeTo == giver
    and previously.anchor.point == "RIGHT", true)
C:Tab("quests").unlock.set(false)
stub.FireEvent("QUEST_DETAIL")
tooltip = {}
_G.GameTooltip = { SetOwner = function() end, SetText = function(_, text) tooltip.title = text end,
    AddLine = function(_, text) tooltip.line = text end, Show = function() end, Hide = function() end }
for _, handler in ipairs(previously.hooks and previously.hooks.OnEnter or {}) do handler(previously) end
_G.GameTooltip = gameTooltip
Expect("...which says so, naming the quest before", tooltip.title == L.QUEST_PREVIOUSLY
    and tooltip.line:find("Lost Necklace", 1, true) ~= nil, true)
Spoken:StopAll()
previously.scripts.OnClick(previously)
queued = {}
for _, clip in ipairs(Spoken:GetQueue()) do table.insert(queued, clip.fileName) end
Expect("...and plays what was said when that one was handed in, only that", table.concat(queued, ","), "85-complete")
Expect("...as Stop while it plays", previously.state, "stop")
previously.scripts.OnClick(previously)
Expect("...which stops it", #VO.Player:Queued(), 0)
stub.world.questID = BACK
completed[PIE] = true
stub.FireEvent("QUEST_DETAIL")
Expect("no Previously where no pack has the quest before's hand-in", previously:IsShown(), false)
stub.world.questID = KOBOLDS
stub.FireEvent("QUEST_DETAIL")
Expect("...nor on a quest that follows none", previously:IsShown(), false)
stub.world.questID = 0
stub.ShowPanel(nil)
stub.FireEvent("QUEST_FINISHED")
questLog, logQuest = { PIE }, PIE
QuestLog_UpdateQuestDetails()
Expect("the quest log's details have Previously too", Tab.logButton.previous:IsShown()
    and Tab.logButton.previous.questID, NECKLACE)
questLog, logQuest = {}, nil
QuestLog_UpdateQuestDetails()
Expect("...not with no quest chosen", Tab.logButton.previous:IsShown(), false)
QuestMapFrame_ShowQuestDetails(PIE)
Expect("and the map's quest log's", Tab.mapButton.previous:IsShown(), true)
completed[NECKLACE], completed[PIE] = nil, nil

---------------------------------------------------------------- another language
-- A German client: the words and the title the quest's window shows are kept, for every
-- character, and shown over the English.
stub.SetLocale("deDE")
stub.world.questID = KOBOLDS
stub.world.title = "Säuberung des Koboldlagers"
stub.world.questText = "Tester, Ihr müsst die Kobolde vertreiben."
stub.FireEvent("QUEST_DETAIL")
stub.world.questID = 0
Tab:Refresh()
Click("Säuberung des Koboldlagers")
words = PageWords() or ""
Expect("the title the window showed", page.title.text, "Säuberung des Koboldlagers")
Expect("...and its words, over the English", words:find("Ihr müsst die Kobolde vertreiben.", 1, true) ~= nil, true)
Expect("...the moments the window has not shown yet still in English",
    words:find(SpokenQuestsText[KOBOLDS].complete:sub(1, 20), 1, true) ~= nil, true)
stub.world.playerName = "Zweite"
Tab:Refresh()
Expect("...another character's name where the player's was", (PageWords() or ""):find("Zweite, Ihr müsst", 1, true) ~= nil, true)
stub.world.playerName = "Tester"
local kept = VO.Addon.db.global.CompendiumText
Expect("...kept by language", kept.deDE[KOBOLDS] ~= nil and kept.enUS == nil, true)
-- A quest whose English has a word for each sex: what a man was told is not shown to a woman.
stub.world.questID = CANDLES
stub.world.title = "Koboldkerzen"
stub.world.questText = "Hallo, werter Herr!"
stub.FireEvent("QUEST_DETAIL")
stub.world.questID = 0
Tab:Refresh()
Click("Koboldkerzen")
Expect("words kept from a man's window, shown to a man", (PageWords() or ""):find("Hallo, werter Herr!", 1, true) ~= nil, true)
stub.world.unitSex = 3
Tab:Refresh()
Expect("...and to a woman, the English, with her word", (PageWords() or ""):find("Hello, my lady!", 1, true) ~= nil, true)
stub.world.unitSex = 2
stub.SetLocale("enUS")
stub.world.questID = CANDLES
stub.FireEvent("QUEST_DETAIL")
stub.world.questID = 0
Expect("an English client keeps nothing: the English ships", VO.Addon.db.global.CompendiumText.enUS, nil)

-- A client without the art: the list is drawn in plain colours instead, and still works.
_G.C_Texture = { GetAtlasInfo = function() return nil end }
Tab:Open(KOBOLDS)
local plainBanner, plainCard = RowFor("Eastern Kingdoms"), RowFor("Elwynn Forest")
Expect("with no campaign header, a banner is a dark band with gold edges", plainBanner.bannerFill:IsShown()
    and plainBanner.headMiddle:IsShown(), false)
Expect("...its plus or minus the older buttons", plainBanner.toggle.texture, [[Interface\Buttons\UI-MinusButton-Up]])
Expect("with no character select card, a card a faint fill", plainCard.cardFill:IsShown() and plainCard.face[5]:IsShown(), false)
Expect("...its painting without the frame", plainCard.icon:IsShown() and plainCard.iconFrame:IsShown(), false)
Expect("...its bar a flat yellow, no frame", plainCard.fill.texture == nil and plainCard.barCaps[1]:IsShown(), false)
Click("Elwynn Forest")
plainCard = RowFor("Elwynn Forest")
Expect("...chosen, the list's own light full with its gold edge", plainCard.selected and plainCard.wash:IsShown()
    and plainCard.wash.alpha == 1 and plainCard.edge:IsShown(), true)
_G.C_Texture = { GetAtlasInfo = stub.ListAtlas }

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll quests compendium tests passed")
