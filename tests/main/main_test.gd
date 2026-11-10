extends "res://tests/common/screen_test_base.gd"
## Headless test for the screen host and the flow of the screens
## (docs/roles/leader/outputs/13 work order, 3.1 and 3.7).
##
## Run:
##   godot --headless --path . res://tests/main/main_test.tscn -- --settings-path=user://test_settings.cfg
## Exit code 0 means every check passed. Any failure gives exit code 1.
## Without the argument the run does nothing and exits with 1.
##
## The host is tested against tests/common/fake_game.gd, which writes no file.
## The title screen, the workshop, the day summary and the settings screen are
## the real ones. The settings screen uses the real autoload Settings with the
## test settings file; no setting is changed here.

const MAIN_SCENE: PackedScene = preload("res://scenes/main/main.tscn")
const FakeGame: GDScript = preload("res://tests/common/fake_game.gd")

const TITLE_SCENE_PATH: String = "res://scenes/title/title_screen.tscn"
const WORKSHOP_SCENE_PATH: String = "res://scenes/workshop/workshop_screen.tscn"
const DAY_SUMMARY_SCENE_PATH: String = "res://scenes/day/day_summary_screen.tscn"
const DIALOG_SCENE_PATH: String = "res://scenes/common/dialog_panel.tscn"
const FLOW_CYCLES: int = 8


func _tag() -> String:
	return "main_test"


func _scene_path() -> String:
	return "res://tests/main/main_test.tscn"


func _run_tests() -> void:
	await _test_first_screen()
	await _test_continue_follows_the_save()
	await _test_new_game_without_save()
	await _test_new_game_with_save()
	await _test_new_game_fails()
	await _test_continue()
	await _test_continue_at_summary()
	await _test_continue_fails()
	await _test_day_ends_by_nameplate()
	await _test_day_ends_by_time()
	await _test_day_ends_under_panels()
	await _test_to_title()
	await _test_transition()
	await _test_game_started_from_outside()
	await _test_host_freed()
	await _test_missing_game()
	await _test_bad_game()
	await _test_layout()
	await _test_no_leaks()


# --- Tests -------------------------------------------------------------------

func _test_first_screen() -> void:
	_section("the first screen is the title screen")
	var game: Node = FakeGame.new()
	var host: Control = await _open(game)
	_equal(host.get_screen_kind(), &"title", "the host shows the title screen")
	_equal(_screen_path(host), TITLE_SCENE_PATH, "it is the title screen scene")
	_equal(_holder_count(host), 1, "one screen is under the host")
	_equal(host.is_transitioning(), false, "no swap is under way")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is set")
	_equal(game.count_calls("new_game") + game.count_calls("continue_game") + game.count_calls("end_game"), 0, "showing the title screen starts and ends nothing")
	_equal(_focus_name(), "NewGameButton", "new game has the focus")
	await _free(host, game)


func _test_continue_follows_the_save() -> void:
	_section("continue can be pressed only when a saved game exists")
	var game: Node = FakeGame.new()
	var host: Control = await _open(game)
	_equal(_title_button(host, "ContinueButton").disabled, true, "no save: continue cannot be pressed")
	await _free(host, game)
	game = FakeGame.new()
	game.save_exists = true
	host = await _open(game)
	_equal(_title_button(host, "ContinueButton").disabled, false, "a save: continue can be pressed")
	await _free(host, game)


func _test_new_game_without_save() -> void:
	_section("new game without a save: straight to the workshop")
	var game: Node = FakeGame.new()
	var host: Control = await _open(game)
	var title: Control = host.get_screen()
	var button: Button = _title_button(host, "NewGameButton")
	button.pressed.emit()
	button.pressed.emit()
	button.pressed.emit()
	_equal(game.count_calls("new_game"), 1, "three presses in one frame start one game")
	_equal(_overlay_count(host), 0, "no question is asked")
	await _settle(host)
	_equal(host.get_screen_kind(), &"workshop", "the host shows the workshop")
	_equal(_screen_path(host), WORKSHOP_SCENE_PATH, "it is the workshop scene")
	_equal(is_instance_valid(title), false, "the title screen is freed")
	_equal(_holder_count(host), 1, "one screen is under the host")
	_equal(_text(host, "DayLabel"), "1일차", "day 1")
	_equal(_text(host, "TimeLabel"), "남은 시간 10분 00초", "the whole day is left")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is left")
	_equal(game.count_calls("new_game"), 1, "still one game was started")
	await _free(host, game)


