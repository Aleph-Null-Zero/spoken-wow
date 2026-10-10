setfenv(1, SpokenEnv)

-- The "minimal" narrator style, the Small Window: the speaker's portrait beside a panel with the
-- name, the line's title and its words, and the round controls the DialogueUI window and the
-- subtitle have. Playback and source-owned actions still belong to the queue and actions services.
MinimalPlayer = {}
local ART = [[Interface\AddOns\Spoken\Textures\]]
local HEIGHT, WIDTH = 98, 380
-- Down the content, from its top: the name's row, then the title's. The words start WORDS_TOP
-- down, and the progress line PROGRESS_GAP under them (under the title, with no words); FOOT is
-- the room under the last of them to the frame's bottom, over the border.
local NAME_HEIGHT, TITLE_HEIGHT = 21, 19
local WORDS_TOP, PROGRESS_GAP, FOOT = 44, 6, 27
-- The content's inset from the frame's top and right; its left edge clears the portrait.
local INSET, BESIDE_PORTRAIT, NO_PORTRAIT = 18, 96, 16
-- Between the name or the title and the header's buttons; between the buttons, as the subtitle's.
local CONTROLS_CLEAR, ROUND_GAP = 8, 4
-- The Forever client tints its frame metal bronze; its palette, so the player matches.
local BRONZE = Version.IsCamelot and { .95, .68, .35 } or nil
-- The panel's backgrounds (Frame.MinimalBackground). On parchment, the DialogueUI window's
-- parchment ink (DialogueUITheme's first palette), with no shadow; on the dark rock, the light
-- colours the window always had.
local LOOKS = {
    parchment = { name = { .19, .17, .13 }, title = { .19, .17, .13 }, tail = { .50, .36, .24 }, shadow = 0,
        words = { color = { .19, .17, .13 }, shadow = false, highlight = "|cff9c1a1a" } },
    dark = { name = { 1, .82, 0 }, title = { .88, .84, .76 }, tail = { .62, .58, .46 }, shadow = 1 },
}
-- The parchment's art: tiled atlases the Classic Era and Forever clients both have, the first the
-- default. /spoken parchment steps through them (MinimalPlayer:NextParchment). Where the client
-- has none of them, the parchment's own colour.
MinimalPlayer.PARCHMENTS = { "GarrMission_MissionParchment", "AdventureMap_TileBg_Parchment",
    "photosensitivitywarning-parchment-background", "ShipMissionParchment-Tile" }
local PARCHMENT_COLOR = { .88, .68, .41 }
-- Portrait badges by bullet id. Quests use trimmed copies of their own glyphs; books
-- and zones take native ones, since their registered bullet (or none) is not a badge.
local BADGES = {
    ["quest-accept"] = ART .. "MinimalBulletAccept",
    ["quest-progress"] = ART .. "MinimalBulletProgress",
    ["quest-complete"] = ART .. "MinimalBulletComplete",
    gossip = ART .. "MinimalBulletGossip",
    book = [[Interface\GossipFrame\TrainerGossipIcon]],
    zone = [[Interface\WorldMap\UI-World-Icon]],
}
MinimalPlayer.BADGES = BADGES
local function Clamp(n, low, high) return math.max(low, math.min(high, n)) end
-- The frame still resizes while the UI is torn down, after AceDB strips it (Addon:Profile).
local function Config() return Addon:Profile("Frame") end
local function Waiting() return math.max(0, SoundQueue:GetQueueSize() - 1) end
local function Label(clip) return clip and (clip.present and clip.present.label or clip.key) or "" end
local function Font(parent, size, r, g, b)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(GameFontNormal:GetFont(), size, "")
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetTextColor(r, g, b)
    return text
end
local function BelongsTo(frame, root)
    while frame do
        if frame == root then return true end
        frame = frame.GetParent and frame:GetParent()
    end
    return false
end

function MinimalPlayer:IsEnabled()
    return Addon.db and Addon:DisplayStyle() == "minimal"
end

-- Shared with the DialogueUI window, so both windows' text behaves alike.
MinimalPlayer.parts = { Font = Font, Label = Label, Clamp = Clamp, Waiting = Waiting, BelongsTo = BelongsTo }

function MinimalPlayer:HideTooltip()
    local owner = GameTooltip:GetOwner()
    if BelongsTo(owner, self.frame) or BelongsTo(owner, self.menu) then GameTooltip_Hide() end
end

function MinimalPlayer:HasClip()
    return self:IsEnabled() and self.wanted and SoundQueue:GetCurrentSound() ~= nil
end

function MinimalPlayer:Initialize(original)
    if self.frame then return end
    local frame = CreateFrame("Frame", "SpokenMinimalPlayerFrame", UIParent)
    self.frame = frame
    frame:SetSize(WIDTH, HEIGHT)
    if not Addon:RestoreLayout("Minimal", frame) then
        local point, relative, relativePoint, x, y = original:GetPoint(1)
        frame:SetPoint(point or "BOTTOM", relative or UIParent, relativePoint or "BOTTOM", x or 0, y or 200)
    end
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    -- Placed from the saved layout instead; the client's cache would only fight it.
    frame:SetUserPlaced(false)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() self:StartDrag() end)
    frame:SetScript("OnDragStop", function() self:StopDrag() end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then self:ToggleMenu() end
    end)
    frame:Hide()

    self.panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    self.panel:SetBackdrop({
        edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]], edgeSize = 24,
        insets = { left = 7, right = 7, top = 7, bottom = 7 },
    })
    -- Inside the 7px inset: the parchment, or the rock tiled by hand (Dress), since the
    -- backdrop's own tiling stretched it once the words made the panel taller.
    self.paper = self.panel:CreateTexture(nil, "BACKGROUND")
    self.paper:SetPoint("TOPLEFT", 7, -7)
    self.paper:SetPoint("BOTTOMRIGHT", -7, 7)
    self.panel:SetScript("OnSizeChanged", function() self:TileRock() end)

    local content = CreateFrame("Frame", nil, frame)
    self.content, frame.container = content, content
    content:SetHeight(76)
    content:SetFrameLevel(self.panel:GetFrameLevel() + 1)
    content.buttons = {}
    -- The name and the title's rows: dragged to move the window, right-clicked for the menu.
    self.header = CreateFrame("Button", nil, content)
    self.header:SetPoint("TOPLEFT")
    self.header:SetPoint("TOPRIGHT")
    self.header:SetHeight(NAME_HEIGHT + TITLE_HEIGHT)
    self.header:RegisterForClicks("RightButtonUp")
    self.header:RegisterForDrag("LeftButton")
    self.header:SetScript("OnClick", function() self:ToggleMenu() end)
    self.header:SetScript("OnDragStart", function() self:StartDrag() end)
    self.header:SetScript("OnDragStop", function() self:StopDrag() end)
    self.header:SetScript("OnEnter", function()
        if not self:HasClip() or self.menu:IsShown() then return end
        GameTooltip:SetOwner(self.header, "ANCHOR_RIGHT")
        GameTooltip:SetText(Label(self.clip))
        GameTooltip:AddLine(L.MIN_MENU_HINT, 1, .82, 0, true)
        GameTooltip:Show()
    end)
    self.header:SetScript("OnLeave", function() self:HideTooltip() end)

    -- Stop or Replay, Skip, then Report, at the header's right, as the DialogueUI window has them.
    self.controls = CreateFrame("Frame", nil, content)
    self.controls:SetHeight(1)
    self.controls:SetFrameLevel(content:GetFrameLevel() + 3)
    self.controls:SetPoint("RIGHT", content, "TOPRIGHT", 0, -(NAME_HEIGHT + TITLE_HEIGHT) / 2)
    self.play = Actions.StopButton(self.controls, function() return self:HasClip() end,
        function() self:UpdateControls() end)
    self.skip = Actions.SkipButton(self.controls)
    self.buttons = { self.play, self.skip }

    self.name = Font(self.header, 16, 1, .82, 0)
    self.name:SetHeight(NAME_HEIGHT)
    self.name:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    self.name:SetPoint("RIGHT", self.controls, "LEFT", -CONTROLS_CLEAR, 0)
    content.name = self.name -- Actions' header anchor contract.
    -- The line's name, nothing to click: Skip takes a line away, as on the subtitle.
    self.title = CreateFrame("Frame", nil, content)
    self.title:SetHeight(TITLE_HEIGHT)
    self.title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -NAME_HEIGHT)
    self.title:SetPoint("RIGHT", self.controls, "LEFT", -CONTROLS_CLEAR, 0)
    self.title.text = Font(self.title, 12, .88, .84, .76)
    -- Stopped and the lines waiting, after the title, each fading by itself.
    self.stopped = Font(self.title, 12, .62, .58, .46)
    self.stopped:SetText(format("• (%s)", L.SUBTITLE_STOPPED))
    self.stopped:Hide()
    self.count = Font(self.title, 12, .62, .58, .46)
    self.count:Hide()
    self.tail = Actions.Tail(self.stopped, self.count)

    -- The subtitle's progress line, along the foot of the words (MinimalPlayer:Layout).
    self.progress = Actions.ProgressBar(content)

    self:BuildPortrait()
    self:BuildMenu()
    Actions:Build(frame)

    self.resizer = CreateFrame("Button", nil, frame)
    self.resizer:SetSize(12, 12)
    self.resizer:SetPoint("BOTTOMRIGHT", -5, 12)
    self.resizer:SetNormalTexture(ART .. "SizeGrabber-Up")
    self.resizer:SetAlpha(0)
    self.resizer:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or Addon:IsFrameLocked() then return end
        self.sizing = true
        frame:StartSizing("BOTTOMRIGHT")
    end)
    self.resizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        if self.sizing then self:SaveLayout() end
        self.sizing = false
    end)
    frame:SetScript("OnSizeChanged", function() self:Layout() end)
    frame:SetScript("OnUpdate", function(_, elapsed) self:Tick(elapsed) end)
    frame:SetScript("OnHide", function()
        self.menu:Hide()
        self:HideTooltip()
    end)
