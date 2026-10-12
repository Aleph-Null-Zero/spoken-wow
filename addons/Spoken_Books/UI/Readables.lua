-- SpokenBooks -- the readables in Azeroth's Compendium (UI/Compendium.lua): every book, letter,
-- note and plaque Spoken Books reads, found or not, to read and listen to anywhere.
--
-- The list is laid out as the places' (Spoken Zones' tab): a banner for each continent, a card for
-- each of its zones (how many of its writings are found, with a bar), a city a small card inside
-- the zone around it; in an opened zone a small card for each kind of writing -- books, journals,
-- letters, notes, scrolls, tablets, plaques, gravestones, exhibits, pictures -- and the writings
-- under it. After the continents, a banner each for the seasonal events' readables, for those had
-- in too many zones to list under each and for those whose origin is not known, with a card for
-- each kind inside. With By Zone off, the list is a card for each kind alone, every readable under
-- its own. Where each is comes from
-- Data/Places.lua; what this character has found, from SpokenBooksCharacter (Core.lua). A readable
-- not found yet is listed greyed, with a padlock, and does not open, unless Unlock Unfound
-- Readables is on. On the right its pages, on parchment, with where it comes from and Play.

local ADDON_NAME, SpokenBooks = ...

local L = SpokenBooks.L

local C = SpokenCompendium
local WORLD, CONTINENTS, CITY_IN = C.WORLD, C.CONTINENTS, C.CITY_IN
local MapName, ContinentOf = C.MapName, C.ContinentOf

local list, page
local selection          -- { book = id } | { mapID = id } | { mapID = id, group = type }
                         -- | { group = "events"|"wide"|"unknown" }
                         -- | { group = "events"|"wide"|"unknown", type = type } | { type = type }
                         -- | { zones = "lands"|"battlegrounds" } | nil
local expandedZone
local continentOpen = { [1414] = true, [1415] = true }
local zonesOpen = {}          -- [key] = true: Other Lands' or Battlegrounds' banner, opened
local ZONES_LABEL = { lands = "GROUP_LANDS", battlegrounds = "GROUP_BATTLEGROUNDS" }
-- The battlegrounds, under a banner of their own after the continents, whatever map the client
-- hangs them under: one client puts Alterac Valley in Hillsbrad Foothills, another under Azeroth,
-- where no continent's list reached it.
local BATTLEGROUNDS = { 1459, 1460, 1461, 2524 } -- Alterac Valley, Warsong Gulch, Arathi Basin, Darkspear Islands
local IS_BATTLEGROUND = {}
for _, mapID in ipairs(BATTLEGROUNDS) do IS_BATTLEGROUND[mapID] = true end
local groupOpen = { events = false, wide = false, unknown = false }
local GROUP_LABEL = { events = "GROUP_EVENTS", wide = "GROUP_WIDE", unknown = "GROUP_UNKNOWN" }
local typeOpen = {}
local zoneTypeShut = {}       -- ["mapID:type"] = true: a zone's Books, Notes and the rest, closed
local groupTypeShut = {}      -- ["wide:type"] = true: the same in a group's banner
local TYPES, TYPE_NAMES = SpokenBooks.TYPES, SpokenBooks.TYPE_NAMES
local function TypeLabel(type) return L[(TYPE_NAMES[type] or TYPE_NAMES.other).all] end
local filter = ""

--------------------------------------------------------------------------------
-- What there is
--------------------------------------------------------------------------------

local function Books()
	local data = SpokenBooks:Data()
	return data and data.books or {}
end

local function Title(id)
	local book = Books()[id]
	return book and book.title or tostring(id)
end

