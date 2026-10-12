-- SpokenZones -- the places in Azeroth's Compendium (UI/Compendium.lua): every place's story, to
-- browse and listen to anywhere.
--
-- Opened from the minimap menu, the Zones settings page or /spz window. Independent of
-- WorldMapFrame, so it works with the map closed.
--
-- The window, its list and its rows are the Compendium's; this is what goes in them. On the left,
-- a banner for each continent, a card under it for each of its zones (how many of its places are
-- found, with a bar), and an opened zone's areas as rows, its city a small card among them with
-- its own areas; after the continents, a banner for the zones on none (Other Lands) and one for
-- the battlegrounds. On the right, the story on the spellbook's parchment (UI/LorePage.lua).
--
-- Each zone's and city's card opens and closes on its own click, and stays as the player left it
-- for the session. A zone's areas are rows only while its card is open, so the list holds what
-- the player opened. A search opens every card with a match in it instead: one naming a zone or
-- a city lists all its areas, and one naming a banner lists its cards as the player left them.

local ADDON_NAME, SpokenZones = ...

local L = SpokenZones.L

local panel, list, page
-- The zones' and cities' cards open, by mapID: a city's keeps its state while its zone is closed.
local openZones = {}
-- The continents start open, so the zones show; each opens and closes on its own.
local continentOpen = { [1414] = true, [1415] = true }
-- Whether the banners after the continents are open: the zones on no continent, the battlegrounds.
local groupOpen = { lands = false, battlegrounds = false }
local selection = nil -- { mapID = , key = nil|string }, or { group = "lands"|"battlegrounds" }
-- The selection made for the player, where they stood; any other is one they chose.
local landed = nil
-- Sorted once, as sortedZoneIDs is: the tree is rebuilt on every click and keystroke, and the
-- data under it is fixed for the session (a language change reloads the interface).
local sortedZoneIDs = nil
local zonesOfContinent = {}
local sortedSubzoneKeys = {}
local filter = ""   -- what the list's search box holds, lowered (UI/Compendium.lua's List)

--------------------------------------------------------------------------------
-- Data ordering
--------------------------------------------------------------------------------

local function ZoneName(mapID)
	return SpokenZones:GetMapName(mapID) or (SpokenZones.Zones[mapID] and SpokenZones.Zones[mapID].name) or tostring(mapID)
end

-- The world, its continents, the cities inside the zone around each, and which continent a zone is
-- on: Compendium.lua's, which every tab lays its tree out by.
local WORLD, CONTINENTS, CITY_IN = SpokenCompendium.WORLD, SpokenCompendium.CONTINENTS, SpokenCompendium.CITY_IN
local ContinentOf = SpokenCompendium.ContinentOf
SpokenZones.CityIn = CITY_IN

local function IsContinent(mapID)
	return mapID == 1414 or mapID == 1415
end

-- Under a banner of their own, as the Quests tab lists them, wherever the client hangs their maps.
local BATTLEGROUNDS = { 1459, 1460, 1461, 2524 } -- Alterac Valley, Warsong Gulch, Arathi Basin, Darkspear Islands
local IS_BATTLEGROUND = {}
for _, mapID in ipairs(BATTLEGROUNDS) do IS_BATTLEGROUND[mapID] = true end

local function ByName(a, b)
	local na, nb = ZoneName(a), ZoneName(b)
	if na == nb then return a < b end
	return na < nb
end

-- A map this client has never heard of: in the data for another client (Forever's 2482, 2521,
-- 2524, 2548 and 2652 on Era), it would sit loose under Azeroth, counted among its zones, and
-- lead nowhere. Only where C_Map can be asked, and only for a zone on no continent we know.
local function UnknownHere(mapID)
	if not (C_Map and C_Map.GetMapInfo) or ContinentOf(mapID) then return false end
	return C_Map.GetMapInfo(mapID) == nil
end