end

-- The speaker's face in its ring. No Stop on it: the header's is the one, as the DialogueUI window
-- and the subtitle have one.
function MinimalPlayer:BuildPortrait()
    local host = CreateFrame("Frame", nil, self.frame)
    self.portrait, self.frame.portrait = host, host
    host:SetPoint("TOPLEFT", 0, -4)
    host:SetSize(90, 90)
    host:SetFrameLevel(self.content:GetFrameLevel() + 2)
    local background = host:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetTexture(ART .. "MinimalPortraitBackground")

    self.viewport = CreateFrame("Frame", nil, host)
    self.viewport:SetSize(78, 78)
    self.viewport:SetPoint("CENTER", host, "TOPLEFT", 90 * 35 / 71, -90 * 34 / 71)
    self.viewport:SetClipsChildren(true)
    local chrome = CreateFrame("Frame", nil, host)
    chrome:SetAllPoints()
    chrome:SetFrameLevel(host:GetFrameLevel() + 8)
    -- Unit-frame badge centres are backed separately from their metal ring.
    -- Without this disc the speaker's face shows through the speech-bubble badge.
    self.badgeBackground = chrome:CreateTexture(nil, "BACKGROUND")
    self.badgeBackground:SetSize(24, 24)
    self.badgeBackground:SetPoint("CENTER", host, "TOPLEFT", 90 * 56.5 / 71, -90 * 56.5 / 71)
    self.badgeBackground:SetTexture(ART .. "MinimalPortraitMask")
    self.badgeBackground:SetVertexColor(.04, .04, .035, 1)
    local ring = chrome:CreateTexture(nil, "ARTWORK")
    ring:SetAllPoints()
    ring:SetTexture(ART .. "MinimalPortraitRing")
    self.ring = ring
    self.badge = chrome:CreateTexture(nil, "OVERLAY")
    self.badge:SetSize(16, 16)
    self.badge:SetPoint("CENTER", host, "TOPLEFT", 90 * 56.5 / 71, -90 * 56.5 / 71)
