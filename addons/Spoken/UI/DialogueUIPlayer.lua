setfenv(1, SpokenEnv)

-- The "dialogueui" narrator style: the queue drawn as a smaller twin of DialogueUI's quest
-- window in its own art. DialogueUI's art, window size and colours come through DialogueUITheme.lua.
--
-- Parsed by the 1.12 client too (addon.xml is shared), so Lua 5.0 syntax throughout; the
-- stub below is all that client runs.

DialogueUIPlayer = { rows = {}, offset = 0 }
-- The closing dialog drawn again (Skin:ShowGhost): off until its copy is faithful. In the game it
-- drew parts DialogueUI keeps hidden, left the portrait empty and cut titles short.
DialogueUIPlayer.drawGhost = false

if Version.IsAnyLegacy then
    function DialogueUIPlayer:IsEnabled() return false end
    function DialogueUIPlayer:SetVisible() end
    function DialogueUIPlayer:HasClip() return false end
    function DialogueUIPlayer:Describe() return "dialogueui skin: not available on this client" end
    return
end

local Skin = DialogueUIPlayer
local Theme = DialogueUITheme
local MAX_ROWS, ROW_HEIGHT = 4, 20
local PORTRAIT = 48
local MIN_LINES = 2
-- The panel's share of DialogueUI's window at the default Window Size, small enough to read
-- beside the next dialog. Taking over from the dialog, it starts at the dialog's whole size and
-- shrinks to this (Skin:Settle).
local BASE_SCALE = 0.65
-- Where it settles when the dialog closes: this far from the screen's top left, the paper's
-- edge rather than the frame's. And how it gets there from the dialog (Skin:SettleStep): lifted
-- off it SETTLE_GROW larger over SETTLE_LIFT, flown over SETTLE_TIME on a curve bowed SETTLE_BOW
-- of the way to one side (down, so it stays on the screen), then landing: giving SETTLE_GIVE
-- under it and back, over LAND_TIME.
local EDGE = 16
local SETTLE_LIFT, SETTLE_TIME, LAND_TIME = .12, .5, .5
local SETTLE_GROW, SETTLE_BOW, SETTLE_GIVE = .025, .16, 5
-- A dialog closing on another line than its own: its page goes behind this window (Skin:Tuck). A
-- line queued this long before its dialog showed is still the dialog's: Spoken and DialogueUI hear
-- the same event, in either order.
local JUST_BEFORE = 0.5
-- The tuck, in seconds: the page lifted, flying over, sliding behind; this window giving under it
-- by TUCK_GIVE and back, and its count rippling over TUCK_RIPPLE. The page lands at TUCK_SIZE of
-- the window, TUCK_LOW of its height under its middle, its foot showing under it.
local TUCK_LIFT, TUCK_FLY, TUCK_SLIDE, TUCK_NUDGE, TUCK_RIPPLE = .16, .62, .24, .5, .45
local TUCK_GIVE, TUCK_SIZE, TUCK_LOW = 7, .9, .3
-- The art a line is drawn in (Skin:Look), as DialogueUI draws it: its quest window's parchment
-- for quests, gossip and places; its book view's paper for books and letters, and its stone for
-- plaques and tombstones, picked as DialogueUI picks them from the item's material. Each is a
-- top cap, a middle that stretches and a bottom cap, rows of its file's 2048: the caps centred on
-- the window's top and foot, the middle running on `under` rows under the bottom cap, which fades
-- in over its first rows. Then, in the caps' 256 rows and the file's 1024 columns:
--   paperTop: the top cap's first opaque row; paperLeft: the first opaque column (the quest
--     parchment's: Brown 122 and 130, Dark 126 and 125, the smaller of each, so the paper never
--     runs off the screen);
--   foot: how far over the window's foot the bottom cap's light paper ends (the quest
--     parchment's rows to 105 are light, the curled rim under them).
-- The book view's paper spans columns 128 to 896, the frame's width (BOOK_PAPER).
local BOOK_ART = "Interface/AddOns/DialogueUI/Art/Book/TextureKit-"
local LOOKS = {
    quest = { top = { 0, 256 }, middle = { 256, 896 }, bottom = { 896, 1152 }, under = 0,
        paperTop = 122, paperLeft = 125, foot = 23 },
    paper = { file = BOOK_ART .. "Parchment.png", top = { 0, 256 }, middle = { 256, 896 },
        bottom = { 1152, 1408 }, under = 40, paperTop = 128, paperLeft = 128, foot = 8, palette = 1, book = true },
    stone = { file = BOOK_ART .. "Metal.png", top = { 0, 256 }, middle = { 256, 896 },
        bottom = { 1152, 1408 }, under = 40, paperTop = 123, paperLeft = 112, foot = 12, palette = 2, book = true,
        shadow = true },
}
local BOOK_PAPER = 768 / 1024
-- DialogueUI's book view: TextureKit 2 (stone) for these materials, 1 (paper) for every other.
local STONE = { Stone = true, Marble = true, Silver = true, Bronze = true, Progenitor = true }
-- In the book art: the line under its title, and the ring it draws round an item's icon, whose
-- opening is 56 of its 96 across, where the face sits.
local BOOK_DIVIDER = { 0, 768 / 1024, 1520 / 2048, 1552 / 2048 }
local BOOK_RING, RING_OPENING = { 768 / 1024, 864 / 1024, 1616 / 2048, 1712 / 2048 }, 56 / 96
-- Showing and hiding, the paper first and the rest over it (Skin:SetLevel).
local FADE_IN, FADE_OUT = .28, .32
-- A new line on a window already showing: its words fade in over LINE_IN, and the window eases to
-- its new height, as the subtitle's do (Subtitle's PAGE_IN and SIZE_EASE).
local LINE_IN, SIZE_EASE = .28, 10
-- Every fade is of the window as one image (Skin:Buffer), and nothing in it may change while it is
-- one. Before it becomes one: still this long (a face or picture just set is drawn or loaded a
-- moment after), and, fading out, deaf to the pointer for ARM_FRAMES frames so a click's pressed
-- and lit states have settled. Never waiting longer than ARM_MOST.
local STILL, ARM_FRAMES, ARM_MOST = 0.1, 2, 0.5
-- What follows the title, "• (Stopped)" and the waiting count "• +N": this far after it, fading
-- over COUNT_IN, Stopped in and out as the line stops and plays, the count in as a line is added.
local COUNT_GAP, COUNT_IN = 6, .25
-- Between the round controls in the header, as the subtitle's (Subtitle:BuildControls); and the
-- buttons' size, which is also the least room between them and the title's end (its count or
-- Stopped), so a long title cut short does not crowd them.
local ROUND_GAP, ROUND_SIZE = 4, 24
-- The words take this share of DialogueUI's column, centred in it: a narrower column than the
-- header's and the progress line's, read more easily.
local WORDS_SHARE = 0.9
-- A place's picture over its words, as Place Lore draws it (Spoken_Zones' TextView): 2:1, as
-- wide as the words, PICTURE_GAP above them, the page's grain through it.
local PICTURE_GAP, PICTURE_ALPHA = 10, 0.95
-- Where the header strip's line ends, of the strip's height: its art is clear under that (its
-- last dark row is 77 of the 96 in Parchment.png).
local DIVIDER_LINE = 0.8
local DEFAULT_WINDOW_SIZE = Defaults.profile.Frame.FrameScale
-- Text Size's default, at which the words are DialogueUI's own size.
local BASE_FONT_SIZE = 16
-- Smaller than DialogueUI's quest title, since the speaker's name shares the strip here.
local TITLE_SHARE = 0.85
-- Shift-drag width limits as shares of DialogueUI's width; the minimum still fits the face
-- and a title on the header strip.
local MIN_WIDTH_SHARE, MAX_WIDTH_SHARE = 0.6, 2
-- DialogueUI's paddings at multiplier 1.
local PAD_H, PAD_TOP, PAD_BOTTOM = 26, 48, 36
-- Where in the quest parchment's file its header strip is; it sits below the caps.
local HEADER_DIVIDER = { 0, 0.65625, 0.56640625, 0.61328125, 358, 51 }
-- Where, of the strip's 358, the portrait socket at its left end gives way to the plain
-- line. The socket is drawn as is; only the line past it stretches with the panel.
local SOCKET_WIDTH = 64
-- Ctrl-wheel limits for Window Size and Text Size, matching their sliders' ranges.
local WINDOW_SIZES, WINDOW_STEP = { 0.5, 2 }, 0.05
local FONT_SIZES = { 12, 26 }

local parts = MinimalPlayer.parts
local Font, Removable, ShowRemove, Label = parts.Font, parts.Removable, parts.ShowRemove, parts.Label
local HeldLabel, Clamp, Waiting, BelongsTo = parts.HeldLabel, parts.Clamp, parts.Waiting, parts.BelongsTo
local function Round(n) return math.floor(n + 0.5) end
local function Smooth(t) return t * t * (3 - 2 * t) end
local function EaseInOut(t)
    if t < 0.5 then return 4 * t * t * t end
    local f = 2 - 2 * t
    return 1 - f * f * f / 2
end
local function EaseOutCubic(t)
    local f = 1 - t
    return 1 - f * f * f
end
-- Of a quadratic curve from a to c bent toward b.
local function Bend(a, b, c, u) return (1 - u) * (1 - u) * a + 2 * (1 - u) * u * b + u * u * c end
-- The point bowing a path from a to b `share` of its length to one side: the side below it, so a
-- window flying to the screen's top edge never runs off it.
local function BowOf(ax, ay, bx, by, share)
    local dx, dy = bx - ax, by - ay
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0 then return ax, ay end
    local px, py = -dy / length, dx / length
    if py > 0 then px, py = -px, -py end
    return (ax + bx) / 2 + px * share * length, (ay + by) / 2 + py * share * length
end
-- Through Addon:Profile: the frame still redraws during UI teardown, after AceDB strips
-- the profile.
local function Config() return Addon:Profile("Frame") end
-- The expand state, shared with the other windows' captions.
local function Expanded() return Addon.db and Addon:Layout().CaptionsExpanded and true or false end

function Skin:IsEnabled()
    return Addon.db and Addon:DisplayStyle() == "dialogueui"
end

--- The art a line is drawn in (LOOKS): Spoken Books' pages in the book view's paper, or its
--- stone for the materials DialogueUI draws in stone; every other line in the quest parchment.
local function LookOf(clip)
    local present = clip and clip.present
    if present and (present.material or present.bullet == "book") then
        return STONE[present.material or ""] and LOOKS.stone or LOOKS.paper
    end
    return LOOKS.quest
end

function Skin:Look()
    return LookOf(self.clip)
end

function Skin:HideTooltip()
    if BelongsTo(GameTooltip:GetOwner(), self.frame) then GameTooltip_Hide() end
end

function Skin:HasClip()
    return self:IsEnabled() and self.wanted and SoundQueue:GetCurrentSound() ~= nil
end

-- No control shows the wheel sizing (Skin:Wheel), so the resize handle's tooltip mentions it.
local function WheelHint()
    GameTooltip:AddLine(L.DUI_WHEEL_HINT, 1, .82, 0, true)
end

