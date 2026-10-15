-- Korean interface strings for Spoken Gossip.
--
-- Keyed exactly as in Strings.lua; anything missing falls back to English.

if not SpokenGossipEnv then return end
setfenv(1, SpokenGossipEnv)

if GetLocale() ~= "koKR" then
	return
end

L.OPT_PAGE_TITLE = "잡담"
L.OPT_PANEL_GREETINGS = "인사말 읽기"
L.OPT_GREETING_LABEL_ALWAYS = "매번"
L.OPT_GREETING_LABEL_ONCE_QUEST = "퀘스트 제공자는 한 번"
L.OPT_GREETING_LABEL_ONCE_NPC = "NPC당 한 번"
L.OPT_GREETING_LABEL_NEVER = "안 함"
L.OPT_PANEL_STOP_ON_CLOSE = "잡담을 닫으면 정지"
L.OPT_OG_THRALL = "오리지널 스랄 연설"
L.OPT_OG_THRALL_TIP = "Spoken의 녹음 대신 AI VoiceOver의 스랄 연설 녹음을 재생합니다."
L.OPT_FORGET_GREETINGS = "들은 인사말 잊기"
L.REASON_FORGET_GREETINGS = "이 기능을 쓰려면 '인사말 읽기'를 'NPC당 한 번' 또는 '퀘스트 제공자는 한 번'으로 설정하세요."
L.OPT_FORGET_GREETINGS_DONE = "이 캐릭터의 들은 인사말 목록을 지웠습니다."
L.OPT_PACK_GOSSIP = "잡담"
L.OPT_PACK_INCLUDED = "모든 퀘스트에 포함"
L.OPT_RESET_PROFILE_CONFIRM = "사용 중인 프로필의 잡담 설정을 모두 기본값으로 되돌릴까요?"
L.OPT_MINIMAP_SETTINGS = "잡담 설정"
L.OPT_GREETING = "인사말"
L.OPT_NEVER_TIP = "Spoken 설정의 잡담 페이지에서 '인사말 읽기'가 '안 함'으로 설정되어 있습니다."
L.OPT_GROUP_GENERAL = "일반"
L.OPT_CMD_GROUP = "명령어"
L.OPT_CMD_READ = "열린 창 읽기"
L.OPT_CMD_READ_DESC = "열려 있는 인사말 또는 잡담 창을 읽습니다"
L.OPT_CMD_OPTIONS = "설정"
L.OPT_CMD_OPTIONS_DESC = "이 모듈의 설정 페이지를 엽니다"
L.OPT_CMD_TEST = "테스트 대사 재생"
L.OPT_CMD_TEST_DESC = "알려진 NPC 대사를 재생해 들리는지 확인합니다"
L.OPT_CMD_DIAG = "진단 정보 보기"
L.OPT_CMD_DIAG_DESC = "클라이언트, API, 음성 팩 불러오기 상태를 출력합니다"
