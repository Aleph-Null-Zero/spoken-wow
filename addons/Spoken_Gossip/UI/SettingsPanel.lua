if not SpokenGossipEnv then return end
setfenv(1, SpokenGossipEnv)

-- The module's page in the game's settings, under Spoken's, laid out by Spoken's UI/Layout.lua so
-- the pages read alike. Absent on the three legacy clients, which have no Settings API: the
-- options window and /spg are the interface there (Options.lua).

SettingsPanel = {}

-- The game's settings list sets its rows 25 in from the canvas's left.
local INDENT = 25

-- A language's name as Spoken lists it for every module: its own, in English where the font
-- cannot draw it.
local function LanguageName(code)
    if Spoken and Spoken.LanguageName then return Spoken:LanguageName(code) end
    return Language:GetNativeName(code)
end
local ICON = [[Interface\Icons\UI_Chat]]
local panel

-- The enum is stored as a number and read as a name. Ordered as the menu lists them: from
-- reading the most to the least.
local GOSSIP_ORDER = { "Always", "OncePerNPC", "OncePerQuestNPC", "Never" }
local GOSSIP_LABELS = {
    Always = L.OPT_GREETING_LABEL_ALWAYS,
    OncePerQuestNPC = L.OPT_GREETING_LABEL_ONCE_QUEST,
    OncePerNPC = L.OPT_GREETING_LABEL_ONCE_NPC,
    Never = L.OPT_GREETING_LABEL_NEVER,
}

local function GossipName()
    return Enums.GossipFrequency:GetName(Addon.db.profile.Audio.GossipFrequency) or "Always"
end

