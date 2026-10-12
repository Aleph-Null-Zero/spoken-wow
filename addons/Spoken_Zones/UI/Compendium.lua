-- Azeroth's Compendium: one window, a tab for each Spoken part that has something to browse --
-- the places (Spoken Zones), the writings (Spoken Books) -- each a list on the left and a page on
-- the right.
--
-- Carried byte for byte by every addon that adds a tab, as UI/Layout.lua is, so either works on its
-- own and both together share one window: the newest copy loaded wins (VERSION), and a tab
-- registered by any copy is kept. The window is the game's portrait frame, resizable from its corner
-- and folding down to the list. The list is a search box over an inset of rows, with Discovered Only
-- and the tab's other switches in the filter menu beside the search. Its rows are drawn in the
-- game's own art: the objective tracker's campaign bar across the list for each group (a
-- continent), the character select card for each place or set inside one (its painting in the
-- collections window's gold frame, the name, a grey line under it, the share found and the Pet
-- Journal's bar), and a plain row for each single thing, a padlock on what is not found yet. What
-- is inside an open card is indented under it, a faint gold line down its left. What the rows are,
-- what a click does and the page beside them are each tab's own.
--
-- A tab: SpokenCompendium:Register(key, { label, order, title, build(panel), onShow(panel),
-- store = { get(key), set(key, value) }, open(), enabled(), unlock = { get(), set(value) } }).
-- build lays the tab out in `panel`, which fills the window, and sets panel.pageInset, folded away
-- with the window. title is the window's, from the first tab registered; store keeps the window's
-- size, from the first tab that has one. open shows the tab as its part wants it opened, enabled
-- says whether its part is on, and unlock is its Unlock switch, which Spoken's page shows
-- (SpokenCompendium:Toggle opens the window from there and from the minimap menu). Shared
-- with the tabs too: the zones' tree (C.MapName, C.ContinentOf, C.CITY_IN) and the parchment page
-- (C.NewPage).

local VERSION = 9

if SpokenCompendium and (SpokenCompendium.VERSION or 0) >= VERSION then
	return
end

local C = SpokenCompendium or {}
SpokenCompendium = C
C.VERSION = VERSION
C.tabs = C.tabs or {}

local WINDOW_WIDTH = 920
local WINDOW_HEIGHT = 600
local WINDOW_MIN_HEIGHT = 360
-- Room for the longest zone name in any language (Portuguese's Cordilheira das Torres de
-- Pedra) beside its count, found out of all and the share: 27/27 • 100%.
local LIST_WIDTH = 345
-- The narrowest the page beside the list lays out at.
local PAGE_MIN_WIDTH = 278
local BANNER_ROW = 36
local BANNER_GAP = 14         -- above each banner but the first
local FIRST_GAP = 2           -- above the first row
local UNDER_BANNER = 8        -- between a banner and the first card in it
local CARD_ROW = 60
local SMALL_CARD_ROW = 52
local CARD_GAP = 6            -- between cards under a banner
local LEAF_ROW = 26
local NEST_GAP = 5            -- between the rows inside an open card
local NEST_PAD = 2            -- inside the line down an open card's contents, above and below them
local NEST_AFTER = 6          -- under an open card's contents
local NEST_STEP = 28          -- each card's contents in, under the open card they belong to
local RAIL_X = 16             -- the line down an open card's contents, this far into the step
local LIST_LEFT, LIST_RIGHT = 7, 2 -- room in the list for a chosen card's glow
local LIST_TOP, LIST_FOOT = 6, 8
local SCROLL_STEP = 60
local GRABBER_SIZE = 16
local FILTER_ROOM = 26       -- what the search box gives up for the filter menu's arrow beside it
local NAME = "SpokenCompendiumWindow"
-- The window's portrait: a tome from the game, the Compendium's own rather than any one part's.
local ICON = [[Interface\Icons\INV_Misc_Book_11]]
C.LIST_WIDTH, C.ICON = LIST_WIDTH, ICON

local GRABBER_UP = [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]]
local GRABBER_DOWN = [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Down]]
local GRABBER_HIGHLIGHT = [[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]]
local SMALLER_UP = [[Interface\Buttons\UI-Panel-SmallerButton-Up]]
local SMALLER_DOWN = [[Interface\Buttons\UI-Panel-SmallerButton-Down]]
local BIGGER_UP = [[Interface\Buttons\UI-Panel-BiggerButton-Up]]
local BIGGER_DOWN = [[Interface\Buttons\UI-Panel-BiggerButton-Down]]
local PANEL_HI = [[Interface\Buttons\UI-Panel-MinimizeButton-Highlight]]

--------------------------------------------------------------------------------
-- Art with a way out
--------------------------------------------------------------------------------

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil or false
end
C.HasAtlas = HasAtlas

-- Paint `texture` with the game's atlas and say so, or leave it alone and say not: a missing
-- atlas draws nothing at all.
local function Atlas(texture, atlas, useAtlasSize)
	if texture.SetAtlas and HasAtlas(atlas) then
		texture:SetAtlas(atlas, useAtlasSize)
		return true
	end
	return false
end

-- Where `atlas` sits in its file, for drawing a piece of it: nil where the client has not got it,
-- or does not say.
local function AtlasSpot(atlas)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	local file = info and (info.file or info.filename)
	if not file or not info.leftTexCoord or not info.rightTexCoord or not info.topTexCoord
		or not info.bottomTexCoord or (info.width or 0) <= 0 or (info.height or 0) <= 0 then
		return nil
	end
	return info
end

-- `texture` showing the part of the atlas at `spot` from x1 to x2 and y1 to y2, in the atlas's own
-- pixels; turned left to right with `mirror`.
local function AtlasCut(texture, spot, x1, x2, y1, y2, mirror)
	local l, r, t, b = spot.leftTexCoord, spot.rightTexCoord, spot.topTexCoord, spot.bottomTexCoord
	local u1, u2 = l + (r - l) * x1 / spot.width, l + (r - l) * x2 / spot.width
	if mirror then u1, u2 = u2, u1 end
	texture:SetTexture(spot.file or spot.filename)
	texture:SetTexCoord(u1, u2, t + (b - t) * y1 / spot.height, t + (b - t) * y2 / spot.height)
end

local function Sound(kit)
	if SpokenLayout and SpokenLayout.Sound then SpokenLayout.Sound(kit) end
end

--------------------------------------------------------------------------------
-- The tabs
--------------------------------------------------------------------------------

local window, tabButtons
local active
local minimized = false
local resizer, minimizeButton, minimizeFrame

local function Ordered()
	local list = {}
	for key, tab in pairs(C.tabs) do
		tab.key = key
		table.insert(list, tab)
	end
	table.sort(list, function(a, b)
		if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
		return a.key < b.key
	end)
	return list
end

local function Store()
	for _, tab in ipairs(Ordered()) do
		if tab.store then return tab.store end
	end
end

-- The list's margins inside the window, left and right, and how far below its top the tab's
-- content starts: a templated frame's portrait takes the top-left corner.
function C.Margins()
	if window and window.templated then
		return 6, 6, -24
	end
	return 14, 12, -36
end

--------------------------------------------------------------------------------
-- The window's size
--------------------------------------------------------------------------------

local function CollapsedWidth()
	local left, right = C.Margins()
	return LIST_WIDTH + left + right
end

local function MinWidth()
	local left, right = C.Margins()
	return LIST_WIDTH + left + right + PAGE_MIN_WIDTH
end

local function ScreenMaxWidth()
	return math.floor((UIParent:GetWidth() or 1920) * 0.95)
end

local function ScreenMaxHeight()
	return math.floor((UIParent:GetHeight() or 1080) * 0.95)
end

local function ApplyResizeBounds()
	local maxW = minimized and CollapsedWidth() or ScreenMaxWidth()
	local minW = minimized and CollapsedWidth() or MinWidth()
	if window.SetResizeBounds then
		window:SetResizeBounds(minW, WINDOW_MIN_HEIGHT, maxW, ScreenMaxHeight())
	else
		window:SetMinResize(minW, WINDOW_MIN_HEIGHT)
		window:SetMaxResize(maxW, ScreenMaxHeight())
	end
