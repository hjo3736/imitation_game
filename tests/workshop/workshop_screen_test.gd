extends "res://tests/common/screen_test_base.gd"
## Headless test for the temporary workshop screen and its pause panel
## (docs/roles/leader/outputs/13 work order, 3.3 and 3.7).
##
## Run:
##   godot --headless --path . res://tests/workshop/workshop_screen_test.tscn -- --settings-path=user://test_settings.cfg
## Exit code 0 means every check passed. Any failure gives exit code 1.
## Without the argument the run does nothing and exits with 1.
##
## The screen is tested against tests/common/fake_game.gd, which writes no
## file. The settings screen opened from the pause panel uses the real autoload
## Settings with the test settings file; no setting is changed here.

const SCREEN_SCENE: PackedScene = preload("res://scenes/workshop/workshop_screen.tscn")
const FakeGame: GDScript = preload("res://tests/common/fake_game.gd")

const SETTINGS_SCENE_PATH: String = "res://scenes/settings/settings_screen.tscn"
const PAUSE_SCENE_PATH: String = "res://scenes/workshop/pause_panel.tscn"
const DIALOG_SCENE_PATH: String = "res://scenes/common/dialog_panel.tscn"
const OPEN_CLOSE_CYCLES: int = 10

var _title_requests: int = 0


func _tag() -> String:
	return "workshop_screen_test"


func _scene_path() -> String:
	return "res://tests/workshop/workshop_screen_test.tscn"


func _run_tests() -> void:
	await _test_shows_state()
	await _test_follows_state()
	await _test_nameplate_question()
	await _test_nameplate_confirmed_once()
	await _test_nameplate_refused()
	await _test_pause_stops_the_clock()
	await _test_pause_settings()
	await _test_pause_to_title()
	await _test_one_panel_at_a_time()
	await _test_input_behind_a_panel()
	await _test_freed_with_panels_open()
	await _test_no_game_in_progress()
	await _test_missing_game()
	await _test_bad_game()
	await _test_layout()
	await _test_no_leaks()


# --- Tests -------------------------------------------------------------------

func _test_shows_state() -> void:
	_section("the screen shows the day and the time left of the core")
	for sample: Array in [
		[1, 600.0, "1일차", "남은 시간 10분 00초"],
		[7, 59.4, "7일차", "남은 시간 1분 00초"],
		[7, 59.0, "7일차", "남은 시간 0분 59초"],
		[123, 0.0, "123일차", "남은 시간 0분 00초"],
	]:
		var game: Node = _game_playing(sample[0], sample[1])
		var screen: Control = await _open(game)
		_equal(_text(screen, "DayLabel"), sample[2], "day %d" % sample[0])
		_equal(_text(screen, "TimeLabel"), sample[3], "time left %s" % sample[1])
		_equal(_nameplate(screen).text, "명패 닫기", "the nameplate text")
		_equal(_nameplate(screen).disabled, false, "the nameplate can be pressed")
		_equal(_focus_name(), "NameplateButton", "the nameplate has the focus")
		_equal(game.core.calls.size(), 0, "showing sends no command")
		_equal(game.calls.size(), 0, "showing calls nothing on the game")
		await _free(screen, game)


func _test_follows_state() -> void:
	_section("the screen follows the core; it does not measure time itself")
	var game: Node = _game_playing(1, 600.0)
	var screen: Control = await _open(game)
	await _frames(30)
	_equal(_text(screen, "TimeLabel"), "남은 시간 10분 00초", "30 frames without a tick: the time does not move")
	game.tick(0.5)
	await _frames(2)
	_equal(_text(screen, "TimeLabel"), "남은 시간 10분 00초", "599.5 left is still shown as 10:00")
	game.tick(0.5)
	await _frames(2)
	_equal(_text(screen, "TimeLabel"), "남은 시간 9분 59초", "599 left")
	game.tick(539.6)
	await _frames(2)
	_equal(_text(screen, "TimeLabel"), "남은 시간 1분 00초", "59.4 left")
	game.core.state.day = 9
	game.core.state.day_time_left = 125.0
	await _frames(2)
	_equal(_text(screen, "DayLabel"), "9일차", "a new day is shown")
	_equal(_text(screen, "TimeLabel"), "남은 시간 2분 05초", "and its time")
	# Another game: the screen reads Game.core again and keeps no old core.
	var old_core: WeakRef = weakref(game.core)
	game.new_game()
	await _frames(2)
	_equal(_text(screen, "DayLabel"), "1일차", "a new game is shown")
	_equal(old_core.get_ref() == null, true, "the core of the game before is gone: the screen did not keep it")
	await _free(screen, game)