-- Every readable by where it is: index.zones[mapID] = { [type] = { ids } }, the two groups, the
-- types, and `all`, what every count is out of. A readable Data/Places.lua does not carry is left
-- out everywhere: places.mjs drops the Deprecated and TEST items no one can find, and counting
-- them would keep every total out of reach. Built once: the data is fixed for the session.
local index
local function Index()
	if index then return index end
	index = { zones = {}, events = {}, wide = {}, unknown = {}, types = {}, all = {}, typeOf = {} }
	local places = _G.SpokenBooksPlaces and SpokenBooksPlaces.books or {}
	local function Add(mapID, type, id)
		local zone = index.zones[mapID] or {}
		index.zones[mapID] = zone
		zone[type] = zone[type] or {}
		table.insert(zone[type], id)
	end
	for id in pairs(Books()) do
		local place = places[id]
		if place or not _G.SpokenBooksPlaces then
			index.all[id] = true
			local type = place and TYPE_NAMES[place.type] and place.type or "other"
			index.typeOf[id] = type
			index.types[type] = index.types[type] or {}
			table.insert(index.types[type], id)
			-- A seasonal event's readable under the event, not where its NPCs stand.
			if place and place.event then
				table.insert(index.events, id)
			elseif place and place.wide then
				table.insert(index.wide, id)
			elseif place and place.zones and #place.zones > 0 then
				for _, mapID in ipairs(place.zones) do Add(mapID, type, id) end
			else
				table.insert(index.unknown, id)
			end
		end
	end
	local function ByTitle(a, b)
		local ta, tb = Title(a), Title(b)
		if ta == tb then return a < b end
		return ta < tb
	end
	for _, zone in pairs(index.zones) do
		for _, ids in pairs(zone) do table.sort(ids, ByTitle) end
	end
	for _, ids in pairs(index.types) do table.sort(ids, ByTitle) end
	table.sort(index.events, ByTitle)
	table.sort(index.wide, ByTitle)
	table.sort(index.unknown, ByTitle)
	return index
end

local function Found(id)
	return SpokenBooks:IsBookFound(id)
end

local function Unlocked()
	return SpokenBooksSettings and SpokenBooksSettings.unlockUnfound == true
end

local function OnlyFound()
	return SpokenBooksSettings and SpokenBooksSettings.compendiumFoundOnly == true
end

-- Voiced Only, after Found Only in the filter menu: what no installed voice pack reads is left out,
-- and with it any zone, type or group left with nothing. A writing is voiced as Play finds it: its
-- first page has a recording.
local function OnlyVoiced()
	return SpokenBooksSettings ~= nil and SpokenBooksSettings.compendiumVoicedOnly == true
end

local function Voiced(id)
	local book = Books()[id]
	return book ~= nil and SpokenBooks:HasAudio(book.pages[1]) and true or false
end

-- Whether a set of writings ({ [id] = true }) has one to list under Voiced Only.
local function Listed(set)
	if not OnlyVoiced() then return true end
	for id in pairs(set) do
		if Voiced(id) then return true end
	end
	return false
end

-- By Zone, under the list: on, zones then types; off, the types alone.
local function ByZone()
	return not (SpokenBooksSettings and SpokenBooksSettings.compendiumByZone == false)
end

local function Matches(text)
	return filter == "" or (text and string.find(string.lower(text), filter, 1, true) ~= nil)
end

local function ByName(a, b)
	local na, nb = MapName(a), MapName(b)
	if na == nb then return a < b end
	return na < nb
end

-- The zones on `continent` that have readables, cities left to the zone around them and
-- battlegrounds to their banner.
local function ZonesOn(continent)
	local out = {}
	for mapID in pairs(Index().zones) do
		if not CITY_IN[mapID] and not IS_BATTLEGROUND[mapID] and ContinentOf(mapID) == continent then
			table.insert(out, mapID)
		end
	end
	-- A zone with no readables of its own but a city that has some.
	for city, zone in pairs(CITY_IN) do
		if Index().zones[city] and ContinentOf(zone) == continent then
			local listed = false
			for _, z in ipairs(out) do if z == zone then listed = true end end
			if not listed then table.insert(out, zone) end
		end
	end
	table.sort(out, ByName)
	return out
end

-- The zones with readables on no continent, under Other Lands after the continents. Not a map
-- this client has never heard of: its card would lead nowhere.
local function LooseZones()
	local out = {}
	for mapID in pairs(Index().zones) do
		if not CITY_IN[mapID] and not IS_BATTLEGROUND[mapID] and not ContinentOf(mapID)
			and not (C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID) == nil) then
			table.insert(out, mapID)
		end
	end
	table.sort(out, ByName)
	return out
end

-- The battlegrounds with readables, by name.
local function Battlegrounds()
	local out = {}
	for _, mapID in ipairs(BATTLEGROUNDS) do
		if Index().zones[mapID] then table.insert(out, mapID) end
	end
	table.sort(out, ByName)
	return out
end

local ZONES_OF = { lands = LooseZones, battlegrounds = Battlegrounds }

