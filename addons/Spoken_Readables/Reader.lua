-- Which page the client is showing, if any.
--
-- ItemTextFrame is the whole of the book UI on all three targets, and it serves MAIL as
-- well: the same frame, the same events, the same getters. So the first question here is
-- never "which page is this" but "is this a book at all" -- a reader who opens a letter
-- from another player and hears it read aloud has been given somebody else's post by a
-- narrator, which is worse than hearing nothing.
--
-- Identification order, and each step earns its place:
--
--   1. title + page number + checksum   -- the normal path
--   2. checksum alone                   -- for a client whose object name differs from the
--                                          corpus's; only for checksums no other page shares
--   3. nothing                          -- silently, because the alternative is reading the
--                                          wrong page's words aloud

local ADDON_NAME, SpokenBooks = ...

-- A value the game hands over as a secret, in an instance or in combat, reads as nil.
local NotSecret = Spoken and Spoken.NotSecret or function(value) return value end

--- Whether the frame is showing mail rather than something the world wrote.
---
--- Two tests, because they catch different things. A creator is a player's name, and only
--- mail has one. And MailFrame being open is what catches a piece of mail with no creator
--- at all -- a returned letter, or one the server sent.
function SpokenBooks:IsMail()
	if ItemTextGetCreator and NotSecret(ItemTextGetCreator()) then
		return true
	end

	local mail = _G.MailFrame
	if mail and mail.IsShown and mail:IsShown() then
		return true
	end

	return false
end

--- A page id from one language's index, or nil.
local function Find(index, title, number, checksum)
	local byTitle = title and index.index and index.index[title]
	local byNumber = byTitle and byTitle[number]
	local found = byNumber and byNumber[checksum]
	if found then
		return found
	end

	-- The fallback. `loose` holds only checksums no other page shares, so a hit here is
	-- the page, not a guess between candidates.
	found = index.loose and index.loose[checksum]
	if found then
		return found
	end

	-- A pack's own pages, which the corpus module does not have.
	byTitle = title and index.extraIndex and index.extraIndex[title]
	byNumber = byTitle and byTitle[number]
	return (byNumber and byNumber[checksum]) or (index.extraLoose and index.extraLoose[checksum])
end

--- The page id the client is showing, or nil.
function SpokenBooks:PageOnScreen()
	local data = self:Data()
	if not data or self:IsMail() then
		return nil
	end

	local text = ItemTextGetText and NotSecret(ItemTextGetText())
	if type(text) ~= "string" or text == "" then
		return nil
	end

	local checksum = self:ChecksumOf(text)
	local title = ItemTextGetItem and NotSecret(ItemTextGetItem())
	local number = (ItemTextGetPage and NotSecret(ItemTextGetPage())) or 1

	-- The client's own locale first: the title and the words are what this client shows, and
	-- a German client's are German. A language's index ships in that language's pack, in the
	-- shape of the English one, because a client in that locale is the only one it can match
	-- and a player there who wants the language installs its pack. A pack in another language
	-- is not asked: its words are not the ones on this screen. Without one, every client is
	-- left on the English index, as before.
	local client = self:GetClientLanguage()
	for _, pack in ipairs(self:GetAudioPacks()) do
		if (type(pack.index) == "table" or type(pack.extraIndex) == "table")
			and self:PackLanguage(pack) == client then
			local found = Find(pack, title, number, checksum)
			if found then
				self:RememberPageText(found, client, text, title)
				return found
			end
		end
	end
	local found = Find(data, title, number, checksum)
	if found then self:RememberPageText(found, self.BASE_LANGUAGE, text, title) end
	return found
end

-- Older translated packs have an index but no caption text. Remember only pages
-- identified as books, in the language of the matching index, for those packs.
-- The title is the book's, so the pages queued after this one carry it too: the corpus has
-- only the English one.
function SpokenBooks:RememberPageText(pageId, language, text, title)
	self.pageText = self.pageText or {}
	self.pageText[language] = self.pageText[language] or {}
	self.pageText[language][pageId] = text:gsub("\r\n?", "\n"):gsub("%$[Bb]", "\n")
		:gsub("<[^>]+>", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	local book = self:PlaceOf(pageId)
	if book and type(title) == "string" and title ~= "" then
		self.bookTitle = self.bookTitle or {}
		self.bookTitle[language] = self.bookTitle[language] or {}
		self.bookTitle[language][book] = title
	end
end

--- Where a page sits: its book and its number. The corpus module's place, or a pack's for a
--- page only it has. Nil for a page nothing carries.
function SpokenBooks:PlaceOf(pageId)
	local data = self:Data()
	local place = data and data.pages[pageId]
	if not place then
		for _, pack in ipairs(self:GetAudioPacks()) do
			place = type(pack.places) == "table" and pack.places[pageId]
			if place then break end
		end
	end
	if not place then
		return nil, nil
	end
	return place.book, place.number
end

--- A book's title and its pages in reading order, by book id. A pack adds the pages Books.lua
--- lacks, so the list merges both, ordered by page number; a book only a pack has is its own.
function SpokenBooks:BookById(bookId)
	local data = self:Data()
	local book = data and data.books[bookId]
	local packs = self:GetAudioPacks()
	local hasBooks = false
	for _, pack in ipairs(packs) do
		if type(pack.books) == "table" then hasBooks = true break end
	end
	if not hasBooks then
		return book
	end

	local extra = {}
	local seen = {}
	for _, id in ipairs(book and book.pages or {}) do seen[id] = true end
	for _, pack in ipairs(packs) do
		local entry = type(pack.books) == "table" and pack.books[bookId]
		for _, id in ipairs(entry and entry.pages or {}) do
			if not seen[id] then
				seen[id] = true
				table.insert(extra, id)
			end
		end
	end
	if #extra == 0 then
		return book
	end

	local pages = {}
	for _, id in ipairs(book and book.pages or {}) do table.insert(pages, id) end
	for _, id in ipairs(extra) do table.insert(pages, id) end
	local order = {}
	for position, id in ipairs(pages) do
		local _, number = self:PlaceOf(id)
		order[id] = { number or math.huge, position }
	end
	table.sort(pages, function(a, b)
		if order[a][1] ~= order[b][1] then return order[a][1] < order[b][1] end
		return order[a][2] < order[b][2]
	end)
	return { title = book and book.title, pages = pages }
end

--- The book a page belongs to: its title and its pages in reading order.
function SpokenBooks:BookOf(pageId)
	local book = self:PlaceOf(pageId)
	return book and self:BookById(book) or nil
end
