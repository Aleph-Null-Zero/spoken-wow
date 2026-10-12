-- Shift-click on a quest in the Quests tab of Azeroth's Compendium: its recording goes into
-- Spoken's queue behind what is playing, as Play hands it over, and the quest chosen stays
-- chosen. A plain click still chooses. Against the shipped data. Run with `make test-player`.
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
local shift = false
_G.IsShiftKeyDown = function() return shift end

local VO = stub.LoadQuests(QUESTS, SPOKEN)
VO.Addon:OnInitialize()
local Spoken = _G.Spoken
local B = {}
for _, file in ipairs({ "Locale/enUS", "UI/Layout", "UI/TextView", "UI/Compendium" }) do
    assert(loadfile(BOOKS .. file .. ".lua"))("Spoken_Books", B)
end
local ns = {}
for _, file in ipairs({ "Data/Compendium", "Data/QuestText", "UI/TextView", "UI/QuestsTab" }) do
    assert(loadfile(QUESTS .. file .. ".lua"))("Spoken_Quests", ns)
end
-- Each quest on its own row, not inside its chain's.
for _, quest in pairs(SpokenQuestsCompendium.quests) do quest.prev = nil end
local L, Tab = VO.L, VO.QuestsTab
stub.FireEvent("PLAYER_ENTERING_WORLD")
Tab:Open()
local page = Tab.panel.page

local function RowFor(label, frame)
    for _, child in ipairs((frame or Tab.panel).children or {}) do
        if child.row and child.shown ~= false and child.label.text == label then return child end
        local found = RowFor(label, child)
        if found then return found end
    end
end
local function Click(label, withShift)
    local row = RowFor(label)
    assert(row, "no row " .. label)
    shift = withShift and true or false
    row.scripts.OnClick(row, "LeftButton")
    shift = false
end
local function Queued()
    local names = {}
    for _, clip in ipairs(Spoken:GetQueue()) do table.insert(names, clip.fileName) end
    return table.concat(names, ",")
end

VO.DataModules:Register("TestPack", {
    SoundLengthLookupByFileName = { ["7-accept"] = 2, ["7-complete"] = 2, ["60-accept"] = 3 },
    GetSoundPath = function(_, fileName) return fileName .. ".ogg" end,
})

Expect("with nothing chosen, the page says shift-click queues a quest", page.body.text.text == L.QUESTS_PICK
    and L.QUESTS_PICK:find("Shift-click", 1, true) ~= nil, true)
Click("Elwynn Forest")
Click("Kobold Camp Cleanup")
page.play.scripts.OnClick(page.play)
Expect("Play on a quest's page plays it", Queued(), "7-accept")

Click("Kobold Candles", true)
Expect("a shift-click on another quest queues its recording after what is playing", Queued(),
    "7-accept,60-accept")
Expect("...the line speaking left speaking", Spoken:GetCurrent() and Spoken:GetCurrent().fileName, "7-accept")
Expect("...and the quest chosen still chosen", page.title.text, "Kobold Camp Cleanup")
Expect("...its row still the chosen one", RowFor("Kobold Camp Cleanup").selected and not RowFor("Kobold Candles").selected, true)
Click("Kobold Candles", true)
Expect("a second shift-click does not queue it twice", Queued(), "7-accept,60-accept")

Spoken:StopAll()
Click("Kobold Candles", true)
Expect("with nothing playing, a shift-click plays it", Spoken:GetCurrent() and Spoken:GetCurrent().fileName, "60-accept")
Spoken:StopAll()

Click("Kobold Candles")
Expect("a plain click still chooses the quest", page.title.text, "Kobold Candles")
Expect("...and plays nothing", Queued(), "")

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll quests shift-queue tests passed")