function Skin:Initialize()
    if self.frame then return end
    local frame = CreateFrame("Frame", "SpokenDialogueUIPlayerFrame", UIParent)
    self.frame = frame
    frame.spokenBaseScale = 1
    frame:SetSize(300, 400)
    -- RefreshConfig re-runs PlaceDefault until the player drags it.
    if not Addon:RestoreLayout("DialogueUI", frame) then self:PlaceDefault() end
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    frame:SetUserPlaced(false)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() self:StartDrag() end)
    frame:SetScript("OnDragStop", function() self:StopDrag() end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Options:Open() end
    end)
    frame:SetScript("OnUpdate", function(_, elapsed) self:Tick(elapsed) end)
    -- While the handle is dragged the captions follow the edge, not the drop.
    frame:SetScript("OnSizeChanged", function()
        if self.sizing and not self.layingOut then self:Layout() end
    end)
    frame:SetScript("OnHide", function() self:HideTooltip() end)
    -- The captions and the queue take the wheel first and hand it here when Ctrl is held.
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) self:Wheel(delta) end)
    frame.spokenWheel = function(delta) return self:Wheel(delta) end
    frame:Hide()
    -- DialogueUI's quest window or its book view closing on a line that plays on: this one takes
    -- over from it. Told by a child of each, as DialogueUIBridge's driver is: DialogueUI sets the
    -- quest window's own OnHide with SetScript, which drops a hook.
    self.dialogs, self.dialogWatches = {}, {}
    -- Which lines each dialog queued (Skin:StartSession), so the one closing knows its own.
    self.queuedAt, self.sessions = setmetatable({}, { __mode = "k" }), {}
    for _, name in ipairs({ "DUIQuestFrame", "DUIBookFrame" }) do
        local dialog = _G[name]
        if type(dialog) == "table" and dialog.GetEffectiveScale then
            local watch = CreateFrame("Frame", nil, dialog)
            watch:SetScript("OnHide", function() self:Settle(dialog) end)
            -- Opening, it shows the line itself: this one steps aside at once (Skin:Covered).
            watch:SetScript("OnShow", function()
                self:StartSession(dialog)
                self.captureWait = 0
                self:Update()
            end)
            -- Its look, read while it is open (Skin:Capture).
            watch:SetScript("OnUpdate", function(_, elapsed) self:CaptureTick(dialog, elapsed) end)
            table.insert(self.dialogs, dialog)
            self.dialogWatches[dialog] = watch
            self.sessions[dialog] = setmetatable({}, { __mode = "k" })
        end
    end
    self.captures = {}
    Callbacks:Register("CLIP_QUEUED", function(clip) self:Queued(clip) end)
    self.dialog = _G.DUIQuestFrame
    self.dialogWatch = self.dialog and self.dialogWatches[self.dialog]

    -- DialogueUI's three parchment strips: caps centred on the frame's ends, the middle
    -- stretched between, all wider than the frame.
    self.parchments = {}
    for index = 1, 3 do
        local strip = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
        self.parchments[index] = strip
    end
    self.parchments[1]:SetPoint("CENTER", frame, "TOP", 0, 0)
    self.parchments[3]:SetPoint("CENTER", frame, "BOTTOM", 0, 0)
    self.parchments[2]:SetPoint("TOPLEFT", self.parchments[1], "BOTTOMLEFT", 0, 0)
    self.parchments[2]:SetPoint("BOTTOMRIGHT", self.parchments[3], "TOPRIGHT", 0, 0)
    -- Over the middle where the book art's bottom cap fades in over it.
    self.parchments[3]:SetDrawLayer("BACKGROUND", 0)

    local content = CreateFrame("Frame", nil, frame)
    self.content, frame.container = content, content
    -- The words are docked here (Skin:Layout), and hand Ctrl-wheel to their parent.
    content.spokenWheel = frame.spokenWheel
    content.buttons = {}

    -- The header strip's place, which the face and the title are set in whatever the look.
    self.header = CreateFrame("Frame", nil, content)
    -- In the quest parchment, DialogueUI's header strip in two pieces: the face's socket, never
    -- stretched, and the line past it, stretched to the panel's width. In a book's, the ring
    -- round the face and the line under the title (Skin:Layout).
    self.headerSocket = content:CreateTexture(nil, "ARTWORK")
    self.headerDivider = content:CreateTexture(nil, "ARTWORK")
    local host = CreateFrame("Frame", nil, content)
    self.portrait, frame.portrait = host, host
    host:SetSize(PORTRAIT, PORTRAIT)
    self.viewport = CreateFrame("Frame", nil, host)
    self.viewport:SetAllPoints()
    self.viewport:SetClipsChildren(true)
    -- What kind of line it is, on a dark disc at the face's lower right, as the subtitle and the
    -- small window badge theirs (MinimalPlayer.BADGES).
    local chrome = CreateFrame("Frame", nil, host)
    chrome:SetAllPoints()
    chrome:SetFrameLevel(host:GetFrameLevel() + 8)
    self.badgeDisc = chrome:CreateTexture(nil, "BACKGROUND")
    self.badgeDisc:SetTexture([[Interface\AddOns\Spoken\Textures\MinimalPortraitMask]])
    self.badgeDisc:SetVertexColor(.04, .04, .035, 1)
    self.badge = chrome:CreateTexture(nil, "OVERLAY")
    self.name = Font(content, 18, 1, 1, 1)
    content.name = self.name -- Actions' header anchor contract.
    self.name:SetHeight(20)
    -- The line's name, nothing to click: Skip takes a line away, as on the subtitle.
    self.title = CreateFrame("Frame", nil, content)
    self.title.text = Font(self.title, 12, 1, 1, 1)
    self.title.text:SetPoint("TOPLEFT")
    self.title.text:SetPoint("BOTTOMRIGHT")
    -- Stopped and the lines waiting, after the title: each its own text, so each fades by itself.
    self.stopped = Font(self.title, 12, 1, 1, 1)
    self.stopped:SetText(format("• (%s)", L.SUBTITLE_STOPPED))
    self.stopped:Hide()
    self.stoppedAlpha = 0
    self.count = Font(self.title, 12, 1, 1, 1)
    self.count:Hide()

    self.picture = content:CreateTexture(nil, "ARTWORK")
    self.picture:SetAlpha(PICTURE_ALPHA)
    self.picture:Hide()
    -- Its frayed edge, where the client has mask textures.
    if content.CreateMaskTexture and self.picture.AddMaskTexture then
        self.pictureMask = content:CreateMaskTexture()
        self.pictureMask:SetAllPoints(self.picture)
        self.picture:AddMaskTexture(self.pictureMask)
    end

    self.drawer = CreateFrame("Frame", nil, content)
    self.drawer:EnableMouseWheel(true)
    self.drawer:SetScript("OnMouseWheel", function(_, delta)
        if self:Wheel(delta) then return end
        self.offset = Clamp(self.offset - delta, 0, math.max(0, Waiting() - MAX_ROWS))
        self:LayoutQueue()
    end)
    self.queueNote = Font(self.drawer, 10, 1, 1, 1)
    self.drawer:Hide()

    -- The subtitle's progress line, along the foot of the words.
    self.progress = Actions.ProgressBar(content)
    -- The subtitle's controls (Subtitle:BuildControls) at the header's right end, beside the
    -- speaker and the line: Stop or Replay, Skip, then Report (Skin:ConfigureActions).
    self.controls = CreateFrame("Frame", nil, content)
    self.controls:SetHeight(1)
    local play = Actions.RoundButton(self.controls, 12)
    play:SetScript("OnClick", function()
        if not (self:HasClip() and SoundQueue:CanBePaused()) then return end
        SpokenLayout.Sound("U_CHAT_SCROLL_BUTTON")
        SoundQueue:TogglePauseQueue()
        self:UpdateControls()
    end)
    play:SetScript("OnEnter", function()
        play.glyph:SetAlpha(1)
        GameTooltip:SetOwner(play, "ANCHOR_TOP")
        GameTooltip:SetText(SoundQueue:IsPaused() and L.REPLAY or L.STOP)
        GameTooltip:Show()
    end)
    self.play, self.skip = play, Actions.SkipButton(self.controls)
    -- What they are, for a closing dialog's matching buttons to travel to (Skin:GhostTarget).
    self.play.spokenRound, self.skip.spokenRound = "play", "skip"
    self.buttons = { self.play, self.skip }
    Actions:Build(frame)

    -- No scrollbar: the captions scroll themselves on the wheel.

    -- The width changes only with Shift held at drag start, so a height drag cannot knock
    -- the column out of DialogueUI's shape.
    self.resizer = CreateFrame("Button", nil, frame)
    self.resizer:SetSize(14, 14)
    self.resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    self.resizer:SetNormalTexture([[Interface\AddOns\Spoken\Textures\SizeGrabber-Up]])
    self.resizer:SetAlpha(.5)
    self.resizer:SetScript("OnEnter", function()
        self.resizer:SetAlpha(1)
        GameTooltip:SetOwner(self.resizer, "ANCHOR_LEFT")
        GameTooltip:SetText(L.DUI_RESIZE_TIP, 1, 1, 1, 1, true)
        WheelHint()
        GameTooltip:Show()
    end)
    self.resizer:SetScript("OnLeave", function() self.resizer:SetAlpha(.5); self:HideTooltip() end)
    self.resizer:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or Addon:IsFrameLocked() or not Expanded() then return end
        self.sizing = true
        self.sizingWidth = IsShiftKeyDown and IsShiftKeyDown() and true or false
        self:Layout() -- the resize bounds for this drag: free width only with Shift
        frame:StartSizing(self.sizingWidth and "BOTTOMRIGHT" or "BOTTOM")
    end)
    self.resizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        if self.sizing then
            Addon:Layout().DialogueUIHeight = Round(frame:GetHeight())
            if self.sizingWidth then Addon:Layout().DialogueUIWidth = Round(frame:GetWidth()) end
            -- Sizing pins the top-left, so the panel now counts as placed by the player.
            Addon:SaveLayout("DialogueUI", frame)
        end
        self.sizing, self.sizingWidth = false, false
        self:Layout(); self:Update()
    end)
end

--- DialogueUI's own window open over this one, which then stays hidden: the dialog shows the line.
--- Not while this one sits on the dialog (Show Spoken Over DialogueUI).
function Skin:Covered()
    for _, dialog in ipairs(self.dialogs or {}) do
        if dialog:IsShown() and self.frame:GetParent() ~= dialog then return true end
    end
    return false
end

function Skin:StartDrag()
    if not Addon:IsFrameLocked() then self.frame:StartMoving() end
end

function Skin:StopDrag()
    self.frame:StopMovingOrSizing()
    if not Addon:IsFrameLocked() then Addon:SaveLayout("DialogueUI", self.frame) end
end

--- Runs on every refresh, so a theme or size change in DialogueUI lands on the next one.
function Skin:Layout()
    self:Touch()
    local frame, cfg = self.frame, Theme:Config()
    local look = self:Look()
    self.look = look
    local parchment = look.file or Theme:TexturePath() .. "Parchment.png"
    self.layingOut = true
    -- Laid out at DialogueUI's own size, paddings and text; Window Size then scales the
    -- whole frame from BASE_SCALE.
    local scale = BASE_SCALE * (Config().FrameScale or DEFAULT_WINDOW_SIZE) / DEFAULT_WINDOW_SIZE
    frame.spokenBaseScale = scale * Theme:FrameScale() / UIParent:GetEffectiveScale()
    local duiWidth, duiHeight = Theme:FrameSize()
    -- The multiplier DialogueUI drew its window at, so the paddings keep its proportions.
    local multiplier = duiHeight / (Theme.HEIGHT_SHARE * math.max(1, UIParent:GetHeight()))
    local padH, padTop, padBottom = PAD_H * multiplier, PAD_TOP * multiplier, PAD_BOTTOM * multiplier
    local width = self.sizingWidth and Round(frame:GetWidth()) or Addon:Layout().DialogueUIWidth or Round(duiWidth)
    local minWidth, maxWidth = Round(duiWidth * MIN_WIDTH_SHARE), Round(duiWidth * MAX_WIDTH_SHARE)
    width = Clamp(width, minWidth, maxWidth)
    local inner = math.max(1, width - 2 * padH)
    local wordsWidth = math.max(1, Round(inner * WORDS_SHARE))
    local wordsLeft = Round((inner - wordsWidth) / 2)
    -- The header and footer are sized from DialogueUI's own column, so a wider panel stretches
    -- the strips but keeps the face, the title and the strips' thickness.
    local baseInner = math.max(1, Round(duiWidth) - 2 * padH)
    -- DialogueUI's spacing: 0.35 of the text size under each line, four of those between
    -- paragraphs, which an empty line approximates.
    local fonts = Theme:Fonts(look.book)
    local fontSize = fonts.paragraphSize
    local textSize = tonumber(Addon:Profile("Transcript").FontSize) or BASE_FONT_SIZE
    local captionSize = math.max(6, Round(fontSize * textSize / BASE_FONT_SIZE))
    local lineGap = Round(0.35 * captionSize)
    local lineHeight = captionSize + lineGap
    self.fonts, self.captionSize, self.lineGap = fonts, captionSize, lineGap

    -- DialogueUI's header strip thickness and its face and title placements, scaled to its column,
    -- whatever the look.
    local ratio = baseInner / HEADER_DIVIDER[5]
    local stripHeight = Round(HEADER_DIVIDER[6] * ratio)
    local face = Round(34 * ratio)
    -- DialogueUI's gap under its header line, before the text.
    local textGap = Round(4 * 0.35 * fontSize)
    local headerHeight = stripHeight + textGap
    -- A place's picture (Spoken Zones gives one with its line) between the header and the words,
    -- as wide as they are.
    local picture = self.clip and self.clip.present and self.clip.present.picture
    local pictureWidth = picture and wordsWidth or 0
    local pictureHeight = Round(pictureWidth / 2)
    -- With a picture, one gap over it and under it: from the divider's line to the picture, and
    -- from the picture to the words. Halfway between the header's gap under the line and the
    -- picture's own.
    local lineBottom = Round(stripHeight * DIVIDER_LINE)
    local pictureGap = Round((stripHeight - lineBottom + textGap + PICTURE_GAP) / 2)
    local pictureTop = lineBottom + pictureGap
    local wordsTop = picture and pictureTop + pictureHeight + pictureGap or headerHeight
    -- The same gap above the progress line, so the words sit as far from the foot as from the
    -- head. The last line's own spacing counts towards it.
    -- Show Progress, as the subtitle has it: off, the bar goes and the window closes up under the words.
    local progress = Addon:Profile("Transcript").SubtitleProgress ~= false
    self.progress.track:SetShown(progress)
    local footerHeight = (progress and self.progress.height + 6 or 0) + math.max(0, textGap - lineGap)
    -- A line's room over and under the words, which a line gliding out or in fades through: it is
    -- at nothing by the time it reaches the edge, so no line is ever seen cut there. It reaches
    -- over the gaps there (the header's or the picture's, the one over the progress line) and
    -- adds none: the words keep their place.
    -- Under the progress line, as far to where the paper's light ends as the last line is over it:
    -- the 6 and the header's gap over the line, and the line's own spacing under its letters.
    -- The caps: the quest parchment's as DialogueUI drew them, following the panel's width and
    -- keeping DialogueUI's overhang either side; a book's as wide as its paper puts the paper on
    -- the frame's width, 4 to 1 as in the file.
    local capWidth, capHeight = Theme:ParchmentSize()
    if look.book then
        capWidth = width / BOOK_PAPER
        capHeight = capWidth * (look.top[2] - look.top[1]) / 1024
    else
        capWidth = capWidth * width / math.max(1, Round(duiWidth))
    end
    local barLift = 0
    if progress then
        local above = 6 + math.max(0, textGap - lineGap) + lineGap
        local foot = capHeight * look.foot / 256
        barLift = Round(above - (padBottom - foot))
        footerHeight = footerHeight + barLift
        self.progressGaps = { above = above, below = padBottom + barLift - foot }
    end
    -- The lines waiting get rows while the window is open; folded, the title counts them.
    local waiting = Waiting()
    local shownRows = Expanded() and math.min(MAX_ROWS, waiting) or 0
    local queueHeight = shownRows * ROW_HEIGHT + (shownRows > 0 and waiting > MAX_ROWS and 14 or 0)
    -- A panel too small for MIN_LINES grows to fit them, so the controls are never cut off.
    local height = self.sizing and Round(frame:GetHeight()) or Addon:Layout().DialogueUIHeight or Round(duiHeight)
    local body = height - padTop - wordsTop - queueHeight - padBottom - footerHeight
    local lines = math.max(MIN_LINES, math.floor(body / lineHeight))
    local expanded = Expanded()
    if not expanded then
        lines = Addon:Profile("Transcript").Lines == 1 and 1 or 2
        height = 0
    end
    -- Fit to the Words, except while the handle is dragged and the panel follows the pointer.
    if cfg.FitText ~= false and not self.sizing then
        local needed = self:TextLines(wordsWidth)
        if needed and needed < lines then
            lines, height = math.max(needed, expanded and MIN_LINES or 1), 0
        end
    end
    local captionHeight = lines * lineHeight
    height = math.max(height, padTop + wordsTop + captionHeight + queueHeight + padBottom + footerHeight)
    self.settledHeight = height
    -- A new line on a window already showing eases to its height (Skin:Tick).
    local easing = self.easeNext and not self.settling and not self.sizing
    self.easeNext = nil
    self.heightWant = easing and height or nil
    frame:SetSize(width, (self.settling or easing) and frame:GetHeight() or height)
    local minHeight = padTop + wordsTop + MIN_LINES * lineHeight + queueHeight + padBottom + footerHeight
    if frame.SetResizeBounds then
        if self.sizingWidth then
            frame:SetResizeBounds(minWidth, minHeight, maxWidth, 4000)
        else
            frame:SetResizeBounds(width, minHeight, width, 4000)
        end
    end
    self.resizer:SetShown(expanded and not Addon:IsFrameLocked())
    self.lines = lines

    for index = 1, 3 do self.parchments[index]:SetTexture(parchment) end
    self.parchments[1]:SetTexCoord(0, 1, look.top[1] / 2048, look.top[2] / 2048)
    self.parchments[2]:SetTexCoord(0, 1, look.middle[1] / 2048, look.middle[2] / 2048)
    self.parchments[3]:SetTexCoord(0, 1, look.bottom[1] / 2048, look.bottom[2] / 2048)
    self.parchments[1]:SetSize(capWidth, capHeight)
    self.parchments[3]:SetSize(capWidth, capHeight)
    self.parchments[2]:ClearAllPoints()
    self.parchments[2]:SetPoint("TOPLEFT", self.parchments[1], "BOTTOMLEFT", 0, 0)
    self.parchments[2]:SetPoint("BOTTOMRIGHT", self.parchments[3], "TOPRIGHT", 0, -capHeight * look.under / 256)

    local content = self.content
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", padH, -padTop)
    content:SetPoint("BOTTOMRIGHT", -padH, padBottom)
    local socket = Round(SOCKET_WIDTH * ratio)
    self.header:ClearAllPoints()
    self.header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    self.header:SetSize(socket, stripHeight)
    self.portrait:SetSize(face, face)
    self.portrait:ClearAllPoints()
    self.portrait:SetPoint("CENTER", self.header, "TOPLEFT", Round(23 * ratio), -Round(23 * ratio))
    self.headerSocket:SetTexture(parchment)
    self.headerDivider:SetTexture(parchment)
    self.headerSocket:ClearAllPoints()
    self.headerDivider:ClearAllPoints()
    if look.book then
        -- The book's ring round the face, its opening the face's size, and its line under the
        -- title where the quest strip's line ends.
        local ring = Round(face / RING_OPENING)
        self.headerSocket:SetTexCoord(BOOK_RING[1], BOOK_RING[2], BOOK_RING[3], BOOK_RING[4])
        self.headerSocket:SetSize(ring, ring)
        self.headerSocket:SetPoint("CENTER", self.portrait, "CENTER", 0, 0)
        local lineHeightArt = math.max(1, Round(inner * 32 / 768))
        self.headerDivider:SetTexCoord(BOOK_DIVIDER[1], BOOK_DIVIDER[2], BOOK_DIVIDER[3], BOOK_DIVIDER[4])
        self.headerDivider:SetSize(inner, lineHeightArt)
        self.headerDivider:SetPoint("CENTER", content, "TOP", 0,
            -(Round(stripHeight * DIVIDER_LINE) - Round(lineHeightArt / 2)))
    else
        local socketU = HEADER_DIVIDER[1] + (HEADER_DIVIDER[2] - HEADER_DIVIDER[1]) * SOCKET_WIDTH / HEADER_DIVIDER[5]
        self.headerSocket:SetTexCoord(HEADER_DIVIDER[1], socketU, HEADER_DIVIDER[3], HEADER_DIVIDER[4])
        self.headerSocket:SetPoint("TOPLEFT", self.header, "TOPLEFT", 0, 0)
        self.headerSocket:SetSize(socket, stripHeight)
        self.headerDivider:SetTexCoord(socketU, HEADER_DIVIDER[2], HEADER_DIVIDER[3], HEADER_DIVIDER[4])
        self.headerDivider:SetPoint("TOPLEFT", self.headerSocket, "TOPRIGHT", 0, 0)
        self.headerDivider:SetSize(math.max(1, inner - socket), stripHeight)
    end
    local badgeAt = Round(face * 0.36)
    self.badgeDisc:SetSize(Round(face * 0.42), Round(face * 0.42))
    self.badge:SetSize(Round(face * 0.3), Round(face * 0.3))
    for _, part in ipairs({ self.badgeDisc, self.badge }) do
        part:ClearAllPoints()
        part:SetPoint("CENTER", self.portrait, "CENTER", badgeAt, -badgeAt)
    end
    -- The round buttons as large on screen as Place Lore draws them (24, at UIParent's scale) at
    -- the default Window Size, growing and shrinking with it from there (Skin:FitControls).
    self.controlsRound = (Config().FrameScale or DEFAULT_WINDOW_SIZE) / DEFAULT_WINDOW_SIZE / frame.spokenBaseScale
    -- The line's title sits where DialogueUI puts its quest title, the speaker's name in its
    -- small line above, both stopping a button's width short of the buttons.
    local clear = Round(ROUND_SIZE * self.controlsRound)
    self.title:ClearAllPoints()
    self.title:SetPoint("LEFT", self.header, "LEFT", Round(53 * ratio), Round(2 * ratio))
    self.title:SetPoint("RIGHT", self.controls, "LEFT", -clear, 0)
    self.title:SetHeight(Round(fonts.titleSize * TITLE_SHARE) + 4)
    self.name:ClearAllPoints()
    self.name:SetPoint("BOTTOMLEFT", self.title, "TOPLEFT", 0, 2)
    self.name:SetPoint("RIGHT", self.controls, "LEFT", -clear, 0)
    self.name:SetHeight(fonts.subtitleSize + 2)
    -- Centred on the speaker's name and the line's title together: the title sits on the
    -- socket's middle, 2 up, and the name above it.
    local nameHeight = fonts.subtitleSize + 2
    local middle = stripHeight / 2 - Round(2 * ratio) - (2 + nameHeight) / 2
    self.controlsMiddle = middle
    self:FitControls()

    -- The words in their narrower column, the picture over them.
    self.picture:SetShown(picture ~= nil)
    if picture then
        self.picture:SetTexture(picture.file)
        if self.pictureMask then
            self.pictureMask:SetTexture(picture.mask or [[Interface\Buttons\WHITE8X8]], "CLAMPTOBLACKADDITIVE",
                "CLAMPTOBLACKADDITIVE")
        end
        self.picture:SetSize(pictureWidth, pictureHeight)
        self.picture:ClearAllPoints()
        self.picture:SetPoint("TOP", content, "TOPLEFT", Round(inner / 2), -pictureTop)
    end
    -- The captions span that room too; the lines fade through it (Transcript:Place).
    self.lineRoom = lineHeight
    Transcript:Dock(content, content, "TOPLEFT", wordsLeft, -(wordsTop - lineHeight), wordsWidth,
        captionHeight + 2 * lineHeight)

    self.drawer:ClearAllPoints()
    self.drawer:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(wordsTop + captionHeight))
    self.drawer:SetSize(inner, math.max(1, queueHeight))

    -- The progress line as wide as the words and the picture over it.
    self.progress.track:ClearAllPoints()
    self.progress.track:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", wordsLeft, barLift)
    self.progress.track:SetWidth(wordsWidth)

    self:Dress()
    self.layingOut = false
