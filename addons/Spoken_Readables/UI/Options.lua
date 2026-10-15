-- SpokenBooks -- options panel in the interface settings.
--
-- Nested under Spoken's settings entry, and laid out by Spoken's UI/Layout.lua, so this page and
-- the others read alike.
-- UI/Options.lua on the zones side is the same file one size larger; the reasoning for both
-- choices is written down there.
--
-- Every switch here also has a slash command, and always will: the settings panel is the
-- Settings API's, and a client that does not offer one must still leave the addon
-- configurable. /spr is what the Print below points at when that happens.

local ADDON_NAME, SpokenBooks = ...

local L = SpokenBooks.L

-- The game's settings list sets its rows 25 in from the canvas's left.
local INDENT = 25
-- The voice pack this addon is made for, and where to get it.
local AUDIO_ADDON = "SpokenBooksAudio"
local AUDIO_URL = "https://www.curseforge.com/wow/addons/spoken-books-audio"

local panel

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

function SpokenBooks:SetupOptions()
	if panel then
		return
	end

	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		self:Print("|cffffcc00Settings API missing; options panel unavailable (use /spr)|r")
		return
	end

	-- Parentless, with `.name` set, is the shape the Settings API expects here.
	panel = CreateFrame("Frame")
	panel.name = "Spoken Readables"

	-- Laid out in the scroller's content frame rather than on the panel itself: the settings
	-- canvas is a fixed size and neither scrolls nor clips, so rows that overflow it draw
	-- over the game world. Three rows fit today; the next one added should not have to
	-- discover this.
	local scroller = SpokenLayout.Scroll(panel)
	local content = scroller.child
	panel.content = content

	local layout = SpokenLayout.New(content, INDENT, -16)
	layout:Header(L.OPT_PAGE_TITLE, L.OPT_NOTE, nil, [[Interface\Icons\INV_Misc_Book_09]])
	local refresh = function() layout:Refresh() end

	-- The part's own switch first, as on Spoken's page: off, everything under it is greyed
	-- out and says why, rather than looking live and doing nothing. Its own entry, nested under
	-- Spoken in the game's settings list and headed as the game's pages are: the page is there
	-- whether the part is on or not. The part's card on Spoken's page turns it on and off too.
	local function PartOn() return SpokenBooks:IsPartOn() end
	layout:HideHeader()
	layout:Intro([[Interface\Icons\INV_Misc_Book_09]], L.OPT_PAGE_TITLE)
	local switch = layout:Checkbox(L.OPT_PART_SWITCH, L.OPT_PART_SWITCH_TIP, PartOn,
		function(value) Spoken:SetPartOn("books", value) end, refresh)

	local function Get(key)
		return function() return SpokenBooksSettings and SpokenBooksSettings[key] end
	end
	local function Set(key)
		return function(value) if SpokenBooksSettings then SpokenBooksSettings[key] = value end end
	end

	layout:Section(L.OPT_SECTION_READING)
	local autoplay = Get("autoplay")
	layout:Checkbox(L.OPT_AUTOPLAY,
		L.OPT_AUTOPLAY_TIP,
		autoplay, Set("autoplay"), refresh)
	-- Indented under it and greyed with it off: only automatic reading skips a book already
	-- heard (Events.lua); Play reads it again whatever this says.
	layout:Indent()
	local once = layout:Checkbox(L.OPT_READ_ONCE,
		L.OPT_READ_ONCE_TIP,
		Get("readOnce"), Set("readOnce"))
	layout:Outdent()
	layout:Requires(once, function() return SpokenBooksSettings ~= nil and autoplay() ~= false end, L.REASON_AUTOPLAY)
	layout:Checkbox(L.OPT_WHOLE_BOOK,
		L.OPT_WHOLE_BOOK_TIP,
		Get("readWholeBook"), Set("readWholeBook"))
	layout:Checkbox(L.OPT_ONE_LINE,
		L.OPT_ONE_LINE_TIP,
		Get("bookAsOneLine"), Set("bookAsOneLine"))
	layout:Checkbox(L.OPT_STOP_ON_CLOSE,
		L.OPT_STOP_ON_CLOSE_TIP,
		Get("stopOnClose"), Set("stopOnClose"))
	layout:Checkbox(L.OPT_CLOSE_WHEN_READ,
		L.OPT_CLOSE_WHEN_READ_TIP,
		Get("closeWhenRead"), Set("closeWhenRead"))

	-- What this character has heard, before the voice packs, as on the other modules' pages.
	layout:Section(L.OPT_SECTION_READ)
	layout:Button(L.OPT_FORGET, 200, function()
		local count = SpokenBooks:ForgetRead()
		SpokenBooks:Print(L.OPT_FORGET_DONE_FMT:format(count))
	end, L.OPT_FORGET_TIP)

	-- Every voice pack, a row each, as on the quests page: its version where it is installed,
	-- and where it is not, a button with the address to get it.
	layout:Section(L.OPT_SECTION_PACKS)
	local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	-- The packs to get are the voice language's; any pack installed is listed too. Not the
	-- fallback's to get: it buried the one that mattered. But a voice language with no pack of its
	-- own (itIT) is heard in the fallback's, so that is the one to get there.
	local function Installed(addon)
		for _, pack in ipairs(SpokenBooks:GetAudioPacks()) do
			if pack.addon == addon then return true end
		end
		return false
	end
	local function Wanted(code, addon)
		local voice = SpokenBooks:GetVoiceLanguage()
		if code == voice or Installed(addon) then return true end
		local own = voice == "enUS" or (Spoken and Spoken.VoicePack and Spoken:VoicePack("books", voice))
		return not own and code == SpokenBooks:GetFallbackLanguage()
	end
	-- Each language's row shown while it is wanted.
	local listed = {}
	local function PackRow(addon, name, url)
		listed[addon] = true
		return layout:Download(L.OPT_PACK_NAME_FMT:format(name), function()
			for _, pack in ipairs(SpokenBooks:GetAudioPacks()) do
				if pack.addon == addon then
					return "ok", (GetMeta and GetMeta(addon, "Version")) or L.OPT_PACK_INSTALLED
				end
			end
		end, L.OPT_DOWNLOAD, function()
			SpokenBooks:ShowCopyLink(url or AUDIO_URL, L.OPT_DOWNLOAD_ADDRESS)
		end, L.OPT_DOWNLOAD_TIP)
	end
	for _, locale in ipairs(SpokenBooks.LOCALES or {}) do
		local folder, url = Spoken and Spoken.VoicePack and Spoken:VoicePack("books", locale.code)
		if folder then
			local code = locale.code
			layout:ShowWhen(PackRow(folder, SpokenBooks:GetLanguageName(code), url), function() return Wanted(code, folder) end)
		end
	end
	layout:ShowWhen(PackRow(AUDIO_ADDON, L.OPT_PACK_OFFICIAL), function() return Wanted("enUS", AUDIO_ADDON) end)
	-- A pack the list does not know, after the ones it does.
	for _, pack in ipairs(SpokenBooks:GetAudioPacks()) do
		if not listed[pack.addon] then PackRow(pack.addon, pack.title or pack.addon) end
	end

	-- The same three as every module's page: a page to check the sound with, what is
	-- installed, and where to report the rest.
	layout:Section(L.OPT_SECTION_TROUBLE)
	layout:Columns(2)
	layout:Button(L.OPT_TEST_LINE, 200, function() SpokenBooks:PlayTestLine() end, L.OPT_TEST_LINE_TIP)
	layout:Button(L.OPT_DIAGNOSTICS, 200, function() SpokenBooks:ShowStatus() end, L.OPT_DIAGNOSTICS_TIP)
	layout:Columns(nil)
	layout:Button(L.OPT_REPORT_PROBLEM, 200, function()
		SpokenBooks:ShowCopyLink(SpokenBooks:SiteURL(), L.OPT_REPORT_ADDRESS)
	end, L.OPT_REPORT_PROBLEM_TIP)

	-- Every page ends the same way, as Spoken's does: one section, last, to start over.
	layout:StartOver(L.OPT_SECTION_START_OVER, L.OPT_RESET_PAGE, function()
		SpokenLayout.Confirm(L.OPT_RESET_PAGE_CONFIRM, L.OPT_RESET, L.OPT_CANCEL, function()
			SpokenBooks:ResetOptions()
			layout:Refresh()
			-- Found Only, Voiced Only and By Zone are among them: a Readables tab open beside this page
			-- is drawn again for them.
			if SpokenBooks.RefreshReadables then SpokenBooks:RefreshReadables() end
		end)
	end, L.OPT_RESET_PAGE_TIP)
	-- Switched off, the module is off: everything on its page greys out but its own switch.
	layout:RequiresAll(PartOn, L.REASON_PART_OFF, switch)
	layout:Refresh()
	content:SetScript("OnShow", refresh)
	-- Switched on or off from Spoken's page while this one was hidden: drawn again for it.
	Spoken:RegisterCallback("PART_SWITCHED", function(part) if part == "books" then refresh() end end)

	-- Derived rather than written as a number: a hardcoded height is a number nobody updates
	-- when a row is added, and what that produces is a section you cannot scroll to.
	scroller:SetContentHeight(layout:Height() + 40)

	-- Under Spoken's own entry, named as DialogueUI names the same things.
	SpokenBooks.optionsPage = Spoken:AddSettingsPage(panel, L.OPT_PAGE_TITLE, 4, layout, scroller)
	SpokenBooks.optionsPanel = panel
end

--- Open the panel, or say why there is none. Reached by `/spr settings`, the player's
--- minimap menu and the settings link on the player's own panel.
function SpokenBooks:OpenOptions()
	-- Nested under Spoken's entry: Spoken opens this page.
	if self.optionsPage and self.optionsPage.Open and self.optionsPage.Open() then return end
	local category = self.optionsPage and self.optionsPage.category
	if not (SpokenLayout and SpokenLayout.OpenCategory(category)) then
		self:Print("open Game Menu -> Options -> AddOns -> Spoken -> Readables")
	end
end