end

-- StartSizing does not hold the opposite corner still. Anchored at CENTER, that corner moves
-- away from the cursor every frame and the size runs to its bound.
local function PinTopLeft()
	local left, top = window:GetLeft(), window:GetTop()
	if not left or not top then
		return
	end
	window:ClearAllPoints()
	window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

-- Saved sizes are clamped on the way in: a size persisted by the runaway would otherwise
-- reopen at the bound for good.
local function SavedSize(key, min, max, fallback)
	local store = Store()
	local saved = store and store.get(key)
	if type(saved) ~= "number" or saved < min then
		return fallback
	end
	return math.min(saved, max)
end

local function ExpandedWidth()
	return SavedSize("width", MinWidth(), ScreenMaxWidth(), WINDOW_WIDTH)
end

local function SavedHeight()
	return SavedSize("height", WINDOW_MIN_HEIGHT, ScreenMaxHeight(), WINDOW_HEIGHT)
end

local function SaveWindowSize()
	local store = Store()
	local width, height = window:GetSize()
	if not store or not width or not height or width <= 0 or height <= 0 then
		return
	end
	store.set("height", math.floor(height + 0.5))
	if not minimized then
		store.set("width", math.floor(width + 0.5))
	end
end

local function SetCollapseArrow()
	if minimizeFrame then
		minimizeFrame.MaximizeButton:SetShown(minimized)
		minimizeFrame.MinimizeButton:SetShown(not minimized)
		return
	end
	if not minimizeButton then
		return
	end
	if minimized then
		minimizeButton:SetNormalTexture(BIGGER_UP)
		minimizeButton:SetPushedTexture(BIGGER_DOWN)
	else
		minimizeButton:SetNormalTexture(SMALLER_UP)
		minimizeButton:SetPushedTexture(SMALLER_DOWN)
	end
end

-- Folded down to the list: the page goes, and only the height resizes, so folding never reflows
-- the rows.
local function ShowPages()
	for _, tab in pairs(C.tabs) do
		if tab.panel and tab.panel.pageInset then tab.panel.pageInset:SetShown(not minimized) end
	end
end

local function SetMinimized(want)
	if not window or want == minimized then
		return
	end
	minimized = want
	ApplyResizeBounds()
	PinTopLeft()
	window:SetWidth(minimized and CollapsedWidth() or ExpandedWidth())
	ShowPages()
	SetCollapseArrow()
	if not minimized and active and C.tabs[active].panel and C.tabs[active].panel.Refresh then
		C.tabs[active].panel:Refresh()
	end
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

-- The game's portrait frame where the client has it: its border, title bar, portrait and close
-- button. A plain dialog box where it does not.
local function NewWindow(title, icon)
	local ok, frame = pcall(CreateFrame, "Frame", NAME, UIParent, "PortraitFrameTemplate")
	if ok and frame and frame.SetTitle then
		frame:SetTitle(title)
		if frame.SetPortraitToAsset and icon then frame:SetPortraitToAsset(icon) end
		frame.templated = true
		return frame
	end
	frame = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	local text = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	text:SetPoint("TOP", frame, "TOP", 0, -14)
	text:SetText(title)
	frame.titleText = text
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -8)
	close:SetScript("OnClick", function() frame:Hide() end)
	frame.CloseButton = close
	return frame
end

local function BuildChrome()
	local close = type(window.CloseButton) == "table" and window.CloseButton
	if close then
		local buttonSize = math.max((close:GetWidth() > 0 and close:GetWidth() or 32) - 2, 24)
		close:SetSize(buttonSize, buttonSize)
		close:ClearAllPoints()
		if window.templated then
			close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -1)
		else
			close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -10, -8)
		end

		local ok, mm = pcall(CreateFrame, "Frame", nil, window, "MaximizeMinimizeButtonFrameTemplate")
		if ok and mm and mm.MaximizeButton and mm.MinimizeButton then
			minimizeFrame = mm
			mm:ClearAllPoints()
			mm:SetPoint("RIGHT", close, "LEFT", 0, 0)
			mm:SetFrameLevel(close:GetFrameLevel())
			mm.MinimizeButton:SetSize(buttonSize, buttonSize)
			mm.MaximizeButton:SetSize(buttonSize, buttonSize)
			mm.MinimizeButton:SetScript("OnClick", function() SetMinimized(true) end)
			mm.MaximizeButton:SetScript("OnClick", function() SetMinimized(false) end)
		else
			minimizeButton = CreateFrame("Button", nil, window)
			minimizeButton:SetSize(buttonSize, buttonSize)
			minimizeButton:SetPoint("RIGHT", close, "LEFT", 0, 0)
			minimizeButton:SetFrameLevel(close:GetFrameLevel())
			minimizeButton:SetHighlightTexture(PANEL_HI)
			minimizeButton:SetScript("OnClick", function() SetMinimized(not minimized) end)
		end
		SetCollapseArrow()
	end

	resizer = CreateFrame("Button", nil, window)
	resizer:SetPoint("BOTTOMRIGHT", -2, 2)
	resizer:SetSize(GRABBER_SIZE, GRABBER_SIZE)
	resizer:SetNormalTexture(GRABBER_UP)
	resizer:SetPushedTexture(GRABBER_DOWN)
	resizer:SetHighlightTexture(GRABBER_HIGHLIGHT)
	resizer:SetFrameLevel(window:GetFrameLevel() + 5)
	resizer:SetScript("OnEnter", function() SetCursor([[Interface\Cursor\UI-Cursor-SizeRight]]) end)
	resizer:SetScript("OnLeave", function() SetCursor(nil) end)
	resizer:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then
			return
		end
		local highlight = resizer:GetHighlightTexture()
		if highlight then highlight:Hide() end
		PinTopLeft()
		window:StartSizing("BOTTOMRIGHT")
	end)
	resizer:SetScript("OnMouseUp", function()
		local highlight = resizer:GetHighlightTexture()
		if highlight then highlight:Show() end
		window:StopMovingOrSizing()
		SaveWindowSize()
		SetCursor(nil)
	end)
end

-- The tabs along the window's foot, as the character sheet has them; none with only one.
local function NewTab(index, label)
	local tab
	for _, template in ipairs({ "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate" }) do
		local ok, button = pcall(CreateFrame, "Button", NAME .. "Tab" .. index, window, template)
		if ok and button then
			tab = button
			tab.template = template
			break
		end
	end
	if not tab then
		tab = CreateFrame("Button", NAME .. "Tab" .. index, window, "UIPanelButtonTemplate")
		tab:SetSize(110, 22)
	end
	tab:SetID(index)
	tab:SetText(label)
	if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
	return tab
end

-- Whether a tab's part is on: a tab that does not say always is.
local function Enabled(tab)
	return not tab.enabled or (tab.enabled() and true or false)
end

-- Only the tabs whose part is on: a part switched off in Spoken's settings takes its tab away.
local function LayOutTabs()
	local list = {}
	for _, def in ipairs(Ordered()) do
		if Enabled(def) then table.insert(list, def) end
	end
	tabButtons = tabButtons or {}
	for i, def in ipairs(list) do
		local button = tabButtons[i] or NewTab(i, def.label)
		tabButtons[i] = button
		button:SetText(def.label)
		button.key = def.key
		button:ClearAllPoints()
		if i == 1 then
			button:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 12, 2)
		else
			-- The character sheet's tabs overlap, each tucked under the one before.
			local gap = button.template == "CharacterFrameTabButtonTemplate" and -15 or 3
			button:SetPoint("LEFT", tabButtons[i - 1], "RIGHT", gap, 0)
		end
		button:SetScript("OnClick", function(self)
			Sound("igCharacterInfoTab")
			C:Select(self.key)
		end)
		button:SetShown(#list > 1)
	end
	for i = #list + 1, #tabButtons do tabButtons[i]:Hide() end
end

local function PaintTabs()
	if not tabButtons then return end
	for _, button in ipairs(tabButtons) do
		local selected = button.key == active
		if PanelTemplates_SelectTab and PanelTemplates_DeselectTab then
			if selected then pcall(PanelTemplates_SelectTab, button) else pcall(PanelTemplates_DeselectTab, button) end
		elseif button.LockHighlight then
			if selected then button:LockHighlight() else button:UnlockHighlight() end
		end
		button.selected = selected
	end
end

local function BuildWindow()
	local first = Ordered()[1]
	window = NewWindow(first and first.title or "", ICON)
	window:SetSize(ExpandedWidth(), SavedHeight())
	window:SetPoint("CENTER")
	window:SetFrameStrata("HIGH")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:SetResizable(true)
	window:SetClampedToScreen(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetScript("OnShow", function()
		-- The screen may have changed size since the bounds were last set.
		ApplyResizeBounds()
		local tab = active and C.tabs[active]
		if tab and tab.onShow then tab.onShow(tab.panel) end
		if PlaySound and SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN then PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN) end
	end)
	window:SetScript("OnHide", function()
		if PlaySound and SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_CLOSE then PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE) end
	end)
	window:Hide()
	BuildChrome()
	if UISpecialFrames then table.insert(UISpecialFrames, NAME) end -- close on Escape
	C.window = window
