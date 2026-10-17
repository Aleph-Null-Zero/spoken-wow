-- One NPC with several gossip texts: the text on screen picks the line, and a text the packs
-- lack for this NPC plays nothing. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local world = stub.world
local QUESTS = here .. "/../../addons/Spoken_Quests/"
local SPOKEN = here .. "/../../addons/Spoken/"
local Expect, Failures = H.Expecter(print)

local TRAINER = 257021
local DEFAULT = "I hope that your interruption is for a good cause, I was in the middle of an experiment."
local HERBALIST = "Another Herbalist, hmm. I doubt your skill is as great as my own so perhaps I can " ..
    "train you in a few proper techniques."
local NAMED = "Greetings, $N. Welcome, my $gbrother:sister;.$B$BThe $c trainers are upstairs."

local lines = { default = 3, herbalist = 4, named = 5, ["en-guess"] = 4 }

local function Boot(locale, gossip)
    stub.SetClient("11509"); stub.ResetSound(); stub.ResetTimers()
    stub.SetLocale(locale or "enUS")
    world.questID = 0; stub.ShowPanel(nil); world.gossipText = nil; world.greetingText = nil
    world.playerName = "Valaas"; world.playerClass = "Mage"; world.unitSex = 2
    _G.SpokenQuestsSettings = nil
    local VO = stub.LoadQuests(QUESTS, SPOKEN)
    VO.Addon:OnInitialize()
    VO.Addon.db.char.hasSeenGossipForNPC = {}
    VO.DataModules:Register("TestPack", {
        SoundLengthLookupByFileName = lines,
        GetSoundPath = function(_, fileName) return fileName .. ".ogg" end,
        LookupLocale = "enUS",
        GossipLookupByNPCID = gossip or { [TRAINER] = {
            [DEFAULT] = "default", [HERBALIST] = "herbalist", [NAMED] = "named" } },
    })
    stub.Advance(2)
    world.npcName = "Halassa Brisecho"; world.npcGUID = "Creature-0-0-0-0-" .. TRAINER .. "-0"
    return VO, _G.Spoken
end

local function Lookup(VO, text)
    local soundData = { event = VO.Enums.SoundEvent.Gossip, unitGUID = world.npcGUID,
        name = world.npcName, text = text }
    return VO.DataModules:PrepareSound(soundData) and soundData.fileName or nil
end

---------------------------------------------------------------- each text its own line
local VO, Spoken = Boot()
Expect("a player of no profession hears the trainer's own greeting", Lookup(VO, DEFAULT), "default")
Expect("...a herbalist the herbalist's", Lookup(VO, HERBALIST), "herbalist")

world.gossipText = HERBALIST
VO.Addon:GOSSIP_SHOW()
Expect("the window reads the line on screen", Spoken:GetCurrent() and Spoken:GetCurrent().fileName, "herbalist")

---------------------------------------------------------------- a text the NPC has no line for
VO, Spoken = Boot()
local UNKNOWN = "Ah, hello. You look as though you have a question for me."
Expect("a text the packs lack for this NPC finds no line", Lookup(VO, UNKNOWN), nil)
world.gossipText = UNKNOWN
VO.Addon:GOSSIP_SHOW()
Expect("...and nothing is read in its place", Spoken:GetQueueSize(), 0)

-- The Darkmoon Faire's barker names a place by faction. The Horde's line, where only the
-- Alliance's is held, shares most of its words and is still not that line.
local ELWYNN = "When the Darkmoon Faire is open, it will be located in Elwynn Forest.  We'll be pitching our " ..
    "tents just south of Goldshire!"
local MULGORE = "When the Darkmoon Faire opens, it will be located in Mulgore.  We'll be pitching our tents " ..
    "just southwest of Thunder Bluff!"
VO = Boot(nil, { [TRAINER] = { [ELWYNN] = "default" } })
Expect("one faction's line is not read for the other's", Lookup(VO, MULGORE), nil)
Expect("...and its own is", Lookup(VO, ELWYNN), "default")

---------------------------------------------------------------- what the client fills in
VO = Boot()
Expect("the player's name, sex and class are filled into the line",
    Lookup(VO, "Greetings, Valaas. Welcome, my brother.\n\nThe Mage trainers are upstairs."), "named")
Expect("...whatever the spacing and the punctuation",
    Lookup(VO, "Greetings, Valaas!  Welcome, my brother...  The Mage trainers are upstairs"), "named")
Expect("a word reworded since the extract still finds the line",
    Lookup(VO, "I hope that your interruption is for a good cause, I was in the midst of an experiment."), "default")

---------------------------------------------------------------- a client in another language
-- No table in the client's language knows the NPC: the English ones are guessed from, as
-- every non-English client with English packs always has.
VO = Boot("deDE", { [TRAINER] = { [DEFAULT] = "en-guess" } })
Expect("a German client with only English text still hears the NPC's one line",
    Lookup(VO, "Ich hoffe, Ihr stört mich aus gutem Grund."), "en-guess")

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll gossip variant tests passed")
