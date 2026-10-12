-- Which quests' recordings have been heard through, kept for the whole account, and the quiet
-- mark the Quests tab of Azeroth's Compendium shows on them: on the row, and on the page under
-- Play. A quest is heard once every part the voice packs have of it (offer, progress, hand-in)
-- has played to its end, or been skipped with most of it heard.
--
-- Not under setfenv(1, VoiceOver), as UI/QuestsTab.lua is not: the frames are built here.

local VO = VoiceOver
local QuestsTab = VO.QuestsTab
local L = VO.L

-- A part skipped this far in counts as heard: the last words are often a sign-off.
local MOSTLY = 0.8
-- The tick every client has; Spoken ships no glyph for it.
local MARK = [[Interface\Buttons\UI-CheckBox-Check]]
-- The page's ink, so the mark reads as written on the parchment.
local INK = { 0.25, 0.16, 0.08 }

local MOMENTS = { "accept", "progress", "complete" }
local EVENTS = { accept = VO.Enums.SoundEvent.QuestAccept, progress = VO.Enums.SoundEvent.QuestProgress,
    complete = VO.Enums.SoundEvent.QuestComplete }
local MOMENT_OF = {}
for moment, event in pairs(EVENTS) do MOMENT_OF[event] = moment end

-- SpokenQuestsSettings.global.CompendiumHeard[questID] = { accept = true, ... }
local function Store(create)
    local db = VO.Addon and VO.Addon.db and VO.Addon.db.global
    if not db then return nil end
    if create and not db.CompendiumHeard then db.CompendiumHeard = {} end
    return db.CompendiumHeard
end

local function Voiced(id, moment)
    return VO.DataModules:PrepareSound({ event = EVENTS[moment], questID = id }) and true or false
end

--- Whether every part of `questID`'s recording the voice packs have has been heard through.
function QuestsTab:IsHeard(questID)
    local store = Store()
    local heard = store and store[questID]
    if not heard then return false end
    for _, moment in ipairs(MOMENTS) do
        if not heard[moment] and Voiced(questID, moment) then return false end
    end
    return true
end

-- How much of `clip` was heard before it was taken away. Stopped first, it is silent already and
-- its start time is stale.
local function MostlyHeard(clip)
    local length = tonumber(clip.length) or 0
    if length <= 0 or not clip.spokenAt or (Spoken.IsPaused and Spoken:IsPaused()) then return false end
    return length - (clip.spokenAt - GetTime()) >= MOSTLY * length
end

local function OnStopped(clip, finished)
    if not clip or clip.source == nil or clip.source ~= VO.Player.source then return end
    local moment = MOMENT_OF[clip.event]
    if not moment or not clip.questID or not (finished or MostlyHeard(clip)) then return end
    local store = Store(true)
    if not store then return end
    store[clip.questID] = store[clip.questID] or {}
    if store[clip.questID][moment] then return end
    store[clip.questID][moment] = true
    if QuestsTab.panel and QuestsTab.panel:IsVisible() then QuestsTab:Refresh() end
end

if _G.Spoken and Spoken.RegisterCallback then
    Spoken:RegisterCallback("CLIP_STOPPED", OnStopped)
end

--------------------------------------------------------------------------------
-- The mark
--------------------------------------------------------------------------------

local function ShowTip(mark)
    GameTooltip:SetOwner(mark, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.QUEST_HEARD)
    GameTooltip:AddLine(L.QUEST_HEARD_TIP, 1, 1, 1, true)
    GameTooltip:Show()
end

-- A mark over a row would take the row's pointer and clicks: both are handed on to it.
local function NewMark(parent, size, row)
    local mark = CreateFrame("Frame", nil, parent)
    mark:SetSize(size, size)
    mark:EnableMouse(true)
    mark.icon = mark:CreateTexture(nil, "OVERLAY")
    mark.icon:SetAllPoints()
    mark.icon:SetTexture(MARK)
    mark:SetScript("OnEnter", function(self)
        local enter = row and row:GetScript("OnEnter")
        if enter then enter(row) end
        ShowTip(self)
    end)
    mark:SetScript("OnLeave", function()
        GameTooltip:Hide()
        local leave = row and row:GetScript("OnLeave")
        if leave then leave(row) end
    end)
    if row then
        if mark.SetPropagateMouseClicks then
            mark:SetPropagateMouseClicks(true)
        else
            mark:SetScript("OnMouseUp", function(_, button)
                local click = row:GetScript("OnClick")
                if click then click(row, button or "LeftButton") end
            end)
        end
    end
    mark:Hide()
    return mark
end

local function MarkRow(row, item)
    if item.kind ~= "quest" or not QuestsTab:IsHeard(item.quest) then
        if row.heardMark then row.heardMark:Hide() end
        return
    end
    local mark = row.heardMark
    if not mark then
        mark = NewMark(row, 12, row)
        if mark.icon.SetDesaturated then mark.icon:SetDesaturated(true) end
        mark.icon:SetAlpha(0.6)
        row.heardMark = mark
    end
    mark:ClearAllPoints()
    if row.lock and row.lock:IsShown() then
        mark:SetPoint("RIGHT", row.lock, "LEFT", -4, 0)
    else
        mark:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    end
    row.label:SetPoint("RIGHT", mark, "LEFT", -4, 0)
    mark:Show()
end

local function MarkPage(page, questID)
    local mark = page.heardMark
    if not mark then
        mark = NewMark(page.frame, 14)
        if mark.icon.SetDesaturated then mark.icon:SetDesaturated(true) end
        mark.icon:SetVertexColor(INK[1], INK[2], INK[3])
        -- Under Play, at the end of the line under the title, which stops short of it.
        if page.play then
            mark:SetPoint("TOP", page.play, "BOTTOM", 0, -2)
        else
            mark:SetPoint("TOPRIGHT", page.title, "BOTTOMRIGHT", 34, -2)
        end
        page.sub:SetPoint("RIGHT", mark, "LEFT", -4, 0)
        page.heardMark = mark
    end
    mark:SetShown(questID ~= nil and QuestsTab:IsHeard(questID))
end

--- The mark on every quest row heard through, and on the page of `questID` if it is.
function QuestsTab:MarkHeard(list, items, page, questID)
    for i, item in ipairs(items or {}) do
        local row = list.rows[i]
        if row then MarkRow(row, item) end
    end
    if page then MarkPage(page, questID) end
end