func _test_nameplate_question() -> void:
	_section("nameplate: asks once before anything happens")
	var game: Node = _game_playing(2, 300.0)
	var screen: Control = await _open(game)
	_nameplate(screen).pressed.emit()
	_nameplate(screen).pressed.emit()
	_nameplate(screen).pressed.emit()
	_equal(_overlay_count(screen), 1, "three presses in one frame open one question")
	var question: Control = _overlay(screen)
	_equal(question.scene_file_path, DIALOG_SCENE_PATH, "it is the question panel")
	_equal((question.get_node("%Message") as Label).text, "명패를 닫고 하루를 끝낼까요?", "the question")
	_equal((question.get_node("%AcceptButton") as Button).text, "확인", "the accepting button")
	_equal((question.get_node("%CloseButton") as Button).text, "취소", "the cancelling button")
	_equal(game.core.count_calls("request_end_day"), 0, "nothing is sent before the answer")
	await _frames(2)
	_equal(_focus_name(), "CloseButton", "the focus is on cancel")
	_equal(game.blocked_reasons(), [], "the question does not stop the clock")

	(question.get_node("%CloseButton") as Button).pressed.emit()
	await _frames(2)
	_equal(_overlay_count(screen), 0, "cancel closes the question")
	_equal(game.core.count_calls("request_end_day"), 0, "cancel sends nothing")
	_equal(_focus_name(), "NameplateButton", "the focus is back on the nameplate")

	# Esc on the question closes the question and does not open the pause panel.
	_nameplate(screen).pressed.emit()
	await _frames(2)
	_press_key(KEY_ESCAPE)
	await _frames(3)
	_equal(_overlay_count(screen), 0, "Esc closes the question and opens nothing else")
	_equal(game.core.count_calls("request_end_day"), 0, "Esc sends nothing")
	_equal(game.blocked_reasons(), [], "Esc on the question does not stop the clock")
	_equal(game.calls.size(), 0, "nothing was called on the game")
	await _free(screen, game)


func _test_nameplate_confirmed_once() -> void:
	_section("nameplate: confirmed, request_end_day is called once")
	var game: Node = _game_playing(2, 300.0)
	var screen: Control = await _open(game)
	_nameplate(screen).pressed.emit()
	await _frames(2)
	var accept: Button = _overlay(screen).get_node("%AcceptButton")
	accept.pressed.emit()
	accept.pressed.emit()
	accept.pressed.emit()
	_equal(game.core.count_calls("request_end_day"), 1, "three presses on confirm send one command")
	await _frames(2)
	_equal(_overlay_count(screen), 0, "the question is closed")
	_equal(_nameplate(screen).disabled, true, "the nameplate cannot be pressed again")
	_nameplate(screen).pressed.emit()
	_click(_nameplate(screen))
	await _frames(2)
	_equal(_overlay_count(screen), 0, "pressing the nameplate again opens nothing")
	_equal(game.core.count_calls("request_end_day"), 1, "still one command")
	_equal(game.core.state.phase, &"playing", "the day ends on the core's next tick, not in the screen")
	game.tick(0.1)
	_equal(game.core.state.phase, &"summary", "after a tick the core is at the summary")
	_equal(game.core.state.last_summary.get("ended_by"), &"request", "ended by request")
	_equal(game.calls.size(), 0, "the screen called nothing on the game: no saving")
	await _free(screen, game)

	# By real input: enter on the nameplate, left to confirm, enter.
	game = _game_playing(5, 100.0)
	screen = await _open(game)
	_press_key(KEY_ENTER)
	await _frames(2)
	_equal(_overlay_count(screen), 1, "enter on the nameplate opens the question")
	_press_key(KEY_ENTER)
	await _frames(3)
	_equal(game.core.count_calls("request_end_day"), 0, "enter on the focused cancel sends nothing")
	_equal(_overlay_count(screen), 0, "and closes the question")
	_click(_nameplate(screen))
	await _frames(2)
	_equal(_overlay_count(screen), 1, "a click on the nameplate opens the question")
	_click(_overlay(screen).get_node("%AcceptButton") as Control)
	await _frames(3)
	_equal(game.core.count_calls("request_end_day"), 1, "a click on confirm sends the command")
	await _free(screen, game)


