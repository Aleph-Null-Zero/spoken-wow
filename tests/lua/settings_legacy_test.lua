-- The Spoken page on a legacy client, whose playback (Compat.lua) ignores the sound channel:
-- nothing offers a channel there, and none greys a row over one. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local Expect, Failures = H.Expecter(stub.print)
local SPOKEN = here .. "/../../addons/Spoken/"
local QUESTS = here .. "/../../addons/Spoken_Quests/"

_G.UISpecialFrames = _G.UISpecialFrames or {}

stub.SetClient("1.12"); stub.ResetSound(); stub.ResetTimers(); stub.ResetFrames()
stub.settingsCategories = {}; stub.ldbObjects = {}; stub.dbIcons = {}
stub.world.questID = 0; stub.ShowPanel(nil)
local VO = stub.LoadQuests(QUESTS, SPOKEN)
VO.Addon:OnInitialize()
local env = _G.SpokenEnv
env.Addon:Enable()
local L, Options = env.L, env.Options
local home = _G.SpokenOptionsPanel.layout

local function Row(label)
    for _, entry in ipairs(home.entries) do
        -- Prefix: a legacy dropdown is a button labelled "<label>: %s".
        if entry.label:sub(1, #label) == label then return entry.frame end
    end
end

Expect("1.12 offers no channel to choose", Row(L.OPT_CHANNEL), nil)
-- A profile can still hold Dialog from an older version.
env.Addon.db.profile.Audio.SoundChannel = "Dialog"; Options:UpdateRows()
Expect("...which playback reads as Master", env.Sources:PlayerChannel(), "Master")
local silence = Row(L.OPT_MUTE_DIALOGUE)
Expect("Silence NPC Voices is there", silence ~= nil, true)
Expect("...and not greyed over a channel playback ignores", silence and silence.layoutReason, nil)

if Failures() > 0 then os.exit(1) end
stub.print("\nAll legacy settings tests passed")
