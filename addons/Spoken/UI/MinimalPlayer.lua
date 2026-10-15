setfenv(1, SpokenEnv)

-- The "minimal" narrator style, the Small Window: the speaker's portrait beside a panel with the
-- name, the line's title, its words and the round controls. Playback and source-owned actions
-- belong to the queue and actions services.
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
-- Between the name or the title and the header's buttons; between the buttons.
local CONTROLS_CLEAR, ROUND_GAP = 8, 4
local BRONZE = Actions.BRONZE
-- The smallest a portrait's badge is drawn, on a face smaller than the Small Window's.
local BADGE_LEAST = 12
-- The narrowest the window goes, and the room the portrait takes left of the panel.
local function MinWidth() return Addon:Profile("Frame").HidePortrait and 200 or 280 end
local function PortraitWidth() return Addon:Profile("Frame").HidePortrait and 80 or 0 end
-- The text colours for each background (Frame.MinimalBackground): dark ink with no shadow on
-- parchment, light text on the rock.
local LOOKS = {
    parchment = { name = { .19, .17, .13 }, title = { .19, .17, .13 }, tail = { .50, .36, .24 }, shadow = 0,
        words = { color = { .19, .17, .13 }, shadow = false, highlight = "|cff9c1a1a" } },
    dark = { name = { 1, .82, 0 }, title = { .88, .84, .76 }, tail = { .62, .58, .46 }, shadow = 1 },
}
-- Shipped with Spoken: the Classic clients list the retail parchment atlases without their art,
-- so those draw nothing.
local PARCHMENT = ART .. "MinimalParchment"
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
-- A line with no label (a one-page letter) goes by its header: its key means nothing to a player.
local function Label(clip)
    local present = clip and clip.present
    return clip and (present and (present.label or present.header) or clip.key) or ""
end
-- The name over the title: the header, unless it is already the title (a line with no label).
local function Name(clip)
    local present = clip and clip.present
    return present and present.label and present.header or ""
end
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
MinimalPlayer.parts = { Font = Font, Label = Label, Name = Name, Clamp = Clamp, Waiting = Waiting,
    BelongsTo = BelongsTo }

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
    self.fader = Actions.Fader(frame, function() return { self.viewport and self.viewport.model } end, function()
        -- Faded out for a turn: show the next line.
        if self.turning then self.turning = nil; self:Update() end
    end)

    self.panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    self.panel:SetBackdrop({
        edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]], edgeSize = 24,
        insets = { left = 7, right = 7, top = 7, bottom = 7 },
    })
    -- The rock is tiled by hand: the backdrop's own tiling stretches it when the words make the
    -- panel taller.
    self.paper = self.panel:CreateTexture(nil, "BACKGROUND")
    self.paper:SetPoint("TOPLEFT", 7, -7)
    self.paper:SetPoint("BOTTOMRIGHT", -7, 7)
    self.panel:SetScript("OnSizeChanged", function() self:TileRock() end)

    local content = CreateFrame("Frame", nil, frame)
    self.content, frame.container = content, content
    content:SetHeight(76)
    content:SetFrameLevel(self.panel:GetFrameLevel() + 1)
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
    self.title = CreateFrame("Frame", nil, content)
    self.title:SetHeight(TITLE_HEIGHT)
    self.title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -NAME_HEIGHT)
    self.title:SetPoint("RIGHT", self.controls, "LEFT", -CONTROLS_CLEAR, 0)
    self.title.text = Font(self.title, 12, .88, .84, .76)
    self.stopped = Font(self.title, 12, .62, .58, .46)
    self.stopped:SetText(format("• (%s)", L.SUBTITLE_STOPPED))
    self.stopped:Hide()
    self.count = Font(self.title, 12, .62, .58, .46)
    self.count:Hide()
    self.held = Font(self.title, 12, .62, .58, .46)
    self.held:Hide()
    self.tail = Actions.Tail(self.stopped, self.count, self.held)

    self.progress = Actions.ProgressBar(content)

    self:BuildPortrait()
    self:BuildMenu()
    Actions:Build(frame)

    self.resizer = CreateFrame("Button", nil, frame)
    self.resizer:SetSize(12, 12)
    self.resizer:SetPoint("BOTTOMRIGHT", -5, 12)
    -- The client's own, as Azeroth's Compendium's. The Small Window is not offered on the legacy
    -- clients.
    self.resizer:SetNormalTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
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