end

-- A tab's panel, built the first time it is asked for: the tab lays itself out in it.
local function Panel(key)
	local tab = C.tabs[key]
	if not tab then return nil end
	if not tab.panel then
		local panel = CreateFrame("Frame", nil, window)
		panel:SetAllPoints(window)
		panel:Hide()
		tab.panel = panel
		tab.build(panel)
		if panel.pageInset then panel.pageInset:SetShown(not minimized) end
	end
	return tab.panel
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

--- A tab, registered by the part that fills it. The window is built when first opened.
function C:Register(key, def)
	C.tabs[key] = def
	if window then
		LayOutTabs()
		PaintTabs()
	end
end

--- The tab a part registered, and its panel once built.
function C:Tab(key)
	return C.tabs[key]
end

function C:Window()
	if not window then BuildWindow() end
	return window
end

--- Show `key`'s tab in the window, building either the first time.
function C:Select(key)
	if not C.tabs[key] or not Enabled(C.tabs[key]) then return end
	self:Window()
	LayOutTabs()
	local previous = active
	active = key
	for k, tab in pairs(C.tabs) do
		if tab.panel then tab.panel:SetShown(k == key) end
	end
	local panel = Panel(key)
	panel:Show()
	PaintTabs()
	if previous ~= key and window:IsShown() and C.tabs[key].onShow then C.tabs[key].onShow(panel) end
	if panel.Refresh then panel:Refresh() end
	return panel
end

--- Open the window on `key`'s tab.
function C:Open(key)
	local panel = self:Select(key)
	if panel and not window:IsShown() then window:Show() end
	return panel
end

--- Whether the window is open, on `key`'s tab when one is given.
function C:IsOpen(key)
	return window ~= nil and window:IsShown() and (key == nil or active == key)
end

function C:Hide()
	if window then window:Hide() end
end

--- Unfold the window to its page: asked for an entry, a window closed folded would reopen as the
--- bare list.
function C:Expand()
	SetMinimized(false)
end

function C:Active()
	return active
end

--- Lay the tabs out again when a part is switched on or off, and close the window if the tab it
--- shows is one switched off: left open, it would go on playing and listing a part turned off.
function C:Relayout()
	if not window then return end
	LayOutTabs()
	PaintTabs()
	if active and C.tabs[active] and not Enabled(C.tabs[active]) then window:Hide() end
end

--- Whether there is anything to open: a tab whose part is on.
function C:Available()
	for _, tab in ipairs(Ordered()) do
		if Enabled(tab) then return true end
	end
	return false
end

--- Open the window, or close it when it is open: on the tab last looked at, else the first whose
--- part is on, through the tab's own open() where it has one (the places' lands on where the
--- player stands). Spoken's minimap menu and settings page open it this way.
function C:Toggle()
	if window and window:IsShown() then
		window:Hide()
		return
	end
	local ordered = Ordered()
	local tab = active and C.tabs[active]
	if not (tab and Enabled(tab)) then
		tab = nil
		for _, each in ipairs(ordered) do
			if Enabled(each) then
				tab = each
				break
			end
		end
	end
	if not tab then return end
	if tab.open then tab.open() else C:Open(tab.key) end
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

local PLUS = [[Interface\Buttons\UI-PlusButton-Up]]
local MINUS = [[Interface\Buttons\UI-MinusButton-Up]]
local PLUS_OFF = [[Interface\Buttons\UI-PlusButton-Disabled]]
local READY = [[Interface\RaidFrame\ReadyCheck-Ready]]
local ACTIVE = [[Interface\GossipFrame\ActiveQuestIcon]]
-- A card's badge where it has no painting of its own: a map; a chain's where the storyline's mark
-- is missing, a scroll.
local MAP_ICON = [[Interface\Icons\INV_Misc_Map_01]]
local STORY_ICON = [[Interface\Icons\INV_Scroll_03]]
local CHECK = "questlog-icon-checkmark-yellow"
-- The icons' bevelled border, trimmed inside the gold frame.
local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }

-- The campaign header's bar, in its atlas's own pixels: its crest sits half outside the bar at
-- the left end and looked cut off, so the left end is the right one turned round.
local BAR_HORDE, BAR_ALLIANCE = "Objective-Header-CampaignHorde", "Objective-Header-CampaignAlliance"
local BAR_TOP, BAR_BOTTOM = 3, 40
local BAR_MIDDLE, BAR_END = 64, 250

-- Classic's character select card: its corners are `cut` pixels of the atlas drawn `size` across.
-- The chosen one carries its glow round it, `out` beyond the card.
local CARD_ART = {
	normal = { atlas = "glues-characterselect-card-singles-c60", cut = 16, size = 11, out = 0 },
	hover = { atlas = "glues-characterselect-card-singles-hover-c60", cut = 16, size = 11, out = 0 },
	selected = { atlas = "glues-characterselect-card-selected-c60", cut = 30, size = 19, out = 7 },
}
local CARD_RIGHT = 56         -- what a card's share or tick keeps clear on its right
local CARD_INK = { 0.73, 0.70, 0.65 }
local SHARE_INK = { 0.80, 0.76, 0.70 }
local BANNER_INK = { 0.85, 0.81, 0.73 }
local LOCKED_INK = { 0.50, 0.48, 0.45 }

-- A gold wash fading from `from` on the left to `to` on the right, as alpha; even where the client
-- cannot fade one.
local function GoldWash(texture, from, to)
	texture:SetColorTexture(1, 1, 1, 1)
	if CreateColor and texture.SetGradient and pcall(texture.SetGradient, texture, "HORIZONTAL",
		CreateColor(1, 0.82, 0, from), CreateColor(1, 0.82, 0, to)) then
		return
	end
	if texture.SetGradientAlpha then
		texture:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, from, 1, 0.82, 0, to)
		return
	end
	texture:SetColorTexture(1, 0.82, 0, (from + to) / 2)
end

local function Tint(fontString, colour)
	fontString:SetTextColor(colour[1], colour[2], colour[3])
end

local function NewNine(row, layer, sublevel)
	local parts = {}
	for i = 1, 9 do parts[i] = row:CreateTexture(nil, layer, nil, sublevel) end
	return parts
end

-- `parts` drawn from the card art `art` round the box `left`, `top`, `right`, `bottom` of `row`
-- (offsets as SetPoint takes them): its corners as they are, its sides and middle stretched.
-- False, and nothing changed, where the client has not got the atlas.
local function SetNine(parts, art, row, left, top, right, bottom)
	local spot = AtlasSpot(art.atlas)
	if not spot then return false end
	local cut, size, out = art.cut, art.size, art.out
	local xs = { 0, cut, spot.width - cut, spot.width }
	local ys = { 0, cut, spot.height - cut, spot.height }
	for r = 1, 3 do
		for c = 1, 3 do
			local part = parts[(r - 1) * 3 + c]
			AtlasCut(part, spot, xs[c], xs[c + 1], ys[r], ys[r + 1])
			part:ClearAllPoints()
		end
	end
	local tl, tr, bl, br = parts[1], parts[3], parts[7], parts[9]
	for _, corner in ipairs({ tl, tr, bl, br }) do corner:SetSize(size, size) end
	tl:SetPoint("TOPLEFT", row, "TOPLEFT", left - out, top + out)
	tr:SetPoint("TOPRIGHT", row, "TOPRIGHT", right + out, top + out)
	bl:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left - out, bottom - out)
	br:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", right + out, bottom - out)
	parts[2]:SetPoint("TOPLEFT", tl, "TOPRIGHT")
	parts[2]:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
	parts[4]:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
	parts[4]:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
	parts[5]:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT")
	parts[5]:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
	parts[6]:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
	parts[6]:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
	parts[8]:SetPoint("TOPLEFT", bl, "TOPRIGHT")
	parts[8]:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
	return true
