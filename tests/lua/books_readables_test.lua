-- The readables in Azeroth's Compendium: every book, letter, note and plaque, in a card for the
-- zone it is in under its continent's banner and a small card for what it is, or by what it is
-- alone, found or not; a readable's page with
-- where it comes from; the search, Found Only and Unlock Unfound Readables; and the tabs once the
-- places are there too. Against the shipped data (Data/Books.lua, Data/Places.lua). Run with
-- `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local Expect, Failures = H.Expecter(print)
local BOOKS = here .. "/../../addons/Spoken_Books/"
local SPOKEN = here .. "/../../addons/Spoken/"

stub.SetClient("11509"); stub.ResetSound(); stub.ResetTimers(); stub.ResetFrames()

-- The maps the client names, and where each is.
local MAPS = { [947] = { "Azeroth" }, [1414] = { "Kalimdor", 947 }, [1415] = { "Eastern Kingdoms", 947 },
    [1429] = { "Elwynn Forest", 1415 }, [1453] = { "Stormwind City", 1415 }, [1436] = { "Westfall", 1415 },
    [1455] = { "Ironforge", 1415 }, [1426] = { "Dun Morogh", 1415 },
    -- Alterac Valley under Azeroth, as one client hangs it; Warsong Gulch in Ashenvale; an isle on
    -- no continent.
    [1459] = { "Alterac Valley", 947 }, [1440] = { "Ashenvale", 1414 }, [1460] = { "Warsong Gulch", 1440 },
    [9001] = { "Zephras Isle", 947 },
    -- A hill on Kalimdor with nothing to read, and a map on no continent with nothing either.
    [9002] = { "Bare Hills", 1414 }, [9003] = { "Empty Sea", 947 } }
_G.C_Map.GetMapInfo = function(id)
    local map = MAPS[id]
    return { mapType = 3, name = map and map[1] or ("Map " .. id), parentMapID = map and map[2] or nil }
end
_G.C_Texture = { GetAtlasInfo = stub.ListAtlas }
_G.GetLocale = function() return "enUS" end
_G.UISpecialFrames = _G.UISpecialFrames or {}
-- The game's portrait frame, its title kept to be read back, and each frame's template.
local createFrame = _G.CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
    local frame = createFrame(kind, name, parent, template)
    if template == "PortraitFrameTemplate" then
        function frame:SetTitle(text) self.title = text end
        function frame:SetPortraitToAsset(path) self.portrait = path end
    end
    frame.template = template
    return frame
end

local env = stub.LoadSpoken(SPOKEN)
env.Addon:Enable()
_G.SpokenBooksSettings, _G.SpokenBooksCharacter = nil, nil
-- The spellbook's colour, which the places' page writes in too.
_G.SPELLBOOK_FONT_COLOR = { GetRGB = function() return 0.2, 0.09, 0 end }
local B = {}
for _, file in ipairs({ "Locale/enUS", "Checksum", "Core", "Language", "Reader", "Audio", "Playlist",
    "UI/Layout", "UI/TextView", "UI/Compendium", "UI/Readables", "Events", "Commands" }) do
    assert(loadfile(BOOKS .. file .. ".lua"))("Spoken_Books", B)
end
B:InitDB()
B:SetupSource()
dofile(BOOKS .. "Data/Books.lua")
dofile(BOOKS .. "Data/Places.lua")
local L = B.L

-- A note on the isle, and one in Warsong Gulch: the shipped data has neither.
local ISLE_NOTE, GULCH_NOTE = 990001, 990002
for id, place in pairs({ [ISLE_NOTE] = { "Isle Tide Tables", 9001 }, [GULCH_NOTE] = { "Gulch Orders", 1460 } }) do
    SpokenBooksData.pages[id] = { book = id, number = 1, text = "Words of " .. place[1] .. "." }
    SpokenBooksData.books[id] = { title = place[1], pages = { id } }
    SpokenBooksPlaces.books[id] = { kind = "world", type = "note", zones = { place[2] } }
end

-- Kurdran Wildhammer and Alleria Windrunner stand in Stormwind; A Dusty Unsent Letter is carried
-- from Westfall; An Exotic Cookbook is had across Azeroth.
local KURDRAN, ALLERIA, LETTER, COOKBOOK = 287, 288, 16, 410
SpokenBooksCharacter.found[KURDRAN] = true

B:SetupReadables()
stub.SetZone({ map = 1436 })
B:ShowReadables()
local window = _G.SpokenCompendium.window
local panel = B.readables
Expect("the readables are a tab of Azeroth's Compendium", window.title, L.COMPENDIUM_TITLE)
Expect("...with no tabs while they are its only one", _G.SpokenCompendiumWindowTab1:IsShown(), false)

local rows
local function Collect(frame)
    for _, child in ipairs(frame.children or {}) do
        if child.row then table.insert(rows, child) end
        Collect(child)
    end
end
-- By each item's own name: a banner draws its name in capitals.
local function Shown()
    rows = {}
    Collect(panel)
    local labels = {}
    for _, row in ipairs(rows) do if row.shown ~= false and row.row then table.insert(labels, row.row.label) end end
    return table.concat(labels, "|")
end
local function RowFor(label)
    Shown()
    for _, row in ipairs(rows) do if row.shown ~= false and row.row and row.row.label == label then return row end end
end
local function Click(label)
    local row = RowFor(label)
    assert(row, "no row " .. label)
    row.scripts.OnClick(row)
end
local function Has(list, label)
    return ("|" .. list .. "|"):find("|" .. label .. "|", 1, true) ~= nil
end

-- Opened with nothing chosen, or still on where it landed, the tab lands on where the player stands.
local function Reopen(map)
    window:Hide()
    stub.SetZone({ map = map })
    B:ShowReadables()
end
Expect("opened, the tab lands on the player's zone", panel.page.title.text, "Westfall")
Expect("...its card open on what is in it", RowFor("Westfall").row.open and Has(Shown(), "A Dusty Unsent Letter"), true)
Reopen(1453)
Expect("...reopened elsewhere, on the zone the player stands in now", panel.page.title.text, "Stormwind City")
Expect("...a city's card opened inside its zone's", RowFor("Elwynn Forest").row.open and Has(Shown(), "Kurdran Wildhammer"), true)
Reopen(9002)
Expect("...where their zone has nothing to read, their continent's banner", panel.page.title.text, "Kalimdor")
Reopen(9003)
Expect("...on no continent, the first continent's", panel.page.title.text, "Eastern Kingdoms")
Click("Westfall")
Reopen(1453)
Expect("...and what the player chose, kept on reopening", panel.page.title.text, "Westfall")
Click("Westfall")

local list = Shown()
Expect("the list is laid out as the places': a banner for each continent, no Azeroth above them",
    RowFor("Eastern Kingdoms") ~= nil and RowFor("Eastern Kingdoms").row.style == "banner" and not Has(list, "Azeroth"), true)
Expect("...its name as it is", RowFor("Eastern Kingdoms").label.text, "Eastern Kingdoms")
Expect("...a card under it for each zone", Has(list, "Elwynn Forest") and Has(list, "Westfall")
    and RowFor("Elwynn Forest").row.style == "card" and RowFor("Elwynn Forest").row.nest, 0)
Expect("...a city inside the zone around it, not beside it", Has(list, "Stormwind City"), false)
Expect("...the readables after the continents, a banner each: those found across Azeroth and those of no known origin",
    RowFor(L.GROUP_WIDE).row.style == "banner" and RowFor(L.GROUP_UNKNOWN).row.style, "banner")
Expect("...each zone's card counting what is found out of all, its city's included",
    RowFor("Elwynn Forest").count.text:match("^1/%d+ • %d+%%$") ~= nil, true)
Expect("...its badge the zone's painting in the collections window's gold frame", RowFor("Elwynn Forest").icon.texture
    == _G.Spoken:ZoneIcon(1429) and RowFor("Elwynn Forest").iconFrame:IsShown() and RowFor("Elwynn Forest").iconFrame.atlas,
    "collections-itemborder-collected")
Expect("...and the seasonal events' readables, in a group of their own before them",
    Has(list, L.GROUP_EVENTS) and list:find(L.GROUP_EVENTS, 1, true) < list:find(L.GROUP_WIDE, 1, true), true)
Click(L.GROUP_EVENTS)
Expect("...which opens on them, the Winter Veil feast it once listed in the cities among them",
    Has(Shown(), "The Feast of Winter Veil") and Has(Shown(), "A Bloodstained Envelope"), true)
Click(L.GROUP_EVENTS)

-- The zones on no continent, then the battlegrounds wherever the client hangs them, each under a
-- banner of their own after the continents.
local function At(list, label) return ("|" .. list .. "|"):find("|" .. label .. "|", 1, true) end
list = Shown()
Expect("Other Lands then Battlegrounds, each a banner, after the continents and before the groups",
    RowFor(L.GROUP_LANDS).row.style == "banner" and RowFor(L.GROUP_BATTLEGROUNDS).row.style == "banner"
    and At(list, "Kalimdor") < At(list, L.GROUP_LANDS) and At(list, L.GROUP_LANDS) < At(list, L.GROUP_BATTLEGROUNDS)
    and At(list, L.GROUP_BATTLEGROUNDS) < At(list, L.GROUP_EVENTS), true)
Expect("...closed at first", Has(list, "Zephras Isle") or Has(list, "Alterac Valley"), false)
Expect("...a battleground hung under a continent not listed under it", Has(list, "Warsong Gulch"), false)
Click(L.GROUP_LANDS)
Expect("Other Lands opens on a card for each zone on no continent", RowFor("Zephras Isle") ~= nil
    and RowFor("Zephras Isle").row.style == "card" and RowFor("Zephras Isle").row.nest, 0)
Expect("...its page its name, what is found of it, and the words to choose one",
    panel.page.title.text .. "|" .. panel.page.sub.text .. "|" .. panel.page.body.text.text,
    L.GROUP_LANDS .. "|" .. L.FOUND_FMT:format(0, 1) .. "|" .. L.READABLES_PICK)
Click(L.GROUP_LANDS)
Expect("...and closes again", Has(Shown(), "Zephras Isle"), false)
Click(L.GROUP_BATTLEGROUNDS)
Expect("Battlegrounds opens on Alterac Valley under Azeroth and Warsong Gulch under Ashenvale",
    Has(Shown(), "Alterac Valley") and Has(Shown(), "Warsong Gulch"), true)
Expect("...its page its name", panel.page.title.text, L.GROUP_BATTLEGROUNDS)
Click("Alterac Valley")
Expect("...Alterac Valley's gravestone listed in it", Has(Shown(), "Rock of Durotan"), true)
Click("Alterac Valley")
Click(L.GROUP_BATTLEGROUNDS)

Click("Elwynn Forest")
Click("Stormwind City")
list = Shown()
Expect("the city opens inside its zone, its readables by what they are", Has(list, L.TYPE_PLAQUE) and Has(list, "Kurdran Wildhammer"), true)
Expect("...the city a small card inside its zone's card", RowFor("Stormwind City").row.small and RowFor("Stormwind City").row.nest, 1)
Expect("...each kind a small card inside the city's", RowFor(L.TYPE_PLAQUE).row.small and RowFor(L.TYPE_PLAQUE).row.nest, 2)
Expect("...its badge what that kind of writing looks like, in the same frame", RowFor(L.TYPE_PLAQUE).icon.texture
    .. " " .. RowFor(L.TYPE_PLAQUE).iconFrame.atlas, [[Interface\Icons\INV_Misc_StoneTablet_03]] .. " collections-itemborder-collected")
Expect("...its writings rows inside that", RowFor("Kurdran Wildhammer").row.leaf and RowFor("Kurdran Wildhammer").row.nest, 3)
Expect("...a line down each open card's contents beside them, a step in from the banner",
    RowFor("Kurdran Wildhammer").rails[3] ~= nil
    and RowFor("Kurdran Wildhammer").rails[3]:IsShown() and RowFor("Kurdran Wildhammer").rails[3].anchor.x, 60)
Expect("...a readable not found greyed, with the padlock", RowFor("Ranger Captain Alleria Windrunner").row.locked, true)
Expect("...one found open to read", RowFor("Kurdran Wildhammer").row.locked, false)

Click("Kurdran Wildhammer")
local page = panel.page
Expect("a readable's page: its title", page.title.text, "Kurdran Wildhammer")
Expect("...in the spellbook's ink, as the places' page is", page.body.ink and page.body.ink[1], 0.2)
Expect("...where it is", page.sub.text, L.KIND_WORLD .. " · Stormwind City")
Expect("...on one line, cut short where it names many places", page.sub.wordWrap, false)
Expect("...and its words", page.body.text.text ~= nil and #page.body.text.text > 40, true)
Click("Ranger Captain Alleria Windrunner")
Expect("a readable not found does not open", page.title.text, "Kurdran Wildhammer")

SpokenBooksSettings.unlockUnfound = true
B:RefreshReadables()
Expect("Unlock Unfound Readables opens it", RowFor("Ranger Captain Alleria Windrunner").row.locked, false)
-- Opening one is not finding it: the counts stay what the character has found.
local before = RowFor("Stormwind City").count.text
Click("Ranger Captain Alleria Windrunner")
Expect("...and choosing it leaves the counts as they were", RowFor("Stormwind City").count.text, before)
SpokenBooksSettings.unlockUnfound = false

SpokenBooksCharacter.found[LETTER] = true
Click("Westfall")
Click("A Dusty Unsent Letter")
Expect("opened on a readable carried from a zone", page.title.text, "A Dusty Unsent Letter")
Expect("...said to be carried, and from where", page.sub.text, L.KIND_CARRIED .. " · Westfall")
Expect("...how it is had first, the name and the zone", (page.body.text.text or ""):find(
    L.FROM_IN_ZONES:format(L.FROM_QUEST_START:format("The Legend of Stalvan"), "Westfall"), 1, true) == 1, true)

-- The search: every match, with what holds it, opened.
local box
for _, child in ipairs(panel.children or {}) do if child.template == "SearchBoxTemplate" then box = child end end
box:SetText("cookbook")
box.hooks.OnTextChanged[1](box)
list = Shown()
Expect("a search shows what matches, under what holds it", Has(list, L.GROUP_WIDE) and Has(list, "An Exotic Cookbook")
    and not Has(list, "Kurdran Wildhammer"), true)
local function Search(text)
    box:SetText(text)
    box.hooks.OnTextChanged[1](box)
    return Shown()
end
-- A search naming what holds readables lists all it holds, the titles matching or not.
list = Search("alterac")
Expect("a search naming a zone lists all it holds, its card open", Has(list, "Rock of Durotan")
    and RowFor("Alterac Valley").row.open, true)
list = Search(L.TYPE_GRAVE:lower())
Expect("...naming a kind, every one of that kind", Has(list, "Rock of Durotan") and not Has(list, "Kurdran Wildhammer"), true)
list = Search(L.GROUP_LANDS:lower())
Expect("...naming Other Lands, its zones and their readables", Has(list, "Zephras Isle") and Has(list, "Isle Tide Tables"), true)
list = Search(L.GROUP_WIDE:lower())
Expect("...naming a group, its readables", Has(list, "An Exotic Cookbook"), true)
list = Search("eastern kingdoms")
Expect("...naming a continent, its zones and their readables", Has(list, "Westfall") and Has(list, "Kurdran Wildhammer")
    and not Has(list, "Rock of Durotan"), true)
Click("Westfall")
Expect("...a card in it chosen, its page shows", page.title.text, "Westfall")
Search("")

-- Found Only: the readables not found, and what holds none found, left out.
SpokenBooksSettings.compendiumFoundOnly = true
B:RefreshReadables()
list = Shown()
Expect("Found Only leaves out what is not found", Has(list, "Ranger Captain Alleria Windrunner") or Has(list, L.GROUP_UNKNOWN), false)
Expect("...Other Lands' and Battlegrounds' banners too, holding nothing found",
    Has(list, L.GROUP_LANDS) or Has(list, L.GROUP_BATTLEGROUNDS), false)
Expect("...and keeps what is", Has(list, "Westfall") and Has(list, "Elwynn Forest"), true)
SpokenBooksSettings.compendiumFoundOnly = false

-- Opening one in the world finds it, and the tree says so.
SpokenBooksCharacter.found[ALLERIA] = true
Click("Elwynn Forest")
Click("Stormwind City")
Expect("a readable found since opens", RowFor("Ranger Captain Alleria Windrunner").row.locked, false)

-- The type it is listed under closes and opens again, as the zone does.
local typeRow
do
    Shown()
    for _, row in ipairs(rows) do
        if row.shown ~= false and row.row and row.row.kind == "group" and row.row.mapID then typeRow = row.label.text end
        if row.row and row.label.text == "Ranger Captain Alleria Windrunner" then break end
    end
end
Expect("a zone's readables are under a small card for their kind, open", typeRow ~= nil and RowFor(typeRow).row.open, true)
Click(typeRow)
Expect("...a click closes the type", Has(Shown(), "Ranger Captain Alleria Windrunner") or RowFor(typeRow).row.open, false)
Click(typeRow)
Expect("...and another opens it again", Has(Shown(), "Ranger Captain Alleria Windrunner") and RowFor(typeRow).row.open, true)

-- The filter menu beside the search box, as the spellbook's: Found Only, then By Zone or By Type
-- under a divider. By Type is the types alone.
local function Menu()
    local entries = {}
    for _, info in ipairs(stub.OpenDropdown(panel.filterMenu)) do
        table.insert(entries, info.isSeparator and "--" or info.text)
    end
    return table.concat(entries, "|"), stub.OpenDropdown(panel.filterMenu)
end
Expect("the filter menu holds Found Only and Voiced Only, then By Zone and By Type", (Menu()),
    L.READABLES_FOUND_ONLY .. "|" .. L.READABLES_VOICED_ONLY .. "|--|" .. L.READABLES_BY_ZONE .. "|" .. L.READABLES_BY_TYPE)
local _, choices = Menu()
Expect("...By Zone the one chosen", choices[4].checked and not choices[5].checked, true)

-- Voiced Only: what no installed voice pack reads is left out, with what holds nothing else.
local hasAudio = B.HasAudio
local alleriaPage = B:Data().books[ALLERIA].pages[1]
B.HasAudio = function(_, page) return page == alleriaPage end
choices[2].func()
list = Shown()
Expect("Voiced Only leaves out what has no recording", Has(list, "Kurdran Wildhammer") or Has(list, "Westfall"), false)
Expect("...and keeps what has one, with the zone that holds it", Has(list, "Ranger Captain Alleria Windrunner")
    and Has(list, "Elwynn Forest"), true)
Expect("...counting only what it lists", RowFor("Elwynn Forest").count.text, "1/1")
Expect("...and is remembered", SpokenBooksSettings.compendiumVoicedOnly, true)
_, choices = Menu()
choices[2].func()
Expect("...off, everything again", Has(Shown(), "Westfall"), true)
B.HasAudio = hasAudio

-- The readables places.mjs leaves out (the Deprecated and TEST items, whose page is "Missing
-- Text") are neither listed nor counted, so every count can reach all.
local placed = 0
for _ in pairs(SpokenBooksPlaces.books) do placed = placed + 1 end

_, choices = Menu()
choices[5].func()
list = Shown()
local counted = 0
for _, row in ipairs(rows) do if row.shown ~= false and row.row and row.row.kind == "type" then counted = counted + row.row.total end end
Expect("the kinds count only the readables the places know", counted, placed)
Click(L.TYPE_OTHER)
Expect("By Type does not list one the places leave out", RowFor("Test Language Item"), nil)
Click(L.TYPE_OTHER)
Expect("By Type: the list is a card for each kind alone", Has(list, L.TYPE_PLAQUE) and Has(list, L.TYPE_LETTER) and not Has(list, "Elwynn Forest"), true)
_, choices = Menu()
Expect("...and the menu says so", choices[5].checked and not choices[4].checked, true)
Expect("...a search naming a kind lists every one of it", Has(Search(L.TYPE_PLAQUE:lower()), "Kurdran Wildhammer"), true)
Search("")
Click(L.TYPE_PLAQUE)
Expect("...a type opens on its readables", Has(Shown(), "Kurdran Wildhammer"), true)
Expect("...each a card, counted found out of all", RowFor(L.TYPE_PLAQUE).row.style == "card"
    and RowFor(L.TYPE_PLAQUE).count.text:match("^2/%d+ • ") ~= nil, true)
Expect("...with no banner above them, not set in", RowFor(L.TYPE_PLAQUE).face[1].anchor.x, 0)
list = Shown()
Expect("...journals and diaries a type of their own, after books, and pictures and maps one too",
    Has(list, L.TYPE_JOURNAL) and Has(list, L.TYPE_PICTURE)
    and list:find(L.TYPE_BOOK, 1, true) < list:find(L.TYPE_JOURNAL, 1, true), true)
Click(L.TYPE_JOURNAL)
Expect("...Stalvan's diary among the journals", Has(Shown(), "Book from Sven's Farm"), true)
Click(L.TYPE_JOURNAL)
Click(L.TYPE_PICTURE)
Expect("...the Snapshot of Gammerita among the pictures", Has(Shown(), "Snapshot of Gammerita"), true)
Click(L.TYPE_PICTURE)
_, choices = Menu()
choices[4].func()
Expect("...and By Zone again, the zones", Has(Shown(), "Elwynn Forest"), true)

-- The groups after the continents: a card for each kind inside, the writings under it.
Click(L.GROUP_WIDE)
list = Shown()
local kindRow
for _, row in ipairs(rows) do
    if row.shown ~= false and row.row and row.row.kind == "kind" and row.row.group == "wide" then kindRow = kindRow or row end
end
Expect("a group's banner opens on a card for each kind of writing in it", kindRow ~= nil and kindRow.row.style == "card"
    and kindRow.row.nest, 0)
Expect("...the writings under it", Has(list, "An Exotic Cookbook") and RowFor("An Exotic Cookbook").row.nest, 1)
kindRow.scripts.OnClick(kindRow)
Expect("...a kind chosen, its page names it and its group", page.title.text == kindRow.row.label
    and page.sub.text:find(L.GROUP_WIDE .. " · ", 1, true) == 1, true)
Expect("...and the click closes it", kindRow.row.open, false)
Click(L.GROUP_WIDE)

-- The places' tab joins: the tabs show, and each shows its own panel.
_G.SpokenCompendium:Register("places", { label = "Zones", order = 1, title = L.COMPENDIUM_TITLE,
    build = function(p) p.places = true end })
_G.SpokenCompendium:Select("places")
Expect("with two tabs, the tabs show", _G.SpokenCompendiumWindowTab1:IsShown() and _G.SpokenCompendiumWindowTab2:IsShown(), true)
Expect("...each its own panel", _G.SpokenCompendium:Tab("places").panel:IsShown() and not panel:IsShown(), true)
_G.SpokenCompendiumWindowTab2.scripts.OnClick(_G.SpokenCompendiumWindowTab2)
Expect("...and a click on the other goes back to the readables", panel:IsShown(), true)

-- A tab whose part is off is not shown, and does not open.
local on = { spare = false, readables = true }
_G.SpokenCompendium:Register("spare", { label = "Spare", order = 3, build = function() end,
    enabled = function() return on.spare end })
_G.SpokenCompendium:Tab("readables").enabled = function() return on.readables end
Expect("a tab whose part is off has no tab", _G.SpokenCompendiumWindowTab3 == nil or not _G.SpokenCompendiumWindowTab3:IsShown(), true)
Expect("...and is not opened", _G.SpokenCompendium:Select("spare") == nil and _G.SpokenCompendium:Active(), "readables")
Expect("...the window open on the readables", window:IsShown(), true)
on.readables = false
_G.SpokenCompendium:Relayout()
Expect("the part of the tab shown switched off, the window closes", window:IsShown(), false)
on.readables = true

-- Played from the Compendium is browsing: it does not count for Read Only Once, so the book still
-- reads itself the first time it is opened in the world.
do
    local source, clipFor, isQueued = B.source, B.ClipFor, B.IsQueued
    B.source = { Enqueue = function() return true end, StopAll = function() end }
    B.ClipFor = function() return {} end
    B.IsQueued = function() return false end
    SpokenBooksCharacter.read[KURDRAN] = nil
    B:SyncTo(SpokenBooksData.books[KURDRAN].pages[1], true)
    Expect("Play in the Compendium does not count for Read Only Once", B:HasReadBook(KURDRAN), false)
    B:SyncTo(SpokenBooksData.books[KURDRAN].pages[1])
    Expect("...a book read in the world does", B:HasReadBook(KURDRAN), true)
    B.source, B.ClipFor, B.IsQueued = source, clipFor, isQueued
end

-- Listening is not finding: a book heard (Read Only Once's record) stays unfound until it is
-- opened in the world. One heard before Found was kept still is.
SpokenBooksCharacter.found[ALLERIA] = nil
B:MarkBookRead(ALLERIA)
Expect("a book heard is not found by it", B:IsBookFound(ALLERIA), false)
_G.SpokenBooksCharacter = { read = { [LETTER] = true } }
B:InitDB()
Expect("...one heard before Found was kept is found", B:IsBookFound(LETTER), true)

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll readables tests passed")
