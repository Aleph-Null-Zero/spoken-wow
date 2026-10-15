setfenv(1, SpokenEnv)

-- The DialogueUI settings on Spoken's page: the window's own rows, shown only with the
-- DialogueUI style, then, after the narrator style's settings, the rows feature addons add
-- through Spoken:AddDialogueUISettings, shown under any style.
--
-- Parsed by the 1.12 client too (addon.xml is shared), so Lua 5.0 syntax throughout; that
-- client has no DialogueUI and returns below.

DialogueUIOptions = { builders = {}, resets = {} }

if Version.IsAnyLegacy then
    function DialogueUIOptions:Add() end
    function DialogueUIOptions:ThemeRows() end
    function DialogueUIOptions:FitRow() end
    function DialogueUIOptions:Place() end
    function DialogueUIOptions:Reset() end
    function DialogueUIOptions:WordRowsShown(style) return style ~= "none" end
    return
end

local Page = DialogueUIOptions

local function Panel() return Addon.db.profile.Frame.DialogueUI end

function Page:Add(build)
    table.insert(self.builders, build)
    if self.keep then
        self:Run(build)
        Options:UpdateRows()
    end
end

function Page:Run(build)
    local layout = self.layout
    local ok, reset = pcall(layout.Fill, layout, self.keep, build)
    if ok and type(reset) == "function" then
        table.insert(self.resets, reset)
    elseif not ok then
        table.insert(Callbacks.errors, "DialogueUI settings: " .. tostring(reset))
    end
end

local function Window(layout, only, row)
    only(row)
    layout:Requires(row, function() return DialogueUITheme:Available() end, L.OPT_STYLE_DUI_UNKNOWN)
    return row
end

function Page:ThemeRows(layout, only, refresh)
    Window(layout, only, layout:Checkbox(L.OPT_DUI_FOLLOW_THEME, L.OPT_DUI_FOLLOW_THEME_TIP,
        function() return Panel().FollowTheme end, function(v) Panel().FollowTheme = v end, refresh))
    layout:Indent()
    layout:Requires(Window(layout, only, layout:Dropdown(L.OPT_DUI_THEME, L.OPT_DUI_THEME_TIP, { 1, 2 },
        function() return Panel().Theme end, function(v) Panel().Theme = v end, refresh,
        function(v) return v == 2 and L.OPT_DUI_THEME_DARK or L.OPT_DUI_THEME_PARCHMENT end)),
        function() return not Panel().FollowTheme end, L.REASON_DUI_FOLLOW)
    layout:Outdent()
end

function Page:FitRow(layout, only, refresh)
    return Window(layout, only, layout:Checkbox(L.OPT_DUI_FIT_TEXT, L.OPT_DUI_FIT_TEXT_TIP,
        function() return Panel().FitText ~= false end, function(v) Panel().FitText = v end, refresh))
end

--- Where the feature addons' rows go, after the narrator style's settings, now or whenever they
--- arrive. They show under any style, since they change DialogueUI's own quest window.
function Page:Place(layout)
    if not DialogueUITheme:Installed() then return end
    self.layout = layout
    self.keep = layout:Keep()
    for _, build in ipairs(self.builders) do self:Run(build) end
end

--- Whether Show Words, Highlight Words and Type Words Out are offered under narrator style `style`:
--- under every style that shows words, and under Voice Only too while DialogueUI is installed, as
--- they mark DialogueUI's own quest, gossip and book text (Spoken:GetCaption).
function Page:WordRowsShown(style)
    return style ~= "none" or DialogueUITheme:Installed() and true or false
end

--- Spoken's Start Over, before its reload: the window's settings back, and every feature
--- addon's, which Spoken's profile does not hold.
function Page:Reset()
    local cfg = Panel()
    for key, value in pairs(Defaults.profile.Frame.DialogueUI) do cfg[key] = value end
    for _, reset in ipairs(self.resets) do pcall(reset) end
end