end

function Skin:Dress()
    local look = self.look or LOOKS.quest
    local colors = Theme:Colors(look.palette)
    local fonts = self.fonts or Theme:Fonts(look.book)
    local body = fonts.paragraphSize
    -- On stone, the book view's shadow under its pale text.
    local shadow = look.shadow and 1 or 0
    local function Paint(text, face, size, color)
        text:SetFont(face, size, "")
        text:SetShadowColor(0, 0, 0, shadow)
        text:SetShadowOffset(1, -1)
        text:SetTextColor(color[1], color[2], color[3])
    end
    Paint(self.name, fonts.subtitle, fonts.subtitleSize, colors.title)
    Paint(self.title.text, fonts.title, Round(fonts.titleSize * TITLE_SHARE), colors.title)
    Paint(self.count, fonts.title, Round(fonts.titleSize * TITLE_SHARE), colors.disabled)
    Paint(self.stopped, fonts.title, Round(fonts.titleSize * TITLE_SHARE), colors.disabled)
    self.title.color = colors.title
    Paint(self.queueNote, fonts.paragraph, math.max(8, body - 2), colors.disabled)
    for _, row in ipairs(self.rows) do
        Paint(row.text, fonts.paragraph, math.max(8, body - 1), colors.gossip)
        row.color = colors.gossip
    end
    self.colors = colors
    local tint = colors.portraitTint
    if self.viewport.texture then self.viewport.texture:SetVertexColor(tint[1], tint[2], tint[3]) end
    local captionSize = self.captionSize or body
    Transcript:SetStyle({ font = fonts.paragraph, size = captionSize, lineGap = self.lineGap or Round(0.35 * captionSize),
        paragraphs = true, color = colors.paragraph, shadow = look.shadow and true or false,
        highlight = colors.highlight, lines = self.lines, padTop = self.lineRoom })
end

function Skin:ConfigurePortrait()
    -- A face set or redrawn: it is drawn a moment after.
    self:Touch()
    -- Always the face: the header strip has its socket, which would stand empty without it.
    self.portrait:Show()
    if not StaticPortrait:Configure(self.viewport, self.clip) then Portrait:Configure(self.viewport, self.clip) end
    local viewport = self.viewport
    if viewport.active == "texture" and viewport.texture then StaticPortrait:Mask(viewport, viewport.texture) end
    local tint = self.colors and self.colors.portraitTint
    if tint and viewport.texture then viewport.texture:SetVertexColor(tint[1], tint[2], tint[3]) end
    local id = self.clip and self.clip.present and self.clip.present.bullet
    local badge = MinimalPlayer.BADGES[id] or (Bullets and Bullets[id] and Bullets[id].texture)
    self.badge:SetTexture(badge)
    self.badge:SetShown(badge ~= nil)
    self.badgeDisc:SetShown(badge ~= nil)
end

function Skin:ConfigureActions()
    Actions:Configure(self.frame, self.clip)
    local row = { self.play, self.skip }
    for _, button in ipairs(self.frame.actions.buttons) do
        if button.action.anchor == "header" then
            button:Hide()
        else
            -- Report and anything else a line offers, after Skip and as strong as it, as the
            -- subtitle shows them.
            button:SetParent(self.controls)
            button:SetFrameLevel(self.controls:GetFrameLevel() + 1)
            if button.showsIcon then button:SetSize(self.play:GetWidth(), self.play:GetHeight()) end
            button:SetAlpha(1)
            if button:IsShown() then table.insert(row, button) end
        end
    end
    self.row = row
    self:LayoutControls()
end

--- Ctrl-wheel steps Window Size, Ctrl-Shift-wheel Text Size, keeping the top-left corner in
--- place as the scale changes. True when the wheel was taken.
function Skin:Wheel(delta)
    if delta == 0 or not (IsControlKeyDown and IsControlKeyDown()) then return false end
    local text
    if IsShiftKeyDown and IsShiftKeyDown() then
        local transcript = Addon:Profile("Transcript")
        transcript.FontSize = Clamp((transcript.FontSize or BASE_FONT_SIZE) + (delta > 0 and 1 or -1),
            FONT_SIZES[1], FONT_SIZES[2])
        text = format("%s: %d", L.TRANSCRIPT_SIZE, transcript.FontSize)
    else
        local cfg = Config()
        local value = (cfg.FrameScale or DEFAULT_WINDOW_SIZE) + (delta > 0 and WINDOW_STEP or -WINDOW_STEP)
        cfg.FrameScale = Clamp(math.floor(value / WINDOW_STEP + 0.5) * WINDOW_STEP, WINDOW_SIZES[1], WINDOW_SIZES[2])
        text = format("%s: %d%%", L.OPT_SCALE, Round(cfg.FrameScale * 100))
    end
    local frame = self.frame
    local left, top, before = frame:GetLeft(), frame:GetTop(), frame:GetEffectiveScale()
    PlayerFrame:RefreshConfig()
    -- Dragged before: its top-left corner stays put. Never dragged: it stays where DialogueUI
    -- puts its window, and RefreshConfig has placed it there at its new size.
    if left and top and Addon:Layout().DialogueUI and not Addon:IsFrameLocked() then
        local after = frame:GetEffectiveScale()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * before / after, top * before / after)
        Addon:SaveLayout("DialogueUI", frame)
    end
    GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
    GameTooltip:SetText(text)
    GameTooltip:Show()
    return true
end

--- The state persists and is shared with the other windows' expand button.
function Skin:SetExpanded(expanded)
    expanded = expanded and true or false
    if Expanded() == expanded then return end
    Addon:Layout().CaptionsExpanded = expanded
    if self.frame then self:Layout(); self:Update() end
end

function Skin:LayoutControls()
    local x, tallest = 0, 1
    for _, button in ipairs(self.row or self.buttons) do
        button:ClearAllPoints()
        button:SetPoint("LEFT", self.controls, "LEFT", x, 0)
        x = x + button:GetWidth() + ROUND_GAP
        tallest = math.max(tallest, button:GetHeight())
    end
    self.controls:SetSize(math.max(1, x - ROUND_GAP), tallest)
end

--- `relayout` when the row's buttons may have changed (Update); otherwise the row is laid out
--- again only when the play button's label does.
function Skin:UpdateControls(relayout)
    if not self.clip then return end
    local paused = SoundQueue:IsPaused()
    Actions.SetPlayGlyph(self.play, Actions.HeadState())
    -- The line's name alone, as the subtitle shows it: not why it waits (the NPC's own greeting
    -- first, a fight), which the waiting lines' rows still say.
    self.title.text:SetText(Label(self.clip))
    -- Stopped, said after its name, as the subtitle does.
    if paused ~= (self.shownStopped or false) then self.shownStopped = paused end
    self:Count(Waiting())
    local pausable = SoundQueue:CanBePaused()
    for _, button in ipairs(self.buttons) do
        button:SetAlpha(pausable and 1 or .4)
        if pausable then button:Enable() else button:Disable() end
    end
    if relayout then self:LayoutControls() end
end

function Skin:UpdateProgress()
    local clip = self.clip
    if not clip then return end
    local duration = tonumber(clip.length) or 0
    if clip.nextSoundTimer and duration > 0 then
        -- The queue's timer includes the source's trailing gap and any initial silence,
        -- so TimeLeft is right through hidden UI and replays alike.
        local remaining = Addon:TimeLeft(clip.nextSoundTimer)
        self.seconds = Clamp(duration + SoundQueue:GapAfter(clip) - remaining, 0, duration)
    elseif not SoundQueue:IsPaused() then self.seconds = 0 end
    Actions.SetProgress(self.progress, duration > 0 and (self.seconds or 0) / duration or 0)
end