func _test_new_game_with_save() -> void:
	_section("new game with a save: only after the question")
	var game: Node = FakeGame.new()
	game.save_exists = true
	var host: Control = await _open(game)
	var button: Button = _title_button(host, "NewGameButton")
	button.pressed.emit()
	button.pressed.emit()
	_equal(_overlay_count(host), 1, "two presses open one question")
	var question: Control = _overlay(host)
	_equal(question.scene_file_path, DIALOG_SCENE_PATH, "it is the question panel")
	# The wording is fixed by docs/roles/leader/outputs/14 design, section 3.
	_equal((question.get_node("%Message") as Label).text, "새 게임을 시작하면 현재 진행중인 정보가 사라집니다. 그래도 새 게임을 시작하겠습니까?", "the question")
	_equal((question.get_node("%AcceptButton") as Button).text, "확인", "the accepting button")
	_equal((question.get_node("%CloseButton") as Button).text, "취소", "the cancelling button")
	_equal(game.count_calls("new_game"), 0, "nothing starts before the answer")
	await _frames(2)
	# Added in the 14 work: the question is too long for one line, so the panel
	# wraps it instead of growing sideways.
	var message: Label = question.get_node("%Message")
	_equal(message.get_line_count(), 2, "the long question is shown on two lines")
	_equal(message.get_visible_line_count(), message.get_line_count(), "every line of the question is visible")
	_equal((question.get_node("%Panel") as Control).size.x <= 1000.0, true, "the question panel stays narrow (%s wide)" % (question.get_node("%Panel") as Control).size.x)
	_equal(_focus_name(), "CloseButton", "the focus is on cancel")
	_equal(_reachable(host.get_screen()), Vector2i.ZERO, "the title screen behind takes neither focus nor mouse")
	# Menu presses behind the question do nothing.
	for name: String in ["NewGameButton", "ContinueButton", "SettingsButton", "CreditsButton"]:
		_title_button(host, name).pressed.emit()
	_equal(_overlay_count(host), 1, "presses on the menu behind open nothing more over the host")
	_equal(host.get_screen().get_node("%OverlayLayer").get_child_count(), 0, "and nothing over the title screen")
	_equal(game.count_calls("new_game") + game.count_calls("continue_game"), 0, "and start nothing")
	_equal(game.count_calls("set_time_blocked(transition, true)"), game.count_calls("set_time_blocked(transition, false)"), "and leave no swap begun")

	# Cancel: nothing happens.
	(question.get_node("%CloseButton") as Button).pressed.emit()
	await _frames(3)
	_equal(_overlay_count(host), 0, "cancel closes the question")
	_equal(game.count_calls("new_game"), 0, "cancel starts nothing")
	_equal(host.get_screen_kind(), &"title", "the title screen stays")
	_equal(_focus_name(), "NewGameButton", "the focus is back on the menu")
	_equal(_title_button(host, "ContinueButton").disabled, false, "continue can still be pressed")
	# Esc: the same.
	button.pressed.emit()
	await _frames(2)
	_press_key(KEY_ESCAPE)
	await _frames(3)
	_equal(_overlay_count(host), 0, "Esc closes the question")
	_equal(game.count_calls("new_game"), 0, "Esc starts nothing")

	# Confirm: one game.
	button.pressed.emit()
	await _frames(2)
	var accept: Button = _overlay(host).get_node("%AcceptButton")
	accept.pressed.emit()
	accept.pressed.emit()
	accept.pressed.emit()
	_equal(game.count_calls("new_game"), 1, "three presses on confirm start one game")
	await _settle(host)
	_equal(host.get_screen_kind(), &"workshop", "the host shows the workshop")
	_equal(_overlay_count(host), 0, "the question is gone")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is left")
	await _free(host, game)


func _test_new_game_fails() -> void:
	_section("new game fails: a notice, and the title screen stays")
	var game: Node = FakeGame.new()
	game.new_game_succeeds = false
	var host: Control = await _open(game)
	_title_button(host, "NewGameButton").pressed.emit()
	_title_button(host, "NewGameButton").pressed.emit()
	_equal(game.count_calls("new_game"), 1, "new_game was called once")
	_equal(_overlay_count(host), 1, "one notice is open")
	var notice: Control = _overlay(host)
	_equal((notice.get_node("%Message") as Label).get_line_count(), 1, "a short notice stays on one line")
	_equal((notice.get_node("%Message") as Label).text, "새 게임을 시작하지 못했습니다.", "the notice")
	_equal((notice.get_node("%AcceptButton") as Button).visible, false, "a notice has no accepting button")
	_equal((notice.get_node("%CloseButton") as Button).text, "닫기", "the closing button")
	_equal(host.get_screen_kind(), &"title", "the title screen stays")
	(notice.get_node("%CloseButton") as Button).pressed.emit()
	await _frames(3)
	_equal(_overlay_count(host), 0, "the notice closes")
	_equal(_focus_name(), "NewGameButton", "the focus is back on the menu")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is set")
	await _free(host, game)

	# With a save: the question first, then the notice.
	game = FakeGame.new()
	game.save_exists = true
	game.new_game_succeeds = false
	host = await _open(game)
	_title_button(host, "NewGameButton").pressed.emit()
	await _frames(2)
	(_overlay(host).get_node("%AcceptButton") as Button).pressed.emit()
	_equal(game.count_calls("new_game"), 1, "new_game was called once after the question")
	await _frames(4)
	_equal(_overlay_count(host), 1, "one panel is open after the question closed")
	_equal((_overlay(host).get_node("%Message") as Label).text, "새 게임을 시작하지 못했습니다.", "it is the notice")
	_equal(host.get_screen_kind(), &"title", "the title screen stays")
	_press_key(KEY_ESCAPE)
	await _frames(3)
	_equal(_overlay_count(host), 0, "Esc closes the notice")
	await _free(host, game)