-- The round face, `size` across: a dark backing, the speaker in a viewport clipped to it, the
-- ring, and the line's badge on a small dark disc at the lower right. Placed on the ring art's
-- 71-unit grid, so it is the Small Window's portrait (90) at any size. `level` is the face's
-- frame level, set before its ring is built above it.
local function BuildFace(parent, size, level)
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(size, size)
    if level then host:SetFrameLevel(level) end
    local function At(units) return size * units / 71 end
    local background = host:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetTexture(ART .. "MinimalPortraitBackground")

    host.viewport = CreateFrame("Frame", nil, host)
    host.viewport:SetSize(size * 78 / 90, size * 78 / 90)
    host.viewport:SetPoint("CENTER", host, "TOPLEFT", At(35), -At(34))
    host.viewport:SetClipsChildren(true)
    local chrome = CreateFrame("Frame", nil, host)
    chrome:SetAllPoints()
    chrome:SetFrameLevel(host:GetFrameLevel() + 8)
    -- At least BADGE_LEAST: at a small face's own scale the glyph is too small to make out.
    local badge = math.max(size * 16 / 90, BADGE_LEAST)
    -- Unit-frame badge centres are backed separately from their metal ring.
    -- Without this disc the speaker's face shows through the speech-bubble badge.
    host.badgeBackground = chrome:CreateTexture(nil, "BACKGROUND")
    host.badgeBackground:SetSize(badge * 1.5, badge * 1.5)
    host.badgeBackground:SetPoint("CENTER", host, "TOPLEFT", At(56.5), -At(56.5))
    host.badgeBackground:SetTexture(ART .. "MinimalPortraitMask")
    host.badgeBackground:SetVertexColor(.04, .04, .035, 1)
    host.ring = chrome:CreateTexture(nil, "ARTWORK")
    host.ring:SetAllPoints()
    host.ring:SetTexture(ART .. "MinimalPortraitRing")
    host.badge = chrome:CreateTexture(nil, "OVERLAY")
    host.badge:SetSize(badge, badge)
    host.badge:SetPoint("CENTER", host, "TOPLEFT", At(56.5), -At(56.5))
    return host
end

function MinimalPlayer:BuildPortrait()
    local host = BuildFace(self.frame, 90, self.content:GetFrameLevel() + 2)
    self.portrait, self.frame.portrait = host, host
    host:SetPoint("TOPLEFT", 0, -4)
    self.viewport, self.ring = host.viewport, host.ring
    self.badgeBackground, self.badge = host.badgeBackground, host.badge
end

--------------------------------------------------------------------------------
-- A speaker's face on a page of a feature addon's (Spoken:CreateSpeakerFace)
--------------------------------------------------------------------------------

-- What the Small Window shows where it has no face to draw, as Present gives it: the book for a
-- creature, a posted notice for an object or an item with no picture of its own.
local BOOK = ART .. "Book"
local NOTICE = [[Interface\Icons\INV_Misc_Note_01]]
local ICON_CROP = { .08, .92, .08, .92 }
local UNITS = { "npc", "target", "mouseover", "focus" }
-- How long a face drawn before the client has its creature keeps asking for it. StaticPortrait
-- stops asking the server after 5 seconds; the face keeps the book from then on.
local FACE_WAIT = 6
local Face = {}

-- The presentation spec for a speaker, as Present:Portrait builds it for a line.
local function SpecFor(speaker)
    if speaker.objectOrItem then
        return { kind = "texture", texture = speaker.icon or NOTICE, texCoord = ICON_CROP }
    end
    return { kind = "model", creatureID = speaker.creatureID, animation = 60,
        fallback = { kind = "texture", texture = BOOK } }
end

-- The speaker's unit-frame portrait, as StaticPortrait draws it: from its unit while one with its
-- GUID is about, else from its creature's appearance. Painted on the face's own texture rather
-- than StaticPortrait's cached one, which moves to whichever viewport shows it last: two faces of
-- one NPC on a page, or a page and the Small Window, would take it from each other.
local function Still(face, speaker)
    local guid = speaker.guid
    -- A quest-log GUID is made up, and names no unit.
    if guid and UnitGUID and SetPortraitTexture and not string.find(guid, "^Creature%-0%-0%-0%-0%-") then
        for _, unit in ipairs(UNITS) do
            if NotSecret(UnitGUID(unit)) == guid then
                SetPortraitTexture(face.still, unit)
                return true
            end
        end
    end
    local display = speaker.creatureID and SetPortraitTextureFromCreatureDisplayID
        and StaticPortrait:Prime(speaker.creatureID)
    if not display then return false end
    SetPortraitTextureFromCreatureDisplayID(face.still, display)
    return true
