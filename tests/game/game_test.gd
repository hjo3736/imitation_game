extends Node
## Headless tests for the autoload Game (scripts/game/game.gd): starting,
## ending and continuing a game, the save file, blocking time, the balance file.
##
## Run:
##   godot --headless --path . res://tests/game/game_test.tscn -- --settings-path=user://test_settings.cfg --save-path=user://test_save.json
## Exit code 0 when every check passes, 1 otherwise. Without the two arguments
## the run is not isolated from the player's files: it does nothing and exits
## with 1.
##
## The autoload Game uses the save file named on the command line and the
## game's balance file. The Game objects the tests make themselves
## (tests/game/game_under_test.gd) use OWN_SAVE_PATH and test balance files.
## All test files are removed at the end.

const GameUnderTest: GDScript = preload("res://tests/game/game_under_test.gd")
const Isolation: GDScript = preload("res://tests/common/game_isolation.gd")

const SCENE_PATH: String = "res://tests/game/game_test.tscn"
const TAG: String = "game_test"
const GAME_BALANCE_PATH: String = "res://data/balance.json"
const OWN_SAVE_PATH: String = "user://game_test_own_save.json"
const BROKEN_BALANCE_PATH: String = "user://game_test_broken_balance.json"
const TEST_BALANCE: String = "res://tests/game/balance_test.json"
const SHORT_DAY_BALANCE: String = "res://tests/game/balance_short_day.json"
const LONG_DAY_BALANCE: String = "res://tests/game/balance_long_day.json"
## Test numbers, not the game's numbers.
const TEST_DAY_LENGTH: float = 120.0
const WAIT_MSEC: int = 150
const TIME_TOLERANCE: float = 0.000001

var _check_count: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _current_test: String = ""
var _started_count: int = 0
var _ended_count: int = 0
var _core_at_start: GameCore = null
var _blocked_at_start: bool = false
var _save_file_at_start: bool = false
var _temporary_file_at_start: bool = false
var _core_at_end: GameCore = null
var _own_games: Array[Node] = []


func _ready() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	if not Isolation.begin(get_tree(), TAG, SCENE_PATH, true):
		get_tree().quit(1)
		return
	Game.game_started.connect(_on_game_started)
	Game.game_ended.connect(_on_game_ended)

	await _run("contract", _test_contract)
	await _run("new_game_and_save_file", _test_new_game_and_save_file)
	await _run("clock_runs_and_blocks", _test_clock_runs_and_blocks)
	await _run("end_and_continue", _test_end_and_continue)
	await _run("save_points", _test_save_points)
	await _run("new_game_overwrites", _test_new_game_overwrites)
	await _run("unreadable_save", _test_unreadable_save)
	await _run("save_replaces_whole_file", _test_save_replaces_whole_file)
	await _run("balance_file", _test_balance_file)
	await _run("day_length_change", _test_day_length_change)
	await _run("temporary_save_file", _test_temporary_save_file)
	await _run("temporary_file_cannot_be_moved", _test_temporary_file_cannot_be_moved)
	await _run("save_when_the_game_closes", _test_save_when_the_game_closes)

	Game.game_started.disconnect(_on_game_started)
	Game.game_ended.disconnect(_on_game_ended)
	_current_test = "isolation"
	_remove(OWN_SAVE_PATH)
	_remove(OWN_SAVE_PATH + ".tmp")
	_remove(BROKEN_BALANCE_PATH)
	_check(not FileAccess.file_exists(OWN_SAVE_PATH), "the tests' own save file was left behind")
	_check(Isolation.finish(get_tree(), TAG), "the player's files changed or a test file is still there")

	print("[%s] checks=%d failures=%d" % [TAG, _check_count, _failures.size()])
	for failure: String in _failures:
		print("[%s] FAIL %s" % [TAG, failure])
	print("[%s] RESULT %s" % [TAG, "PASS" if _failures.is_empty() else "FAIL"])
	get_tree().quit(0 if _failures.is_empty() else 1)


# --- Helpers ------------------------------------------------------------------

func _run(test_name: String, test: Callable) -> void:
	_current_test = test_name
	if Game.core != null:
		Game.end_game()
	Isolation.remove_test_save(get_tree())
	_started_count = 0
	_ended_count = 0
	var failures_before: int = _failures.size()
	await test.call()
	for game: Node in _own_games.duplicate():
		_discard(game)
	if Game.core != null:
		Game.end_game()
	Game.set_time_blocked(&"pause_menu", false)
	Game.set_time_blocked(&"transition", false)
	Isolation.remove_test_save(get_tree())
	_remove(OWN_SAVE_PATH)
	_remove(OWN_SAVE_PATH + ".tmp")
	print("[%s] %s %s" % [TAG, "ok  " if _failures.size() == failures_before else "FAIL", test_name])


func _check(condition: bool, message: String) -> void:
	_check_count += 1
	if not condition:
		_failures.append("%s: %s" % [_current_test, message])


func _check_equal(actual: Variant, expected: Variant, what: String) -> void:
	var same: bool = typeof(actual) == typeof(expected) and actual == expected
	_check(same, "%s: expected %s (%s), got %s (%s)" % [
		what, str(expected), type_string(typeof(expected)), str(actual), type_string(typeof(actual))])


func _check_close(actual: float, expected: float, what: String) -> void:
	_check(absf(actual - expected) <= TIME_TOLERANCE, "%s: expected %f, got %f" % [what, expected, actual])


func _on_game_started() -> void:
	_started_count += 1
	_core_at_start = Game.core
	_blocked_at_start = Game.is_time_blocked()
	_save_file_at_start = FileAccess.file_exists(Game.get_save_path())
	_temporary_file_at_start = FileAccess.file_exists(Game.get_save_path() + ".tmp")


