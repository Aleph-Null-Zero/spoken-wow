setfenv(1, VoiceOver)

-- Gossip's page in the interface settings, beside Quests', laid out by UI/Layout.lua. What an
-- NPC says when you start talking to them is a part of its own on Spoken's page, with its own
-- switch; the settings that only it has are here. Absent on the three legacy clients, which
-- have no Settings API: the window and /spq are the interface there.

GossipSettingsPanel = {}

-- The game's settings list sets its rows 25 in from the canvas's left.
local INDENT = 25
local ICON = [[Interface\Icons\UI_Chat]]
local panel, category

-- The enum is stored as a number and read as a name. Ordered, because a cycle button
-- steps through them in the order the list is written.
local GOSSIP_ORDER = { "Always", "OncePerQuestNPC", "OncePerNPC", "Never" }
local GOSSIP_LABELS = {
    Always = L.OPT_GREETING_LABEL_ALWAYS,
    OncePerQuestNPC = L.OPT_GREETING_LABEL_ONCE_QUEST,
    OncePerNPC = L.OPT_GREETING_LABEL_ONCE_NPC,
    Never = L.OPT_GREETING_LABEL_NEVER,
}

local function GossipName()
    return Enums.GossipFrequency:GetName(Addon.db.profile.Audio.GossipFrequency) or "Always"
end

function GossipSettingsPanel:Setup()
    if panel or not (Settings and Settings.RegisterCanvasLayoutCategory) then
        return
    end
    panel = CreateFrame("Frame", "SpokenGossipOptionsPanel", UIParent)
    panel.name = "Spoken Gossip"

    -- The settings canvas is a fixed size and neither scrolls nor clips what overflows
    -- it, so a panel with more rows than fit draws them over the game world.
    local scroller = SpokenLayout.Scroll(panel)
    local content = scroller.child

    local layout = SpokenLayout.New(content, INDENT, -16)
    panel.layout = layout
    local audio = function() return Addon.db.profile.Audio end
    local refresh = function() layout:Refresh() end
    layout:Header(L.OPT_GOSSIP_PAGE_TITLE, L.OPT_GOSSIP_PANEL_NOTE, nil, ICON)

    -- The part's own switch first, as on Spoken's page: off, everything under it is greyed
    -- out and says why, rather than looking live and doing nothing.
    local switch
    local function PartOn() return Addon:IsPartOn("gossip") end
    if Spoken and Spoken.SettingsStyle and Spoken:SettingsStyle() == "pages" then
        layout:HideHeader()
        layout:Intro(ICON, L.OPT_GOSSIP_PAGE_TITLE)
        switch = layout:Checkbox(L.OPT_PART_SWITCH, L.OPT_GOSSIP_PART_SWITCH_TIP, PartOn,
            function(value) Spoken:SetPartOn("gossip", value) end, refresh)
    else
        if Spoken and Spoken.PartStatus then
            layout:Status(function() return Spoken:PartStatus("gossip") end)
        end
        if Spoken and Spoken.IsPartOn then
            switch = layout:Checkbox(L.OPT_PART_SWITCH, L.OPT_GOSSIP_PART_SWITCH_TIP, PartOn,
                function(value) Spoken:SetPartOn("gossip", value) end, refresh)
        end
    end

    -- Both wait on Read Automatically, which is Quests' page's and covers every NPC window:
    -- they only decide what that reads, and a live control that does nothing reads as broken.
    layout:Section(L.OPT_SECTION_DIALOGUE)
    local greetings = layout:Dropdown(L.OPT_PANEL_GREETINGS, L.OPT_PANEL_GREETINGS_TIP,
        GOSSIP_ORDER,
        GossipName,
        function(name)
            Addon.db.profile.Audio.GossipFrequency = Enums.GossipFrequency[name]
        end,
        nil,
        function(name) return GOSSIP_LABELS[name] or name end)
    layout:Requires(greetings, function() return Addon:IsAutoplayOn() end, L.REASON_AUTOPLAY_ON_QUESTS)
    -- Only what autoplay reads waits for the greeting, so with it off this does nothing.
    local greetingFirst = layout:Checkbox(L.OPT_PANEL_GAME_GREETING_FIRST,
        L.OPT_PANEL_GAME_GREETING_FIRST_TIP,
        function() return audio().GreetingFirst end,
        function(value)
            audio().GreetingFirst = value
            if value then GreetingFirst:SetDialogApart() end
        end)
    layout:Requires(greetingFirst, function() return Addon:IsAutoplayOn() end, L.REASON_AUTOPLAY_ON_QUESTS)

    layout:Section(L.OPT_SECTION_EXTRAS)
    layout:Checkbox(L.OPT_OG_THRALL,
        L.OPT_OG_THRALL_TIP,
        function() return audio().OGThrall end,
        function(value) audio().OGThrall = value end)

    -- What this character has heard: forgotten, every NPC greets again.
    layout:Section(L.OPT_SECTION_HISTORY)
    layout:Button(L.OPT_FORGET_GREETINGS, 200, function()
        local char = Addon.db and Addon.db.char
        if char then char.hasSeenGossipForNPC = {} end
        print("|cFF00CCFFSpoken Gossip:|r " .. L.OPT_FORGET_GREETINGS_DONE)
    end, L.OPT_FORGET_GREETINGS_TIP)

    -- Switched off, the part is off: everything on its page greys out but its own switch.
    layout:RequiresAll(PartOn, L.REASON_PART_OFF, switch)
    content:SetScript("OnShow", function() layout:Refresh() end)
    -- Switched on or off from Spoken's page while this one was hidden: drawn again for it.
    if Spoken and Spoken.RegisterCallback then
        Spoken:RegisterCallback("PART_SWITCHED", function(part) if part == "gossip" then layout:Refresh() end end)
    end

    -- Derived rather than written down: a hardcoded height is a number nobody updates
    -- when a row is added, and the failure it produces is a section you cannot reach.
    scroller:SetContentHeight(layout:Height() + 40)
    panel.content = content

    -- Under Spoken's own entry when the player can nest it, beside the other parts' pages;
    -- a top-level entry of its own otherwise.
    layout:Refresh()
    local page = Spoken and Spoken.AddSettingsPage
        and Spoken:AddSettingsPage(panel, L.OPT_GOSSIP_PAGE_TITLE, 2, layout, scroller)
    if page then
        self.page = page
    else
        category = Settings.RegisterCanvasLayoutCategory(panel, "Spoken Gossip")
        Settings.RegisterAddOnCategory(category)
    end
    self.panel, self.category = panel, category
end

function GossipSettingsPanel:Open()
    -- Nested under Spoken's entry: Spoken opens this page.
    if self.page and self.page.Open and self.page.Open() then return true end
    local category = category or (self.page and self.page.category)
    return SpokenLayout ~= nil and SpokenLayout.OpenCategory(category)
end
