setfenv(1, SpokenEnv)

-- The frame's settings, or their defaults once AceDB has stripped them (Addon:Profile).
local function FrameConfig()
    return Addon:Profile("Frame")
end

-- The large window, the "classic" narrator style: the speaker's portrait, and beside it a box with
-- the header (who speaks, the line's name, Stopped and the lines waiting, the round controls), the
-- words under it and the progress line along their foot, as the DialogueUI window lays them out.
-- With Bronze Border on, in retail's Talking Head art where the client has it; otherwise in
-- Spoken's own. Loads on 1.12 too, so Lua 5.0 syntax throughout.
--
-- Refreshed through the player's AUDIO_CHANGED callback rather than by the queue
-- calling this file, which is what keeps SoundQueue.lua free of any dependency on it.
PlayerFrame = {}

local PORTRAIT_SIZE = 120
-- Spoken's own portrait art: the border's cell in PortraitFrameAtlas, and the opening in it.
local PORTRAIT_ATLAS_SIZE = 512
local PORTRAIT_ATLAS_BORDER_SIZE = 416
local PORTRAIT_ATLAS_VIEWPORT_SIZE = 348
local PORTRAIT_BORDER_OUTSET = 34 * PORTRAIT_SIZE / PORTRAIT_ATLAS_VIEWPORT_SIZE
-- The Talking Head's (TalkingHeadUI.xml), scaled to this portrait: its face is 115 across and 21
-- into its box from the top and the left, its ring 143 across, 16 left of the face and 15 above it.
local HEAD = PORTRAIT_SIZE / 115
local HEAD_INSET, HEAD_RING = 21 * HEAD, 143 * HEAD
local HEAD_RING_X, HEAD_RING_Y = -16 * HEAD, 15 * HEAD
-- The Talking Head's atlases, the first of each the client has. The Forever client's Neutral box
-- is a light parchment; the other is dark.
local RING = { "TalkingHeads-Neutral-PortraitFrame", "TalkingHeads-PortraitFrame" }
local BOX = { "TalkingHeads-Neutral-TextBackground", "TalkingHeads-TextBackground" }
local FACE = { "TalkingHeads-PortraitBg" }
local LIGHT_BOX = "TalkingHeads-Neutral-TextBackground"
-- The width the window opens at, less the portrait, which Hide Portrait takes off.
local FRAME_WIDTH_WITHOUT_PORTRAIT = 400
-- Round the column: after the portrait; from the window's left edge without it, leaving the mover
-- room; before the right edge, where the resizer sits; and the least over and under it.
local GAP, LEFT, RIGHT, PAD = 18, 30, 20, 12
-- The column's least width: the header's three controls and a name.
local LEAST_COLUMN = 200
-- The header is as tall as its round controls, ROUND_GAP apart. Its words end a button's width
-- short of them; the line's label sits LABEL_GAP after the name, left off with less room than
-- LABEL_LEAST.
local ROUND_SIZE, ROUND_GAP = 24, 4
local LABEL_GAP, LABEL_LEAST = 8, 40
-- The words' gap under the header, of a line's height; a line leaving at the top fades through a
-- whole line's room over them, into the header's foot.
local WORDS_UNDER = 0.6
-- Between the words and the progress line.
local BAR_GAP = 6
local TEXTURES = [[Interface\AddOns\Spoken\Textures\]]
-- The header's colours on each box: Spoken's own and the Talking Head's dark one; on its light one
-- the game's (TalkingHeadUI.lua: a brown name, dark words, no shadow), with the words and the word
-- lit in DialogueUI's parchment colours.
local LOOKS = {
    own = { name = { 214 / 255, 214 / 255, 214 / 255 }, label = { .62, .62, .62 }, tail = { .5, .5, .5 } },
    dark = { name = { 1, .82, 0 }, label = { .72, .72, .72 }, tail = { .5, .5, .5 } },
    light = { name = { .33, .16, .02 }, label = { .5, .36, .24 }, tail = { .5, .36, .24 },
        words = { .19, .17, .13 }, highlight = "|cff9c1a1a", flat = true },
}

do
    local font = CreateFont("SpokenNameFont")
    font:SetFont(GameFontNormal:GetFont(), 19, "")
    font:SetShadowColor(0, 0, 0)
    font:SetShadowOffset(1, -1)
    font:SetJustifyH("LEFT")
    font:SetJustifyV("MIDDLE")
end
do
    local font = CreateFont("SpokenLabelFont")
    font:SetFont(GameFontNormal:GetFont(), 14, "")
    font:SetShadowColor(0, 0, 0)
    font:SetShadowOffset(1, -1)
    font:SetJustifyH("LEFT")
    font:SetJustifyV("MIDDLE")
end

-- 1.12 reports no width for a frame that has not been laid out; the edges are reliable.
local function WidthOf(frame)
    if Version.IsLegacyVanilla then
        return (frame:GetRight() or 0) - (frame:GetLeft() or 0)
    end
    return frame:GetWidth()
end

local function Round(n) return math.floor(n + 0.5) end
local function Label(clip) return clip and (clip.present and clip.present.label or clip.key) or "" end
local function Waiting() return math.max(0, SoundQueue:GetQueueSize() - 1) end

local function FirstAtlas(names)
    for _, name in ipairs(names) do
        if Actions.HasAtlas(name) then return name end
    end
    return nil
end

function PlayerFrame:Initialize()
    if self.frame then return end
    self:InitDisplay()
    self:InitPortrait()
    self:InitHeader()
    self:InitMover()
    Actions:Build(self.frame)
    self:RefreshConfig()
    Callbacks:Register("AUDIO_CHANGED", function() PlayerFrame:Update() end)
end

function PlayerFrame:InitDisplay()
    self.frame = CreateFrame("Frame", "SpokenPlayerFrame", UIParent, "BackdropTemplate")
    function self.frame:Reset()
        self:SetWidth(PORTRAIT_SIZE + FRAME_WIDTH_WITHOUT_PORTRAIT)
        self:SetHeight(PORTRAIT_SIZE)
        self:ClearAllPoints()
        self:SetPoint("BOTTOM", 0, 200)
    end
    self.frame:Reset()
    if Addon:RestoreLayout("Player", self.frame) then
        -- Saved as the width with the portrait, which RefreshConfig takes off when hidden.
        self.frame:SetWidth(Addon:Layout().Player.width or self.frame:GetWidth())
    end
    self.frame:SetMovable(true)
    self.frame:SetResizable(true)
    self.frame:SetClampedToScreen(true)
    -- Placed from the saved layout instead; the client's cache would only fight it.
    self.frame:SetUserPlaced(false)
    self.frame:SetFrameStrata(FrameConfig().FrameStrata)
    self.frame:Hide()

    -- The box: the Talking Head's behind the whole window, or Spoken's gradient beside the portrait
    -- (PlayerFrame:ApplyArt).
    self.frame.background = self.frame:CreateTexture(nil, "BACKGROUND")

    self.frame.resizer = CreateFrame("Button", nil, self.frame)
    self.frame.resizer:SetPoint("BOTTOMRIGHT")
    self.frame.resizer:SetSize(16, 16)
    self.frame.resizer:SetNormalTexture(TEXTURES .. "SizeGrabber-Up")
    self.frame.resizer:SetPushedTexture(TEXTURES .. "SizeGrabber-Down")
    self.frame.resizer:SetHighlightTexture(TEXTURES .. "SizeGrabber-Highlight")
    self.frame.resizer:HookScript("OnEnter", function() SetCursor([[Interface\Cursor\UI-Cursor-SizeRight]]) end)
    self.frame.resizer:HookScript("OnLeave", function() SetCursor(nil) end)
    self.frame.resizer:HookScript("OnMouseDown", function()
        self.frame.resizer:GetHighlightTexture():Hide()
        self.frame:StartSizing("BOTTOMRIGHT")
    end)
    self.frame.resizer:HookScript("OnMouseUp", function()
        self.frame.resizer:GetHighlightTexture():Show()
        self.frame:StopMovingOrSizing()
        self:SaveLayout()
    end)

    -- The column in the box: the header, the words under it, the progress line along their foot.
    self.frame.container = CreateFrame("Frame", nil, self.frame)

    self.frame:SetScript("OnSizeChanged", function() self:Layout() end)
    self.frame:SetScript("OnUpdate", function(_, elapsed) self:Tick(elapsed) end)
end

function PlayerFrame:InitPortrait()
    self.frame.portrait = CreateFrame("Frame", nil, self.frame)
    self.frame.portrait:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)

    self.frame.portrait.background = self.frame.portrait:CreateTexture(nil, "BACKGROUND")
    self.frame.portrait.background:SetAllPoints()

    -- A separate frame so the border and the mover draw above the face.
    self.frame.portrait.border = CreateFrame("Frame", nil, self.frame.portrait)
    self.frame.portrait.border:SetFrameLevel(self.frame.portrait:GetFrameLevel() + 3)
    self.frame.portrait.border:SetAllPoints()
    self.frame.portrait.border.texture = self.frame.portrait.border:CreateTexture(nil, "BORDER")
