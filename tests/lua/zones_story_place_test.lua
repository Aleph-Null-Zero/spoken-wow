-- A dungeon whose story is kept under another zone than its entrance's: Razorfen Downs, told under
-- Thousand Needles and entered in The Barrens. Found at its entrance, it is told by its story's own
-- ids (s:1441:razorfen downs), with the real zone and queue code. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local Expect, Failures = H.Expecter(print)
local SPOKEN = here .. "/../../addons/Spoken/"
local ZONES = here .. "/../../addons/Spoken_Places/"
local after = C_Timer.After

local BARRENS, NEEDLES = 1413, 1441
local ENTRANCE = { map = BARRENS, zone = "The Barrens", subzone = "Razorfen Downs" }

local function Boot()
    stub.SetClient("16001")
    stub.ResetSound(); stub.ResetTimers()
    stub.world.inCombat = false
    stub.world.playerLevel = 40
    SpokenZonesSettings = nil
    SpokenZonesCharacter = { greeted = true }
    SpokenZonesAudioPacks = {
        SpokenZonesAudio = { version = 1, addon = "SpokenZonesAudio", language = "enUS", zones = {},
            subzones = { [NEEDLES] = { ["razorfen downs"] = { file = "1441\\razorfen-downs", len = 40 } } } },
    }
    local env = stub.LoadSpoken(SPOKEN)
    env.Addon:Enable()
    C_Timer.After = after
    local Z = H.LoadZones(ZONES)
    assert(loadfile(ZONES .. "Locale/enUS.lua"))("Spoken_Places", Z)
    for _, file in ipairs({ "Autoplay", "Discovery", "Data/Dungeons", "UI/LoreWindow" }) do
        assert(loadfile(ZONES .. file .. ".lua"))("Spoken_Places", Z)
    end
    Z.Zones[BARRENS] = { name = "The Barrens", full = "Dry land." }
    Z.Zones[NEEDLES] = { name = "Thousand Needles", full = "Spires." }
    Z.Subzones[BARRENS] = { crossroads = { name = "Crossroads", full = "A fort." } }
    Z.Subzones[NEEDLES] = { ["razorfen downs"] = { name = "Razorfen Downs", full = "The quilboars' barrows." } }
    Z.GetMapName = function(_, mapID) return Z.Zones[mapID] and Z.Zones[mapID].name end
    stub.SetZone(ENTRANCE)
    stub.FireEvent("ADDON_LOADED", "Spoken_Places")
    Z:SetupAudio()
    Z:SetupAutoplay()
    Z:SetupDiscovery()
    return Z
end

local Z = Boot()
local entry, key, story = Z:GetSubzoneLore(BARRENS, "Razorfen Downs")
Expect("at its entrance in The Barrens, Razorfen Downs finds its story under Thousand Needles",
    (entry and entry.full) .. "|" .. tostring(key) .. "|" .. tostring(story), "The quilboars' barrows.|razorfen downs|1441")
Expect("...as it does where the story is kept", select(3, Z:GetSubzoneLore(NEEDLES, "Razorfen Downs")), NEEDLES)
Expect("any other area is told where it is found", select(3, Z:GetSubzoneLore(BARRENS, "Crossroads")), BARRENS)
Expect("StoryPlace names where a story found at a map is kept",
    table.concat({ Z:StoryPlace(BARRENS, "razorfen downs") }, "|") .. " " .. table.concat({ Z:StoryPlace(BARRENS, "crossroads") }, "|"),
    "1441|razorfen downs 1413|crossroads")

-- With Autoplay Explored Areas on, standing in it is enough.
Z:Set("autoplayExplored", true)
stub.FireEvent("ZONE_CHANGED")
local clip = Spoken:GetCurrent()
Expect("standing at its entrance plays its story by its own id", clip and clip.key, "s:1441:razorfen downs")
Expect("...headed by The Barrens, where its entrance is", clip and clip.present.header, "The Barrens")
Expect("...and its report names the story's map", clip and Z:ReportURL(clip.mapID, clip.areaKey),
    "https://spoken.rusty.one/zones/r/1441/razorfen-downs")
Expect("...and the visit is recorded at its entrance, where it is found",
    tostring(SpokenZonesCharacter.visited["1413/razorfen downs"]) .. "|" .. tostring(Z:IsFound(NEEDLES, "razorfen downs")),
    "true|true")

Z = Boot()
stub.FireEvent("CHAT_MSG_SYSTEM", "Discovered Razorfen Downs: 10 experience gained.")
clip = Spoken:GetCurrent()
Expect("discovering it at its entrance plays the same story", clip and clip.key, "s:1441:razorfen downs")

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll zones story place tests passed")