func _test_nameplate_refused() -> void:
	_section("nameplate: a refused request leaves the nameplate usable")
	var game: Node = _game_playing(2, 300.0)
	var screen: Control = await _open(game)
	# The core refuses the nameplate while something is being worked on.
	game.core.begin_activity()
	_nameplate(screen).pressed.emit()
	await _frames(2)
	print("  (the next engine warning line is expected)")
	(_overlay(screen).get_node("%AcceptButton") as Button).pressed.emit()
	await _frames(3)
	_equal(game.core.count_calls("request_end_day"), 1, "the command was sent")
	_equal(_nameplate(screen).disabled, false, "the nameplate can be pressed again")
	game.core.end_activity()
	_nameplate(screen).pressed.emit()
	await _frames(2)
	(_overlay(screen).get_node("%AcceptButton") as Button).pressed.emit()
	await _frames(3)
	_equal(game.core.count_calls("request_end_day"), 2, "the second try sends the command again")
	_equal(_nameplate(screen).disabled, true, "this time it is accepted and the nameplate is locked")
	await _free(screen, game)


func _test_pause_stops_the_clock() -> void:
	_section("pause: Esc opens it, the clock stops while it is open")
	var game: Node = _game_playing(1, 600.0)
	var screen: Control = await _open(game)
	_press_key(KEY_ESCAPE)
	await _frames(2)
	_equal(_overlay_count(screen), 1, "Esc opens one panel")
	var pause: Control = _overlay(screen)
	_equal(pause.scene_file_path, PAUSE_SCENE_PATH, "it is the pause panel")
	_equal((pause.get_node("%Heading") as Label).text, "일시정지", "the heading")
	_equal((pause.get_node("%ResumeButton") as Button).text, "계속하기", "first item")
	_equal((pause.get_node("%SettingsButton") as Button).text, "설정", "second item")
	_equal((pause.get_node("%TitleButton") as Button).text, "시작 화면으로", "third item")
	_equal(_focus_name(), "ResumeButton", "continue has the focus")
	_equal(game.blocked_reasons(), [&"pause_menu"], "the clock is stopped with pause_menu")
	_equal(game.count_calls("set_time_blocked(pause_menu, true)"), 1, "it was set once")
	game.tick(100.0)
	await _frames(2)
	_equal(game.core.state.day_time_left, 600.0, "a tick of the game does not move the clock")
	_equal(_text(screen, "TimeLabel"), "남은 시간 10분 00초", "the shown time does not move")

	(pause.get_node("%ResumeButton") as Button).pressed.emit()
	(pause.get_node("%ResumeButton") as Button).pressed.emit()
	await _frames(2)
	_equal(_overlay_count(screen), 0, "continue closes the panel")
	_equal(game.blocked_reasons(), [], "the clock runs again")
	_equal(game.count_calls("set_time_blocked(pause_menu, false)"), 1, "it was released once")
	_equal(_focus_name(), "NameplateButton", "the focus is back on the nameplate")
	game.tick(1.0)
	_equal(game.core.state.day_time_left, 599.0, "a tick moves the clock again")

	# Esc closes the pause panel; Esc opens it again.
	_press_key(KEY_ESCAPE)
	await _frames(2)
	_equal(_overlay_count(screen), 1, "Esc opens the pause panel")
	_equal(game.blocked_reasons(), [&"pause_menu"], "the clock is stopped")
	_press_key(KEY_ESCAPE)
	await _frames(3)
	_equal(_overlay_count(screen), 0, "Esc closes the pause panel")
	_equal(game.blocked_reasons(), [], "the clock runs again")
	# Twice in one frame: opens, and the second Esc belongs to the panel.
	_press_key(KEY_ESCAPE)
	_press_key(KEY_ESCAPE)
	await _frames(3)
	_equal(_overlay_count(screen), 0, "two Esc in one frame open and close it")
	_equal(game.blocked_reasons(), [], "and leave the clock running")
	_equal(game.count_calls("set_time_blocked(pause_menu, true)"), game.count_calls("set_time_blocked(pause_menu, false)"), "every stop has its release")
	_equal(game.core.calls.size(), 0, "pausing sends no command to the core")
	await _free(screen, game)