end

--- The header: the speaker, the line's label after the name, Stopped and the count after those,
--- and the round controls at its right end, as the DialogueUI window's. The progress line too.
function PlayerFrame:InitHeader()
    local container = self.frame.container
    container.name = container:CreateFontString(nil, "ARTWORK", "SpokenNameFont")
    container.name:SetWordWrap(false)
    container.label = container:CreateFontString(nil, "ARTWORK", "SpokenLabelFont")
    container.label:SetWordWrap(false)
    self.stopped = container:CreateFontString(nil, "ARTWORK", "SpokenLabelFont")
    self.stopped:SetWordWrap(false)
    self.stopped:SetText(format("• (%s)", L.SUBTITLE_STOPPED))
    self.stopped:Hide()
    self.count = container:CreateFontString(nil, "ARTWORK", "SpokenLabelFont")
    self.count:SetWordWrap(false)
    self.count:Hide()
    self.tail = Actions.Tail(self.stopped, self.count)

    self.controls = CreateFrame("Frame", nil, container)
    self.controls:SetHeight(1)
    self.play = Actions.StopButton(self.controls, function() return self:Current() ~= nil end,
        function() self:UpdateControls() end)
    self.skip = Actions.SkipButton(self.controls)
    self.buttons = { self.play, self.skip }

    self.progress = Actions.ProgressBar(container)
