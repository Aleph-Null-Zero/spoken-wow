--[[
This addon runs in the dialogue core's environment, the VoiceOver table Spoken creates in
Dialogue/Environment.lua: the voice packs, languages and sound events it reads lines with are
there, shared with the gossip module. Its own files add to that table.

Without the core (another addon's VoiceOver table in its place) the addon loads nothing: every
file starts with

    if not (VoiceOver and VoiceOver.SpokenDialogue) then return end

before its setfenv(1, VoiceOver).
]]
local _G = getfenv(0)
local core = rawget(_G, "VoiceOver")
if not (core and rawget(core, "SpokenDialogue")) then
    return
end

core.AddonFolder = "Spoken_Quests"
-- What /spq diagnostics prints. A literal because this file loads before the addon has any
-- metadata API; scripts/package.sh refuses to build when it disagrees with the .toc.
core.AddonVersion = "3.4.0"