func _test_continue() -> void:
	_section("continue: to the workshop, at the saved day and time")
	var game: Node = FakeGame.new()
	game.save_exists = true
	game.saved_day = 4
	game.saved_time_left = 125.0
	var host: Control = await _open(game)
	var button: Button = _title_button(host, "ContinueButton")
	button.pressed.emit()
	button.pressed.emit()
	button.pressed.emit()
	_equal(game.count_calls("continue_game"), 1, "three presses in one frame continue once")
	_equal(game.count_calls("new_game"), 0, "no new game is started")
	await _settle(host)
	_equal(host.get_screen_kind(), &"workshop", "the host shows the workshop")
	_equal(_text(host, "DayLabel"), "4일차", "the saved day")
	_equal(_text(host, "TimeLabel"), "남은 시간 2분 05초", "the saved time left")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is left")
	await _free(host, game)


func _test_continue_at_summary() -> void:
	_section("continue a game saved at a day summary: to the day summary")
	var game: Node = FakeGame.new()
	game.save_exists = true
	game.saved_day = 6
	game.saved_phase = &"summary"
	game.saved_time_left = 0.0
	game.saved_summary = {"day": 6, "ended_by": &"time", "time_used": 600.0}
	var host: Control = await _open(game)
	_title_button(host, "ContinueButton").pressed.emit()
	await _settle(host)
	_equal(host.get_screen_kind(), &"day_summary", "the host shows the day summary")
	_equal(_screen_path(host), DAY_SUMMARY_SCENE_PATH, "it is the day summary scene")
	_equal(_text(host, "Heading"), "6일차가 끝났습니다", "the saved summary is shown")
	(host.get_screen().get_node("%NextDayButton") as Button).pressed.emit()
	await _settle(host)
	_equal(host.get_screen_kind(), &"workshop", "next day goes to the workshop")
	_equal(_text(host, "DayLabel"), "7일차", "day 7")
	await _free(host, game)


func _test_continue_fails() -> void:
	_section("continue fails: a notice, and the title screen stays")
	var game: Node = FakeGame.new()
	game.save_exists = true
	game.continue_succeeds = false
	var host: Control = await _open(game)
	var title: Control = host.get_screen()
	# The focus is where a click or the keyboard would have put it.
	_title_button(host, "ContinueButton").grab_focus()
	_title_button(host, "ContinueButton").pressed.emit()
	_title_button(host, "ContinueButton").pressed.emit()
	_equal(game.count_calls("continue_game"), 1, "continue_game was called once")
	_equal(_overlay_count(host), 1, "one notice is open")
	var notice: Control = _overlay(host)
	_equal((notice.get_node("%Message") as Label).text, "저장된 게임을 읽지 못했습니다.", "the notice")
	_equal((notice.get_node("%CloseButton") as Button).text, "닫기", "the closing button")
	await _frames(2)
	_equal(_focus_inside(notice), true, "the focus is inside the notice")
	_equal(host.get_screen() == title, true, "the same title screen stays")
	_equal(game.core == null, true, "no game is in progress")
	(notice.get_node("%CloseButton") as Button).pressed.emit()
	await _frames(3)
	_equal(_overlay_count(host), 0, "the notice closes")
	_equal(host.get_screen_kind(), &"title", "the title screen stays")
	_equal(_focus_name(), "ContinueButton", "the focus is back on the menu")
	_equal(game.count_calls("new_game"), 0, "nothing else was called")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is set")
	await _free(host, game)