end

local function ShowAll(parts, shown)
	for _, part in ipairs(parts) do part:SetShown(shown and true or false) end
end

-- A row's light. A banner brightens and a card turns to its hover or chosen card; a plain row, or
-- one drawn without the game's art, takes a gold wash, stronger when chosen with a gold edge.
local function Light(row)
	local style = row.row and row.row.style
	local over, chosen = row.over and true or false, row.selected and true or false
	local flat = style == nil or (style == "card" and not row.cardArt) or (style == "banner" and not row.bannerArt)
	row.wash:SetShown(flat and over and not chosen)
	row.chosen:SetShown(flat and chosen)
	row.edge:SetShown(flat and chosen)
	if row.glow then
		ShowAll(row.glow, style == "banner" and row.bannerArt and (over or chosen))
		for _, part in ipairs(row.glow) do part:SetAlpha(chosen and 0.25 or 0.15) end
	end
	if row.lift then
		local art = style == "card" and row.cardArt and (chosen and CARD_ART.selected or over and CARD_ART.hover) or nil
		ShowAll(row.lift, art ~= nil and SetNine(row.lift, art, row, row.indent or 0, 0, 0, 0))
	end
end


local List = {}
List.__index = List

--- The list down a tab's left: a search box, the filter menu beside it, and an inset of rows under
--- them running to the window's foot. opts = { search = text, none = text, only = text, onlyGet(),
--- onlySet(on), checks = { { label, get(), set(on) }... }, arrange = { values, describe(value), get(),
--- set(value) }, build() -> items,
--- isSelected(item), onClick(item), onSearch(), addScrollBar(scroll, child, inset) }. The filter
--- menu is the spellbook's, the arrow beside its search box: the tab's only switch (Discovered Only,
--- Found Only) and any other checks as checkboxes, and where the tab can arrange its tree more than
--- one way, those ways under a divider. An item is { label, count, total, open, locked, missing } and one of:
--- - style = "banner": a group across the list, its plus or minus, the name, count/total.
--- - style = "card", small = bool: a badge (`icon` with its `iconCrop` in a gold frame, greyed with
---   `none`; the storyline's mark instead with `story`), the name, `sub` under it, the share or a
---   tick with `tick`, and a bar filled to `ratio`.
--- - leaf = true: one line, the name, a tick before it with `done` or the quest mark with `going`.
--- Cards and leaves give `nest`, how many open cards hold them.
function C.NewList(panel, opts)
	local list = setmetatable({ panel = panel, opts = opts, rows = {}, filter = "" }, List)
	local left, _, top = C.Margins()
	local filtered = opts.only ~= nil or opts.checks ~= nil or opts.arrange ~= nil

	local searchBox = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	searchBox:SetSize(LIST_WIDTH - 66 - (filtered and FILTER_ROOM or 0), 20)
	searchBox:SetPoint("TOPLEFT", panel, "TOPLEFT", left + 66, top - 8)
	if type(searchBox.Instructions) == "table" then searchBox.Instructions:SetText(opts.search or "") end
	searchBox:HookScript("OnTextChanged", function(self)
		list.filter = string.lower(strtrim and strtrim(self:GetText() or "") or (self:GetText() or ""))
		list.scroll:SetVerticalScroll(0)
		if opts.onSearch then opts.onSearch(list.filter) end
	end)
	list.searchBox = searchBox

	local ok, inset = pcall(CreateFrame, "Frame", nil, panel, "InsetFrameTemplate")
	if not ok or not inset then inset = CreateFrame("Frame", nil, panel) end
	inset:SetPoint("TOPLEFT", panel, "TOPLEFT", left, top - 38)
	-- Down to the window's foot, level with the page beside it.
	inset:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", left, (window and window.templated) and 6 or 12)
	inset:SetWidth(LIST_WIDTH)
	list.inset = inset

	local scroll = CreateFrame("ScrollFrame", nil, inset)
	scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
	if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = math.max(0, (list.child:GetHeight() or 0) - (self:GetHeight() or 0))
		local target = self:GetVerticalScroll() - (delta * SCROLL_STEP)
		self:SetVerticalScroll(math.max(0, math.min(range, target)))
	end)
	list.scroll = scroll

	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(LIST_WIDTH - 8, 1)
	scroll:SetScrollChild(child)
	list.child = child
	-- The game's minimal scroll bar down the list's right side, as each part draws its pages'.
	if opts.addScrollBar then list.bar = opts.addScrollBar(scroll, child, inset) end

	-- The filter menu.
	local function Changed()
		scroll:SetVerticalScroll(0)
		if panel.Refresh then panel:Refresh() end
	end
	local function OnlyOn() return opts.onlyGet ~= nil and opts.onlyGet() and true or false end
	local function SetOnly(on)
		if opts.onlySet then opts.onlySet(on) end
		Changed()
	end
	local function Arrange(value)
		opts.arrange.set(value)
		Changed()
	end
	list.setOnly, list.chooseArrange = SetOnly, Arrange
	-- Every checkbox the menu holds, the only switch first.
	local boxes = {}
	if opts.only then table.insert(boxes, { label = opts.only, get = OnlyOn, set = SetOnly }) end
	for _, check in ipairs(opts.checks or {}) do
		table.insert(boxes, { label = check.label, get = function() return check.get() and true or false end,
			set = function(on) check.set(on); Changed() end })
	end
	if filtered then
		local button
		if MenuUtil then
			local okMenu, made = pcall(CreateFrame, "DropdownButton", nil, panel, "UIPanelArrowDropdownButtonTemplate")
			if okMenu and made and made.SetupMenu then
				button = made
				button:SetupMenu(function(_, root)
					for _, box in ipairs(boxes) do
						root:CreateCheckbox(box.label, box.get, function() box.set(not box.get()) end)
					end
					if opts.arrange then
						if #boxes > 0 then root:CreateDivider() end
						for _, value in ipairs(opts.arrange.values) do
							root:CreateRadio(opts.arrange.describe(value), function() return opts.arrange.get() == value end,
								function() Arrange(value) end, value)
						end
					end
				end)
			end
		end
		if not button and UIDropDownMenu_Initialize and UIDropDownMenu_AddButton and ToggleDropDownMenu then
			-- Where the client has not got the game's menus: the older one, from an arrow of the same
			-- shape. Named: the template's parts are found by their parent's name on the older clients.
			C.filterMenus = (C.filterMenus or 0) + 1
			local menu = CreateFrame("Frame", NAME .. "Filter" .. C.filterMenus, panel, "UIDropDownMenuTemplate")
			UIDropDownMenu_Initialize(menu, function(_, level)
				for _, box in ipairs(boxes) do
					local info = UIDropDownMenu_CreateInfo()
					info.text, info.isNotRadio, info.keepShownOnClick = box.label, true, true
					info.checked = box.get()
					info.func = function() box.set(not box.get()) end
					UIDropDownMenu_AddButton(info, level)
				end
				if opts.arrange then
					if #boxes > 0 and UIDropDownMenu_AddSeparator then UIDropDownMenu_AddSeparator(level) end
					for _, value in ipairs(opts.arrange.values) do
						local info = UIDropDownMenu_CreateInfo()
						info.text = opts.arrange.describe(value)
						info.checked = opts.arrange.get() == value
						info.func = function() Arrange(value) end
						UIDropDownMenu_AddButton(info, level)
					end
				end
			end, "MENU")
			button = CreateFrame("Button", nil, panel)
			button:SetSize(20, 20)
			button:SetNormalTexture([[Interface\ChatFrame\UI-ChatIcon-ScrollDown-Up]])
			button:SetPushedTexture([[Interface\ChatFrame\UI-ChatIcon-ScrollDown-Down]])
			button:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
			button:SetScript("OnClick", function(self) ToggleDropDownMenu(1, nil, menu, self, 0, 0) end)
			list.filterMenu = menu
		end
		if button then
			-- As close to the box, and as level with it, as the spellbook's arrow is to its search.
			button:SetPoint("LEFT", searchBox, "RIGHT", 4, -3)
			list.filterButton = button
		end
	end

	list.noMatch = inset:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	list.noMatch:SetPoint("TOP", inset, "TOP", 0, -24)
	list.noMatch:SetText(opts.none or "")
	list.noMatch:Hide()
	return list
