-- Places and Readables keep their settings in Spoken's profile (Modules.Zones and
-- Modules.Writings): copied from what the player had saved the first time, under the same keys,
-- and a profile made later starts from the defaults. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local SPOKEN = here .. "/../../addons/Spoken/"
local READABLES = here .. "/../../addons/Spoken_Readables/"
local PLACES = here .. "/../../addons/Spoken_Places/"
local Expect, Failures = H.Expecter(print)

stub.SetClient("16001"); stub.ResetSound(); stub.ResetTimers(); stub.ResetFrames()
stub.SetAddOns({ { folder = "Spoken_Places", meta = { Version = "9.9.9" } } })
-- The callbacks Spoken registers with AceDB are kept, and fired by hand after the stub's profile
-- calls, which fire none: a switch then runs Spoken's own rebinding and each module's bind function.
local callbacks = {}
do
    local AceDB = _G.LibStub("AceDB-3.0")
    local realNew = AceDB.New
    AceDB.New = function(lib, name, defaults)
        local made = realNew(lib, name, defaults)
        made.RegisterCallback = function(_, event, fn) callbacks[event] = fn end
        return made
    end
end
local env = stub.LoadSpoken(SPOKEN)
local db = env.Addon.db
local function Switch(name)
    db:SetProfile(name)
    callbacks.OnProfileChanged("OnProfileChanged", db, name)
end

local function Readables()
    local B = {}
    for _, file in ipairs({ "Locale/enUS", "Checksum", "Core" }) do
        assert(loadfile(READABLES .. file .. ".lua"))("Spoken_Readables", B)
    end
    B:InitDB()
    return B
end

---------------------------------------------------------------- Readables
_G.SpokenBooksSettings = { autoplay = false, readOnce = true }
_G.SpokenBooksCharacter = nil
local B = Readables()
local mine = db.profile.Modules.Writings
Expect("Readables: what the player saved is copied under the same keys", mine.autoplay == false and mine.readOnce == true, true)
Expect("Readables: the settings the player reads are the profile's table", SpokenBooksSettings == mine, true)
Expect("Readables: a setting not saved before has its default", mine.readWholeBook, true)
B:Set("stopOnClose", true)
Expect("Readables: a change is written to the profile", mine.stopOnClose, true)

-- A reload: the old table still on disk is not copied again over the profile's.
_G.SpokenBooksSettings = { autoplay = true }
B = Readables()
Expect("Readables: a later load keeps the profile's values", db.profile.Modules.Writings.autoplay, false)

-- Another profile: its own table, from the defaults, and the old one is left as it was.
db:SetProfile("Second")
env.Addon:RebindModules()
local second = db.profile.Modules.Writings
Expect("Readables: a profile made later starts from the defaults", second.autoplay == true and second.readOnce == false, true)
Expect("Readables: ...and is the table read now", SpokenBooksSettings == second, true)
db:SetProfile("Default")
env.Addon:RebindModules()
Expect("Readables: going back finds the first profile's values", SpokenBooksSettings.readOnce, true)

---------------------------------------------------------------- Places
db:SetProfile("Places profile")
db.global.ModulesLegacy = nil
_G.SpokenZonesSettings = { language = "deDE", showPictures = false, dump = { 1, 2, 3 } }
_G.SpokenZonesAudioPacks = {}
local Z = H.LoadPlaces(PLACES, {})
local places = db.profile.Modules.Zones
Expect("Places: the language and switches are copied under the same keys",
    places.language == "deDE" and places.showPictures == false, true)
Expect("Places: the developer's dump is not a setting", places.dump, nil)
Expect("Places: a setting not saved before reads its default", Z:Get("voiceEnabled"), true)
Expect("Places: reads and writes go to the profile's table", Z:Get("showPictures") == false and SpokenZonesSettings == places, true)

-- A switch with the addon running: its database is set, so the bind function runs again.
stub.FireEvent("ADDON_LOADED", "Spoken_Places")
Switch("Places second")
Expect("Places: a profile switch binds the new profile's table", Z.db ~= nil and Z.db == SpokenZonesSettings
    and SpokenZonesSettings == db.profile.Modules.Zones, true)
Expect("Places: ...which starts from the defaults", SpokenZonesSettings.showPictures, true)
Z:Set("showPictures", false)
Switch("Places profile")
Expect("Places: going back finds the first profile's values", Z:Get("showPictures"), false)

-- The language is resolved once, at load. A profile that reads another one says so, once.
do
    db:SetProfile("Places German")
    db.profile.Modules = { Zones = { language = "deDE" } }
    callbacks.OnProfileChanged("OnProfileChanged", db, "Places German")
    local langs = { { code = "enUS", ready = true }, { code = "deDE", ready = true } }
    _G.SpokenZonesSettings = db.profile.Modules.Zones
    _G.SpokenZonesAudioPacks = {}
    Z = H.LoadPlaces(PLACES, { Languages = langs })
    assert(loadfile(PLACES .. "Locale/enUS.lua"))("Spoken_Places", Z)
    stub.FireEvent("ADDON_LOADED", "Spoken_Places")
    Expect("Places: this load reads German", Z:GetLanguage(), "deDE")
    stub.chat = {}
    db:SetProfile("Places German again")
    db.profile.Modules = { Zones = { language = "deDE" } }
    callbacks.OnProfileChanged("OnProfileChanged", db, "Places German again")
    Expect("Places: a profile that reads the same language says nothing", #stub.chat, 0)
    db.profile.Modules = { Zones = { language = "enUS" } }
    callbacks.OnProfileChanged("OnProfileChanged", db, "Places German again")
    local said = table.concat(stub.chat, "|")
    Expect("Places: a profile that reads another language says so", said:find("English", 1, true) ~= nil and said:find("/reload", 1, true) ~= nil, true)
    Expect("Places: ...once", #stub.chat, 1)
end

-- The same for Readables, through its own bind function.
B = Readables()
Switch("Readables second")
Expect("Readables: a profile switch binds the new profile's table", SpokenBooksSettings == db.profile.Modules.Writings
    and SpokenBooksSettings.autoplay, true)

if Failures() > 0 then print(Failures() .. " failure(s)"); os.exit(1) end