func _test_day_ends_by_nameplate() -> void:
	_section("nameplate -> day summary -> next day -> workshop")
	var game: Node = FakeGame.new()
	var host: Control = await _start_game(game)
	game.tick(187.9)
	var workshop: Control = host.get_screen()
	(workshop.get_node("%NameplateButton") as Button).pressed.emit()
	await _frames(2)
	(workshop.get_node("%OverlayLayer").get_child(0).get_node("%AcceptButton") as Button).pressed.emit()
	_equal(game.core.count_calls("request_end_day"), 1, "the nameplate sent the request once")
	_equal(host.get_screen_kind(), &"workshop", "the workshop stays until the core ends the day")
	await _frames(2)
	game.tick(0.0)
	await _settle(host)
	_equal(host.get_screen_kind(), &"day_summary", "after the core's tick the host shows the day summary")
	_equal(is_instance_valid(workshop), false, "the workshop is freed")
	_equal(_holder_count(host), 1, "one screen is under the host")
	_equal(_text(host, "Heading"), "1일차가 끝났습니다", "which day ended")
	_equal(_text(host, "EndedByLabel"), "명패로 닫음", "how it ended")
	_equal(_text(host, "TimeUsedLabel"), "쓴 시간 3분 07초", "time used, as in the summary of the core")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is left")
	# While the summary is shown the clock does not run (the core's own rule).
	game.tick(50.0)
	_equal(game.core.state.day, 1, "ticks during the summary change nothing")

	var summary_screen: Control = host.get_screen()
	var next: Button = summary_screen.get_node("%NextDayButton")
	next.pressed.emit()
	next.pressed.emit()
	next.pressed.emit()
	_equal(game.core.count_calls("confirm_day_summary"), 1, "three presses on next day send one command")
	await _settle(host)
	_equal(host.get_screen_kind(), &"workshop", "the host shows the workshop again")
	_equal(is_instance_valid(summary_screen), false, "the day summary is freed")
	_equal(_text(host, "DayLabel"), "2일차", "day 2")
	_equal(_text(host, "TimeLabel"), "남은 시간 10분 00초", "a whole day is left")
	_equal((host.get_screen().get_node("%NameplateButton") as Button).disabled, false, "the nameplate of the new day can be pressed")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is left")
	_equal(game.count_calls("end_game"), 0, "the game was not ended")
	await _free(host, game)


func _test_day_ends_by_time() -> void:
	_section("the time runs out -> day summary")
	var game: Node = FakeGame.new()
	var host: Control = await _start_game(game)
	game.tick(599.0)
	await _frames(2)
	_equal(_text(host, "TimeLabel"), "남은 시간 0분 01초", "one second left")
	game.tick(5.0)
	await _settle(host)
	_equal(host.get_screen_kind(), &"day_summary", "the host shows the day summary")
	_equal(_text(host, "EndedByLabel"), "시간이 다 됨", "how it ended")
	_equal(_text(host, "TimeUsedLabel"), "쓴 시간 10분 00초", "the whole day was used")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is left")
	await _free(host, game)


func _test_day_ends_under_panels() -> void:
	_section("day_ended while a panel is open: the panel goes, the day summary comes")
	var settings: Node = get_node_or_null("/root/Settings")
	var settings_connections: int = _connection_count(settings, &"changed")
	for case: String in ["question", "pause", "pause and settings"]:
		var game: Node = FakeGame.new()
		var host: Control = await _start_game(game)
		var workshop: Control = host.get_screen()
		var panels: Array[Control] = []
		if case == "question":
			(workshop.get_node("%NameplateButton") as Button).pressed.emit()
			await _frames(2)
			panels.append(workshop.get_node("%OverlayLayer").get_child(0))
		else:
			_press_key(KEY_ESCAPE)
			await _frames(2)
			var pause: Control = workshop.get_node("%OverlayLayer").get_child(0)
			panels.append(pause)
			_equal(game.blocked_reasons(), [&"pause_menu"], "%s: the clock is stopped" % case)
			if case == "pause and settings":
				(pause.get_node("%SettingsButton") as Button).pressed.emit()
				await _frames(2)
				panels.append(pause.get_node("%OverlayLayer").get_child(0))
		# Straight to the core, past the stopped clock: day_ended can come
		# whatever the screen is doing.
		game.core.tick(700.0)
		_equal(game.core.state.phase, &"summary", "%s: the core ended the day" % case)
		await _settle(host)
		_equal(host.get_screen_kind(), &"day_summary", "%s: the host shows the day summary" % case)
		_equal(is_instance_valid(workshop), false, "%s: the workshop is freed" % case)
		var left: int = 0
		for panel: Control in panels:
			if is_instance_valid(panel):
				left += 1
		_equal(left, 0, "%s: no panel is left (%d were open)" % [case, panels.size()])
		_equal(_holder_count(host), 1, "%s: one screen is under the host" % case)
		_equal(_overlay_count(host), 0, "%s: nothing is open over the host" % case)
		_equal(game.blocked_reasons(), [], "%s: no reason to stop the clock is left" % case)
		_equal(_connection_count(settings, &"changed"), settings_connections, "%s: no connection left on Settings.changed" % case)
		_equal(_focus_name(), "NextDayButton", "%s: next day has the focus" % case)
		panels.clear()
		await _free(host, game)


