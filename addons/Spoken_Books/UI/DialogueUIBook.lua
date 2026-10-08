-- Spoken's controls on DialogueUI's book view (DUIBookFrame), as Spoken Quests puts them on its
-- quest window: Play (Stop while this book is read), Skip and Report, the player's round buttons
-- as large on screen as Place Lore draws them, in a row left of the book's close button, in
-- place of DialogueUI's own speaker. Left alone without DialogueUI or without the player.
--
-- DialogueUI loads every page of a book as it opens it and leaves the game on the last, so Play
-- reads the book from its first page, not from the page the game is on.

local ADDON_NAME, SpokenBooks = ...
local L = SpokenBooks.L

local ROUND, ROUND_GAP = 24, 4
-- DialogueUI's speaker, as it draws it, given back when the row goes.
local THEIRS_ALPHA = 0.6
-- How often the row looks again at what plays while the book is open.
local LOOK_EVERY = 0.1

local Book = {}
SpokenBooks.DialogueUIBook = Book

local function View()
	return _G.DUIBookFrame
end

--- The book open in the view: its key in the corpus and its first page, or nil for a page the
--- corpus does not carry.
local function OpenBook()
	local pageId = SpokenBooks.lastPage
	local key = pageId and SpokenBooks:PlaceOf(pageId)
	local data = key and SpokenBooks:Data()
	local entry = data and data.books[key]
	if not entry then
		return nil, nil
	end
	return key, entry.pages[1] or pageId
end

--- The page of this book the player is on, else its first.
local function ReadingPage(first)
	local head = Spoken.GetCurrent and Spoken:GetCurrent()
	if head and head.pageId and SpokenBooks:IsQueued(head.pageId) then
		return head.pageId, head.language
	end
	return first, nil
end

local function ReportsHidden()
	return Spoken.AreReportButtonsHidden and Spoken:AreReportButtonsHidden() or false
end

--- A tooltip on the view itself: the game's is a child of UIParent, which DialogueUI hides.
function Book:Tooltip()
	local view = View()
	local tooltip = self.tooltip
	if not tooltip then
		tooltip = CreateFrame("GameTooltip", "SpokenBooksDialogueUITooltip", view, "GameTooltipTemplate")
		tooltip:SetFrameStrata("TOOLTIP")
		self.tooltip = tooltip
	end
	tooltip:SetScale(UIParent:GetEffectiveScale() / view:GetEffectiveScale())
	return tooltip
end

local function HideTooltip(button)
	if button.tooltip then
		button.tooltip:Hide()
	end
end

--- What a click on Play does now, and Read Automatically, which a right-click switches.
function Book:ShowPlayTooltip(button)
	local tooltip = self:Tooltip()
	local key = OpenBook()
	local reading = key and SpokenBooks:IsNarrating(key)
	tooltip:SetOwner(button, "ANCHOR_RIGHT")
	tooltip:SetText(reading and L.STOP_TIP or L.PLAY_TIP)
	local on = SpokenBooksSettings and SpokenBooksSettings.autoplay
	tooltip:AddDoubleLine(L.OPT_AUTOPLAY, on and L.DUI_ON or L.DUI_OFF, 1, 1, 1,
		on and 0.1 or 1, on and 1 or 0.125, on and 0.1 or 0.125)
	tooltip:AddLine(L.DUI_PLAY_RIGHT_CLICK, 1, 0.82, 0, true)
	tooltip:Show()
	button.tooltip = tooltip
end

--- The row, built the first time the view opens: a child of the view, drawn over it.
function Book:Row()
	if self.row then
		return self.row
	end
	local view = View()
	local holder = CreateFrame("Frame", nil, view)
	holder:SetFrameStrata("FULLSCREEN")
	holder:SetSize(ROUND, ROUND)
	local play = Spoken:CreateRoundButton(holder, "play")
	play:SetFrameStrata("FULLSCREEN")
	play:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	play:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			if SpokenBooksSettings then
				SpokenBooksSettings.autoplay = not SpokenBooksSettings.autoplay
			end
		else
			local key, first = OpenBook()
			if key and SpokenBooks:IsNarrating(key) then
				SpokenBooks:StopReading()
			elseif first then
				SpokenBooks:SyncTo(first)
			end
		end
		Book:Draw()
		if play.tooltip and play.tooltip:IsShown() then
			Book:ShowPlayTooltip(play)
		end
	end)
	-- Skips by itself.
	local skip = Spoken:CreateRoundButton(holder, "skip")
	skip:SetFrameStrata("FULLSCREEN")
	local report = Spoken:CreateRoundButton(holder, "report")
	report:SetFrameStrata("FULLSCREEN")
	report:SetScript("OnClick", function()
		local _, first = OpenBook()
		local pageId, language = ReadingPage(first)
		local url = pageId and SpokenBooks:ReportURL(pageId, language)
		if url and Spoken.ShowContribution then
			Spoken:ShowContribution(url, nil, true)
		end
	end)
	local tips = {
		[play] = function() Book:ShowPlayTooltip(play) end,
		[skip] = function()
			local tooltip = Book:Tooltip()
			tooltip:SetOwner(skip, "ANCHOR_RIGHT")
			tooltip:SetText(SpokenEnv and SpokenEnv.L and SpokenEnv.L.BIND_SKIP or "Skip")
			tooltip:Show()
			skip.tooltip = tooltip
		end,
		[report] = function()
			local tooltip = Book:Tooltip()
			tooltip:SetOwner(report, "ANCHOR_RIGHT")
			tooltip:SetText(L.REPORT_PROBLEM)
			tooltip:AddLine(L.REPORT_LINE_TIP, 1, 0.8, 0.2, true)
			tooltip:Show()
			report.tooltip = tooltip
		end,
	}
	-- Brighter under the pointer as the ring's own hover has it, and the tooltip on the view's.
	for button, Show in pairs(tips) do
		button:SetScript("OnEnter", function(self)
			if self:IsEnabled() then self.glyph:SetAlpha(1) end
			Show()
		end)
		button:SetScript("OnLeave", function(self)
			if self:IsEnabled() then self.glyph:SetAlpha(0.85) end
			HideTooltip(self)
		end)
	end
	local since = 0
	holder:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since >= LOOK_EVERY then
			since = 0
			Book:Draw()
		end
	end)
	holder:Hide()
	self.row = { frame = holder, play = play, skip = skip, report = report }
	return self.row