-- Every readable under `mapID`, its city's included, each once.
local function ReadablesIn(mapID, into)
	into = into or {}
	local zone = Index().zones[mapID]
	if zone then
		for _, ids in pairs(zone) do
			for _, id in ipairs(ids) do into[id] = true end
		end
	end
	for city, around in pairs(CITY_IN) do
		if around == mapID then ReadablesIn(city, into) end
	end
	return into
end

-- Found out of all, of what is listed: under Voiced Only, what no voice pack reads is left out of
-- the count as it is of the rows, so the number is of the rows beneath it.
local function Tally(set)
	local found, total = 0, 0
	for id in pairs(set) do
		if not OnlyVoiced() or Voiced(id) then
			total = total + 1
			if Found(id) then found = found + 1 end
		end
	end
	return found, total
end

--------------------------------------------------------------------------------
-- The rows
--------------------------------------------------------------------------------

local function Leaf(id, nest)
	if OnlyFound() and not Found(id) then return nil end
	if OnlyVoiced() and not Voiced(id) then return nil end
	if filter ~= "" and not Matches(Title(id)) then return nil end
	return { kind = "readable", leaf = true, book = id, label = Title(id), nest = nest,
		locked = not Found(id) and not Unlocked(), done = Found(id) and true or false }
end

local function Leaves(ids, nest, into)
	for _, id in ipairs(ids) do
		local row = Leaf(id, nest)
		if row then table.insert(into, row) end
	end
end

-- What each kind of writing shows on its card, from the game's own icons; plain parchment for the
-- rest.
local KIND_ICON = {
	book = [[Interface\Icons\INV_Misc_Book_09]],
	letter = [[Interface\Icons\INV_Letter_04]],
	note = [[Interface\Icons\INV_Misc_Note_01]],
	scroll = [[Interface\Icons\INV_Scroll_03]],
	tablet = [[Interface\Icons\INV_Misc_StoneTablet_04]],
	rune = [[Interface\Icons\INV_Misc_Rune_06]],
	plaque = [[Interface\Icons\INV_Misc_StoneTablet_03]],
	sign = [[Interface\Icons\INV_Misc_StoneTablet_06]],
	grave = [[Interface\Icons\INV_Misc_StoneTablet_02]],
	exhibit = [[Interface\Icons\INV_Misc_Statue_02]],
	journal = [[Interface\Icons\INV_Misc_Book_11]],
	diary = [[Interface\Icons\INV_Misc_Book_11]],
	picture = [[Interface\Icons\INV_Misc_Map_01]],
	map = [[Interface\Icons\INV_Misc_Map_01]],
	other = [[Interface\Icons\INV_Scroll_08]],
}

-- A card's numbers: the found out of all on its line, the share and the bar. Its badge: a zone's
-- painting, or what its kind of writing looks like.
local function Card(item, found, total)
	item.style = "card"
	item.count, item.total = found, total
	if item.kind == "zone" then
		if Spoken and Spoken.ZoneIcon then item.icon, item.iconCrop = Spoken:ZoneIcon(item.mapID) end
	else
		item.icon = KIND_ICON[item.which] or KIND_ICON.other
	end
	item.sub = L.FOUND_FMT:format(found, total)
	item.ratio = total > 0 and found / total or 0
	item.tick = total > 0 and found == total
	item.none = found == 0
	return item
end

-- A card for each kind of writing in `byType` ({ [type] = ids }) with something listed, and its
-- writings under it while it is open: open until closed, and always while searching. `item`
-- makes each card's own fields.
local function KindCards(byType, nest, into, item, shut)
	for _, type in ipairs(TYPES) do
		local ids = byType[type] or {}
		if #ids > 0 then
			local leaves = {}
			Leaves(ids, nest + 1, leaves)
			if #leaves > 0 then
				local set = {}
				for _, id in ipairs(ids) do set[id] = true end
				local closed = filter == "" and shut(type)
				local card = item(type)
				card.label, card.nest, card.open = TypeLabel(type), nest, not closed
				table.insert(into, Card(card, Tally(set)))
				if not closed then
					for _, row in ipairs(leaves) do table.insert(into, row) end
				end
			end
		end
	end
end

