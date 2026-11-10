extends "res://tests/common/screen_test_base.gd"
## Headless test for the day summary screen and for the time texts
## (docs/leader/13 work order, 3.4 and 3.7).
##
## Run:
##   godot --headless --path . res://tests/day/day_summary_screen_test.tscn -- --settings-path=user://test_settings.cfg
## Exit code 0 means every check passed. Any failure gives exit code 1.
## Without the argument the run does nothing and exits with 1.
##
## The screen is tested against tests/common/fake_game.gd, which writes no file.

const SCREEN_SCENE: PackedScene = preload("res://scenes/day/day_summary_screen.tscn")
const FakeGame: GDScript = preload("res://tests/common/fake_game.gd")
const UiText: GDScript = preload("res://scripts/common/ui_text.gd")


func _tag() -> String:
	return "day_summary_screen_test"


func _scene_path() -> String:
	return "res://tests/day/day_summary_screen_test.tscn"


func _run_tests() -> void:
	_test_time_texts()
	await _test_shows_summary()
	await _test_next_day()
	await _test_refused()
	await _test_no_game_in_progress()
	await _test_missing_game()
	await _test_bad_game()
	await _test_layout()


# --- Tests -------------------------------------------------------------------

func _test_time_texts() -> void:
	_section("time texts: minutes and seconds, time left rounded up, time used rounded down")
	_equal(UiText.format_time_left(600.0), "10분 00초", "time left 600")
	_equal(UiText.format_time_left(599.9), "10분 00초", "time left 599.9")
	_equal(UiText.format_time_left(599.0), "9분 59초", "time left 599")
	_equal(UiText.format_time_left(60.0), "1분 00초", "time left 60")
	_equal(UiText.format_time_left(59.4), "1분 00초", "time left 59.4")
	_equal(UiText.format_time_left(59.0), "0분 59초", "time left 59")
	_equal(UiText.format_time_left(1.0), "0분 01초", "time left 1")
	_equal(UiText.format_time_left(0.001), "0분 01초", "time left 0.001")
	_equal(UiText.format_time_left(0.0), "0분 00초", "time left 0")
	_equal(UiText.format_time_left(-3.0), "0분 00초", "time left below 0")
	_equal(UiText.format_time_left(3600.0), "60분 00초", "time left 3600")
	_equal(UiText.format_time_used(0.0), "0분 00초", "time used 0")
	_equal(UiText.format_time_used(0.6), "0분 00초", "time used 0.6")
	_equal(UiText.format_time_used(59.9), "0분 59초", "time used 59.9")
	_equal(UiText.format_time_used(540.6), "9분 00초", "time used 540.6")
	_equal(UiText.format_time_used(600.0), "10분 00초", "time used 600")
	_equal(UiText.format_time_used(-1.0), "0분 00초", "time used below 0")
	# Shown time left + shown time used = length of the day (whole seconds).
	for time_left: float in [600.0, 599.9, 300.5, 59.4, 0.3, 0.0]:
		var shown_left: int = ceili(time_left)
		var shown_used: int = floori(600.0 - time_left)
		_equal(shown_left + shown_used, 600, "left %s + used %s add up to 600" % [time_left, 600.0 - time_left])
	_equal(UiText.ended_by_text(&"time"), "시간이 다 됨", "ended by time")
	_equal(UiText.ended_by_text(&"request"), "명패로 닫음", "ended by request")
	_equal(UiText.ended_by_text("request"), "명패로 닫음", "ended by request given as a String")
	_equal(UiText.ended_by_text(&"something_else"), "-", "ended by an unknown value")


func _test_shows_summary() -> void:
	_section("the screen shows the summary of the core")
	var game: Node = _game_at_summary(3, &"time", 600.0)
	var screen: Control = await _open(game)
	_equal(_text(screen, "Heading"), "3일차가 끝났습니다", "which day ended")
	_equal(_text(screen, "EndedByLabel"), "시간이 다 됨", "how it ended: time")
	_equal(_text(screen, "TimeUsedLabel"), "쓴 시간 10분 00초", "time used")
	_equal(_button(screen).text, "다음 날", "the button text")
	_equal(_button(screen).disabled, false, "next day can be pressed")
	_equal(_focus_name(), "NextDayButton", "next day has the focus")
	_equal(game.core.calls.size(), 0, "showing the summary sends no command")
	_equal(game.calls.size(), 0, "showing the summary calls nothing on the game")
	await _free(screen, game)

	game = _game_at_summary(12, &"request", 187.9)
	screen = await _open(game)
	_equal(_text(screen, "Heading"), "12일차가 끝났습니다", "which day ended")
	_equal(_text(screen, "EndedByLabel"), "명패로 닫음", "how it ended: request")
	_equal(_text(screen, "TimeUsedLabel"), "쓴 시간 3분 07초", "time used is rounded down")
	await _free(screen, game)


