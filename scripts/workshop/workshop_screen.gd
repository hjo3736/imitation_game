extends Control
## Workshop screen, temporary (docs/leader/13 design, section 6).
##
## Shows which day it is, the time left in the day and the nameplate of the
## door. The time is read from the state of the core every frame; this screen
## does not measure time and holds no rule and no number of the game.
##
##   nameplate -> one question -> core.request_end_day()
##   Esc       -> pause panel; the clock is stopped with &"pause_menu" for as
##                long as the panel is there
##
## The question and the pause panel open over this screen one at a time
## (scripts/common/overlay_layer.gd). When the day ends the screen host
## replaces this screen, and whatever is open over it goes with it.
##
## By default the game object is the autoload "Game". Call set_game() before
## adding the screen to the tree to use another object (tests do this).

const GameAccess: GDScript = preload("res://scripts/common/game_access.gd")
const UiStyle: GDScript = preload("res://scripts/common/ui_style.gd")
const UiText: GDScript = preload("res://scripts/common/ui_text.gd")

const DIALOG_SCENE: PackedScene = preload("res://scenes/common/dialog_panel.tscn")
const PAUSE_SCENE: PackedScene = preload("res://scenes/workshop/pause_panel.tscn")

## Emitted once when "to the title screen" is chosen in the pause panel. The
## screen host ends the game and shows the title screen.
signal title_requested

# --- Contract (docs/leader/13 design, section 5) ------------------------------
const BLOCK_PAUSE: StringName = &"pause_menu"
const COMMAND_END_DAY: StringName = &"request_end_day"

var _game: Object = null
var _game_ready: bool = false
## True after the core accepted the request to end the day.
var _end_requested: bool = false
## True after "to the title screen" was chosen.
var _leaving: bool = false
## True while this screen holds the clock with &"pause_menu".
var _pause_blocking: bool = false

@onready var _background: ColorRect = %Background
@onready var _content: VBoxContainer = %Content
@onready var _day_label: Label = %DayLabel
@onready var _time_label: Label = %TimeLabel
@onready var _nameplate_button: Button = %NameplateButton
@onready var _overlay_layer: Control = %OverlayLayer


## Sets the game object to use instead of the autoload "Game".
## Must be called before the screen enters the tree.
func set_game(game: Object) -> void:
	if is_inside_tree():
		push_error("WorkshopScreen.set_game(): 트리에 들어간 뒤에는 게임 객체를 바꿀 수 없습니다.")
		return
	_game = game


## True while the question or the pause panel is open.
func has_overlay() -> bool:
	return _overlay_layer != null and _overlay_layer.call(&"has_overlay")


func _enter_tree() -> void:
	_game = GameAccess.resolve(self, _game, "WorkshopScreen")
	_game_ready = _game != null


func _exit_tree() -> void:
	# Normally the pause panel has already left and the clock runs again.
	_release_pause()


func _ready() -> void:
	_background.color = UiStyle.COLOR_BACKGROUND
	_content.theme = UiStyle.make_screen_theme()
	_day_label.add_theme_font_size_override(&"font_size", UiStyle.HEADING_FONT_SIZE)
	_nameplate_button.custom_minimum_size = UiStyle.SCREEN_BUTTON_MIN_SIZE
	_nameplate_button.text = UiText.NAMEPLATE_BUTTON
	_overlay_layer.call(&"set_blocked", _content)
	# Connections to the screen's own children: freed together with the screen.
	_overlay_layer.connect(&"overlay_gone", _on_overlay_gone)
	_nameplate_button.pressed.connect(_on_nameplate_pressed)
	_refresh()
	_nameplate_button.grab_focus()


func _process(_delta: float) -> void:
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_ESCAPE or not _can_act():
		return
	get_viewport().set_input_as_handled()
	_open_pause()


func _has_game() -> bool:
	return _game_ready and _game != null and is_instance_valid(_game)


## False while a panel is open or closing, once the screen is being freed and
## after "to the title screen" was chosen.
func _can_act() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and not _leaving and not has_overlay()


# --- Showing the state -------------------------------------------------------

## Shows the day and the time left as the core has them now. The labels are
## only written when their text changes.
func _refresh() -> void:
	var day_text: String = UiText.NO_VALUE
	var time_text: String = UiText.NO_VALUE
	var state: Object = GameAccess.state_of(_game) if _has_game() else null
	if state != null:
		var day: Variant = state.get(&"day")
		var time_left: Variant = state.get(&"day_time_left")
		if day is int:
			day_text = UiText.DAY_FORMAT % day
		if time_left is float or time_left is int:
			time_text = UiText.format_time_left(float(time_left))
	time_text = UiText.TIME_LEFT_FORMAT % time_text
	if _day_label.text != day_text:
		_day_label.text = day_text
	if _time_label.text != time_text:
		_time_label.text = time_text
	var nameplate_disabled: bool = _end_requested or state == null
	if _nameplate_button.disabled != nameplate_disabled:
		_nameplate_button.disabled = nameplate_disabled


# --- Nameplate ---------------------------------------------------------------

func _on_nameplate_pressed() -> void:
	if not _can_act() or _end_requested:
		return
	var question: Control = DIALOG_SCENE.instantiate()
	question.call(&"setup", UiText.NAMEPLATE_CONFIRM, UiText.BUTTON_CONFIRM, UiText.BUTTON_CANCEL)
	# A connection to a panel under this screen: freed together with it.
	question.connect(&"accepted", _on_nameplate_confirmed)
	_overlay_layer.call(&"open", question)


## The question emits accepted at most once. The core ends the day on its next
## tick; the screen host then replaces this screen.
func _on_nameplate_confirmed() -> void:
	if _end_requested or _leaving or is_queued_for_deletion():
		return
	var core: Object = GameAccess.core_of(_game) if _has_game() else null
	if core == null or not core.has_method(COMMAND_END_DAY):
		push_error("WorkshopScreen: 진행 중인 게임이 없어 하루를 끝낼 수 없습니다.")
		return
	var result: Variant = core.call(COMMAND_END_DAY)
	if GameAccess.succeeded(result):
		_end_requested = true
	else:
		push_warning("WorkshopScreen: request_end_day()가 거절됐습니다: %s" % [result])


# --- Pause -------------------------------------------------------------------

func _open_pause() -> void:
	var pause: Control = PAUSE_SCENE.instantiate()
	# A connection to a panel under this screen: freed together with it.
	pause.connect(&"title_requested", _on_pause_title_requested)
	if not _overlay_layer.call(&"open", pause):
		return
	_pause_blocking = true
	if _has_game():
		_game.set_time_blocked(BLOCK_PAUSE, true)


func _on_pause_title_requested() -> void:
	if _leaving or is_queued_for_deletion():
		return
	_leaving = true
	title_requested.emit()


## A panel has left the tree. When it was the pause panel, the clock runs
## again, however the panel went (closed, or thrown away with the screen).
func _on_overlay_gone() -> void:
	_release_pause()


func _release_pause() -> void:
	if not _pause_blocking:
		return
	_pause_blocking = false
	if _has_game():
		_game.set_time_blocked(BLOCK_PAUSE, false)