end

function MinimalPlayer:BuildMenu()
    local menu = CreateFrame("Frame", "SpokenMinimalPlayerMenu", UIParent, "BackdropTemplate")
    self.menu = menu
    menu:SetSize(210, 144)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetBackdrop({ bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
        edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]], tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    menu:SetBackdropColor(.07, .065, .05, .98)
    menu:SetBackdropBorderColor(.6, .57, .48, 1)
    menu:Hide()
    table.insert(UISpecialFrames, "SpokenMinimalPlayerMenu")
    menu:RegisterEvent("GLOBAL_MOUSE_DOWN")
    menu:SetScript("OnEvent", function()
        if menu:IsShown() and not MouseIsOver(menu) and not MouseIsOver(self.frame) then menu:Hide(); self:HideTooltip() end
    end)
    self.menuButtons = {}
    local function Item(text, fn)
        local button = self:MenuItem(getn(self.menuButtons) + 1, fn)
        button.text:SetText(text)
        table.insert(self.menuButtons, button)
        return button
    end
    self.menuPlay = Item(L.STOP, function() if SoundQueue:CanBePaused() then SoundQueue:TogglePauseQueue() end end)
    self.menuSkip = Item(L.MIN_SKIP, function() SoundQueue:Skip() end)
    self.menuStop = Item(L.MIN_STOP_ALL, function() SoundQueue:RemoveAllSoundsFromQueue() end)
    Item(L.SETTINGS, function() Options:Open() end)
    self.actionRows = {}
