-- The gossip module's settings page: nested under Spoken's beside the other modules', laid out by
-- Spoken's UI/Layout.lua. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local GOSSIP = here .. "/../../addons/Spoken_Gossip/"
local SPOKEN = here .. "/../../addons/Spoken/"
local Expect, Failures = H.Expecter(print)

stub.SetClient("16001"); stub.ResetSound(); stub.ResetTimers(); stub.ResetFrames()
stub.settingsCategories = {}; stub.ldbObjects = {}; stub.dbIcons = {}
stub.world.questID = 0; stub.ShowPanel(nil)
_G.SpokenGossipSettings = nil
-- Installed: the Gossip pack, and Alliance's, which holds no gossip.
stub.SetAddOns({
    { folder = "SpokenQuestsAudioGossip", meta = { ["X-VoiceOver-DataModule-Version"] = "1", Version = "2.2.0",
        Title = "Spoken Quests Audio: Gossip" } },
    { folder = "SpokenQuestsAudioAlliance", meta = { ["X-VoiceOver-DataModule-Version"] = "1", Version = "2.2.0",
        Title = "Spoken Quests Audio: Alliance" } },
})
local G = stub.LoadGossip(GOSSIP, SPOKEN)
G.Addon:OnInitialize()
_G.SpokenEnv.Addon:Enable()
local SettingsPanel = stub.LoadGossipPanel(GOSSIP, G)
SettingsPanel:Setup()
local L = G.L

Expect("the page is registered", SettingsPanel.page and SettingsPanel.page.category ~= nil, true)
local mine = 0
for _, registered in ipairs(stub.settingsCategories) do
    if registered.name == "Gossip" then mine = mine + 1 end
end
Expect("...as an entry named Gossip", mine, 1)
Expect("...nested under Spoken's", SettingsPanel.page.category.parent and SettingsPanel.page.category.parent.name, "Spoken")

local content = SettingsPanel.panel.content
local headings, buttons = {}, {}
for _, child in ipairs(content.children) do
    if child.layoutHeading then
        table.insert(headings, child.text)
    elseif type(child.text) == "string" and child.text ~= "" and child.scripts and child.scripts.OnClick then
        table.insert(buttons, child)
    end
end
Expect("every section is there", table.concat(headings, "|"), "When to Read|Voice Packs|Reading History")
local W = _G.Spoken:Words()
local function Button(text)
    for _, button in ipairs(buttons) do if button.text == text then return button end end
end
-- Diagnostics and Report a Problem are on Spoken's page, for every module at once.
Expect("the voice packs end with Play a Test Line, as on every module's page",
    tostring(Button(W.MODULE_TEST_LINE) ~= nil) .. " " .. tostring(Button(W.DIALOGUE_REPORT_PROBLEM) ~= nil), "true false")

---------------------------------------------------------------- NPC Greetings
local db = G.Addon.db.profile
local greetings
for _, child in ipairs(content.children) do
    if child.dropdownInit and child.layoutLabel and child.layoutLabel.text == L.OPT_PANEL_GREETINGS then
        greetings = child
    end
end
Expect("Read Greetings is a dropdown", greetings ~= nil, true)
greetings:GetScript("OnShow")(greetings)
Expect("...showing Once per NPC to start with", greetings.dropdownText, L.OPT_GREETING_LABEL_ONCE_NPC)
local offered = {}
for _, entry in ipairs(stub.OpenDropdown(greetings)) do table.insert(offered, entry.text) end
Expect("...offering every choice at once, from reading the most to the least", table.concat(offered, "|"),
    "Every Time|Once per NPC|Once for Quest Givers|Never")
-- Live whatever the quests module's autoplay is: this page has no autoplay to grey it.
Expect("...live, with no switch above it to grey it", greetings.dropdownDisabled or false, false)
Expect("picking Never is possible", stub.PickDropdown(greetings, "Never"), true)
Expect("...and stores the number the addon reads", db.Audio.GossipFrequency, G.Enums.GossipFrequency.Never)
Expect("...which the Listen button follows", G.Addon:IsNever(), true)
stub.PickDropdown(greetings, "Once per NPC")

---------------------------------------------------------------- forgetting greetings
G.Addon.db.char.hasSeenGossipForNPC = { ["Creature-0-0-0-0-12345-0"] = true }
local forget
for _, button in ipairs(buttons) do if button.text == L.OPT_FORGET_GREETINGS then forget = button end end
Expect("Forget Greetings Heard is a button", forget ~= nil, true)
-- It only matters while a greeting is read once.
stub.PickDropdown(greetings, "Every Time"); SettingsPanel.panel.layout:Refresh()
Expect("...greyed while every greeting is read each time, saying why", forget.layoutReason, L.REASON_FORGET_GREETINGS)
stub.PickDropdown(greetings, "Once per NPC"); SettingsPanel.panel.layout:Refresh()
Expect("...and live with a greeting read once", forget.layoutReason, nil)
forget.scripts.OnClick(forget)
Expect("...which clears this character's greetings heard", next(G.Addon.db.char.hasSeenGossipForNPC), nil)

---------------------------------------------------------------- the packs that hold gossip
local rows = {}
for _, item in ipairs(SettingsPanel.panel.layout.items) do
    if item.kind == "section" and item.text == W.PART_VOICE then
        for _, row in ipairs(item.rows) do
            local caption = row.regions and row.regions[4]
            if row.shown and caption and caption.text then table.insert(rows, caption.text) end
        end
    end
end
Expect("the pack offered is English's that holds gossip, named by its language, not the retired complete pack",
    table.concat(rows, "|"), "English")
Expect("...the card counts only the installed one that does", _G.Spoken:PartStatus("gossip") ~= nil, true)
Expect("the minimap menu heads its entries with the page's name, in the player's language",
    _G.Spoken:GetSource("gossip").title, L.OPT_PAGE_TITLE)
local packs = _G.Spoken:GetSource("gossip").packs()
Expect("...Alliance's not among them", table.concat(packs, "|"), "Spoken Quests Audio: Gossip")

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll gossip options tests passed")