end

function PlayerFrame:InitMover()
    self.frame.mover = CreateFrame("Button", nil, self.frame.portrait.border)
    self.frame.mover:SetSize(26, 26)
    self.frame.mover:SetNormalTexture(TEXTURES .. "PortraitFrameAtlas")
    self.frame.mover:GetNormalTexture():SetTexCoord(462 / PORTRAIT_ATLAS_SIZE, 512 / PORTRAIT_ATLAS_SIZE, 462 / PORTRAIT_ATLAS_SIZE, 512 / PORTRAIT_ATLAS_SIZE)
    self.frame.mover:GetNormalTexture():ClearAllPoints()
    self.frame.mover:GetNormalTexture():SetPoint("CENTER")
    self.frame.mover:GetNormalTexture():SetSize(16, 16)
    self.frame.mover:SetPushedTexture(TEXTURES .. "PortraitFrameAtlas")
    self.frame.mover:GetPushedTexture():SetTexCoord(462 / PORTRAIT_ATLAS_SIZE, 512 / PORTRAIT_ATLAS_SIZE, 462 / PORTRAIT_ATLAS_SIZE, 512 / PORTRAIT_ATLAS_SIZE)
    self.frame.mover:GetPushedTexture():ClearAllPoints()
    self.frame.mover:GetPushedTexture():SetPoint("CENTER")
    self.frame.mover:GetPushedTexture():SetSize(14, 14)
    self.frame.mover.background = self.frame.mover:CreateTexture(nil, "BACKGROUND")
    self.frame.mover.background:SetTexture(TEXTURES .. "SettingsButton")
    self.frame.mover.background:SetPoint("CENTER")
    self.frame.mover.background:SetSize(32, 32)
    self.frame.mover:HookScript("OnEnter", function(button)
        if Addon:IsFrameLocked() then return end
        SetCursor([[Interface\Cursor\UI-Cursor-Move]])
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.OPT_STYLE_CLASSIC)
        GameTooltip:AddLine(L.QUEUE_DRAG_HINT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.frame.mover:HookScript("OnLeave", function() SetCursor(nil); GameTooltip_Hide() end)
    self.frame.mover:HookScript("OnMouseDown", function()
        if Addon:IsFrameLocked() then return end
        self.frame:StartMoving()
    end)
    self.frame.mover:HookScript("OnMouseUp", function()
        if Addon:IsFrameLocked() then return end
        self.frame:StopMovingOrSizing()
        self:SaveLayout()
    end)
end

--- The skin drawing the queue in place of this window, or nil when this window does.
function PlayerFrame:Skin()
    if MinimalPlayer:IsEnabled() then return MinimalPlayer end
    if DialogueUIPlayer and DialogueUIPlayer:IsEnabled() then return DialogueUIPlayer end
    return nil
end

--- Whether this window shows the lines: the large window chosen, no skin in its place.
function PlayerFrame:IsShowing()
    return self:Skin() == nil and Addon:DisplayStyle() == "classic"
end

--- The Talking Head's atlases, with Bronze Border on and every one in the client; nil for
--- Spoken's own art.
function PlayerFrame:Art()
    if not Addon:Bronze() then return nil end
    local ring, box, face = FirstAtlas(RING), FirstAtlas(BOX), FirstAtlas(FACE)
    if not (ring and box and face) then return nil end
    return { ring = ring, box = box, face = face, look = box == LIGHT_BOX and LOOKS.light or LOOKS.dark }
end

local function DrawArt(frame, art)
    local portrait = frame.portrait
    local border = portrait.border.texture
    border:ClearAllPoints()
    if art then
        frame.background:SetAtlas(art.box)
        portrait.background:SetAtlas(art.face)
        border:SetAtlas(art.ring)
        border:SetSize(HEAD_RING, HEAD_RING)
        border:SetPoint("TOPLEFT", portrait, "TOPLEFT", HEAD_RING_X, HEAD_RING_Y)
        return
    end
    frame.background:SetTexture(TEXTURES .. "BackgroundGradient")
    frame.background:SetTexCoord(0, 1, 0, 1)
    portrait.background:SetTexture(TEXTURES .. "PortraitFrameBackground")
    portrait.background:SetTexCoord(0, 1, 0, 1)
    border:SetTexture(TEXTURES .. "PortraitFrameAtlas")
    border:SetTexCoord(0, PORTRAIT_ATLAS_BORDER_SIZE / PORTRAIT_ATLAS_SIZE, 0, PORTRAIT_ATLAS_BORDER_SIZE / PORTRAIT_ATLAS_SIZE)
    border:SetPoint("TOPLEFT", portrait, "TOPLEFT", -PORTRAIT_BORDER_OUTSET, PORTRAIT_BORDER_OUTSET)
    border:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", PORTRAIT_BORDER_OUTSET, -PORTRAIT_BORDER_OUTSET)
end

--- The box and the portrait's art, and the header's colours on it. Art that fails to draw leaves
--- Spoken's own, and its error goes to the error handler.
function PlayerFrame:ApplyArt()
    local art = self:Art()
    if art then
        local ok, err = pcall(DrawArt, self.frame, art)
        if not ok then
            art = nil
            if geterrorhandler then geterrorhandler()(err) end
        end
    end
    if not art then DrawArt(self.frame, nil) end
    self.art = art
    self.look = art and art.look or LOOKS.own
    local look = self.look
    local container = self.frame.container
    local function Paint(text, color)
        text:SetTextColor(color[1], color[2], color[3])
        text:SetShadowColor(0, 0, 0, look.flat and 0 or 1)
    end
    Paint(container.name, look.name)
    Paint(container.label, look.label)
    Paint(self.stopped, look.tail)
    Paint(self.count, look.tail)
end

function PlayerFrame:RefreshConfig()
    -- Bronze Border tints every round button, whichever way lines are shown.
    Actions.RefreshRings()
    local skin = self:Skin()
    -- Each window dresses the captions its own way; the others' look must not stay on them.
    if skin ~= DialogueUIPlayer and not self:IsShowing() then Transcript:SetStyle(nil) end
    for _, other in ipairs({ MinimalPlayer, DialogueUIPlayer }) do
        if other ~= skin then other:SetVisible(false, true) end
    end
    if skin then
        self.frame:Hide()
        skin:RefreshConfig(self)
        return
    end
    local cfg = FrameConfig()
    if cfg.HidePortrait then
        if self.frame.portrait:IsShown() then
            self.frame:SetWidth(self.frame:GetWidth() - PORTRAIT_SIZE)
        end
        self.frame.portrait:Hide()
        self.frame.mover:SetParent(self.frame)
        self.frame.mover:SetPoint("CENTER", self.frame, "BOTTOMLEFT", LEFT / 2, LEFT / 2)
    else
        if not self.frame.portrait:IsShown() then
            self.frame:SetWidth(self.frame:GetWidth() + PORTRAIT_SIZE)
        end
        self.frame.portrait:Show()
        self.frame.mover:SetParent(self.frame.portrait.border)
        self.frame.mover:SetPoint("CENTER", self.frame.portrait, "BOTTOMLEFT", 5, 6)
    end
    self:ApplyArt()

    self.frame.mover:SetShown(not Addon:IsFrameLocked())
    self.frame.resizer:SetShown(not Addon:IsFrameLocked())
    self.frame:SetScale(cfg.FrameScale)
    self.frame:SetFrameStrata(cfg.FrameStrata)
    Addon:ApplyHost(self.frame)
    self:Update()
end

--- Lines Shown of the words and a line's height, or no lines where the line has no words to show
--- (Show Words off, none written, or 1.12, which has no captions).
function PlayerFrame:WordLines(clip)
    local transcript = Addon:Profile("Transcript")
    local lineHeight = (transcript.FontSize or 16) + 4
    if Transcript:HeightForClip(clip) <= 0 then return 0, lineHeight end
    return transcript.Lines == 1 and 1 or 2, lineHeight
end

--- The window's height and its column's place for the line, the words docked in the column. Run
--- on every update and resize; the height follows the words, the width is the player's.
function PlayerFrame:Layout()
    if self.laying or not self:IsShowing() then return end
    self.laying = true
    local frame, container = self.frame, self.frame.container
    local hidePortrait = FrameConfig().HidePortrait
    local inset = (self.art and not hidePortrait) and HEAD_INSET or 0
    local left = hidePortrait and LEFT or inset + PORTRAIT_SIZE + GAP

    local lines, lineHeight = self:WordLines(self:Current())
    local words = lines * lineHeight
    local wordsGap = Round(WORDS_UNDER * lineHeight)
    local wordsTop = ROUND_SIZE + wordsGap
    local content = (words > 0 and wordsTop + words or ROUND_SIZE) + BAR_GAP + self.progress.height
    local height = math.max(hidePortrait and 0 or PORTRAIT_SIZE + 2 * inset, content + 2 * PAD)
    Transcript:ResizePlayer(frame, height, left + LEAST_COLUMN + RIGHT, 10000)

    local width = math.max(1, WidthOf(frame) - left - RIGHT)
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -Round((height - content) / 2))
    container:SetWidth(width)
    container:SetHeight(content)

    self.frame.portrait:ClearAllPoints()
    self.frame.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    self.frame.background:ClearAllPoints()
    if self.art or hidePortrait then
        self.frame.background:SetPoint("TOPLEFT")
    else
        self.frame.background:SetPoint("TOPLEFT", PORTRAIT_SIZE, 0)
    end
    self.frame.background:SetPoint("BOTTOMRIGHT")

    container.name:ClearAllPoints()
    container.name:SetPoint("LEFT", container, "TOPLEFT", 0, -ROUND_SIZE / 2)
    container.label:ClearAllPoints()
    container.label:SetPoint("BOTTOMLEFT", container.name, "BOTTOMRIGHT", LABEL_GAP, 1)
    self.controls:ClearAllPoints()
    self.controls:SetPoint("RIGHT", container, "TOPRIGHT", 0, -ROUND_SIZE / 2)

    -- A line's room over the words and under them, which a line gliding out or in fades through.
    local look = self.look or LOOKS.own
    local style = { lines = math.max(1, lines), padTop = lineHeight, color = look.words, highlight = look.highlight }
    if look.flat then style.shadow = false end
    self.styling = true
    Transcript:SetStyle(style)
    self.styling = nil
    Transcript:Dock(container, container, "TOPLEFT", 0, -(wordsTop - lineHeight), width,
        words > 0 and words + 2 * lineHeight or 0)

    self.progress.track:ClearAllPoints()
    self.progress.track:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    self.progress.track:SetWidth(width)
    self:LayoutHeader()
    self.laying = nil