function SettingsPanel:Setup()
    if panel or not (Settings and Settings.RegisterCanvasLayoutCategory) then
        return
    end
    panel = CreateFrame("Frame", "SpokenGossipOptionsPanel", UIParent)
    panel.name = "Spoken Gossip"
    -- The words every module's page shares, kept in Spoken.
    local W = Spoken:Words()

    -- The settings canvas is a fixed size and neither scrolls nor clips what overflows
    -- it, so a panel with more rows than fit draws them over the game world.
    local scroller = SpokenLayout.Scroll(panel)
    local content = scroller.child

    local layout = SpokenLayout.New(content, INDENT, -16)
    panel.layout = layout
    local audio = function() return Addon.db.profile.Audio end
    local refresh = function() layout:Refresh() end

    -- Its own entry under Spoken's, with the module's switch first: off, everything under it is
    -- greyed out and says why, rather than looking live and doing nothing.
    local function PartOn() return Addon:IsPartOn() end
    layout:Intro(ICON, L.OPT_PAGE_TITLE)
    local switch = layout:Checkbox(W.MODULE_SWITCH, nil, PartOn,
        function(value) Spoken:SetPartOn("gossip", value) end, refresh)

    layout:Section(W.MODULE_WHEN)
    layout:Dropdown(L.OPT_PANEL_GREETINGS, nil,
        GOSSIP_ORDER,
        GossipName,
        function(name)
            Addon.db.profile.Audio.GossipFrequency = Enums.GossipFrequency[name]
            Addon:RefreshConfig()
        end,
        refresh,
        function(name) return GOSSIP_LABELS[name] or name end)
    layout:Checkbox(L.OPT_PANEL_STOP_ON_CLOSE, nil,
        function() return audio().StopAudioOnDisengage end,
        function(value) audio().StopAudioOnDisengage = value end)
    layout:Checkbox(L.OPT_OG_THRALL, L.OPT_OG_THRALL_TIP,
        function() return audio().OGThrall end,
        function(value) audio().OGThrall = value end)

    -- The packs that hold gossip, a row each named by its language: its version where it is
    -- installed, and where it is not, a button with the address to get it. Each language's one
    -- pack holds quests and gossip both, so those rows are the quests page's too.
    layout:Section(W.PART_VOICE)
    local ALL = "SpokenQuestsAudioAll"
    local function Present(name)
        for _, module in DataModules:GetPresentModules() do
            if module.AddonName == name then return module end
        end
    end
    local present = 0
    for _, module in DataModules:GetPresentModules() do
        if Player:HoldsGossip(module) then present = present + 1 end
    end
    if present == 0 then
        layout:Note(W.MODULE_NO_PACK, nil, 16)
    end
    -- No pack in the voice language, and nothing to fall back on: said here, or the page goes
    -- quiet with no word why.
    local silent = layout:Note("", nil, 32)
    layout:OnRefresh(function() silent:SetText(Spoken:SilentNote("quests") or "") end)
    layout:ShowWhen(silent, function() return Spoken:SilentNote("quests") ~= nil end)
    local listed = {}
    -- The packs to get are the voice language's; any pack installed is listed too. A voice
    -- language with no pack of its own is heard in the fallback's, so those are the ones to get
    -- there. Each row is built whatever is chosen and shown while it is wanted, so a change of
    -- language on Spoken's page shows at once.
    local function Wanted(code, addon)
        local voice = Language:GetVoiceLanguage()
        if code == voice or Present(addon) ~= nil then return true end
        local own = voice == Language.BASE or Spoken:VoicePack("quests", voice)
        return not own and code == Language:GetFallbackLanguage()
    end
    local function PackRow(module, label)
        listed[module.AddonName] = true
        return layout:Download(label or DataModules:GetPackLabel(module), function()
            local installed = Present(module.AddonName)
            if installed then
                if not DataModules:GetModule(module.AddonName) then return "warn", W.MODULE_NOT_LOADED end
                local version = installed.ContentVersion
                return "ok", (version and version ~= "") and version or W.MODULE_INSTALLED
            end
            if module.AddonName ~= ALL and Present(ALL) then return "off", L.OPT_PACK_INCLUDED end
        end, W.MODULE_DOWNLOAD, function() ReportButton:ShowAddress(module.URL) end)
    end
    for _, locale in ipairs(Language.LOCALES) do
        local folder, url = Spoken:VoicePack("quests", locale.code)
        if folder then
            local code = locale.code
            layout:ShowWhen(PackRow({ AddonName = folder, URL = url }, LanguageName(code)),
                function() return Wanted(code, folder) end)
        end
    end
    -- English's that holds gossip: the Gossip pack, named by its language as the others are. Not
    -- the retired complete pack, listed below only where a player still has it.
    for _, module in DataModules:GetAvailableModules() do
        if Player:HoldsGossip(module) and module.AddonName ~= ALL then
            layout:ShowWhen(PackRow(module, LanguageName(Language.BASE)),
                function() return Wanted(Language.BASE, module.AddonName) end)
        end
    end
    -- A pack the list does not know, after the ones it does.
    for _, module in DataModules:GetPresentModules() do
        if not listed[module.AddonName] and Player:HoldsGossip(module) then PackRow(module) end
    end
    layout:Button(W.MODULE_TEST_LINE, 200, function() Addon:RunSelfTest() end)
    content:SetScript("OnShow", function() layout:Refresh() end)
    -- Switched on or off from Spoken's page while this one was hidden: drawn again for it.
    Spoken:RegisterCallback("PART_SWITCHED", function(part) if part == "gossip" then layout:Refresh() end end)

    -- What this character has heard: forgotten, every NPC greets again. It only matters while
    -- a greeting is read once.
    layout:Section(W.MODULE_HISTORY)
    local forget = layout:Button(L.OPT_FORGET_GREETINGS, 200, function() Addon:ForgetGreetings() end)
    layout:Requires(forget, function()
        local name = GossipName()
        return name == "OncePerNPC" or name == "OncePerQuestNPC"
    end, L.REASON_FORGET_GREETINGS)

    -- Profiles are Spoken's, on its own page: one choice for every part.
    local db = Addon.db

    -- The page's Defaults, as Spoken's has.
    if db.ResetProfile then
        layout:Defaults(function()
            SpokenLayout.Confirm(L.OPT_RESET_PROFILE_CONFIRM, W.MODULE_RESET, W.CANCEL, function()
                db:ResetProfile()
                layout:Refresh()
            end)
        end, nil, W.OPT_RESET_ALL_TIP)
    end
    -- Switched off, the module is off: everything on its page greys out but its own switch.
    layout:RequiresAll(PartOn, W.REASON_PART_OFF, switch)

    -- Derived rather than written down: a hardcoded height is a number nobody updates
    -- when a row is added, and the failure it produces is a section you cannot reach.
    scroller:SetContentHeight(layout:Height() + 40)
    panel.content = content

    -- Under Spoken's own entry, beside the other modules' pages.
    layout:Refresh()
    self.page = Spoken:AddSettingsPage(panel, L.OPT_PAGE_TITLE, 2, layout, scroller)
    self.panel = panel
end

function SettingsPanel:Open()
    -- Nested under Spoken's entry: Spoken opens this page.
    return self.page ~= nil and self.page.Open() and true or false
end
