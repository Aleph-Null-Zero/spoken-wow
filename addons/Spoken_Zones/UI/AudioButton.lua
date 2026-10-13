-- SpokenZones -- the play/pause button shown next to a lore description.
--
-- A factory in the same shape as SpokenTextView.Create: anchor the returned
-- button yourself, then call SetTarget whenever the panel's content changes.
--
-- The player's own round button (Spoken:CreateRoundButton), the one its subtitle shows, so the
-- two are one button: Play to start the story, Stop while it is read, Replay once stopped, and
-- Play again when it has ended. Report sits beside it (SpokenZones:CreateReportIcon).

local ADDON_NAME, SpokenZones = ...

local L = SpokenZones.L

local AudioButton = {}

--------------------------------------------------------------------------------
-- The round button
--------------------------------------------------------------------------------

--- The player's round button: `kind` "play", "report", or "icon" with the texture `icon`.
function SpokenZones:CreateRoundButton(parent, kind, icon)
	return Spoken:CreateRoundButton(parent, kind, nil, icon)
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- nil areaKey means the zone itself. Passing a nil mapID parks the button: it
-- has nothing to play, so it hides.
function AudioButton:SetTarget(mapID, areaKey)
	self.mapID = mapID
	self.areaKey = areaKey
	self:Refresh()
end

function AudioButton:Refresh()
	if not SpokenZones:IsVoiceEnabled() or not self.mapID then
		self:Hide()
		return
	end

	if not SpokenZones:HasAudio(self.mapID, self.areaKey) then
		self:Hide()
		return
	end

	self:Show()
	-- Stop while this story is read, Replay while it is stopped at the head, Play otherwise.
	local state = "play"
	if SpokenZones:IsLoreAtHead(self.mapID, self.areaKey) and SpokenZones:IsPaused() then
		state = "replay"
	elseif SpokenZones:IsPlayingLore(self.mapID, self.areaKey) then
		state = "stop"
	end
	self:SetState(state)
end

-- The tooltip for the button's state, in Spoken's words as every Play of the Compendium's has
-- them; ours where Spoken is missing, and nothing then plays. Play says what is read.
local function Tooltip(button)
	local words = _G.SpokenEnv and _G.SpokenEnv.L or {}
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	if button.state == "stop" then
		GameTooltip:SetText(words.STOP or L.STOP)
		GameTooltip:AddLine(words.STOP_READING_TIP or L.STOP_TOOLTIP, 1, 0.8, 0.2, true)
	elseif button.state == "replay" then
		GameTooltip:SetText(words.REPLAY or L.REPLAY)
		GameTooltip:AddLine(words.REPLAY_READING_TIP or L.REPLAY_TOOLTIP, 1, 0.8, 0.2, true)
	else
		GameTooltip:SetText(words.PLAY or L.PLAY)
		GameTooltip:AddLine(L.AUDIO_READ_TIP, 1, 0.8, 0.2, true)
	end
	GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function SpokenZones:CreateAudioButton(parent)
	local button = SpokenZones:CreateRoundButton(parent, "play")
	button:Hide()

	button.SetTarget = AudioButton.SetTarget
	button.Refresh = AudioButton.Refresh

	-- This story speaking, or at the head of the queue and paused: pause or resume it, as the
	-- subtitle's button does. Anything else, including this story at the head unstarted because
	-- a gate holds it (combat, a cinematic): start it. Toggling then would pause the whole queue.
	button:SetScript("OnClick", function(self)
		if not self.mapID then
			return
		end
		if SpokenZones:IsPlayingLore(self.mapID, self.areaKey)
			or (SpokenZones:IsLoreAtHead(self.mapID, self.areaKey) and SpokenZones:IsPaused()) then
			SpokenLayout.Sound("U_CHAT_SCROLL_BUTTON")
			_G.Spoken:TogglePause()
		else
			SpokenZones:PlayLore(self.mapID, self.areaKey)
		end
		self:Refresh()
		if GameTooltip:GetOwner() == self then Tooltip(self) end
	end)

	button:HookScript("OnEnter", Tooltip)

	button:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Both panels can show the same entry at once, and either can start playback,
	-- so every button re-reads the shared state rather than tracking its own.
	SpokenZones:OnAudioChanged(function()
		button:Refresh()
	end)

	return button
end