func _test_to_title() -> void:
	_section("pause -> to the title screen: end_game once, then the title screen")
	var game: Node = FakeGame.new()
	var host: Control = await _start_game(game)
	game.tick(100.0)
	var workshop: Control = host.get_screen()
	_press_key(KEY_ESCAPE)
	await _frames(2)
	var pause: Control = workshop.get_node("%OverlayLayer").get_child(0)
	var button: Button = pause.get_node("%TitleButton")
	button.pressed.emit()
	button.pressed.emit()
	button.pressed.emit()
	_equal(game.count_calls("end_game"), 1, "three presses in one frame end the game once")
	_equal(game.core == null, true, "no game is in progress")
	await _settle(host)
	_equal(host.get_screen_kind(), &"title", "the host shows the title screen")
	_equal(is_instance_valid(workshop), false, "the workshop is freed")
	_equal(is_instance_valid(pause), false, "the pause panel is freed")
	_equal(_holder_count(host), 1, "one screen is under the host")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is left")
	_equal(_title_button(host, "ContinueButton").disabled, false, "continue can be pressed: the game was saved")
	_equal(_focus_name(), "NewGameButton", "new game has the focus")
	_equal(game.count_calls("end_game"), 1, "still one end_game")

	# Continue brings the same game back.
	_title_button(host, "ContinueButton").pressed.emit()
	await _settle(host)
	_equal(host.get_screen_kind(), &"workshop", "continue goes to the workshop")
	_equal(_text(host, "TimeLabel"), "남은 시간 8분 20초", "at the time the game was left")
	await _free(host, game)


func _test_transition() -> void:
	_section("swapping the screen: the clock is stopped, input is ignored, and it ends")
	var game: Node = FakeGame.new()
	game.save_exists = true
	var host: Control = await _open(game)
	var title: Control = host.get_screen()
	var first_transition_calls: int = game.count_calls("set_time_blocked(transition, true)")
	_equal(first_transition_calls, game.count_calls("set_time_blocked(transition, false)"), "the first screen: every stop has its release")
	game.calls.clear()

	_title_button(host, "ContinueButton").pressed.emit()
	# The same frame: the title screen is on its way out.
	_equal(host.is_transitioning(), true, "the swap has begun")
	_equal(host.get_screen() == null, true, "the host shows no screen during the swap")
	_equal(game.blocked_reasons(), [&"transition"], "the clock is stopped with transition")
	_equal(title.is_queued_for_deletion(), true, "the title screen is being freed")
	game.tick(50.0)
	_equal(game.core.state.day_time_left, 600.0, "a tick during the swap does not move the clock")
	# Input during the swap.
	_title_button_of(title, "NewGameButton").pressed.emit()
	_title_button_of(title, "ContinueButton").pressed.emit()
	_title_button_of(title, "SettingsButton").pressed.emit()
	_title_button_of(title, "CreditsButton").pressed.emit()
	_press_key(KEY_ESCAPE)
	_press_key(KEY_ENTER)
	_equal(game.count_calls("continue_game"), 1, "continue during the swap is ignored")
	_equal(game.count_calls("new_game"), 0, "new game during the swap is ignored")
	_equal(_overlay_count(host), 0, "nothing opens over the host during the swap")
	_equal(title.get_node("%OverlayLayer").get_child_count(), 0, "nothing opens over the leaving title screen")
	await _settle(host)
	_equal(host.is_transitioning(), false, "the swap has ended")
	_equal(host.get_screen_kind(), &"workshop", "the host shows the workshop")
	_equal(game.blocked_reasons(), [], "transition is released")
	_equal(game.count_calls("set_time_blocked(transition, true)"), 1, "it was set once")
	_equal(game.count_calls("set_time_blocked(transition, false)"), 1, "and released once")
	_equal(host.get_screen().get_node("%OverlayLayer").get_child_count(), 0, "the Esc pressed during the swap did not open the pause panel")
	game.tick(1.0)
	_equal(game.core.state.day_time_left, 599.0, "the clock runs again")

	# The state moves on twice within one swap: day ends, next day starts.
	game.core.tick(1000.0)
	_equal(host.is_transitioning(), true, "day_ended began a swap")
	game.core.confirm_day_summary()
	await _settle(host)
	_equal(host.get_screen_kind(), &"workshop", "the host ends at the screen of the state as it is now")
	_equal(_text(host, "DayLabel"), "2일차", "day 2")
	_equal(_holder_count(host), 1, "one screen is under the host")
	_equal(game.blocked_reasons(), [], "transition is released")
	await _free(host, game)


