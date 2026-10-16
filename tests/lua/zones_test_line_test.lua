-- The zones page's Test line, Start Over and Text Size, with the addon's Core.lua loaded for real. Run
-- with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local SPOKEN = here .. "/../../addons/Spoken/"
local ZONES = here .. "/../../addons/Spoken_Places/"
local Expect, Failures = H.Expecter(print)

stub.SetClient("16001")
stub.LoadSpoken(SPOKEN)
local Z = H.LoadZones(ZONES)
_G.SpokenZonesSettings = { voiceEnabled = true }
local printed = {}
Z.Print = function(_, fmt, ...)
    table.insert(printed, select("#", ...) > 0 and fmt:format(...) or fmt)
end

---------------------------------------------------------------- Test line
-- No voice pack: every story lacks a clip. Trying each in turn printed why, once per zone.
Z.Zones = {}
for id = 1, 50 do Z.Zones[id] = { name = "Zone " .. id } end
Z:PlayTestLine()
Expect("with no voice pack, the test line says so once", #printed, 1)
Expect("...naming the missing pack", printed[1] and printed[1]:find("no sound pack installed", 1, true) ~= nil, true)

-- A pack covering one story far down the list: that one plays, and nothing is printed for the
-- ones before it.
printed = {}
local tried = {}
Z.HasAudio = function(_, mapID) return mapID == 40 end
Z.PlayLore = function(_, mapID) table.insert(tried, mapID); return true end
Z:PlayTestLine()
Expect("the first story with a clip is the one played", table.concat(tried, ","), "40")
Expect("...without a word about the others", #printed, 0)

---------------------------------------------------------------- Start Over
-- The page's reset writes the defaults and applies them, as the checkboxes do.
local notified = 0
Z.NotifyAudioChanged = function() notified = notified + 1 end
_G.SpokenZonesSettings.voiceEnabled = false
Z:ResetOptions()
Expect("a reset brings the voice back on", _G.SpokenZonesSettings.voiceEnabled, true)
Expect("...and the play buttons hear the voice is on again", notified, 1)

---------------------------------------------------------------- Text Size
-- Azeroth's Compendium's, on Spoken's page. Until it is set there, the size the Zones page had.
local Spoken = _G.Spoken
_G.SpokenZonesSettings.fontSize = 15
Expect("Text Size not yet set on Spoken's page is the one the Zones page had, which Zones reads",
    Spoken:CompendiumFontSize() .. "|" .. Z:Get("fontSize"), "15|15")
local told = 0
Spoken:RegisterCallback("COMPENDIUM_FONT_CHANGED", function() told = told + 1 end)
Spoken:SetCompendiumFontSize(18)
Expect("...set there, it is Spoken's, and Zones reads it", Spoken:CompendiumFontSize() .. "|" .. Z:Get("fontSize")
    .. "|" .. _G.SpokenZonesSettings.fontSize, "18|18|15")
Expect("...the parts that draw it told once", told, 1)
Z:ResetOptions()
Expect("the Zones page's Start Over leaves it, as it is on Spoken's page", _G.SpokenZonesSettings.fontSize .. "|"
    .. Z:Get("fontSize"), "15|18")
_G.SpokenEnv.Addon.db.profile.CompendiumFontSize = nil
_G.SpokenZonesSettings.fontSize = nil
Expect("with neither set, it is 12", Spoken:CompendiumFontSize(), 12)

os.exit(Failures() == 0 and 0 or 1)
