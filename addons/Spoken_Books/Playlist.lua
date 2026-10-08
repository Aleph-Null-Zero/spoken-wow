-- A book read straight through, and kept in step with the page on screen.
--
-- Opening a book reads it from the page being read to its last, so a twenty-page journal
-- narrates on while the reader turns pages. Turning a page does not restart anything: if
-- the page turned to is speaking or still to come, nothing happens. If it is not -- the
-- reader jumped, or opened a different book -- what this source holds is dropped and the
-- reading starts again from there. One readable at a time: opening a gravestone while a
-- book is read replaces the book.
--
-- The book is ONE line in the queue: its first page is queued, and each page, as it
-- finishes, puts the next at the head (source:Continue), so the queue and its waiting count
-- show the book once, and Skip skips the rest of it. Reading the WHOLE book rather than the
-- page on screen is the difference between reading along and pressing play twenty times.

local ADDON_NAME, SpokenBooks = ...

--- The pages of a book from `pageId` onwards, in reading order.
function SpokenBooks:PagesFrom(pageId)
	local book = self:BookOf(pageId)
	if not book then
		return {}
	end

	local rest, found = {}, false
	for _, id in ipairs(book.pages) do
		if id == pageId then
			found = true
		end
		if found then
			table.insert(rest, id)
		end
	end
	return rest
end

--- Whether a page is already queued or speaking.
function SpokenBooks:IsQueued(pageId)
	if not self.source or not _G.Spoken or not Spoken.GetQueue then
		return false
	end

	local key = "b:" .. pageId
	-- GetQueue is a shallow copy of the whole queue, both sources included; the key
	-- namespace is this addon's, so a match can only be one of ours.
	for _, clip in ipairs(Spoken:GetQueue()) do
		if clip.key == key then
			return true
		end
	end
	return false
end

--- The pages still to come of the book being read: { book, pages }, each page put at the head
--- of the queue as the one before it finishes (PageEnded). Nil once the book is done, skipped
--- or stopped.
SpokenBooks.following = nil

--- Whether `pageId` is still to come of the book being read.
function SpokenBooks:IsComing(pageId)
	for _, id in ipairs(self.following and self.following.pages or {}) do
		if id == pageId then
			return true
		end
	end
	return false
end

local Follow

--- A page left the queue: finished, the next page with a clip goes to the head; skipped or
--- stopped, the rest of the book goes with it.
local function PageEnded(clip, finished)
	local following = SpokenBooks.following
	if not (following and SpokenBooks:PlaceOf(clip.pageId) == following.book) then
		return
	end
	if not finished then
		SpokenBooks.following = nil
		return
	end
	while table.getn(following.pages) > 0 do
		local id = table.remove(following.pages, 1)
		local nextClip = SpokenBooks:ClipFor(id)
		if nextClip then
			Follow(nextClip)
			if SpokenBooks.source and SpokenBooks.source:Continue(nextClip) then
				return
			end
		end
	end
	SpokenBooks.following = nil
end

--- `clip` puts the next page at the head as it ends (PageEnded), before whatever else its own
--- stopCallback does: the next page is coming by the time that asks.
function Follow(clip)
	local after = clip.stopCallback
	clip.stopCallback = function(ended, finished)
		PageEnded(ended, finished)
		if after then after(ended, finished) end
	end
end

--- Whether any page of `book` is still queued or speaking.
---
--- Asked by the read-once rule, which must not refuse the book it is in the middle of
--- reading: a reader who jumps past the queued pages is still inside the book that was
--- already counted as read, and a refusal there would strand the narration on the page they
--- turned away from. Walks the book rather than trusting a remembered "currently reading",
--- which nothing clears when a queue drains on its own.
function SpokenBooks:IsNarrating(book)
	local data = self:Data()
	local entry = book and data and data.books[book]
	if not entry then
		return false
	end

	for _, id in ipairs(entry.pages) do
		if self:IsQueued(id) then
			return true
		end
	end
	return false
end

--- Read this page and the rest of its book: this page queued, the rest to follow it (PageEnded).
--- Returns how many pages will be read.
---
--- A page the installed pack has no clip for is skipped rather than queued silent: the
--- player would otherwise hold a clip with no sound for its whole length, which reads as
--- the addon having stopped working.
---
--- `browsing`: played from the Compendium, which is not meeting the book in the world, so Read
--- Only Once still lets it read itself the first time it is opened there.
function SpokenBooks:PlayFrom(pageId, browsing)
	local source = self.source
	if not source then
		return 0
	end

	local queued, rest = 0, {}
	self.following = nil
	for _, id in ipairs(self:PagesFrom(pageId)) do
		if SpokenBooksSettings and SpokenBooksSettings.readWholeBook == false and id ~= pageId then
			break
		end
		if queued == 0 then
			local clip = self:ClipFor(id)
			if clip then
				Follow(clip)
				if source:Enqueue(clip) then
					queued = 1
				end
			end
		elseif self:HasAudio(id) then
			table.insert(rest, id)
			queued = queued + 1
		end
	end
	if table.getn(rest) > 0 then
		self.following = { book = self:PlaceOf(pageId), pages = rest }
	end

	-- Read, as far as this character is concerned, the moment a page of it is admitted --
	-- whether autoplay queued it or the reader pressed play. Recorded even with readOnce
	-- off, so turning the setting on remembers what was heard before rather than starting
	-- from a blank slate.
	if queued > 0 and not browsing then
		self:MarkBookRead(self:PlaceOf(pageId))
	end

	return queued
end

--- The page on screen changed. Keep the queue pointed at it. `browsing` as PlayFrom's.
function SpokenBooks:SyncTo(pageId, browsing)
	if not pageId then
		return 0
	end

	-- Already coming: the reader turned to a page this book is reading or has still to read,
	-- which is the normal case and the one that must not restart narration.
	if self:IsQueued(pageId) or self:IsComing(pageId) then
		return 0
	end

	-- Somewhere else entirely. Drop what this source holds -- never the whole queue, which
	-- may be carrying a quest line -- and rebuild from here.
	if self.source then
		self.source:StopAll()
	end
	return self:PlayFrom(pageId, browsing)
end

--- Stop this source, and only this source: the queue may be carrying a quest line that has
--- nothing to do with a book.
---
--- Reached by `/spb stop` and by SyncTo rebuilding, not by closing the frame -- a book
--- carries on being read after it is shut.
function SpokenBooks:StopReading()
	if self.source then
		self.source:StopAll()
	end
end