-- A zone's card, and when it is open (or a search finds something in it) its city's small card,
-- then a small card for each kind of writing in it.
local function ZoneRows(mapID, nest, small)
	local all = ReadablesIn(mapID)
	local found, total = Tally(all)
	if OnlyFound() and found == 0 then return {} end
	if not Listed(all) then return {} end
	local open = expandedZone == mapID or CITY_IN[expandedZone] == mapID
	local inside = {}
	if open or filter ~= "" then
		for city, around in pairs(CITY_IN) do
			if around == mapID and Index().zones[city] then
				for _, row in ipairs(ZoneRows(city, nest + 1, true)) do table.insert(inside, row) end
			end
		end
		KindCards(Index().zones[mapID] or {}, nest + 1, inside,
			function(type) return { kind = "group", which = type, mapID = mapID, small = true } end,
			function(type) return zoneTypeShut[mapID .. ":" .. type] end)
	end
	if filter ~= "" and #inside == 0 and not Matches(MapName(mapID)) then return {} end
	local rows = { Card({ kind = "zone", small = small, mapID = mapID, label = MapName(mapID), nest = nest,
		open = (open or filter ~= "") and #inside > 0 }, found, total) }
	for _, row in ipairs(inside) do table.insert(rows, row) end
	return rows
end

-- Those found across Azeroth, or of no known origin: a banner of their own after the continents,
-- holding a card for each kind of writing.
local function GroupRows(key, label, ids)
	if #ids == 0 then return {} end
	local set, byType = {}, {}
	for _, id in ipairs(ids) do
		set[id] = true
		local type = Index().typeOf[id]
		byType[type] = byType[type] or {}
		table.insert(byType[type], id)
	end
	local found, total = Tally(set)
	if OnlyFound() and found == 0 then return {} end
	if not Listed(set) then return {} end
	local inside = {}
	if groupOpen[key] or filter ~= "" then
		KindCards(byType, 0, inside,
			function(type) return { kind = "kind", which = type, group = key } end,
			function(type) return groupTypeShut[key .. ":" .. type] end)
	end
	if filter ~= "" and #inside == 0 then return {} end
	local rows = { { style = "banner", kind = "group", which = key, label = label, count = found, total = total,
		open = #inside > 0 } }
	for _, row in ipairs(inside) do table.insert(rows, row) end
	return rows
end

-- By Zone off: a card for each kind of writing, every one of it under it.
local function TypeRows()
	local out = {}
	for _, type in ipairs(TYPES) do
		local ids = Index().types[type] or {}
		if #ids > 0 then
			local set = {}
			for _, id in ipairs(ids) do set[id] = true end
			local found, total = Tally(set)
			local leaves = {}
			if typeOpen[type] or filter ~= "" then Leaves(ids, 1, leaves) end
			if not (OnlyFound() and found == 0) and Listed(set) and (filter == "" or #leaves > 0) then
				table.insert(out, Card({ kind = "type", which = type, nest = 0, label = TypeLabel(type),
					open = #leaves > 0 }, found, total))
				for _, row in ipairs(leaves) do table.insert(out, row) end
			end
		end
	end
	return out
end

-- Other Lands' or Battlegrounds' banner, a card for each of its zones under it, opened and chosen
-- as a continent's.
local function ZoneBanner(key)
	local zones = ZONES_OF[key]()
	if #zones == 0 then return {} end
	local set = {}
	for _, mapID in ipairs(zones) do ReadablesIn(mapID, set) end
	local found, total = Tally(set)
	if (OnlyFound() and found == 0) or not Listed(set) then return {} end
	local searching = filter ~= ""
	local inside = {}
	if searching or zonesOpen[key] then
		for _, mapID in ipairs(zones) do
			for _, row in ipairs(ZoneRows(mapID, 0)) do table.insert(inside, row) end
		end
	end
	if searching and #inside == 0 then return {} end
	local rows = { { style = "banner", kind = "zones", key = key, label = L[ZONES_LABEL[key]], count = found,
		total = total, open = #inside > 0 } }
	for _, row in ipairs(inside) do table.insert(rows, row) end
	return rows
end

-- A banner for each continent, its zones' cards under it; Other Lands' and Battlegrounds'; then
-- the groups' banners.
local function BuildRows()
	if not ByZone() then return TypeRows() end
	local out = {}
	local function Add(rows) for _, row in ipairs(rows) do table.insert(out, row) end end
	local searching = filter ~= ""
	local continents = {}
	for _, continent in ipairs(CONTINENTS) do
		local zones = ZonesOn(continent)
		if #zones > 0 then
			local set = {}
			for _, mapID in ipairs(zones) do ReadablesIn(mapID, set) end
			local found, total = Tally(set)
			local rows = {}
			if searching or continentOpen[continent] then
				for _, mapID in ipairs(zones) do
					for _, row in ipairs(ZoneRows(mapID, 0)) do table.insert(rows, row) end
				end
			end
			if not (OnlyFound() and found == 0) and Listed(set) and (not searching or #rows > 0) then
				table.insert(continents, { style = "banner", kind = "continent", mapID = continent,
					label = MapName(continent), count = found, total = total, open = #rows > 0, rows = rows })
			end
		end
	end
	table.sort(continents, function(a, b) return a.label < b.label end)
	for _, continent in ipairs(continents) do
		table.insert(out, continent)
		Add(continent.rows)
	end
	Add(ZoneBanner("lands"))
	Add(ZoneBanner("battlegrounds"))
	Add(GroupRows("events", L.GROUP_EVENTS, Index().events))
	Add(GroupRows("wide", L.GROUP_WIDE, Index().wide))
	Add(GroupRows("unknown", L.GROUP_UNKNOWN, Index().unknown))
	return out
end

local function IsSelected(row)
	if not selection then return false end
	if row.kind == "zones" then return selection.zones == row.key end
	if row.kind == "readable" then return selection.book == row.book end
	if row.kind == "kind" then return selection.group == row.group and selection.type == row.which end
	if row.kind == "group" then
		return selection.group == row.which and selection.mapID == row.mapID and not selection.type
	end
	if row.kind == "type" then return selection.type == row.which and not selection.group end
	return selection.mapID == row.mapID and not selection.book and not selection.group
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

-- Play on a readable's page: the book from its first page, or stop it.
local PLAY = {
	has = function(id) local book = Books()[id] return book ~= nil and SpokenBooks:HasAudio(book.pages[1]) end,
	playing = function(id) return SpokenBooks:IsNarrating(id) end,
	-- Browsing: heard here is not heard in the world (Read Only Once), nor found.
	start = function(id) SpokenBooks:SyncTo(Books()[id].pages[1], true) end,
	stop = function(id) SpokenBooks:StopReading(id) end,
}

-- How a carried readable is had, one line each: "Dropped by Defias Messenger (Westfall)".
local HOW = {
	["drop"] = "FROM_DROP", ["pickpocket"] = "FROM_PICKPOCKET", ["quest start"] = "FROM_QUEST_START",
	["quest reward"] = "FROM_QUEST_REWARD", ["quest"] = "FROM_QUEST", ["mail"] = "FROM_MAIL",
	["object"] = "FROM_OBJECT", ["container"] = "FROM_CONTAINER", ["fishing"] = "FROM_FISHING", ["vendor"] = "FROM_VENDOR",
}

local function LocalName(index)
	local names = _G.SpokenBooksPlaces and SpokenBooksPlaces.names
	local name = names and names[index]
	if not name then return nil end
	local locale = GetLocale and GetLocale() or "enUS"
	return name[locale] or name[1]
end

local function ZoneList(zones)
	local names = {}
	for _, mapID in ipairs(zones or {}) do table.insert(names, MapName(mapID)) end
	return table.concat(names, ", ")
end

local function Sources(place)
	local lines = {}
	for _, from in ipairs(place.from or {}) do
		local key = HOW[from[1]]
		if key and L[key] then
			local name = from[2] and LocalName(from[2])
			local line = name and L[key]:format(name) or (from[1] == "fishing" and L[key] or nil)
			if line then
				local zones = {}
				for i = 3, #from do table.insert(zones, from[i]) end
				if #zones > 0 then line = L.FROM_IN_ZONES:format(line, ZoneList(zones)) end
				table.insert(lines, line)
			end
		end
	end
	return lines
end

local function Count(found, total)
	return L.FOUND_FMT:format(found, total)
end

local function ShowEntry()
	if not page then return end
	if not selection then
		page:Show({ title = L.COMPENDIUM_READABLES, subtitle = Count(Tally(Index().all)), text = L.READABLES_PICK })
		return
	end
	if selection.book then
		local id = selection.book
		local place = _G.SpokenBooksPlaces and SpokenBooksPlaces.books[id] or {}
		local where
		if place.event then
			where = L.GROUP_EVENTS
		elseif place.wide then
			where = L.GROUP_WIDE
		elseif place.zones then
			where = (place.kind == "world" and L.KIND_WORLD or L.KIND_CARRIED) .. " · " .. ZoneList(place.zones)
		else
			where = L.GROUP_UNKNOWN
		end
		if not Found(id) and not Unlocked() then
			page:Show({ title = Title(id), subtitle = where, text = L.READABLE_NOT_FOUND })
			return
		end
		local parts = {}
		local sources = Sources(place)
		if #sources > 0 then table.insert(parts, table.concat(sources, "\n")) end
		local data = SpokenBooks:Data()
		for _, pageId in ipairs(Books()[id].pages) do
			local text = data.pages[pageId] and data.pages[pageId].text
			if text and text ~= "" then table.insert(parts, text) end
		end
		page:Show({ title = Title(id), subtitle = where, text = table.concat(parts, "\n\n"), target = id })
		return
	end
	-- A zone, a continent, a group, a type: what it holds.
	local set = {}
	if selection.type and not selection.group then
		for _, id in ipairs(Index().types[selection.type] or {}) do set[id] = true end
		page:Show({ title = TypeLabel(selection.type), subtitle = Count(Tally(set)), text = L.READABLES_PICK })
		return
	end
	if selection.group and selection.mapID and TYPE_NAMES[selection.group] then
		for _, id in ipairs((Index().zones[selection.mapID] or {})[selection.group] or {}) do set[id] = true end
		page:Show({ title = TypeLabel(selection.group), subtitle = MapName(selection.mapID) .. " · " .. Count(Tally(set)),
			text = L.READABLES_PICK })
		return
	end
	if selection.type and selection.group then
		local where = L[GROUP_LABEL[selection.group]]
		for _, id in ipairs(Index()[selection.group]) do
			if Index().typeOf[id] == selection.type then set[id] = true end
		end
		page:Show({ title = TypeLabel(selection.type), subtitle = where .. " · " .. Count(Tally(set)),
			text = L.READABLES_PICK })
		return
	end
	if selection.zones then
		for _, mapID in ipairs(ZONES_OF[selection.zones]()) do ReadablesIn(mapID, set) end
		page:Show({ title = L[ZONES_LABEL[selection.zones]], subtitle = Count(Tally(set)), text = L.READABLES_PICK })
		return
	end
	if GROUP_LABEL[selection.group] then
		for _, id in ipairs(Index()[selection.group]) do set[id] = true end
		page:Show({ title = L[GROUP_LABEL[selection.group]], subtitle = Count(Tally(set)), text = L.READABLES_PICK })
		return
	end
	if selection.mapID == WORLD then
		set = Index().all
	elseif selection.mapID == 1414 or selection.mapID == 1415 then
		for _, mapID in ipairs(ZonesOn(selection.mapID)) do ReadablesIn(mapID, set) end
	else
		ReadablesIn(selection.mapID, set)
	end
	page:Show({ title = MapName(selection.mapID), subtitle = Count(Tally(set)), text = L.READABLES_PICK })
end

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

local function OnClick(row)
	if row.kind == "readable" then
		selection = { book = row.book }
	elseif row.kind == "zones" then
		if filter == "" then zonesOpen[row.key] = not zonesOpen[row.key] end
		selection = { zones = row.key }
	elseif row.kind == "type" then
		if filter == "" then typeOpen[row.which] = not typeOpen[row.which] end
		selection = { type = row.which }
	elseif row.kind == "kind" then
		-- A group's Books, Notes and the rest: closed and opened again, as a zone's are.
		local key = row.group .. ":" .. row.which
		if filter == "" then groupTypeShut[key] = not groupTypeShut[key] or nil end
		selection = { group = row.group, type = row.which }
	elseif filter ~= "" then
		selection = { mapID = row.mapID, group = row.kind == "group" and row.which or nil }
	elseif row.kind == "continent" then
		continentOpen[row.mapID] = not continentOpen[row.mapID]
		selection = { mapID = row.mapID }
	elseif row.kind == "zone" then
		if expandedZone == row.mapID or CITY_IN[expandedZone] == row.mapID then
			expandedZone = CITY_IN[row.mapID]
		else
			expandedZone = row.mapID
		end
		selection = { mapID = row.mapID }
	elseif row.kind == "group" and not row.mapID then
		groupOpen[row.which] = not groupOpen[row.which]
		selection = { group = row.which }
	else
		-- A zone's Books, Notes and the rest: closed and opened again, as the zone is.
		local key = row.mapID .. ":" .. row.which
		zoneTypeShut[key] = not zoneTypeShut[key] or nil
		selection = { mapID = row.mapID, group = row.which }
	end
	SpokenBooks:RefreshReadables()
end

function SpokenBooks:RefreshReadables(scrollToSelection)
	if not list then return end
	local items = list:Render()
	if scrollToSelection and selection then list:ScrollToSelection(items) end
	ShowEntry()
end

local function Build(panel)
	list = SpokenCompendium.NewList(panel, {
		search = L.READABLES_SEARCH,
		none = L.READABLES_NONE,
		only = L.READABLES_FOUND_ONLY,
		onlyGet = OnlyFound,
		onlySet = function(on) if SpokenBooksSettings then SpokenBooksSettings.compendiumFoundOnly = on end end,
		checks = { { label = L.READABLES_VOICED_ONLY, get = OnlyVoiced,
			set = function(on) if SpokenBooksSettings then SpokenBooksSettings.compendiumVoicedOnly = on end end } },
		-- By zone, then type; or by type alone.
		arrange = {
			values = { "zone", "type" },
			describe = function(value) return value == "type" and L.READABLES_BY_TYPE or L.READABLES_BY_ZONE end,
			get = function() return ByZone() and "zone" or "type" end,
			set = function(value) if SpokenBooksSettings then SpokenBooksSettings.compendiumByZone = value == "zone" end end,
		},
		build = BuildRows,
		isSelected = IsSelected,
		onClick = OnClick,
		onSearch = function(text)
			filter = text
			SpokenBooks:RefreshReadables()
		end,
		addScrollBar = function(scroll, child, inset) return SpokenBooks:AddScrollBar(scroll, child, inset) end,
	})
	panel.Refresh = function() SpokenBooks:RefreshReadables() end
	panel.inset, panel.filterButton, panel.filterMenu, panel.noMatch = list.inset, list.filterButton, list.filterMenu, list.noMatch

	local _, right = SpokenCompendium.Margins()
	local window = SpokenCompendium:Window()
	local ok, pageInset = pcall(CreateFrame, "Frame", nil, panel, "InsetFrameTemplate")
	if not ok or not pageInset then pageInset = CreateFrame("Frame", nil, panel) end
	pageInset:SetPoint("TOPLEFT", list.inset, "TOPRIGHT", 6, 38)
	pageInset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -right, window.templated and 6 or 12)
	panel.pageInset = pageInset
	local holder = CreateFrame("Frame", nil, pageInset)
	holder:SetPoint("TOPLEFT", pageInset, "TOPLEFT", 3, -3)
	holder:SetPoint("BOTTOMRIGHT", pageInset, "BOTTOMRIGHT", -3, 3)
	page = C.NewPage(holder, SpokenBooks, PLAY)
	if type(pageInset.NineSlice) == "table" and pageInset.NineSlice.SetFrameLevel then
		pageInset.NineSlice:SetFrameLevel(holder:GetFrameLevel() + 5)
	end
	panel.page = page
	SpokenBooks.readables = panel
end

--- Open the readables.
function SpokenBooks:ShowReadables()
	if not SpokenCompendium then return end
	if list then
		list:ClearSearch()
		filter = ""
	end
	SpokenCompendium:Open("readables")
	SpokenCompendium:Expand()
	SpokenBooks:RefreshReadables(true)
end

-- The window's size, with the rest of this addon's settings, for when Spoken Zones is not there
-- to keep it.
local SIZE_KEYS = { width = "compendiumWidth", height = "compendiumHeight" }

function SpokenBooks:SetupReadables()
	if not SpokenCompendium or SpokenCompendium:Tab("readables") then return end
	SpokenCompendium:Register("readables", {
		label = L.COMPENDIUM_READABLES,
		order = 2,
		title = L.COMPENDIUM_TITLE,
		build = Build,
		store = {
			get = function(key) return SpokenBooksSettings and SpokenBooksSettings[SIZE_KEYS[key]] end,
			set = function(key, value) if SpokenBooksSettings then SpokenBooksSettings[SIZE_KEYS[key]] = value end end,
		},
		open = function() SpokenBooks:ShowReadables() end,
		enabled = function() return SpokenBooks:IsPartOn() end,
		-- Unlock Unfound Books, on Spoken's page.
		unlock = {
			get = function() return SpokenBooksSettings ~= nil and SpokenBooksSettings.unlockUnfound == true end,
			set = function(value)
				if SpokenBooksSettings then SpokenBooksSettings.unlockUnfound = value end
				SpokenBooks:RefreshReadables()
			end,
		},
	})
end
