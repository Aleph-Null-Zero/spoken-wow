-- The mark on quests heard through, in the Quests tab of Azeroth's Compendium: a quest is heard
-- once every part the voice packs have of it has played to its end, or been skipped with most of
-- it heard, on any character of the account; the mark shows on its row and on its page, and says
-- what it means. Against the shipped data. Run with `make test-player`.
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
    [1429] = { "Elwynn Forest", 1415 }, [1453] = { "Stormwind City", 1415 } }
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
    return frame
end

-- A human mage who has completed Kobold Camp Cleanup and Kobold Candles.
local KOBOLDS, CANDLES = 7, 60
_G.UnitRace = function() return "Human", "Human", 1 end
_G.UnitClass = function() return "Mage", "MAGE", 8 end
_G.GetQuestsCompleted = function() return { [KOBOLDS] = true, [CANDLES] = true } end

local VO = stub.LoadQuests(QUESTS, SPOKEN)
VO.Addon:OnInitialize()
local Spoken = _G.Spoken
local B = {}
for _, file in ipairs({ "Locale/enUS", "UI/Layout", "UI/TextView", "UI/Compendium" }) do
    assert(loadfile(BOOKS .. file .. ".lua"))("Spoken_Books", B)
end
local ns = {}
for _, file in ipairs({ "Data/Compendium", "Data/QuestText", "UI/TextView", "UI/QuestsTab", "UI/QuestsHeard" }) do
    assert(loadfile(QUESTS .. file .. ".lua"))("Spoken_Quests", ns)
end
local L, Tab = VO.L, VO.QuestsTab
stub.FireEvent("PLAYER_ENTERING_WORLD")
Tab:Open()
local panel = Tab.panel
local page = panel.page

local function RowFor(label, frame)
    for _, child in ipairs((frame or panel).children or {}) do
        if child.row and child.shown ~= false and child.label.text == label then return child end
        local found = RowFor(label, child)
        if found then return found end
    end
end
local function Click(label)
    local row = RowFor(label)
    assert(row, "no row " .. label)
    row.scripts.OnClick(row)
end
local function Marked(label)
    local row = RowFor(label)
    return row ~= nil and row.heardMark ~= nil and row.heardMark:IsShown()
end
local function PageMarked()
    return page.heardMark ~= nil and page.heardMark:IsShown()
end

local lengths = { ["7-accept"] = 2, ["7-complete"] = 2, ["60-accept"] = 10 }
VO.DataModules:Register("TestPack", {
    SoundLengthLookupByFileName = lengths,
    GetSoundPath = function(_, fileName) return fileName .. ".ogg" end,
})

Click("Elwynn Forest")
Click("Kobold Camp Cleanup")
Expect("a quest not heard has no mark on its row", Marked("Kobold Camp Cleanup"), false)
Expect("...nor on its page", PageMarked(), false)

-- Its offer heard to the end through Play, which plays the offer alone; then the offer again,
-- stopped at once.
page.play.scripts.OnClick(page.play)
stub.Advance(3)
page.play.scripts.OnClick(page.play)
local heard = VO.Addon.db.global.CompendiumHeard
Expect("a part played to its end is kept, for the whole account", heard and heard[KOBOLDS] and heard[KOBOLDS].accept, true)
Expect("...one stopped as it began is not", heard[KOBOLDS].complete, nil)
Expect("with a part not heard, no mark", Marked("Kobold Camp Cleanup") or PageMarked(), false)

-- Played through: the hand-in heard too, where the quest giver says it.
VO.Player:PlayNow({ event = VO.Enums.SoundEvent.QuestComplete, questID = KOBOLDS, title = "Kobold Camp Cleanup" })
stub.Advance(10)
Expect("every part the packs have heard through: the mark on its row", Marked("Kobold Camp Cleanup"), true)
Expect("...and on its page", PageMarked(), true)
Expect("...the row's name stops short of it", RowFor("Kobold Camp Cleanup").label.anchor.relativeTo,
    RowFor("Kobold Camp Cleanup").heardMark)

local tooltip = {}
local gameTooltip = _G.GameTooltip
_G.GameTooltip = { SetOwner = function() end, SetText = function(_, text) tooltip.title = text end,
    AddLine = function(_, text) tooltip.line = text end, Show = function() end, Hide = function() end }
local mark = RowFor("Kobold Camp Cleanup").heardMark
mark.scripts.OnEnter(mark)
_G.GameTooltip = gameTooltip
Expect("the mark says what it means", tooltip.title == L.QUEST_HEARD and tooltip.line, L.QUEST_HEARD_TIP)

-- Skipped: heard once most of it has played.
Click("Kobold Candles")
page.play.scripts.OnClick(page.play)
stub.Advance(3)
Spoken:Skip()
Expect("a part skipped early is not heard", Marked("Kobold Candles") or PageMarked(), false)
page.play.scripts.OnClick(page.play)
stub.Advance(9)
Spoken:Skip()
Expect("...one skipped near its end is", Marked("Kobold Candles") and PageMarked(), true)

-- A part a pack adds later has not been heard.
lengths["7-progress"] = 2
Click("Kobold Camp Cleanup")
Expect("a quest with a part newly voiced loses its mark until that is heard", Marked("Kobold Camp Cleanup"), false)

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll quests heard tests passed")