function Skin:CreateQueueRow(index)
    local button = CreateFrame("Button", nil, self.drawer)
    self.rows[index] = button
    button:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    button:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
    button:SetHeight(ROW_HEIGHT)
    local color = self.colors and self.colors.gossip or { 1, 1, 1 }
    Removable(button, 11, color[1], color[2], color[3])
    local fonts = self.fonts or Theme:Fonts()
    button.text:SetFont(fonts.paragraph, math.max(8, fonts.paragraphSize - 1), "")
    button.text:SetShadowColor(0, 0, 0, 0)
    button:SetScript("OnEnter", function()
        -- Nothing in the window changes while it is one image (Skin:Buffer).
        if self.buffered then return end
        ShowRemove(button, true)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(Label(button.clip))
        GameTooltip:AddLine(L.QUEUE_REMOVE_TOOLTIP, 1, .82, 0, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() ShowRemove(button, false); self:HideTooltip() end)
    button:SetScript("OnClick", function()
        if self:HasClip() then SoundQueue:RemoveSoundFromQueue(button.clip) end
    end)
    return button
end

function Skin:LayoutQueue()
    local waiting = Waiting()
    self.offset = Clamp(self.offset, 0, math.max(0, waiting - MAX_ROWS))
    local shown = Expanded() and math.min(MAX_ROWS, waiting - self.offset) or 0
    for index = 1, MAX_ROWS do
        local button = self.rows[index]
        if index <= shown then
            button = button or self:CreateQueueRow(index)
            button.clip = SoundQueue.sounds[index + self.offset + 1]
            button.text:SetText(HeldLabel(button.clip))
            ShowRemove(button, false)
            button:Show()
        elseif button then button:Hide(); button.clip = nil end
    end
    self.queueNote:ClearAllPoints()
    self.queueNote:SetPoint("BOTTOMLEFT")
    self.queueNote:SetText(format(L.MIN_SCROLL_QUEUE, self.offset + 1, self.offset + shown, waiting))
    self.queueNote:SetShown(shown > 0 and waiting > MAX_ROWS)
    self.drawer:SetShown(shown > 0)
end

--- How much of the window shows, 0 to 1: as one image, its alpha (Skin:Buffer). Where the client
--- has no frame buffers, the paper takes the lower half and everything on it the upper, so the two
--- never fade at once and the paper never shows through the strips and words.
function Skin:SetLevel(level)
    self.level = level
    if self.buffered then
        self.frame:SetAlpha(level)
        self.content:SetAlpha(1)
        return
    end
    self.frame:SetAlpha(Clamp(level * 2, 0, 1))
    self:PaintContent()
end

-- The window's direct parts, which ignore its alpha while it is one image.
local function Parts(self)
    return { self.content, self.resizer, self.parchments[1], self.parchments[2], self.parchments[3] }
end

-- What the pointer lights, presses or scrolls in the window: a button pressed or lit changes its
-- textures, which must not happen while it is one image.
local function Clickables(self)
    local list = { self.frame, self.play, self.skip, self.resizer, self.drawer, Transcript.frame }
    for _, button in ipairs(self.row or {}) do table.insert(list, button) end
    for _, row in ipairs(self.rows or {}) do table.insert(list, row) end
    return list
end

-- A texture in the window still loading, which it must not be while it becomes one image.
local function Loading(texture)
    return texture ~= nil and texture.IsObjectLoaded ~= nil and texture:IsShown() and not texture:IsObjectLoaded()
end

--- Something in the window changed: it waits to be still again before it becomes one image.
function Skin:Touch()
    self.stillFor = 0
end

--- Nothing in the window may change: it is one image. The portrait cache asks before it paints a
--- face anew (StaticPortrait:Capture).
function Skin:Frozen()
    return self.buffered and true or false
end

--- Still a while, and nothing in it loading: it may become one image.
function Skin:Still()
    if (self.stillFor or STILL) < STILL then return false end
    local viewport = self.viewport
    return not (Loading(self.picture) or Loading(self.badge)
        or Loading(viewport and viewport.activeFrame) or Loading(viewport and viewport.texture))
end

--- Deaf to the pointer, so nothing in the window lights or presses: before it becomes one image,
--- and while it is.
function Skin:Deafen()
    if self.deafened then return end
    self.deafened = {}
    for _, part in ipairs(Clickables(self)) do
        local entry = { part = part }
        if part.IsMouseEnabled and part:IsMouseEnabled() then entry.mouse = true; part:EnableMouse(false) end
        if part.IsMouseWheelEnabled and part:IsMouseWheelEnabled() then entry.wheel = true; part:EnableMouseWheel(false) end
        table.insert(self.deafened, entry)
    end
end

function Skin:Undeafen()
    if not self.deafened then return end
    for _, entry in ipairs(self.deafened) do
        if entry.mouse then entry.part:EnableMouse(true) end
        if entry.wheel then entry.part:EnableMouseWheel(true) end
    end
    self.deafened = nil
    -- Locked, clicks still pass through (Skin:RefreshConfig).
    local frame = self.frame
    if frame.SetMouseClickEnabled and frame.SetMouseMotionEnabled then
        frame:SetMouseMotionEnabled(true)
        frame:SetMouseClickEnabled(not Addon:IsFrameLocked())
    end
end

--- Switch the window into or out of being one image while it is hidden: switched while on screen
--- and faded (fading in from nothing), the client crashed at once (ASSERT(flattenedBatch !=
--- nullptr)), as Place Lore's panel did; made one while hidden, as at its creation, it never did.
--- Hidden and shown again in the one frame, so nothing flickers, and its buttons' lit and pressed
--- states are reset by it.
local function SwitchHidden(frame, on)
    local shown = frame:IsShown()
    if shown then frame:Hide() end
    local ok = pcall(frame.SetIsFrameBuffer, frame, on)
    if shown then frame:Show() end
    return ok
end

--- The window drawn as one image (a frame buffer, as the world map is) and faded as one, its parts
--- ignoring its alpha so only the finished image fades. Every crash came of something in it
--- changing while it was one (the title's remove cross loading, the captions clearing at a line's
--- end, Skip going from pressed to normal: CSimpleRender.cpp's texture asserts, ASSERT(!m_deleted),
--- ASSERT(flattenedBatch != nullptr)), so while it is: deaf to the pointer, the captions held, its
--- own updates waiting (Skin:Tick, Skin:Update), the portrait cache not painting its face. False
--- where the client has no frame buffers.
function Skin:Buffer()
    local frame = self.frame
    if self.buffered then return true end
    if not frame.SetIsFrameBuffer then return false end
    -- Its own small animations finished first.
    self.lineFade, self.countFade = nil, nil
    if self.count then
        self.stoppedAlpha = self.shownStopped and 1 or 0
        self:Count(self.counted or 0)
    end
    if self.heightWant then frame:SetHeight(self.heightWant); self.heightWant = nil end
    self:Deafen()
    if not SwitchHidden(frame, true) then
        self:Undeafen()
        return false
    end
    self.buffered = true
    frame.spokenFrozen = true
    Transcript:Hold()
    for _, part in ipairs(Parts(self)) do
        if part.SetIgnoreParentAlpha then part:SetIgnoreParentAlpha(true) end
    end
    self:SetLevel(self.level or 0)
    return true
end

--- Itself again, and catching up on what waited: the captions, and an update or a refresh.
function Skin:Unbuffer()
    if not self.buffered then return end
    self.buffered = nil
    for _, part in ipairs(Parts(self)) do
        if part.SetIgnoreParentAlpha then part:SetIgnoreParentAlpha(false) end
    end
    SwitchHidden(self.frame, false)
    self:Undeafen()
    self:SetLevel(self.level or 0)
    -- Moved onto or off DialogueUI's window meanwhile (Addon:ApplyHost): now.
    self.frame.spokenFrozen = nil
    if self.frame.spokenHostPending then
        self.frame.spokenHostPending = nil
        Addon:ApplyHost(self.frame)
    end
    Transcript:Release()
    local pending = self.pending
    self.pending = nil
    if pending == "refresh" then self:RefreshConfig()
    elseif pending == "update" then self:Update() end
end

--- What is on the paper: its share of the window's fade, times a new line's own fade-in.
function Skin:PaintContent()
    local line = self.lineFade and Clamp(self.lineFade / LINE_IN, 0, 1) or 1
    self.content:SetAlpha(Clamp((self.level or 0) * 2 - 1, 0, 1) * (1 - (1 - line) * (1 - line)))
end

function Skin:SetVisible(visible, immediate)
    if not self.frame then return end
    if not visible then self:HideTooltip() end
    if immediate then
        self:StopTuck()
        self:StopLanding()
        self:HideGhost()
        self.wanted, self.preparing, self.arming, self.fadeTime, self.pending = false, nil, nil, nil, nil
        self.frame:Hide()
        self:Unbuffer()
        self:Undeafen()
        Transcript:Release()
        self:SetLevel(0)
        return
    end
    if self.wanted == visible then return end
    self.wanted = visible
    if visible then
        self.arming = nil
        if self.buffered or (self.frame:IsShown() and (self.level or 0) > 0) then
            -- Fading out, or still on screen: back up from where it is, as it is.
            if not self.buffered then self:Undeafen(); Transcript:Release() end
            self.fadeFrom, self.fadeTime = self.level or 0, 0
            return
        end
        -- From nothing: laid out unseen, then once it is still, faded in as one image (Skin:Tick).
        self:SetLevel(0)
        self.frame:Show()
        self.preparing, self.fadeTime = true, nil
        return
    end
    if self.preparing or not self.frame:IsShown() or (self.level or 0) <= 0 then
        -- Never seen: gone at once.
        self.preparing, self.fadeTime = nil, nil
        self.frame:Hide()
        self:SetLevel(0)
        return
    end
    if self.buffered then
        -- Fading in as one image: back out the same way.
        self.fadeFrom, self.fadeTime = self.level or 0, 0
        return
    end
    -- On screen: deaf to the pointer first, so a click's pressed and lit states settle, then one
    -- image once it is still (Skin:Tick). Its words held from now, so they fade out with it.
    self:Deafen()
    Transcript:Hold()
    self.arming, self.fadeTime = { waited = 0, frames = 0 }, nil
end

--- Start the fade, as one image where the client can draw one.
function Skin:StartFade()
    self:Buffer()
    self.fadeFrom, self.fadeTime = self.level or 0, 0
end

--- After the title, as the subtitle has them: "• (Stopped)" while the line is stopped, and the
--- lines waiting behind it, "• +N". One more fades the count in; Stopped fades in and out, and
--- keeps its room until it has faded. The title is cut short, not these.
function Skin:Count(waiting)
    local count, stopped = self.count, self.stopped
    if waiting ~= self.counted then
        if waiting > (self.counted or 0) then self.countFade = 0 end
        self.counted = waiting
        count:SetText(waiting > 0 and "• +" .. waiting or "")
    end
    local tail = {}
    local stoppedShown = self.shownStopped or self.stoppedAlpha > 0
    stopped:SetShown(stoppedShown)
    if stoppedShown then table.insert(tail, stopped) end
    count:SetShown(waiting > 0)
    if waiting > 0 then table.insert(tail, count) end
    local room = 0
    for _, part in ipairs(tail) do room = room + (part:GetStringWidth() or 0) + COUNT_GAP end
    local text = self.title.text
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT")
    text:SetPoint("BOTTOMRIGHT", -room, 0)
    if #tail == 0 then return end
    local x = math.min(text:GetStringWidth() or 0, math.max(0, (self.title:GetWidth() or 0) - room))
    for _, part in ipairs(tail) do
        part:ClearAllPoints()
        part:SetPoint("LEFT", text, "LEFT", x + COUNT_GAP, 0)
        x = x + COUNT_GAP + (part:GetStringWidth() or 0)
    end
    self:PaintCount()
end

local function EaseOut(t) return 1 - (1 - t) * (1 - t) end

function Skin:PaintCount()
    self.count:SetAlpha(EaseOut(self.countFade and Clamp(self.countFade / COUNT_IN, 0, 1) or 1))
    self.stopped:SetAlpha(EaseOut(self.stoppedAlpha))
end

function Skin:Tick(elapsed)
    -- Landing from the frame after it lands, so it touches down where it rests.
    if self.landing then self:LandStep(elapsed) end
    if self.settling then self:SettleStep(elapsed) end
    self.stillFor = (self.stillFor or 0) + elapsed
    -- Waiting to be still before it becomes one image: in, laid out unseen; out, deaf to the pointer.
    if self.preparing and self:Still() then
        self.preparing = nil
        self:StartFade()
    end
    local arming = self.arming
    if arming then
        arming.frames, arming.waited = arming.frames + 1, arming.waited + elapsed
        if (arming.frames >= ARM_FRAMES and self:Still()) or arming.waited >= ARM_MOST then
            self.arming = nil
            self:StartFade()
        end
    end
    if self.countFade then
        self.countFade = self.countFade + elapsed
        self:PaintCount()
        if self.countFade >= COUNT_IN then self.countFade = nil end
    end
    local stoppedWant = self.shownStopped and 1 or 0
    if self.stopped and self.stoppedAlpha ~= stoppedWant then
        local step = elapsed / COUNT_IN
        self.stoppedAlpha = stoppedWant > self.stoppedAlpha and math.min(1, self.stoppedAlpha + step)
            or math.max(0, self.stoppedAlpha - step)
        self:PaintCount()
        -- Faded out: its room given back.
        if self.stoppedAlpha == 0 then self:Count(self.counted or 0) end
    end
    if self.lineFade then
        self.lineFade = self.lineFade + elapsed
        if self.lineFade >= LINE_IN then self.lineFade = nil end
        self:PaintContent()
    end
    local want = self.heightWant
    if want then
        local height = self.frame:GetHeight()
        height = height + (want - height) * math.min(1, elapsed * SIZE_EASE)
        if math.abs(want - height) < .5 then height, self.heightWant = want, nil end
        self.frame:SetHeight(height)
    end
    if self.fadeTime then
        self.fadeTime = self.fadeTime + elapsed
        local t = Clamp(self.fadeTime / (self.wanted and FADE_IN or FADE_OUT), 0, 1)
        local eased = t * t * (3 - 2 * t)
        self:SetLevel(self.fadeFrom + ((self.wanted and 1 or 0) - self.fadeFrom) * eased)
        if t == 1 then
            self.fadeTime = nil
            if not self.wanted then
                self.frame:Hide()
                self:Undeafen()
            end
            -- Faded: itself again, catching up on what waited.
            self:Unbuffer()
            if not self.wanted then return end
        end
    end
    -- Nothing in it changes while it is one image, nor while it waits to be one.
    if not self.wanted or self.buffered or self.preparing or self.arming then return end
    if StaticPortrait:Resolved() then self:ConfigurePortrait() end
    self:UpdateProgress()
    self.poll = (self.poll or 0) + elapsed
    if self.poll >= .2 then
        self.poll = 0
        self:UpdateControls()
    end
end

--- How far the paper's visible edge reaches past the frame's left and top, in the frame's units:
--- its caps are centred on the frame's ends and wider than it, inside a transparent margin.
function Skin:PaperOverhang()
    local cap = self.parchments and self.parchments[1]
    local paperWidth, capHeight = cap and cap:GetWidth() or 0, cap and cap:GetHeight() or 0
    local look = self.look or LOOKS.quest
    return math.max(0, (paperWidth - self.frame:GetWidth()) / 2 - look.paperLeft / 1024 * paperWidth),
        math.max(0, capHeight * (0.5 - look.paperTop / 256))
end

--- The screen's top left, EDGE from the paper: where the window settles when DialogueUI's
--- window closes on a line that plays on (Skin:Settle), out of the way of the next dialog.
function Skin:PlaceDefault()
    local frame = self.frame
    -- In the frame's own units: its effective scale is UIParent's times its base scale.
    local k = 1 / (frame.spokenBaseScale or 1)
    local left, top = self:PaperOverhang()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", Round(EDGE * k + left), -Round(EDGE * k + top))
end

--- Where the window rests, its top left in the screen's pixels: where it was dragged to, or the
--- screen's top left (PlaceDefault). Worked out rather than read off the frame, which has no
--- place on screen while DialogueUI hides the interface.
function Skin:Home()
    local frame = self.frame
    local ui = UIParent:GetEffectiveScale()
    local scale = ui * (frame.spokenBaseScale or 1)
    local saved = Addon:Layout().DialogueUI
    if type(saved) == "table" and saved.left and saved.top then
        return saved.left * scale, saved.top * scale
    end
    local left, top = self:PaperOverhang()
    return EDGE * ui + left * scale, UIParent:GetHeight() * ui - EDGE * ui - top * scale
end

--- DialogueUI's quest window or book view closed while its line plays on: this window takes the
--- dialog's place, size and height, then shrinks to its own size and height as it moves to where
--- it rests, DialogueUI's opening in reverse. Closed while another line plays, this window comes
--- back as it is, and a line the dialog queued goes behind it (Skin:StartTuck). Not while it sits
--- on the dialog (Show Spoken Over DialogueUI): it is in place already. Should anything fail, it
--- is simply put where it rests.
function Skin:Settle(dialog)
    local frame = self.frame
    if not (self:IsEnabled() and PlayerFrame:Current()) or frame:GetParent() ~= UIParent then return end
    -- Fading as one image: it finishes, then shows the line as it does any (Skin:Unbuffer).
    if self.buffered then self.pending = self.pending or "update"; return end
    self:StopTuck()
    self:StopLanding()
    self.arming, self.preparing = nil, nil
    self:Undeafen()
    -- The dialog drawn again where it was, to dissolve rather than vanish.
    local drawn = false
    local last = self.captures and self.captures[dialog]
    local look = self.drawGhost and self:ClosingLook(dialog) or nil
    local okGhost, shown = pcall(self.ShowGhost, self, dialog, look, PlayerFrame:Current())
    if okGhost then drawn = shown else self:HideGhost() end
    -- For /spoken ghost: what this close had to go on, and what came of it.
    self.lastClose = { dialog = dialog:GetName() or "?", read = last and table.getn(last) or 0,
        closing = look and table.getn(look) or 0, drawn = drawn and true or false,
        problem = not okGhost and tostring(shown) or nil, owns = self:Owns(dialog) }
    if not self:Owns(dialog) then
        local queued = self:QueuedBy(dialog)
        self:Update()
        if queued then
            local ok, err = pcall(self.StartTuck, self, dialog, queued, drawn)
            if not ok then
                self:StopTuck()
                if geterrorhandler then geterrorhandler()(err) end
            end
        end
        return
    end
    local ok, err = pcall(self.StartSettle, self, dialog)
    if not ok then
        self.settling = nil
        frame:SetScale(frame.spokenBaseScale or 1)
        if not Addon:RestoreLayout("DialogueUI", frame) then self:PlaceDefault() end
        self:Layout()
        if geterrorhandler then geterrorhandler()(err) end
    end
end

--- The dialog's middle and top, width and height in UIParent's units, and how large DialogueUI's
--- units are in them. The quest window's from where DialogueUI puts it: it has no place on screen
--- to read while it hides the interface. The book view's from its frame, which keeps its place as
--- it hides: its paper is the frame.
function Skin:DialogPlace(dialog)
    local ui = UIParent:GetEffectiveScale()
    local q = dialog:GetEffectiveScale() / ui
    if dialog == _G.DUIQuestFrame then
        local x, top = Theme:WindowPlace()
        local width, height = Theme:FrameSize()
        if x and top and width and height then return x, top, width * q, height * q, q end
        return nil
    end
    local left, bottom, w, h = dialog:GetRect()
    if left and bottom and w and h then
        return (left + w / 2) * q, (bottom + h) * q, w * q, h * q, q
    end
    return nil
end

function Skin:StartSettle(dialog)
    local frame = self.frame
    self:Update()
    local ui = UIParent:GetEffectiveScale()
    local x, top, width, height = self:DialogPlace(dialog)
    if not (x and top and width and frame:GetWidth() > 0) then error("DialogueUI's window has no place") end
    -- Its own scale, and the one at which it is drawn as wide as the dialog.
    local to = frame.spokenBaseScale or 1
    local from = width / frame:GetWidth()
    local toLeft, toTop = self:Home()
    local left = (x - width / 2) * ui
    local bendX, bendY = BowOf(left, top * ui, toLeft, toTop, SETTLE_BOW)
    self.settling = { time = 0, from = from, to = to,
        left = left, top = top * ui, height = height * ui, toLeft = toLeft, toTop = toTop, bendX = bendX, bendY = bendY,
        width = width * ui, ghost = self.ghost ~= nil and self.ghost:IsShown() }
    if self.settling.ghost then self.ghost.driven = true end
    -- In full at once, where the dialog was: no fade.
    self.wanted, self.fadeTime = true, nil
    self:SetLevel(1)
    frame:Show()
    self:SettleStep(0)
end

--- The header's round buttons as large on screen as they settle at: while the window slides out
--- of the dialog at a larger scale, against that scale, whichever of the slide and a layout set
--- them last in a frame.
function Skin:FitControls()
    if not self.controlsRound then return end
    local settling = self.settling
    local now = self.frame:GetScale() or 1
    self:ScaleControls(self.controlsRound * (settling and now > 0 and settling.to / now or 1))
end

--- The header's round buttons at `scale` of the window's, their anchor's offset in their own.
function Skin:ScaleControls(scale)
    self.controls:SetScale(scale)
    self.controls:ClearAllPoints()
    self.controls:SetPoint("RIGHT", self.content, "TOPRIGHT", 0, -(self.controlsMiddle or 0) / scale)
end

--- The window lifted off the dialog, a touch larger and its shadow thrown, the dialog drawn again
--- over it dissolving into it (Skin:ShowGhost); flown to where it rests on a curve, shrinking to its
--- own size and height, its shadow drawn in; then landing (Skin:LandStep).
function Skin:SettleStep(elapsed)
    local settling, frame = self.settling, self.frame
    settling.time = settling.time + elapsed
    local t = settling.time
    local lift = Smooth(Clamp(t / SETTLE_LIFT, 0, 1))
    local u = Clamp((t - SETTLE_LIFT) / SETTLE_TIME, 0, 1)
    local eased = EaseInOut(u)
    local function Toward(a, b) return a + (b - a) * eased end
    local ui = UIParent:GetEffectiveScale()
    -- Grown about its middle as it is lifted, back to size as it lands.
    local grow = 1 + SETTLE_GROW * lift * (1 - eased)
    local base = Toward(settling.from, settling.to)
    local scale = base * grow
    frame:SetScale(scale)
    -- The round buttons stay as large on screen as they settle at, as the dialog's own are, rather
    -- than starting at the dialog's larger scale with the rest.
    self:FitControls()
    local pixels = ui * scale
    local toHeight = (self.settledHeight or frame:GetHeight()) * ui * settling.to
    local height = Toward(settling.height, toHeight)
    local width = (frame:GetWidth() or 0) * ui * base
    local left = Bend(settling.left, settling.bendX or settling.left, settling.toLeft, eased) - (grow - 1) * width / 2
    local top = Bend(settling.top, settling.bendY or settling.top, settling.toTop, eased) + (grow - 1) * height / 2
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / pixels, top / pixels)
    frame:SetHeight(height * grow / pixels)
    -- Its shadow thrown as it is lifted, drawn in as it comes down.
    self:ShadowUnder((1 - 0.7 * eased) * lift, 0.5 * lift * (1 - 0.3 * eased))
    -- The dialog drawn again over it, moving with it and handing over to it (Skin:Morph).
    if settling.ghost then
        local f = width * grow / math.max(1, settling.width)
        local ghost = self.ghost
        local fromLeft, fromTop = settling.left, settling.top
        self:MoveGhost(left - f * fromLeft, top - f * fromTop, f)
        self:Morph(t, elapsed)
    end
    if u == 1 then
        self.settling = nil
        if settling.ghost then self:HideGhost() end
        frame:SetScale(settling.to)
        if not Addon:RestoreLayout("DialogueUI", frame) then self:PlaceDefault() end
        self:Layout()
        self.landing = { time = 0 }
    end
