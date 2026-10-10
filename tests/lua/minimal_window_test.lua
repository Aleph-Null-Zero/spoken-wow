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

---------------------------------------------------------------- its background
-- What each part was last painted: the stub keeps no colours of its own.
local function Colour(r, g, b) return string.format("%.2f %.2f %.2f", r, g, b) end
local function Record(widget)
    widget.SetTextColor = function(self, r, g, b) self.colour = Colour(r, g, b) end
    widget.SetVertexColor = function(self, r, g, b) self.colour = Colour(r, g, b) end
    widget.SetAtlas = function(self, atlas) self.atlas, self.texture, self.colour = atlas, nil, nil end
    widget.SetTexture = function(self, texture) self.texture, self.atlas, self.colour = texture, nil, nil end
    widget.SetColorTexture = function(self, r, g, b) self.colour, self.atlas, self.texture = Colour(r, g, b), nil, nil end
    return widget
end
local INK, RED = "0.19 0.17 0.13", "|cff9c1a1a"
env, quests = Boot()
M, T, L = env.MinimalPlayer, env.Transcript, env.L
local frame = env.Addon.db.profile.Frame
Expect("the small window is on parchment unless the player chooses otherwise", frame.MinimalBackground, "parchment")
for _, part in ipairs({ M.paper, M.name, M.title.text, M.count, M.ring }) do Record(part) end
quests:Enqueue(Line("One", "Grull"))
env.PlayerFrame:RefreshConfig()
Expect("...drawn in the parchment's colour where the client has none of its art", tostring(M.paper.atlas) .. " " .. tostring(M.paper.colour),
    "nil 0.88 0.68 0.41")
Expect("...the name and the title in the DialogueUI window's parchment ink", tostring(M.name.colour) .. "|"
    .. tostring(M.title.text.colour), INK .. "|" .. INK)
Expect("...the words too, unshadowed, the word being read in its red", tostring(T.style and Colour(T.style.color[1], T.style.color[2],
    T.style.color[3])) .. " " .. tostring(T.style and T.style.shadow) .. " " .. tostring(T.style and T.style.highlight),
    INK .. " false " .. RED)
frame.MinimalBackground = "dark"
env.PlayerFrame:RefreshConfig()
Expect("Dark is the rock it always had", M.paper.texture, [[Interface\AddOns\Spoken\Textures\MinimalBackground]])
Expect("...with the gold name and the light words", tostring(M.name.colour) .. "|" .. tostring(M.title.text.colour) .. "|"
    .. tostring(T.style),
    "1.00 0.82 0.00|0.88 0.84 0.76|nil")
frame.MinimalBackground = "parchment"

-- The parchment art, where the client has it: tiled atlases both clients list.
local PARCHMENTS = M.PARCHMENTS or { "none", "none", "none", "none" }
local atlases = {}
for _, name in ipairs(PARCHMENTS) do atlases[name] = true end
_G.C_Texture = { GetAtlasInfo = function(name) return atlases[name] and { width = 256, height = 256 } or nil end }
env.PlayerFrame:RefreshConfig()
Expect("with the art, the first parchment is the default", M.paper.atlas, PARCHMENTS[1])
local said = {}
local hadPrint = _G.print
_G.print = function(text) table.insert(said, text) end
SlashCmdList.SPOKEN("parchment")
Expect("/spoken parchment draws the next one", M.paper.atlas, PARCHMENTS[2])
Expect("...and names it", said[1], string.format("Spoken: small window parchment 2/%d: %s", #PARCHMENTS, PARCHMENTS[2]))
atlases[PARCHMENTS[3]] = nil
SlashCmdList.SPOKEN("parchment")
Expect("...passing over one the client has not got", M.paper.atlas, PARCHMENTS[4])
SlashCmdList.SPOKEN("parchment")
Expect("...and round to the first again", M.paper.atlas, PARCHMENTS[1])
said = {}
SlashCmdList.SPOKEN("help me")
Expect("the command is in /spoken's help", said[1] ~= nil and string.find(said[1], "| parchment", 1, true) ~= nil, true)
_G.print = hadPrint
_G.C_Texture = nil
env.SoundQueue:RemoveAllSoundsFromQueue()

-- The setting, on Spoken's page, for the small window only.
env.Options:UpdateRows()
local main = _G.SpokenOptionsPanel.layout
local function Row(label)
    for _, entry in ipairs(main.entries) do if entry.label == label then return entry.frame end end
end
main:Refresh()
local row = Row(L.OPT_MINIMAL_BACKGROUND)
Expect("Background is on Spoken's page with the small window chosen", row ~= nil and row:IsShown(), true)
Expect("...offering Parchment and Dark", row and row.layoutValues and table.concat(row.layoutValues, ","), "parchment,dark")
pcall(function() row.layoutChoose("dark") end)
Expect("...choosing Dark there draws the rock", tostring(frame.MinimalBackground) .. " " .. tostring(M.paper.texture),
    [[dark Interface\AddOns\Spoken\Textures\MinimalBackground]])
pcall(function() row.layoutChoose("parchment") end)
env.Addon:SetPlayerStyle("classic")
main:Refresh()
Expect("...and not with another style", row ~= nil and row:IsShown(), false)
env.Addon:SetPlayerStyle("minimal")
main:Refresh()
Expect("Show Progress is offered for the small window, which has the progress line",
    Row(L.OPT_SUBTITLE_PROGRESS) ~= nil and Row(L.OPT_SUBTITLE_PROGRESS):IsShown(), true)

if Failures() > 0 then stub.print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
stub.print("\nAll small window tests passed")
