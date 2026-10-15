-- French interface strings for Spoken Gossip.
--
-- Keyed exactly as in Strings.lua; anything missing falls back to English.

if not SpokenGossipEnv then return end
setfenv(1, SpokenGossipEnv)

if GetLocale() ~= "frFR" then
	return
end

L.OPT_PAGE_TITLE = "Discussions"
L.OPT_PANEL_GREETINGS = "Lire les salutations"
L.OPT_GREETING_LABEL_ALWAYS = "À chaque fois"
L.OPT_GREETING_LABEL_ONCE_QUEST = "Une fois pour les donneurs de quêtes"
L.OPT_GREETING_LABEL_ONCE_NPC = "Une fois par PNJ"
L.OPT_GREETING_LABEL_NEVER = "Jamais"
L.OPT_PANEL_STOP_ON_CLOSE = "Arrêter à la fermeture"
L.OPT_OG_THRALL = "Discours original de Thrall"
L.OPT_OG_THRALL_TIP = "Joue l'enregistrement du discours de Thrall d'AI VoiceOver au lieu de celui de Spoken."
L.OPT_FORGET_GREETINGS = "Oublier les salutations entendues"
L.REASON_FORGET_GREETINGS = "Réglez Lire les salutations sur Une fois par PNJ ou Une fois pour les donneurs de quêtes pour utiliser ceci."
L.OPT_FORGET_GREETINGS_DONE = "La liste des salutations entendues par ce personnage est effacée."
L.OPT_PACK_GOSSIP = "Discussions"
L.OPT_PACK_INCLUDED = "Inclus dans « Toutes les quêtes »"
L.OPT_RESET_PROFILE_CONFIRM = "Remettre chaque paramètre du module Discussions du profil utilisé à sa valeur par défaut ?"
L.OPT_MINIMAP_SETTINGS = "Paramètres des Discussions"
L.OPT_GREETING = "Salutation"
L.OPT_NEVER_TIP = "« Lire les salutations » est réglé sur « Jamais » sur la page Discussions des paramètres de Spoken."
L.OPT_GROUP_GENERAL = "Général"
L.OPT_CMD_GROUP = "Commandes"
L.OPT_CMD_READ = "Lire la fenêtre ouverte"
L.OPT_CMD_READ_DESC = "Lit la fenêtre de salutation ou de discussion ouverte"
L.OPT_CMD_OPTIONS = "Paramètres"
L.OPT_CMD_OPTIONS_DESC = "Ouvre la page de paramètres de ce module"
L.OPT_CMD_TEST = "Lire une réplique de test"
L.OPT_CMD_TEST_DESC = "Joue une réplique de PNJ connue pour vérifier que vous l'entendez"
L.OPT_CMD_DIAG = "Afficher le diagnostic"
L.OPT_CMD_DIAG_DESC = "Affiche l'état du client, de l'API et du chargement des packs de voix"