end

--- Landed where it rests: giving under it and back as it touches down, its shadow drawn in.
function Skin:LandStep(elapsed)
    local landing = self.landing
    landing.time = landing.time + elapsed
    local t = landing.time
    self:Give(landing, -SETTLE_GIVE * math.exp(-7 * t) * math.sin(2 * math.pi * t / 0.3))
    local shadow = 1 - Smooth(Clamp(t / 0.25, 0, 1))
    self:ShadowUnder(0.3 * shadow, 0.35 * shadow)
    if t >= LAND_TIME then self:StopLanding() end
end

function Skin:StopLanding()
    local landing = self.landing
    self.landing = nil
    if self.shadow then self.shadow:Hide() end
    if landing then self:Rest(landing) end
end

--- This window's own shadow, `reach` of the way thrown (down and right) and `alpha` dark: a frame
--- of its own under it, never part of it.
function Skin:ShadowUnder(reach, alpha)
    local frame = self.frame
    local shadow = self.shadow
    if not shadow then
        shadow = CreateFrame("Frame", nil, UIParent)
        shadow:EnableMouse(false)
        shadow.texture = shadow:CreateTexture(nil, "BACKGROUND")
        shadow.texture:SetAllPoints()
        self.shadow = shadow
    end
    if alpha <= 0.001 then shadow:Hide(); return end
    shadow.texture:SetTexture(Theme:TexturePath() .. "Settings-BackgroundShadow.png")
    shadow:SetFrameStrata(frame:GetFrameStrata())
    shadow:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    local dx, dy, blur = 8 * reach, -12 * reach, 18
    shadow:ClearAllPoints()
    shadow:SetPoint("TOPLEFT", frame, "TOPLEFT", dx - blur, dy + blur)
    shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", dx + blur, dy - blur)
    shadow:SetAlpha(alpha)
    shadow:Show()
end

--- This window moved `offset` (UIParent's units, up) off where it rests, and back (Skin:Rest).
function Skin:Give(state, offset)
    local frame = self.frame
    if not state.rest then
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
        if not point then return end
        state.rest = { point, relativeTo, relativePoint, x, y }
    end
    local rest = state.rest
    frame:ClearAllPoints()
    frame:SetPoint(rest[1], rest[2], rest[3], rest[4], rest[5] + offset / (frame:GetScale() or 1))
end

function Skin:Rest(state)
    if not state.rest then return end
    state.rest = nil
    if not Addon:RestoreLayout("DialogueUI", self.frame) then self:PlaceDefault() end
end

---------------------------------------------------------------- the dialog, drawn again as it closes
-- DialogueUI's dialog and this window lay out the same line differently (its title, paragraphs,
-- buttons and pages), so this window taking its place showed all of that change at once. Instead
-- the dialog is drawn again as it closes, whole, by frames of this window's own, and changes from
-- there: its parts are read off it while it is open (every CAPTURE_EVERY) and as it closes
-- (Skin:Capture), and drawn where they were (Skin:ShowGhost), over everything. What both have
-- (the title, the face, the round buttons, the start of the words) then travels to where this
-- window has it and hands over to it; what only the dialog has (objectives, its buttons, the rest
-- of its words) sinks a little and fades first; its paper, this window's too, dissolves into this
-- window's. It has no parent, so it shows while DialogueUI still hides the interface, and its
-- paper waits for the interface to come back: the world never shows through between the two.
-- Models are left out (they cannot be copied), as are parts lit only under the pointer.
local GHOST_FADE, CAPTURE_EVERY = .3, .25
local LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true }
local UNCOPIED = { Model = true, PlayerModel = true, DressUpModel = true, CinematicModel = true, TabardModel = true,
    ModelScene = true, Browser = true, MovieFrame = true }
-- The settle's handover, in seconds from the dialog closing: what only the dialog has gone by
-- MORPH_SINK, sinking SINK_DROP; what both have travelling MORPH_FROM to MORPH_TO, then handing
-- over to this window's own by MORPH_SWAP; the dialog's paper dissolving from PAPER_FROM.
local MORPH_SINK, SINK_DROP, MORPH_FROM, MORPH_TO, MORPH_SWAP, PAPER_FROM = .18, 6, .04, .46, .58, .2

-- A texture's rotation, read (no `angle`) or set. Run with the game's own globals as its
-- environment: the client answers GetRotation with a Vector2D too, whose mixin it looks up in the
-- caller's environment, and this file's has none ("unable to find mixin or metatable").
local Rotation = setfenv(function(region, angle)
    if angle == nil then return (region:GetRotation()) end
    region:SetRotation(angle)
end, getfenv(0))

-- Where two clipping rectangles overlap ({ left, bottom, width, height }), either may be nil.
local function Overlap(a, b)
    if not a then return b end
    if not b then return a end
    local left, bottom = math.max(a[1], b[1]), math.max(a[2], b[2])
    local right, top = math.min(a[1] + a[3], b[1] + b[3]), math.min(a[2] + a[4], b[2] + b[4])
    return { left, bottom, math.max(0, right - left), math.max(0, top - bottom) }
end

-- Text as read, without colour codes or runs of space, to tell one line from another.
local function Plain(text)
    text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " ")
    return (text:gsub("^ ", ""):gsub(" $", ""))
end

--- The dialog's visible parts: each texture's art and each line of text's words, font and colours,
--- where it is (in its own frame's units, with that frame's scale), its alpha against the dialog's,
--- its layer and its frame's level, the rectangle a scroll frame clips it to, and what it is where
--- that is known: a round button's kind (Spoken:CreateRoundButton marks them), the face.
function Skin:Capture(dialog)
    local parts = {}
    local rootAlpha = dialog.GetEffectiveAlpha and dialog:GetEffectiveAlpha() or dialog:GetAlpha() or 1
    rootAlpha = math.max(0.01, rootAlpha or 1)
    local front = type(dialog.FrontFrame) == "table" and dialog.FrontFrame
    local face = front and type(front.Header) == "table" and front.Header.Portrait
    local function Copy(region, frame, clip, tag)
        local kind = region.GetObjectType and region:GetObjectType()
        if (kind ~= "FontString" and kind ~= "Texture") or not region:IsShown() then return end
        local layer, sublevel = region:GetDrawLayer()
        if not LAYERS[layer or ""] then return end
        local left, bottom, width, height = region:GetRect()
        if not (left and bottom and width and height) or width <= 0 or height <= 0 then return end
        local alpha = region.GetEffectiveAlpha and region:GetEffectiveAlpha() or region:GetAlpha() or 1
        alpha = math.min(1, (alpha or 1) / rootAlpha)
        if alpha <= 0.01 then return end
        local part = { kind = kind, left = left, bottom = bottom, width = width, height = height,
            scale = frame:GetEffectiveScale() or 1, alpha = alpha, layer = layer, sublevel = sublevel or 0,
            level = frame:GetFrameLevel() or 0, clip = clip, tag = tag }
        if region == face then part.tag = "face" end
        if kind == "FontString" then
            local text = region:GetText()
            local fontFace, size, flags = region:GetFont()
            if not text or text == "" or not fontFace then return end
            part.text, part.font = text, { fontFace, size, flags or "" }
            part.color = { region:GetTextColor() }
            part.shadow = { region:GetShadowColor() }
            part.shadowOffset = { region:GetShadowOffset() }
            part.justifyH, part.justifyV = region:GetJustifyH(), region:GetJustifyV()
            part.spacing = region.GetSpacing and region:GetSpacing() or 0
            part.wrap = region.CanWordWrap and region:CanWordWrap()
            part.maxLines = region.GetMaxLines and region:GetMaxLines() or 0
        else
            local atlas = region.GetAtlas and region:GetAtlas()
            local file = region:GetTexture()
            if not atlas and not file then return end
            part.atlas, part.file = atlas, file
            part.coords = { region:GetTexCoord() }
            part.color = { region:GetVertexColor() }
            part.blend = region:GetBlendMode()
            part.desaturated = region.IsDesaturated and region:IsDesaturated() or false
            part.rotation = region.GetRotation and Rotation(region) or 0
            -- What cuts it to shape (a portrait's circle, a button's brushed edge), where it is.
            local count = region.GetNumMaskTextures and region:GetNumMaskTextures() or 0
            for index = 1, count do
                local mask = region:GetMaskTexture(index)
                local maskFile = mask and mask:GetTexture()
                local ml, mb, mw, mh
                if mask then ml, mb, mw, mh = mask:GetRect() end
                if maskFile and ml and mb and mw and mh then
                    local owner = mask:GetParent()
                    local maskScale = owner and owner.GetEffectiveScale and owner:GetEffectiveScale() or part.scale
                    part.masks = part.masks or {}
                    table.insert(part.masks, { file = maskFile, left = ml * maskScale, bottom = mb * maskScale,
                        width = mw * maskScale, height = mh * maskScale })
                end
            end
        end
        table.insert(parts, part)
    end
    local function Walk(frame, clip, tag)
        if frame.IsForbidden and frame:IsForbidden() then return end
        if UNCOPIED[frame:GetObjectType() or ""] then return end
        if frame ~= dialog and not frame:IsShown() then return end
        if frame.spokenRound then tag = "round:" .. frame.spokenRound end
        if (frame.DoesClipChildren and frame:DoesClipChildren()) or frame:GetObjectType() == "ScrollFrame" then
            local left, bottom, width, height = frame:GetRect()
            if left and bottom and width and height then
                local scale = frame:GetEffectiveScale() or 1
                clip = Overlap(clip, { left * scale, bottom * scale, width * scale, height * scale })
            end
        end
        local regions = { frame:GetRegions() }
        for index = 1, table.getn(regions) do Copy(regions[index], frame, clip, tag) end
        local children = { frame:GetChildren() }
        for index = 1, table.getn(children) do Walk(children[index], clip, tag) end
    end
    Walk(dialog, nil, nil)
    local left, bottom, width = dialog:GetRect()
    parts.width = (width or 0) * (dialog:GetEffectiveScale() or 1)
    return parts
