-- SpokenBooks -- the readables in Azeroth's Compendium (UI/Compendium.lua): every book, letter,
-- note and plaque Spoken Readables reads, found or not, to read and listen to anywhere.
--
-- The list is laid out as the places' (Spoken Places' tab): a banner for each continent, a card for
-- each of its zones (how many of its writings are found, with a bar), a city a card inside the
-- zone around it, and after it the card of each dungeon or raid whose entrance is in the zone, as
-- the Quests tab files their quests (a zone with several has a Dungeons and Raids line holding
-- them); in an opened zone or dungeon a line for each kind of writing -- books, journals, letters,
-- notes, scrolls, tablets, plaques, gravestones, exhibits, pictures -- and the writings under it.
-- After the continents, Other Lands' banner for the zones on none and Battlegrounds', each with a
-- card for each of its zones; then a banner each for the seasonal events' readables, for those had
-- in too many zones to list under each and for those whose origin is not known, with a line for
-- each kind inside. With By Zone off, the list is a banner for each kind alone, every readable
-- under its own. Where each is comes from Data/Places.lua; what this character has found, from
-- SpokenBooksCharacter (Core.lua). A readable not found yet is listed greyed, with a padlock, and
-- does not open, unless Unlock Unfound Readables is on. On the right its pages, on parchment, with
-- where it comes from and Play.

local ADDON_NAME, SpokenBooks = ...

-- A value the game hands over as a secret, in an instance or in combat, reads as nil.
local NotSecret = Spoken and Spoken.NotSecret or function(value) return value end

local L = SpokenBooks.L

local C = SpokenCompendium
local CONTINENTS, CITY_IN = C.CONTINENTS, C.CITY_IN
local MapName, ContinentOf = C.MapName, C.ContinentOf

local list, page
local selection          -- { book = id } | { mapID = id } | { mapID = id, group = type }
                         -- | { mapID = id, dungeons = true } | { mapID = id, dungeon = map }
                         -- | { mapID = id, dungeon = map, group = type }
                         -- | { group = "events"|"wide"|"unknown" }
                         -- | { group = "events"|"wide"|"unknown", type = type } | { type = type }
                         -- | { zones = "lands"|"battlegrounds" } | nil
local landed             -- the selection made for the player, where they stood; any other they chose
local openZones = {}          -- [mapID] = true: a zone's or city's card, opened
local dungeonsOpen = {}       -- [mapID] = true: a zone's Dungeons and Raids line, opened
local dungeonOpen = {}        -- ["mapID:map"] = true: a dungeon's card, opened
-- A dungeon's or a raid's card's badge, the Quests tab's: a key, as to a door below.
local DUNGEON_ICON = [[Interface\Icons\INV_Misc_Key_03]]
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
local zoneTypeOpen = {}       -- ["mapID:type"] = true: a zone's Books, Notes and the rest, opened;
                              -- ["mapID:map:type"] = true: a dungeon's
local groupTypeOpen = {}      -- ["wide:type"] = true: the same in a group's banner
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

-- The dungeons and raids, by instance map: { zone = the zone of its entrance, English name, [locale]
-- = name }.
local function Dungeons()
	return _G.SpokenBooksPlaces and SpokenBooksPlaces.dungeons or {}
end

local function DungeonName(map)
	local names = Dungeons()[map]
	if not names then return tostring(map) end
	local locale = GetLocale and GetLocale() or "enUS"
	return names[locale] or names[1]
end