end

--- The name in full where it fits, the label after it cut short (or left off where it would not
--- show enough), then Stopped and the count, all short of the controls by a button's width.
function PlayerFrame:LayoutHeader()
    local container = self.frame.container
    local name, label, tail = container.name, container.label, self.tail
    local room = math.max(1, WidthOf(container) - self.controls:GetWidth() - ROUND_SIZE)
    local tailRoom = tail:Room()
    -- Unbounded first, so the widths measured are the texts' own.
    name:SetWidth(0)
    name:SetText(name:GetText())
    local nameWidth = math.min((name:GetStringWidth() or 0) + 1, math.max(1, room - tailRoom))
    name:SetWidth(nameWidth)
    local text = label:GetText() or ""
    local shown = 0
    if text ~= "" then
        label:SetWidth(0)
        label:SetText(text)
        local want = (label:GetStringWidth() or 0) + 1
        local free = room - tailRoom - nameWidth - LABEL_GAP
        if free >= math.min(want, LABEL_LEAST) then shown = math.min(want, free) end
    end
    label:SetShown(shown > 0)
    if shown > 0 then label:SetWidth(shown) end
    if tailRoom > 0 then
        if shown > 0 then tail:Place(label, shown) else tail:Place(name, nameWidth) end
        tail:Paint()
    end
