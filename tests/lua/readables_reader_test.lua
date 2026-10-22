-- Which page the addon thinks is on screen, against the real generated lookup and the real
-- pages from the corpus. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local world = stub.world
local SPOKEN = here .. "/../../addons/Spoken/"
local READABLES = here .. "/../../addons/Spoken_Readables/"
local Expect, Failures = H.Expecter(print)

local function LoadReadables()
    local SpokenReadables = {}
    for _, file in ipairs({ "Locale/enUS", "Checksum", "Core", "Language", "Reader", "Audio" }) do
        local chunk = assert(loadfile(READABLES .. file .. ".lua"))
        chunk("Spoken_Readables", SpokenReadables)
    end
    return SpokenReadables
end

stub.SetClient("16001"); stub.ResetSound(); stub.ResetTimers()
_G.SpokenReadablesSettings = nil
local env = stub.LoadSpoken(SPOKEN)
env.Addon:Enable()
local B = LoadReadables()
B:InitDB()
B:SetupSource()
dofile(READABLES .. "Data/Books.lua")

-- Two real pages of one real book: the Hillsbrad Town Registry, whose first page names the
-- town and whose second lists its debts.
local REGISTRY_1 = "Hillsbrad Town Registry\n\nWe the people of Hillsbrad do solemny swear our faith and devotion to the Alliance maintained by the great monarchs, King Magni Bronzebeard of Ironforge and King Anduin Wrynn of Stormwind.\n\nHerein lies the town registry for purposes of governing this fair city in the foothills of the great Alterac Mountains as well as serving as a record of those who have paid their taxes to their Kings and to the great almighty Alliance."

---------------------------------------------------------------- the normal path
stub.ShowPage({ title = "Hillsbrad Town Registry", number = 1, text = REGISTRY_1, hasNext = true })
Expect("a page is found by title, number and checksum", B:PageOnScreen(), 261)

local book, number = B:PlaceOf(261)
Expect("...and knows which book it is in", book, 261)
Expect("...and where", number, 1)
Expect("...and what the book is called", B:BookOf(261).title, "Hillsbrad Town Registry")

---------------------------------------------------------------- mail is not a book
stub.ShowPage({ title = "A letter", number = 1, text = REGISTRY_1, creator = "Somebody" })
Expect("a letter with a creator is not read", B:PageOnScreen(), nil)
local savedPageText = B.pageText
B.pageText = nil
Expect("mail is never captured for captions", B:PageOnScreen(), nil)
Expect("...even if its words match a book", B.pageText, nil)
B.pageText = savedPageText

stub.ShowPage({ title = "Hillsbrad Town Registry", number = 1, text = REGISTRY_1 })
_G.MailFrame = { IsShown = function() return true end }
Expect("a page under an open MailFrame is not read", B:PageOnScreen(), nil)
_G.MailFrame = { IsShown = function() return false end }
Expect("...and is read again once the mail is closed", B:PageOnScreen(), 261)
_G.MailFrame = nil

---------------------------------------------------------------- the title fallback
stub.ShowPage({ title = "Registre de la ville", number = 1, text = REGISTRY_1 })
Expect("a title the corpus does not know still finds the page by checksum", B:PageOnScreen(), 261)

---------------------------------------------------------------- refusing to guess
stub.ShowPage({ title = "Hillsbrad Town Registry", number = 1, text = "Words nobody wrote." })
Expect("text the corpus does not have is nil rather than a guess", B:PageOnScreen(), nil)

stub.ShowPage({ title = "Hillsbrad Town Registry", number = 9, text = REGISTRY_1 })
Expect("the wrong page number still matches, through the checksum", B:PageOnScreen(), 261)

stub.ClosePage()
Expect("a closed frame is not a page", B:PageOnScreen(), nil)

world.itemText = ""
Expect("an empty page is not a page", B:PageOnScreen(), nil)

