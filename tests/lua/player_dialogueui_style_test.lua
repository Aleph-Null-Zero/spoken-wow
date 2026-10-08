-- The DialogueUI narrator style (UI/DialogueUITheme.lua, UI/DialogueUIPlayer.lua), with and
-- without a fake DialogueUI. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local SPOKEN = here .. "/../../addons/Spoken/"
local Expect, Failures = H.Expecter(print)

local GOLD, RED = "|cffffd100", "|cff9c1a1a"
local BROWN, DARK = "Interface/AddOns/DialogueUI/Art/Theme_Brown/", "Interface/AddOns/DialogueUI/Art/Theme_Dark/"

---------------------------------------------------------------- a fake DialogueUI
local loaded = false
_G.IsAddOnLoaded = function(name) return name == "DialogueUI" and loaded end
local function FakeDialogueUI()
    _G.DialogueUI_DB = { Theme = 1, FrameSize = 2 }
    local frame = stub.Widget("Frame")
    -- DialogueUI's window at its default size on a 1080p screen, drawn at 0.8 scale.
    frame.frameWidth, frame.frameHeight = 624, 734
    frame.GetEffectiveScale = function() return 0.8 end
    local cap = stub.Widget("Texture")
    function cap:GetSize() return 601, 150 end
    frame.Parchments = { cap }
    function frame:LoadTheme() end
    function frame:UpdateFrameSize() end
    -- Closed until a dialog opens.
    frame:Hide()
    _G.DUIQuestFrame = frame
    local font = stub.Widget("Font")
    function font:GetFont() return "Interface/AddOns/DialogueUI/Fonts/frizqt__.ttf", 14 end
    _G.DUIFont_Quest_Paragraph = font
    return frame
end

local function Boot(client)
    stub.SetClient(client or "16001"); stub.ResetSound(); stub.ResetTimers(); stub.ResetFrames()
    stub.settingsCategories = {}; stub.ldbObjects = {}; stub.dbIcons = {}
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    -- A screen, for the window to take DialogueUI's share of; the stub's is a thumbnail.
    _G.UIParent:SetSize(1920, 1080)
    local env = stub.LoadSpoken(SPOKEN)
    -- LoadSpoken picks the large window for the other suites; these start from the small one.
    env.Addon.db.profile.Frame.Style = "minimal"
    env.Addon:Enable()
    local quests = env.Sources:Register("quests", { title = "Quests", addon = "Spoken_Quests", order = 1 })
    return env, quests
end

-- By label and tooltip: the DialogueUI window's Window Size and Text Size share their labels
-- with the other windows' rows they stand in for.
local function Row(layout, label, tooltip)
    for _, entry in ipairs(layout.entries) do
        if entry.label == label and (not tooltip or entry.tooltip == tooltip) then return entry.frame end
    end
end

---------------------------------------------------------------- without DialogueUI
local env = Boot()
local Spoken = _G.Spoken
Expect("the small window is the default window", Spoken:GetPlayerStyle(), "minimal")
Expect("no DialogueUI tile without DialogueUI", table.concat(env.Options:Styles(), ","), "subtitle,minimal,classic,none")
SlashCmdList.SPOKEN("player dialogueui")
Expect("the slash command says why it cannot switch", env.Addon.db.profile.Frame.Style, "minimal")
env.Addon.db.profile.Frame.Style = "dialogueui"
env.PlayerFrame:RefreshConfig()
Expect("a DialogueUI window chosen falls back to the small one", Spoken:GetPlayerStyle(), "minimal")
Expect("...the choice is kept, for DialogueUI coming back", env.Addon.db.profile.Frame.Style, "dialogueui")
Expect("...and the player frame is the small one", Spoken:GetPlayerFrame(), env.MinimalPlayer.frame)
Expect("...with the reason to hand", env.DialogueUITheme:Problem(), env.L.OPT_STYLE_DUI_MISSING)
Expect("no DialogueUI window is built for it", env.DialogueUIPlayer.frame, nil)

env = Boot("1.12")
Expect("the legacy client has the large window and nothing else", Spoken:GetPlayerStyle(), "classic")
Expect("...and no DialogueUI reading", env.DialogueUITheme:Available(), false)

---------------------------------------------------------------- the window, with DialogueUI
loaded = true
local DUI = FakeDialogueUI()
local quests
env, quests = Boot()
Spoken = _G.Spoken
Expect("with DialogueUI it is a fifth tile, after the large window",
    table.concat(env.Options:Styles(), ","), "subtitle,minimal,classic,dialogueui,none")
Expect("...named, described and drawn", env.Options.STYLE_LABELS.dialogueui ~= nil and env.Options.STYLE_TEXTS.dialogueui ~= nil
    and env.Options.STYLE_TIPS.dialogueui ~= nil and env.Options.SKETCHES.dialogueui ~= nil, true)