func _on_game_ended() -> void:
	_ended_count += 1
	_core_at_end = Game.core


## Lets real time and frames pass.
func _wait(msec: int = WAIT_MSEC) -> void:
	var until: int = Time.get_ticks_msec() + msec
	await get_tree().process_frame
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _frames(count: int) -> void:
	for index: int in count:
		await get_tree().process_frame


## The day length in the game's balance file, read here so that the test holds
## no game number.
func _game_day_length() -> float:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(GAME_BALANCE_PATH))
	return float((data as Dictionary)["day_length_seconds"])


func _read_save(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _md5(path: String) -> String:
	return FileAccess.get_md5(path) if FileAccess.file_exists(path) else "absent"


## A Game of the tests' own, with a test balance file and its own save file.
func _make_own_game(balance_path: String) -> Node:
	var game: Node = GameUnderTest.new()
	game.test_save_path = OWN_SAVE_PATH
	game.test_balance_path = balance_path
	add_child(game)
	_own_games.append(game)
	return game


func _discard(game: Node) -> void:
	_own_games.erase(game)
	if game.core != null:
		game.end_game()
	remove_child(game)
	game.free()


# --- Tests --------------------------------------------------------------------

func _test_contract() -> void:
	_check(get_node_or_null("/root/Game") != null, "the autoload Game exists")
	for signal_name: StringName in [&"game_started", &"game_ended"]:
		_check(Game.has_signal(signal_name), "signal %s is missing" % signal_name)
	for method: StringName in [&"has_save", &"new_game", &"continue_game", &"end_game",
			&"set_time_blocked", &"is_time_blocked", &"get_save_path"]:
		_check(Game.has_method(method), "method %s is missing" % method)
	_check(&"core" in Game, "the property core is missing")
	_check(Game.core == null, "no game at first")
	_check_equal(Game.has_save(), false, "no save at first")
	_check_equal(Game.is_time_blocked(), false, "time is not blocked at first")
	var given: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(Isolation.SAVE_ARGUMENT):
			given = argument.substr(Isolation.SAVE_ARGUMENT.length())
	_check(given.begins_with("user://"), "this run was given a user:// save path")
	_check_equal(Game.get_save_path(), given, "Game uses the save path from the command line")
	_check(Game.get_save_path() != Isolation.DEFAULT_SAVE_PATH, "Game does not use the default save path")
	# Without a game nothing happens.
	Game.end_game()
	_check_equal(_ended_count, 0, "end_game without a game does nothing")
	_check_equal(Game.continue_game(), false, "continue_game without a save fails")
	_check(Game.core == null, "still no game")
	_check_equal(_started_count, 0, "game_started was not sent")
	_check_equal(Game.has_save(), false, "still no save")


func _test_new_game_and_save_file() -> void:
	var day_length: float = _game_day_length()
	_check(day_length > 0.0, "the game's balance file has a day length")
	_check_equal(Game.new_game(), true, "new_game succeeds")
	_check_equal(_started_count, 1, "game_started once")
	_check(Game.core != null, "there is a game")
	_check(_core_at_start == Game.core, "the game was already there when game_started arrived")
	_check_equal(Game.core.state.day, 1, "day 1")
	_check_equal(Game.core.state.day_length, day_length, "the day length comes from the balance file")
	_check_equal(Game.core.state.day_time_left, day_length, "a full day is left")
	_check_equal(Game.core.state.phase, &"playing", "playing")
	# The save file is there right after new_game, before any frame.
	_check_equal(Game.has_save(), true, "has_save right after new_game")
	_check(FileAccess.file_exists(Game.get_save_path()), "the save file exists")
	var saved: Variant = _read_save(Game.get_save_path())
	_check_equal(typeof(saved), TYPE_DICTIONARY, "the save file holds keys and values")
	if typeof(saved) == TYPE_DICTIONARY:
		_check(saved.has("version"), "the save file has a format version")
		_check_equal(int(saved["day"]), 1, "saved day")
		_check_close(float(saved["day_time_left"]), day_length, "saved time left")
		_check_equal(int(saved["version"]), 2, "the format version is 2")
		_check(saved.has("day_length"), "the save file holds the day length")
		_check_close(float(saved.get("day_length", -1.0)), day_length, "saved day length")
		_check_equal(saved["phase"], "playing", "saved phase")
	_check(not FileAccess.file_exists(Game.get_save_path() + ".tmp"), "no temporary file is left")
	_check(not FileAccess.file_exists(Isolation.DEFAULT_SAVE_PATH), "the player's save file was not created")


func _test_clock_runs_and_blocks() -> void:
	Game.new_game()
	var core: GameCore = Game.core
	var at_start: float = core.state.day_time_left
	await _wait()
	var after_wait: float = core.state.day_time_left
	_check(after_wait < at_start, "the clock runs frame by frame (%f -> %f)" % [at_start, after_wait])
	_check(at_start - after_wait < 5.0, "it runs in real time, not faster")

	Game.set_time_blocked(&"pause_menu", true)
	_check_equal(Game.is_time_blocked(), true, "blocked by pause_menu")
	var blocked_at: float = core.state.day_time_left
	await _wait()
	_check_equal(core.state.day_time_left, blocked_at, "the clock stands still while blocked")
	Game.set_time_blocked(&"transition", true)
	Game.set_time_blocked(&"pause_menu", false)
	_check_equal(Game.is_time_blocked(), true, "still blocked by transition")
	await _wait()
	_check_equal(core.state.day_time_left, blocked_at, "the clock stands still with one reason left")
	# Setting a reason twice and clearing it once clears it.
	Game.set_time_blocked(&"transition", true)
	Game.set_time_blocked(&"transition", false)
	_check_equal(Game.is_time_blocked(), false, "not blocked when every reason is cleared")
	await _wait()
	_check(core.state.day_time_left < blocked_at, "the clock runs again")
	# Clearing a reason that is not set is harmless.
	Game.set_time_blocked(&"pause_menu", false)
	_check_equal(Game.is_time_blocked(), false, "clearing a reason that is not set changes nothing")
	print("[%s]   (the engine error that follows is expected: an unknown reason)" % TAG)
	Game.set_time_blocked(&"no_such_reason", true)
	_check_equal(Game.is_time_blocked(), false, "an unknown reason does not block time")

	# new_game, continue_game and end_game clear every reason.
	Game.set_time_blocked(&"pause_menu", true)
	Game.set_time_blocked(&"transition", true)
	Game.end_game()
	_check_equal(Game.is_time_blocked(), false, "end_game clears the reasons")
	Game.set_time_blocked(&"pause_menu", true)
	Game.continue_game()
	_check_equal(Game.is_time_blocked(), false, "continue_game clears the reasons")
	_check_equal(_blocked_at_start, false, "they were already cleared when game_started arrived")
	Game.set_time_blocked(&"transition", true)
	Game.new_game()
	_check_equal(Game.is_time_blocked(), false, "new_game clears the reasons")
	# A reason can be set without a game; nothing breaks.
	Game.end_game()
	Game.set_time_blocked(&"transition", true)
	await _frames(2)
	_check(Game.core == null, "no game appears by itself")
	Game.set_time_blocked(&"transition", false)


func _test_end_and_continue() -> void:
	Game.new_game()
	await _wait()
	var core: GameCore = Game.core
	var day: int = core.state.day
	var time_left: float = core.state.day_time_left
	_check(time_left < core.state.day_length, "some time passed before the game ends")
	_ended_count = 0
	_core_at_end = core
	Game.end_game()
	_check_equal(_ended_count, 1, "game_ended once")
	_check(Game.core == null, "core is null after end_game")
	_check(_core_at_end == null, "core was already null when game_ended arrived")
	_check_equal(Game.has_save(), true, "has_save after end_game")
	var saved: Variant = _read_save(Game.get_save_path())
	_check_close(float((saved as Dictionary)["day_time_left"]), time_left, "end_game saved the time left at that moment")
	Game.end_game()
	_check_equal(_ended_count, 1, "a second end_game does nothing")
	await _wait()
	_check_close(float((_read_save(Game.get_save_path()) as Dictionary)["day_time_left"]), time_left, "no time passes while there is no game")

	var file_before: String = _md5(Game.get_save_path())
	_started_count = 0
	_check_equal(Game.continue_game(), true, "continue_game succeeds")
	_check_equal(_started_count, 1, "game_started once")
	_check(Game.core != null and Game.core != core, "there is a new core")
	_check_equal(Game.core.state.day, day, "the same day")
	_check_close(Game.core.state.day_time_left, time_left, "the same time left")
	_check_equal(Game.core.state.phase, &"playing", "playing")
	_check_equal(_md5(Game.get_save_path()), file_before, "continue_game does not touch the save file")
	await _frames(3)
	_check_equal(_md5(Game.get_save_path()), file_before, "nor in the frames after it")
	await _wait()
	_check(Game.core.state.day_time_left < time_left, "the clock goes on from the saved time")

	# A game that ended in the summary continues in the summary.
	Game.core.request_end_day()
	await _frames(2)
	_check_equal(Game.core.state.phase, &"summary", "the day ended")
	var summary: Dictionary = Game.core.state.last_summary.duplicate()
	Game.end_game()
	_check_equal(Game.continue_game(), true, "continue_game in the summary succeeds")
	_check_equal(Game.core.state.phase, &"summary", "still the summary")
	_check_equal(Game.core.state.last_summary["day"], summary["day"], "the summary's day")
	_check_equal(Game.core.state.last_summary["ended_by"], &"request", "the summary's ended_by")
	_check_close(float(Game.core.state.last_summary["time_used"]), float(summary["time_used"]), "the summary's time used")
	_check_equal(Game.core.confirm_day_summary(), {"ok": true}, "the summary can be confirmed")
	_check_equal(Game.core.state.day, day + 1, "the next day")


func _test_save_points() -> void:
	var path: String = Game.get_save_path()
	Game.new_game()
	var after_new_game: String = _md5(path)
	_check(after_new_game != "absent", "saved when the new game was made")
	await _wait()
	_check_equal(_md5(path), after_new_game, "not saved while the day goes on")
	Game.core.begin_activity()
	Game.core.end_activity()
	await _frames(2)
	_check_equal(_md5(path), after_new_game, "not saved for an activity")

	Game.core.request_end_day()
	_check_equal(_md5(path), after_new_game, "not saved by the request itself")
	await _frames(2)
	var after_day_end: String = _md5(path)
	_check(after_day_end != after_new_game, "saved when the day ended")
	var saved: Dictionary = _read_save(path)
	_check_equal(saved["phase"], "summary", "the saved phase is summary")
	_check_equal((saved["last_summary"] as Dictionary)["ended_by"], "request", "the saved summary")
	await _wait()
	_check_equal(_md5(path), after_day_end, "not saved while the summary is shown")

	Game.core.confirm_day_summary()
	await _frames(2)
	var after_next_day: String = _md5(path)
	_check(after_next_day != after_day_end, "saved when the next day started")
	saved = _read_save(path)
	_check_equal(int(saved["day"]), 2, "the saved day is 2")
	_check_equal(saved["phase"], "playing", "the saved phase is playing")
	await _wait()
	_check_equal(_md5(path), after_next_day, "not saved after that")

	# While time is blocked the core is not ticked, so nothing is saved either;
	# it is saved as soon as time runs again.
	Game.core.request_end_day()
	Game.set_time_blocked(&"transition", true)
	await _frames(3)
	_check_equal(Game.core.state.phase, &"playing", "the day does not end while time is blocked")
	_check_equal(_md5(path), after_next_day, "not saved while time is blocked")
	Game.set_time_blocked(&"transition", false)
	await _frames(2)
	_check_equal(Game.core.state.phase, &"summary", "the day ends when time runs again")
	_check(_md5(path) != after_next_day, "and it is saved then")

	Game.core.confirm_day_summary()
	var before_end: String = _md5(path)
	Game.end_game()
	_check(_md5(path) != before_end, "saved by end_game")
	_check_equal(int((_read_save(path) as Dictionary)["day"]), 3, "end_game saved day 3")
	_check(not FileAccess.file_exists(path + ".tmp"), "no temporary file is left")


func _test_new_game_overwrites() -> void:
	var path: String = Game.get_save_path()
	Game.new_game()
	Game.core.request_end_day()
	await _frames(2)
	Game.core.confirm_day_summary()
	await _frames(2)
	Game.end_game()
	_check_equal(int((_read_save(path) as Dictionary)["day"]), 2, "a save on day 2 exists")
	_check_equal(Game.new_game(), true, "new_game with a save succeeds")
	_check_equal(Game.core.state.day, 1, "the new game is on day 1")
	_check_equal(int((_read_save(path) as Dictionary)["day"]), 1, "the save was overwritten")

	# new_game while a game is in progress replaces it.
	var old_core: GameCore = Game.core
	var old_reference: WeakRef = weakref(old_core)
	_started_count = 0
	_ended_count = 0
	await _wait()
	_check_equal(Game.new_game(), true, "new_game during a game succeeds")
	_check(Game.core != old_core, "there is a new core")
	_check_equal(_started_count, 1, "game_started once")
	_check_close(Game.core.state.day_time_left, Game.core.state.day_length, "a full day again")
	_check_equal(old_core.save_requested.get_connections().size(), 0, "Game let go of the old core's signal")
	old_core.request_end_day()
	old_core.tick(1.0)
	_check_equal(int((_read_save(path) as Dictionary)["day"]), 1, "the old core can no longer cause a save")
	_check_equal((_read_save(path) as Dictionary)["phase"], "playing", "the save is the new game's")
	old_core = null
	_check(old_reference.get_ref() == null, "the old core is freed")
	_check_equal(Game.core.save_requested.get_connections().size(), 1, "one connection on the new core")


func _test_unreadable_save() -> void:
	var path: String = Game.get_save_path()
	var bad_files: Dictionary = {
		"not JSON": "this is { not a save file\n\u0001",
		"empty": "",
		"a list": "[1, 2, 3]",
		"day 0": JSON.stringify({"version": 2, "day": 0, "day_length": 100.0, "day_time_left": 10.0, "phase": "playing", "last_summary": {}}),
		"too much time left": JSON.stringify({"version": 2, "day": 1, "day_length": 100.0, "day_time_left": 100.5, "phase": "playing", "last_summary": {}}),
		"day length 0": JSON.stringify({"version": 2, "day": 1, "day_length": 0.0, "day_time_left": 0.0, "phase": "playing", "last_summary": {}}),
		"negative day length": JSON.stringify({"version": 2, "day": 1, "day_length": -100.0, "day_time_left": 0.0, "phase": "playing", "last_summary": {}}),
		"day length as text": JSON.stringify({"version": 2, "day": 1, "day_length": "100", "day_time_left": 10.0, "phase": "playing", "last_summary": {}}),
		"no day length": JSON.stringify({"version": 2, "day": 1, "day_time_left": 10.0, "phase": "playing", "last_summary": {}}),
		# The format the 13 work wrote. Refused since the format is version 2.
		"version 1": JSON.stringify({"version": 1, "day": 1, "day_time_left": 10.0, "phase": "playing", "last_summary": {}}),
		"version 3": JSON.stringify({"version": 3, "day": 1, "day_length": 100.0, "day_time_left": 10.0, "phase": "playing", "last_summary": {}}),
		"missing field": JSON.stringify({"version": 2, "day": 1, "day_length": 100.0, "phase": "playing", "last_summary": {}}),
	}
	print("[%s]   (the engine warnings that follow are expected: unreadable save files)" % TAG)
	for name: String in bad_files:
		_write_text(path, bad_files[name])
		var before: String = _md5(path)
		_started_count = 0
		_check_equal(Game.has_save(), true, "%s: has_save is true, the file exists" % name)
		_check_equal(Game.continue_game(), false, "%s: continue_game fails" % name)
		_check(Game.core == null, "%s: no game" % name)
		_check_equal(_started_count, 0, "%s: game_started was not sent" % name)
		_check_equal(_md5(path), before, "%s: the file is left as it is" % name)
		await _frames(2)
		_check_equal(_md5(path), before, "%s: the file is still the same two frames later" % name)

	# A failed continue_game leaves a game in progress alone.
	Game.new_game()
	var core: GameCore = Game.core
	_write_text(path, "broken")
	_started_count = 0
	_check_equal(Game.continue_game(), false, "continue_game fails during a game")
	_check(Game.core == core, "the game in progress is still there")
	_check_equal(_started_count, 0, "game_started was not sent")
	_check_equal(FileAccess.get_file_as_string(path), "broken", "the broken file is left as it is")
	Game.end_game()
	_check_equal(int((_read_save(path) as Dictionary)["day"]), 1, "end_game wrote a good save over it")

	# new_game overwrites an unreadable save.
	_write_text(path, "broken again")
	_check_equal(Game.new_game(), true, "new_game succeeds over an unreadable save")
	_check_equal(typeof(_read_save(path)), TYPE_DICTIONARY, "the save is readable again")
	Game.end_game()
	_check_equal(Game.continue_game(), true, "and it can be continued")

	# No save at all.
	Game.end_game()
	Isolation.remove_test_save(get_tree())
	_check_equal(Game.has_save(), false, "has_save is false without a file")
	_check_equal(Game.continue_game(), false, "continue_game fails without a file")
	_check(not FileAccess.file_exists(path), "continue_game did not create a file")


func _test_save_replaces_whole_file() -> void:
	var path: String = Game.get_save_path()
	# A long file in the way: the new save must replace it, not be written into it.
	_write_text(path, "x".repeat(20000))
	_check_equal(Game.new_game(), true, "new_game succeeds")
	_check(FileAccess.get_file_as_string(path).length() < 2000, "the old content is gone")
	_check_equal(typeof(_read_save(path)), TYPE_DICTIONARY, "the save is readable")
	_check(not FileAccess.file_exists(path + ".tmp"), "no temporary file is left")
	# A temporary file left by a run that died while saving does not matter.
	_write_text(path + ".tmp", "half a sav")
	var good: String = _md5(path)
	Game.end_game()
	_check_equal(Game.continue_game(), true, "a stray temporary file does not stop continue_game")
	_check(_md5(path) != "absent", "the save file is still there")
	Game.core.request_end_day()
	await _frames(2)
	_check(_md5(path) != good, "the next save went through")
	_check(not FileAccess.file_exists(path + ".tmp"), "and the stray temporary file is gone")
	_check_equal((_read_save(path) as Dictionary)["phase"], "summary", "the save holds the new state")


func _test_balance_file() -> void:
	# A good test balance.
	var game: Node = _make_own_game(TEST_BALANCE)
	_check_equal(game.get_save_path(), OWN_SAVE_PATH, "a test Game reports its own save path")
	_check_equal(game.new_game(), true, "new_game with the test balance")
	_check_equal(game.core.state.day_length, TEST_DAY_LENGTH, "the day length comes from the test balance")
	_check(FileAccess.file_exists(OWN_SAVE_PATH), "it saves to its own path")
	_check(not FileAccess.file_exists(Game.get_save_path()), "not to the autoload's path")
	game.core.tick(100.0)
	game.end_game()

	# The same save with a shorter day in the balance: 20 seconds are left of a
	# day of 120, the balance now says 5. The save holds its own day length, so
	# it is read (docs/roles/leader/outputs/14 design, section 2). Before 14 it
	# was refused. More of this in _test_day_length_change.
	var short_day: Node = _make_own_game(SHORT_DAY_BALANCE)
	var save_before: String = _md5(OWN_SAVE_PATH)
	_check_equal(short_day.continue_game(), true, "a save from a longer day is read")
	_check(short_day.core != null, "there is a game")
	_check_equal(short_day.core.state.day_length, TEST_DAY_LENGTH, "the day in progress keeps its saved length")
	_check_close(short_day.core.state.day_time_left, 20.0, "the time left is as saved")
	_check_equal(_md5(OWN_SAVE_PATH), save_before, "the save file is left as it is")
	_discard(short_day)
	_remove(OWN_SAVE_PATH)
	print("[%s]   (the engine errors that follow are expected: balance problems)" % TAG)

	# Balance files that cannot be used.
	_write_text(BROKEN_BALANCE_PATH, "{ \"day_length_seconds\": 120\n")
	var bad_balances: Dictionary = {
		"no file": "res://tests/game/there_is_no_such_file.json",
		"no key": "res://tests/game/balance_no_key.json",
		"not a number": "res://tests/game/balance_bad_value.json",
		"not keys and values": "res://tests/game/balance_not_keys.json",
		"not JSON": BROKEN_BALANCE_PATH,
	}
	for name: String in bad_balances:
		var broken: Node = _make_own_game(bad_balances[name])
		_check_equal(broken.new_game(), false, "%s: new_game fails" % name)
		_check(broken.core == null, "%s: no game" % name)
		_check(not FileAccess.file_exists(OWN_SAVE_PATH), "%s: no save file is made" % name)
		_check_equal(broken.continue_game(), false, "%s: continue_game fails" % name)
		_check_equal(broken.has_save(), false, "%s: has_save stays false" % name)
		_discard(broken)

	# With a good save in place, a bad balance still stops continue_game and
	# leaves the save alone.
	game.new_game()
	game.end_game()
	save_before = _md5(OWN_SAVE_PATH)
	var no_key: Node = _make_own_game("res://tests/game/balance_no_key.json")
	_check_equal(no_key.has_save(), true, "the save is seen")
	_check_equal(no_key.continue_game(), false, "continue_game fails without the day length")
	_check_equal(no_key.new_game(), false, "new_game fails without the day length")
	_check_equal(_md5(OWN_SAVE_PATH), save_before, "the save file is left as it is")
	_remove(BROKEN_BALANCE_PATH)


## docs/roles/leader/outputs/14 design, section 2. A game saved with the
## game's own day length is continued with a balance that holds another one.
func _test_day_length_change() -> void:
	var saved_length: float = _game_day_length()
	for other_balance: String in [SHORT_DAY_BALANCE, LONG_DAY_BALANCE]:
		var other_length: float = float((JSON.parse_string(FileAccess.get_file_as_string(other_balance)) as Dictionary)["day_length_seconds"])
		var tag: String = "%d -> %d" % [int(saved_length), int(other_length)]
		_check(other_length != saved_length, "%s: the two day lengths differ" % tag)

		# Saved in the middle of the day.
		var first: Node = _make_own_game(GAME_BALANCE_PATH)
		_check_equal(first.new_game(), true, "%s: new game with the game's balance" % tag)
		_check_equal(first.core.state.day_length, saved_length, "%s: the day has the game's length" % tag)
		first.core.tick(100.0)
		_discard(first)
		_check_close(float((_read_save(OWN_SAVE_PATH) as Dictionary)["day_length"]), saved_length, "%s: the save file holds the day length" % tag)
		var file_before: String = _md5(OWN_SAVE_PATH)

		var later: Node = _make_own_game(other_balance)
		_check_equal(later.continue_game(), true, "%s: the save is read" % tag)
		_check_equal(_md5(OWN_SAVE_PATH), file_before, "%s: continue_game does not touch the save file" % tag)
		_check_equal(later.core.state.day, 1, "%s: day 1" % tag)
		_check_equal(later.core.state.day_length, saved_length, "%s: the day in progress keeps its saved length" % tag)
		_check_close(later.core.state.day_time_left, saved_length - 100.0, "%s: the time left is as saved" % tag)
		later.core.tick(saved_length - 101.0)
		_check_equal(later.core.state.phase, &"playing", "%s: not over with 1 second left of the saved length" % tag)
		later.core.tick(1.0)
		_check_equal(later.core.state.phase, &"summary", "%s: the day ends at the saved length" % tag)
		_check_equal(later.core.state.last_summary["ended_by"], &"time", "%s: it ended by time" % tag)
		_check_close(float(later.core.state.last_summary["time_used"]), saved_length, "%s: the time used is the saved length" % tag)
		_check_equal(later.core.confirm_day_summary(), {"ok": true}, "%s: confirm" % tag)
		_check_equal(later.core.state.day, 2, "%s: day 2" % tag)
		_check_equal(later.core.state.day_length, other_length, "%s: the next day has the balance's length" % tag)
		_check_equal(later.core.state.day_time_left, other_length, "%s: and a full day of it" % tag)
		later.end_game()
		var saved: Dictionary = _read_save(OWN_SAVE_PATH)
		_check_equal(int(saved["day"]), 2, "%s: day 2 is saved" % tag)
		_check_close(float(saved["day_length"]), other_length, "%s: with the new day length" % tag)
		_discard(later)
		_remove(OWN_SAVE_PATH)

		# Saved in the day summary.
		var ended: Node = _make_own_game(GAME_BALANCE_PATH)
		ended.new_game()
		ended.core.tick(100.0)
		ended.core.request_end_day()
		ended.core.tick(0.0)
		_check_equal(ended.core.state.phase, &"summary", "%s: the day ended by the door sign" % tag)
		_discard(ended)
		file_before = _md5(OWN_SAVE_PATH)

		var later_summary: Node = _make_own_game(other_balance)
		_check_equal(later_summary.continue_game(), true, "%s: the save in the summary is read" % tag)
		_check_equal(_md5(OWN_SAVE_PATH), file_before, "%s: continue_game does not touch that save file either" % tag)
		_check_equal(later_summary.core.state.phase, &"summary", "%s: still the summary" % tag)
		_check_equal(later_summary.core.state.day_length, saved_length, "%s: the ended day keeps its saved length" % tag)
		_check_equal(later_summary.core.state.last_summary["day"], 1, "%s: the summary's day" % tag)
		_check_equal(later_summary.core.state.last_summary["ended_by"], &"request", "%s: the summary's ended_by" % tag)
		_check_close(float(later_summary.core.state.last_summary["time_used"]), 100.0, "%s: the summary's time used" % tag)
		_check_close(later_summary.core.state.day_time_left, saved_length - 100.0, "%s: the time left is as saved" % tag)
		_check_equal(later_summary.core.confirm_day_summary(), {"ok": true}, "%s: confirm from the summary" % tag)
		_check_equal(later_summary.core.state.day_length, other_length, "%s: the next day has the balance's length (from the summary)" % tag)
		_check_equal(later_summary.core.state.day_time_left, other_length, "%s: and a full day of it (from the summary)" % tag)
		_discard(later_summary)
		_remove(OWN_SAVE_PATH)


## A save text for the autoload Game on the given day (1 or 2), made by the
## game itself.
func _make_save_text(day: int) -> String:
	Game.new_game()
	if day == 2:
		Game.core.request_end_day()
		Game.core.tick(0.0)
		Game.core.confirm_day_summary()
	Game.end_game()
	var text: String = FileAccess.get_file_as_string(Game.get_save_path())
	Isolation.remove_test_save(get_tree())
	return text


## docs/roles/leader/outputs/14 design, sections 4 and 6: a temporary save file
## that was left behind.
func _test_temporary_save_file() -> void:
	var path: String = Game.get_save_path()
	var temporary: String = path + ".tmp"
	var day_1: String = _make_save_text(1)
	var day_2: String = _make_save_text(2)
	_check(day_1 != day_2 and day_1 != "" and day_2 != "", "two different good saves to work with")

	# Neither file.
	_check_equal(Game.has_save(), false, "neither: has_save is false")
	_check_equal(Game.continue_game(), false, "neither: continue_game fails")

	# 1. The save file only.
	_write_text(path, day_1)
	_check_equal(Game.has_save(), true, "save only: has_save is true")
	_check_equal(Game.continue_game(), true, "save only: continue_game succeeds")
	_check_equal(Game.core.state.day, 1, "save only: the save file was read")
	_check_equal(FileAccess.get_file_as_string(path), day_1, "save only: the save file is untouched")
	_check(not FileAccess.file_exists(temporary), "save only: no temporary file appears")
	Game.end_game()
	Isolation.remove_test_save(get_tree())

	# 2. Both: the save file is read, the temporary file is not used.
	_write_text(path, day_1)
	_write_text(temporary, day_2)
	_check_equal(Game.has_save(), true, "both: has_save is true")
	_started_count = 0
	_check_equal(Game.continue_game(), true, "both: continue_game succeeds")
	_check_equal(Game.core.state.day, 1, "both: the save file was read, not the temporary file")
	_check_equal(FileAccess.get_file_as_string(path), day_1, "both: the save file is untouched")
	_check_equal(FileAccess.get_file_as_string(temporary), day_2, "both: the temporary file is left as it is")
	await _frames(2)
	_check_equal(FileAccess.get_file_as_string(temporary), day_2, "both: and still two frames later")
	# The next save writes over the leftover temporary file.
	Game.end_game()
	_check(not FileAccess.file_exists(temporary), "both: the next save used up the temporary file")
	_check_equal(int((_read_save(path) as Dictionary)["day"]), 1, "both: the save file holds the game that was continued")
	Isolation.remove_test_save(get_tree())

	# Both, with a temporary file that is broken: it does not matter.
	_write_text(path, day_2)
	_write_text(temporary, "half a sav")
	_check_equal(Game.continue_game(), true, "both, broken temporary: continue_game succeeds")
	_check_equal(Game.core.state.day, 2, "both, broken temporary: the save file was read")
	_check_equal(FileAccess.get_file_as_string(temporary), "half a sav", "both, broken temporary: it is left as it is")
	Game.end_game()
	Isolation.remove_test_save(get_tree())

	# Both, with a save file that is broken: the good temporary file is not used.
	print("[%s]   (the engine warnings that follow are expected: unreadable save and temporary files)" % TAG)
	_write_text(path, "broken save")
	_write_text(temporary, day_2)
	_started_count = 0
	_check_equal(Game.has_save(), true, "both, broken save: has_save is true")
	_check_equal(Game.continue_game(), false, "both, broken save: continue_game fails")
	_check(Game.core == null, "both, broken save: no game")
	_check_equal(_started_count, 0, "both, broken save: game_started was not sent")
	_check_equal(FileAccess.get_file_as_string(path), "broken save", "both, broken save: the save file is left as it is")
	_check_equal(FileAccess.get_file_as_string(temporary), day_2, "both, broken save: the temporary file is left as it is")
	Isolation.remove_test_save(get_tree())

	# 3. The temporary file only, and it is good: it is the save.
	_write_text(temporary, day_2)
	_check(not FileAccess.file_exists(path), "temporary only: there is no save file")
	_check_equal(Game.has_save(), true, "temporary only: has_save is true")
	_started_count = 0
	_save_file_at_start = false
	_temporary_file_at_start = true
	_check_equal(Game.continue_game(), true, "temporary only: continue_game succeeds")
	_check_equal(_started_count, 1, "temporary only: game_started once")
	_check_equal(Game.core.state.day, 2, "temporary only: the temporary file was read")
	_check(FileAccess.file_exists(path), "temporary only: there is a save file now")
	_check(not FileAccess.file_exists(temporary), "temporary only: the temporary file is gone")
	_check_equal(FileAccess.get_file_as_string(path), day_2, "temporary only: the save file is the temporary file, moved")
	_check_equal(_save_file_at_start, true, "temporary only: it was moved before game_started")
	_check_equal(_temporary_file_at_start, false, "temporary only: nothing was left behind when game_started arrived")
	_check_equal(Game.has_save(), true, "temporary only: has_save is still true")
	await _wait()
	_check(Game.core.state.day_time_left < Game.core.state.day_length, "temporary only: the game runs")
	Game.end_game()
	_check_equal(Game.continue_game(), true, "temporary only: and it continues again from the save file")
	_check_equal(Game.core.state.day, 2, "temporary only: on the same day")
	Game.end_game()
	Isolation.remove_test_save(get_tree())

	# 4. The temporary file only, and it cannot be read: like an unreadable save.
	var bad_temporaries: Dictionary = {
		"not JSON": "half a sav",
		"empty": "",
		"refused data": JSON.stringify({"version": 2, "day": 0, "day_length": 100.0, "day_time_left": 10.0, "phase": "playing", "last_summary": {}}),
		"version 1": JSON.stringify({"version": 1, "day": 1, "day_time_left": 10.0, "phase": "playing", "last_summary": {}}),
	}
	for name: String in bad_temporaries:
		_write_text(temporary, bad_temporaries[name])
		_started_count = 0
		_check_equal(Game.has_save(), true, "broken temporary only (%s): has_save is true" % name)
		_check_equal(Game.continue_game(), false, "broken temporary only (%s): continue_game fails" % name)
		_check(Game.core == null, "broken temporary only (%s): no game" % name)
		_check_equal(_started_count, 0, "broken temporary only (%s): game_started was not sent" % name)
		_check_equal(FileAccess.get_file_as_string(temporary), bad_temporaries[name], "broken temporary only (%s): the file is left as it is" % name)
		_check(not FileAccess.file_exists(path), "broken temporary only (%s): no save file is made" % name)
		await _frames(2)
		_check_equal(FileAccess.get_file_as_string(temporary), bad_temporaries[name], "broken temporary only (%s): still the same two frames later" % name)
		_check_equal(Game.has_save(), true, "broken temporary only (%s): has_save stays true" % name)
	# new_game writes the save file as always; the leftover is used up by it.
	_check_equal(Game.new_game(), true, "broken temporary only: new_game succeeds")
	_check(FileAccess.file_exists(path), "broken temporary only: new_game made the save file")
	_check(not FileAccess.file_exists(temporary), "broken temporary only: the leftover temporary file is gone")
	_check_equal(int((_read_save(path) as Dictionary)["day"]), 1, "broken temporary only: the save is the new game")
	Game.end_game()

	# new_game with a good temporary file only: it is not recovered, the new game is saved.
	Isolation.remove_test_save(get_tree())
	_write_text(temporary, day_2)
	_check_equal(Game.new_game(), true, "good temporary only: new_game succeeds")
	_check_equal(Game.core.state.day, 1, "good temporary only: the new game is on day 1")
	_check_equal(int((_read_save(path) as Dictionary)["day"]), 1, "good temporary only: the save is the new game")
	_check(not FileAccess.file_exists(temporary), "good temporary only: the leftover temporary file is gone")


## 14 design, section 6: the temporary file is good, but moving it into the
## save file's place fails. The move can only be made to fail through the hook
## of tests/game/game_under_test.gd.
func _test_temporary_file_cannot_be_moved() -> void:
	var own_temporary: String = OWN_SAVE_PATH + ".tmp"
	var maker: Node = _make_own_game(TEST_BALANCE)
	maker.new_game()
	maker.core.tick(45.0)
	_discard(maker)
	var good: String = FileAccess.get_file_as_string(OWN_SAVE_PATH)
	_remove(OWN_SAVE_PATH)

	# The move works: the same recovery as with the autoload.
	_write_text(own_temporary, good)
	var working: Node = _make_own_game(TEST_BALANCE)
	_check_equal(working.has_save(), true, "has_save with the temporary file only")
	_check_equal(working.continue_game(), true, "continue_game recovers the temporary file")
	_check_equal(working.replace_count, 1, "the file was moved once")
	_check(FileAccess.file_exists(OWN_SAVE_PATH) and not FileAccess.file_exists(own_temporary), "the temporary file became the save file")
	working.end_game()
	_discard(working)
	_remove(OWN_SAVE_PATH)

	# The move fails: the game goes on, the temporary file stays.
	_write_text(own_temporary, good)
	var stuck: Node = _make_own_game(TEST_BALANCE)
	stuck.fail_replace = true
	print("[%s]   (the engine warnings that follow are expected: files that cannot be moved)" % TAG)
	_check_equal(stuck.continue_game(), true, "continue_game succeeds although the move failed")
	_check_equal(stuck.replace_count, 1, "the move was tried once")
	_check(stuck.core != null, "there is a game")
	_check_equal(stuck.core.state.day, 1, "the game is the one in the temporary file")
	_check_close(stuck.core.state.day_time_left, TEST_DAY_LENGTH - 45.0, "with its time left")
	_check_equal(FileAccess.get_file_as_string(own_temporary), good, "the temporary file is left as it is")
	_check(not FileAccess.file_exists(OWN_SAVE_PATH), "there is still no save file")
	_check_equal(stuck.has_save(), true, "has_save is still true")
	_check_equal(stuck.is_time_blocked(), false, "time is not blocked")
	stuck.core.tick(5.0)
	_check_close(stuck.core.state.day_time_left, TEST_DAY_LENGTH - 50.0, "the game runs")
	# While files cannot be moved, saving does not go through either; the
	# game and the last good file are both kept.
	stuck.core.request_end_day()
	stuck.core.tick(0.0)
	_check_equal(stuck.core.state.phase, &"summary", "the day ended although it could not be saved")
	_check(not FileAccess.file_exists(OWN_SAVE_PATH), "no save file while files cannot be moved")
	# Once files can be moved again, the next save makes the save file.
	stuck.fail_replace = false
	stuck.core.confirm_day_summary()
	stuck.core.tick(0.0)
	_check(FileAccess.file_exists(OWN_SAVE_PATH), "the next save made the save file")
	_check(not FileAccess.file_exists(own_temporary), "and the temporary file is gone")
	_check_equal(int((_read_save(OWN_SAVE_PATH) as Dictionary)["day"]), 2, "the save holds the game as it is now")
	_discard(stuck)
	var next_run: Node = _make_own_game(TEST_BALANCE)
	_check_equal(next_run.continue_game(), true, "the next run continues from the save file")
	_check_equal(next_run.core.state.day, 2, "on day 2")

	# A new game that cannot be saved still fails (13 behaviour, unchanged).
	var no_save: Node = _make_own_game(TEST_BALANCE)
	_remove(OWN_SAVE_PATH)
	no_save.fail_replace = true
	print("[%s]   (the engine error that follows is expected: a new game that cannot be saved)" % TAG)
	_check_equal(no_save.new_game(), false, "new_game fails when the save cannot be put in place")
	_check(no_save.core == null, "no game")
	_remove(own_temporary)


func _test_save_when_the_game_closes() -> void:
	# The window is closed while a game is in progress.
	var game: Node = _make_own_game(TEST_BALANCE)
	game.new_game()
	game.core.tick(30.0)
	_check_close(float((_read_save(OWN_SAVE_PATH) as Dictionary)["day_time_left"]), TEST_DAY_LENGTH, "the file still holds the start")
	game.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	_check_close(float((_read_save(OWN_SAVE_PATH) as Dictionary)["day_time_left"]), 90.0, "the close request saved the game")
	# The game leaves the tree (the engine shuts down).
	game.core.tick(15.0)
	remove_child(game)
	_check_close(float((_read_save(OWN_SAVE_PATH) as Dictionary)["day_time_left"]), 75.0, "leaving the tree saved the game")
	add_child(game)
	_check(game.core != null, "the game is still in progress")

	# Without a game nothing is written.
	game.end_game()
	_remove(OWN_SAVE_PATH)
	game.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	remove_child(game)
	add_child(game)
	_check(not FileAccess.file_exists(OWN_SAVE_PATH), "nothing is saved on closing without a game")

	# A new start continues from the moment of closing.
	game.new_game()
	game.core.tick(42.5)
	game.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	_discard(game)
	var next_run: Node = _make_own_game(TEST_BALANCE)
	_check_equal(next_run.continue_game(), true, "the next run can continue")
	_check_close(next_run.core.state.day_time_left, 77.5, "from the time left when the game closed")
