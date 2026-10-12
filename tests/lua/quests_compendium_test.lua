-- The quests in Azeroth's Compendium: every quest this character's race and class may take, in a
-- card for the zone it is in under its continent's banner, or under its class, profession or
-- season; its chain a small card inside, with the chain's page; a quest's page with its words, its
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

local MAPS = { [947] = { "Azeroth" }, [1414] = { "Kalimdor", 947 }, [1415] = { "Eastern Kingdoms", 947 },
    [1429] = { "Elwynn Forest", 1415 }, [1453] = { "Stormwind City", 1415 }, [1436] = { "Westfall", 1415 },
    [1440] = { "Ashenvale", 1414 } }
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
-- reads as single quests.
local NECKLACE, PIE, BACK, GOLDTOOTH = 85, 86, 84, 87
local shipped = SpokenQuestsCompendium.quests
local linked = shipped[PIE].prev == NECKLACE and shipped[BACK].prev == PIE and shipped[GOLDTOOTH].prev == BACK
for _, quest in pairs(shipped) do quest.prev = nil end
SpokenQuestsCompendium.quests[PIE].prev = NECKLACE
SpokenQuestsCompendium.quests[BACK].prev = PIE
SpokenQuestsCompendium.quests[GOLDTOOTH].prev = BACK
local L, Tab = VO.L, VO.QuestsTab
Expect("the shipped data has the quests' chains, from the world DB", linked, true)
local C = _G.SpokenCompendium

Expect("no tab before the world is up", C:Tab("quests"), nil)
stub.FireEvent("PLAYER_ENTERING_WORLD")
Expect("the quests are a tab of Azeroth's Compendium once it is", C:Tab("quests") ~= nil and C:Tab("quests").label, L.COMPENDIUM_QUESTS)
-- A map with no quests and nothing above it.
stub.world.playerMapID = 9999
Tab:Open()
local panel = Tab.panel
local page = panel.page
Expect("...and open on it", C:IsOpen("quests"), true)
Expect("...where the player's zone is not known, on the first continent, as there is no Azeroth to land on",
    page.title.text, "Eastern Kingdoms")
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
faction = "Horde"
Tab:Refresh()
Expect("...the Horde's for a Horde character", RowFor("Eastern Kingdoms").headMiddle.texture, "file:Objective-Header-CampaignHorde")
faction = "Alliance"
Tab:Refresh()
Expect("...each zone a card inside it", RowFor("Elwynn Forest").row.style == "card" and RowFor("Elwynn Forest").row.nest, 0)
Expect("...then a banner each for the quests no zone holds: Classes, Professions, Events, Other",
    list:find("|Classes|Professions|Events|Other$") ~= nil and not Has(list, "Mage")
    and RowFor("Classes").row.style == "banner", true)
local elwynn = RowFor("Elwynn Forest")
Expect("a zone's card: its quests completed out of all on the line under its name",
    elwynn.sub.text:match("^1 of %d+ quests$") ~= nil, true)
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
Expect("...a step in from the continent's banner", elwynn.face[1].anchor.x, 14)
local elwynnTotal = tonumber(elwynn.sub.text:match("of (%d+)"))
Expect("...the share completed on its right", elwynn.count.text, math.floor(100 / elwynnTotal) .. "%")
Expect("...and its bar filled as far", elwynn.fill:IsShown() and math.floor(elwynn.fill.width / elwynn.track.width
    * elwynnTotal + 0.5), 1)
Expect("...with the game's yellow cut to the same share, not squeezed", elwynn.fill.texture == "file:ui-frame-bar-fill-yellow"
    and math.abs(elwynn.fill.texCoord[2] - 1 / elwynnTotal) < 1e-9, true)
Expect("...in the Pet Journal's bar frame", elwynn.barCaps[1]:IsShown() and elwynn.barCaps[1].atlas .. " "
    .. elwynn.barCaps[2].atlas .. " " .. elwynn.barCaps[3].atlas, "PetJournal-ExpBar-Left PetJournal-ExpBar-Mid PetJournal-ExpBar-Right")