func _test_pause_settings() -> void:
	_section("pause: settings opens over the pause panel; the clock stays stopped")
	var settings: Node = get_node_or_null("/root/Settings")
	var settings_connections: int = _connection_count(settings, &"changed")
	var game: Node = _game_playing(1, 600.0)
	var screen: Control = await _open(game)
	_press_key(KEY_ESCAPE)
	await _frames(2)
	var pause: Control = _overlay(screen)
	# By the keyboard, so that the focus is where a player's would be: down
	# from "continue" to "settings", then enter. A second press follows at once.
	_press_key(KEY_DOWN)
	await _frames(2)
	_equal(_focus_name(), "SettingsButton", "down moves the focus from continue to settings")
	_press_key(KEY_ENTER)
	await _frames(2)
	(pause.get_node("%SettingsButton") as Button).pressed.emit()
	await _frames(2)
	var pause_layer: Node = pause.get_node("%OverlayLayer")
	_equal(pause_layer.get_child_count(), 1, "enter and one more press open one settings screen")
	var settings_screen: Control = pause_layer.get_child(0)
	_equal(settings_screen.scene_file_path, SETTINGS_SCENE_PATH, "it is the existing settings screen")
	_equal((settings_screen.get_node("%ErrorLabel") as Label).visible, false, "it found Settings")
	_equal(_connection_count(settings, &"changed"), settings_connections + 1, "it is connected to Settings.changed")
	_equal(_overlay_count(screen), 1, "the pause panel is still the workshop's panel")
	_equal(_focus_inside(settings_screen), true, "the focus is inside the settings screen")
	_equal(_reachable(pause.get_node("%Panel")), Vector2i.ZERO, "the pause panel behind it takes neither focus nor mouse")
	_equal(game.blocked_reasons(), [&"pause_menu"], "the clock is still stopped")
	# Buttons of the pause panel do nothing behind the settings screen.
	(pause.get_node("%ResumeButton") as Button).pressed.emit()
	(pause.get_node("%TitleButton") as Button).pressed.emit()
	_equal(_title_requests, 0, "to the title screen does nothing behind the settings screen")
	_equal(pause.is_queued_for_deletion(), false, "continue does nothing behind the settings screen")

	# Esc closes the settings screen only.
	_press_key(KEY_ESCAPE)
	await _frames(3)
	_equal(pause_layer.get_child_count(), 0, "Esc closes the settings screen")
	_equal(_overlay_count(screen), 1, "the pause panel stays")
	_equal(is_instance_valid(pause) and not pause.is_queued_for_deletion(), true, "the pause panel was not closed")
	_equal(game.blocked_reasons(), [&"pause_menu"], "the clock is still stopped after the settings screen closed")
	_equal(_focus_name(), "SettingsButton", "the focus is back on the pause panel")
	_equal(_reachable(pause.get_node("%Panel")), Vector2i(3, 3), "the pause panel takes input again")
	_equal(_connection_count(settings, &"changed"), settings_connections, "no connection left on Settings.changed")

	# Opened again and closed with its own button.
	(pause.get_node("%SettingsButton") as Button).pressed.emit()
	await _frames(2)
	_equal(pause_layer.get_child_count(), 1, "settings opens again")
	(pause_layer.get_child(0).get_node("%CloseButton") as Button).pressed.emit()
	await _frames(3)
	_equal(pause_layer.get_child_count(), 0, "its close button closes it")
	_equal(game.blocked_reasons(), [&"pause_menu"], "the clock is still stopped")

	(pause.get_node("%ResumeButton") as Button).pressed.emit()
	await _frames(3)
	_equal(_overlay_count(screen), 0, "continue closes the pause panel")
	_equal(game.blocked_reasons(), [], "now the clock runs again")
	_equal(game.count_calls("set_time_blocked(pause_menu, true)"), 1, "the reason was set once in all of this")
	_equal(game.count_calls("set_time_blocked(pause_menu, false)"), 1, "and released once")
	await _free(screen, game)


