-- Spoken's controls on DialogueUI's book view (UI/DialogueUIBook.lua), against a fake
-- DUIBookFrame. The queue is the real Spoken one. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local SPOKEN = here .. "/../../addons/Spoken/"
local BOOKS = here .. "/../../addons/Spoken_Books/"
local Expect, Failures = H.Expecter(print)

-- The Hillsbrad Town Registry: four real pages of one real book, 261 through 265; a pack with
-- the first three.
local REGISTRY = { 261, 262, 263, 265 }
_G.SpokenBooksAudioPacks = {
    SpokenBooksAudio = {
        version = 1, addon = "SpokenBooksAudio", quality = "high", bitrate = 128,
        pages = { [261] = { file = "261", len = 30.5 }, [262] = { file = "262", len = 41.0 },
            [263] = { file = "263", len = 20.0 } },
    },
}

local function LoadBooks()
    local SpokenBooks = {}
    for _, file in ipairs({ "Locale/enUS", "Checksum", "Core", "Language", "Reader", "Audio", "Playlist", "UI/CopyLink",
        "UI/DialogueUIBook" }) do
        local chunk = assert(loadfile(BOOKS .. file .. ".lua"))
        chunk("Spoken_Books", SpokenBooks)
    end
    return SpokenBooks
end

stub.SetClient("11509"); stub.ResetSound(); stub.ResetTimers()
_G.SpokenBooksSettings = nil
local env = stub.LoadSpoken(SPOKEN)
env.Addon:Enable()

-- DialogueUI's book view: no parent, drawn at 0.8, its close button in its top right, its own
-- speaker in its top left.
local view = stub.Widget("Frame")
view.GetEffectiveScale = function() return 0.8 end
view.CloseButton = stub.Widget("Button")
view.TTSButton = stub.Widget("Button")
view.TTSButton:SetAlpha(0.6)
view:Hide()
_G.DUIBookFrame = view

local B = LoadBooks()
B:InitDB()
B:SetupSource()
dofile(BOOKS .. "Data/Books.lua")
B:SetupDialogueUIBook()
local Book = B.DialogueUIBook
local watch = Book.watch

local function QueuedPages()
    local pages = {}
    for _, clip in ipairs(Spoken:GetQueue()) do
        if clip.pageId then table.insert(pages, clip.pageId) end
    end
    return table.concat(pages, ",")
end

---------------------------------------------------------------- the row
-- DialogueUI loads every page as it opens the book and leaves the game on the last.
B.lastPage = 265
view:Show()
watch.scripts.OnShow(watch)
local row = Book.row
Expect("the book view opening shows Spoken's controls on it", row ~= nil and row.frame:IsShown()
    and row.frame:GetParent() == view, true)
Expect("...Play, Skip and Report, the player's round buttons", row.play.ring ~= nil and row.skip.bar ~= nil
    and row.report:IsShown(), true)
Expect("...left of the book's close button", row.frame.anchor.point .. " " .. tostring(row.frame.anchor.relativeTo
    == view.CloseButton) .. " " .. row.frame.anchor.relativePoint .. " " .. row.frame.anchor.x, "RIGHT true LEFT -4")
Expect("...Report rightmost, then Skip, then Play", row.report.anchor.relativeTo == row.frame
    and row.skip.anchor.relativeTo == row.report and row.play.anchor.relativeTo == row.skip, true)
Expect("...as large on screen as Place Lore draws them, 24 at UIParent's scale",
    row.play:GetWidth() .. " " .. row.play:GetScale(), "24 " .. (UIParent:GetEffectiveScale() / 0.8))
Expect("...in place of DialogueUI's own speaker", view.TTSButton:GetAlpha(), 0)
Expect("Play is lit for a book with a recording", row.play:IsEnabled(), true)
Expect("Skip is greyed with nothing speaking", row.skip:IsEnabled(), false)

---------------------------------------------------------------- playing it
row.play.scripts.OnClick(row.play, "LeftButton")
Expect("Play reads the book from its first page, not the last the game is on", QueuedPages(), "261,262,263")
Book:Draw()
Expect("...and turns to Stop while it reads", row.play.state, "stop")
Expect("...Skip lit", row.skip:IsEnabled(), true)
row.play.scripts.OnEnter(row.play)
Expect("its tooltip is on the book view, which DialogueUI's hiding of the interface leaves up",
    row.play.tooltip ~= nil and row.play.tooltip:GetParent() == view and row.play.tooltip.text, B.L.STOP_TIP)
row.play.scripts.OnLeave(row.play)
row.report.scripts.OnClick(row.report)
local box = Spoken.ContributeBox
Expect("Report gives the address for the page being read, in Spoken's box",
    box and box.editBox:GetText(), B:ReportURL(261))
row.play.scripts.OnClick(row.play, "LeftButton")
Expect("Stop stops it", QueuedPages(), "")
Book:Draw()
Expect("...and Stop turns back to Play", row.play.state, "play")
local autoplay = SpokenBooksSettings.autoplay
row.play.scripts.OnClick(row.play, "RightButton")
Expect("right-click switches Read Automatically", SpokenBooksSettings.autoplay, not autoplay)
row.play.scripts.OnClick(row.play, "RightButton")

---------------------------------------------------------------- a book with no recording
B.lastPage = 2810
Book:Draw()
Expect("a book no pack voices greys Play", row.play:IsEnabled(), false)
Expect("...and has nothing to report", row.report:IsShown(), false)
Expect("...Skip and Play moving up to the close button", row.skip.anchor.relativeTo, row.frame)

---------------------------------------------------------------- closing
view:Hide()
watch.scripts.OnHide(watch)
Expect("the book view closing takes the row with it", row.frame:IsShown(), false)
Expect("...and gives DialogueUI's speaker back", view.TTSButton:GetAlpha(), 0.6)

if Failures() > 0 then
    print(string.format("\n%d book view test(s) failed", Failures()))
    os.exit(1)
end
print("\nAll book view tests passed")