end

--- A row of the menu, `index` rows down; `fn(row)` runs on click while a clip plays.
function MinimalPlayer:MenuItem(index, fn)
    local button = CreateFrame("Button", nil, self.menu)
    button:SetPoint("TOPLEFT", 10, -8 - (index - 1) * 23)
    button:SetPoint("TOPRIGHT", -10, -8 - (index - 1) * 23)
    button:SetHeight(23)
    button.text = Font(button, 12, 1, .82, 0)
    button.text:SetPoint("LEFT", 4, 0)
    button:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]])
    button:GetHighlightTexture():SetAlpha(.25)
    button:SetScript("OnClick", function()
        self.menu:Hide()
        self:HideTooltip()
        if self:HasClip() then fn(button) end
    end)
    return button
end

--- An icon action that names itself gets a menu row, "[icon] label", besides its button in the
--- header.
function MinimalPlayer:ActionRow(index)
    local row = self.actionRows[index]
    if row then return row end
    row = self:MenuItem(getn(self.menuButtons) + index, function(button)
        if button.action.onClick then button.action.onClick(self.frame.actions.clip) end
    end)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 4, 0)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    self.actionRows[index] = row
    return row
end

function MinimalPlayer:ConfigureActions()
    self.row = Actions:HeaderControls(self.frame, self.controls, self.buttons, self.clip)
    Actions.LayOutRow(self.controls, self.row, ROUND_GAP)
    local rows = 0
    for _, button in ipairs(self.frame.actions.buttons) do
        local action = button.action
        if action.anchor ~= "header" and action.icon and action.label then
            rows = rows + 1
            local row = self:ActionRow(rows)
            row.action = action
            row.icon:SetTexture(action.icon)
            row.text:SetText(action.label)
            row:Show()
        end
    end
    for index = rows + 1, getn(self.actionRows) do self.actionRows[index]:Hide() end
    self.menu:SetHeight(8 + (getn(self.menuButtons) + rows) * 23 + 9)
end

function MinimalPlayer:ToggleMenu()
    if not self:HasClip() then return end
    if self.menu:IsShown() then self.menu:Hide(); self:HideTooltip(); return end
    self:ConfigureActions()
    self:UpdateControls()
    self:HideTooltip()
    self.menu:ClearAllPoints()
    self.menu:SetPoint("TOPLEFT", self.frame, "BOTTOMLEFT", Config().HidePortrait and 12 or 36, 8)
    -- The window's parent, not UIParent, which a hosting dialog addon may have hidden.
    self.menu:SetParent(self.frame:GetParent())
    self.menu:SetFrameStrata("TOOLTIP")
    self.menu:SetScale(self.frame:GetScale())
    self.menu:Show()
end

