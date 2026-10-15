-- The login greeting: a new character hears its starting area once, and a character whose
-- saved record was lost is still not greeted with wherever it logs in.
-- Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local Expect, Failures = H.Expecter(print)
local SPOKEN = here .. "/../../addons/Spoken/"
local ZONES = here .. "/../../addons/Spoken_Places/"
local after = C_Timer.After
local getMapInfo = C_Map.GetMapInfo

local function Boot(where, level, record)
    stub.SetClient("16001")
    stub.ResetSound(); stub.ResetTimers()
    stub.world.inCombat = false
    stub.world.playerLevel = level
    SpokenZonesSettings = nil
    SpokenZonesCharacter = record
    SpokenZonesAudioPacks = {
        SpokenZonesAudio = { version = 1, addon = "SpokenZonesAudio", language = "enUS",
            zones = { [1411] = { file = "1411\\zone", len = 80 }, [1453] = { file = "1453\\zone", len = 80 } },
            subzones = { [1411] = {
                ["valley of trials"] = { file = "1411\\valley-of-trials", len = 35 },
                ["razor hill"] = { file = "1411\\razor-hill", len = 35 },
            } } },
    }
    local env = stub.LoadSpoken(SPOKEN)
    env.Addon:Enable()
    C_Timer.After = after
    local Z = H.LoadZones(ZONES)
    assert(loadfile(ZONES .. "Locale/enUS.lua"))("Spoken_Places", Z)
    assert(loadfile(ZONES .. "Autoplay.lua"))("Spoken_Places", Z)
    Z.Zones[1411] = { name = "Durotar", full = "Durotar lore." }
    Z.Zones[1453] = { name = "Stormwind City", full = "Stormwind lore." }
    Z.Subzones[1411] = {
        ["valley of trials"] = { name = "Valley of Trials", full = "Valley lore." },
        ["razor hill"] = { name = "Razor Hill", full = "Razor Hill lore." },
    }
    stub.SetZone(where)
    stub.FireEvent("ADDON_LOADED", "Spoken_Places")
    Z:SetupAudio()
    Z:SetupAutoplay()
    return Z
end

local VALLEY = { map = 1411, zone = "Durotar", subzone = "Valley of Trials" }

Boot(VALLEY, 1, nil)
stub.Advance(2)
Expect("a new character in its starting area is greeted", Spoken:IsPlaying(), true)
Expect("...and remembered", SpokenZonesCharacter.greeted, true)

Boot(VALLEY, 1, { greeted = true })
stub.Advance(20)
Expect("a character greeted before is not greeted again", Spoken:GetQueueSize(), 0)

-- The record lost, as after a crash before logout.
Boot({ map = 1453, zone = "Stormwind City", subzone = "Trade District" }, 1, nil)
stub.Advance(20)
Expect("a level 1 character parked in a city is not greeted", Spoken:GetQueueSize(), 0)
Expect("...nor marked greeted", SpokenZonesCharacter.greeted, nil)

Boot({ map = 1411, zone = "Durotar", subzone = "Razor Hill" }, 1, nil)
stub.Advance(20)
Expect("a level 1 character out of its valley is not greeted", Spoken:GetQueueSize(), 0)

Boot(VALLEY, 12, nil)
stub.Advance(20)
Expect("a levelled character back in a valley is not greeted", Spoken:GetQueueSize(), 0)

-- A new character's first answers name the continent, with no subzone yet.
local continent = true
C_Map.GetMapInfo = function(id) return { mapType = continent and 2 or 3 } end
Boot({ map = 1411, zone = "", subzone = "" }, 1, nil)
stub.Advance(6)
Expect("the greeting waits while the map is the continent", Spoken:GetQueueSize(), 0)
Expect("...without spending its turn", SpokenZonesCharacter.greeted, nil)
continent = false
stub.SetZone(VALLEY)
stub.Advance(2)
Expect("once the map settles on the valley, it is greeted", Spoken:IsPlaying(), true)
C_Map.GetMapInfo = getMapInfo

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll zones greeting tests passed")