-- Every readable by where it is: index.zones[mapID] = { [type] = { ids } } for the zone's own,
-- index.dungeons[mapID][map] = { [type] = { ids } } for each dungeon whose entrance is in it, the
-- three groups, the types, and `all`, what every count is out of. A readable Data/Places.lua does
-- not carry is left out everywhere: places.mjs drops the Deprecated and TEST items no one can
-- find, and counting them would keep every total out of reach. Built once: the data is fixed for
-- the session.
local index
local function Index()
	if index then return index end
	index = { zones = {}, dungeons = {}, events = {}, wide = {}, unknown = {}, types = {}, all = {}, typeOf = {} }
	local places = _G.SpokenBooksPlaces and SpokenBooksPlaces.books or {}
	local function Add(mapID, type, id, map)
		local zone = index.zones[mapID] or {}
		index.zones[mapID] = zone
		if map then
			index.dungeons[mapID] = index.dungeons[mapID] or {}
			zone = index.dungeons[mapID][map] or {}
			index.dungeons[mapID][map] = zone
		end
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
				-- One in a city and in the zone around it is listed in the city alone: the zone's
				-- card holds the city's, and would list it twice.
				local cityIn = {}
				for _, mapID in ipairs(place.zones) do
					if CITY_IN[mapID] then cityIn[CITY_IN[mapID]] = true end
				end
				-- One had inside a dungeon alone, in the zone of the dungeon's entrance, is the dungeon's.
				local inDungeon = {}
				for _, map in ipairs(place.dungeons or {}) do
					local dungeon = Dungeons()[map]
					if dungeon then
						inDungeon[dungeon.zone] = inDungeon[dungeon.zone] or {}
						table.insert(inDungeon[dungeon.zone], map)
					end
				end
				for _, mapID in ipairs(place.zones) do
					if not cityIn[mapID] then
						if inDungeon[mapID] then
							for _, map in ipairs(inDungeon[mapID]) do Add(mapID, type, id, map) end
						else
							Add(mapID, type, id)
						end
					end
				end
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
	for _, dungeons in pairs(index.dungeons) do
		for _, dungeon in pairs(dungeons) do
			for _, ids in pairs(dungeon) do table.sort(ids, ByTitle) end
		end
	end
	for _, ids in pairs(index.types) do table.sort(ids, ByTitle) end
	table.sort(index.events, ByTitle)
	table.sort(index.wide, ByTitle)
	table.sort(index.unknown, ByTitle)
	return index
end

-- Each readable that shares its title with others ("Dark Keeper Nameplate", six of them) by its
-- place among them in id order, so no two rows read the same.
local nth
local function Nth()
	if nth then return nth end
	nth = {}
	local byTitle = {}
	for id in pairs(Index().all) do
		local title = Title(id)
		byTitle[title] = byTitle[title] or {}
		table.insert(byTitle[title], id)
	end
	for _, ids in pairs(byTitle) do
		if #ids > 1 then
			table.sort(ids)
			for i, id in ipairs(ids) do nth[id] = i end
		end
	end
	return nth
end

-- A readable's name in the list and on its page: its title, numbered where others share it.
local function Name(id)
	local n = Nth()[id]
	return n and L.BOOKS_TITLE_NTH_FMT:format(Title(id), n) or Title(id)
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
-- and with it any zone, type or group left with nothing. A writing is voiced as Play finds it: a
-- page of it has a recording.
local function OnlyVoiced()
	return SpokenBooksSettings ~= nil and SpokenBooksSettings.compendiumVoicedOnly == true
end

-- A readable's first page with a recording, where Play starts it, or nil.
local function FirstVoiced(id)
	local book = Books()[id]
	for _, pageId in ipairs(book and book.pages or {}) do
		if SpokenBooks:HasAudio(pageId) then return pageId end
	end
end

local function Voiced(id)
	return FirstVoiced(id) ~= nil
end

-- Whether a set of writings ({ [id] = true }) has one to list under Voiced Only.
local function Listed(set)
	if not OnlyVoiced() then return true end
	for id in pairs(set) do
		if Voiced(id) then return true end
	end
	return false
end

-- By Zone, in the filter menu: on, zones then types; off, the types alone.
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

-- The battlegrounds with readables, by name. Not a map this client has never heard of: its card
-- would lead nowhere.
local function Battlegrounds()
	local out = {}
	for _, mapID in ipairs(BATTLEGROUNDS) do
		if Index().zones[mapID] and not (C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID) == nil) then
			table.insert(out, mapID)
		end
	end
	table.sort(out, ByName)
	return out
end

local ZONES_OF = { lands = LooseZones, battlegrounds = Battlegrounds }

-- Every readable of the dungeon `map` whose entrance is in `mapID`.
local function DungeonReadables(mapID, map, into)
	into = into or {}
	for _, ids in pairs((Index().dungeons[mapID] or {})[map] or {}) do
		for _, id in ipairs(ids) do into[id] = true end
	end
	return into
end

-- Every readable under `mapID`, its city's and its dungeons' included, each once.
local function ReadablesIn(mapID, into)
	into = into or {}
	local zone = Index().zones[mapID]
	if zone then
		for _, ids in pairs(zone) do
			for _, id in ipairs(ids) do into[id] = true end
		end
	end
	for map in pairs(Index().dungeons[mapID] or {}) do DungeonReadables(mapID, map, into) end
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

-- Whether a search names what holds `label`: then all it holds is listed, each title matching or not.
local function Named(label, whole)
	return whole or (filter ~= "" and Matches(label))
end