end

--- Draws the speaker: their still where there is one, else the Small Window's fallback picture
--- (the book, or an object's or item's picture), never an empty socket. A creature the client has
--- not cached yet shows the book and is asked for every frame the face is shown, until it comes.
function Face:Draw()
    local speaker, viewport = self.speaker, self.viewport
    local spec = SpecFor(speaker)
    self.waiting = nil
    if spec.kind == "model" and Still(self, speaker) then
        -- Whatever Portrait drew here before, put away.
        Portrait:Configure(viewport, nil)
        self.still:Show()
    else
        self.still:Hide()
        if spec.kind == "model" and speaker.creatureID then
            self.waiting, self.since = speaker.creatureID, GetTime()
        end
        Portrait:Configure(viewport, { present = { portrait = spec.kind == "model" and spec.fallback or spec } })
        if viewport.texture then StaticPortrait:Mask(viewport, viewport.texture) end
    end
    self:SetScript("OnUpdate", self.waiting and Face.Wait or nil)
end

function Face.Wait(self)
    if not self.waiting then
        self:SetScript("OnUpdate", nil)
    elseif StaticPortrait:Prime(self.waiting) then
        self:Draw()
    elseif GetTime() - self.since > FACE_WAIT then
        self.waiting = nil
        self:SetScript("OnUpdate", nil)
    end
end

function Face:SetSpeaker(speaker)
    self.speaker = speaker or {}
    local id = self.speaker.bullet
    local badge = BADGES[id] or Bullets[id] and Bullets[id].texture
    self.badge:SetTexture(badge)
    self.badge:SetShown(badge ~= nil)
    self.badgeBackground:SetShown(badge ~= nil)
    -- Bronze Border tints the ring, as it does the Small Window's.
    if self.ring then
        local r, g, b = 1, 1, 1
        if BRONZE and Addon.db and Addon:Bronze() then r, g, b = BRONZE[1], BRONZE[2], BRONZE[3] end
        self.ring:SetVertexColor(r, g, b)
    end
    self:Draw()
end

--- The Small Window's portrait, `size` across, on `parent`, for a page to show who speaks.
function MinimalPlayer:CreateFace(parent, size)
    return self:DrawSpeakers(BuildFace(parent, size))
end

--- Gives `face` SetSpeaker: a frame with a `viewport` clipped round, a `badge` and its
--- `badgeBackground`, and a `ring` where it has one.
function MinimalPlayer:DrawSpeakers(face)
    face.still = face.viewport:CreateTexture(nil, "ARTWORK")
    face.still:SetAllPoints()
    face.still:Hide()
    StaticPortrait:Mask(face.viewport, face.still)
    face.SetSpeaker, face.Draw = Face.SetSpeaker, Face.Draw
    face:SetSpeaker(nil)
    return face
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

--- An icon action that names itself also gets a menu row, "[icon] label".
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
    Addon:SaveLayout("Minimal", self.frame, self.frame:GetWidth() + PortraitWidth())
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

--- The rock repeats once per 256 units, inside the inset.
function MinimalPlayer:TileRock()
    if not self.dark then return end
    local width, height = self.panel:GetWidth() or 0, self.panel:GetHeight() or 0
    self.paper:SetTexCoord(0, math.max(0, width - 14) / 256, 0, math.max(0, height - 14) / 256)
end

--- Paints the panel's background, and the text in colours that read on it.
function MinimalPlayer:Dress()
    local dark = Config().MinimalBackground == "dark"
    local look = dark and LOOKS.dark or LOOKS.parchment
    local paper = self.paper
    self.dark = dark
    if dark then
        paper:SetTexture(ART .. "MinimalBackground", "REPEAT", "REPEAT")
        self:TileRock()
    else
        paper:SetTexture(PARCHMENT)
        paper:SetTexCoord(0, 1, 0, 1)
    end
    local function Ink(text, color)
        text:SetTextColor(color[1], color[2], color[3])
        text:SetShadowColor(0, 0, 0, look.shadow)
    end
    Ink(self.name, look.name)
    Ink(self.title.text, look.title)
    Ink(self.stopped, look.tail)
    Ink(self.count, look.tail)
    Ink(self.held, look.tail)
    Transcript:SetStyle(look.words)
end