end

local function OnRowClick(self)
	local item = self.row
	if not item or item.locked then
		return
	end
	Sound("U_CHAT_SCROLL_BUTTON")
	local list = self.list
	if list.opts.onClick then list.opts.onClick(item) end
end

local FitBar

function List:AcquireRow(index)
	local row = self.rows[index]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, self.child)
	row.list = self

	row.wash = row:CreateTexture(nil, "BACKGROUND")
	GoldWash(row.wash, 0.11, 0.016)
	row.wash:Hide()
	row.chosen = row:CreateTexture(nil, "BACKGROUND")
	GoldWash(row.chosen, 0.2, 0.03)
	row.chosen:Hide()
	row.edge = row:CreateTexture(nil, "ARTWORK")
	row.edge:SetWidth(2)
	row.edge:SetColorTexture(1, 0.82, 0, 1)
	row.edge:Hide()

	-- A plain row's tick or quest mark, before its name.
	row.status = row:CreateTexture(nil, "ARTWORK")
	row.status:Hide()

	row.toggle = row:CreateTexture(nil, "ARTWORK")
	row.toggle:SetSize(16, 16)

	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.label:SetJustifyH("LEFT")
	if row.label.SetWordWrap then row.label:SetWordWrap(false) end

	row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.count:SetJustifyH("RIGHT")

	-- A padlock where the count goes, on what is not found yet: the group finder's own. None where
	-- the client has not got it; the grey name still says it.
	row.lock = row:CreateTexture(nil, "ARTWORK")
	row.lock:SetSize(12, 14)
	row.hasLock = Atlas(row.lock, "LFG-lock", false)
	row.lock:SetAlpha(0.7)
	row.lock:Hide()

	row:SetScript("OnClick", OnRowClick)
	row:SetScript("OnEnter", function(self) self.over = not (self.row and self.row.locked); Light(self) end)
	row:SetScript("OnLeave", function(self) self.over = false; Light(self) end)
	row:SetScript("OnSizeChanged", function(self, width) FitBar(self, width) end)

	self.rows[index] = row
	return row
end

-- The parts only a banner or a card has, made the first time a row is drawn as one: most rows in a
-- long list are plain ones and never need them.
local function BannerParts(row)
	if row.bannerParts then return end
	row.headLeft = row:CreateTexture(nil, "BACKGROUND")
	row.headMiddle = row:CreateTexture(nil, "BACKGROUND")
	row.headRight = row:CreateTexture(nil, "BACKGROUND")
	row.glow = {}
	for i = 1, 3 do
		local glow = row:CreateTexture(nil, "BORDER")
		if glow.SetBlendMode then glow:SetBlendMode("ADD") end
		glow:Hide()
		row.glow[i] = glow
	end
	-- Where the client has not got the bar: a dark band, a gold line along each edge.
	row.bannerFill = row:CreateTexture(nil, "BACKGROUND", nil, -1)
	row.bannerFill:SetColorTexture(0.17, 0.11, 0.06, 0.95)
	row.bannerFill:SetAllPoints(row)
	row.bannerTop = row:CreateTexture(nil, "BORDER")
	row.bannerTop:SetHeight(1)
	row.bannerTop:SetColorTexture(0.79, 0.63, 0.31, 0.8)
	row.bannerTop:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.bannerTop:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
	row.bannerBottom = row:CreateTexture(nil, "BORDER")
	row.bannerBottom:SetHeight(1)
	row.bannerBottom:SetColorTexture(0.79, 0.63, 0.31, 0.45)
	row.bannerBottom:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.bannerBottom:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	row.bannerParts = { row.headLeft, row.headMiddle, row.headRight, row.bannerFill, row.bannerTop, row.bannerBottom,
		row.glow[1], row.glow[2], row.glow[3] }
end

local function CardParts(row)
	if row.cardParts then return end
	row.face = NewNine(row, "BACKGROUND", 0)
	row.lift = NewNine(row, "BACKGROUND", 1)
	ShowAll(row.lift, false)
	-- Where the client has not got the card: a faint fill.
	row.cardFill = row:CreateTexture(nil, "BACKGROUND", nil, -1)
	row.cardFill:SetColorTexture(1, 1, 1, 0.04)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.iconFrame = row:CreateTexture(nil, "ARTWORK", nil, 2)
	row.story = row:CreateTexture(nil, "ARTWORK")
	row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.sub:SetJustifyH("LEFT")
	if row.sub.SetWordWrap then row.sub:SetWordWrap(false) end
	if row.sub.SetMaxLines then row.sub:SetMaxLines(1) end
	Tint(row.sub, CARD_INK)
	row.tick = row:CreateTexture(nil, "ARTWORK")
	row.track = row:CreateTexture(nil, "ARTWORK")
	row.track:SetColorTexture(0.04, 0.035, 0.024, 1)
	row.fill = row:CreateTexture(nil, "ARTWORK", nil, 1)
	row.barCaps = {}
	for i, atlas in ipairs({ "PetJournal-ExpBar-Left", "PetJournal-ExpBar-Mid", "PetJournal-ExpBar-Right" }) do
		local cap = row:CreateTexture(nil, "ARTWORK", nil, 2)
		row.barCaps[i] = cap
		row.hasBarFrame = Atlas(cap, atlas) and (i == 1 or row.hasBarFrame)
	end
	row.cardParts = { row.cardFill, row.icon, row.iconFrame, row.story, row.sub, row.tick, row.track, row.fill }
	for _, list in ipairs({ row.face, row.lift, row.barCaps }) do
		for _, part in ipairs(list) do table.insert(row.cardParts, part) end
	end
end

-- Only the parts of the style a row is drawn in: a row drawn as a card before and reused for a
-- banner would otherwise keep the card's badge and bar.
local function ShowStyle(row, style)
	if row.bannerParts and style ~= "banner" then ShowAll(row.bannerParts, false) end
	if row.cardParts and style ~= "card" then ShowAll(row.cardParts, false) end
	if style ~= nil then row.status:Hide() end
	row.bannerArt = style == "banner" and row.bannerArt
	row.cardArt = style == "card" and row.cardArt
end

-- The faint line down the left of each open card's contents, one for every card a row is inside.
-- Each row draws its share of the line, from the row above: `gap` up for the cards that held that
-- row too, just above itself for a card's first.
local function Rails(row, count, gap, held)
	row.rails = row.rails or {}
	for i = 1, math.max(count, #row.rails) do
		local rail = row.rails[i]
		if i <= count then
			if not rail then
				rail = row:CreateTexture(nil, "BORDER")
				rail:SetWidth(1)
				rail:SetColorTexture(0.84, 0.71, 0.31, 0.2)
				row.rails[i] = rail
			end
			local x = (i - 1) * NEST_STEP + RAIL_X
			rail:ClearAllPoints()
			rail:SetPoint("TOPLEFT", row, "TOPLEFT", x, i <= held and gap or NEST_PAD)
			rail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 0)
			rail:Show()
		elseif rail then
			rail:Hide()
		end
	end
end