-- Set while the rows under a banner whose name the search matches are built: each is listed,
-- closed or open as the player left it, and opens and closes on a click as it does unsearched. A
-- continent's every readable at once would be too long a list to read.
local asLeft = false

-- What a search opened and the player closed again with a click, by row; a new search opens all.
local searchClosed = {}

-- Whether the search opens the row closed under `key`: not where the player closed it.
local function SearchOpens(key)
	return filter ~= "" and not asLeft and not searchClosed[key]
end

-- While a search opens everything it finds, a click on an open row closes it, and opens it again.
local function SearchFold(row)
	if filter == "" or row.asLeft or not row.closeKey then return false end
	searchClosed[row.closeKey] = not searchClosed[row.closeKey] or nil
	return true
end

-- The rows `build` returns, built with asLeft set where `named`.
local function AsLeft(named, build)
	local before = asLeft
	asLeft = before or named
	local rows = build()
	asLeft = before
	return rows
end

-- A readable's row, or nil where it is not listed. `whole`: what holds it was named by the search.
local function Leaf(id, nest, whole)
	if OnlyFound() and not Found(id) then return nil end
	if OnlyVoiced() and not Voiced(id) then return nil end
	if filter ~= "" and not whole and not Matches(Title(id)) then return nil end
	return { kind = "readable", leaf = true, book = id, label = Name(id), nest = nest,
		locked = not Found(id) and not Unlocked(), done = Found(id) and true or false }
end

local function Leaves(ids, nest, into, whole)
	for _, id in ipairs(ids) do
		local row = Leaf(id, nest, whole)
		if row then table.insert(into, row) end
	end
end

-- A zone's or a dungeon's card or a line, with its numbers: the found out of all, the share and the
-- bar. A zone's card has the zone's painting for a badge, a dungeon's a key; a line has none.
local function Card(item, found, total)
	item.style = (item.kind == "zone" or item.kind == "dungeon") and "card" or "group"
	item.count, item.total = found, total
	item.asLeft = asLeft
	if item.kind == "zone" and Spoken and Spoken.ZoneIcon then
		item.icon, item.iconCrop = Spoken:ZoneIcon(item.mapID)
	elseif item.kind == "dungeon" then
		item.icon = DUNGEON_ICON
	end
	item.ratio = total > 0 and found / total or 0
	item.tick = total > 0 and found == total
	item.none = found == 0
	return item
end

-- A line for each kind of writing in `byType` ({ [type] = ids }) with something listed, and its
-- writings under it while it is open: closed until opened, as Quests' chains are, and always open
-- while searching. `item` makes each line's own fields.
local function KindCards(byType, nest, into, item, opened, whole)
	for _, type in ipairs(TYPES) do
		local ids = byType[type] or {}
		if #ids > 0 then
			local leaves = {}
			Leaves(ids, nest + 1, leaves, Named(TypeLabel(type), whole))
			if #leaves > 0 then
				local set = {}
				for _, id in ipairs(ids) do set[id] = true end
				local card = item(type)
				local holder = card.dungeon and ("k" .. card.mapID .. ":" .. card.dungeon)
					or card.mapID and ("k" .. card.mapID) or ("g" .. tostring(card.group))
				card.closeKey = holder .. ":" .. type
				local closed
				if filter == "" or asLeft then
					closed = not opened(type)
				else
					closed = not SearchOpens(card.closeKey)
				end
				card.label, card.nest, card.open = TypeLabel(type), nest, not closed
				table.insert(into, Card(card, Tally(set)))
				if not closed then
					for _, row in ipairs(leaves) do table.insert(into, row) end
				end
			end
		end
	end
end

-- `rows`, the first of them the card or line `item` holding them, shown while it is open.
local function Holding(item, inside, shown)
	local rows = { item }
	if shown then
		for _, row in ipairs(inside) do table.insert(rows, row) end
	end
	return rows
end