--- Every zone with a story, alphabetical: everything in the data but Azeroth, its continents and
--- maps this client has not got.
local function ZoneIDs()
	if sortedZoneIDs then
		return sortedZoneIDs
	end
	sortedZoneIDs = {}
	for mapID in pairs(SpokenZones.Zones) do
		if mapID ~= WORLD and not IsContinent(mapID) and not UnknownHere(mapID) then
			table.insert(sortedZoneIDs, mapID)
		end
	end
	-- Alphabetical by display name: uiMapID order is meaningless to a reader.
	table.sort(sortedZoneIDs, ByName)
	return sortedZoneIDs
end

--- The continents that have a story, alphabetical.
local function Continents()
	local list = {}
	for _, mapID in ipairs(CONTINENTS) do
		if SpokenZones.Zones[mapID] then table.insert(list, mapID) end
	end
	table.sort(list, ByName)
	return list
end

--- A continent's zones, alphabetical, its battlegrounds left to their banner.
local function ZonesOf(continent)
	if zonesOfContinent[continent] then return zonesOfContinent[continent] end
	local list = {}
	for _, mapID in ipairs(ZoneIDs()) do
		if ContinentOf(mapID) == continent and not CITY_IN[mapID] and not IS_BATTLEGROUND[mapID] then
			table.insert(list, mapID)
		end
	end
	zonesOfContinent[continent] = list
	return list
end

