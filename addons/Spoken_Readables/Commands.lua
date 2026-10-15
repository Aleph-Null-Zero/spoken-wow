-- /spokenreadables and /spr, matching /spoken and /sp on the player, /spokenquests and /spq,
-- and /spokenplaces and /spp. /spokenwritings and /spw, and /spokenbooks and /spb, still work, for
-- players' macros.

local ADDON_NAME, SpokenBooks = ...

local function Print(message, ...)
	local text = select("#", ...) > 0 and format(message, ...) or message
	DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffSpoken Readables|r: " .. text)
end

SpokenBooks.Print = function(self, message, ...) Print(message, ...) end

local function Toggle(key, label)
	SpokenBooksSettings[key] = not SpokenBooksSettings[key]
	Print("%s %s", label, SpokenBooksSettings[key] and "enabled" or "disabled")
end

--- Read the page in front of the reader, or say why nothing happened.
---
--- Deliberate, so it works with autoplay off: that is the whole point of the setting, and a
--- command that respected it would leave no way to start narration.
---
function SpokenBooks:ReadOrExplain()
	if self:ReadCurrent() > 0 then
		return
	end
	local pageId = self:PageOnScreen() or self.lastPage
	if not pageId then
		Print("nothing to read -- open a book first")
	elseif not self:HasAudio(pageId) then
		Print(self:DescribeMissingAudio())
	elseif not self.source then
		Print("nothing can read it -- Spoken Readables reads through Spoken, which is not installed")
	elseif not self:IsQueued(pageId) and not self:IsComing(pageId) then
		Print("Spoken did not take this page")
	elseif Spoken:IsPaused() then
		Print("this page is waiting -- Spoken is stopped; press Replay to carry on")
	elseif self:IsComing(pageId) then
		Print("already reading this book -- this page is still to come")
	else
		Print("already reading this page")
	end
end

local function Status()
	local data = SpokenBooks:Data()
	local books, pages = 0, 0
	for _ in pairs(data and data.books or {}) do books = books + 1 end
	for _ in pairs(data and data.pages or {}) do pages = pages + 1 end

	local packs = SpokenBooks:GetAudioPacks()
	local clips = 0
	for _, pack in ipairs(packs) do
		for _ in pairs(pack.pages) do clips = clips + 1 end
	end

	Print("%d readables, %d pages known; %d narrated by %d pack%s", books, pages, clips,
		#packs, #packs == 1 and "" or "s")
	local read = 0
	for _ in pairs(SpokenBooksCharacter and SpokenBooksCharacter.read or {}) do read = read + 1 end

	Print("autoplay %s, whole book %s, one line %s, read once %s",
		SpokenBooksSettings.autoplay and "on" or "off",
		SpokenBooksSettings.readWholeBook and "on" or "off",
		SpokenBooks:OneLine() and "on" or "off",
		SpokenBooksSettings.readOnce and "on" or "off")
	Print("gathering %s", SpokenBooks:GatherAvailable() and (Spoken.Gather:IsEnabled() and "on" or "off") or "unavailable")
	-- Said whether or not read-once is on, because the count is what makes `/spr forget`
	-- make sense, and because a reader turning the setting on wants to know what it will
	-- already consider read.
	Print("%d readable%s read on this character", read, read == 1 and "" or "s")
	if #packs == 0 then
		Print(SpokenBooks:DescribeMissingAudio())
	end
end

--- What /spr status prints, for the settings' Show Diagnostics.
function SpokenBooks:ShowStatus()
	Status()
end

--- A page every installed pack has, played the way a real one is, to check it can be heard.
function SpokenBooks:PlayTestLine()
	for _, pack in ipairs(self:GetAudioPacks()) do
		local pageId = next(pack.pages)
		if pageId then
			-- One page, queued as a real one plays: not PlayFrom, which marks the book read and
			-- with Read Whole Book on lines up the rest of it.
			local clip = self.source and self:ClipFor(pageId)
			if clip and self.source:Enqueue(clip) then
				Print("playing a test page")
			else
				Print("|cffffcc00the test page could not be queued|r")
			end
			return
		end
	end
	Print(self:DescribeMissingAudio())
end

_G.SLASH_SPOKENWRITINGS1 = "/spokenreadables"
_G.SLASH_SPOKENWRITINGS2 = "/spr"
_G.SLASH_SPOKENWRITINGS3 = "/spokenwritings"
_G.SLASH_SPOKENWRITINGS4 = "/spw"
_G.SLASH_SPOKENWRITINGS5 = "/spokenbooks"
_G.SLASH_SPOKENWRITINGS6 = "/spb"
SlashCmdList["SPOKENWRITINGS"] = function(msg)
	local cmd = string.lower(msg or "")
	cmd = string.match(cmd, "^%s*(%S*)") or ""

	if cmd == "autoplay" then
		Toggle("autoplay", "autoplay")
	elseif cmd == "whole" or cmd == "book" then
		Toggle("readWholeBook", "reading the whole book")
	elseif cmd == "oneline" then
		Toggle("bookAsOneLine", "a book as one line in the queue")
	elseif cmd == "once" then
		Toggle("readOnce", "reading each book only once")
	elseif cmd == "close" then
		Toggle("closeWhenRead", "closing the book once it has been read")
	elseif cmd == "forget" then
		local count = SpokenBooks:ForgetRead()
		Print("forgot %d readable%s; they will be read again", count, count == 1 and "" or "s")
	elseif cmd == "settings" or cmd == "options" then
		-- Guarded because UI/Options.lua is the one file here that a client can do without:
		-- everything it offers is also a command on this list.
		if SpokenBooks.OpenOptions then
			SpokenBooks:OpenOptions()
		else
			Print("no settings panel on this client -- type /spr for the commands")
		end
	elseif cmd == "compendium" or cmd == "readables" then
		if SpokenBooks.ShowReadables then
			SpokenBooks:ShowReadables()
		else
			Print("no Compendium on this client")
		end
	elseif cmd == "read" or cmd == "play" then
		SpokenBooks:ReadOrExplain()
	elseif cmd == "stop" then
		SpokenBooks:StopReading()
		Print("stopped")
	elseif cmd == "status" then
		Status()
	elseif cmd == "debug" then
		Toggle("debug", "explaining in chat why a page was or was not read")
	else
		Print("/spr read | stop | autoplay | whole | oneline | once | close | forget | compendium | settings | status | debug")
	end
end
