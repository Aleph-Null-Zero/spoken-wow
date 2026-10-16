-- The model probe, shared by contributions and the body lookups. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local QUESTS = here .. "/../../addons/Spoken_Quests/"
local SPOKEN = here .. "/../../addons/Spoken/"
local Expect, Failures = H.Expecter(print)

stub.SetClient("11509")
local VO = stub.LoadQuests(QUESTS, SPOKEN)
local world = stub.world
local GUID = "Creature-0-0-0-0-15906-0"

world.modelFileID = 119159
VO.NPCModel:Prime(GUID, "npc")
Expect("a load in flight is loading", VO.NPCModel:IsLoading(), true)
stub.FinishModelLoad()
Expect("once loaded, the model is cached per guid", VO.NPCModel:Get(GUID), 119159)
Expect("a finished load is no longer loading", VO.NPCModel:IsLoading(), false)
local calls = stub.SetUnitCount()
VO.NPCModel:Prime(GUID, "npc")
Expect("a cached guid is never loaded twice", stub.SetUnitCount(), calls)

local heard
table.insert(VO.NPCModel.onLoaded, function(guid) heard = guid end)
local OTHER = "Creature-0-0-0-0-68-0"
world.modelFileID = 119940
VO.NPCModel:Prime(OTHER, "target")
Expect("the unit asked for is the one probed", stub.playerModel.unit, "target")
stub.FinishModelLoad()
Expect("a finished load tells whoever listens", heard, OTHER)

local THIRD = "Creature-0-0-0-0-69-0"
VO.NPCModel:Prime(THIRD, "npc")
VO.NPCModel:Abandon()
Expect("an abandoned load is not loading", VO.NPCModel:IsLoading(), false)
Expect("...and is not cached", VO.NPCModel:Get(THIRD), nil)

os.exit(Failures() == 0 and 0 or 1)