---------------------------------------------------------------- the ambiguous ones
-- "Pteradon Skeleton" is two books holding identical text. Nothing on screen tells them
-- apart, so the lookup collapses them and the page must resolve to the lower of the two
-- rather than to nothing.
local PTERADON = "This intact pteradon skeleton was recovered from the remote Un'Goro Crater. Based on the skeletal structure, it is clear that this specific genus has not yet been encountered. This skeleton could have been preserved for any number of centuries beneath the region's rich soil."
stub.ShowPage({ title = "Pteradon Skeleton", number = 1, text = PTERADON })
Expect("two books with the same words resolve to the lower", B:PageOnScreen(), 1756)

---------------------------------------------------------------- pages the client fills in
-- The client writes the reader's name, class and gender word into a page, while the index is
-- keyed on the page with its tokens. These are found by the words around what was filled in.
local PROOF = "This proof of deed is to verify that %s slew Margol the Rager, scourge of the searing gorge.\n\nThe Ironforge museum recognizes this achievement and thanks the bearer for their generous contribution.\n\n-Head Curator Thorius Stonetender"
stub.ShowPage({ title = "Proof of Deed", number = 1, text = string.format(PROOF, "Torno") })
Expect("a page with the reader's name in it is found", B:PageOnScreen(), 1231)
stub.ShowPage({ title = "Proof of Deed", number = 1, text = string.format(PROOF, "Valaas Dawnsight") })
Expect("...whatever the name", B:PageOnScreen(), 1231)
stub.ShowPage({ title = "Proof of Deed", number = 1, text = "This proof of deed is to verify that Torno slew Hogger." })
Expect("...but other words around a name are still nil", B:PageOnScreen(), nil)

local TABLET = "Greetings, %s. The Shattered Hand sends its regards and hopes you find the Valley a comfortable place to apply your trade. This is a time of testing for you, so do not think you are not being watched constantly.\n\nIt is my duty to appraise the Hand of your skills, and to then inform them when I feel you are ready to move on to greater challenges.\n\nWhen you are ready, come find me deep inside the Den. I'll be waiting for you there.\n\n-Rwag, Rogue Trainer "
stub.ShowPage({ title = "Encrypted Tablet", number = 1, text = string.format(TABLET, "brother") })
Expect("a page with the gender word for a man is found", B:PageOnScreen(), 2438)
stub.ShowPage({ title = "Encrypted Tablet", number = 1, text = string.format(TABLET, "sister") })
Expect("...and for a woman", B:PageOnScreen(), 2438)

local NOTE = "Many tribes claim that it is a gift to be blessed with the aptitude to use magic or to talk to our ancestors, but you should know this as well, Warrior, you are just as gifted. Some do not have the strength in their arms to wield mighty weapons. Some do not have the skill to parry a blow from an assassin, or to even suffer the physical punishments from an arcane spellcaster, but you do. You are strong. And I will help you become stronger. Find me in Camp Narache.\n\n-Harutt Thunderhorn, Warrior Trainer"
stub.ShowPage({ title = "Simple Note", number = 1, text = NOTE })
Expect("a class letter with the reader's class in it is found", B:PageOnScreen(), 2441)

world.playerName, world.playerClass, world.playerRace, world.unitSex = "Torno", "Warrior", "Orc", 3
Expect("a caption filled in for this character, as the page shows it",
    B:FillPlayerTokens("Greetings, $gbrother:sister;. Tell me, $c, have you met $N the $r?"),
    "Greetings, sister. Tell me, Warrior, have you met Torno the Orc?")
Expect("a caption as the narrator says it: the first side, adventurer, traveler, capitalised at a sentence's start",
    B:SaidTokens("$N, Before I go. Greetings, $g brother : sister;. Tell me, $c, have you met the $r? $N!"),
    "Adventurer, Before I go. Greetings, brother. Tell me, adventurer, have you met the traveler? Adventurer!")
world.playerName, world.playerClass, world.playerRace, world.unitSex = nil, nil, nil, 2

print(Failures() == 0 and "All readables reader tests passed" or (Failures() .. " failed"))
os.exit(Failures() == 0 and 0 or 1)