func _test_pause_to_title() -> void:
	_section("pause: to the title screen asks for it once")
	var game: Node = _game_playing(3, 200.0)
	var screen: Control = await _open(game)
	_press_key(KEY_ESCAPE)
	await _frames(2)
	var pause: Control = _overlay(screen)
	var button: Button = pause.get_node("%TitleButton")
	button.pressed.emit()
	button.pressed.emit()
	button.pressed.emit()
	_equal(_title_requests, 1, "three presses in one frame emit title_requested once")
	_equal(game.count_calls("end_game"), 0, "the screen does not end the game itself; the screen host does")
	await _frames(3)
	_equal(_overlay_count(screen), 0, "the pause panel is closed")
	_equal(game.blocked_reasons(), [], "the clock is not left stopped")
	# After asking for the title screen the workshop takes nothing more.
	_press_key(KEY_ESCAPE)
	_nameplate(screen).pressed.emit()
	await _frames(2)
	_equal(_overlay_count(screen), 0, "nothing opens after the title screen was asked for")
	_equal(_title_requests, 1, "still one request")
	_equal(game.core.calls.size(), 0, "no command was sent to the core")
	await _free(screen, game)


func _test_one_panel_at_a_time() -> void:
	_section("one panel at a time")
	var game: Node = _game_playing(1, 600.0)
	var screen: Control = await _open(game)
	# Esc and the nameplate in the same frame.
	_nameplate(screen).pressed.emit()
	_press_key(KEY_ESCAPE)
	await _frames(3)
	_equal(_overlay_count(screen), 0, "nameplate then Esc: the question opened and Esc closed it")
	_equal(game.blocked_reasons(), [], "the pause panel did not open behind it")
	_press_key(KEY_ESCAPE)
	await _frames(2)
	_equal(_overlay(screen).scene_file_path, PAUSE_SCENE_PATH, "the pause panel is open")
	_nameplate(screen).pressed.emit()
	_nameplate(screen).pressed.emit()
	await _frames(2)
	_equal(_overlay_count(screen), 1, "the nameplate opens nothing over the pause panel")
	_equal(_overlay(screen).scene_file_path, PAUSE_SCENE_PATH, "the pause panel is still the open one")
	# The frame in which the pause panel closes.
	var pause: Control = _overlay(screen)
	pause.close()
	_nameplate(screen).pressed.emit()
	_equal(_overlay_count(screen), 1, "while the pause panel is closing nothing else opens")
	await _frames(3)
	_equal(is_instance_valid(pause), false, "the pause panel is freed")
	_equal(_overlay_count(screen), 0, "the layer is empty")
	_equal(game.blocked_reasons(), [], "the clock runs")
	_nameplate(screen).pressed.emit()
	_equal(_overlay_count(screen), 1, "the next frame the nameplate works again")
	_overlay(screen).close()
	await _frames(3)
	await _free(screen, game)