end

function PlayerFrame:ConfigureActions(clip)
    self.row = Actions:HeaderControls(self.frame, self.controls, self.buttons, clip)
    Actions.LayOutRow(self.controls, self.row, ROUND_GAP)
end

function PlayerFrame:UpdateControls()
    if not self:Current() then return end
    Actions.SetPlayGlyph(self.play, Actions.HeadState())
    self.tail:SetStopped(SoundQueue:IsPaused())
    self.tail:SetCount(Waiting())
    local pausable = SoundQueue:CanBePaused()
    for _, button in ipairs(self.buttons) do
        button:SetAlpha(pausable and 1 or .4)
        if pausable then button:Enable() else button:Disable() end
    end
    self:LayoutHeader()
end

function PlayerFrame:UpdateProgress()
    local clip = self:Current()
    if not clip then return end
    if clip ~= self.timed then self.timed, self.seconds = clip, 0 end
    self.seconds = Actions.Elapsed(clip, self.seconds)
    local duration = tonumber(clip.length) or 0
    Actions.SetProgress(self.progress, duration > 0 and (self.seconds or 0) / duration or 0)
end

function PlayerFrame:Tick(elapsed)
    if not self.frame:IsShown() then return end
    self:UpdateProgress()
    -- Stopped faded out: its room given back.
    if self.tail:Step(elapsed) then
        self.tail:SetCount(Waiting())
        self:LayoutHeader()
    end
    self.poll = (self.poll or 0) + elapsed
    if self.poll >= .2 then
        self.poll = 0
        self:UpdateControls()
    end
