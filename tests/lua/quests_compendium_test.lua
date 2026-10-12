-- The quests in Azeroth's Compendium: every quest this character's race and class may take, by
-- the zone it is in, or under its class, profession or season; a quest's page with its words, its
-- placeholders filled for the player; found once completed; Completed Only, the search and Unlock
-- Uncompleted Quests; Play; and on a client in another language, the words its windows showed.
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
_G.C_Texture = { GetAtlasInfo = function(name) return (name == "LFG-lock" or name == "Professions_Recipe_Hover") and {} or nil end }
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
local ns = {}
for _, file in ipairs({ "Data/Compendium", "Data/QuestText", "UI/TextView", "UI/QuestsTab" }) do
    assert(loadfile(QUESTS .. file .. ".lua"))("Spoken_Quests", ns)
end
local L, Tab = VO.L, VO.QuestsTab
local C = _G.SpokenCompendium

Expect("no tab before the world is up", C:Tab("quests"), nil)
stub.FireEvent("PLAYER_ENTERING_WORLD")
Expect("the quests are a tab of Azeroth's Compendium once it is", C:Tab("quests") ~= nil and C:Tab("quests").label, L.COMPENDIUM_QUESTS)
Tab:Open()
local panel = Tab.panel
local page = panel.page
Expect("...and open on it", C:IsOpen("quests"), true)

local rows
local function Collect(frame)
    for _, child in ipairs(frame.children or {}) do
        if child.row then table.insert(rows, child) end
        Collect(child)
    end
end
local function Shown()
    rows = {}
    Collect(panel)
    local labels = {}
    for _, row in ipairs(rows) do if row.shown ~= false and row.row then table.insert(labels, row.label.text) end end
    return table.concat(labels, "|")
end
local function RowFor(label)
    Shown()
    for _, row in ipairs(rows) do if row.shown ~= false and row.row and row.label.text == label then return row end end
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
Expect("the tree is the places': Azeroth, its continents, their zones", Has(list, "Azeroth") and Has(list, "Eastern Kingdoms")
    and Has(list, "Elwynn Forest"), true)
Expect("...then a class's quests under its name, this character's class only", Has(list, "Mage") and not Has(list, "Warlock"), true)
Expect("...each zone counted, completed out of all", RowFor("Elwynn Forest").count.text:match("^1/") ~= nil, true)
Expect("with nothing chosen, the page counts every quest", page.sub.text:match("^1 of %d+ completed$") ~= nil, true)

Click("Elwynn Forest")
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

-- Unlock Uncompleted Quests, the switch Spoken's page shows.
C:Tab("quests").unlock.set(true)
Expect("Unlock Uncompleted Quests opens it", RowFor("Kobold Candles").row.locked, false)
Click("Kobold Candles")
words = page.body.text.text or ""
Expect("...its words filled for the player: the word for his sex", words:find("Hello, good sir!", 1, true) ~= nil, true)
Expect("...and his name", words:find("Thanks for the candles, Tester,", 1, true) ~= nil, true)
Expect("...and a line break for $B", words:find("moment?\n\nMy brother", 1, true) ~= nil, true)
stub.world.unitSex = 3
Tab:Refresh()
Expect("...and for hers", (page.body.text.text or ""):find("Hello, my lady!", 1, true) ~= nil, true)
stub.world.unitSex = 2
Expect("...choosing it leaves the counts as they were", RowFor("Elwynn Forest").count.text:match("^1/") ~= nil, true)
C:Tab("quests").unlock.set(false)

-- Completing one in the world finds it.
completed[CANDLES] = true
Tab:Refresh()
Expect("a quest completed since opens", RowFor("Kobold Candles").row.locked, false)
Expect("...and is counted", RowFor("Elwynn Forest").count.text:match("^2/") ~= nil, true)

-- Completed Only.
VO.Addon.db.global.Compendium.FoundOnly = true
Tab:Refresh()
list = Shown()
Expect("Completed Only leaves out what is not completed", Has(list, "Wolves Across the Border") or Has(list, "Mage"), false)
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

-- Play: what the voice packs have of the quest, from the offer on.
VO.DataModules:Register("TestPack", {
    SoundLengthLookupByFileName = { ["7-accept"] = 2, ["7-complete"] = 2 },
    GetSoundPath = function(_, fileName) return fileName .. ".ogg" end,
})
Click("Kobold Camp Cleanup")
Expect("a voiced quest's page has Play", page.play ~= nil and page.play:IsShown(), true)
page.play.scripts.OnClick(page.play)
local queued = {}
for _, clip in ipairs(Spoken:GetQueue()) do table.insert(queued, clip.fileName) end
Expect("...which plays its offer, then its hand-in", table.concat(queued, ","), "7-accept,7-complete")
page.play.scripts.OnClick(page.play)
Expect("...and again, stops them", #VO.Player:Queued(), 0)
Click("Kobold Candles")
Expect("a quest no pack has has no Play", page.play:IsShown(), false)

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

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll quests compendium tests passed")