func _test_input_behind_a_panel() -> void:
	_section("what is behind a panel takes neither the keyboard nor the mouse")
	var game: Node = _game_playing(1, 600.0)
	var screen: Control = await _open(game)
	var content: Control = screen.get_node("%Content")
	_equal(_reachable(content), Vector2i(1, 1), "without a panel the nameplate takes focus and mouse")
	_press_key(KEY_ESCAPE)
	await _frames(2)
	var pause: Control = _overlay(screen)
	_equal(_reachable(content), Vector2i.ZERO, "with the pause panel open it takes neither")
	_equal(_focus_inside(pause), true, "the focus is inside the pause panel")
	_press_key(KEY_UP)
	_press_key(KEY_TAB)
	_press_key(KEY_DOWN)
	await _frames(2)
	_equal(_focus_inside(pause), true, "arrow keys and tab keep the focus inside the pause panel")
	# A real click where the nameplate is, unless a pause button lies there.
	var target: Vector2 = _nameplate(screen).get_global_rect().get_center()
	var covered: bool = false
	for button_name: String in ["%ResumeButton", "%SettingsButton", "%TitleButton"]:
		if (pause.get_node(button_name) as Control).get_global_rect().grow(4.0).has_point(target):
			covered = true
	if covered:
		print("  note: a pause button lies over the nameplate; the click check is left out")
	else:
		_click(_nameplate(screen))
		await _frames(2)
		_equal(_overlay_count(screen), 1, "a click where the nameplate is opens nothing")
		_equal(_overlay(screen) == pause, true, "the pause panel is still the open panel")
	# A real click on continue closes the pause panel.
	_click(pause.get_node("%ResumeButton") as Control)
	await _frames(3)
	_equal(_overlay_count(screen), 0, "a click on continue closes the pause panel")
	_equal(_reachable(content), Vector2i(1, 1), "the nameplate takes input again")
	await _free(screen, game)


func _test_freed_with_panels_open() -> void:
	_section("the screen is replaced while panels are open: nothing is left behind")
	var settings: Node = get_node_or_null("/root/Settings")
	var settings_connections: int = _connection_count(settings, &"changed")
	# The question open.
	var game: Node = _game_playing(1, 600.0)
	var screen: Control = await _open(game)
	_nameplate(screen).pressed.emit()
	await _frames(2)
	var question: Control = _overlay(screen)
	await _free(screen, game, false)
	_equal(is_instance_valid(question), false, "the question went with the screen")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is left")
	game.free()

	# The pause panel open.
	game = _game_playing(1, 600.0)
	screen = await _open(game)
	_press_key(KEY_ESCAPE)
	await _frames(2)
	var pause: Control = _overlay(screen)
	_equal(game.blocked_reasons(), [&"pause_menu"], "the clock is stopped")
	await _free(screen, game, false)
	_equal(is_instance_valid(pause), false, "the pause panel went with the screen")
	_equal(game.blocked_reasons(), [], "the pause reason was released")
	game.free()

	# The pause panel and the settings screen open.
	game = _game_playing(1, 600.0)
	screen = await _open(game)
	_press_key(KEY_ESCAPE)
	await _frames(2)
	pause = _overlay(screen)
	(pause.get_node("%SettingsButton") as Button).pressed.emit()
	await _frames(2)
	var settings_screen: Control = pause.get_node("%OverlayLayer").get_child(0)
	await _free(screen, game, false)
	_equal(is_instance_valid(pause), false, "the pause panel went with the screen")
	_equal(is_instance_valid(settings_screen), false, "the settings screen went with the screen")
	_equal(game.blocked_reasons(), [], "the pause reason was released")
	_equal(_connection_count(settings, &"changed"), settings_connections, "no connection left on Settings.changed")
	game.free()


func _test_no_game_in_progress() -> void:
	_section("no game in progress: nothing to show, no crash")
	var game: Node = FakeGame.new()
	var screen: Control = await _open(game)
	_equal(_text(screen, "DayLabel"), "-", "no day")
	_equal(_text(screen, "TimeLabel"), "남은 시간 -", "no time")
	_equal(_nameplate(screen).disabled, true, "the nameplate cannot be pressed")
	await _free(screen, game)