func _test_game_started_from_outside() -> void:
	_section("a game that starts while the workshop is shown gets a new workshop")
	var game: Node = FakeGame.new()
	var host: Control = await _start_game(game)
	var workshop: Control = host.get_screen()
	var old_core: WeakRef = weakref(game.core)
	(workshop.get_node("%NameplateButton") as Button).pressed.emit()
	await _frames(2)
	(workshop.get_node("%OverlayLayer").get_child(0).get_node("%AcceptButton") as Button).pressed.emit()
	await _frames(3)
	_equal((workshop.get_node("%NameplateButton") as Button).disabled, true, "the nameplate of the old game is locked")
	game.new_game()
	await _settle(host)
	_equal(host.get_screen_kind(), &"workshop", "the host shows the workshop")
	_equal(is_instance_valid(workshop), false, "the workshop of the game before is freed")
	_equal((host.get_screen().get_node("%NameplateButton") as Button).disabled, false, "the nameplate of the new game can be pressed")
	_equal(old_core.get_ref() == null, true, "the core of the game before is gone: nothing kept it")
	_equal(_connection_count(game.core, &"day_ended"), 1, "the host is connected to the new core's day_ended")
	_equal(_connection_count(game.core, &"day_started"), 1, "and to its day_started")
	game.core.tick(1000.0)
	await _settle(host)
	_equal(host.get_screen_kind(), &"day_summary", "day_ended of the new core is followed")
	await _free(host, game)


func _test_host_freed() -> void:
	_section("the host is freed: connections and stopped clocks are not left behind")
	var game: Node = FakeGame.new()
	var host: Control = await _start_game(game)
	_equal(_connection_count(game, &"game_started"), 1, "the host is connected to game_started")
	_equal(_connection_count(game, &"game_ended"), 1, "and to game_ended")
	_equal(_connection_count(game.core, &"day_ended"), 1, "and to the core's day_ended")
	# Freed in the middle of a swap, with the pause panel open.
	_press_key(KEY_ESCAPE)
	await _frames(2)
	game.core.tick(1000.0)
	_equal(host.is_transitioning(), true, "a swap is under way")
	host.queue_free()
	await _frames(3)
	_equal(is_instance_valid(host), false, "the host is freed")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is left")
	_equal(_connection_count(game, &"game_started"), 0, "nothing is connected to game_started")
	_equal(_connection_count(game, &"game_ended"), 0, "nothing is connected to game_ended")
	_equal(_connection_count(game.core, &"day_ended"), 0, "nothing is connected to the core's day_ended")
	_equal(_connection_count(game.core, &"day_started"), 0, "nothing is connected to the core's day_started")
	game.free()


func _test_missing_game() -> void:
	_section("no game object: an error, the title screen still works, new game gives the notice")
	if get_node_or_null("/root/Game") != null:
		print("  SKIP: the autoload Game exists in this project, so this case cannot be produced")
		return
	print("  (the next engine error line is expected)")
	var host: Control = MAIN_SCENE.instantiate()
	add_child(host)
	await _frames(2)
	_equal(host.get_screen_kind(), &"title", "the host shows the title screen")
	_equal(_title_button(host, "ContinueButton").disabled, true, "continue cannot be pressed")
	_title_button(host, "NewGameButton").pressed.emit()
	await _frames(2)
	_equal(_overlay_count(host), 1, "new game opens a notice")
	_equal((_overlay(host).get_node("%Message") as Label).text, "새 게임을 시작하지 못했습니다.", "the notice")
	_overlay(host).close()
	await _frames(3)
	_title_button(host, "CreditsButton").pressed.emit()
	await _frames(2)
	_equal(host.get_screen().get_node("%OverlayLayer").get_child_count(), 1, "the credits panel still opens")
	host.queue_free()
	await _frames(3)
	_equal(is_instance_valid(host), false, "the host is freed")


func _test_bad_game() -> void:
	_section("an object that does not follow the contract: an error, no crash")
	print("  (the next engine error line is expected)")
	var bad: Node = Node.new()
	var host: Control = MAIN_SCENE.instantiate()
	host.set_game(bad)
	add_child(host)
	await _frames(2)
	_equal(host.get_screen_kind(), &"title", "the host shows the title screen")
	_title_button(host, "NewGameButton").pressed.emit()
	await _frames(2)
	_equal(_overlay_count(host), 1, "new game opens a notice")
	host.queue_free()
	await _frames(3)
	_equal(is_instance_valid(host), false, "the host is freed")
	bad.free()

	_section("set_game after entering the tree is refused")
	print("  (the next engine error line is expected)")
	var game: Node = FakeGame.new()
	var other: Node = FakeGame.new()
	host = await _open(game)
	host.set_game(other)
	_title_button(host, "NewGameButton").pressed.emit()
	_equal(game.count_calls("new_game"), 1, "the first object is still used")
	_equal(other.calls.size(), 0, "the second object is not used")
	await _settle(host)
	await _free(host, game)
	other.free()


