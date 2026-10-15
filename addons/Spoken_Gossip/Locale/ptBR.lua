-- Brazilian Portuguese interface strings for Spoken Gossip.
--
-- Keyed exactly as in Strings.lua; anything missing falls back to English.

if not SpokenGossipEnv then return end
setfenv(1, SpokenGossipEnv)

if GetLocale() ~= "ptBR" then
	return
end

L.OPT_PAGE_TITLE = "Conversas"
L.OPT_PANEL_GREETINGS = "Ler saudações"
L.OPT_GREETING_LABEL_ALWAYS = "Toda vez"
L.OPT_GREETING_LABEL_ONCE_QUEST = "Uma vez para quem dá missões"
L.OPT_GREETING_LABEL_ONCE_NPC = "Uma vez por PNJ"
L.OPT_GREETING_LABEL_NEVER = "Nunca"
L.OPT_PANEL_STOP_ON_CLOSE = "Parar ao fechar a conversa"
L.OPT_OG_THRALL = "Discurso original do Thrall"
L.OPT_OG_THRALL_TIP = "Toca a gravação do discurso do Thrall do AI VoiceOver em vez da do Spoken."
L.OPT_FORGET_GREETINGS = "Esquecer saudações ouvidas"
L.REASON_FORGET_GREETINGS = "Ajuste Ler saudações para Uma vez por PNJ ou Uma vez para quem dá missões para usar isto."
L.OPT_FORGET_GREETINGS_DONE = "A lista de saudações ouvidas deste personagem foi limpa."
L.OPT_PACK_GOSSIP = "Conversas"
L.OPT_PACK_INCLUDED = "Incluído em “Todas as missões”"
L.OPT_RESET_PROFILE_CONFIRM = "Voltar todas as configurações de Conversas do perfil em uso ao padrão?"
L.OPT_MINIMAP_SETTINGS = "Configurações de Conversas"
L.OPT_GREETING = "Saudação"
L.OPT_NEVER_TIP = "“Ler saudações” está em “Nunca” na página Conversas das configurações do Spoken."
L.OPT_GROUP_GENERAL = "Geral"
L.OPT_CMD_GROUP = "Comandos"
L.OPT_CMD_READ = "Ler janela aberta"
L.OPT_CMD_READ_DESC = "Lê a janela de saudação ou de conversa aberta"
L.OPT_CMD_OPTIONS = "Configurações"
L.OPT_CMD_OPTIONS_DESC = "Abre a página de configurações deste módulo"
L.OPT_CMD_TEST = "Reproduzir fala de teste"
L.OPT_CMD_TEST_DESC = "Toca uma fala conhecida de um PNJ para verificar se você a ouve"
L.OPT_CMD_DIAG = "Mostrar diagnóstico"
L.OPT_CMD_DIAG_DESC = "Mostra o estado do cliente, da API e do carregamento dos pacotes de voz"
