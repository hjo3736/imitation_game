extends Control
## Day summary screen (docs/leader/13 design, section 6).
##
## Shows which day ended, how it ended and how much time was used, from the
## summary the core keeps in its state. "Next day" calls
## core.confirm_day_summary(); the core starts the next day and the screen host
## goes back to the workshop.
##
## While this screen is shown the core is in &"summary" and its clock does not
## run, so the screen stops nothing itself.
##
## By default the game object is the autoload "Game". Call set_game() before
## adding the screen to the tree to use another object (tests do this).

const GameAccess: GDScript = preload("res://scripts/common/game_access.gd")
const UiStyle: GDScript = preload("res://scripts/common/ui_style.gd")
const UiText: GDScript = preload("res://scripts/common/ui_text.gd")

# --- Contract (docs/leader/13 design, section 5) ------------------------------
const COMMAND_CONFIRM: StringName = &"confirm_day_summary"

var _game: Object = null
var _game_ready: bool = false
## True after the core accepted "next day".
var _confirmed: bool = false

@onready var _background: ColorRect = %Background
@onready var _content: VBoxContainer = %Content
@onready var _heading: Label = %Heading
@onready var _ended_by_label: Label = %EndedByLabel
@onready var _time_used_label: Label = %TimeUsedLabel
@onready var _next_day_button: Button = %NextDayButton


## Sets the game object to use instead of the autoload "Game".
## Must be called before the screen enters the tree.
func set_game(game: Object) -> void:
	if is_inside_tree():
		push_error("DaySummaryScreen.set_game(): 트리에 들어간 뒤에는 게임 객체를 바꿀 수 없습니다.")
		return
	_game = game


func _enter_tree() -> void:
	_game = GameAccess.resolve(self, _game, "DaySummaryScreen")
	_game_ready = _game != null


func _ready() -> void:
	_background.color = UiStyle.COLOR_BACKGROUND
	_content.theme = UiStyle.make_screen_theme()
	_heading.add_theme_font_size_override(&"font_size", UiStyle.HEADING_FONT_SIZE)
	_next_day_button.custom_minimum_size = UiStyle.SCREEN_BUTTON_MIN_SIZE
	_next_day_button.text = UiText.SUMMARY_NEXT_DAY
	# A connection to the screen's own child: freed together with the screen.
	_next_day_button.pressed.connect(_on_next_day_pressed)
	_show_summary()
	if not _next_day_button.disabled:
		_next_day_button.grab_focus()


func _has_game() -> bool:
	return _game_ready and _game != null and is_instance_valid(_game)


## Writes the summary the core has now. The summary does not change while this
## screen is shown, so it is read once.
func _show_summary() -> void:
	var heading_text: String = UiText.NO_VALUE
	var ended_by_text: String = UiText.NO_VALUE
	var time_used_text: String = UiText.NO_VALUE
	var state: Object = GameAccess.state_of(_game) if _has_game() else null
	var summary: Variant = state.get(&"last_summary") if state != null else null
	if summary is Dictionary:
		var values: Dictionary = summary
		var day: Variant = values.get("day")
		var time_used: Variant = values.get("time_used")
		if day is int:
			heading_text = UiText.SUMMARY_HEADING_FORMAT % day
		ended_by_text = UiText.ended_by_text(values.get("ended_by"))
		if time_used is float or time_used is int:
			time_used_text = UiText.format_time_used(float(time_used))
	_heading.text = heading_text
	_ended_by_label.text = ended_by_text
	_time_used_label.text = UiText.SUMMARY_TIME_USED_FORMAT % time_used_text
	_next_day_button.disabled = state == null


func _on_next_day_pressed() -> void:
	if _confirmed or not is_inside_tree() or is_queued_for_deletion():
		return
	var core: Object = GameAccess.core_of(_game) if _has_game() else null
	if core == null or not core.has_method(COMMAND_CONFIRM):
		push_error("DaySummaryScreen: 진행 중인 게임이 없어 다음 날로 넘어갈 수 없습니다.")
		return
	# Set first: the core emits day_started inside the call and the screen host
	# may already be replacing this screen when the call returns.
	_confirmed = true
	_next_day_button.disabled = true
	var result: Variant = core.call(COMMAND_CONFIRM)
	if not GameAccess.succeeded(result):
		push_warning("DaySummaryScreen: confirm_day_summary()가 거절됐습니다: %s" % [result])
		_confirmed = false
		_next_day_button.disabled = false