function MinimalPlayer:UpdateControls()
    if not self.clip then return end
    local paused = SoundQueue:IsPaused()
    Actions.SetPlayGlyph(self.play, Actions.HeadState())
    self.title.text:SetText(Label(self.clip))
    Addon:ClipFont(self.title.text, self.clip)
    self.tail:SetHeld(SoundQueue:GetHeldReason(self.clip))
    self.tail:SetStopped(paused)
    self:Count(Waiting())
    local pausable = Actions.SetPausable(self.buttons)
    self.menuPlay.text:SetText(paused and L.REPLAY or L.STOP)
    for _, button in ipairs({ self.menuPlay, self.menuSkip, self.menuStop }) do
        if pausable then button:Enable(); button.text:SetAlpha(1)
        else button:Disable(); button.text:SetAlpha(.35) end
    end
end

--- Puts the tail after the title: the title is cut short, not it.
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
    self.seconds = Actions.Elapsed(clip, self.seconds)
    Actions.SetProgress(self.progress, SoundQueue:Share(clip, self.seconds))
end

--- The window as tall as its words, with the progress line along their foot.
function MinimalPlayer:Layout()
    if not self.frame or self.layingOut then return end
    self.layingOut = true
    local cfg = Config()
    local words = Transcript:HeightForClip(self.clip)
    -- Show Progress, one setting for every window.
    local progress = Addon:Profile("Transcript").SubtitleProgress ~= false
    local width = math.max(1, self.frame:GetWidth() - (cfg.HidePortrait and NO_PORTRAIT or BESIDE_PORTRAIT) - INSET)
    local bottom = words > 0 and WORDS_TOP + words or NAME_HEIGHT + TITLE_HEIGHT
    local barTop = bottom + PROGRESS_GAP
    if progress then bottom = barTop + self.progress.height end
    Transcript:ResizePlayer(self.frame, math.max(HEIGHT, INSET + bottom + FOOT), MinWidth(), 1000)
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
    self.wanted = visible and true or false
    self.fader:Set(visible, immediate)
end

function MinimalPlayer:Tick(elapsed)
    if not self.wanted then return end
    -- Once "(Stopped)" has faded out, the title gets its room back.
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
    frame:SetResizeBounds(MinWidth(), frame:GetHeight(), 1000, frame:GetHeight())
    local saved = Addon:Layout().Minimal
    frame:SetWidth(Clamp((saved and saved.width or cfg.MinimalWidth or WIDTH) - PortraitWidth(), MinWidth(), 1000))
    self.content:ClearAllPoints()
    self.content:SetPoint("TOPLEFT", cfg.HidePortrait and NO_PORTRAIT or BESIDE_PORTRAIT, -INSET)
    self.content:SetPoint("TOPRIGHT", -INSET, -INSET)
    self.portrait:SetShown(not cfg.HidePortrait)
    local r, g, b = 1, 1, 1
    if BRONZE and Addon:Bronze() then r, g, b = BRONZE[1], BRONZE[2], BRONZE[3] end
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

--- Whether this window, showing a line, will fade out before it shows `clip`.
function MinimalPlayer:WillTurn(clip)
    return self:IsEnabled() and self.frame ~= nil and self.clip ~= nil and clip ~= self.clip and self.wanted
        and self.frame:IsShown() and not Actions.DialogCovers() and true or false
end

function MinimalPlayer:Update()
    if not self.frame then return end
    if not self:IsEnabled() then self.turning = nil; self:SetVisible(false, true); return end
    local clip = PlayerFrame:Current()
    if not clip or Actions.DialogCovers() then self.turning = nil; self:SetVisible(false); return end
    -- Mid-turn: the fader's callback shows the next line once faded out.
    if self.turning and self.frame:IsShown() then return end
    -- A new line while one shows: fade out whole first, so the change happens unseen.
    if clip ~= self.clip and self.clip and self.wanted and self.frame:IsShown() then
        self.turning = true
        self:SetVisible(false)
        return
    end
    if clip ~= self.clip then
        self.menu:Hide()
        self:HideTooltip()
        self.clip, self.seconds = clip, 0
    end
    self:SetVisible(true)
    -- A speaker name the same as the line's own is left off, so it is not said twice.
    local name = Name(clip)
    self.name:SetText(name ~= Label(clip) and name or "")
    Addon:ClipFont(self.name, clip)
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
    return format("minimal=%s visible=%s portrait=%s background=%s progress=%.1fs",
        tostring(self:IsEnabled()), tostring(self.frame and self.frame:IsShown()),
        tostring(self.viewport and self.viewport.active), tostring(Config().MinimalBackground),
        self.seconds or 0)
end