-- The quest log's own expand and collapse, for anything with something inside to open. Where
-- nothing inside opens -- locked, empty (Thunder Bluff, with no areas of its own), or none found
-- with Discovered Only on -- greyed, as the name beside it is. `found`, where an item counts
-- something narrower than what it holds (the quests completed, not those in progress too).
local function Toggle(row, item, onlyFound)
	local count = item.found or item.count or 0
	local opens = ((item.total or count) > 0) and not item.locked and not (onlyFound and count == 0)
	local atlas = opens and item.open and "questlog-icon-shrink" or "questlog-icon-expand"
	if Atlas(row.toggle, atlas) then
		if row.toggle.SetDesaturated then row.toggle:SetDesaturated(not opens) end
		row.toggle:SetAlpha(opens and 0.9 or 0.45)
	else
		if row.toggle.SetDesaturated then row.toggle:SetDesaturated(false) end
		row.toggle:SetAlpha(1)
		row.toggle:SetTexture(opens and (item.open and MINUS or PLUS) or PLUS_OFF)
		row.toggle:SetTexCoord(0, 1, 0, 1)
	end
	row.toggle:Show()
end

local function Inner(nest)
	return nest > 0 and NEST_GAP or CARD_GAP
end

-- The room above the row for `items[i]`, and how many open cards hold both it and the row above.
local function GapAbove(items, i)
	local item, before = items[i], items[i - 1]
	if not before then return FIRST_GAP, 0 end
	if item.style == "banner" then return BANNER_GAP, 0 end
	if before.style == "banner" then return UNDER_BANNER, 0 end
	local was, now = before.nest or 0, item.nest or 0
	if now > was then return Inner(was) + NEST_PAD, was end
	return (was - now) * (NEST_PAD + NEST_AFTER) + Inner(now), now
end

local function RowHeight(item)
	if item.style == "banner" then return BANNER_ROW end
	if item.style == "card" then return item.small and SMALL_CARD_ROW or CARD_ROW end
	return LEAF_ROW
end

local function DrawBanner(row, item, onlyFound)
	BannerParts(row)
	local horde = UnitFactionGroup and UnitFactionGroup("player") == "Horde"
	local spot = AtlasSpot(horde and BAR_HORDE or BAR_ALLIANCE)
	row.bannerArt = spot ~= nil
	if spot then
		local width = spot.width
		local cap = math.floor((width - BAR_END) * BANNER_ROW / (BAR_BOTTOM - BAR_TOP) + 0.5)
		local pieces = { { row.headLeft, BAR_END, width, true }, { row.headMiddle, BAR_MIDDLE, BAR_END },
			{ row.headRight, BAR_END, width } }
		for i, piece in ipairs(pieces) do
			AtlasCut(piece[1], spot, piece[2], piece[3], BAR_TOP, BAR_BOTTOM, piece[4])
			AtlasCut(row.glow[i], spot, piece[2], piece[3], BAR_TOP, BAR_BOTTOM, piece[4])
			piece[1]:ClearAllPoints()
		end
		row.headLeft:SetSize(cap, BANNER_ROW)
		row.headLeft:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
		row.headRight:SetSize(cap, BANNER_ROW)
		row.headRight:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
		row.headMiddle:SetPoint("TOPLEFT", row.headLeft, "TOPRIGHT", 0, 0)
		row.headMiddle:SetPoint("BOTTOMRIGHT", row.headRight, "BOTTOMLEFT", 0, 0)
		for i, piece in ipairs(pieces) do row.glow[i]:SetAllPoints(piece[1]) end
	end
	ShowAll({ row.headLeft, row.headMiddle, row.headRight }, spot ~= nil)
	ShowAll({ row.bannerFill, row.bannerTop, row.bannerBottom }, spot == nil)

	row.toggle:ClearAllPoints()
	row.toggle:SetPoint("LEFT", row, "LEFT", 18, 0)
	Toggle(row, item, onlyFound)
	local locked = item.locked and row.hasLock
	row.lock:SetPoint("RIGHT", row, "RIGHT", -16, 0)
	row.count:SetPoint("RIGHT", row, "RIGHT", -16, 0)
	row.lock:SetShown(locked and true or false)
	row.count:SetShown(not locked)
	row.count:SetFontObject("GameFontHighlightSmall")
	Tint(row.count, BANNER_INK)
	row.count:SetText(item.total and item.total > 0 and string.format("%d/%d", item.count or 0, item.total) or "")
	row.label:SetFontObject("GameFontNormal")
	row.label:SetPoint("LEFT", row, "LEFT", 44, 0)
	row.label:SetPoint("RIGHT", locked and row.lock or row.count, "LEFT", -8, 0)
	if item.locked then Tint(row.label, LOCKED_INK) else row.label:SetTextColor(1, 0.82, 0) end
	row.label:SetShadowColor(0, 0, 0, 1)
	row.label:SetShadowOffset(0, -1)
	row.label:SetText(item.label)
end

-- The fill of a card's bar as far along it as its share, for the row's width: the rows are as
-- wide as the list, which settles after they are drawn.
FitBar = function(row, width)
	if not row.barLeft or not width or width <= 0 then return end
	local track = math.max(1, width - row.barLeft - 16 - 4)
	row.track:SetWidth(track)
	row.fill:SetWidth(math.max(0.01, track * (row.ratio or 0)))
end

local function DrawCard(row, item, indent, width)
	CardParts(row)
	local small = item.small
	row.toggle:Hide()
	row.cardArt = SetNine(row.face, CARD_ART.normal, row, indent, 0, 0, 0)
	ShowAll(row.face, row.cardArt)
	row.cardFill:ClearAllPoints()
	row.cardFill:SetPoint("TOPLEFT", row, "TOPLEFT", indent, 0)
	row.cardFill:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	row.cardFill:SetShown(not row.cardArt)

	-- The badge, level with the name and its line above the bar: the zone's painting or what the
	-- card holds in the collections window's gold frame, greyed with nothing found; a chain's the
	-- storyline's mark.
	local side = small and 30 or 38
	local middle = small and -18 or -21
	local centre = indent + 12 + side / 2
	local none = item.none or item.locked
	local story = item.story and Atlas(row.story, "questlog-storylineicon")
	local icon = item.icon or (item.story and STORY_ICON) or MAP_ICON
	row.story:SetShown(story and true or false)
	if story then
		row.story:SetSize(24, 24)
		row.story:ClearAllPoints()
		row.story:SetPoint("CENTER", row, "TOPLEFT", centre, middle)
		row.icon:Hide()
		row.iconFrame:Hide()
	else
		local inset = small and 3 or 4
		local crop = item.iconCrop or ICON_CROP
		row.icon:SetTexture(icon)
		row.icon:SetTexCoord(crop[1], crop[2], crop[3], crop[4])
		row.icon:SetSize(side - 2 * inset, side - 2 * inset)
		row.icon:ClearAllPoints()
		row.icon:SetPoint("CENTER", row, "TOPLEFT", centre, middle)
		if row.icon.SetDesaturated then row.icon:SetDesaturated(none and true or false) end
		local shade = none and 0.7 or 1
		row.icon:SetVertexColor(shade, shade, shade)
		row.icon:Show()
		local framed = Atlas(row.iconFrame, "collections-itemborder-collected")
		row.iconFrame:SetShown(framed)
		if framed then
			row.iconFrame:SetSize(side, side)
			row.iconFrame:ClearAllPoints()
			row.iconFrame:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
		end
	end

	local top = small and 6 or 8
	local left = indent + 12 + side + 12
	row.label:SetFontObject("GameFontNormal")
	row.label:SetPoint("TOPLEFT", row, "TOPLEFT", left, -top)
	row.label:SetPoint("TOPRIGHT", row, "TOPRIGHT", -CARD_RIGHT, -top)
	if item.locked then
		Tint(row.label, LOCKED_INK)
	elseif item.none or item.missing then
		row.label:SetTextColor(0.84, 0.71, 0.31)
	else
		row.label:SetTextColor(1, 0.82, 0)
	end
	row.label:SetText(item.label)
	row.sub:ClearAllPoints()
	row.sub:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
	row.sub:SetPoint("TOPRIGHT", row.label, "BOTTOMRIGHT", 0, -2)
	row.sub:SetText(item.sub or "")
	row.sub:Show()

	-- On the right the padlock, the gold tick once all are found, or the share found.
	local locked = item.locked and row.hasLock
	local ratio = item.ratio
	if ratio == nil and item.total and item.total > 0 then ratio = (item.count or 0) / item.total end
	ratio = math.max(0, math.min(1, ratio or 0))
	local ticked = not locked and item.tick and true or false
	row.lock:SetPoint("RIGHT", row, "TOPRIGHT", -16, middle)
	row.lock:SetShown(locked and true or false)
	row.tick:SetShown(ticked)
	if ticked then
		if Atlas(row.tick, CHECK) then
			row.tick:SetSize(18, 15)
		else
			row.tick:SetTexture(READY)
			row.tick:SetSize(14, 14)
		end
		row.tick:ClearAllPoints()
		row.tick:SetPoint("RIGHT", row, "TOPRIGHT", -16, middle)
	end
	row.count:SetFontObject("GameFontHighlightSmall")
	Tint(row.count, SHARE_INK)
	row.count:SetPoint("RIGHT", row, "TOPRIGHT", -16, middle)
	row.count:SetShown(not locked and not item.tick)
	row.count:SetText((item.total or 0) > 0 and string.format("%d%%", math.floor(100 * ratio + 1e-6)) or "")

	-- The bar along its foot, under the name: a dark track, the game's yellow as far as the share,
	-- cut rather than squeezed, in the Pet Journal's frame. None on a card with nothing to count.
	local barred = (item.total or 0) > 0
	local barLeft, barBottom, barHeight = indent + (small and 54 or 62), small and 9 or 11, small and 7 or 8
	row.barLeft, row.ratio = barLeft, ratio
	row.track:ClearAllPoints()
	row.track:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", barLeft + 2, barBottom + 1)
	row.track:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -16 - 2, barBottom + 1)
	row.track:SetHeight(barHeight - 2)
	row.track:SetShown(barred)
	row.fill:ClearAllPoints()
	row.fill:SetPoint("BOTTOMLEFT", row.track, "BOTTOMLEFT", 0, 0)
	row.fill:SetHeight(barHeight - 2)
	local spot = AtlasSpot("ui-frame-bar-fill-yellow")
	if spot then
		AtlasCut(row.fill, spot, 0, spot.width * ratio, 0, spot.height)
	else
		row.fill:SetColorTexture(1, 0.82, 0, 0.85)
	end
	row.fill:SetShown(barred and ratio > 0)
	FitBar(row, width)
	local capLeft, capMiddle, capRight = row.barCaps[1], row.barCaps[2], row.barCaps[3]
	for _, cap in ipairs(row.barCaps) do cap:ClearAllPoints() end
	capLeft:SetSize(6, barHeight)
	capLeft:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", barLeft, barBottom)
	capRight:SetSize(6, barHeight)
	capRight:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -16, barBottom)
	capMiddle:SetPoint("TOPLEFT", capLeft, "TOPRIGHT", 0, 0)
	capMiddle:SetPoint("BOTTOMRIGHT", capRight, "BOTTOMLEFT", 0, 0)
	ShowAll(row.barCaps, barred and row.hasBarFrame)