function MinimalPlayer:StartDrag()
    if not Addon:IsFrameLocked() then self.menu:Hide(); self.frame:StartMoving() end
end

function MinimalPlayer:StopDrag()
    self.frame:StopMovingOrSizing()
    if not Addon:IsFrameLocked() then self:SaveLayout() end
end

-- Saved as the width with the portrait, which RefreshConfig takes off when hidden.
function MinimalPlayer:SaveLayout()
    Addon:SaveLayout("Minimal", self.frame, self.frame:GetWidth() + (Config().HidePortrait and 80 or 0))
end

function MinimalPlayer:ConfigurePortrait()
    if Config().HidePortrait then return end
    if not StaticPortrait:Configure(self.viewport, self.clip) then Portrait:Configure(self.viewport, self.clip) end
    local viewport = self.viewport
    if viewport.active == "texture" and viewport.texture then StaticPortrait:Mask(viewport, viewport.texture) end
    local id = self.clip.present and self.clip.present.bullet
    local texture = BADGES[id] or Bullets[id] and Bullets[id].texture
    self.badge:SetTexture(texture)
    self.badge:SetShown(texture ~= nil)
end

--- The parchment art this client draws, and where it is in PARCHMENTS: the one /spoken parchment
--- chose, or the first the client has. Nil where it has none.
function MinimalPlayer:Parchment()
    local list = self.PARCHMENTS
    local count, start = getn(list), self.parchmentIndex or 1
    for step = 0, count - 1 do
        local index = start + step
        if index > count then index = index - count end
        if Actions.HasAtlas(list[index]) then return list[index], index end
    end
end

--- The next parchment art the client has, drawn at once, for comparing them in game: its name,
--- where it is in the list and how long the list is. Nil where the client has none.
function MinimalPlayer:NextParchment()
    local _, current = self:Parchment()
    if not current then return nil end
    local count = getn(self.PARCHMENTS)
    for step = 1, count do
        local index = current + step
        if index > count then index = index - count end
        if Actions.HasAtlas(self.PARCHMENTS[index]) then
            self.parchmentIndex = index
            if self.frame then self:Dress() end
            return self.PARCHMENTS[index], index, count
        end
    end
end

--- The rock repeats once per 256 units, inside the inset.
function MinimalPlayer:TileRock()
    if not self.dark then return end
    local width, height = self.panel:GetWidth() or 0, self.panel:GetHeight() or 0
    self.paper:SetTexCoord(0, math.max(0, width - 14) / 256, 0, math.max(0, height - 14) / 256)
end

--- The panel in its background, and the name, the title and the words in colours that read on it.
function MinimalPlayer:Dress()
    local dark = Config().MinimalBackground == "dark"
    local look = dark and LOOKS.dark or LOOKS.parchment
    local paper = self.paper
    self.dark = dark
    if paper.SetHorizTile then paper:SetHorizTile(not dark); paper:SetVertTile(not dark) end
    local atlas = not dark and self:Parchment()
    if dark then
        paper:SetTexture(ART .. "MinimalBackground", "REPEAT", "REPEAT")
        self:TileRock()
    elseif atlas then
        paper:SetAtlas(atlas)
    elseif paper.SetColorTexture then
        paper:SetColorTexture(PARCHMENT_COLOR[1], PARCHMENT_COLOR[2], PARCHMENT_COLOR[3], 1)
    else
        paper:SetTexture(PARCHMENT_COLOR[1], PARCHMENT_COLOR[2], PARCHMENT_COLOR[3], 1)
    end
    local function Ink(text, color)
        text:SetTextColor(color[1], color[2], color[3])
        text:SetShadowColor(0, 0, 0, look.shadow)
    end
    Ink(self.name, look.name)
    Ink(self.title.text, look.title)
    Ink(self.stopped, look.tail)
    Ink(self.count, look.tail)
    Transcript:SetStyle(look.words)
end