SlashCmdList.SPOKEN("player dialogueui")
local Skin, T = env.DialogueUIPlayer, env.Transcript
Expect("/spoken player dialogueui draws it", Spoken:GetPlayerStyle(), "dialogueui")
Expect("...remembered as the style chosen", env.Addon.db.profile.Frame.Style, "dialogueui")
Expect("...on its own frame", Spoken:GetPlayerFrame(), _G.SpokenDialogueUIPlayerFrame)
Expect("it opens folded to Lines Shown, as the other windows' words do", Skin.lines, 2)
Skin:SetExpanded(true)
Expect("...and opened, the other windows' words are opened too", env.Addon:Layout().CaptionsExpanded, true)
Expect("the window is laid out as DialogueUI's", Skin.frame:GetWidth(), 624)
Expect("...in height too", Skin.frame:GetHeight(), 734)
-- DialogueUI's window has no parent and is drawn at 0.8 here; UIParent at 1. At the default
-- Window Size the window is 0.65 of that, 0.52: the whole window scaled.
Expect("...and its size scales the whole of it", math.abs(Skin.frame.scale - 0.52) < 1e-6, true)
Expect("the parchment is DialogueUI's own", Skin.parchments[2].texture, BROWN .. "Parchment.png")
Expect("...its top cap at the top of the image", table.concat(Skin.parchments[1].texCoord, ","), "0,1,0,0.125")
Expect("...its bottom cap where DialogueUI cuts it", table.concat(Skin.parchments[3].texCoord, ","), "0,1,0.4375,0.5625")
Expect("...sized as DialogueUI's", Skin.parchments[1].width, 601)
Expect("the words are DialogueUI's text size", T.style.size, 14)
Expect("...with its line spacing", T.style.lineGap, 5)
Expect("...and its paragraphs set apart", T.style.paragraphs, true)
T:SetClip({ text = "First paragraph.\nSecond one." })
Expect("an empty line separates two paragraphs", #T.lines == 3 and #T.lines[2] == 0, true)
T:SetClip(nil)
Expect("the words are docked in the window, over the paper with the rest of its contents",
    T.frame:GetParent(), Skin.content)
Expect("...filling its body", Skin.lines > 8, true)
Expect("...with labels enough for them and the line sliding in", #T.labels >= Skin.lines + 1, true)
Expect("...in DialogueUI's font", T.style.font, "Interface/AddOns/DialogueUI/Fonts/frizqt__.ttf")
Expect("...and the parchment's red highlight", T.style.highlight, RED)
Expect("the expand button has no place on a fixed page", T.expand:IsShown(), false)

env.Options:UpdateRows()
local main, Page = _G.SpokenOptionsPanel.layout, env.DialogueUIOptions
main:Refresh()
local function Shown(layout, label, tooltip) local row = Row(layout, label, tooltip); return row ~= nil and row:IsShown() end
Expect("Spoken's page points to the DialogueUI page", Shown(main, env.L.OPT_DUI_OPEN_PAGE), true)
Expect("the DialogueUI page waits for the world to be up", Page.page, nil)
stub.FireEvent("PLAYER_ENTERING_WORLD"); stub.Advance(0.1)
Expect("...then is listed after every part's page", Page.page and Page.page.order, 1000)
Expect("...under DialogueUI's name", Page.page and Page.page.name, env.L.OPT_STYLE_DIALOGUEUI)
Expect("the window's size is the player's Window Size", Shown(main, env.L.OPT_SCALE, env.L.OPT_SCALE_TIP), true)
Expect("...its words' size and lines theirs", Shown(main, env.L.TRANSCRIPT_SIZE, env.L.TRANSCRIPT_SIZE_TIP)
    and Shown(main, env.L.TRANSCRIPT_LINES), true)
Expect("...and how the words scroll too", Shown(main, env.L.TRANSCRIPT_SCROLL), true)
local page = Page.layout
page:Refresh()
local function Live(label, tooltip) local row = Row(page, label, tooltip); return row ~= nil and row.layoutReason == nil end
Expect("the page has the window's theme", Live(env.L.OPT_DUI_FOLLOW_THEME), true)
Expect("...and Fit to the Words", Live(env.L.OPT_DUI_FIT_TEXT), true)
Expect("...but nothing Spoken's page has already", Row(page, env.L.OPT_SCALE) == nil
    and Row(page, env.L.TRANSCRIPT_SIZE) == nil and Row(page, env.L.TRANSCRIPT_LINES) == nil, true)
Expect("the theme waits on not following DialogueUI's", Row(page, env.L.OPT_DUI_THEME).layoutReason, env.L.REASON_DUI_FOLLOW)
env.Addon:SetPlayerStyle("minimal")
page:Refresh()
Expect("with another style chosen they wait on this one, saying where to choose it",
    Row(page, env.L.OPT_DUI_FIT_TEXT).layoutReason, env.L.REASON_DUI_STYLE)
env.Addon:SetPlayerStyle("dialogueui")
env.Addon.db.profile.Frame.DialogueUI.FitText = false
Page:Reset()
Expect("the page's Defaults puts the window's settings back", env.Addon.db.profile.Frame.DialogueUI.FitText, true)

---------------------------------------------------------------- folded or open
Skin:SetExpanded(false)
Expect("folded, the window keeps two lines", Skin.lines, 2)
Expect("...and shrinks to them", Skin.frame:GetHeight() < 734, true)
Expect("...the other windows' words folded with it", env.Addon:Layout().CaptionsExpanded, false)
Skin:SetExpanded(true)
Expect("...and opens back up", Skin.lines > 8, true)
T:ToggleExpanded(); env.PlayerFrame:RefreshConfig()
Expect("the other windows' expand button folds it too", Skin.lines, 2)
T:ToggleExpanded(); env.PlayerFrame:RefreshConfig()
Expect("...and opens it", Skin.lines > 8, true)

local saved = env.Addon:Layout()
saved.DialogueUIHeight = 900
env.PlayerFrame:RefreshConfig()
Expect("a dragged height is kept", Skin.frame:GetHeight(), 900)
Expect("...and the words fill it", Skin.lines > 8, true)
Expect("...with labels enough for them", #T.labels >= Skin.lines, true)
saved.DialogueUIHeight = nil
saved.DialogueUIWidth = 700
env.PlayerFrame:RefreshConfig()
Expect("a width dragged with Shift is kept", Skin.frame:GetWidth(), 700)
local faceAtDefault = Skin.portrait.width
Expect("...the paper stretching with it", math.abs(Skin.parchments[1].width - 601 * 700 / 624) < 0.01, true)
local socketAtDefault = Skin.headerSocket.width
Expect("...and the header line", Skin.headerDivider.width + Skin.headerSocket.width > 600, true)
saved.DialogueUIWidth = 100
env.PlayerFrame:RefreshConfig()
Expect("...but never narrower than the header can hold", Skin.frame:GetWidth(), math.floor(624 * 0.6 + 0.5))
Expect("the face keeps its size whatever the width", Skin.portrait.width, faceAtDefault)
Expect("...and so does the socket it sits in", Skin.headerSocket.width, socketAtDefault)
saved.DialogueUIWidth = nil
env.PlayerFrame:RefreshConfig()

---------------------------------------------------------------- where it opens
local function Near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 1 end
-- The screen's top left, 16 from the paper's visible edge: the caps reach past the frame's top
-- and sides, the paper inside their transparent margin (122 of the cap's 256 rows, 125 of 1024
-- columns).
local function AtTopLeft()
    local anchor, base, cap = Skin.frame.anchor, Skin.frame.spokenBaseScale, Skin.parchments[1]
    local x = 16 / base + math.max(0, (cap.width - Skin.frame:GetWidth()) / 2 - 125 / 1024 * cap.width)
    local y = 16 / base + math.max(0, cap.height * (0.5 - 122 / 256))
    return anchor ~= nil and anchor.point == "TOPLEFT" and anchor.relativePoint == "TOPLEFT"
        and Near(anchor.x, x) and Near(anchor.y, -y)
end
saved.DialogueUI = nil
DUI.frameOffsetX = 480
env.PlayerFrame:RefreshConfig()
Expect("never dragged, it opens at the screen's top left, out of the next dialog's way", AtTopLeft(), true)
DUI.frameOffsetX = -480
env.PlayerFrame:RefreshConfig()
Expect("...wherever DialogueUI puts its own window", AtTopLeft(), true)
local hadCtrl = _G.IsControlKeyDown
_G.IsControlKeyDown = function() return true end
Skin:Wheel(1)
_G.IsControlKeyDown = hadCtrl
Expect("...still there at another size", env.Addon.db.profile.Frame.FrameScale > 0.7
    and AtTopLeft(), true)
Expect("...the size not taken for a move", saved.DialogueUI, nil)
env.Addon.db.profile.Frame.FrameScale = 0.7
env.PlayerFrame:RefreshConfig()
Skin:StopDrag()
Expect("dragged, its place is kept", saved.DialogueUI ~= nil, true)
local dragged = Skin.frame.anchor
DUI.frameOffsetX = 480
env.PlayerFrame:RefreshConfig()
Expect("...and no longer follows DialogueUI's", Skin.frame.anchor, dragged)
env.PlayerFrame:Reset()
Expect("reset, it goes back to the screen's top left", saved.DialogueUI == nil and AtTopLeft(), true)

---------------------------------------------------------------- as tall as the words need
local panel, transcript = env.Addon.db.profile.Frame.DialogueUI, env.Addon.db.profile.Transcript
Expect("Fit to the Words is on by default", panel.FitText, true)
local function Play(text)
    Spoken:StopAll()
    quests:Enqueue(H.Clip({ length = 30, present = { header = "Marshal McBride", label = "Kobold Camp Cleanup",
        transcript = text, portrait = { kind = "none" } } }))
    env.PlayerFrame:RefreshConfig()
end
local long = string.rep("The kobolds dig deeper into the mine every night. ", 60)
Play(long)
Expect("the window shows the line the captions hold", T.clip ~= nil and T.clip == Skin.clip, true)
local ceiling = Skin.lines
Expect("a long line fills the window to its size", ceiling > 8, true)
Play("Go north.")
Expect("a short one takes only the lines it needs", Skin.lines, 2)
Expect("...the window shorter for it", Skin.frame:GetHeight() < 734, true)
panel.FitText = false
env.PlayerFrame:RefreshConfig()
Expect("with Fit to the Words off, it keeps its full size", Skin.lines, ceiling)
panel.FitText = true
saved.DialogueUIHeight = 900
env.PlayerFrame:RefreshConfig()
Expect("a dragged height is the most it grows to, not its size", Skin.lines, 2)
saved.DialogueUIHeight = nil
Play(long)
Skin:SetExpanded(false)
Expect("folded, it shows two lines", Skin.lines, 2)
transcript.Lines = 1
env.PlayerFrame:RefreshConfig()
Expect("...or one, as the player's Lines Shown says", Skin.lines, 1)
transcript.Lines = 2
Play("Go north.")
Expect("...and no more than the words need", Skin.lines, 1)
Skin:SetExpanded(true)
panel.FitText = false
Page:Reset()
Expect("the page's Defaults puts Fit to the Words back", panel.FitText, true)
local function Says(text)
    for _, line in ipairs(_G.GameTooltip.lines or {}) do
        if line == text then return true end
    end
    return false
end
Skin.resizer.scripts.OnEnter(Skin.resizer)
Expect("the resize handle's tooltip names the wheel's shortcuts", Says(env.L.DUI_WHEEL_HINT), true)
local noted = false
local function Look(row)
    for _, region in ipairs(row.regions or {}) do
        if region.text == env.L.DUI_WHEEL_HINT then noted = true end
    end
end
for _, item in ipairs(page.items or {}) do
    Look(item)
    for _, row in ipairs(item.rows or {}) do Look(row) end
end
Expect("...and the DialogueUI page says them too", noted, true)
Spoken:StopAll()
env.PlayerFrame:RefreshConfig()

---------------------------------------------------------------- what it shows
env.Options:Preview("dialogueui")
Expect("previewing the tile shows the window with a sample line", Skin.wanted, true)
Expect("...its speaker", Skin.name:GetText(), env.L.SAMPLE_SPEAKER)
env.Options:Preview(nil)
Expect("...and puts it away", Skin.wanted, false)

local clip = H.Clip({ present = { header = "Eagan Peltskinner", label = "Wolves Across the Border",
    bullet = "quest-accept", portrait = { kind = "none" } } })
quests:Enqueue(clip)
Expect("a queued line shows the window", Skin.wanted, true)
Expect("...naming the speaker", Skin.name:GetText(), "Eagan Peltskinner")
Expect("...and the line", Skin.title.text:GetText(), "Wolves Across the Border")
quests:Enqueue(H.Clip({ present = { header = "Eagan", label = "Second", portrait = { kind = "none" } } }))
Expect("a waiting line gets a row", Skin.rows[1] and Skin.rows[1]:IsShown(), true)
Expect("...reading its label", Skin.rows[1].text:GetText(), "Second")
Spoken:StopAll()

-- A book page and a zone's lore, queued as Spoken_Books and Spoken_Zones queue them.
local books = env.Sources:Register("books", { title = "Books", addon = "Spoken_Books", order = 3 })
books:Enqueue({ key = "b:1", path = "b1.mp3", length = 6, present = { header = "A Letter Home", transcript = "Dear mother, the war goes well.",
    bullet = "book", portrait = { kind = "texture", texture = [[Interface\AddOns\Spoken\Textures\Book]] } } })
Expect("a book page shows the window", Skin.wanted, true)
Expect("...titled by the book", Skin.name:GetText(), "A Letter Home")
Expect("...and named by its key when it has no page label", Skin.title.text:GetText(), "b:1")
Expect("...the book for a face", Skin.viewport.active, "texture")
Expect("...badged as a book, as the subtitle badges it", tostring(Skin.badge:IsShown()) .. " " .. tostring(Skin.badge.texture),
    "true " .. tostring(env.MinimalPlayer.BADGES.book))
Expect("...with its words in the window", T.text, "Dear mother, the war goes well.")
Spoken:StopAll()
local zones = env.Sources:Register("zones", { title = "Zones", addon = "Spoken_Zones", order = 2 })
zones:Enqueue({ key = "z:12", path = "z12.ogg", length = 20, present = { header = "Elwynn Forest", label = "Goldshire",
    bullet = "zone", portrait = { kind = "texture", texture = [[Interface\AddOns\Spoken\Textures\Book]] } } })
Expect("a zone's lore shows it too", Skin.name:GetText() .. "/" .. Skin.title.text:GetText(), "Elwynn Forest/Goldshire")
Expect("...even with no words to show", T.frame:IsShown(), false)
Spoken:StopAll()

---------------------------------------------------------------- DialogueUI's theme and size
_G.DialogueUI_DB.Theme = 2
DUI:LoadTheme()
Expect("DialogueUI switching to dark switches the window", Skin.parchments[2].texture, DARK .. "Parchment.png")
Expect("...and the highlight to gold", T.style.highlight, GOLD)
_G.DialogueUI_DB.Theme = 1
DUI:LoadTheme()
local dui = env.Addon.db.profile.Frame.DialogueUI
dui.FollowTheme, dui.Theme = false, 2
env.PlayerFrame:RefreshConfig()
Expect("not following, the chosen theme wins over DialogueUI's", Skin.parchments[2].texture, DARK .. "Parchment.png")
dui.FollowTheme = true

DUI.frameWidth, DUI.frameHeight = 600, 700
DUI:UpdateFrameSize()
Expect("DialogueUI resizing resizes the window", Skin.frame:GetWidth(), 600)
local frameCfg, words = env.Addon.db.profile.Frame, env.Addon.db.profile.Transcript
frameCfg.FrameScale = 0.35
env.PlayerFrame:RefreshConfig()
Expect("half the Window Size scales it down by half", math.abs(Skin.frame.scale - 0.65 * 0.5 * 0.8) < 1e-6, true)
Expect("...keeping DialogueUI's layout inside", Skin.frame:GetWidth(), 600)
frameCfg.FrameScale = 0.7
env.PlayerFrame:RefreshConfig()
words.FontSize = 26
env.PlayerFrame:RefreshConfig()
-- DialogueUI's 14 at the default Text Size of 16; at 26, 14 * 26 / 16.
Expect("Text Size sets the words against DialogueUI's", T.style.size, 23)
Expect("...their spacing following", T.style.lineGap, 8)
Expect("...the window keeping its scale", math.abs(Skin.frame.scale - 0.52) < 1e-6, true)
words.FontSize = 16
env.PlayerFrame:RefreshConfig()
Expect("at the default Text Size the words are DialogueUI's size", T.style.size, 14)

local ctrl, shift = false, false
_G.IsControlKeyDown = function() return ctrl end
_G.IsShiftKeyDown = function() return shift end
T.top = 1
T.frame:GetScript("OnMouseWheel")(T.frame, -1)
Expect("the wheel alone still scrolls the words", T.manualScroll, true)
Expect("...the size untouched", frameCfg.FrameScale, 0.7)
-- Dragged first, so the corner stays where the player left it rather than following DialogueUI.
Skin:StopDrag()
ctrl = true
T.frame:GetScript("OnMouseWheel")(T.frame, 1)
Expect("Ctrl and the wheel over the words grow Window Size", math.abs(frameCfg.FrameScale - 0.75) < 1e-9, true)
local grown = 0.65 * 0.75 / 0.7 * 0.8
Expect("...drawing it larger", math.abs(Skin.frame.scale - grown) < 1e-6, true)
Expect("...its corner kept where it was", math.abs(Skin.frame.anchor.y - 100 * 0.52 / grown) < 1e-6, true)
Expect("...and saying so", _G.GameTooltip.text, env.L.OPT_SCALE .. ": 75%")
frameCfg.FrameScale = 2
Skin.frame:GetScript("OnMouseWheel")(Skin.frame, 1)
Expect("...no further than the slider goes", frameCfg.FrameScale, 2)
frameCfg.FrameScale = 0.7
env.PlayerFrame:RefreshConfig()
shift = true
Skin.frame:GetScript("OnMouseWheel")(Skin.frame, 1)
Expect("Ctrl, Shift and the wheel grow Text Size", words.FontSize, 17)
Expect("...the window left alone", frameCfg.FrameScale, 0.7)
Expect("...and the words set larger", T.style.size, 15)
Expect("...saying so", _G.GameTooltip.text, env.L.TRANSCRIPT_SIZE .. ": 17")
ctrl, shift = false, false
words.FontSize = 16
env.PlayerFrame:RefreshConfig()

---------------------------------------------------------------- over DialogueUI's window
Spoken:SetPlayerHost(DUI)
Expect("hosted over DialogueUI the window moves onto it", Skin.frame:GetParent(), DUI)
Expect("...at its share of the window it sits on", math.abs(Skin.frame.scale - 0.65) < 1e-6, true)
local moving = false
Skin.frame.StartMoving = function() moving = true end
Skin:StartDrag()
Expect("...and can still be dragged there", moving, true)
Skin.frame.StartMoving = nil
Skin:StopDrag()
local placed = env.Addon:Layout().DialogueUI
Expect("...its place saved", placed ~= nil, true)
Spoken:SetPlayerHost(nil)
Expect("...and comes back", Skin.frame:GetParent(), _G.UIParent)
env.PlayerFrame:RefreshConfig()
Expect("...to the place saved over the window", placed ~= nil and math.abs(Skin.frame:GetLeft() - placed.left) < 1e-6
    and math.abs(Skin.frame:GetTop() - placed.top) < 1e-6, true)
Expect("...at its own scale", math.abs(Skin.frame.scale - 0.52) < 1e-6, true)

---------------------------------------------------------------- its controls, the subtitle's
Spoken:StopAll()
-- Offering Report in the corner, as Quests' lines do.
local REPORT = { id = "report", icon = "Interface/HelpFrame/HelpIcon-Bug", text = "R", anchor = "topright" }
quests:Enqueue(H.Clip({ length = 30, present = { header = "Grull", label = "One", portrait = { kind = "none" },
    actions = { REPORT } } }))
quests:Enqueue(H.Clip({ length = 30, present = { header = "Grull", label = "Two", portrait = { kind = "none" } } }))
Expect("it has the subtitle's round controls, Stop or Replay then Skip, and no Stop All",
    #Skin.buttons == 2 and Skin.buttons[1] == Skin.play and Skin.buttons[2] == Skin.skip and Skin.stop == nil, true)
Expect("...Skip in the subtitle's art", Skin.skip.bar ~= nil, true)
Expect("...in the header at the right, beside the speaker and the line",
    Skin.controls.anchor.point == "RIGHT" and Skin.controls.anchor.relativeTo == Skin.content
    and Skin.controls.anchor.relativePoint == "TOPRIGHT" and Skin.controls.anchor.y < 0, true)
Expect("...the line's title stopping short of them", Skin.title.anchor.relativeTo == Skin.controls, true)
local report = Skin.row[3]
Expect("...Report after Skip, as large", report ~= nil and report:GetParent() == Skin.controls
    and report:GetWidth() == Skin.play:GetWidth(), true)
Expect("...and no fold or close button", Skin.fold == nil and Skin.close == nil, true)
Expect("...nor a second Stop on the face: the header's is the one, as the subtitle has one", Skin.pause, nil)
Expect("the line's title is a name, nothing to click: Skip takes a line away",
    Skin.title:GetObjectType() .. " " .. tostring(Skin.title.scripts.OnClick) .. " " .. tostring(Skin.title.scripts.OnEnter),
    "Frame nil nil")
env.Addon.db.profile.Frame.HidePortrait = true
Skin:ConfigurePortrait()
Expect("Hide Portrait leaves its face: the header's socket would stand empty", Skin.portrait:IsShown(), true)
env.Addon.db.profile.Frame.HidePortrait = false
Expect("the title counts the lines waiting, as the subtitle does",
    string.find(Skin.title.text:GetText(), "One  |c", 1, true) == 1 and string.find(Skin.title.text:GetText(), "• +1|r", 1, true) ~= nil, true)
Skin:SetExpanded(false)
Expect("folded, the lines waiting get no rows", Skin.drawer:IsShown(), false)
Skin:SetExpanded(true)
Expect("...open, they do", Skin.drawer:IsShown(), true)
Expect("its progress line is the subtitle's, with no strip under it",
    Skin.progress ~= nil and Skin.progress.track:GetParent() == Skin.content and Skin.footerDivider == nil, true)
Skin.play.scripts.OnClick(Skin.play)
Expect("Stop stops the line, its glyph turning to Replay", tostring(env.SoundQueue:IsPaused()) .. " " .. tostring(Skin.play.state),
    "true replay")
Expect("...and the title says it is stopped, after the line's name, as the subtitle does",
    string.find(Skin.title.text:GetText(), "One  |c", 1, true) == 1
    and string.find(Skin.title.text:GetText(), "(" .. env.L.SUBTITLE_STOPPED .. ")|r", 1, true) ~= nil, true)
Skin.play.scripts.OnClick(Skin.play)
Expect("...and Replay plays it again", Skin.play.state, "stop")
local first = Spoken:GetCurrent()
Skin.skip.scripts.OnClick(Skin.skip)
Expect("Skip goes on to the next line", Spoken:GetCurrent() ~= nil and Spoken:GetCurrent() ~= first, true)
Expect("...the count gone with no line waiting", string.find(Skin.title.text:GetText(), "+", 1, true), nil)
-- The client fades each texture on its own: the paper and what is on it fade one after the other.
Expect("it is not a frame buffer, which crashed the client", Skin.frame:IsFrameBuffer(), false)
Skin:Tick(1) -- shown in full first
Skin:SetVisible(false)
Skin:Tick(0.16)
Expect("fading out, what is on the paper goes first", Skin.frame:GetAlpha() .. " " .. Skin.content:GetAlpha(), "1 0")
Skin:Tick(0.2)
Expect("...then the paper", Skin.frame:GetAlpha() .. " " .. tostring(Skin.frame:IsShown()), "0 false")
Skin:SetVisible(true)
Skin:Tick(0.14)
Expect("fading in, the paper comes first", Skin.frame:GetAlpha() .. " " .. Skin.content:GetAlpha(), "1 0")
Skin:Tick(0.2)
Expect("...then what is on it", Skin.content:GetAlpha(), 1)
Spoken:StopAll()

---------------------------------------------------------------- locked
Skin.frame.SetMouseClickEnabled = function(f, v) f.clicks = v end
Skin.frame.SetMouseMotionEnabled = function(f, v) f.motion = v end
env.Addon.db.profile.Frame.LockFrame = true
env.PlayerFrame:RefreshConfig()
Expect("locked, clicks on the window pass through to the game, as on the subtitle; the pointer still counts",
    tostring(Skin.frame.clicks) .. " " .. tostring(Skin.frame.motion), "false true")
env.Addon.db.profile.Frame.LockFrame = false
env.PlayerFrame:RefreshConfig()
Expect("...unlocked, they are the window's again", Skin.frame.clicks, true)

---------------------------------------------------------------- a place's picture
quests:Enqueue(H.Clip({ length = 30, present = { header = "Kalimdor", label = "Mulgore", portrait = { kind = "none" } } }))
Skin:Update()
local plainTop = T.frame.anchor.y
Expect("a line with no picture shows none", Skin.picture:IsShown(), false)
Expect("a name over it unlike the line's own is shown", Skin.name:GetText(), "Kalimdor")
Spoken:StopAll()
quests:Enqueue(H.Clip({ length = 30, present = { header = "Kalimdor", label = "Mulgore", portrait = { kind = "none" },
    picture = { file = "Interface/Pictures/1412-mulgore", mask = "Interface/Pictures/Mask7" } } }))
Skin:Update()
Expect("a place's picture shows over its words, as Place Lore shows it", Skin.picture:IsShown()
    and Skin.picture.texture == "Interface/Pictures/1412-mulgore", true)
Expect("...2:1, as wide as the words up to 400", Skin.picture:GetWidth() .. "x" .. Skin.picture:GetHeight(), "400x200")
Expect("...the words under it, 10 below", plainTop - T.frame.anchor.y, 210)
Spoken:StopAll()
quests:Enqueue(H.Clip({ length = 30, present = { header = "Mulgore", label = "Mulgore", portrait = { kind = "none" } } }))
Skin:Update()
Expect("a name the same as the line's own is said once, in the title", Skin.name:GetText() .. "|" .. Skin.title.text:GetText(), "|Mulgore")
Spoken:StopAll()

---------------------------------------------------------------- a line held back
-- Game Greeting First holds a gossip line until the NPC's own greeting ends.
local holding = true
env.SoundQueue:AddGate(function(clip)
    if holding and clip.present and clip.present.label == "Gossip" then return "Waiting for the NPC to finish speaking." end
end)
quests:Enqueue(H.Clip({ length = 30, present = { header = "Vartha Rockmane", label = "Gossip", portrait = { kind = "none" } } }))
Skin:UpdateControls()
Expect("a line held back is named alone, as the subtitle names it, not why it waits", Skin.title.text:GetText(), "Gossip")
holding = false
Spoken:StopAll()

---------------------------------------------------------------- under DialogueUI's open window
quests:Enqueue(H.Clip({ length = 30, present = { header = "Grull", label = "Three", portrait = { kind = "none" } } }))
Skin:Tick(1)
DUI:Show()
Skin.dialogWatch.scripts.OnShow(Skin.dialogWatch)
Expect("DialogueUI's window opening hides this one at once, the dialog showing the line",
    tostring(Skin.wanted) .. " " .. tostring(Skin.frame:IsShown()), "false false")
env.PlayerFrame:RefreshConfig()
Expect("...and it stays hidden while the dialog is open", Skin.frame:IsShown(), false)
Spoken:SetPlayerHost(DUI)
env.PlayerFrame:RefreshConfig()
Expect("...unless it sits on the dialog", Skin.wanted, true)
Spoken:SetPlayerHost(nil)
DUI:Hide()
Spoken:StopAll()

---------------------------------------------------------------- from the dialog to the top left
-- DialogueUI's window closes on a line that plays on: the window starts where the dialog was, as
-- large and as tall, at once and without a fade, then shrinks to its own size and height on its
-- way to the top left.
-- DialogueUI sets its window's OnHide with SetScript, dropping any hook: only the window's
-- children hear it close.
local function CloseDialog()
    DUI.hooks = {}
    DUI:SetScript("OnHide", function() end)
    DUI:Hide()
    local watch = Skin.dialogWatch
    if watch and watch:GetParent() == DUI then watch.scripts.OnHide(watch) end
end
saved.DialogueUI = nil
Skin:SetExpanded(false)
env.PlayerFrame:RefreshConfig()
quests:Enqueue(H.Clip({ length = 30, present = { header = "Grull", label = "The Hunt Begins", portrait = { kind = "none" } } }))
local folded = Skin.frame:GetHeight()
-- DialogueUI hides the interface, so nothing has a place on screen to read: the dialog's comes
-- from where DialogueUI puts it, centred frameOffsetX from the screen's centre, drawn at 0.8.
local frameLeft, frameTop = Skin.frame.GetLeft, Skin.frame.GetTop
Skin.frame.GetLeft, Skin.frame.GetTop = function() return nil end, function() return nil end
local dialogLeft = 960 + DUI.frameOffsetX * 0.8 - DUI.frameWidth * 0.8 / 2
local dialogTop = 540 + DUI.frameHeight * 0.8 / 2
CloseDialog()
Expect("the dialog closing on a line starts the window where the dialog was, as large",
    Near(Skin.frame.scale, 0.8) and Near(Skin.frame.anchor.x * 0.8, dialogLeft) and Near(Skin.frame.anchor.y * 0.8, dialogTop)
    and Skin.frame.anchor.relativePoint == "BOTTOMLEFT", true)
Expect("...as tall as the dialog", Near(Skin.frame:GetHeight() * Skin.frame.scale, DUI.frameHeight * 0.8), true)
Expect("...in full at once, not fading in", Skin.frame:GetAlpha() .. " " .. tostring(Skin.fadeTime), "1 nil")
Skin:Tick(0.2)
Expect("...halfway, shrinking", Skin.frame.scale < 0.8 and Skin.frame.scale > 0.52
    and Skin.frame:GetHeight() * Skin.frame.scale < DUI.frameHeight * 0.8
    and Skin.frame:GetHeight() * Skin.frame.scale > folded * 0.52, true)
Skin:Tick(0.15)
Expect("...still on its way at 0.35 seconds", Skin.settling ~= nil, true)
Skin:Tick(0.1)
Expect("...and settled at the top left by 0.4, at its own size and height", AtTopLeft() and Near(Skin.frame:GetHeight(), folded)
    and math.abs(Skin.frame.scale - 0.52) < 1e-6 and Skin.settling == nil, true)
-- Nowhere known to start from: it is simply put where it rests.
local WindowPlace = env.DialogueUITheme.WindowPlace
env.DialogueUITheme.WindowPlace = function() return nil end
Skin.frame:SetScale(0.9)
CloseDialog()
Expect("with no place for the dialog, the window goes straight to the top left at its own size",
    AtTopLeft() and math.abs(Skin.frame.scale - 0.52) < 1e-6 and Skin.settling == nil, true)
env.DialogueUITheme.WindowPlace = WindowPlace
Skin.frame.GetLeft, Skin.frame.GetTop = frameLeft, frameTop
Spoken:StopAll()
CloseDialog()
Expect("with no line playing on, the dialog closing moves nothing", Skin.settling, nil)

Expect("diagnostics name the style", string.find(Skin:Describe(), "enabled=true", 1, true) ~= nil, true)
Expect("...and the theme reading", string.find(env.DialogueUITheme:Describe(), "theme=1", 1, true) ~= nil, true)

SlashCmdList.SPOKEN("player minimal")
quests:Enqueue(H.Clip({ present = { header = "Eagan", label = "Back", portrait = { kind = "none" } } }))
Expect("switching back hides the DialogueUI window", Skin.frame:IsShown(), false)
Expect("...shows the small one", env.MinimalPlayer.frame:IsShown(), true)
Expect("...and moves the words with it", T.frame:GetParent(), env.MinimalPlayer.frame)
Expect("...in their own look again", T.style, nil)
Spoken:StopAll()

loaded = false
env.Addon.db.profile.Frame.Style = "dialogueui"
env.PlayerFrame:RefreshConfig()
Expect("DialogueUI gone, the window stands down", Skin.frame:IsShown(), false)
Expect("...for the small one", Spoken:GetPlayerStyle(), "minimal")

if Failures() > 0 then
    print(string.format("\n%d DialogueUI style test(s) failed", Failures()))
    os.exit(1)
end
print("\nAll DialogueUI style tests passed")