end

--- Read the open dialog every CAPTURE_EVERY, so its look as it closes is known whichever of it
--- and its parts hears of the closing first. A failure is said once, not every time.
function Skin:CaptureTick(dialog, elapsed)
    if not self.drawGhost then return end
    self.captureWait = (self.captureWait or 0) - elapsed
    if self.captureWait > 0 or not (self:IsEnabled() and self.frame and self.frame:GetParent() == UIParent) then return end
    self.captureWait = CAPTURE_EVERY
    self.captureCount = self.captureCount or {}
    self.captureCount[dialog] = (self.captureCount[dialog] or 0) + 1
    local ok, parts = pcall(self.Capture, self, dialog)
    if ok then
        self.captures[dialog] = parts
    else
        self.captureProblem = tostring(parts)
        if not self.captureSaid then
            self.captureSaid = true
            if geterrorhandler then geterrorhandler()(parts) end
        end
    end
end

--- The dialog's look as it closes: read again now, unless it has already let go of its parts (it
--- clears its pages as it hides), when the last reading stands.
function Skin:ClosingLook(dialog)
    local last = self.captures and self.captures[dialog]
    if self.captures then self.captures[dialog] = nil end
    local ok, now = pcall(self.Capture, self, dialog)
    if ok and now and table.getn(now) >= 0.8 * table.getn(last or {}) then return now end
    return last
end

--- What each part is to the handover: a tag this window has a match for (its title, the start of
--- its words, the face, a round button), the dialog's paper and its wide lines (this window has its
--- own), or what only the dialog has.
local function Sort(parts, clip)
    local title = Plain(clip and Label(clip))
    local present = clip and clip.present
    local words = Plain(present and present.transcript or clip and clip.text):sub(1, 24)
    local titled, worded = false, false
    for _, part in ipairs(parts) do
        local plain = part.text and Plain(part.text)
        if not part.tag and plain and not titled and title ~= "" and plain == title then
            part.tag, titled = "title", true
        elseif not part.tag and plain and not worded and words ~= "" and plain:sub(1, string.len(words)) == words then
            part.tag, worded = "words", true
        end
        if part.tag then
            part.group = part.tag
        elseif part.kind == "Texture" and (parts.width or 0) > 0 and part.width * part.scale >= 0.4 * parts.width then
            part.group = "paper"
        else
            part.group = "only"
        end
    end
end