function MinimalPlayer:UpdateControls()
    if not self.clip then return end
    local paused = SoundQueue:IsPaused()
    Actions.SetPlayGlyph(self.play, Actions.HeadState())
    -- The line's name alone, as the subtitle shows it: not why it waits.
    self.title.text:SetText(Label(self.clip))
    self.tail:SetStopped(paused)
    self:Count(Waiting())
    local pausable = SoundQueue:CanBePaused()
    for _, button in ipairs(self.buttons) do
        button:SetAlpha(pausable and 1 or .4)
        if pausable then button:Enable() else button:Disable() end
    end
    self.menuPlay.text:SetText(paused and L.REPLAY or L.STOP)
    for _, button in ipairs({ self.menuPlay, self.menuSkip, self.menuStop }) do
        if SoundQueue:CanBePaused() then button:Enable(); button.text:SetAlpha(1)
        else button:Disable(); button.text:SetAlpha(.35) end
    end
end

--- After the title, as the subtitle has them: "• (Stopped)" while the line is stopped, and the
--- lines waiting behind it, "• +N" (Actions.Tail). The title is cut short, not these.
function MinimalPlayer:Count(waiting)
    local tail = self.tail
    tail:SetCount(waiting)
    local room = tail:Room()
    local text = self.title.text
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT")
    text:SetPoint("BOTTOMRIGHT", -room, 0)
    if room == 0 then return end
    tail:Place(text, math.min(text:GetStringWidth() or 0, math.max(0, (self.title:GetWidth() or 0) - room)))
    tail:Paint()
end

function MinimalPlayer:UpdateProgress()
    local clip = self.clip
    if not clip then return end
    local duration = tonumber(clip.length) or 0
    self.seconds = Actions.Elapsed(clip, self.seconds)
    Actions.SetProgress(self.progress, duration > 0 and (self.seconds or 0) / duration or 0)
end

--- The window as tall as its words: the name and the title, the words under them in the panel's
--- width, and the progress line along their foot.
function MinimalPlayer:Layout()
    if not self.frame or self.layingOut then return end
    self.layingOut = true
    local cfg = Config()
    local words = Transcript:HeightForClip(self.clip)
    -- Show Progress, as the subtitle and the DialogueUI window have it.
    local progress = Addon:Profile("Transcript").SubtitleProgress ~= false
    local width = math.max(1, self.frame:GetWidth() - (cfg.HidePortrait and NO_PORTRAIT or BESIDE_PORTRAIT) - INSET)
    local bottom = words > 0 and WORDS_TOP + words or NAME_HEIGHT + TITLE_HEIGHT
    local barTop = bottom + PROGRESS_GAP
    if progress then bottom = barTop + self.progress.height end
    Transcript:ResizePlayer(self.frame, math.max(HEIGHT, INSET + bottom + FOOT), cfg.HidePortrait and 200 or 280, 1000)
    Transcript:Dock(self.frame, self.content, "TOPLEFT", 0, -WORDS_TOP, width, words)
    self.progress.track:SetShown(progress)
    self.progress.track:ClearAllPoints()
    self.progress.track:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -barTop)
    self.progress.track:SetWidth(width)
    self.panel:ClearAllPoints()
    -- The panel starts behind the portrait's centre and is centred on it vertically,
    -- so its left corners sit beneath the opaque disc and the text gets even margins.
    self.panel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", cfg.HidePortrait and 0 or 44, -6)
    self.panel:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 10)
    self.resizer:SetShown(not Addon:IsFrameLocked())
    self.layingOut = false
end

function MinimalPlayer:SetVisible(visible, immediate)
    if not self.frame then return end
    if not visible then self.menu:Hide(); self:HideTooltip() end
    if immediate then
        self.wanted = false
        self.frame:Hide()
        self.frame:SetAlpha(0)
        self.fadeTime = nil
        return
    end
    if self.wanted == visible then return end
    self.wanted = visible
    self.fadeFrom = self.frame:IsShown() and self.frame:GetAlpha() or 0
    self.fadeTime = 0
    if visible then self.frame:SetAlpha(self.fadeFrom); self.frame:Show() end
end