Expect("...its page counting its quests", page.sub.text:match("^1 of %d+ completed$") ~= nil, true)
local city = RowFor("Stormwind City")
Expect("a city is a small card inside its zone's card", city ~= nil and city.row.small and city.row.nest, 1)
Expect("...indented under it, its card further in", city.face[1].anchor.x - elwynn.face[1].anchor.x, 28)
Expect("...with the line down the open card's contents beside it", city.rails[1]:IsShown() and city.rails[1].anchor.x, 30)
Expect("...not chosen, the plain card alone", city.lift[5]:IsShown(), false)
city.scripts.OnEnter(city)
Expect("...under the pointer, the hover card over it", city.lift[5]:IsShown() and city.lift[5].texture,
    "file:glues-characterselect-card-singles-hover-c60")
city.scripts.OnLeave(city)
Expect("...and gone again after", city.lift[5]:IsShown(), false)
Expect("...a quest in the zone a row, as far in", RowFor("Kobold Camp Cleanup").row.leaf and RowFor("Kobold Camp Cleanup").row.nest, 1)
Click("Classes")
list = Shown()
Expect("...Classes opening on a class's quests under its name, this character's class only", Has(list, "Mage") and not Has(list, "Warlock"), true)
Expect("...a small card for it", RowFor("Mage").row.style == "card" and RowFor("Mage").row.small, true)
Click("Events")
Expect("...Events on the festivals and the Darkmoon Faire", Has(Shown(), "Lunar Festival") and Has(Shown(), "Darkmoon Faire"), true)
Click("Classes")
Click("Events")
local leftovers, reused = Leftovers()
Expect("a row drawn as a card and reused for a banner or a quest keeps none of the card's parts", leftovers, "")
Expect("...as rows were, once the list changed under them", reused > 0, true)
list = Shown()
Expect("a zone opens on its quests", Has(list, "Kobold Camp Cleanup") and Has(list, "Kobold Candles"), true)
Expect("...a quest completed open to read", RowFor("Kobold Camp Cleanup").row.locked, false)
Expect("...one not completed greyed, with the padlock", RowFor("Kobold Candles").row.locked, true)

Click("Kobold Camp Cleanup")
Expect("a quest's page: its title", page.title.text, "Kobold Camp Cleanup")
Expect("...where it is", page.sub.text, "Elwynn Forest")
Expect("...on one line, cut short", page.sub.wordWrap, false)
local words = page.body.text.text or ""
Expect("...its words, offered then handed in, each headed", words:find(L.QUEST_PART_ACCEPT .. "\n\n", 1, true) == 1
    and words:find("\n\n" .. L.QUEST_PART_COMPLETE .. "\n\n", 1, true) ~= nil, true)
Expect("...no placeholder left in them", words:find("$", 1, true), nil)
Click("Kobold Candles")
Expect("a quest not completed does not open", page.title.text, "Kobold Camp Cleanup")

-- Unlock Unstarted Quests, the switch Spoken's page shows.
C:Tab("quests").unlock.set(true)
Expect("Unlock Unstarted Quests opens it", RowFor("Kobold Candles").row.locked, false)
Click("Kobold Candles")
words = page.body.text.text or ""
Expect("...its words filled for the player: the word for his sex", words:find("Hello, good sir!", 1, true) ~= nil, true)
Expect("...and his name", words:find("Thanks for the candles, Tester,", 1, true) ~= nil, true)
Expect("...and a line break for $B", words:find("moment?\n\nMy brother", 1, true) ~= nil, true)
stub.world.unitSex = 3
Tab:Refresh()
Expect("...and for hers", (page.body.text.text or ""):find("Hello, my lady!", 1, true) ~= nil, true)
stub.world.unitSex = 2
Expect("...choosing it leaves the counts as they were", RowFor("Elwynn Forest").sub.text:match("^1 of ") ~= nil, true)
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
Expect("...and its zone's card counts it in progress, apart from the completed",
    RowFor("Elwynn Forest").sub.text:match("^1 of %d+ quests · 1 in progress$") ~= nil, true)
RowOf(CANDLES).scripts.OnClick(RowOf(CANDLES))
Expect("its page: its title", page.title.text, "Kobold Candles")
Expect("...in progress, then where it is", page.sub.text:find(L.QUEST_IN_PROGRESS .. " • Elwynn Forest", 1, true) ~= nil, true)
Expect("...and its words", (page.body.text.text or ""):find("Thanks for the candles", 1, true) ~= nil, true)
Click("Elwynn Forest")
Expect("a zone's page counts it apart from the completed", page.sub.text:match("^1 of %d+ completed, 1 in progress$") ~= nil, true)
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
Expect("...and is counted", RowFor("Elwynn Forest").sub.text:match("^2 of ") ~= nil, true)

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
box:SetText("")
box.hooks.OnTextChanged[1](box)