end

--- A line to show while none is playing, so a window chosen as the narrator style in the welcome
--- window can be seen at once, as the subtitles show theirs. Either window draws it; the first
--- real line puts it away.
function PlayerFrame:ShowSample(shown)
    self.sample = shown and {
        key = "sample", length = 0,
        source = { key = "sample", gates = {}, interClipGap = 0 },
        present = { header = L.SAMPLE_SPEAKER, label = L.SAMPLE_LINE,
            -- Words for the captions to show, as the subtitle's sample has.
            transcript = L.SUBTITLE_SAMPLE_TEXT,
            portrait = { kind = "texture", texture = [[Interface\AddOns\Spoken\icon.tga]] } },
    } or nil
    Transcript:Sync()
    self:Update()
end

function PlayerFrame:IsShowingSample()
    return self.sample ~= nil
end

--- The line the window stands for: the one playing, or the sample while nothing is.
function PlayerFrame:Current()
    if not SoundQueue:IsEmpty() then self.sample = nil end
    return SoundQueue:GetCurrentSound() or self.sample
end

function PlayerFrame:Update()
    if not self.frame then return end
    local skin = self:Skin()
    if skin then skin:Update(); return end
    -- The captions taking this window's look ask for an update: the layout under way has it.
    if self.styling then return end
    -- Hidden, not torn down, while subtitles stand in for it: going back finds it as it was.
    local head = self:Current()
    self.frame:SetShown(Addon:DisplayStyle() == "classic" and head ~= nil)
    if not self.frame:IsShown() then return end

    -- The speaker, or the line's name where nobody speaks; then the line's name, unless it is
    -- the same, as the subtitle leaves it off.
    local container = self.frame.container
    local header = head.present and head.present.header
    local title = Label(head)
    local name = (header and header ~= "") and header or title
    container.name:SetText(name)
    container.label:SetText(title ~= name and title or "")

    Portrait:Configure(self.frame.portrait, head)
    self:ConfigureActions(head)
    self:Layout()
    self:UpdateControls()
    self:UpdateProgress()