func _test_missing_game() -> void:
	_section("no game object: an error, no crash")
	if get_node_or_null("/root/Game") != null:
		print("  SKIP: the autoload Game exists in this project, so this case cannot be produced")
		return
	print("  (the next engine error line is expected)")
	var screen: Control = SCREEN_SCENE.instantiate()
	add_child(screen)
	await _frames(2)
	_equal(_text(screen, "DayLabel"), "-", "nothing is shown")
	_equal(_nameplate(screen).disabled, true, "the nameplate cannot be pressed")
	_press_key(KEY_ESCAPE)
	await _frames(2)
	_equal(_overlay_count(screen), 1, "the pause panel still opens")
	_overlay(screen).close()
	await _frames(3)
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
	await _frames(2)
	_equal(_text(screen, "DayLabel"), "-", "nothing is shown")
	_equal(_nameplate(screen).disabled, true, "the nameplate cannot be pressed")
	screen.queue_free()
	await _frames(2)
	_equal(is_instance_valid(screen), false, "the screen is freed")
	bad.free()


func _test_layout() -> void:
	_section("layout: inside the safe area, nothing cut, nothing overlapping")
	var game: Node = _game_playing(88, 599.0)
	var screen: Control = await _open(game)
	var content: Control = screen.get_node("%Content")
	_equal(LayoutCheck.count_items(content), 3, "the check covers the day, the time and the nameplate")
	_no_thin_lines(screen, "workshop screen")
	for window_size: Vector2i in LAYOUT_SIZES:
		var tag: String = await _set_window_size(window_size)
		_check_covers_view(screen.get_node("%Background"), "%s: the background" % tag)
		_check_layout(content, "%s: workshop" % tag)

		_nameplate(screen).pressed.emit()
		await _frames(3)
		var question: Control = _overlay(screen)
		_check_covers_view(question, "%s: the question" % tag)
		_check_layout(question.get_node("%Panel"), "%s: question panel" % tag)
		if window_size == LAYOUT_SIZES[0]:
			_equal(LayoutCheck.count_items(question.get_node("%Panel")), 3, "the check covers the question and its two buttons")
			_no_thin_lines(question, "question panel")
		question.close()
		await _frames(3)

		_press_key(KEY_ESCAPE)
		await _frames(3)
		var pause: Control = _overlay(screen)
		_check_covers_view(pause, "%s: the pause panel" % tag)
		_check_layout(pause.get_node("%Panel"), "%s: pause panel" % tag)
		if window_size == LAYOUT_SIZES[0]:
			_equal(LayoutCheck.count_items(pause.get_node("%Panel")), 4, "the check covers the heading and three buttons")
			_no_thin_lines(pause, "pause panel")
		(pause.get_node("%SettingsButton") as Button).pressed.emit()
		await _frames(3)
		var settings_screen: Control = pause.get_node("%OverlayLayer").get_child(0)
		_check_covers_view(settings_screen, "%s: the settings screen over the pause panel" % tag)
		_check_layout(settings_screen.get_node("%Panel"), "%s: settings panel" % tag)
		settings_screen.close()
		await _frames(3)
		pause.close()
		await _frames(3)
	get_window().size = Vector2i(1920, 1080)
	await _frames(2)
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is left")
	await _free(screen, game)


func _test_no_leaks() -> void:
	_section("opening and closing every panel %d times leaves nothing behind" % OPEN_CLOSE_CYCLES)
	var settings: Node = get_node_or_null("/root/Settings")
	var game: Node = _game_playing(1, 600.0)
	var screen: Control = await _open(game)
	await _panel_round(screen, 0, null)

	var nodes_before: int = _node_count()
	var orphans_before: int = _orphan_count()
	var objects_before: int = _object_count()
	var connections_before: Dictionary = _connection_snapshot(screen, game, settings)
	var panels: Array[WeakRef] = []
	for cycle: int in OPEN_CLOSE_CYCLES:
		await _panel_round(screen, cycle, panels)
	var alive: int = 0
	for reference: WeakRef in panels:
		if reference.get_ref() != null:
			alive += 1
	var opened: int = panels.size()
	panels.clear()
	var connections_after: Dictionary = _connection_snapshot(screen, game, settings)
	print("  nodes %d -> %d, orphan nodes %d -> %d, objects %d -> %d" % [
		nodes_before, _node_count(), orphans_before, _orphan_count(), objects_before, _object_count()])
	print("  connections before: %s" % [connections_before])
	print("  connections after:  %s" % [connections_after])
	_equal(alive, 0, "every panel is freed (%d opened)" % opened)
	_equal(_overlay_count(screen), 0, "the layer is empty")
	_equal(_node_count(), nodes_before, "the node count is back where it was")
	_equal(_orphan_count(), orphans_before, "no orphan node was added")
	_equal(connections_after, connections_before, "every connection count is back where it was")
	_equal(_object_count() - objects_before < OPEN_CLOSE_CYCLES, true, "the object count does not grow with every cycle")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is left")
	_equal(game.count_calls("set_time_blocked(pause_menu, true)"), game.count_calls("set_time_blocked(pause_menu, false)"), "every stop has its release")
	_equal(game.core.calls.size(), 0, "no command reached the core")
	await _free(screen, game)