-- Chains: a zone's quests that follow one another under one small card, named after the first.
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
Expect("a chain is a small card in its zone's card, named after its first quest", ChainRow("Lost Necklace") ~= nil
    and ChainRow("Lost Necklace").row.small and ChainRow("Lost Necklace").row.nest, 1)
Expect("...its quests inside it, not beside it", RowOfQuest(NECKLACE) or Has(list, "Pie for Billy") or Has(list, "Goldtooth"), false)
Expect("...a quest in no chain still a row of its own", Has(list, "Kobold Camp Cleanup"), true)
Expect("...its badge the storyline's mark, with no frame", ChainRow("Lost Necklace").story:IsShown()
    and ChainRow("Lost Necklace").story.atlas == "questlog-storylineicon" and ChainRow("Lost Necklace").iconFrame:IsShown(), false)
Expect("...its quests completed out of all on the line under its name", ChainRow("Lost Necklace").sub.text, "0 of 4 quests")
Expect("...none completed, none of the share", ChainRow("Lost Necklace").row.none
    and ChainRow("Lost Necklace").count.text, "0%")
Expect("...its bar empty", ChainRow("Lost Necklace").fill:IsShown(), false)
local zoneRow = RowFor("Westfall")
Expect("a zone with none completed: its painting greyed and darker", zoneRow ~= nil and zoneRow.row.none
    and zoneRow.icon.desaturated and zoneRow.icon.vertexColor[1], 0.7)
completed[NECKLACE], completed[PIE] = true, true
questLog = { BACK }
Tab:Refresh()
Expect("...how many are in progress on its line", ChainRow("Lost Necklace").sub.text, "2 of 4 quests · 1 in progress")
Expect("...the share completed", ChainRow("Lost Necklace").count.text, "50%")
local track, fill = ChainRow("Lost Necklace").track, ChainRow("Lost Necklace").fill
Expect("...and its bar filled as far as completed", fill:IsShown() and math.floor(fill.width / track.width * 100 + 0.5), 50)
ClickChain("Lost Necklace")
list = Shown()
Expect("a chain opens on its quests, in the order they are taken",
    list:find("Lost Necklace|Lost Necklace|Pie for Billy|.*Back to Billy|Goldtooth") ~= nil, true)
Expect("...rows one step further in", RowOfQuest(PIE).row.nest, 2)
Expect("...chosen, its page has the chain's name", page.title.text, "Lost Necklace")
Expect("...its count", page.sub.text, "2 of 4 completed, 1 in progress")
local text = page.body.text.text or ""
local DONE = "|A:questlog%-icon%-checkmark%-yellow:14:17|a "
Expect("...and its quests in order, each marked: the quest log's gold tick, the quest mark, the padlock",
    text:find("^" .. DONE .. "Lost Necklace\n.-\n\n" .. DONE .. "Pie for Billy\n.-\n\n|TInterface\\GossipFrame\\ActiveQuestIcon:0|t "
    .. "Back to Billy\n.-\n\n|A:LFG%-lock:16:13|a Goldtooth\n" .. L.QUEST_NOT_STARTED .. "$") ~= nil, true)
Expect("...each one started with the first sentence or two of its offer", text:find("Lost Necklace\nI lost my necklace, and "
    .. "think that guttersnipe Billy Maclure took it! He's usually scuttling like a rat around the Maclure vineyards east "
    .. "of here.\n\n", 1, true) ~= nil, true)
Expect("...one not started without it", text:find("Goldtooth\n" .. L.QUEST_NOT_STARTED .. "$") ~= nil
    and text:find("Fargodeep", 1, true), nil)
completed[BACK], completed[GOLDTOOTH] = true, true
questLog = {}
Tab:Refresh()
Expect("a chain all completed gets a tick in place of its share", ChainRow("Lost Necklace").tick:IsShown()
    and ChainRow("Lost Necklace").count:IsShown(), false)
Expect("...the quest log's gold tick", ChainRow("Lost Necklace").row.tick and ChainRow("Lost Necklace").tick.atlas,
    "questlog-icon-checkmark-yellow")
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

