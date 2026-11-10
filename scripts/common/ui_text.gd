extends RefCounted
## Every piece of text of the game screens added in the 13 work, in one place
## (docs/leader/13 design, section 11): the screen host, the workshop, the
## pause panel, the day summary and their questions and notices.
##
## The wording is the minimum needed to operate the screens. It is not final.
## The title screen and the settings screen keep their text in their scenes.

# --- Buttons shared by questions and notices ---------------------------------
const BUTTON_CONFIRM: String = "확인"
const BUTTON_CANCEL: String = "취소"
const BUTTON_CLOSE: String = "닫기"

# --- Screen host (13 design, section 6, item 3 and section 11, item 3; --------
# 14 design, section 3 for the new game question, word for word) -------------
const NEW_GAME_CONFIRM: String = "새 게임을 시작하면 현재 진행중인 정보가 사라집니다. 그래도 새 게임을 시작하겠습니까?"
const NEW_GAME_FAILED: String = "새 게임을 시작하지 못했습니다."
const CONTINUE_FAILED: String = "저장된 게임을 읽지 못했습니다."

# --- Workshop (13 design, section 6) -----------------------------------------
const DAY_FORMAT: String = "%d일차"
const TIME_LEFT_FORMAT: String = "남은 시간 %s"
const NAMEPLATE_BUTTON: String = "명패 닫기"
const NAMEPLATE_CONFIRM: String = "명패를 닫고 하루를 끝낼까요?"
const NO_VALUE: String = "-"

# --- Pause panel (13 design, section 6, item 5) ------------------------------
const PAUSE_HEADING: String = "일시정지"
const PAUSE_RESUME: String = "계속하기"
const PAUSE_SETTINGS: String = "설정"
const PAUSE_TO_TITLE: String = "시작 화면으로"

# --- Day summary (13 design, section 6; 13 work order 3.4) -------------------
const SUMMARY_HEADING_FORMAT: String = "%d일차가 끝났습니다"
const SUMMARY_ENDED_BY_TIME: String = "시간이 다 됨"
const SUMMARY_ENDED_BY_REQUEST: String = "명패로 닫음"
const SUMMARY_TIME_USED_FORMAT: String = "쓴 시간 %s"
const SUMMARY_NEXT_DAY: String = "다음 날"

# --- Time (13 design, section 11, item 2) ------------------------------------
const MINUTES_SECONDS_FORMAT: String = "%d분 %02d초"
const SECONDS_PER_MINUTE: int = 60


## Time left in the day, rounded up: it reads "0분 00초" only when no time is
## left. 59.4 seconds is "1분 00초".
static func format_time_left(seconds: float) -> String:
	return _minutes_seconds(ceili(maxf(seconds, 0.0)))


## Time used in the day, rounded down, so that the shown time left and the
## shown time used add up to the length of the day.
static func format_time_used(seconds: float) -> String:
	return _minutes_seconds(floori(maxf(seconds, 0.0)))


## How the day ended, from the summary's ended_by.
static func ended_by_text(ended_by: Variant) -> String:
	match str(ended_by):
		"time":
			return SUMMARY_ENDED_BY_TIME
		"request":
			return SUMMARY_ENDED_BY_REQUEST
	return NO_VALUE


static func _minutes_seconds(whole_seconds: int) -> String:
	@warning_ignore("integer_division")
	var minutes: int = whole_seconds / SECONDS_PER_MINUTE
	return MINUTES_SECONDS_FORMAT % [minutes, whole_seconds % SECONDS_PER_MINUTE]
