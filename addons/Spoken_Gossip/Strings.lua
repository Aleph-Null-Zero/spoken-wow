if not SpokenGossipEnv then return end
setfenv(1, SpokenGossipEnv)

-- Interface strings for Spoken Gossip, and the key set every other language is measured
-- against. A locale file per language overlays this table (Locale/<code>.lua), so anything
-- missing falls back to English at runtime.
--
-- FORMAT ARGUMENTS ARE POSITIONAL (%1$s, %2$d), even where there is only one and the position is
-- obvious. Word order is the thing a translator most often has to change and least often can.
--
-- The windows' Listen and Contribute buttons and the Report action are the dialogue core's, in
-- Spoken's strings (DIALOGUE_*).

L = {}

L.OPT_PAGE_TITLE = "Gossip"
L.OPT_PANEL_GREETINGS = "Read Greetings"
L.OPT_GREETING_LABEL_ALWAYS = "Every Time"
L.OPT_GREETING_LABEL_ONCE_QUEST = "Once for Quest Givers"
L.OPT_GREETING_LABEL_ONCE_NPC = "Once per NPC"
L.OPT_GREETING_LABEL_NEVER = "Never"
L.OPT_PANEL_STOP_ON_CLOSE = "Stop When Gossip Closes"
L.OPT_OG_THRALL = "Original Thrall Speech"
L.OPT_OG_THRALL_TIP = "Plays AI VoiceOver's recording of Thrall's speech instead of Spoken's."
L.OPT_FORGET_GREETINGS = "Forget Greetings Heard"
L.REASON_FORGET_GREETINGS = "Set Read Greetings to Once per NPC or Once for Quest Givers to use this."
L.OPT_FORGET_GREETINGS_DONE = "This character's list of greetings heard is cleared."
L.OPT_PACK_GOSSIP = "Gossip"
L.OPT_PACK_INCLUDED = "In All Quests"
L.OPT_RESET_PROFILE_CONFIRM = "Reset every Gossip setting in the profile in use to its default?"
L.OPT_MINIMAP_SETTINGS = "Gossip Settings"
L.OPT_GREETING = "Greeting"
L.OPT_NEVER_TIP = "Read Greetings is set to Never on the Gossip page of the Spoken settings."
L.OPT_GROUP_GENERAL = "General"
L.OPT_CMD_GROUP = "Commands"
L.OPT_CMD_READ = "Read Open Window"
L.OPT_CMD_READ_DESC = "Reads the greeting or gossip window that is open"
L.OPT_CMD_OPTIONS = "Settings"
L.OPT_CMD_OPTIONS_DESC = "Opens this module's settings page"
L.OPT_CMD_TEST = "Play a Test Line"
L.OPT_CMD_TEST_DESC = "Plays a known NPC line to check that you can hear it"
L.OPT_CMD_DIAG = "Show Diagnostics"
L.OPT_CMD_DIAG_DESC = "Prints client, API and voice pack status"
