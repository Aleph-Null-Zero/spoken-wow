-- The areas that are dungeons and raids, by the zone of their entrance. Azeroth's Compendium lists
-- each as a card inside that zone's card, as the Quests tab files their quests.
--
-- Each is the area's story in Subzones.lua (`mapID` and `key`) and `dungeon`, the instance's map:
-- the id Spoken_Quests' Data/Compendium.lua files the dungeon's quests under, so the two tabs name
-- one dungeon by one id. Kept by hand; tests/lua/zones_dungeons_test.lua checks it against both.
--
-- Razorfen Downs' story is under Thousand Needles, where the wiki has it, and its entrance is in
-- The Barrens: the story, its recording and its picture stay keyed by Thousand Needles, the
-- Compendium lists it in The Barrens and finds it there, and found at its entrance it is told by
-- those keys (SpokenZones:StoryPlace). Any entry whose `mapID` is not its entrance's is told so,
-- as the other areas in Data/AreaZones.lua are.

local _, SpokenZones = ...

SpokenZones.Dungeons = {
	-- Kalimdor
	[1413] = { -- The Barrens
		{ mapID = 1413, key = "wailing caverns", dungeon = 43 },
		{ mapID = 1441, key = "razorfen downs", dungeon = 129 },
	},
	[1440] = { { mapID = 1440, key = "blackfathom deeps", dungeon = 48 } }, -- Ashenvale
	[1444] = { { mapID = 1444, key = "dire maul", dungeon = 429 } }, -- Feralas
	[1445] = { { mapID = 1445, key = "onyxias lair", dungeon = 249 } }, -- Dustwallow Marsh
	[1446] = { { mapID = 1446, key = "zulfarrak", dungeon = 209 } }, -- Tanaris
	[1454] = { { mapID = 1454, key = "ragefire chasm", dungeon = 389 } }, -- Orgrimmar
	-- Eastern Kingdoms
	[1418] = { { mapID = 1418, key = "uldaman", dungeon = 70 } }, -- Badlands
	[1420] = { { mapID = 1420, key = "scarlet monastery", dungeon = 189 } }, -- Tirisfal Glades
	[1421] = { { mapID = 1421, key = "shadowfang keep", dungeon = 33 } }, -- Silverpine Forest
	[1422] = { { mapID = 1422, key = "scholomance", dungeon = 289 } }, -- Western Plaguelands
	[1423] = { { mapID = 1423, key = "stratholme", dungeon = 329 } }, -- Eastern Plaguelands
	[1426] = { { mapID = 1426, key = "gnomeregan", dungeon = 90 } }, -- Dun Morogh
	[1434] = { { mapID = 1434, key = "zulgurub", dungeon = 309 } }, -- Stranglethorn Vale
	[1435] = { { mapID = 1435, key = "temple of atalhakkar", dungeon = 109 } }, -- Swamp of Sorrows: the Sunken Temple
	[1436] = { { mapID = 1436, key = "deadmines", dungeon = 36 } }, -- Westfall
}
