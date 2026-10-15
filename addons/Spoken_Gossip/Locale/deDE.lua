-- German interface strings for Spoken Gossip.
--
-- Keyed exactly as in Strings.lua; anything missing falls back to English.

if not SpokenGossipEnv then return end
setfenv(1, SpokenGossipEnv)

if GetLocale() ~= "deDE" then
	return
end

L.OPT_PAGE_TITLE = "Gespräche"
L.OPT_PANEL_GREETINGS = "Begrüßungen vorlesen"
L.OPT_GREETING_LABEL_ALWAYS = "Jedes Mal"
L.OPT_GREETING_LABEL_ONCE_QUEST = "Einmal bei Questgebern"
L.OPT_GREETING_LABEL_ONCE_NPC = "Einmal pro NPC"
L.OPT_GREETING_LABEL_NEVER = "Nie"
L.OPT_PANEL_STOP_ON_CLOSE = "Beim Schließen stoppen"
L.OPT_OG_THRALL = "Originale Thrall-Rede"
L.OPT_OG_THRALL_TIP = "Spielt die Aufnahme von Thralls Rede aus AI VoiceOver statt der von Spoken."
L.OPT_FORGET_GREETINGS = "Gehörte Begrüßungen vergessen"
L.REASON_FORGET_GREETINGS = "Stelle „Begrüßungen vorlesen“ auf „Einmal pro NPC“ oder „Einmal bei Questgebern“, um dies zu nutzen."
L.OPT_FORGET_GREETINGS_DONE = "Die Liste gehörter Begrüßungen dieses Charakters wurde gelöscht."
L.OPT_PACK_GOSSIP = "Gespräche"
L.OPT_PACK_INCLUDED = "In „Alle Quests“ enthalten"
L.OPT_RESET_PROFILE_CONFIRM = "Jede Einstellung für Gespräche im aktiven Profil auf den Standard zurücksetzen?"
L.OPT_MINIMAP_SETTINGS = "Einstellungen für Gespräche"
L.OPT_GREETING = "Begrüßung"
L.OPT_NEVER_TIP = "„Begrüßungen vorlesen“ steht auf der Seite „Gespräche“ der Spoken-Einstellungen auf „Nie“."
L.OPT_GROUP_GENERAL = "Allgemein"
L.OPT_CMD_GROUP = "Befehle"
L.OPT_CMD_READ = "Offenes Fenster vorlesen"
L.OPT_CMD_READ_DESC = "Liest das offene Begrüßungs- oder Gesprächsfenster vor"
L.OPT_CMD_OPTIONS = "Einstellungen"
L.OPT_CMD_OPTIONS_DESC = "Öffnet die Einstellungsseite dieses Moduls"
L.OPT_CMD_TEST = "Testzeile abspielen"
L.OPT_CMD_TEST_DESC = "Spielt eine bekannte NPC-Zeile ab, um zu prüfen, ob du sie hörst"
L.OPT_CMD_DIAG = "Diagnose anzeigen"
L.OPT_CMD_DIAG_DESC = "Gibt Client-, API- und Sprachpaket-Ladestatus aus"
