-- The small window ("minimal" narrator style, UI/MinimalPlayer.lua): its header, words and
-- progress line as the DialogueUI window has them, its background, and the bronze. Run with
-- `make test-player`. How it looks is checked in game.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local Expect, Failures = H.Expecter(stub.print)
local SPOKEN = here .. "/../../addons/Spoken/"

local function Boot(client)
    stub.SetClient(client or "11509"); stub.ResetSound(); stub.ResetTimers(); stub.ResetFrames()
    stub.settingsCategories = {}; stub.ldbObjects = {}; stub.dbIcons = {}
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    local env = stub.LoadSpoken(SPOKEN)
    -- LoadSpoken picks the large window for the other suites.
    env.Addon.db.profile.Frame.Style = "minimal"
    env.Addon:Enable()
    local quests = env.Sources:Register("quests", { title = "Quests", addon = "Spoken_Quests", order = 1 })
    return env, quests
end

local REPORT = { id = "report", icon = "Interface/HelpFrame/HelpIcon-Bug", text = "R", anchor = "topright",
    label = "Report a problem" }
local function Line(label, header, actions)
    return H.Clip({ length = 30, present = { header = header or "Grull", label = label,
        transcript = "The kobolds dig deeper into the mine every night.", portrait = { kind = "none" },
        actions = actions } })
end

---------------------------------------------------------------- its header, as the DialogueUI window's
-- What `fn` reads, or the error reading it: a window without these parts fails each check.
local function Try(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return "error: " .. tostring(value)
end
local env, quests = Boot()
local M, T, L = env.MinimalPlayer, env.Transcript, env.L
quests:Enqueue(Line("One", "Grull", { REPORT }))
quests:Enqueue(Line("Two"))
Expect("the small window shows the line", M.wanted and M.clip ~= nil, true)
Expect("it has the DialogueUI window's round controls, Stop or Replay then Skip", Try(function()
    return M.controls ~= nil and M.play:GetParent() == M.controls and M.skip:GetParent() == M.controls
        and M.skip.bar ~= nil and M.row[1] == M.play and M.row[2] == M.skip end), true)
Expect("...in its header, at the right", Try(function() return M.controls.anchor.point == "RIGHT"
    and M.controls.anchor.relativeTo == M.content and M.controls.anchor.relativePoint == "TOPRIGHT" end), true)
Expect("...Report after Skip, in the header and as large", Try(function()
    local report = M.row[3]
    return report:GetParent() == M.controls and report:GetWidth() == M.play:GetWidth() end), true)
Expect("...the name and the title stopping short of them", Try(function() return M.controls ~= nil
    and M.name.anchor.relativeTo == M.controls and M.title.anchor.relativeTo == M.controls end), true)
Expect("no Stop on the face: the header's is the one", M.pause, nil)
Expect("no fold and no list of the lines waiting", tostring(M.fold) .. " " .. tostring(M.drawer) .. " " .. tostring(M.rows),
    "nil nil nil")
Expect("...nor a queue entry in its menu", M.menuQueue, nil)
Expect("the line's title is a name, nothing to click", M.title:GetObjectType(), "Frame")
Expect("the title counts the lines waiting, after it", Try(function() return M.title.text:GetText() .. "|"
    .. tostring(M.count:IsShown()) .. "|" .. M.count:GetText() end), "One|true|• +1")
Expect("...fading in as the line is added", Try(function() return M.count:GetAlpha() < 1 end), true)
M:Tick(0.3)
Expect("...all the way", Try(function() return M.count:GetAlpha() end), 1)

pcall(function() M.play.scripts.OnClick(M.play) end)
Expect("Stop stops the line, its glyph turning to Replay", Try(function() return tostring(env.SoundQueue:IsPaused())
    .. " " .. tostring(M.play.state) end), "true replay")
Expect("...and the title says it is stopped, after the line's name", Try(function()
    return tostring(M.stopped:IsShown()) .. "|" .. M.stopped:GetText() end), "true|• (" .. L.SUBTITLE_STOPPED .. ")")
Expect("...fading in", Try(function() return M.stopped:GetAlpha() < 1 end), true)
M:Tick(0.3)
Expect("...all the way", Try(function() return M.stopped:GetAlpha() end), 1)
pcall(function() M.play.scripts.OnClick(M.play) end)
M:Tick(0.4)
Expect("Replay plays it again, Stopped fading out", Try(function()
    return tostring(M.play.state) .. " " .. tostring(M.stopped:IsShown()) end), "stop false")

Expect("the words sit under the name and the title", Try(function() return T.frame:GetParent() == M.frame
    and T.frame.anchor.relativeTo == M.content and T.frame.anchor.y <= -(M.name:GetHeight() + M.title:GetHeight()) end), true)
Expect("the progress line is the subtitle's, along the foot of the words", Try(function()
    return M.progress.track:GetParent() == M.content and M.progress.track.anchor.y < T.frame.anchor.y - T.frame:GetHeight() end),
    true)
Expect("...as wide as they are", Try(function() return M.progress.track:GetWidth() end), T.frame:GetWidth())
do
    local tall = M.frame:GetHeight()
    env.Addon.db.profile.Transcript.SubtitleProgress = false
    env.PlayerFrame:RefreshConfig()
    Expect("Show Progress off, the line goes and the window closes up, as on the DialogueUI window", Try(function()
        return tostring(M.progress.track:IsShown()) .. " " .. tostring(M.frame:GetHeight() < tall) end), "false true")
    env.Addon.db.profile.Transcript.SubtitleProgress = true
    env.PlayerFrame:RefreshConfig()
end

local first = env.SoundQueue:GetCurrentSound()
pcall(function() M.skip.scripts.OnClick(M.skip) end)
Expect("Skip goes on to the next line", env.SoundQueue:GetCurrentSound() ~= nil and env.SoundQueue:GetCurrentSound() ~= first, true)
Expect("...the count gone with no line waiting", Try(function() return M.count:IsShown() end), false)
env.SoundQueue:RemoveAllSoundsFromQueue()
quests:Enqueue(Line("Grull", "Grull"))
Expect("a name the same as the line's is said once", M.name:GetText() .. "|" .. M.title.text:GetText(), "|Grull")
env.SoundQueue:RemoveAllSoundsFromQueue()

if Failures() > 0 then stub.print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
stub.print("\nAll small window tests passed")
