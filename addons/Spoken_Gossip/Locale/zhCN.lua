-- Simplified Chinese interface strings for Spoken Gossip.
--
-- Keyed exactly as in Strings.lua; anything missing falls back to English.

if not SpokenGossipEnv then return end
setfenv(1, SpokenGossipEnv)

if GetLocale() ~= "zhCN" then
	return
end

L.OPT_PAGE_TITLE = "闲聊"
L.OPT_PANEL_GREETINGS = "朗读问候"
L.OPT_GREETING_LABEL_ALWAYS = "每次"
L.OPT_GREETING_LABEL_ONCE_QUEST = "任务发布者一次"
L.OPT_GREETING_LABEL_ONCE_NPC = "每个 NPC 一次"
L.OPT_GREETING_LABEL_NEVER = "从不"
L.OPT_PANEL_STOP_ON_CLOSE = "关闭闲聊时停止"
L.OPT_OG_THRALL = "萨尔原版演讲"
L.OPT_OG_THRALL_TIP = "播放 AI VoiceOver 录制的萨尔演讲，而不是 Spoken 的。"
L.OPT_FORGET_GREETINGS = "忘记已听过的问候"
L.REASON_FORGET_GREETINGS = "将“朗读问候”设为“每个 NPC 一次”或“任务发布者一次”后才能使用。"
L.OPT_FORGET_GREETINGS_DONE = "已清除此角色听过的问候列表。"
L.OPT_PACK_GOSSIP = "闲聊"
L.OPT_PACK_INCLUDED = "已包含在“全部任务”中"
L.OPT_RESET_PROFILE_CONFIRM = "将当前配置文件中的所有闲聊设置恢复为默认值？"
L.OPT_MINIMAP_SETTINGS = "闲聊设置"
L.OPT_GREETING = "问候"
L.OPT_NEVER_TIP = "Spoken 设置的“闲聊”页面中，“朗读问候”设为“从不”。"
L.OPT_GROUP_GENERAL = "常规"
L.OPT_CMD_GROUP = "命令"
L.OPT_CMD_READ = "朗读打开的窗口"
L.OPT_CMD_READ_DESC = "朗读当前打开的问候或闲聊窗口"
L.OPT_CMD_OPTIONS = "设置"
L.OPT_CMD_OPTIONS_DESC = "打开此模块的设置页面"
L.OPT_CMD_TEST = "播放测试台词"
L.OPT_CMD_TEST_DESC = "播放一句已知的 NPC 台词，检查你是否能听到"
L.OPT_CMD_DIAG = "显示诊断"
L.OPT_CMD_DIAG_DESC = "显示客户端、API 和语音包加载状态"