-- A dungeon's or a raid's card, and when it is open (or a search finds something in it) a line for
-- each kind of writing in it, as a zone's.
local function DungeonCard(mapID, map, nest, whole)
	local name = DungeonName(map)
	whole = Named(name, whole)
	local all = DungeonReadables(mapID, map)
	local found, total = Tally(all)
	if OnlyFound() and found == 0 then return {} end
	if not Listed(all) then return {} end
	local key = mapID .. ":" .. map
	local open = dungeonOpen[key] == true
	local inside = {}
	if open or (filter ~= "" and not asLeft) then
		KindCards(Index().dungeons[mapID][map], nest + 1, inside,
			function(type) return { kind = "group", which = type, mapID = mapID, dungeon = map } end,
			function(type) return zoneTypeOpen[key .. ":" .. type] end, whole)
	end
	if filter ~= "" and #inside == 0 and not whole then return {} end
	local shown
	if filter ~= "" and not asLeft then shown = SearchOpens("d" .. key) else shown = open end
	return Holding(Card({ kind = "dungeon", mapID = mapID, dungeon = map, label = name, nest = nest,
		open = shown and #inside > 0, closeKey = "d" .. key }, found, total), inside, shown)
end

-- The dungeons and raids whose entrances are in a zone: the one's card, or a Dungeons and Raids
-- line with a card for each under it (Blackrock Mountain's, in Searing Gorge).
local function DungeonRows(mapID, nest, whole)
	local maps = {}
	for map in pairs(Index().dungeons[mapID] or {}) do table.insert(maps, map) end
	if #maps == 0 then return {} end
	if #maps == 1 then return DungeonCard(mapID, maps[1], nest, whole) end
	table.sort(maps, function(a, b)
		local na, nb = DungeonName(a), DungeonName(b)
		if na == nb then return a < b end
		return na < nb
	end)
	whole = Named(L.GROUP_DUNGEONS, whole)
	local all = {}
	for _, map in ipairs(maps) do DungeonReadables(mapID, map, all) end
	local found, total = Tally(all)
	if OnlyFound() and found == 0 then return {} end
	if not Listed(all) then return {} end
	local open = dungeonsOpen[mapID] == true
	local inside = {}
	if open or (filter ~= "" and not asLeft) then
		for _, map in ipairs(maps) do
			for _, row in ipairs(DungeonCard(mapID, map, nest + 1, whole)) do table.insert(inside, row) end
		end
	end
	if filter ~= "" and #inside == 0 and not whole then return {} end
	local shown
	if filter ~= "" and not asLeft then shown = SearchOpens("ds" .. mapID) else shown = open end
	return Holding(Card({ kind = "dungeons", mapID = mapID, label = L.GROUP_DUNGEONS, nest = nest,
		open = shown and #inside > 0, closeKey = "ds" .. mapID }, found, total), inside, shown)
end

-- A zone's card, and when it is open (or a search finds something in it) its city's card, its
-- dungeons', then a line for each kind of writing in it. A city's card opens on its own, and shows
-- only while its zone is open.
local function ZoneRows(mapID, nest, whole)
	whole = Named(MapName(mapID), whole)
	local all = ReadablesIn(mapID)
	local found, total = Tally(all)
	if OnlyFound() and found == 0 then return {} end
	if not Listed(all) then return {} end
	local open = openZones[mapID] == true
	local inside = {}
	local searched = SearchOpens("z" .. mapID)
	if open or (filter ~= "" and not asLeft) then
		for city, around in pairs(CITY_IN) do
			if around == mapID and Index().zones[city] then
				for _, row in ipairs(ZoneRows(city, nest + 1, whole)) do table.insert(inside, row) end
			end
		end
		for _, row in ipairs(DungeonRows(mapID, nest + 1, whole)) do table.insert(inside, row) end
		KindCards(Index().zones[mapID] or {}, nest + 1, inside,
			function(type) return { kind = "group", which = type, mapID = mapID } end,
			function(type) return zoneTypeOpen[mapID .. ":" .. type] end, whole)
	end
	if filter ~= "" and #inside == 0 and not whole then return {} end
	-- Closed with a click during this search: the card alone.
	local shown
	if filter ~= "" and not asLeft then shown = searched else shown = open end
	return Holding(Card({ kind = "zone", mapID = mapID, label = MapName(mapID), nest = nest,
		open = shown and #inside > 0, closeKey = "z" .. mapID }, found, total), inside, shown)
end

-- A group's readables (the seasonal events', those found across Azeroth or those of no known
-- origin): a banner of their own after the zones', holding a line for each kind of writing.
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
		local whole = Named(label)
		AsLeft(whole, function()
			KindCards(byType, 0, inside,
				function(type) return { kind = "kind", which = type, group = key } end,
				function(type) return groupTypeOpen[key .. ":" .. type] end, whole)
		end)
	end
	if filter ~= "" and #inside == 0 then return {} end
	local rows = { { style = "banner", kind = "group", which = key, label = label, count = found, total = total,
		open = #inside > 0 } }
	for _, row in ipairs(inside) do table.insert(rows, row) end
	return rows
end

-- By Zone off: a banner for each kind of writing, every one of it under it.
local function TypeRows()
	local out = {}
	for _, type in ipairs(TYPES) do
		local ids = Index().types[type] or {}
		if #ids > 0 then
			local set = {}
			for _, id in ipairs(ids) do set[id] = true end
			local found, total = Tally(set)
			local leaves = {}
			if typeOpen[type] or filter ~= "" then Leaves(ids, 0, leaves, Named(TypeLabel(type))) end
			if not (OnlyFound() and found == 0) and Listed(set) and (filter == "" or #leaves > 0) then
				-- A kind of writing is a type: a banner, as the continents are By Zone. Closed with a
				-- click during this search: the banner alone.
				local shown = filter == "" or SearchOpens("t" .. type)
				table.insert(out, { style = "banner", kind = "type", which = type, label = TypeLabel(type),
					count = found, total = total, open = shown and #leaves > 0, closeKey = "t" .. type })
				if shown then
					for _, row in ipairs(leaves) do table.insert(out, row) end
				end
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
		local whole = Named(L[ZONES_LABEL[key]])
		AsLeft(whole, function()
			for _, mapID in ipairs(zones) do
				for _, row in ipairs(ZoneRows(mapID, 0, whole)) do table.insert(inside, row) end
			end
		end)
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
				local whole = Named(MapName(continent))
				AsLeft(whole, function()
					for _, mapID in ipairs(zones) do
						for _, row in ipairs(ZoneRows(mapID, 0, whole)) do table.insert(rows, row) end
					end
				end)
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
		return selection.group == row.which and selection.mapID == row.mapID and selection.dungeon == row.dungeon
			and not selection.type
	end
	if row.kind == "type" then return selection.type == row.which and not selection.group end
	if row.kind == "dungeons" then return selection.dungeons == true and selection.mapID == row.mapID end
	if row.kind == "dungeon" then
		return selection.dungeon == row.dungeon and selection.mapID == row.mapID and not selection.group
	end
	return selection.mapID == row.mapID and not selection.book and not selection.group and not selection.dungeon
		and not selection.dungeons
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

-- Play on a readable's page: the book from its first voiced page, and Stop and Replay while it is
-- read (SpokenCompendium.PlayState).
local PLAY = {
	has = function(id) return Voiced(id) end,
	-- The book's page nearest the head of the queue: read as one line, its one page there; page by
	-- page, the first of its pages still to read.
	find = function(id)
		if not (_G.Spoken and Spoken.GetQueue) then return nil end
		for _, clip in ipairs(Spoken:GetQueue()) do
			if clip.pageId and SpokenBooks:PlaceOf(clip.pageId) == id then return clip end
		end
	end,
	-- Browsing: heard here is not heard in the world (Read Only Once), nor found.
	start = function(id) SpokenBooks:SyncTo(FirstVoiced(id), true) end,
	tip = L.PLAY_TIP,
}

-- The page of a readable being read: the one of it in the queue. Nil where none is.
local function PageReading(id)
	local entry = SpokenBooks.following[id]
	if entry and entry.clip and entry.clip.pageId then return entry.clip.pageId end
	-- Read Book as One Line off: each page is a line of its own, the first in the queue the one read.
	if _G.Spoken and Spoken.GetQueue then
		for _, clip in ipairs(Spoken:GetQueue()) do
			if clip.pageId and SpokenBooks:PlaceOf(clip.pageId) == id then return clip.pageId end
		end
	end
end

-- Report on a readable's page: the page being read, else its first voiced page, filed under the
-- language it plays in, as the player's Report files a page.
local REPORT = {
	has = function(id) return PLAY.has(id) end,
	open = function(id)
		local pageId = PageReading(id) or FirstVoiced(id)
		local clip = pageId and SpokenBooks:ClipFor(pageId)
		local url = pageId and SpokenBooks:ReportURL(pageId, clip and clip.language)
		if url and SpokenBooks.ShowCopyLink then SpokenBooks:ShowCopyLink(url, L.REPORT_LINE_ADDRESS) end
	end,
	title = L.REPORT_PROBLEM,
	tip = L.REPORT_LINE_TIP,
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

-- Where a readable is, under its title: its first two zones, and how many more. One line: a book
-- shelved in seven zones would be cut short mid-name.
local function InZones(zones)
	local names = {}
	for i = 1, math.min(2, #zones) do table.insert(names, MapName(zones[i])) end
	local line = L.READABLES_IN_FMT:format(table.concat(names, ", "))
	if #zones > 2 then line = line .. L.READABLES_MORE_FMT:format(#zones - 2) end
	return line
end

-- How a readable is had, at the top of its page: each source, with the zone it is in.
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

-- A place's page line: the place that holds it and what it counts, one line.
local function InAndCount(where, found, total)
	return L.READABLES_IN_FMT:format(where) .. " · " .. Count(found, total)
end

-- The place one level up from a zone, as the Zones tab nests them: a city's zone, a zone's
-- continent, and the world for a continent or a zone on none.
local function Above(mapID)
	for _, continent in ipairs(CONTINENTS) do
		if continent == mapID then return C.WORLD end
	end
	return CITY_IN[mapID] or ContinentOf(mapID) or C.WORLD
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
		elseif place.zones and #place.zones > 0 then
			where = InZones(place.zones)
		else
			where = L.GROUP_UNKNOWN
		end
		if not Found(id) and not Unlocked() then
			page:Show({ title = Name(id), subtitle = where, text = L.READABLE_NOT_FOUND })
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
		page:Show({ title = Name(id), subtitle = where, text = table.concat(parts, "\n\n"), target = id })
		return
	end
	-- A zone, a continent, a group, a type: where it is and what it holds. A kind of writing across
	-- every place (By Type) and the groups after the zones are no place: their count alone.
	local set = {}
	if selection.type and not selection.group then
		for _, id in ipairs(Index().types[selection.type] or {}) do set[id] = true end
		page:Show({ title = TypeLabel(selection.type), subtitle = Count(Tally(set)), text = L.READABLES_PICK })
		return
	end
	if selection.group and selection.mapID and TYPE_NAMES[selection.group] then
		local byType, where = Index().zones[selection.mapID], MapName(selection.mapID)
		if selection.dungeon then
			byType, where = (Index().dungeons[selection.mapID] or {})[selection.dungeon], DungeonName(selection.dungeon)
		end
		for _, id in ipairs((byType or {})[selection.group] or {}) do set[id] = true end
		page:Show({ title = TypeLabel(selection.group), subtitle = InAndCount(where, Tally(set)), text = L.READABLES_PICK })
		return
	end
	if selection.dungeon then
		DungeonReadables(selection.mapID, selection.dungeon, set)
		page:Show({ title = DungeonName(selection.dungeon), subtitle = InAndCount(MapName(selection.mapID), Tally(set)),
			text = L.READABLES_PICK })
		return
	end
	if selection.dungeons then
		for map in pairs(Index().dungeons[selection.mapID] or {}) do DungeonReadables(selection.mapID, map, set) end
		page:Show({ title = L.GROUP_DUNGEONS, subtitle = InAndCount(MapName(selection.mapID), Tally(set)),
			text = L.READABLES_PICK })
		return
	end
	if selection.type and selection.group then
		-- A group is no place: its name, not "In" it.
		for _, id in ipairs(Index()[selection.group]) do
			if Index().typeOf[id] == selection.type then set[id] = true end
		end
		page:Show({ title = TypeLabel(selection.type),
			subtitle = L[GROUP_LABEL[selection.group]] .. " · " .. Count(Tally(set)), text = L.READABLES_PICK })
		return
	end
	if selection.zones then
		for _, mapID in ipairs(ZONES_OF[selection.zones]()) do ReadablesIn(mapID, set) end
		page:Show({ title = L[ZONES_LABEL[selection.zones]], subtitle = InAndCount(MapName(C.WORLD), Tally(set)),
			text = L.READABLES_PICK })
		return
	end
	if GROUP_LABEL[selection.group] then
		for _, id in ipairs(Index()[selection.group]) do set[id] = true end
		page:Show({ title = L[GROUP_LABEL[selection.group]], subtitle = Count(Tally(set)), text = L.READABLES_PICK })
		return
	end
	if selection.mapID == 1414 or selection.mapID == 1415 then
		for _, mapID in ipairs(ZonesOn(selection.mapID)) do ReadablesIn(mapID, set) end
	else
		ReadablesIn(selection.mapID, set)
	end
	page:Show({ title = MapName(selection.mapID), subtitle = InAndCount(MapName(Above(selection.mapID)), Tally(set)),
		text = L.READABLES_PICK })
end

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

-- The continents with readables, by name, as the list has them.
local function Continents()
	local out = {}
	for _, continent in ipairs(CONTINENTS) do
		if #ZonesOn(continent) > 0 then table.insert(out, continent) end
	end
	table.sort(out, ByName)
	return out
end

-- The zone the player stands in that has a card, walking up from an inn's or a cave's map, or nil.
local function PlayerZone()
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local steps = 0
	while map and steps < 8 do
		if next(ReadablesIn(map)) then return map end
		local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
		map, steps = info and info.parentMapID, steps + 1
	end
end

-- Whether the list shows what holds `set` ({ [id] = true }): Found Only leaves out one with
-- nothing found, Voiced Only one with nothing voiced.
local function SetShown(set)
	return not (OnlyFound() and Tally(set) == 0) and Listed(set)
end

-- The continent the player is on where the list shows it, else the first it shows.
local function PlayerContinent()
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local listed = {}
	for _, continent in ipairs(Continents()) do
		local set = {}
		for _, mapID in ipairs(ZonesOn(continent)) do ReadablesIn(mapID, set) end
		if SetShown(set) then table.insert(listed, continent) end
	end
	for _, continent in ipairs(listed) do
		if map == continent or (map and ContinentOf(map) == continent) then return continent end
	end
	return listed[1]
end

-- The dungeon or raid the player is in, where it has readables: its map, and the zone of its
-- entrance.
local function PlayerDungeon()
	if not GetInstanceInfo then return nil end
	local map = NotSecret((select(8, GetInstanceInfo())))
	local dungeon = map and Dungeons()[map]
	if dungeon and next(DungeonReadables(dungeon.zone, map)) then return map, dungeon.zone end
end

-- By Type: the first kind the list shows holding one of `here` ({ [id] = true }), else the first it
-- shows.
local function PlayerKind(here)
	local first
	for _, type in ipairs(TYPES) do
		local set, holds = {}, false
		for _, id in ipairs(Index().types[type] or {}) do
			set[id] = true
			if here[id] then holds = true end
		end
		if next(set) and SetShown(set) then
			if holds then return type end
			first = first or type
		end
	end
	return first
end

-- Open what holds a zone's card: Battlegrounds' banner, its continent's, or Other Lands'.
local function OpenAround(zone)
	if IS_BATTLEGROUND[zone] then
		zonesOpen.battlegrounds = true
		return
	end
	local continent = ContinentOf(CITY_IN[zone] or zone)
	if continent then
		continentOpen[continent] = true
	else
		zonesOpen.lands = true
	end
end

-- Open a zone's card and, for a city, the zone's around it, leaving the others as they are.
local function OpenZone(zone)
	openZones[zone] = true
	if CITY_IN[zone] then openZones[CITY_IN[zone]] = true end
end

-- Choose where the player stands: the dungeon's card they are in, opened, else their zone's, else
-- their continent's banner; By Type, the kind of writing the dungeon or zone holds. Never what the
-- list does not show: the tab would show a page for no row. The tab never shows a page with nothing
-- chosen.
local function LandOnPlayer()
	local zone = PlayerZone()
	local dungeon, entrance = PlayerDungeon()
	if not ByZone() then
		local here = dungeon and DungeonReadables(entrance, dungeon) or zone and ReadablesIn(zone) or {}
		local kind = PlayerKind(here)
		selection = kind and { type = kind } or nil
	elseif dungeon and SetShown(DungeonReadables(entrance, dungeon)) then
		selection = { mapID = entrance, dungeon = dungeon }
		dungeonsOpen[entrance] = true
		dungeonOpen[entrance .. ":" .. dungeon] = true
		OpenZone(entrance)
		OpenAround(entrance)
	elseif zone and SetShown(ReadablesIn(zone)) then
		selection = { mapID = zone }
		OpenZone(zone)
		OpenAround(zone)
	else
		local continent = PlayerContinent()
		selection = continent and { mapID = continent } or nil
	end
	landed = selection
end

local function OnClick(row)
	local folded = SearchFold(row)
	if row.kind == "readable" then
		selection = { book = row.book }
	elseif row.kind == "zones" then
		if filter == "" then zonesOpen[row.key] = not zonesOpen[row.key] end
		selection = { zones = row.key }
	elseif row.kind == "type" then
		if filter == "" and not folded then typeOpen[row.which] = not typeOpen[row.which] end
		selection = { type = row.which }
	elseif row.kind == "kind" then
		-- A group's Books, Notes and the rest: opened and closed again, as a zone's are.
		local key = row.group .. ":" .. row.which
		if not folded and (filter == "" or row.asLeft) then groupTypeOpen[key] = not groupTypeOpen[key] or nil end
		selection = { group = row.group, type = row.which }
	elseif row.kind == "dungeons" or row.kind == "dungeon" then
		-- A zone's Dungeons and Raids line, or a dungeon's card: opened and closed again, as a zone's.
		if not folded and (filter == "" or row.asLeft) then
			if row.kind == "dungeons" then
				dungeonsOpen[row.mapID] = not dungeonsOpen[row.mapID] or nil
			else
				local key = row.mapID .. ":" .. row.dungeon
				dungeonOpen[key] = not dungeonOpen[key] or nil
			end
		end
		selection = { mapID = row.mapID, dungeons = row.kind == "dungeons" or nil, dungeon = row.dungeon }
	elseif filter ~= "" and not row.asLeft then
		selection = { mapID = row.mapID, group = row.kind == "group" and row.which or nil, dungeon = row.dungeon }
	elseif row.kind == "continent" then
		continentOpen[row.mapID] = not continentOpen[row.mapID]
		selection = { mapID = row.mapID }
	elseif row.kind == "zone" then
		-- A zone's or city's card opens and closes alone.
		openZones[row.mapID] = not openZones[row.mapID] or nil
		selection = { mapID = row.mapID }
	elseif row.kind == "group" and not row.mapID then
		groupOpen[row.which] = not groupOpen[row.which]
		selection = { group = row.which }
	else
		-- A zone's or a dungeon's Books, Notes and the rest: opened and closed again, as the zone is.
		local key = row.mapID .. ":" .. (row.dungeon and (row.dungeon .. ":") or "") .. row.which
		zoneTypeOpen[key] = not zoneTypeOpen[key] or nil
		selection = { mapID = row.mapID, group = row.which, dungeon = row.dungeon }
	end
	SpokenBooks:RefreshReadables()
end

-- The chosen row brought into view. The client's scroll frame takes an offset only within the
-- range it last measured, and a list drawn for the first time has none measured yet; nor has the
-- frame a height until the window is first laid out. Either left the list at its top, the chosen
-- zone off screen: the range is measured now, and the row brought into view again a frame later.
local function ScrollToChosen(items)
	if list.scroll.UpdateScrollChildRect then list.scroll:UpdateScrollChildRect() end
	list:ScrollToSelection(items)
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			if filter == "" and list.items then list:ScrollToSelection(list.items) end
		end)
	end
end

function SpokenBooks:RefreshReadables(scrollToSelection)
	if not list then return end
	if not selection then
		LandOnPlayer()
		scrollToSelection = true
	end
	local items = list:Render()
	if scrollToSelection and selection then ScrollToChosen(items) end
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
			searchClosed = {}
			SpokenBooks:RefreshReadables()
		end,
		addScrollBar = function(scroll, child, inset) return SpokenTextView.AddScrollBar(scroll, child, inset) end,
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
	page = C.NewPage(holder, SpokenBooks, PLAY, REPORT)
	-- Text Size, on Spoken's page, fires no game event: the page is drawn again at the new size.
	if Spoken and Spoken.RegisterCallback then Spoken:RegisterCallback("COMPENDIUM_FONT_CHANGED", ShowEntry) end
	if type(pageInset.NineSlice) == "table" and pageInset.NineSlice.SetFrameLevel then
		pageInset.NineSlice:SetFrameLevel(holder:GetFrameLevel() + 5)
	end
	panel.page = page
	SpokenBooks.readables = panel
end

--- Open the readables.
function SpokenBooks:ShowReadables()
	if not SpokenCompendium then return end
	-- On where the player stands now, unless they chose something here.
	if selection == landed then selection = nil end
	if list then
		list:ClearSearch()
		filter = ""
	end
	SpokenCompendium:Open("readables")
	SpokenCompendium:Expand()
	SpokenBooks:RefreshReadables(true)
end

function SpokenBooks:SetupReadables()
	if not SpokenCompendium or SpokenCompendium:Tab("readables") then return end
	SpokenCompendium:Register("readables", {
		label = L.COMPENDIUM_READABLES,
		order = 2,
		build = Build,
		open = function() SpokenBooks:ShowReadables() end,
		-- Come back to from another tab: where the player stands now, unless they chose here.
		onShow = function() if selection == landed then selection = nil end end,
		enabled = function() return SpokenBooks:IsPartOn() end,
		-- Unlock Unfound Readables, on Spoken's page.
		unlock = {
			get = function() return SpokenBooksSettings ~= nil and SpokenBooksSettings.unlockUnfound == true end,
			set = function(value)
				if SpokenBooksSettings then SpokenBooksSettings.unlockUnfound = value end
				SpokenBooks:RefreshReadables()
			end,
		},
	})
end