end

--- What the frame is actually doing, for a bug report. A header that is set but drawn nowhere,
--- or drawn under something, looks from the outside exactly like one that was never set; this
--- tells the two apart without a client to poke at.
function PlayerFrame:Describe()
    local lines = {}
    local function Say(text) table.insert(lines, text) end
    Say(MinimalPlayer:Describe())
    if DialogueUIPlayer then Say(DialogueUIPlayer:Describe()) end
    if not self.frame then
        Say("no frame built")
        return lines
    end
    local container = self.frame.container
    Say(format("frame shown=%s w=%.0f h=%.0f art=%s", tostring(self.frame:IsShown()),
        self.frame:GetWidth() or 0, self.frame:GetHeight() or 0, self.art and self.art.box or "own"))
    Say(format("container shown=%s w=%.0f h=%.0f header=%q title=%q count=%q", tostring(container:IsShown()),
        container:GetWidth() or 0, container:GetHeight() or 0, container.name:GetText() or "",
        container.label:IsShown() and container.label:GetText() or "", self.count:GetText() or ""))
    Say(format("portrait kind=%s", tostring(self.frame.portrait.active)))
    for _, button in ipairs(self.row or {}) do
        Say(format("  control %s shown=%s", button.action and button.action.id or (button == self.play
            and tostring(self.play.state) or "skip"), tostring(button:IsShown())))
    end
    Say(format("head can be stopped=%s", tostring(SoundQueue:CanBePaused())))
    Say(format("queue=%d", SoundQueue:GetQueueSize()))
    return lines
end

function PlayerFrame:SaveLayout()
    local width = self.frame:GetWidth() + (FrameConfig().HidePortrait and PORTRAIT_SIZE or 0)
    Addon:SaveLayout("Player", self.frame, width)
end

--- Back to the default spot and width, forgetting the saved ones, for a frame dragged
--- off-screen or sized past use.
function PlayerFrame:Reset()
    local skin = self:Skin()
    if skin then skin:Reset(); return end
    Addon:Layout().Player = nil
    if not self.frame then return end
    self.frame:Reset()
    -- Reset's width has the portrait in it, and RefreshConfig only takes it off on a change.
    if FrameConfig().HidePortrait then self.frame:SetWidth(self.frame:GetWidth() - PORTRAIT_SIZE) end
    self:RefreshConfig()
end