end

-- One thing on its own: its tick once completed or the quest mark while under way, its name, and
-- a padlock on what is not found yet.
local function DrawLeaf(row, item, indent)
	row.toggle:Hide()
	local status = item.done and "done" or item.going and "going" or nil
	if status == "done" then
		if Atlas(row.status, CHECK) then
			row.status:SetSize(13, 11)
		else
			row.status:SetTexture(READY)
			row.status:SetSize(14, 14)
		end
	elseif status == "going" then
		-- A file after an atlas keeps the atlas's tex coords.
		row.status:SetTexture(ACTIVE)
		row.status:SetTexCoord(0, 1, 0, 1)
		row.status:SetSize(15, 15)
	end
	row.status:ClearAllPoints()
	row.status:SetPoint("CENTER", row, "LEFT", indent + 16, 0)
	row.status:SetShown(status ~= nil)

	local locked = item.locked and row.hasLock
	row.lock:SetPoint("RIGHT", row, "RIGHT", -12, 0)
	row.lock:SetShown(locked and true or false)
	row.count:SetText("")
	row.count:Hide()
	row.label:SetFontObject("GameFontHighlight")
	row.label:SetPoint("LEFT", row, "LEFT", indent + 32, 0)
	if locked then
		row.label:SetPoint("RIGHT", row.lock, "LEFT", -6, 0)
	else
		row.label:SetPoint("RIGHT", row, "RIGHT", -12, 0)
	end
	-- Something with nothing to read yet, greyed a little: still there to choose. One not yet
	-- found, greyer: listed, but it does not open.
	if item.locked then
		Tint(row.label, LOCKED_INK)
	elseif item.missing then
		row.label:SetTextColor(0.66, 0.64, 0.60)
	else
		row.label:SetTextColor(0.94, 0.93, 0.89)
	end
	row.label:SetText(item.label)
end

