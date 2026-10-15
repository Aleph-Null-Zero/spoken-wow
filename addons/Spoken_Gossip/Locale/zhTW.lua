-- Traditional Chinese interface strings for Spoken Gossip.
--
-- Keyed exactly as in Strings.lua; anything missing falls back to English.

if not SpokenGossipEnv then return end
setfenv(1, SpokenGossipEnv)

if GetLocale() ~= "zhTW" then
	return
end

L.OPT_PAGE_TITLE = "閒聊"
L.OPT_PANEL_GREETINGS = "朗讀問候"
L.OPT_GREETING_LABEL_ALWAYS = "每次"
L.OPT_GREETING_LABEL_ONCE_QUEST = "任務發布者一次"
L.OPT_GREETING_LABEL_ONCE_NPC = "每個 NPC 一次"
L.OPT_GREETING_LABEL_NEVER = "從不"
L.OPT_PANEL_STOP_ON_CLOSE = "關閉閒聊時停止"
L.OPT_OG_THRALL = "索爾原版演講"
L.OPT_OG_THRALL_TIP = "播放 AI VoiceOver 錄製的索爾演講，而不是 Spoken 的。"
L.OPT_FORGET_GREETINGS = "忘記已聽過的問候"
L.REASON_FORGET_GREETINGS = "將「朗讀問候」設為「每個 NPC 一次」或「任務發布者一次」才能使用。"
L.OPT_FORGET_GREETINGS_DONE = "已清除此角色已聽過的問候清單。"
L.OPT_PACK_GOSSIP = "閒聊"
L.OPT_PACK_INCLUDED = "已含於所有任務"
L.OPT_RESET_PROFILE_CONFIRM = "要將使用中設定檔的所有閒聊設定恢復為預設值嗎？"
L.OPT_MINIMAP_SETTINGS = "閒聊設定"
L.OPT_GREETING = "問候"
L.OPT_NEVER_TIP = "Spoken 設定的「閒聊」頁面中，「朗讀問候」設為「從不」。"
L.OPT_GROUP_GENERAL = "一般"
L.OPT_CMD_GROUP = "命令"
L.OPT_CMD_READ = "朗讀開啟的視窗"
L.OPT_CMD_READ_DESC = "朗讀目前開啟的問候或閒聊視窗"
L.OPT_CMD_OPTIONS = "設定"
L.OPT_CMD_OPTIONS_DESC = "開啟此模組的設定頁面"
L.OPT_CMD_TEST = "播放測試台詞"
L.OPT_CMD_TEST_DESC = "播放一句已知的 NPC 台詞，檢查你是否聽得到"
L.OPT_CMD_DIAG = "顯示診斷"
L.OPT_CMD_DIAG_DESC = "顯示客戶端、API 和語音包載入狀態"
