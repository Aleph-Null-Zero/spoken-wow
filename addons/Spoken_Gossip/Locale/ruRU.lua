-- Russian interface strings for Spoken Gossip.
--
-- Keyed exactly as in Strings.lua; anything missing falls back to English.

if not SpokenGossipEnv then return end
setfenv(1, SpokenGossipEnv)

if GetLocale() ~= "ruRU" then
	return
end

L.OPT_PAGE_TITLE = "Разговоры"
L.OPT_PANEL_GREETINGS = "Читать приветствия"
L.OPT_GREETING_LABEL_ALWAYS = "Каждый раз"
L.OPT_GREETING_LABEL_ONCE_QUEST = "Раз для дающих задания"
L.OPT_GREETING_LABEL_ONCE_NPC = "Раз на НИП"
L.OPT_GREETING_LABEL_NEVER = "Никогда"
L.OPT_PANEL_STOP_ON_CLOSE = "Остановка при закрытии"
L.OPT_OG_THRALL = "Оригинальная речь Тралла"
L.OPT_OG_THRALL_TIP = "Включает запись речи Тралла из AI VoiceOver вместо записи Spoken."
L.OPT_FORGET_GREETINGS = "Забыть приветствия"
L.REASON_FORGET_GREETINGS = "Выберите в «Читать приветствия» вариант «Раз на НИП» или «Раз для дающих задания», чтобы пользоваться этим."
L.OPT_FORGET_GREETINGS_DONE = "Список услышанных приветствий этого персонажа очищен."
L.OPT_PACK_GOSSIP = "Разговоры"
L.OPT_PACK_INCLUDED = "Входит в «Все задания»"
L.OPT_RESET_PROFILE_CONFIRM = "Вернуть все настройки разговоров в текущем профиле к значениям по умолчанию?"
L.OPT_MINIMAP_SETTINGS = "Настройки раздела «Разговоры»"
L.OPT_GREETING = "Приветствие"
L.OPT_NEVER_TIP = "«Читать приветствия» установлено на «Никогда» на странице «Разговоры» в настройках Spoken."
L.OPT_GROUP_GENERAL = "Общее"
L.OPT_CMD_GROUP = "Команды"
L.OPT_CMD_READ = "Прочитать открытое окно"
L.OPT_CMD_READ_DESC = "Озвучивает открытое окно приветствия или разговора"
L.OPT_CMD_OPTIONS = "Настройки"
L.OPT_CMD_OPTIONS_DESC = "Открывает страницу настроек этого модуля"
L.OPT_CMD_TEST = "Прослушать тестовую реплику"
L.OPT_CMD_TEST_DESC = "Воспроизводит известную реплику НИП, чтобы проверить, что вы её слышите"
L.OPT_CMD_DIAG = "Показать диагностику"
L.OPT_CMD_DIAG_DESC = "Показывает состояние клиента, API и загрузки пакетов озвучки"