func _test_layout() -> void:
	_section("layout of the host's own panels over the title screen")
	var game: Node = FakeGame.new()
	game.save_exists = true
	game.continue_succeeds = false
	var host: Control = await _open(game)
	_no_thin_lines(host, "host with the title screen")
	for window_size: Vector2i in LAYOUT_SIZES:
		var tag: String = await _set_window_size(window_size)
		_check_covers_view(host.get_node("%Background"), "%s: the host's background" % tag)
		_check_covers_view(host.get_screen(), "%s: the title screen in the host" % tag)
		_check_layout(host.get_screen().get_node("%Content"), "%s: title screen in the host" % tag)
		_title_button(host, "NewGameButton").pressed.emit()
		await _frames(3)
		_check_covers_view(_overlay(host), "%s: the question" % tag)
		_check_layout(_overlay(host).get_node("%Panel"), "%s: new game question" % tag)
		_overlay(host).close()
		await _frames(3)
		_title_button(host, "ContinueButton").pressed.emit()
		await _frames(3)
		_check_layout(_overlay(host).get_node("%Panel"), "%s: continue failed notice" % tag)
		if window_size == LAYOUT_SIZES[0]:
			_equal(LayoutCheck.count_items(_overlay(host).get_node("%Panel")), 2, "the check covers the notice and its button")
		_overlay(host).close()
		await _frames(3)
	get_window().size = Vector2i(1920, 1080)
	await _frames(2)
	await _free(host, game)


func _test_no_leaks() -> void:
	_section("new game -> day ends -> next day -> to the title screen, %d times" % FLOW_CYCLES)
	var settings: Node = get_node_or_null("/root/Settings")
	var game: Node = FakeGame.new()
	var host: Control = await _open(game)
	await _flow_round(host, game, 0, null, null)

	var nodes_before: int = _node_count()
	var orphans_before: int = _orphan_count()
	var objects_before: int = _object_count()
	var connections_before: Dictionary = _connection_snapshot(host, game, settings)
	var screens: Array[WeakRef] = []
	var cores: Array[WeakRef] = []
	var most_screens: int = 0
	for cycle: int in FLOW_CYCLES:
		most_screens = maxi(most_screens, await _flow_round(host, game, cycle, screens, cores))
	var screens_alive: int = 0
	for reference: WeakRef in screens:
		if reference.get_ref() != null:
			screens_alive += 1
	var cores_alive: int = 0
	for reference: WeakRef in cores:
		if reference.get_ref() != null:
			cores_alive += 1
	var screens_seen: int = screens.size()
	var cores_seen: int = cores.size()
	screens.clear()
	cores.clear()
	var connections_after: Dictionary = _connection_snapshot(host, game, settings)
	print("  nodes %d -> %d, orphan nodes %d -> %d, objects %d -> %d" % [
		nodes_before, _node_count(), orphans_before, _orphan_count(), objects_before, _object_count()])
	print("  connections before: %s" % [connections_before])
	print("  connections after:  %s" % [connections_after])
	_equal(host.get_screen_kind(), &"title", "the flow ends at the title screen")
	_equal(most_screens, 1, "never more than one screen under the host")
	# The title screen that is shown now is the only one still alive.
	_equal(screens_alive, 1, "every screen but the shown one is freed (%d seen)" % screens_seen)
	_equal(cores_alive, 0, "every core is gone: nothing kept one (%d seen)" % cores_seen)
	_equal(_node_count(), nodes_before, "the node count is back where it was")
	_equal(_orphan_count(), orphans_before, "no orphan node was added")
	_equal(connections_after, connections_before, "every connection count is back where it was")
	_equal(_object_count() - objects_before < FLOW_CYCLES, true, "the object count does not grow with every cycle")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is left")
	_equal(game.count_calls("set_time_blocked(transition, true)"), game.count_calls("set_time_blocked(transition, false)"), "every transition stop has its release")
	_equal(game.count_calls("set_time_blocked(pause_menu, true)"), game.count_calls("set_time_blocked(pause_menu, false)"), "every pause stop has its release")
	_equal(game.count_calls("new_game"), FLOW_CYCLES + 1, "one new game per round")
	_equal(game.count_calls("end_game"), FLOW_CYCLES + 1, "one end_game per round")
	await _free(host, game)
	_equal(_connection_count(settings, &"changed"), connections_before["Settings.changed"], "nothing is connected to Settings.changed after the host is freed")