--- The zones on neither continent with a story, alphabetical (Forever's Zephras Isle).
local function LooseZones()
	local listed = {}
	for _, continent in ipairs(Continents()) do listed[continent] = true end
	local list = {}
	for _, mapID in ipairs(ZoneIDs()) do
		if not listed[ContinentOf(mapID) or 0] and not CITY_IN[mapID] and not IS_BATTLEGROUND[mapID] then
			table.insert(list, mapID)
		end
	end
	return list
end

--- The battlegrounds with a story on this client, alphabetical.
local function Battlegrounds()
	local list = {}
	for _, mapID in ipairs(ZoneIDs()) do
		if IS_BATTLEGROUND[mapID] then table.insert(list, mapID) end
	end
	return list
end

-- The banners after the continents, in order: what each holds and is called.
local GROUPS = {
	{ key = "lands", zones = LooseZones, label = function() return L.OTHER_LANDS end },
	{ key = "battlegrounds", zones = Battlegrounds, label = function() return L.BATTLEGROUNDS end },
}
local function Group(key)
	for _, group in ipairs(GROUPS) do
		if group.key == key then return group end
	end
end

--- The cities inside the zone `mapID`, alphabetical.
local function CitiesIn(mapID)
	local list = {}
	for _, city in ipairs(ZoneIDs()) do
		if CITY_IN[city] == mapID then table.insert(list, city) end
	end
	return list
end

--- Open what holds `mapID`, so opening on a place shows it.
local function Reveal(mapID)
	if IS_BATTLEGROUND[mapID] then
		groupOpen.battlegrounds = true
		return
	end
	local continent = IsContinent(mapID) and mapID or ContinentOf(mapID)
	if continent then
		continentOpen[continent] = true
	elseif mapID ~= WORLD then
		groupOpen.lands = true
	end
end

--- Open the card of `mapID` and, for a city, the zone's around it, leaving the others as they are.
local function OpenZone(mapID)
	openZones[mapID] = true
	if CITY_IN[mapID] then openZones[CITY_IN[mapID]] = true end
end

-- Whether this is the Forever client, which knows its own maps (Mount Hyjal's, 2482).
local onForever
local function OnForever()
	if onForever == nil then
		onForever = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(2482) ~= nil or false
	end
	return onForever
end

local function SubzoneKeys(mapID)
	local tbl = SpokenZones.Subzones[mapID]
	if not tbl then
		return nil
	end
	if sortedSubzoneKeys[mapID] then return sortedSubzoneKeys[mapID] end
	-- Not the areas only Forever has (Data/ForeverAreas.lua) on another client, which can never
	-- report them: listed, they would never be found.
	local foreverOnly = not OnForever() and SpokenZones.ForeverOnlyAreas and SpokenZones.ForeverOnlyAreas[mapID] or {}
	local keys = {}
	for key in pairs(tbl) do
		if not foreverOnly[key] then table.insert(keys, key) end
	end
	table.sort(keys, function(a, b)
		return (tbl[a].name or a) < (tbl[b].name or b)
	end)
	sortedSubzoneKeys[mapID] = keys
	return keys
end

local function Matches(text)
	return filter == "" or (text and string.find(string.lower(text), filter, 1, true) ~= nil)
end

-- Whether a search names what holds `label`: then all it holds is listed, each area matching or not.
local function Named(label, whole)
	return whole or (filter ~= "" and Matches(label))
end

-- Set while the cards under a banner whose name the search matches are built: each is listed,
-- closed or open as the player left it, and opens and closes on a click as it does unsearched. A
-- continent's every area at once would be too long a list to read.
local asLeft = false

-- What a search opened and the player closed again with a click, by card; a new search opens all.
local searchClosed = {}

-- The rows `build` returns, built with asLeft set where `named`.
local function AsLeft(named, build)
	local before = asLeft
	asLeft = before or named
	local rows = build()
	asLeft = before
	return rows
end

local function SetFilter(text)
	filter = text
	searchClosed = {}
end

-- Whether this character has found a place (Discovery.lua), whatever Unlock Undiscovered Zones
-- says: the counts and Discovered Only go by it.
local function Found(mapID, key)
	return SpokenZones:IsFound(mapID, key)
end

-- Whether a place can be opened: every place with Unlock Undiscovered Zones on, otherwise only
-- those found. The rest are listed greyed out.
local function Discovered(mapID, key)
	return SpokenZones:ShowsUndiscovered() or Found(mapID, key)
end

--- Whether a place is locked for this character: not found yet, with Unlock Undiscovered Zones
--- off. A continent is found through its zones; Azeroth always is. The page and the map's panel
--- say so in its place rather than tell its story.
function SpokenZones:IsLocked(mapID, key)
	if self:ShowsUndiscovered() or mapID == WORLD then return false end
	if not key and IsContinent(mapID) then
		for _, zone in ipairs(ZonesOf(mapID)) do
			if self:IsFound(zone) then return false end
		end
		return true
	end
	return not self:IsFound(mapID, key)
end

-- Discovered Only, in the filter menu: the places not found are left out of the list.
local function OnlyFound()
	return SpokenZones:Get("loreDiscoveredOnly") == true
end

-- Voiced Only, under it: the places no installed voice pack reads are left out. A zone stays while
-- it, an area in it or its city has a recording, so a voiced area is still reached through it.
local function OnlyVoiced()
	return SpokenZones:Get("loreVoicedOnly") == true
end

local function Voiced(mapID, key)
	return SpokenZones.HasAudio ~= nil and SpokenZones:HasAudio(mapID, key) and true or false
end

local function AnyVoiced(mapID)
	if Voiced(mapID) then return true end
	for _, key in ipairs(SubzoneKeys(mapID) or {}) do
		if Voiced(mapID, key) then return true end
	end
	for _, city in ipairs(CitiesIn(mapID)) do
		if AnyVoiced(city) then return true end
	end
	return false
end

local function Missing(mapID)
	local entry = SpokenZones:GetLore(mapID)
	return not entry or SpokenZones:IsPending(entry)
end

-- What a zone holds, found out of all: its areas, and its city as one place more with the city's
-- own areas. Of what is listed: under Voiced Only, what no voice pack reads is left out of the
-- count as it is of the rows, so the card's number is of the rows beneath it. Its page counts the
-- same.
local function Places(mapID)
	local found, total = 0, 0
	for _, city in ipairs(CitiesIn(mapID)) do
		if not OnlyVoiced() or AnyVoiced(city) then
			local f, t = Places(city)
			found, total = found + f, total + t + 1
			if Found(city) then found = found + 1 end
		end
	end
	for _, key in ipairs(SubzoneKeys(mapID) or {}) do
		if not OnlyVoiced() or Voiced(mapID, key) then
			total = total + 1
			if Found(mapID, key) then found = found + 1 end
		end
	end
	return found, total
end

-- One zone's card, and under it when it is open its city's small card (a zone of its own, with
-- its own areas) and its areas' rows. A search opens every card with a match inside and lists the
-- areas that match, or all of them where it names the zone or a card around it (`whole`); a card
-- it opened closes and opens again on a click. Nothing when neither the zone nor anything inside
-- matches the search. A city's card opens on its own, and shows only while its zone is open. A
-- zone not yet discovered is listed locked: greyed out, and it does not open, to a search either,
-- so a search lists nothing that browsing could not reach.
local function ZoneRows(mapID, nest, whole, small)
	if OnlyFound() and not Found(mapID) then return {} end
	if OnlyVoiced() and not AnyVoiced(mapID) then return {} end
	local locked = not Discovered(mapID)
	local subKeys = SubzoneKeys(mapID)
	local zoneName = ZoneName(mapID)
	whole = Named(zoneName, whole)
	local searched = filter ~= "" and not asLeft
	local closeKey = "z" .. mapID
	local open = openZones[mapID] == true and not locked
	local inside = {}
	local found, total = Places(mapID)
	if not locked and (open or searched) then
		for _, city in ipairs(CitiesIn(mapID)) do
			for _, row in ipairs(ZoneRows(city, nest + 1, whole, true)) do table.insert(inside, row) end
		end
		for _, key in ipairs(subKeys or {}) do
			local isFound = Found(mapID, key)
			local entry = SpokenZones.Subzones[mapID][key]
			local name = entry.name or key
			if (filter == "" or whole or Matches(name)) and (isFound or not OnlyFound())
				and (not OnlyVoiced() or Voiced(mapID, key)) then
				table.insert(inside, { kind = "subzone", leaf = true, mapID = mapID, key = key, label = name,
					nest = nest + 1, missing = SpokenZones:IsPending(entry), locked = not Discovered(mapID, key),
					done = isFound and true or false })
			end
		end
	end
	if filter ~= "" and not whole and #inside == 0 then return {} end
	-- Closed with a click during this search: the card alone.
	local shown
	if searched then shown = not locked and not searchClosed[closeKey] else shown = open end
	-- With no areas of its own (Thunder Bluff), nothing to count: no line, share or bar.
	local icon, iconCrop
	if Spoken and Spoken.ZoneIcon then icon, iconCrop = Spoken:ZoneIcon(mapID) end
	local rows = { { style = "card", small = small, kind = "zone", mapID = mapID, label = zoneName, nest = nest,
		count = found, total = total, icon = icon, iconCrop = iconCrop,
		ratio = total > 0 and found / total or 0, tick = total > 0 and found == total,
		none = found == 0 and not Found(mapID),
		open = searched and shown and #inside > 0 or not searched and shown,
		closeKey = closeKey, asLeft = asLeft,
		missing = Missing(mapID), locked = locked } }
	if shown then
		for _, row in ipairs(inside) do table.insert(rows, row) end
	end
	return rows
end

-- What a banner counts: the places its zones' cards count, found out of all, of the cards Discovered
-- Only and Voiced Only list. Also how many cards it lists, and whether any of its zones is found,
-- listed or not, which unlocks it.
local function BannerCount(zones)
	local found, total, listed, anyFound = 0, 0, 0, false
	for _, mapID in ipairs(zones) do
		local isFound = Found(mapID)
		anyFound = anyFound or isFound
		if not (OnlyFound() and not isFound) and not (OnlyVoiced() and not AnyVoiced(mapID)) then
			local f, t = Places(mapID)
			found, total, listed = found + f, total + t, listed + 1
		end
	end
	return found, total, listed, anyFound
end

-- The list: a banner for each continent, its zones' cards under it, and the opened zones'
-- areas. While searching, every match a click could reach, with what holds it opened to show it.
local function BuildRowList()
	local list = {}
	local function Add(rows) for _, row in ipairs(rows) do table.insert(list, row) end end
	local searching = filter ~= ""

	for _, continent in ipairs(Continents()) do
		local name = ZoneName(continent)
		local found, total, listed, anyFound = BannerCount(ZonesOf(continent))
		-- A continent with none of its zones found yet is listed locked, and does not open; with
		-- Discovered Only it is left out. Found through its zones alone: finding Brill finds the
		-- Eastern Kingdoms.
		local unfound = not anyFound
		local locked = unfound and not SpokenZones:ShowsUndiscovered()
		-- A closed continent's zones are never shown, and its count comes from ZonesOf: only a
		-- search, which can open it, needs them built. A locked one opens to a search no more
		-- than to a click. Named by the search, its every zone's card is listed as the player left it.
		local zones = {}
		local named = searching and Matches(name)
		if not locked and (searching or continentOpen[continent]) then
			AsLeft(named, function()
				for _, mapID in ipairs(ZonesOf(continent)) do
					for _, row in ipairs(ZoneRows(mapID, 0, named)) do table.insert(zones, row) end
				end
			end)
		end
		local voiced = not OnlyVoiced() or listed > 0
		if (not searching or Matches(name) or #zones > 0) and not (unfound and OnlyFound()) and voiced then
			local open = searching and #zones > 0 or (not searching and continentOpen[continent] and not locked)
			table.insert(list, { style = "banner", kind = "continent", mapID = continent, label = name,
				count = found, total = total, open = open and true or false, missing = Missing(continent),
				locked = locked })
			if open then Add(zones) end
		end
	end
	-- Zones on neither continent with a story, then the battlegrounds, each under a banner of
	-- their own after them, counted and locked as a continent is.
	for _, group in ipairs(GROUPS) do
		local members = group.zones()
		local label = group.label()
		local found, total, listed, anyFound = BannerCount(members)
		local locked = not anyFound and not SpokenZones:ShowsUndiscovered()
		local zones = {}
		local named = searching and Matches(label)
		if not locked and (searching or groupOpen[group.key]) then
			AsLeft(named, function()
				for _, mapID in ipairs(members) do
					for _, row in ipairs(ZoneRows(mapID, 0, named)) do table.insert(zones, row) end
				end
			end)
		end
		local voiced = not OnlyVoiced() or listed > 0
		if #members > 0 and (not searching or Matches(label) or #zones > 0) and not (not anyFound and OnlyFound())
			and voiced then
			local open = searching and #zones > 0 or (not searching and groupOpen[group.key] and not locked)
			table.insert(list, { style = "banner", kind = "group", group = group.key, label = label, count = found,
				total = total, open = open and true or false, locked = locked })
			if open then Add(zones) end
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

-- The zone the player is standing in, resolved to something we actually have lore for.
-- C_Map.GetBestMapForUnit can return an indoor or micro map (an inn, a dungeon) that is not
-- itself a key in Zones, so walk up to its parent.
local function CurrentZoneID()
	local playerMap = SpokenZones:GetPlayerMapID()
	if not playerMap then
		return nil
	end
	local _, resolved = SpokenZones:GetLoreWithFallback(playerMap)
	return resolved
end

-- The continent the player is on, else the first: where the tab lands when no zone of theirs has
-- a story. Azeroth's own page is never chosen from the list.
local function PlayerContinent()
	local map = SpokenZones:GetPlayerMapID()
	local continent = map and (IsContinent(map) and map or ContinentOf(map))
	if continent and SpokenZones.Zones[continent] then return continent end
	return Continents()[1]
end

-- Choose where the player stands: the area they are in where it has a story of its own, else its
-- zone, opened; their continent where neither resolves. The tab never shows a page with nothing
-- chosen.
local function LandOnPlayer()
	local current = CurrentZoneID()
	if not current or current == WORLD or IsContinent(current) then
		local continent = current and IsContinent(current) and current or PlayerContinent()
		if continent then Reveal(continent) end
		selection = { mapID = continent or WORLD, key = nil }
		landed = selection
		return
	end
	local subZone = GetSubZoneText()
	local subEntry, subKey
	if subZone and subZone ~= "" then
		subEntry, subKey = SpokenZones:GetSubzoneLore(current, subZone)
	end
	OpenZone(current)
	Reveal(current)
	selection = { mapID = current, key = subEntry and subKey or nil }
	landed = selection
end

-- Where a place sits, and what its card or banner counts found out of all, as "1 of 7
-- discovered"; no count where there is nothing to count.
local function InAndCount(where, found, total)
	local line = string.format(L.IN_ZONE_FMT, ZoneName(where))
	if total > 0 then line = line .. " · " .. string.format(L.DISCOVERED_FMT, found, total) end
	return line
end

local function ShowEntry()
	if selection.group then
		-- In Azeroth, as a continent is, a click away.
		local group = Group(selection.group)
		local found, total = BannerCount(group.zones())
		page:Show({ title = group.label(), subtitle = InAndCount(WORLD, found, total),
			onSubtitle = function()
				selection = { mapID = WORLD, key = nil }
				SpokenZones:RefreshLoreWindow()
			end,
			text = L.ZONES_PICK })
		return
	end
	local mapID, key = selection.mapID, selection.key
	-- Chosen from elsewhere (the map's panel), a place not found yet: named, and no more.
	if SpokenZones:IsLocked(mapID, key) then
		local entry = key and SpokenZones.Subzones[mapID] and SpokenZones.Subzones[mapID][key]
		-- Where it sits, a click away: the zone for an area or a city, the continent for a zone.
		local up = key and mapID or SpokenZones:PlaceAbove(mapID)
		local line = up and string.format(L.IN_ZONE_FMT, ZoneName(up)) or nil
		page:Show({ title = entry and (entry.name or key) or ZoneName(mapID), subtitle = line,
			onSubtitle = up and function()
				selection = { mapID = up, key = nil }
				SpokenZones:RefreshLoreWindow()
			end or nil,
			text = L.NOT_DISCOVERED })
		return
	end
	if key then
		local entry = SpokenZones.Subzones[mapID] and SpokenZones.Subzones[mapID][key]
		if entry then
			local name = entry.name or key
			local line = SpokenZones:PlaceLine(mapID, key)
			local back = function()
				selection = { mapID = mapID, key = nil }
				SpokenZones:RefreshLoreWindow()
			end
			if SpokenZones:IsPending(entry) then
				page:Show({ title = name, subtitle = line, onSubtitle = back,
					text = L.LORE_NOT_WRITTEN:format(name), contribute = { mapID, name } })
				return
			end
			-- Rows are keyed by the canonical form already, so this needs no normalising --
			-- unlike the map panel, which starts from the name the client reports.
			page:Show({ title = name, subtitle = line, onSubtitle = back,
				text = entry.full or entry.short or "", audio = { mapID, key }, report = { mapID, key } })
			return
		end
	end

	local entry = SpokenZones:GetLore(mapID)
	local name = ZoneName(mapID)
	local subtitle, up = SpokenZones:PlaceLine(mapID)
	local onSubtitle = up and function()
		selection = { mapID = up, key = nil }
		SpokenZones:RefreshLoreWindow()
	end or nil
	if not entry or SpokenZones:IsPending(entry) then
		page:Show({ title = name, subtitle = subtitle, onSubtitle = onSubtitle, text = L.LORE_NOT_WRITTEN:format(name),
			contribute = { mapID, nil } })
		return
	end
	page:Show({ title = name, subtitle = subtitle, onSubtitle = onSubtitle, text = entry.full or entry.short or "",
		audio = { mapID, nil }, report = { mapID, nil } })
end

local function Count(n, many, one) return n == 1 and one or string.format(many, n) end

--- The line under a place's name: where it sits and what its card or banner counts. Also returns
--- the map one level up, which a click on the line opens (nil for Azeroth).
function SpokenZones:PlaceLine(mapID, key)
	if key then return string.format(L.IN_ZONE_FMT, ZoneName(mapID)), mapID end
	local parent = self:PlaceAbove(mapID)
	if not parent then
		return Count(#Continents(), L.CONTINENT_COUNT_FMT, L.CONTINENT_COUNT_ONE) .. ", "
			.. Count(#ZoneIDs(), L.ZONE_COUNT_FMT, L.ZONE_COUNT_ONE), nil
	elseif IsContinent(mapID) then
		local found, total = BannerCount(ZonesOf(mapID))
		return InAndCount(parent, found, total), parent
	end
	return InAndCount(parent, Places(mapID)), parent
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

local function IsSelected(row)
	if not selection then
		return false
	end
	if row.kind == "subzone" then
		return selection.mapID == row.mapID and selection.key == row.key
	end
	if row.kind == "group" or selection.group then return row.kind == "group" and selection.group == row.group end
	return selection.mapID == row.mapID and selection.key == nil
end

local function OnRowClick(row)
	-- While searching, a banner shows what the search found in it whatever is open: a toggle would
	-- change nothing there, only leave the tree folded when the search is cleared.
	if row.kind == "group" then
		if filter == "" then groupOpen[row.group] = not groupOpen[row.group] end
		selection = { group = row.group }
	elseif row.kind == "continent" then
		-- Each continent opens and closes on its own; a click also chooses it.
		if filter == "" then continentOpen[row.mapID] = not continentOpen[row.mapID] end
		selection = { mapID = row.mapID, key = nil }
	elseif row.kind == "zone" then
		-- Clicking a zone or a city both chooses it and opens or closes its card alone: one the
		-- search opened for this search only, one under a banner it named as unsearched.
		if filter ~= "" and not row.asLeft then
			searchClosed[row.closeKey] = not searchClosed[row.closeKey] or nil
		else
			openZones[row.mapID] = not openZones[row.mapID] or nil
		end
		selection = { mapID = row.mapID, key = nil }
	else
		selection = { mapID = row.mapID, key = row.key }
	end
	SpokenZones:RefreshLoreWindow()
end

-- The chosen row brought into view. The client's scroll frame takes an offset only within the
-- range it last measured, which a list just drawn longer has not measured yet; nor has the frame
-- a height until the window is first laid out. Either left the list at its top, the chosen place
-- off screen: the range is measured now, and the row brought into view again a frame later.
local function ScrollToChosen(items)
	if list.scroll.UpdateScrollChildRect then list.scroll:UpdateScrollChildRect() end
	list:ScrollToSelection(items)
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			if filter == "" and list.items then list:ScrollToSelection(list.items) end
		end)
	end
end

function SpokenZones:RefreshLoreWindow(scrollToSelection)
	if not list then
		return
	end
	if not selection then
		LandOnPlayer()
		scrollToSelection = true
	end
	local items = list:Render()
	if scrollToSelection and selection then
		ScrollToChosen(items)
	end
	ShowEntry()
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

-- The places' tab: the tree down the left, the story on the spellbook's page beside it.
local function BuildPanel(p)
	panel = p
	list = SpokenCompendium.NewList(p, {
		search = L.LORE_SEARCH,
		none = L.LORE_SEARCH_NONE,
		only = L.LORE_DISCOVERED_ONLY,
		onlyGet = OnlyFound,
		onlySet = function(on) SpokenZones:Set("loreDiscoveredOnly", on) end,
		checks = { { label = L.LORE_VOICED_ONLY, get = OnlyVoiced,
			set = function(on) SpokenZones:Set("loreVoicedOnly", on) end } },
		build = BuildRowList,
		isSelected = IsSelected,
		onClick = OnRowClick,
		onSearch = function(text)
			SetFilter(text)
			SpokenZones:RefreshLoreWindow()
		end,
		addScrollBar = function(scroll, child, inset) return SpokenZones:AddScrollBar(scroll, child, inset) end,
	})
	p.Refresh = function() SpokenZones:RefreshLoreWindow() end
	p.inset, p.filterButton, p.filterMenu, p.noMatch, p.listBar = list.inset, list.filterButton, list.filterMenu, list.noMatch, list.bar

	-- The story: the spellbook's page down the rest of the window, in an inset of its own as the
	-- list is -- the way the game's split windows frame each pane (the professions window), so the
	-- two are parted by their borders rather than one running into the other.
	local _, right = SpokenCompendium.Margins()
	local window = SpokenCompendium:Window()
	local okPage, pageInset = pcall(CreateFrame, "Frame", nil, p, "InsetFrameTemplate")
	if not okPage or not pageInset then pageInset = CreateFrame("Frame", nil, p) end
	pageInset:SetPoint("TOPLEFT", list.inset, "TOPRIGHT", 6, 38)
	pageInset:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -right, window.templated and 6 or 12)
	p.pageInset = pageInset
	local holder = CreateFrame("Frame", nil, pageInset)
	holder:SetPoint("TOPLEFT", pageInset, "TOPLEFT", 3, -3)
	holder:SetPoint("BOTTOMRIGHT", pageInset, "BOTTOMRIGHT", -3, 3)
	page = SpokenZones:CreateLorePage(holder, "book")
	-- The inset's border over the parchment's edge, not under it.
	if type(pageInset.NineSlice) == "table" and pageInset.NineSlice.SetFrameLevel then
		pageInset.NineSlice:SetFrameLevel(holder:GetFrameLevel() + 5)
	end
	p.page = page

	-- Toggling "Hide Contribute Buttons" in Spoken's settings fires no game event.
	if _G.Spoken and Spoken.RegisterCallback then
		Spoken:RegisterCallback("CONTRIBUTE_SETTINGS_CHANGED", function()
			SpokenZones:RefreshLoreWindow()
		end)
		-- Nor does Hide Report Buttons.
		Spoken:RegisterCallback("REPORT_SETTINGS_CHANGED", function()
			SpokenZones:RefreshLoreWindow()
		end)
	end

	SpokenZones.window = p
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

function SpokenZones:ToggleLoreWindow()
	if not list then
		return
	end
	if SpokenCompendium:IsOpen("places") then
		SpokenCompendium:Hide()
		return
	end

	-- Opened on where the player stands now, unless they chose a place here: the refresh lands
	-- again on a selection that was only ever where they stood.
	if selection == landed then selection = nil end

	list:ClearSearch()
	SetFilter("")
	SpokenCompendium:Open("places")
	-- A window closed folded would reopen as the bare list.
	SpokenCompendium:Expand()
	SpokenZones:RefreshLoreWindow(true)
end

-- Open on a named entry rather than on the player's location. Not routed through
-- ToggleLoreWindow, which can land on where the player stands: narration outlives the zone you
-- started it in.
function SpokenZones:ShowLoreFor(mapID, areaKey)
	if not list or not mapID then
		return
	end
	OpenZone(mapID)
	Reveal(mapID)
	selection = { mapID = mapID, key = areaKey }
	list:ClearSearch()
	SetFilter("")
	SpokenCompendium:Open("places")
	-- Asked for an entry, so show it: a window closed collapsed would reopen as the bare list.
	SpokenCompendium:Expand()
	SpokenZones:RefreshLoreWindow(true)
end

-- The window's size, kept with the rest of Zones' settings as it was when it was Lore of Azeroth.
local SIZE_KEYS = { width = "loreWindowWidth", height = "loreWindowHeight" }

function SpokenZones:SetupLoreWindow()
	if list then
		return
	end
	SpokenCompendium:Register("places", {
		label = L.COMPENDIUM_PLACES,
		order = 1,
		title = L.LORE_WINDOW_TITLE,
		build = BuildPanel,
		-- A place found since the window last opened is listed now. Come back to from another tab,
		-- the tab is on where the player stands now, unless they chose a place here.
		onShow = function()
			if SpokenZones.RefreshFound then SpokenZones:RefreshFound() end
			if selection == landed then selection = nil end
		end,
		store = {
			get = function(key) return SpokenZones:Get(SIZE_KEYS[key]) end,
			set = function(key, value) SpokenZones:Set(SIZE_KEYS[key], value) end,
		},
		-- Opened from Spoken's menu and page on where the player stands, as from the map.
		open = function() SpokenZones:ToggleLoreWindow() end,
		enabled = function() return SpokenZones:IsPartOn() end,
		-- Unlock Undiscovered Zones, on Spoken's page.
		unlock = {
			get = function() return SpokenZones:Get("showUndiscovered") == true end,
			set = function(value)
				SpokenZones:Set("showUndiscovered", value)
				if SpokenZones.ApplyPanelOptions then SpokenZones:ApplyPanelOptions() end
				SpokenZones:RefreshLoreWindow()
			end,
		},
	})
	-- Built now, hidden, so the map's panel and the settings can open it at once.
	SpokenCompendium:Select("places")
end