end

--- DialogueUI's speaker, kept out of sight while the row stands in for it.
local function CoverTheirs(cover)
	local view = View()
	local theirs = view and view.TTSButton
	if type(theirs) ~= "table" or not theirs.SetAlpha then
		return
	end
	if cover then
		if (theirs:GetAlpha() or 0) > 0 then theirs:SetAlpha(0) end
		Book.covering = true
	elseif Book.covering then
		theirs:SetAlpha(THEIRS_ALPHA)
		Book.covering = false
	end
end

local function SetEnabled(button, on)
	if (button:IsEnabled() and true or false) ~= on then
		if on then button:Enable() else button:Disable() end
	end
end

--- Right to left from the book's close button, centred on it: Report, Skip, Play, whichever show,
--- as large on screen as Place Lore draws them, whatever DialogueUI's book size.
function Book:Place()
	local view, row = View(), self.row
	local scale = UIParent:GetEffectiveScale() / math.max(0.01, view:GetEffectiveScale() or 1)
	local list = {}
	for _, button in ipairs({ row.report, row.skip, row.play }) do
		if button:IsShown() then table.insert(list, button) end
	end
	local key = #list .. " " .. format("%.3f", scale)
	if key == self.placedKey then
		return
	end
	self.placedKey = key
	row.frame:SetSize(math.max(1, (#list * ROUND + (#list - 1) * ROUND_GAP) * scale), ROUND * scale)
	local right
	for _, button in ipairs(list) do
		button:SetScale(scale)
		button:SetSize(ROUND, ROUND)
		button:ClearAllPoints()
		if right then
			button:SetPoint("RIGHT", right, "LEFT", -ROUND_GAP, 0)
		else
			button:SetPoint("RIGHT", row.frame, "RIGHT", 0, 0)
		end
		right = button
	end
	row.frame:ClearAllPoints()
	local close = view.CloseButton
	if type(close) == "table" and close.GetObjectType then
		row.frame:SetPoint("RIGHT", close, "LEFT", -ROUND_GAP, 0)
	else
		row.frame:SetPoint("TOPRIGHT", view, "TOPRIGHT", -48, -19)
	end
end

--- Show the row while the view is open with the part on: Play greyed with no recording of this
--- book and Stop while it is read, Skip greyed with nothing speaking, Report while this book has
--- a recording (unless Hide Report Buttons is on).
function Book:Draw()
	local view = View()
	if not (view and view:IsShown() and SpokenBooks:IsPartOn()) then
		CoverTheirs(false)
		if self.row and self.row.frame:IsShown() then
			self.row.frame:Hide()
			HideTooltip(self.row.play)
			HideTooltip(self.row.skip)
			HideTooltip(self.row.report)
		end
		return
	end
	local row = self:Row()
	row.frame:Show()
	CoverTheirs(true)
	local key, first = OpenBook()
	local voiced = first ~= nil and SpokenBooks:HasAudio(first)
	SetEnabled(row.play, voiced)
	local state = key and SpokenBooks:IsNarrating(key) and "stop" or "play"
	if row.play.state ~= state then
		row.play:SetState(state)
	end
	SetEnabled(row.skip, Spoken.GetCurrent ~= nil and Spoken:GetCurrent() ~= nil)
	row.report:SetShown(voiced and not ReportsHidden())
	self:Place()
end

--- Hooked once DialogueUI's book view exists, with the player there to draw the buttons.
function SpokenBooks:SetupDialogueUIBook()
	local view = View()
	if Book.hooked or not (view and view.HookScript and _G.Spoken and Spoken.CreateRoundButton) then
		return
	end
	Book.hooked = true
	-- Told by a child of the view, as Spoken Quests is by one of the quest window's: a hook on the
	-- view's own scripts goes when DialogueUI sets them anew.
	local watch = CreateFrame("Frame", nil, view)
	watch:SetScript("OnShow", function()
		if Spoken.SetContributeHost then Spoken:SetContributeHost(view) end
		Book:Draw()
	end)
	watch:SetScript("OnHide", function()
		if Spoken.SetContributeHost then Spoken:SetContributeHost(nil) end
		Book:Draw()
	end)
	Book.watch = watch
	-- Hide Report Buttons, in Spoken's settings, fires no game event.
	if Spoken.RegisterCallback then
		Spoken:RegisterCallback("REPORT_SETTINGS_CHANGED", function() Book:Draw() end)
	end
end