# --- Helpers -----------------------------------------------------------------

## One whole round from the title screen back to the title screen. Returns the
## largest number of screens seen under the host.
func _flow_round(host: Control, game: Node, cycle: int, screens: Variant, cores: Variant) -> int:
	var most: int = _holder_count(host)
	_note(screens, host.get_screen())
	# New game (with the question once a save exists).
	_title_button(host, "NewGameButton").pressed.emit()
	if _overlay_count(host) == 1:
		await _frames(2)
		(_overlay(host).get_node("%AcceptButton") as Button).pressed.emit()
	await _settle(host)
	most = maxi(most, _holder_count(host))
	_note(screens, host.get_screen())
	_note(cores, game.core)
	# The day ends: by the nameplate on even rounds, by the time on odd ones.
	if cycle % 2 == 0:
		var workshop: Control = host.get_screen()
		(workshop.get_node("%NameplateButton") as Button).pressed.emit()
		await _frames(2)
		(workshop.get_node("%OverlayLayer").get_child(0).get_node("%AcceptButton") as Button).pressed.emit()
		workshop = null
		await _frames(2)
		game.tick(0.0)
	else:
		game.tick(1000.0)
	await _settle(host)
	most = maxi(most, _holder_count(host))
	_note(screens, host.get_screen())
	# Next day.
	(host.get_screen().get_node("%NextDayButton") as Button).pressed.emit()
	await _settle(host)
	most = maxi(most, _holder_count(host))
	_note(screens, host.get_screen())
	# Pause, the settings screen once, then to the title screen.
	_press_key(KEY_ESCAPE)
	await _frames(2)
	var pause: Control = host.get_screen().get_node("%OverlayLayer").get_child(0)
	_note(screens, pause)
	(pause.get_node("%SettingsButton") as Button).pressed.emit()
	await _frames(2)
	var settings_screen: Control = pause.get_node("%OverlayLayer").get_child(0)
	_note(screens, settings_screen)
	settings_screen.close()
	settings_screen = null
	await _frames(3)
	(pause.get_node("%TitleButton") as Button).pressed.emit()
	pause = null
	await _settle(host)
	most = maxi(most, _holder_count(host))
	_note(screens, host.get_screen())
	return most


func _note(list: Variant, object: Object) -> void:
	if list != null and object != null:
		(list as Array).append(weakref(object))


func _connection_snapshot(host: Control, game: Node, settings: Node) -> Dictionary:
	return {
		"Settings.changed": _connection_count(settings, &"changed"),
		"Game.game_started": _connection_count(game, &"game_started"),
		"Game.game_ended": _connection_count(game, &"game_ended"),
		"into the host": host.get_incoming_connections().size(),
		"into the shown screen": host.get_screen().get_incoming_connections().size(),
	}


func _open(game: Node) -> Control:
	var host: Control = MAIN_SCENE.instantiate()
	host.set_game(game)
	add_child(host)
	await _frames(2)
	return host


## A host with a new game in progress, showing the workshop.
func _start_game(game: Node) -> Control:
	var host: Control = await _open(game)
	_title_button(host, "NewGameButton").pressed.emit()
	await _settle(host)
	game.calls.clear()
	return host


## Waits until the swap of the screen has ended and the new screen is ready.
func _settle(host: Control) -> void:
	for attempt: int in 10:
		await get_tree().process_frame
		if not host.is_transitioning() and host.get_screen() != null:
			break
	await _frames(2)


func _free(host: Control, game: Node) -> void:
	host.queue_free()
	await _frames(3)
	_equal(is_instance_valid(host), false, "the host is freed")
	_equal(game.blocked_reasons(), [], "no reason to stop the clock is left after the host is freed")
	game.free()


func _holder_count(host: Control) -> int:
	return host.get_node("%ScreenHolder").get_child_count()


func _overlay_count(host: Control) -> int:
	return host.get_node("%OverlayLayer").get_child_count()


func _overlay(host: Control) -> Control:
	var layer: Node = host.get_node("%OverlayLayer")
	if layer.get_child_count() == 0:
		return null
	return layer.get_child(layer.get_child_count() - 1) as Control


func _screen_path(host: Control) -> String:
	return host.get_screen().scene_file_path if host.get_screen() != null else "(none)"


func _text(host: Control, label_name: String) -> String:
	return (host.get_screen().get_node("%" + label_name) as Label).text


func _title_button(host: Control, button_name: String) -> Button:
	return host.get_screen().get_node("%" + button_name) as Button


func _title_button_of(title: Control, button_name: String) -> Button:
	return title.get_node("%" + button_name) as Button