-- Play: the first part the voice packs have of the quest, with its words.
VO.DataModules:Register("TestPack", {
    SoundLengthLookupByFileName = { ["7-accept"] = 2, ["7-complete"] = 2, ["85-accept"] = 2, ["85-complete"] = 2 },
    GetSoundPath = function(_, fileName) return fileName .. ".ogg" end,
})
Click("Kobold Camp Cleanup")
Expect("a voiced quest's page has Play", page.play ~= nil and page.play:IsShown(), true)
page.play.scripts.OnClick(page.play)
local queued = {}
for _, clip in ipairs(Spoken:GetQueue()) do table.insert(queued, clip.fileName) end
Expect("...which plays its offer alone, not the hand-in after it", table.concat(queued, ","), "7-accept")
local playing = Spoken:GetQueue()[1]
Expect("...with the offer's words, for the window to show and highlight",
    playing and type(playing.text) == "string" and playing.text ~= "" and page.body.text.text:find(playing.text, 1, true) ~= nil, true)
page.play.scripts.OnClick(page.play)
Expect("...and again, stops them", #VO.Player:Queued(), 0)
Click("Kobold Candles")
Expect("a quest no pack has has no Play", page.play:IsShown(), false)
ClickChain("Lost Necklace")
Expect("a chain with nothing started has no Play", page.play:IsShown(), false)
completed[NECKLACE] = true
Tab:Refresh()
Expect("...one with a voiced quest started has", page.play:IsShown(), true)
page.play.scripts.OnClick(page.play)
queued = {}
for _, clip in ipairs(Spoken:GetQueue()) do table.insert(queued, clip.fileName) end
Expect("...which plays that quest's first part", table.concat(queued, ","), "85-accept")
page.play.scripts.OnClick(page.play)
completed[NECKLACE] = nil
ClickChain("Lost Necklace")

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
stub.world.questID = 0
stub.ShowPanel(nil)
stub.FireEvent("QUEST_FINISHED")

-- The quest log's details, on either log.
questLog, logQuest = { HEIRLOOM, CANDLES }, HEIRLOOM
QuestLog_UpdateQuestDetails()
Tab.logButton.scripts.OnClick(Tab.logButton)
Expect("the quest log's Open on a quest in progress shows its words", page.title.text == "The Forgotten Heirloom"
    and page.body.text.text ~= L.QUEST_NOT_FOUND, true)
logQuest = CANDLES
QuestLog_UpdateQuestDetails()
Expect("Classic Era's quest log details have it", Tab.logButton:IsShown() and Tab.logButton.questID, CANDLES)
Tab.logButton.scripts.OnClick(Tab.logButton)
Expect("...and open the quest", page.title.text, "Kobold Candles")
questLog, logQuest = {}, nil
QuestLog_UpdateQuestDetails()
Expect("...not with no quest chosen", Tab.logButton:IsShown(), false)
QuestMapFrame_ShowQuestDetails(HEIRLOOM)
Expect("the map's quest log details have it", Tab.mapButton:IsShown() and Tab.mapButton.questID, HEIRLOOM)
Spoken:SetPartOn("quests", false)
QuestMapFrame_ShowQuestDetails(HEIRLOOM)
Expect("...not with Quests off", Tab.mapButton:IsShown(), false)
Spoken:SetPartOn("quests", true)

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
Expect("...left of Open in Azeroth's Compendium", previously.anchor ~= nil and previously.anchor.relativeTo == giver
    and previously.anchor.point == "RIGHT", true)
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
words = page.body.text.text or ""
Expect("the title the window showed", page.title.text, "Säuberung des Koboldlagers")
Expect("...and its words, over the English", words:find("Ihr müsst die Kobolde vertreiben.", 1, true) ~= nil, true)
Expect("...the moments the window has not shown yet still in English",
    words:find(SpokenQuestsText[KOBOLDS].complete:sub(1, 20), 1, true) ~= nil, true)
stub.world.playerName = "Zweite"
Tab:Refresh()
Expect("...another character's name where the player's was", (page.body.text.text or ""):find("Zweite, Ihr müsst", 1, true) ~= nil, true)
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
Expect("words kept from a man's window, shown to a man", (page.body.text.text or ""):find("Hallo, werter Herr!", 1, true) ~= nil, true)
stub.world.unitSex = 3
Tab:Refresh()
Expect("...and to a woman, the English, with her word", (page.body.text.text or ""):find("Hello, my lady!", 1, true) ~= nil, true)
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
Expect("...chosen, a gold wash with its edge", plainCard.selected and plainCard.chosen:IsShown() and plainCard.edge:IsShown(), true)
_G.C_Texture = { GetAtlasInfo = stub.ListAtlas }

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll quests compendium tests passed")