func _test_next_day() -> void:
	_section("next day calls confirm_day_summary once")
	var game: Node = _game_at_summary(1, &"request", 30.0)
	var screen: Control = await _open(game)
	var core: RefCounted = game.core
	var button: Button = _button(screen)
	button.pressed.emit()
	button.pressed.emit()
	button.pressed.emit()
	_equal(core.count_calls("confirm_day_summary"), 1, "three presses in one frame send one command")
	_equal(core.state.day, 2, "the core went on to day 2")
	_equal(core.state.phase, &"playing", "the core is playing again")
	_equal(button.disabled, true, "the button cannot be pressed again")
	await _frames(2)
	button.pressed.emit()
	_press_key(KEY_ENTER)
	await _frames(2)
	_equal(core.count_calls("confirm_day_summary"), 1, "later presses send nothing")
	_equal(game.calls.size(), 0, "the screen calls nothing on the game: no saving, no clock")
	core = null
	await _free(screen, game)

	# By real input.
	game = _game_at_summary(4, &"time", 600.0)
	screen = await _open(game)
	_press_key(KEY_ENTER)
	await _frames(2)
	_equal(game.core.count_calls("confirm_day_summary"), 1, "enter on the focused button sends the command")
	await _free(screen, game)
	game = _game_at_summary(4, &"time", 600.0)
	screen = await _open(game)
	_click(_button(screen))
	await _frames(2)
	_equal(game.core.count_calls("confirm_day_summary"), 1, "a click on the button sends the command")
	await _free(screen, game)


func _test_refused() -> void:
	_section("a refused command leaves the button usable")
	var game: Node = _game_at_summary(2, &"time", 600.0)
	var screen: Control = await _open(game)
	# The core is no longer at a summary, so it refuses.
	game.core.state.phase = &"playing"
	print("  (the next engine warning line is expected)")
	_button(screen).pressed.emit()
	_equal(game.core.count_calls("confirm_day_summary"), 1, "the command was sent")
	_equal(game.core.state.day, 2, "the core did not change")
	_equal(_button(screen).disabled, false, "the button can be pressed again")
	game.core.state.phase = &"summary"
	_button(screen).pressed.emit()
	_equal(game.core.count_calls("confirm_day_summary"), 2, "the second press sends the command again")
	_equal(game.core.state.day, 3, "and this time the core went on")
	_equal(_button(screen).disabled, true, "then the button is locked")
	await _free(screen, game)


func _test_no_game_in_progress() -> void:
	_section("no game in progress: nothing to show, no crash")
	var game: Node = FakeGame.new()
	var screen: Control = await _open(game)
	_equal(_text(screen, "Heading"), "-", "no day")
	_equal(_text(screen, "EndedByLabel"), "-", "no reason")
	_equal(_text(screen, "TimeUsedLabel"), "쓴 시간 -", "no time")
	_equal(_button(screen).disabled, true, "next day cannot be pressed")
	print("  (the next engine error line is expected)")
	_button(screen).pressed.emit()
	await _free(screen, game)


func _test_missing_game() -> void:
	_section("no game object: an error, no crash")
	if get_node_or_null("/root/Game") != null:
		print("  SKIP: the autoload Game exists in this project, so this case cannot be produced")
		return
	print("  (the next engine error line is expected)")
	var screen: Control = SCREEN_SCENE.instantiate()
	add_child(screen)
	await get_tree().process_frame
	_equal(_text(screen, "Heading"), "-", "nothing is shown")
	_equal(_button(screen).disabled, true, "next day cannot be pressed")
	screen.queue_free()
	await _frames(2)
	_equal(is_instance_valid(screen), false, "the screen is freed")


func _test_bad_game() -> void:
	_section("an object that does not follow the contract: an error, no crash")
	print("  (the next engine error line is expected)")
	var bad: Node = Node.new()
	var screen: Control = SCREEN_SCENE.instantiate()
	screen.set_game(bad)
	add_child(screen)
	await get_tree().process_frame
	_equal(_text(screen, "Heading"), "-", "nothing is shown")
	_equal(_button(screen).disabled, true, "next day cannot be pressed")
	screen.queue_free()
	await _frames(2)
	_equal(is_instance_valid(screen), false, "the screen is freed")
	bad.free()


func _test_layout() -> void:
	_section("layout: inside the safe area, nothing cut, nothing overlapping")
	var game: Node = _game_at_summary(88, &"request", 599.0)
	var screen: Control = await _open(game)
	var content: Control = screen.get_node("%Content")
	_equal(LayoutCheck.count_items(content), 4, "the check covers three texts and the button")
	_no_thin_lines(screen, "day summary screen")
	for window_size: Vector2i in LAYOUT_SIZES:
		var tag: String = await _set_window_size(window_size)
		_check_covers_view(screen.get_node("%Background"), "%s: the background" % tag)
		_check_layout(content, "%s: day summary" % tag)
	get_window().size = Vector2i(1920, 1080)
	await _frames(2)
	await _free(screen, game)


# --- Helpers -----------------------------------------------------------------

## A fake game whose core is at the summary of the given day.
func _game_at_summary(day: int, ended_by: StringName, time_used: float) -> Node:
	var game: Node = FakeGame.new()
	game.save_exists = true
	game.saved_day = day
	game.saved_phase = &"summary"
	game.saved_time_left = game.test_day_length - time_used
	game.saved_summary = {"day": day, "ended_by": ended_by, "time_used": time_used}
	game.continue_game()
	game.calls.clear()
	return game


func _open(game: Node) -> Control:
	var screen: Control = SCREEN_SCENE.instantiate()
	screen.set_game(game)
	add_child(screen)
	await get_tree().process_frame
	return screen


func _free(screen: Control, game: Node) -> void:
	screen.queue_free()
	await _frames(2)
	_equal(is_instance_valid(screen), false, "the screen is freed")
	game.free()


func _text(screen: Control, label_name: String) -> String:
	return (screen.get_node("%" + label_name) as Label).text


func _button(screen: Control) -> Button:
	return screen.get_node("%NextDayButton") as Button