--- Build the items again and draw them. Returns the items.
function List:Render()
	local items = self.opts.build()
	local onlyFound = self.opts.onlyGet and self.opts.onlyGet()
	local width = (self.child:GetWidth() or (LIST_WIDTH - 8)) - LIST_LEFT - LIST_RIGHT
	local y = LIST_TOP
	for i, item in ipairs(items) do
		local row = self:AcquireRow(i)
		row.row = item
		local gap, held = GapAbove(items, i)
		local height = RowHeight(item)
		y = y + gap
		row:SetHeight(height)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.child, "TOPLEFT", LIST_LEFT, -y)
		row:SetPoint("TOPRIGHT", self.child, "TOPRIGHT", -LIST_RIGHT, -y)
		y = y + height

		ShowStyle(row, item.style)
		local nest = item.style ~= "banner" and item.nest or 0
		Rails(row, nest, gap, held)
		local indent = nest * NEST_STEP
		row.indent = indent
		row.barLeft = nil
		row.label:ClearAllPoints()
		row.lock:ClearAllPoints()
		row.count:ClearAllPoints()
		if item.style == "banner" then
			indent = 0
			DrawBanner(row, item, onlyFound)
		elseif item.style == "card" then
			DrawCard(row, item, indent, width)
		else
			DrawLeaf(row, item, indent)
		end
		for _, light in ipairs({ row.wash, row.chosen }) do
			light:ClearAllPoints()
			light:SetPoint("TOPLEFT", row, "TOPLEFT", indent, 0)
			light:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
		end
		row.edge:ClearAllPoints()
		row.edge:SetPoint("TOPLEFT", row, "TOPLEFT", indent, 0)
		row.edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", indent, 0)
		-- Clicks on the card or row, not on the room beside its line.
		if row.SetHitRectInsets then row:SetHitRectInsets(indent, 0, 0, 0) end

		row.selected = self.opts.isSelected and self.opts.isSelected(item) or false
		Light(row)
		row:Show()
	end

	for i = #items + 1, #self.rows do
		self.rows[i]:Hide()
		self.rows[i].row = nil
	end

	self.child:SetHeight(math.max(y + LIST_FOOT, 1))
	self.noMatch:SetShown(#items == 0)
	return items
end

--- Bring the chosen row into view. Only when a tab opens on something: doing it on every
--- refresh would yank the list out from under a click.
function List:ScrollToSelection(items)
	local y = LIST_TOP
	for i, item in ipairs(items) do
		y = y + GapAbove(items, i)
		local height = RowHeight(item)
		if self.opts.isSelected and self.opts.isSelected(item) then
			local viewHeight = self.scroll:GetHeight() or 0
			-- GetVerticalScrollRange is stale until the next layout pass, right after
			-- child:SetHeight, so derive the range instead.
			local range = math.max(0, (self.child:GetHeight() or 0) - viewHeight)
			local target = y - (viewHeight / 2) + (height / 2)
			self.scroll:SetVerticalScroll(math.max(0, math.min(range, target)))
			return
		end
		y = y + height
	end
end

function List:ClearSearch()
	if self.searchBox:GetText() ~= "" then self.searchBox:SetText("") end
	self.filter = ""
end

--- Whether `text` matches what is being searched for: everything, with nothing typed.
function List:Matches(text)
	return self.filter == "" or (text and string.find(string.lower(text), self.filter, 1, true) ~= nil)
end

--------------------------------------------------------------------------------
-- The zones, as every tab lays them out
--------------------------------------------------------------------------------

C.WORLD = 947
C.CONTINENTS = { 1414, 1415 } -- Kalimdor, the Eastern Kingdoms
-- Where the client cannot say (C_Map's parents), Classic's own map ids: Kalimdor's zones and
-- cities, then the Eastern Kingdoms'.
local KNOWN_CONTINENT = {}
for _, id in ipairs({ 1411, 1412, 1413, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447,
	1448, 1449, 1450, 1451, 1452, 1454, 1456, 1457 }) do KNOWN_CONTINENT[id] = 1414 end
for _, id in ipairs({ 1416, 1417, 1418, 1419, 1420, 1421, 1422, 1423, 1424, 1425, 1426, 1427, 1428,
	1429, 1430, 1431, 1432, 1433, 1434, 1435, 1436, 1437, 1453, 1455, 1458 }) do KNOWN_CONTINENT[id] = 1415 end
-- The cities, each inside the zone around it, as the places list them.
C.CITY_IN = { [1453] = 1429, [1454] = 1411, [1455] = 1426, [1456] = 1412, [1457] = 1438, [1458] = 1420 }

function C.MapName(mapID)
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
	return info and info.name or tostring(mapID)
end

local continentCache = {}
--- The continent a zone is on: up the game's map tree until one is reached, else Classic's ids.
function C.ContinentOf(mapID)
	if continentCache[mapID] ~= nil then return continentCache[mapID] or nil end
	local found
	local current, steps = mapID, 0
	while current and steps < 8 and C_Map and C_Map.GetMapInfo do
		local info = C_Map.GetMapInfo(current)
		local parent = info and info.parentMapID
		if not parent or parent == 0 then break end
		if parent == 1414 or parent == 1415 then found = parent break end
		current, steps = parent, steps + 1
	end
	found = found or KNOWN_CONTINENT[mapID]
	continentCache[mapID] = found or false
	return found
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

-- The parchment: Spoken Zones' copies of the spellbook's page and divider where it is installed,
-- so every tab is on the same paper as the places; the game's own atlas where the client has it;
-- a plain colour where neither.
local ZONES_ART = "Interface\\AddOns\\Spoken_Zones\\Textures\\Art\\"
-- One ink for every word on the page: a lighter one for the line under the title and for a page
-- with nothing chosen read as greyed out, and was hard to make out on the parchment.
-- The spellbook's own, as the places' page has it: the game's colour is darker than the brown
-- this falls back to.
local INK = { 0.25, 0.16, 0.08 }
if _G.SPELLBOOK_FONT_COLOR and SPELLBOOK_FONT_COLOR.GetRGB then INK = { SPELLBOOK_FONT_COLOR:GetRGB() } end
local PAD, TOP, RIGHT = 24, 36, 36
-- The spellbook header's backplate behind the title, as the places' page lays it: laid out as if it
-- started this far left of the page, and cut there.
local BACKPLATE_CUT, BACKPLATE_FULL = 40, 460

local function ZonesLoaded()
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded("Spoken_Zones") end
	return IsAddOnLoaded and IsAddOnLoaded("Spoken_Zones") or false
end

local function Ink(fontString, color)
	fontString:SetTextColor(color[1], color[2], color[3])
	fontString:SetShadowColor(0, 0, 0, 0)
end

local Page = {}
Page.__index = Page

--- A page of parchment filling `parent`: a title, the line under it, the divider, the words in a
--- scrolling view (`addon`'s UI/TextView.lua), and Play on the title's right. `play` = { has(target),
--- playing(target), start(target), stop(target) }, what Play does for whatever Show was given.
function C.NewPage(parent, addon, play)
	local self = setmetatable({ playing = play }, Page)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	self.frame = frame

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	-- The spellbook's page, its top band cut off as the places' page has it.
	local file, coords
	if ZonesLoaded() then
		file = ZONES_ART .. "spellbook-Page-Right-C60"
		coords = { 0, 0.791016, 0.666016 * 0.07, 0.666016 }
		bg:SetTexture(file)
		bg:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	elseif not Atlas(bg, "spellbook-Page-Right-C60") then
		bg:SetColorTexture(0.86, 0.76, 0.56, 1)
	end
	self.bg, self.bgFile, self.bgCoords = bg, file, coords

	if ZonesLoaded() then
		local backplate = frame:CreateTexture(nil, "BORDER")
		backplate:SetTexture(ZONES_ART .. "spellbook-list-backplate")
		backplate:SetHeight(110)
		backplate:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 28 - TOP)
		backplate:SetAlpha(0.55)
		local right, bottom = 0.617188, 0.828125
		local function Fit()
			local shown = BACKPLATE_FULL - BACKPLATE_CUT
			local room = frame:GetWidth() or 0
			if room > 0 then shown = math.min(shown, room) end
			backplate:SetWidth(shown)
			backplate:SetTexCoord(right * BACKPLATE_CUT / BACKPLATE_FULL,
				right * (BACKPLATE_CUT + shown) / BACKPLATE_FULL, 0, bottom)
		end
		frame:HookScript("OnSizeChanged", Fit)
		Fit()
		self.backplate = backplate
	end

	local title = frame:CreateFontString(nil, "ARTWORK", _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge")
	local face = _G.QuestTitleFont and _G.QuestTitleFont.GetFont and _G.QuestTitleFont:GetFont()
	if face then title:SetFont(face, 26, "") end
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TOP)
	title:SetPoint("RIGHT", frame, "RIGHT", -RIGHT - 34, 0)
	title:SetJustifyH("LEFT")
	Ink(title, INK)
	self.title = title

	local sub = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
	sub:SetPoint("RIGHT", frame, "RIGHT", -RIGHT, 0)
	sub:SetJustifyH("LEFT")
	-- One line, cut short with an ellipsis: a book found in several places names them all.
	if sub.SetWordWrap then sub:SetWordWrap(false) end
	if sub.SetMaxLines then sub:SetMaxLines(1) end
	Ink(sub, INK)
	self.sub = sub

	local divider = frame:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(11)
	divider:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -6, -10)
	divider:SetPoint("RIGHT", frame, "RIGHT", -RIGHT, 0)
	if ZonesLoaded() then
		divider:SetTexture(ZONES_ART .. "spellbook-divider")
		divider:SetTexCoord(0, 0.641602, 0, 0.6875)
	elseif not Atlas(divider, "spellbook-divider") then
		divider:SetColorTexture(INK[1], INK[2], INK[3], 0.35)
		divider:SetHeight(1)
	end
	self.divider = divider

	local body = addon:CreateTextView(frame)
	body.frame:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 6, -2)
	body.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -RIGHT, PAD - 6)
	body:SetInk(INK[1], INK[2], INK[3])
	body:SetThumbColor(INK[1], INK[2], INK[3])
	if file then body:SetFadeSource(frame, file, coords) end
	self.body = body

	-- Play, the player's round button, on the heading's right as the places' page has it.
	if play and _G.Spoken and Spoken.CreateRoundButton then
		local button = Spoken:CreateRoundButton(frame, "play")
		button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -RIGHT, -TOP + 1)
		button:SetScript("OnClick", function()
			local target = self.target
			if target == nil then return end
			if play.playing(target) then play.stop(target) else play.start(target) end
			self:RefreshPlay()
		end)
		button:Hide()
		self.play = button
		if Spoken.RegisterCallback then
			Spoken:RegisterCallback("AUDIO_CHANGED", function() self:RefreshPlay() end)
		end
	end
	return self
end

function Page:RefreshPlay()
	local button, target = self.play, self.target
	if not button then return end
	if target == nil or not self.playing.has(target) then
		button:Hide()
		return
	end
	button:Show()
	if button.SetState then button:SetState(self.playing.playing(target) and "stop" or "play") end
end

--- entry = { title, subtitle, text, target = what Play plays, or nil for none }
function Page:Show(entry)
	self.title:SetText(entry.title or "")
	self.sub:SetText(entry.subtitle or "")
	self.body:SetColor(INK[1], INK[2], INK[3])
	self.body:SetText(entry.text or "")
	self.target = entry.target
	self:RefreshPlay()
end