--- Draw `parts` where they were, over everything; `clip` is the line they showed, which tells
--- its title and words among them.
function Skin:ShowGhost(dialog, parts, clip)
    if not parts or table.getn(parts) == 0 then return false end
    local ghost = self.ghost
    if not ghost then
        ghost = CreateFrame("Frame")
        ghost:SetSize(1, 1)
        ghost:EnableMouse(false)
        ghost.frames, ghost.textures, ghost.texts = {}, {}, {}
        -- What only the dialog has, and its paper: each faded and moved as one.
        ghost.only = CreateFrame("Frame", nil, ghost)
        ghost.paper = CreateFrame("Frame", nil, ghost)
        for _, layer in ipairs({ ghost.only, ghost.paper }) do
            layer:SetSize(1, 1)
            layer:EnableMouse(false)
        end
        -- Left alone (a dialog closing on another line, nothing queued), it dissolves in place.
        ghost:SetScript("OnUpdate", function(_, elapsed) self:GhostStep(elapsed) end)
        self.ghost = ghost
    end
    for _, list in ipairs({ ghost.frames, ghost.textures, ghost.texts }) do
        for _, item in ipairs(list) do item:Hide() end
    end
    Sort(parts, clip)
    -- Over everything this window and DialogueUI draw.
    ghost:SetFrameStrata("FULLSCREEN_DIALOG")
    for _, layer in ipairs({ ghost.only, ghost.paper }) do
        layer:SetScale(1)
        layer:ClearAllPoints()
        layer:SetPoint("BOTTOMLEFT", ghost, "BOTTOMLEFT", 0, 0)
        layer:SetAlpha(1)
    end
    -- Each of the dialog's frame levels its own frame, in their order, inside the frame clipping
    -- them where a scroll frame clipped them; each matched thing a frame of its own, to move.
    local levels, order = {}, {}
    for _, part in ipairs(parts) do
        if not levels[part.level] then levels[part.level] = true; table.insert(order, part.level) end
    end
    table.sort(order)
    local rank = {}
    for index, level in ipairs(order) do rank[level] = index end
    local base = ghost:GetFrameLevel() or 1
    local frames, used, holders, clips = ghost.frames, 0, {}, {}
    local function NewFrame(parent)
        used = used + 1
        local frame = frames[used]
        if not frame then
            frame = CreateFrame("Frame", nil, parent)
            frame:EnableMouse(false)
            frames[used] = frame
        end
        frame:SetParent(parent)
        frame:SetScale(1)
        frame:SetAlpha(1)
        frame:SetClipsChildren(false)
        frame:ClearAllPoints()
        frame:Show()
        frame.masksUsed = 0
        return frame
    end
    ghost.groups = {}
    local function Holder(part)
        local layer = part.group == "paper" and ghost.paper or ghost.only
        local tagged = part.group ~= "paper" and part.group ~= "only"
        local key = tagged and part.group or (part.group .. ":" .. tostring(part.clip) .. ":" .. part.level .. ":" .. part.scale)
        if holders[key] then return holders[key] end
        local parent = tagged and ghost or layer
        if part.clip and not tagged then
            local clipKey = part.group .. ":" .. tostring(part.clip)
            parent = clips[clipKey]
            if not parent then
                parent = NewFrame(layer)
                parent:SetClipsChildren(true)
                parent:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", part.clip[1], part.clip[2])
                parent:SetSize(math.max(1, part.clip[3]), math.max(1, part.clip[4]))
                parent:SetFrameLevel(base + 1)
                clips[clipKey] = parent
            end
        end
        local holder = NewFrame(parent)
        holder:SetScale(part.scale)
        holder:SetSize(1, 1)
        holder:SetPoint("BOTTOMLEFT", tagged and ghost or layer, "BOTTOMLEFT", 0, 0)
        holder:SetFrameLevel(base + 1 + rank[part.level] + (tagged and table.getn(order) or 0))
        holder.tag = tagged and part.group or nil
        if tagged then
            holder.left, holder.bottom, holder.right, holder.top = math.huge, math.huge, -math.huge, -math.huge
            holder.scale = part.scale
            ghost.groups[part.group] = holder
        end
        holders[key] = holder
        return holder
    end
    -- Matched things' bounds first, so their parts sit in their frame from its corner.
    for _, part in ipairs(parts) do
        local holder = Holder(part)
        if holder.tag then
            holder.left, holder.bottom = math.min(holder.left, part.left), math.min(holder.bottom, part.bottom)
            holder.right = math.max(holder.right, part.left + part.width)
            holder.top = math.max(holder.top, part.bottom + part.height)
            if part.text then holder.text, holder.fontSize, holder.justifyH = part.text, part.font[2], part.justifyH end
        end
    end
    local textures, texts, usedTextures, usedTexts = ghost.textures, ghost.texts, 0, 0
    for _, part in ipairs(parts) do
        local holder = Holder(part)
        local region
        if part.kind == "FontString" then
            usedTexts = usedTexts + 1
            region = texts[usedTexts]
            if not region then region = holder:CreateFontString(nil, "ARTWORK"); texts[usedTexts] = region end
            region:SetParent(holder)
            region:SetFont(part.font[1], part.font[2], part.font[3])
            region:SetTextColor(part.color[1] or 1, part.color[2] or 1, part.color[3] or 1, part.color[4] or 1)
            region:SetShadowColor(part.shadow[1] or 0, part.shadow[2] or 0, part.shadow[3] or 0, part.shadow[4] or 0)
            region:SetShadowOffset(part.shadowOffset[1] or 0, part.shadowOffset[2] or 0)
            region:SetJustifyH(part.justifyH or "CENTER")
            region:SetJustifyV(part.justifyV or "MIDDLE")
            region:SetSpacing(part.spacing or 0)
            region:SetWordWrap(part.wrap and true or false)
            if region.SetMaxLines then region:SetMaxLines(part.maxLines or 0) end
            region:SetText(part.text)
            if holder.tag then holder.textRegion = region end
        else
            usedTextures = usedTextures + 1
            region = textures[usedTextures]
            if not region then region = holder:CreateTexture(nil, "ARTWORK"); textures[usedTextures] = region end
            region:SetParent(holder)
            if part.atlas then
                region:SetAtlas(part.atlas, false)
            else
                region:SetTexture(part.file)
            end
            local c = part.coords
            if table.getn(c) == 8 then
                region:SetTexCoord(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
            elseif table.getn(c) == 4 then
                region:SetTexCoord(c[1], c[2], c[3], c[4])
            end
            region:SetVertexColor(part.color[1] or 1, part.color[2] or 1, part.color[3] or 1, part.color[4] or 1)
            region:SetBlendMode(part.blend or "BLEND")
            region:SetDesaturated(part.desaturated and true or false)
            if region.SetRotation then Rotation(region, part.rotation or 0) end
        end
        -- Placed from its frame's corner: a matched thing's own, else the dialog's screen corner.
        local fromLeft, fromBottom = holder.tag and holder.left or 0, holder.tag and holder.bottom or 0
        region:SetDrawLayer(part.layer, part.sublevel)
        region:ClearAllPoints()
        region:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", part.left - fromLeft, part.bottom - fromBottom)
        region:SetSize(part.width, part.height)
        region:SetAlpha(part.alpha)
        if part.kind == "Texture" then
            -- Its masks, as it had them: the last showing's taken off first.
            for _, old in ipairs(region.ghostMasks or {}) do region:RemoveMaskTexture(old) end
            region.ghostMasks = {}
            for _, shape in ipairs(part.masks or {}) do
                holder.masks = holder.masks or {}
                holder.masksUsed = (holder.masksUsed or 0) + 1
                local mask = holder.masks[holder.masksUsed]
                if not mask then
                    mask = holder:CreateMaskTexture()
                    holder.masks[holder.masksUsed] = mask
                end
                mask:SetTexture(shape.file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:ClearAllPoints()
                mask:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", shape.left / part.scale - fromLeft,
                    shape.bottom / part.scale - fromBottom)
                mask:SetSize(shape.width / part.scale, shape.height / part.scale)
                mask:Show()
                region:AddMaskTexture(mask)
                table.insert(region.ghostMasks, mask)
            end
        end
        region:Show()
    end
    ghost.time, ghost.fade, ghost.driven = 0, 0, nil
    ghost.dx, ghost.dy, ghost.f = 0, 0, 1
    self:MoveGhost(0, 0, 1)
    self:GhostLayers(1, 1, 1, 0)
    ghost:Show()
    return true
end

--- The ghost moved so the dialog's screen corner (0, 0) is at `dx`, `dy` in the screen's pixels
--- (UIParent's units times its scale), `scale` as large. Its matched things ride with it.
function Skin:MoveGhost(dx, dy, scale)
    local ghost = self.ghost
    if not ghost then return end
    scale = math.max(0.01, scale)
    ghost.dx, ghost.dy, ghost.f = dx, dy, scale
    ghost:SetScale(scale)
    ghost:ClearAllPoints()
    ghost:SetPoint("BOTTOMLEFT", WorldFrame, "BOTTOMLEFT", dx / scale, dy / scale)
    ghost:SetAlpha(1)
    for _, holder in pairs(ghost.groups or {}) do self:PlaceGroup(holder, nil, 0) end
end

--- The ghost's alphas: its paper, what only the dialog has (sunk `sink` pixels), and the matched
--- things.
function Skin:GhostLayers(paper, only, matched, sink)
    local ghost = self.ghost
    if not ghost then return end
    ghost.paper:SetAlpha(Clamp(paper, 0, 1))
    ghost.only:SetAlpha(Clamp(only, 0, 1))
    ghost.only:ClearAllPoints()
    ghost.only:SetPoint("BOTTOMLEFT", ghost, "BOTTOMLEFT", 0, -(sink or 0) / (ghost.f or 1))
    for _, holder in pairs(ghost.groups or {}) do holder:SetAlpha(Clamp(matched, 0, 1)) end
end

--- Where a matched thing goes in this window: its region, and for words, the size of their font
--- on screen there.
function Skin:GhostTarget(tag)
    if tag == "title" then return self.title and self.title.text end
    if tag == "face" then return self.portrait end
    if tag == "words" then return Transcript.frame end
    local kind = tag:match("^round:(.+)$")
    if kind == "play" then return self.play end
    if kind == "skip" then return self.skip end
    if kind == "report" then
        for _, button in ipairs(self.row or {}) do
            if button.action and button.action.id == "report" and button:IsShown() then return button end
        end
    end
    return nil
end

-- A region's rectangle in the screen's pixels.
local function ScreenRect(region)
    local left, bottom, width, height = region:GetRect()
    if not (left and bottom and width and height) then return nil end
    local scale = region.GetEffectiveScale and region:GetEffectiveScale()
        or (region:GetParent() and region:GetParent():GetEffectiveScale()) or 1
    return left * scale, bottom * scale, width * scale, height * scale, scale
end

--- A matched thing `m` of the way (0 to 1) from where it rides with the ghost to where `target`
--- is in this window, and as large there: by its font's size for words and titles, else by width.
function Skin:PlaceGroup(holder, target, m)
    local ghost = self.ghost
    local f, ps = ghost.f or 1, holder.scale or 1
    local width, height = (holder.right - holder.left) * ps * f, (holder.top - holder.bottom) * ps * f
    local fromX, fromTop = ghost.dx + holder.left * ps * f, ghost.dy + holder.top * ps * f
    local toX, toTop, grow = fromX, fromTop, 1
    if target and m > 0 then
        local tl, tb, tw, th, ts = ScreenRect(target)
        if tl then
            toX, toTop = tl, tb + th
            if holder.text then
                local _, size = target.GetFont and target:GetFont()
                if holder.tag == "words" then size = self.captionSize or size; toTop = toTop - (self.lineRoom or 0) * ts end
                if size and holder.fontSize and holder.fontSize > 0 then grow = size * ts / (holder.fontSize * ps * f) end
                -- Centred text starts where its words do, not its box.
                if holder.justifyH == "CENTER" and holder.textRegion and holder.textRegion.GetStringWidth then
                    fromX = fromX + (width - (holder.textRegion:GetStringWidth() or 0) * ps * f) / 2
                end
                if target.GetJustifyH and target:GetJustifyH() == "CENTER" and target.GetStringWidth then
                    toX = toX + (tw - (target:GetStringWidth() or 0) * ts) / 2
                end
            elseif width > 0 then
                grow = tw / width
            end
        end
    end
    local x = fromX + (toX - fromX) * m
    local top = fromTop + (toTop - fromTop) * m
    local g = 1 + (grow - 1) * m
    local own = ps * g
    holder:SetScale(own)
    holder:ClearAllPoints()
    -- Its corner at `x`, `top`: offsets in its own units, from the ghost's corner.
    local bottom = top - height * g
    holder:SetPoint("BOTTOMLEFT", ghost, "BOTTOMLEFT", (x - ghost.dx) / (f * own), (bottom - ghost.dy) / (f * own))
end

--- The handover as the window settles, `t` seconds after the dialog closed (Skin:SettleStep):
--- what only the dialog has sinking away, matched things travelling to this window's, then this
--- window's own words, title and buttons in their place; the paper last, once the interface is back.
function Skin:Morph(t, elapsed)
    local ghost = self.ghost
    if not ghost then return end
    local back = UIParent:IsShown() and (UIParent:GetAlpha() or 1) or 0
    local sink = Smooth(Clamp(t / MORPH_SINK, 0, 1))
    local m = EaseInOut(Clamp((t - MORPH_FROM) / (MORPH_TO - MORPH_FROM), 0, 1))
    local swap = Smooth(Clamp((t - MORPH_TO) / (MORPH_SWAP - MORPH_TO), 0, 1))
    ghost.fade = math.min(1, (ghost.fade or 0) + elapsed / GHOST_FADE * back * (t >= PAPER_FROM and 1 or 0))
    self:GhostLayers(1 - Smooth(ghost.fade), 1 - sink, 1 - swap, SINK_DROP * sink)
    for tag, holder in pairs(ghost.groups or {}) do
        local target = self:GhostTarget(tag)
        -- With nothing here to go to, it goes with what only the dialog had.
        if target and target:IsVisible() then
            self:PlaceGroup(holder, target, m)
        else
            holder:SetAlpha(1 - sink)
        end
    end
    -- This window's own things, under the ghost until its matched things hand over.
    if self.content then self.content:SetAlpha(swap) end
    if Transcript.frame and Transcript.frame:GetParent() ~= self.content then Transcript.frame:SetAlpha(swap) end
end

--- The ghost dissolving over GHOST_FADE, only as fast as the interface comes back (DialogueUI
--- fades it in as the dialog closes), so the world never shows through between it and this
--- window. Its alpha after `elapsed` more.
function Skin:GhostFade(elapsed)
    local ghost = self.ghost
    if not ghost then return 0 end
    local back = UIParent:IsShown() and (UIParent:GetAlpha() or 1) or 0
    ghost.fade = math.min(1, (ghost.fade or 0) + elapsed / GHOST_FADE * back)
    return 1 - Smooth(ghost.fade)
end

--- Left alone, the ghost dissolves where the dialog was: what only it had first, then the rest.
function Skin:GhostStep(elapsed)
    local ghost = self.ghost
    ghost.time = (ghost.time or 0) + elapsed
    if ghost.driven then return end
    local alpha = self:GhostFade(elapsed)
    local sink = Smooth(Clamp(ghost.time / MORPH_SINK, 0, 1))
    self:GhostLayers(alpha, math.min(alpha, 1 - sink), math.min(alpha, 1 - sink), SINK_DROP * sink)
    if alpha <= 0 or ghost.time > 5 then ghost:Hide() end
end

--- /spoken ghost: what the window knows of the dialogs and the last close. With `show`, the open
--- dialog (or the last read) drawn again where it is for four seconds.
function Skin:GhostReport(show)
    local function Say(text) print("|cff88ccffSpoken ghost:|r " .. text) end
    -- One value, whatever a call returns.
    local function S(...) local value = ...; return tostring(value) end
    if not self.frame then Say("the DialogueUI window was never built (style not DialogueUI?)") return end
    Say(format("enabled=%s window strata=%s level=%s parent=%s", S(self:IsEnabled()),
        S(self.frame:GetFrameStrata()), S(self.frame:GetFrameLevel()),
        self.frame:GetParent() == UIParent and "UIParent" or S(self.frame:GetParent() and self.frame:GetParent():GetName())))
    for _, dialog in ipairs(self.dialogs or {}) do
        local parts = self.captures and self.captures[dialog]
        Say(format("%s: shown=%s, read %d times, last reading %d parts, watch shown=%s", dialog:GetName() or "?",
            S(dialog:IsShown()), self.captureCount and self.captureCount[dialog] or 0, parts and table.getn(parts) or 0,
            S(self.dialogWatches[dialog] and self.dialogWatches[dialog]:IsVisible())))
    end
    if table.getn(self.dialogs or {}) == 0 then Say("no DialogueUI dialogs were found when the window was built") end
    if self.captureProblem then Say("reading failed: " .. self.captureProblem) end
    local close = self.lastClose
    if close then
        Say(format("last close: %s, its own line=%s, read before %d, as it closed %d, drawn=%s%s", close.dialog,
            S(close.owns), close.read, close.closing, S(close.drawn),
            close.problem and (", failed: " .. close.problem) or ""))
    else
        Say("no dialog has closed on a playing line since the reload")
    end
    local ghost = self.ghost
    if ghost then
        local point, _, _, x, y = ghost:GetPoint(1)
        local texts, textures = 0, 0
        for _, item in ipairs(ghost.texts or {}) do if item:IsShown() then texts = texts + 1 end end
        for _, item in ipairs(ghost.textures or {}) do if item:IsShown() then textures = textures + 1 end end
        Say(format("drawn again: shown=%s strata=%s level=%s scale=%.2f at %s %.0f,%.0f, %d texts %d textures, paper %.2f only %.2f",
            S(ghost:IsShown()), S(ghost:GetFrameStrata()), S(ghost:GetFrameLevel()), ghost:GetScale() or 0,
            S(point), x or 0, y or 0, texts, textures, ghost.paper:GetAlpha() or 0, ghost.only:GetAlpha() or 0))
    end
    if show then
        local dialog
        for _, candidate in ipairs(self.dialogs or {}) do
            if candidate:IsShown() then dialog = candidate end
        end
        dialog = dialog or self.dialogs and self.dialogs[1]
        if not dialog then return end
        local ok, parts = pcall(self.Capture, self, dialog)
        if not ok then Say("reading it now failed: " .. S(parts)) return end
        if table.getn(parts) == 0 then parts = self.captures and self.captures[dialog] or parts end
        local okShow, problem = pcall(self.ShowGhost, self, dialog, parts, PlayerFrame:Current())
        if not okShow then Say("drawing it failed: " .. S(problem)) return end
        self.ghost.driven = true
        Say(format("drawn again from %d parts, for four seconds", table.getn(parts)))
        C_Timer.After(4, function() self:HideGhost() end)
    end
end

--- Gone, and this window's own things all seen again.
function Skin:HideGhost()
    if self.ghost then self.ghost:Hide() end
    if self.content then self:PaintContent() end
    if Transcript.frame and self.content and Transcript.frame:GetParent() ~= self.content then Transcript.frame:SetAlpha(1) end
end

---------------------------------------------------------------- a dialog's line joining the queue
-- A dialog closing while another line plays (a gravestone read during a quest's line): its page
-- does not take this window's place, as its own line's would (Skin:Settle). The page is lifted off
-- where the dialog was, flies over to this window, bending a little as it goes, comes down low on
-- it with its foot showing under it, and slides up behind it: the line waits behind the one
-- playing. This window gives as it goes under, and its count ripples. The page is a frame of its
-- own, never part of this window, which may be one image while it fades in (Skin:Buffer); the
-- dialog drawn again (Skin:ShowGhost) dissolves into it as it is lifted.

--- A line joining the queue: when, and with which open dialog.
function Skin:Queued(clip)
    if type(clip) ~= "table" or not self.queuedAt then return end
    self.queuedAt[clip] = GetTime()
    for _, dialog in ipairs(self.dialogs) do
        if dialog:IsShown() then self.sessions[dialog][clip] = true end
    end
end

--- A dialog opening: its lines are the ones queued while it is open, and those queued just before
--- it showed (JUST_BEFORE).
function Skin:StartSession(dialog)
    local lines = setmetatable({}, { __mode = "k" })
    local now = GetTime()
    for _, clip in ipairs(SoundQueue.sounds) do
        local at = self.queuedAt[clip]
        if at and now - at <= JUST_BEFORE then lines[clip] = true end
    end
    self.sessions[dialog] = lines
end

--- Whether `dialog` queued the line playing: closing on it, this window takes the dialog's place.
function Skin:Owns(dialog)
    local lines = self.sessions and self.sessions[dialog]
    local clip = PlayerFrame:Current()
    return lines ~= nil and clip ~= nil and lines[clip] == true
end

--- The first line waiting behind the one playing that `dialog` queued.
function Skin:QueuedBy(dialog)
    local lines = self.sessions and self.sessions[dialog]
    if not lines then return nil end
    for index, clip in ipairs(SoundQueue.sounds) do
        if index > 1 and lines[clip] then return clip end
    end
    return nil
end

--- The page and the count's ripple: built once, out of this window.
function Skin:TuckFrames()
    if self.card then return self.card end
    local card = CreateFrame("Frame", nil, UIParent)
    card:Hide()
    card:EnableMouse(false)
    card.shadow = card:CreateTexture(nil, "BACKGROUND", nil, -8)
    card.strips = {}
    for index = 1, 3 do card.strips[index] = card:CreateTexture(nil, "BACKGROUND", nil, -1) end
    card.divider = card:CreateTexture(nil, "ARTWORK")
    card.title = card:CreateFontString(nil, "ARTWORK")
    card.body = card:CreateFontString(nil, "ARTWORK")
    card:SetScript("OnUpdate", function(_, elapsed) self:TuckStep(elapsed) end)
    self.card = card
    -- Its count rippling out from where it is.
    local ripple = CreateFrame("Frame", nil, UIParent)
    ripple:Hide()
    ripple:EnableMouse(false)
    ripple:SetSize(1, 1)
    ripple.text = ripple:CreateFontString(nil, "OVERLAY")
    ripple.text:SetPoint("CENTER")
    self.ripple = ripple
    return card
end

--- The page as the dialog showed it: its art, title and words, `width` by `height` in UIParent's
--- units, at `q` of DialogueUI's (its fonts' sizes are in its units). Placed as DialogueUI placed
--- them where it still says (its title and text keep their anchors when it hides), else as near.
function Skin:DressCard(card, dialog, look, clip, width, height, q)
    local present = clip.present or {}
    local file = look.file or Theme:TexturePath() .. "Parchment.png"
    local capWidth, capHeight
    if look.book then
        capWidth = width / BOOK_PAPER
        capHeight = capWidth * (look.top[2] - look.top[1]) / 1024
    else
        local paperWidth, paperHeight = Theme:ParchmentSize()
        capWidth, capHeight = paperWidth * q, paperHeight * q
    end
    card.capWidth, card.capHeight, card.look = capWidth, capHeight, look
    local strips = card.strips
    for index = 1, 3 do strips[index]:SetTexture(file) end
    strips[1]:SetTexCoord(0, 1, look.top[1] / 2048, look.top[2] / 2048)
    strips[2]:SetTexCoord(0, 1, look.middle[1] / 2048, look.middle[2] / 2048)
    strips[3]:SetTexCoord(0, 1, look.bottom[1] / 2048, look.bottom[2] / 2048)
    strips[1]:ClearAllPoints()
    strips[1]:SetPoint("CENTER", card, "TOP", 0, 0)
    strips[3]:ClearAllPoints()
    strips[3]:SetPoint("CENTER", card, "BOTTOM", 0, 0)
    strips[2]:ClearAllPoints()
    strips[2]:SetPoint("TOPLEFT", strips[1], "BOTTOMLEFT", 0, 0)
    strips[2]:SetPoint("BOTTOMRIGHT", strips[3], "TOPRIGHT", 0, -capHeight * look.under / 256)
    card.shadow:SetTexture(Theme:TexturePath() .. "Settings-BackgroundShadow.png")

    local fonts, colors = Theme:Fonts(look.book), Theme:Colors(look.palette)
    local shadow = look.shadow and 1 or 0
    local function Paint(text, face, size, color)
        text:SetFont(face, math.max(6, Round(size)), "")
        text:SetShadowColor(0, 0, 0, shadow)
        text:SetShadowOffset(1, -1)
        text:SetTextColor(color[1], color[2], color[3])
    end
    local titleSize = fonts.titleSize * q
    Paint(card.title, fonts.title, titleSize, colors.title)
    Paint(card.body, fonts.paragraph, fonts.paragraphSize * q, colors.paragraph)
    card.title:SetText(Label(clip))
    -- Its words: the line's own, which the dialog showed.
    card.body:SetText(present.transcript or clip.text or "")
    card.body:SetJustifyH("LEFT")
    card.body:SetJustifyV("TOP")
    card.body:SetSpacing(Round(0.35 * fonts.paragraphSize * q))

    -- Where DialogueUI had them, from its title's and text's anchors, else near enough.
    local function Offset(region)
        if type(region) ~= "table" or not region.GetPoint then return nil end
        local _, _, _, x, y = region:GetPoint(1)
        if type(y) == "number" then return (x or 0) * q, -y * q end
        return nil
    end
    local header = dialog.Header or (type(dialog.FrontFrame) == "table" and dialog.FrontFrame.Header)
    local headerShown = type(header) == "table" and header.IsShown and header:IsShown()
    local _, titleTop = Offset(look.book and type(header) == "table" and header.Title)
    titleTop = titleTop or math.max(96, (look.book and 90 * width / 768 or 0.07 * height))
    local column = width * 0.8
    card.title:ClearAllPoints()
    card.body:ClearAllPoints()
    card.divider:ClearAllPoints()
    card.divider:SetTexture(file)
    local bodyTop
    if look.book then
        card.title:SetPoint("TOP", card, "TOP", 0, -titleTop)
        card.title:SetWidth(column)
        card.title:SetJustifyH("CENTER")
        local lineWidth = width * 0.92
        card.divider:SetTexCoord(BOOK_DIVIDER[1], BOOK_DIVIDER[2], BOOK_DIVIDER[3], BOOK_DIVIDER[4])
        card.divider:SetSize(lineWidth, lineWidth * 32 / 768)
        card.divider:SetPoint("CENTER", card, "TOP", 0, -(titleTop + titleSize * 1.6))
        card.divider:Show()
        card.title:Show()
        bodyTop = titleTop + titleSize * 2.6
    else
        -- The quest window: its header strip's line and the title on it, on a quest page; a
        -- gossip page has neither.
        local headerWidth = headerShown and tonumber(header:GetWidth()) or 0
        local stripWidth = headerWidth > 0 and headerWidth * q or width * 358 / 624
        local stripHeight = stripWidth * 51 / 358
        local _, stripTop = Offset(headerShown and header)
        stripTop = stripTop or titleTop - stripHeight * 0.3
        local socketU = HEADER_DIVIDER[1] + (HEADER_DIVIDER[2] - HEADER_DIVIDER[1]) * SOCKET_WIDTH / HEADER_DIVIDER[5]
        local socket = stripWidth * SOCKET_WIDTH / 358
        card.divider:SetTexCoord(socketU, HEADER_DIVIDER[2], HEADER_DIVIDER[3], HEADER_DIVIDER[4])
        card.divider:SetSize(stripWidth - socket, stripHeight)
        card.divider:SetPoint("TOPLEFT", card, "TOP", -stripWidth / 2 + socket, -stripTop)
        card.title:SetPoint("LEFT", card, "TOP", -stripWidth / 2 + stripWidth * 53 / 358, -(stripTop + stripHeight / 2 - 2 * q))
        card.title:SetWidth(stripWidth * (358 - 61) / 358)
        card.title:SetJustifyH("LEFT")
        card.divider:SetShown(headerShown and true or false)
        card.title:SetShown(headerShown and true or false)
        local _, scrollTop = Offset(dialog.ScrollFrame)
        bodyTop = scrollTop or (headerShown and stripTop + stripHeight * 1.4 or 0.1 * height)
        column = width - 2 * 26 * stripWidth / 358
    end
    card.body:SetWidth(column)
    card.body:SetHeight(math.max(1, height - bodyTop - capHeight * 0.45))
    card.body:SetPoint("TOP", card, "TOP", 0, -bodyTop)
end

--- What `dialog` queued goes behind this window: `clip`'s page lifted off where the dialog was,
--- the dialog drawn again over it (`drawn`) dissolving into it.
function Skin:StartTuck(dialog, clip, drawn)
    local frame = self.frame
    local x, top, width, height, q = self:DialogPlace(dialog)
    local base = frame.spokenBaseScale or 1
    local toWidth, toHeight = frame:GetWidth() * base, (self.settledHeight or frame:GetHeight()) * base
    if not (x and top and width and toWidth > 0 and toHeight > 0) then return end
    local ui = UIParent:GetEffectiveScale()
    local left, topPx = self:Home()
    local card = self:TuckFrames()
    local look = LookOf(clip)
    self:DressCard(card, dialog, look, clip, width, height, q)
    self.tuck = { time = 0, width = width, height = height, ghost = drawn and self.ghost ~= nil,
        from = { x = x, y = top - height / 2 },
        to = { x = left / ui + toWidth / 2, y = topPx / ui - toHeight / 2, width = toWidth, height = toHeight } }
    -- Under this window, so it goes behind it.
    card:SetFrameStrata(frame:GetFrameStrata())
    card:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    card:Show()
    if self.tuck.ghost then self.ghost.driven = true end
    self:DrawTuck(self.tuck, 0)
end

function Skin:TuckStep(elapsed)
    local tuck = self.tuck
    if not tuck then
        if self.card then self.card:Hide() end
        return
    end
    tuck.time = tuck.time + elapsed
    local ok, err = pcall(self.DrawTuck, self, tuck, elapsed)
    if not ok then
        self:StopTuck()
        if geterrorhandler then geterrorhandler()(err) end
    end
end

function Skin:DrawTuck(tuck, elapsed)
    local card, from, to, t = self.card, tuck.from, tuck.to, tuck.time
    local landed = TUCK_LIFT + TUCK_FLY
    local lift = Smooth(Clamp(t / TUCK_LIFT, 0, 1))
    local fly = EaseInOut(Clamp((t - TUCK_LIFT) / TUCK_FLY, 0, 1))
    local slide = EaseOutCubic(Clamp((t - landed) / TUCK_SLIDE, 0, 1))

    -- Lifted a touch, then the window's shape at TUCK_SIZE of it, so it fits behind it; bending a
    -- little across as it flies, as paper does.
    local endScale = to.width * TUCK_SIZE / tuck.width
    local scale = 1 + 0.03 * lift + (endScale - 1.03) * fly
    local endHeight = to.height * TUCK_SIZE / endScale
    local height = math.max(tuck.height + (endHeight - tuck.height) * fly, card.capHeight * 1.05)
    local bend = 1 - 0.05 * math.sin(math.pi * fly)
    local width = tuck.width * bend
    card.strips[1]:SetSize(card.capWidth * bend, card.capHeight)
    card.strips[3]:SetSize(card.capWidth * bend, card.capHeight)

    -- Up off the dialog's place, over in an arc, down low on the window, its foot showing under
    -- it, then up behind it.
    local startX, startY = from.x, from.y + 4 * lift
    local landX, landY = to.x, to.y - to.height * TUCK_LOW
    local distance = math.sqrt((landX - startX) * (landX - startX) + (landY - startY) * (landY - startY))
    local bendX, bendY = (startX + landX) / 2, math.max(startY, landY) + 0.3 * distance
    local x, y = Bend(startX, bendX, landX, fly), Bend(startY, bendY, landY, fly)
    y = y + (to.y - landY) * slide
    card:SetScale(scale)
    card:SetSize(width, height)
    card:ClearAllPoints()
    card:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)

    -- Its words go first, then its title: a page in the queue, not one to read.
    card.body:SetAlpha(1 - Smooth(Clamp((t - 0.08) / 0.3, 0, 1)))
    local heading = 1 - Smooth(Clamp((t - 0.22) / 0.36, 0, 1))
    card.title:SetAlpha(heading)
    card.divider:SetAlpha(heading)
    local away = 1 - Smooth(Clamp((t - landed - TUCK_SLIDE * 0.3) / (TUCK_SLIDE * 0.7), 0, 1))
    -- The dialog drawn again over it, moving with it and dissolving into it.
    if tuck.ghost then
        local ghostAlpha = self:GhostFade(elapsed)
        local ui = UIParent:GetEffectiveScale()
        local sink = Smooth(Clamp(t / MORPH_SINK, 0, 1))
        self:MoveGhost((x - scale * from.x) * ui, (y - scale * from.y) * ui, scale)
        self:GhostLayers(ghostAlpha, math.min(ghostAlpha, 1 - sink), math.min(ghostAlpha, 1 - sink), SINK_DROP * sink)
        if ghostAlpha <= 0 then tuck.ghost = false; self:HideGhost() end
        away = away * (1 - ghostAlpha)
    end
    card:SetAlpha(away)

    -- Its shadow: thrown as it is lifted, drawn back in as it comes down.
    local reach = (1 - fly * 0.7) * lift
    local dx, dy = 7 * reach, -10 * reach
    local blur = 16
    card.shadow:ClearAllPoints()
    card.shadow:SetPoint("TOPLEFT", card, "TOPLEFT", (dx - blur) / scale, (dy + blur) / scale)
    card.shadow:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", (dx + blur) / scale, (dy - blur) / scale)
    card.shadow:SetAlpha(0.55 * lift * (1 - 0.45 * fly) * (1 - slide))

    -- The window giving as the page goes under it: up a little and back, settling.
    local nudge = t - (landed - 0.05)
    if nudge >= 0 and nudge <= TUCK_NUDGE then
        self:Give(tuck, TUCK_GIVE * math.exp(-6 * nudge) * math.sin(2 * math.pi * nudge / 0.34))
    elseif nudge > TUCK_NUDGE then
        self:Rest(tuck)
    end

    -- Taken: its count ripples out.
    local taken = t - (landed + TUCK_SLIDE * 0.45)
    if taken >= 0 then
        if not tuck.taken then
            tuck.taken = true
            self:StartRipple()
        end
        local g = Clamp(taken / TUCK_RIPPLE, 0, 1)
        local ripple = self.ripple
        if ripple:IsShown() then
            local r = EaseOutCubic(g)
            local rippleScale = 1 + 1.3 * r
            ripple:SetScale(rippleScale)
            ripple:ClearAllPoints()
            ripple:SetPoint("CENTER", UIParent, "BOTTOMLEFT", tuck.rippleX / rippleScale, tuck.rippleY / rippleScale)
            ripple:SetAlpha(0.9 * (1 - r))
        end
        if g >= 1 then self:StopTuck() end
    end
end

--- This window's count, if it shows one, about to ripple out from where it is.
function Skin:StartRipple()
    local tuck, frame, ripple = self.tuck, self.frame, self.ripple
    local scale = frame:GetScale() or 1
    local count = self.count
    local cx, cy
    if count and count:IsShown() and (self.counted or 0) > 0 and count.GetCenter then cx, cy = count:GetCenter() end
    if type(cx) ~= "number" or type(cy) ~= "number" then return end
    local ui = UIParent:GetEffectiveScale()
    local pixels = frame:GetEffectiveScale()
    tuck.rippleX, tuck.rippleY = cx * pixels / ui, cy * pixels / ui
    local face, size = count:GetFont()
    local colors = self.colors or Theme:Colors((self.look or LOOKS.quest).palette)
    ripple:SetFrameStrata(frame:GetFrameStrata())
    ripple:SetFrameLevel(frame:GetFrameLevel() + 41)
    ripple.text:SetFont(face, math.max(6, Round((size or 12) * scale)), "")
    ripple.text:SetTextColor(colors.title[1], colors.title[2], colors.title[3])
    ripple.text:SetText(count:GetText() or "")
    ripple:Show()
end

--- Done, or cut short (a dialog opening, another closing): the page, the dialog drawn again and
--- the ripple gone, this window where it rests.
function Skin:StopTuck()
    local tuck = self.tuck
    self.tuck = nil
    if self.card then self.card:Hide() end
    if self.ripple then self.ripple:Hide() end
    if tuck then
        if tuck.ghost then self:HideGhost() end
        self:Rest(tuck)
    end
end

--- Caption lines the current clip's words take at `width`; nil while the captions hold
--- another clip's words, or none.
function Skin:TextLines(width)
    if not (self.clip and Transcript.clip == self.clip and Transcript.frame) then return nil end
    -- Wrapped at this width first: the captions reflow only when their width changes.
    if Transcript.frame:GetWidth() ~= width then
        Transcript:Dock(self.content, self.content, "TOPLEFT", 0, 0, width, math.max(1, Transcript.frame:GetHeight()))
    end
    local count = Transcript.lines and #Transcript.lines or 0
    return count > 0 and count or nil
end

function Skin:RefreshConfig(original)
    self:Initialize()
    -- One image fading: nothing in it may change; this waits for it (Skin:Unbuffer).
    if self.buffered then self.pending = "refresh"; return end
    local frame = self.frame
    frame:SetFrameStrata(Config().FrameStrata)
    self:Layout()
    frame:SetScale(frame.spokenBaseScale)
    if not Addon:Layout().DialogueUI and not self.sizing then self:PlaceDefault() end
    if Addon:IsFrameLocked() then frame:StopMovingOrSizing() end
    -- Locked, clicks on the window pass through to the game, as the subtitle's and the small
    -- window's do; its buttons still take theirs. Where the client cannot tell a click from the
    -- pointer passing over, the window keeps both.
    if frame.SetMouseClickEnabled and frame.SetMouseMotionEnabled then
        frame:SetMouseMotionEnabled(true)
        frame:SetMouseClickEnabled(not Addon:IsFrameLocked())
    end
    Addon:ApplyHost(frame)
    self:Update()
end

function Skin:Update()
    if not self.frame then return end
    if not self:IsEnabled() then self:SetVisible(false, true); return end
    -- The line playing, or the sample a style tile previews (PlayerFrame:ShowSample).
    local clip = PlayerFrame:Current()
    -- Nothing to show: an image fading out goes on fading.
    if not clip then self:SetVisible(false); return end
    if self:Covered() then self:SetVisible(false, true); return end
    -- One image fading: nothing in it may change; this waits for it (Skin:Unbuffer).
    if self.buffered then self.pending = self.pending or "update"; return end
    self:Touch()
    if clip ~= self.clip then
        self:HideTooltip()
        -- Following another line on screen: its words fade in and the window eases to it.
        if self.clip and self.wanted and self.frame:IsShown() then
            self.easeNext, self.lineFade = true, 0
            self:PaintContent()
        end
        self.clip, self.seconds, self.offset = clip, 0, 0
    end
    -- The queue's length decides how much of the body the captions get, and the line's words
    -- how tall the panel is (Fit to the Words): a new line, or its words arriving late.
    local textLines = Transcript.clip == clip and Transcript.lines and #Transcript.lines or 0
    local picture = clip.present and clip.present.picture
    local key = Waiting() .. ":" .. textLines .. ":" .. (picture and picture.file .. ":" .. (picture.pixels or "") or "")
    if key ~= self.laidOutFor then
        self.laidOutFor = key
        self:Layout()
    end
    self:SetVisible(true)
    -- Said once: a name the same as the line's own is left off, as the subtitle leaves it.
    local header = clip.present and clip.present.header
    self.name:SetText(header ~= Label(clip) and header or "")
    self:ConfigurePortrait()
    self:ConfigureActions()
    self:LayoutQueue()
    self:UpdateProgress()
    self:UpdateControls(true)
end

function Skin:Reset()
    if not self.frame then return end
    self.frame:StopMovingOrSizing()
    Addon:Layout().DialogueUI = nil
    Addon:Layout().DialogueUIHeight = nil
    Addon:Layout().DialogueUIWidth = nil
    -- Back where DialogueUI puts its window (RefreshConfig, with no saved place).
    self:RefreshConfig(PlayerFrame)
end

function Skin:Describe()
    if not self.frame then return "dialogueui skin: no frame built" end
    return format("dialogueui skin: enabled=%s visible=%s theme=%d size=%.0fx%.0f lines=%d portrait=%s",
        tostring(self:IsEnabled()), tostring(self.frame:IsVisible()), Theme:Available() and Theme:ThemeID() or 0,
        self.frame:GetWidth() or 0, self.frame:GetHeight() or 0, self.lines or 0, tostring(self.viewport.active))
end