function MinimalPlayer:Tick(elapsed)
    if self.fadeTime then
        self.fadeTime = self.fadeTime + elapsed
        local t = Clamp(self.fadeTime / (self.wanted and .18 or .24), 0, 1)
        local eased = 1 - (1 - t) * (1 - t)
        self.frame:SetAlpha(self.fadeFrom + ((self.wanted and 1 or 0) - self.fadeFrom) * eased)
        if t == 1 then
            self.fadeTime = nil
            if not self.wanted then self.frame:Hide(); return end
        end
    end
    if not self.wanted then return end
    -- Stopped faded out: its room given back.
    if self.tail:Step(elapsed) then self:Count(Waiting()) end
    if StaticPortrait:Resolved() then self:ConfigurePortrait() end
    self:UpdateProgress()
    self.poll = (self.poll or 0) + elapsed
    if self.poll >= .2 then
        self.poll = 0
        self:UpdateControls()
        self.resizer:SetAlpha(MouseIsOver(self.frame) and .65 or 0)
    end
end

function MinimalPlayer:RefreshConfig(original)
    self:Initialize(original.frame)
    local cfg, frame = Config(), self.frame
    frame:SetScale(cfg.FrameScale)
    frame:SetFrameStrata(cfg.FrameStrata)
    frame:SetResizeBounds(cfg.HidePortrait and 200 or 280, frame:GetHeight(), 1000, frame:GetHeight())
    local saved = Addon:Layout().Minimal
    frame:SetWidth(Clamp((saved and saved.width or cfg.MinimalWidth or WIDTH) - (cfg.HidePortrait and 80 or 0), cfg.HidePortrait and 200 or 280, 1000))
    self.content:ClearAllPoints()
    self.content:SetPoint("TOPLEFT", cfg.HidePortrait and NO_PORTRAIT or BESIDE_PORTRAIT, -INSET)
    self.content:SetPoint("TOPRIGHT", -INSET, -INSET)
    self.portrait:SetShown(not cfg.HidePortrait)
    local r, g, b = 1, 1, 1
    if BRONZE and cfg.BronzeTint then r, g, b = unpack(BRONZE) end
    self.panel:SetBackdropBorderColor(r, g, b)
    Actions.TintProgress(self.progress, r, g, b)
    self.ring:SetVertexColor(r, g, b)
    self:Dress()
    if Addon:IsFrameLocked() then frame:StopMovingOrSizing(); self.sizing = false end
    -- Locked, clicks on the window pass through to the game, as the subtitle's do; its buttons
    -- still take theirs, and the header still opens the menu. Where the client cannot tell a
    -- click from the pointer passing over, the window keeps both.
    if frame.SetMouseClickEnabled and frame.SetMouseMotionEnabled then
        frame:SetMouseMotionEnabled(true)
        frame:SetMouseClickEnabled(not Addon:IsFrameLocked())
    end
    Addon:ApplyHost(frame)
    self:Update()
end

function MinimalPlayer:Update()
    if not self.frame then return end
    if not self:IsEnabled() then self:SetVisible(false, true); return end
    local clip = PlayerFrame:Current()
    if not clip then self:SetVisible(false); return end
    if clip ~= self.clip then
        self.menu:Hide()
        self:HideTooltip()
        self.clip, self.seconds = clip, 0
    end
    self:SetVisible(true)
    -- Said once: a name the same as the line's own is left off, as the subtitle leaves it.
    local header = clip.present and clip.present.header
    self.name:SetText(header ~= Label(clip) and header or "")
    self:ConfigurePortrait()
    self:ConfigureActions()
    self:Layout()
    self:UpdateProgress()
    self:UpdateControls()
end

function MinimalPlayer:Reset()
    if not self.frame then return end
    self.frame:StopMovingOrSizing()
    Config().MinimalWidth = WIDTH
    Addon:Layout().Minimal = nil
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
    self:RefreshConfig(PlayerFrame)
end

function MinimalPlayer:Describe()
    return format("minimal=%s visible=%s portrait=%s background=%s parchment=%s progress=%.1fs",
        tostring(self:IsEnabled()), tostring(self.frame and self.frame:IsShown()),
        tostring(self.viewport and self.viewport.active), tostring(Config().MinimalBackground),
        tostring((self:Parchment())), self.seconds or 0)
end
