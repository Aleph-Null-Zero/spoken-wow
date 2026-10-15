-- Spanish interface strings for Spoken Gossip.
-- Covers both esES and esMX: nothing in these strings varies by region.
--
-- Keyed exactly as in Strings.lua; anything missing falls back to English.

if not SpokenGossipEnv then return end
setfenv(1, SpokenGossipEnv)

if GetLocale() ~= "esES" and GetLocale() ~= "esMX" then
	return
end

L.OPT_PAGE_TITLE = "Charlas"
L.OPT_PANEL_GREETINGS = "Leer saludos"
L.OPT_GREETING_LABEL_ALWAYS = "Cada vez"
L.OPT_GREETING_LABEL_ONCE_QUEST = "Una vez con quien da misiones"
L.OPT_GREETING_LABEL_ONCE_NPC = "Una vez por PNJ"
L.OPT_GREETING_LABEL_NEVER = "Nunca"
L.OPT_PANEL_STOP_ON_CLOSE = "Detener al cerrar la charla"
L.OPT_OG_THRALL = "Discurso original de Thrall"
L.OPT_OG_THRALL_TIP = "Reproduce la grabación del discurso de Thrall de AI VoiceOver en lugar de la de Spoken."
L.OPT_FORGET_GREETINGS = "Olvidar saludos oídos"
L.REASON_FORGET_GREETINGS = "Pon «Leer saludos» en «Una vez por PNJ» o «Una vez con quien da misiones» para usar esto."
L.OPT_FORGET_GREETINGS_DONE = "Se ha borrado la lista de saludos oídos de este personaje."
L.OPT_PACK_GOSSIP = "Charlas"
L.OPT_PACK_INCLUDED = "Incluido en «Todas las misiones»"
L.OPT_RESET_PROFILE_CONFIRM = "¿Restablecer todos los ajustes de Charlas del perfil en uso a su valor predeterminado?"
L.OPT_MINIMAP_SETTINGS = "Configuración de Charlas"
L.OPT_GREETING = "Saludo"
L.OPT_NEVER_TIP = "«Leer saludos» está en «Nunca» en la página Charlas de la configuración de Spoken."
L.OPT_GROUP_GENERAL = "General"
L.OPT_CMD_GROUP = "Comandos"
L.OPT_CMD_READ = "Leer ventana abierta"
L.OPT_CMD_READ_DESC = "Lee la ventana de saludo o de charla abierta"
L.OPT_CMD_OPTIONS = "Configuración"
L.OPT_CMD_OPTIONS_DESC = "Abre la página de ajustes de este módulo"
L.OPT_CMD_TEST = "Reproducir una línea de prueba"
L.OPT_CMD_TEST_DESC = "Reproduce una línea conocida de un PNJ para comprobar que la oyes"
L.OPT_CMD_DIAG = "Mostrar diagnóstico"
L.OPT_CMD_DIAG_DESC = "Muestra el estado del cliente, la API y la carga de paquetes de voces"