# --- Helpers -----------------------------------------------------------------

## Question (cancelled), pause panel, settings screen over it, all closed again.
func _panel_round(screen: Control, cycle: int, panels: Variant) -> void:
	_nameplate(screen).pressed.emit()
	await _frames(2)
	var question: Control = _overlay(screen)
	if panels != null:
		(panels as Array).append(weakref(question))
	if cycle % 2 == 0:
		(question.get_node("%CloseButton") as Button).pressed.emit()
	else:
		_press_key(KEY_ESCAPE)
	question = null
	await _frames(3)

	_press_key(KEY_ESCAPE)
	await _frames(2)
	var pause: Control = _overlay(screen)
	(pause.get_node("%SettingsButton") as Button).pressed.emit()
	await _frames(2)
	var settings_screen: Control = pause.get_node("%OverlayLayer").get_child(0)
	if panels != null:
		(panels as Array).append(weakref(pause))
		(panels as Array).append(weakref(settings_screen))
	settings_screen.close()
	settings_screen = null
	await _frames(3)
	if cycle % 2 == 0:
		(pause.get_node("%ResumeButton") as Button).pressed.emit()
	else:
		_press_key(KEY_ESCAPE)
	pause = null
	await _frames(3)


func _connection_snapshot(screen: Control, game: Node, settings: Node) -> Dictionary:
	return {
		"Settings.changed": _connection_count(settings, &"changed"),
		"Game.game_started": _connection_count(game, &"game_started"),
		"Game.game_ended": _connection_count(game, &"game_ended"),
		"core.day_ended": _connection_count(game.core, &"day_ended"),
		"core.day_started": _connection_count(game.core, &"day_started"),
		"into the workshop screen": screen.get_incoming_connections().size(),
		"NameplateButton.pressed": _connection_count(_nameplate(screen), &"pressed"),
	}


func _game_playing(day: int, time_left: float) -> Node:
	var game: Node = FakeGame.new()
	game.save_exists = true
	game.saved_day = day
	game.saved_time_left = time_left
	game.continue_game()
	game.calls.clear()
	return game


func _open(game: Node) -> Control:
	var screen: Control = SCREEN_SCENE.instantiate()
	screen.set_game(game)
	_title_requests = 0
	screen.connect(&"title_requested", _on_title_requested)
	add_child(screen)
	await get_tree().process_frame
	return screen


func _free(screen: Control, game: Node, free_game: bool = true) -> void:
	screen.queue_free()
	await _frames(2)
	_equal(is_instance_valid(screen), false, "the screen is freed")
	if free_game:
		game.free()


func _text(screen: Control, label_name: String) -> String:
	return (screen.get_node("%" + label_name) as Label).text


func _nameplate(screen: Control) -> Button:
	return screen.get_node("%NameplateButton") as Button


func _overlay_count(screen: Control) -> int:
	return screen.get_node("%OverlayLayer").get_child_count()


func _overlay(screen: Control) -> Control:
	var layer: Node = screen.get_node("%OverlayLayer")
	if layer.get_child_count() == 0:
		return null
	return layer.get_child(layer.get_child_count() - 1) as Control


func _on_title_requested() -> void:
	_title_requests += 1
