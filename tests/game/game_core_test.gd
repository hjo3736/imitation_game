extends Node
## Headless tests for the game core (scripts/game/game_core.gd, game_state.gd,
## balance.gd). The core is tested on its own: no screen, no files, no frames.
##
## Run:
##   godot --headless --path . res://tests/game/game_core_test.tscn -- --settings-path=user://test_settings.cfg --save-path=user://test_save.json
## Exit code 0 when every check passes, 1 otherwise. Without the two arguments
## the run is not isolated from the player's files: it does nothing and exits
## with 1.
##
## The numbers below are test numbers, not the game's numbers.

const Isolation: GDScript = preload("res://tests/common/game_isolation.gd")

const SCENE_PATH: String = "res://tests/game/game_core_test.tscn"
const TAG: String = "game_core_test"
const TEST_DAY_LENGTH: float = 100.0
const CORE_SOURCES: Array[String] = [
	"res://scripts/game/game_core.gd", "res://scripts/game/game_state.gd", "res://scripts/game/balance.gd",
]
## What the core must not touch (13 design, section 4).
const FORBIDDEN_IN_CORE: Array[String] = [
	"extends Node", "get_tree", "Engine.get_main_loop", "SceneTree", "Input.", "InputEvent",
	"FileAccess", "DirAccess", "ResourceLoader", "ResourceSaver", "ConfigFile",
	"Time.", "OS.", "Timer", "create_timer", "randf", "randi", "randomize", "await",
]

var _check_count: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _current_test: String = ""
## Signals of the core under test, in the order they arrived.
var _events: Array = []
var _confirm_on_day_end: GameCore = null


func _ready() -> void:
	if not Isolation.begin(get_tree(), TAG, SCENE_PATH, true):
		get_tree().quit(1)
		return

	_run("contract", _test_contract)
	_run("core_is_pure", _test_core_is_pure)
	_run("balance", _test_balance)
	_run("new_game", _test_new_game)
	_run("clock", _test_clock)
	_run("day_ends_when_time_is_up", _test_day_ends_when_time_is_up)
	_run("request_end_day", _test_request_end_day)
	_run("request_and_time_in_one_tick", _test_request_and_time_in_one_tick)
	_run("activity", _test_activity)
	_run("summary_and_next_day", _test_summary_and_next_day)
	_run("large_and_small_delta", _test_large_and_small_delta)
	_run("save_requested", _test_save_requested)
	_run("confirm_inside_day_ended", _test_confirm_inside_day_ended)
	_run("save_data_round_trip", _test_save_data_round_trip)
	_run("save_data_refused", _test_save_data_refused)
	_run("day_length_is_saved", _test_day_length_is_saved)
	_run("failed_commands_change_nothing", _test_failed_commands_change_nothing)

	_current_test = "isolation"
	_check(Isolation.finish(get_tree(), TAG), "the player's files changed or a test file is still there")

	print("[%s] checks=%d failures=%d" % [TAG, _check_count, _failures.size()])
	for failure: String in _failures:
		print("[%s] FAIL %s" % [TAG, failure])
	print("[%s] RESULT %s" % [TAG, "PASS" if _failures.is_empty() else "FAIL"])
	get_tree().quit(0 if _failures.is_empty() else 1)


# --- Helpers ------------------------------------------------------------------

func _run(test_name: String, test: Callable) -> void:
	_current_test = test_name
	_events.clear()
	_confirm_on_day_end = null
	var failures_before: int = _failures.size()
	test.call()
	print("[%s] %s %s" % [TAG, "ok  " if _failures.size() == failures_before else "FAIL", test_name])


func _check(condition: bool, message: String) -> void:
	_check_count += 1
	if not condition:
		_failures.append("%s: %s" % [_current_test, message])


func _check_equal(actual: Variant, expected: Variant, what: String) -> void:
	var same: bool = typeof(actual) == typeof(expected) and actual == expected
	_check(same, "%s: expected %s (%s), got %s (%s)" % [
		what, str(expected), type_string(typeof(expected)), str(actual), type_string(typeof(actual))])


func _check_ok(result: Dictionary, what: String) -> void:
	_check_equal(result, {"ok": true}, what)


func _check_fails(result: Dictionary, error: StringName, what: String) -> void:
	_check_equal(result, {"ok": false, "error": error}, what)


func _balance(day_length: float = TEST_DAY_LENGTH) -> Balance:
	return Balance.from_dictionary({"day_length_seconds": day_length})


## A new game whose signals are recorded in _events.
func _new_core(day_length: float = TEST_DAY_LENGTH) -> GameCore:
	var core: GameCore = GameCore.create_new(_balance(day_length))
	_listen(core)
	return core


func _listen(core: GameCore) -> void:
	core.day_started.connect(_on_day_started)
	core.day_end_pending.connect(_on_day_end_pending)
	core.day_ended.connect(_on_day_ended)
	core.save_requested.connect(_on_save_requested)


func _on_day_started(day: int) -> void:
	_events.append(["day_started", day])


func _on_day_end_pending() -> void:
	_events.append(["day_end_pending"])


func _on_day_ended(summary: Dictionary) -> void:
	_events.append(["day_ended", summary])
	if _confirm_on_day_end != null:
		_events.append(["confirm", _confirm_on_day_end.confirm_day_summary()])


func _on_save_requested() -> void:
	_events.append(["save_requested"])


func _count(event_name: String) -> int:
	var count: int = 0
	for event: Array in _events:
		if event[0] == event_name:
			count += 1
	return count


func _names() -> Array:
	var names: Array = []
	for event: Array in _events:
		names.append(event[0])
	return names


## Everything a screen can read, plus what would be saved.
func _snapshot(core: GameCore) -> Dictionary:
	return {
		"day": core.state.day,
		"day_length": core.state.day_length,
		"day_time_left": core.state.day_time_left,
		"phase": core.state.phase,
		"last_summary": core.state.last_summary.duplicate(true),
		"save_data": core.to_save_data(),
	}


func _valid_save_data() -> Dictionary:
	return {"version": 2, "day": 3, "day_length": 100.0, "day_time_left": 40.0, "phase": "playing", "last_summary": {}}


func _valid_summary_save_data() -> Dictionary:
	return {
		"version": 2, "day": 3, "day_length": 100.0, "day_time_left": 40.0, "phase": "summary",
		"last_summary": {"day": 3, "ended_by": "request", "time_used": 60.0},
	}


# --- Tests --------------------------------------------------------------------

func _test_contract() -> void:
	var core: GameCore = _new_core()
	for signal_name: StringName in [&"day_started", &"day_end_pending", &"day_ended", &"save_requested"]:
		_check(core.has_signal(signal_name), "signal %s is missing" % signal_name)
	for method: StringName in [&"tick", &"request_end_day", &"confirm_day_summary", &"begin_activity", &"end_activity"]:
		_check(core.has_method(method), "method %s is missing" % method)
	_check(core.state is GameState, "state is a GameState")
	for property: StringName in [&"day", &"day_length", &"day_time_left", &"phase", &"last_summary"]:
		_check(property in core.state, "state.%s is missing" % property)
	_check_equal(typeof(core.state.day), TYPE_INT, "day is an int")
	_check_equal(typeof(core.state.day_length), TYPE_FLOAT, "day_length is a float")
	_check_equal(typeof(core.state.day_time_left), TYPE_FLOAT, "day_time_left is a float")
	_check_equal(typeof(core.state.phase), TYPE_STRING_NAME, "phase is a StringName")
	_check_equal(typeof(core.state.last_summary), TYPE_DICTIONARY, "last_summary is a Dictionary")


func _test_core_is_pure() -> void:
	var core: GameCore = _new_core()
	var objects: Array[Object] = [core, core.state, _balance()]
	for object: Object in objects:
		_check(not object.is_class("Node"), "%s is not a Node" % object.get_script().get_global_name())
		_check(object.is_class("RefCounted"), "%s is a RefCounted" % object.get_script().get_global_name())
	for path: String in CORE_SOURCES:
		var source: String = FileAccess.get_file_as_string(path)
		_check(source != "", "%s can be read" % path)
		var code: String = ""
		for line: String in source.split("\n"):
			# Comments may name what the core avoids; only code counts.
			code += line.get_slice("#", 0) + "\n"
		for word: String in FORBIDDEN_IN_CORE:
			_check(not code.contains(word), "%s uses '%s'" % [path, word])
		_check(not code.contains("600"), "%s holds the day length as a number" % path)


func _test_balance() -> void:
	var balance: Balance = _balance(120.0)
	_check(balance.has_key(&"day_length_seconds"), "the key exists")
	_check(balance.has_number(&"day_length_seconds"), "the key holds a number")
	_check_equal(balance.get_number(&"day_length_seconds"), 120.0, "the number is read")
	_check_equal(GameCore.balance_problems(balance).size(), 0, "a usable balance has no problems")
	_check(GameCore.create_new(balance) != null, "a game starts with a usable balance")
	_check_equal(GameCore.create_new(balance).state.day_length, 120.0, "the day length comes from the balance")
	_check(Balance.from_dictionary({"day_length_seconds": 90}).has_number(&"day_length_seconds"), "an int is a number too")

	print("[%s]   (the engine errors that follow are expected: unusable balances)" % TAG)
	var empty: Balance = Balance.from_dictionary({})
	_check(not empty.has_key(&"day_length_seconds"), "a missing key is missing")
	_check(is_nan(empty.get_number(&"day_length_seconds")), "a missing key gives no default")
	_check_equal(GameCore.balance_problems(empty).size(), 1, "a missing key is a problem")
	_check(GameCore.balance_problems(empty)[0].contains("day_length_seconds"), "the problem names the key")
	_check(GameCore.create_new(empty) == null, "no game without the day length")
	_check(GameCore.create_from_save_data(empty, _valid_save_data()) == null, "no loaded game without the day length")
	for bad_value: Variant in ["600", null, [600], -5.0, 0.0, 0, INF, NAN]:
		var bad: Balance = Balance.from_dictionary({"day_length_seconds": bad_value})
		_check(GameCore.balance_problems(bad).size() >= 1, "day length %s is a problem" % str(bad_value))
		_check(GameCore.create_new(bad) == null, "no game with day length %s" % str(bad_value))
	_check(GameCore.create_new(null) == null, "no game without a balance")
	# Other keys do not matter.
	_check(GameCore.create_new(Balance.from_dictionary({"day_length_seconds": 50.0, "something_else": "x"})) != null, "unknown keys are ignored")


func _test_new_game() -> void:
	var core: GameCore = _new_core()
	_check_equal(core.state.day, 1, "day")
	_check_equal(core.state.day_length, TEST_DAY_LENGTH, "day length")
	_check_equal(core.state.day_time_left, TEST_DAY_LENGTH, "time left")
	_check_equal(core.state.phase, &"playing", "phase")
	_check_equal(core.state.last_summary, {}, "last summary")
	_check_equal(_events.size(), 0, "no signal before the first tick")


func _test_clock() -> void:
	var core: GameCore = _new_core()
	core.tick(0.0)
	_check_equal(core.state.day_time_left, 100.0, "a tick of 0 moves nothing")
	core.tick(10.0)
	_check_equal(core.state.day_time_left, 90.0, "10 seconds pass")
	core.tick(0.5)
	_check_equal(core.state.day_time_left, 89.5, "half a second passes")
	core.tick(-5.0)
	_check_equal(core.state.day_time_left, 89.5, "a negative delta moves nothing")
	core.tick(NAN)
	_check_equal(core.state.day_time_left, 89.5, "NaN moves nothing")
	_check_equal(core.state.phase, &"playing", "still playing")
	# Commands do not move the clock.
	core.begin_activity()
	core.end_activity()
	_check_equal(core.state.day_time_left, 89.5, "commands do not move the clock")
	core.tick(1000.0)
	_check_equal(core.state.day_time_left, 0.0, "the clock stops at 0")
	core.tick(1000.0)
	core.tick(INF)
	_check_equal(core.state.day_time_left, 0.0, "the clock never goes below 0")
	_check_equal(core.state.day_length, 100.0, "the day length does not change")


func _test_day_ends_when_time_is_up() -> void:
	var core: GameCore = _new_core()
	core.tick(0.0)
	_events.clear()
	core.tick(99.0)
	_check_equal(_count("day_ended"), 0, "not ended with 1 second left")
	_check_equal(core.state.phase, &"playing", "playing with 1 second left")
	core.tick(1.0)
	_check_equal(_count("day_ended"), 1, "day_ended once")
	_check_equal(core.state.phase, &"summary", "phase is summary")
	var expected: Dictionary = {"day": 1, "ended_by": &"time", "time_used": 100.0}
	_check_equal(_events[0], ["day_ended", expected], "the summary in the signal")
	_check_equal(core.state.last_summary, expected, "the summary in the state")
	_check_equal(typeof(_events[0][1]["ended_by"]), TYPE_STRING_NAME, "ended_by is a StringName")
	# The signal carries a copy: changing it does not change the state.
	(_events[0][1] as Dictionary)["day"] = 99
	_check_equal(core.state.last_summary["day"], 1, "the state keeps its own summary")
	for index: int in 5:
		core.tick(30.0)
	_check_equal(_count("day_ended"), 1, "day_ended is not sent again")
	_check_equal(_count("day_started"), 0, "the next day does not start by itself")
	_check_equal(core.state.day, 1, "still day 1")
	_check_equal(core.state.day_time_left, 0.0, "time left stays 0")


func _test_request_end_day() -> void:
	var core: GameCore = _new_core()
	core.tick(30.0)
	_events.clear()
	_check_ok(core.request_end_day(), "the request is accepted")
	_check_equal(core.state.phase, &"playing", "nothing ends before the next tick")
	_check_equal(_events.size(), 0, "no signal before the next tick")
	_check_fails(core.request_end_day(), &"day_ending", "a second request is refused")
	core.tick(0.0)
	_check_equal(_count("day_ended"), 1, "day_ended once")
	_check_equal(core.state.phase, &"summary", "phase is summary")
	_check_equal(core.state.last_summary, {"day": 1, "ended_by": &"request", "time_used": 30.0}, "the summary")
	_check_equal(core.state.day_time_left, 70.0, "the time left is kept as it was")
	_check_fails(core.request_end_day(), &"not_playing", "a request in the summary is refused")
	core.tick(10.0)
	_check_equal(_count("day_ended"), 1, "day_ended is not sent again")

	# The request is handled in the next tick even when time passes in it.
	var second: GameCore = _new_core()
	second.tick(10.0)
	second.request_end_day()
	second.tick(5.0)
	_check_equal(second.state.last_summary, {"day": 1, "ended_by": &"request", "time_used": 15.0}, "time of the ending tick counts")


func _test_request_and_time_in_one_tick() -> void:
	var core: GameCore = _new_core()
	core.tick(99.0)
	_events.clear()
	_check_ok(core.request_end_day(), "the request is accepted with 1 second left")
	core.tick(5.0)
	_check_equal(_count("day_ended"), 1, "the day ends once")
	_check_equal(core.state.last_summary, {"day": 1, "ended_by": &"request", "time_used": 100.0}, "ended_by is request")
	core.tick(5.0)
	core.tick(0.0)
	_check_equal(_count("day_ended"), 1, "and never a second time")
	# Time already up and waiting to be handled: a request is refused.
	var core_at_zero: GameCore = _new_core()
	core_at_zero.begin_activity()
	core_at_zero.tick(200.0)
	core_at_zero.end_activity()
	_check_fails(core_at_zero.request_end_day(), &"day_ending", "a request while the day is already ending is refused")
	core_at_zero.tick(0.0)
	_check_equal(core_at_zero.state.last_summary["ended_by"], &"time", "that day ended by time")


func _test_activity() -> void:
	var core: GameCore = _new_core()
	core.tick(0.0)
	_events.clear()
	_check_ok(core.begin_activity(), "begin_activity")
	_check_fails(core.begin_activity(), &"activity_active", "a second begin_activity is refused")
	_check_fails(core.request_end_day(), &"activity_active", "the door sign cannot be used during an activity")
	core.tick(150.0)
	_check_equal(core.state.phase, &"playing", "the day does not end during an activity")
	_check_equal(core.state.day_time_left, 0.0, "time left is 0")
	_check_equal(_names(), ["day_end_pending"], "day_end_pending once, nothing else")
	core.tick(10.0)
	core.tick(0.0)
	_check_equal(_count("day_end_pending"), 1, "day_end_pending is not sent again")
	_check_equal(_count("day_ended"), 0, "still not ended")
	_check_fails(core.request_end_day(), &"activity_active", "the door sign is still refused")
	_check_ok(core.end_activity(), "end_activity")
	_check_equal(core.state.phase, &"playing", "nothing ends before the next tick")
	_check_equal(_count("day_ended"), 0, "no day_ended before the next tick")
	_check_fails(core.begin_activity(), &"day_ending", "no new activity while the day is ending")
	core.tick(0.0)
	_check_equal(_count("day_ended"), 1, "the day ends in the tick after end_activity")
	_check_equal(core.state.last_summary, {"day": 1, "ended_by": &"time", "time_used": 100.0}, "the summary")
	_check_fails(core.begin_activity(), &"not_playing", "no activity in the summary")
	_check_fails(core.end_activity(), &"no_activity", "end_activity without an activity is refused")

	# An activity that ends before time is up changes nothing.
	var early: GameCore = _new_core()
	early.tick(0.0)
	_events.clear()
	early.begin_activity()
	early.tick(10.0)
	_check_ok(early.end_activity(), "end_activity before time is up")
	early.tick(10.0)
	_check_equal(_events.size(), 0, "no signal for an activity that ended in time")
	_check_equal(early.state.day_time_left, 80.0, "the clock ran during the activity")
	_check_ok(early.request_end_day(), "the door sign works again after the activity")
	_check_fails(early.begin_activity(), &"day_ending", "no activity after the door sign")
	early.tick(0.0)
	_check_equal(early.state.last_summary["ended_by"], &"request", "ended by the request")

	# The next day starts clean: pending is announced again when it happens again.
	var again: GameCore = _new_core()
	again.begin_activity()
	again.tick(200.0)
	again.end_activity()
	again.tick(0.0)
	again.confirm_day_summary()
	_events.clear()
	_check_ok(again.begin_activity(), "an activity on the next day")
	again.tick(200.0)
	_check_equal(_count("day_end_pending"), 1, "day_end_pending on the next day")


func _test_summary_and_next_day() -> void:
	var core: GameCore = _new_core()
	_check_fails(core.confirm_day_summary(), &"not_in_summary", "confirm while playing is refused")
	core.tick(40.0)
	core.request_end_day()
	core.tick(0.0)
	_events.clear()
	core.tick(50.0)
	core.tick(500.0)
	_check_equal(core.state.day_time_left, 60.0, "the clock does not run in the summary")
	_check_equal(core.state.phase, &"summary", "still the summary")
	_check_equal(_events.size(), 0, "no signal while the summary is shown")
	_check_ok(core.confirm_day_summary(), "confirm in the summary")
	_check_equal(core.state.day, 2, "day 2")
	_check_equal(core.state.day_time_left, 100.0, "a full day again")
	_check_equal(core.state.phase, &"playing", "playing")
	_check_equal(core.state.last_summary, {}, "the summary is cleared")
	_check_equal(_events, [["day_started", 2]], "day_started(2) once")
	_check_fails(core.confirm_day_summary(), &"not_in_summary", "a second confirm is refused")
	_check_equal(core.state.day, 2, "still day 2")
	core.tick(25.0)
	_check_equal(core.state.day_time_left, 75.0, "the clock runs again")
	# Days go on without an end.
	for day: int in range(2, 8):
		core.tick(1000.0)
		_check_equal(core.state.last_summary["day"], day, "day %d ended" % day)
		core.confirm_day_summary()
	_check_equal(core.state.day, 8, "day 8 after six more days")


func _test_large_and_small_delta() -> void:
	# One large delta and many small ones (0.25 is exact in binary).
	var large: GameCore = GameCore.create_new(_balance())
	var small: GameCore = GameCore.create_new(_balance())
	large.tick(60.0)
	for index: int in 240:
		small.tick(0.25)
	_check_equal(_snapshot(small), _snapshot(large), "60 seconds, mid-day")
	large.tick(40.0)
	for index: int in 160:
		small.tick(0.25)
	_check_equal(_snapshot(small), _snapshot(large), "exactly the length of the day")
	_check_equal(large.state.phase, &"summary", "the day ended")

	# A delta far longer than the day ends the day once.
	var huge: GameCore = _new_core()
	huge.tick(0.0)
	_events.clear()
	huge.tick(100000.0)
	_check_equal(_count("day_ended"), 1, "a huge delta ends the day once")
	_check_equal(_count("save_requested"), 1, "and asks for one save")
	_check_equal(huge.state.day, 1, "it does not skip days")
	_check_equal(huge.state.last_summary, {"day": 1, "ended_by": &"time", "time_used": 100.0}, "the summary after a huge delta")
	var stepped: GameCore = GameCore.create_new(_balance())
	stepped.tick(0.0)
	for index: int in 1000:
		stepped.tick(0.5)
	_check_equal(_snapshot(stepped), _snapshot(huge), "the same as many small deltas")

	# The same with a request on the way.
	var large_request: GameCore = GameCore.create_new(_balance())
	var small_request: GameCore = GameCore.create_new(_balance())
	large_request.tick(30.0)
	for index: int in 120:
		small_request.tick(0.25)
	large_request.request_end_day()
	small_request.request_end_day()
	large_request.tick(20.0)
	small_request.tick(20.0)
	_check_equal(_snapshot(small_request), _snapshot(large_request), "with a request")


func _test_save_requested() -> void:
	var core: GameCore = _new_core()
	_check_equal(_count("save_requested"), 0, "none before the first tick")
	core.tick(0.0)
	_check_equal(_count("save_requested"), 1, "once for the new game")
	for index: int in 20:
		core.tick(1.0)
	_check_equal(_count("save_requested"), 1, "none while the day goes on")
	core.begin_activity()
	core.end_activity()
	core.request_end_day()
	core.tick(0.0)
	_check_equal(_count("save_requested"), 2, "once when the day ended")
	_check_equal(_names().slice(1), ["day_ended", "save_requested"], "day_ended first, save_requested last")
	for index: int in 20:
		core.tick(1.0)
	_check_equal(_count("save_requested"), 2, "none while the summary is shown")
	core.confirm_day_summary()
	_check_equal(_count("save_requested"), 2, "confirm only marks it")
	core.tick(0.0)
	_check_equal(_count("save_requested"), 3, "once when the next day started")
	core.tick(1.0)
	core.tick(1.0)
	_check_equal(_count("save_requested"), 3, "none after that")
	# Failed commands and a pending day end ask for nothing.
	core.confirm_day_summary()
	core.end_activity()
	core.begin_activity()
	core.tick(500.0)
	core.tick(1.0)
	_check_equal(_count("save_requested"), 3, "none for failed commands or a pending day end")
	core.end_activity()
	core.tick(0.0)
	_check_equal(_count("save_requested"), 4, "once when the pending day ended")
	# At most one per tick, whatever happens in it.
	var per_tick_most: int = 0
	var busy: GameCore = _new_core()
	for index: int in 50:
		var before: int = _count("save_requested")
		if index % 7 == 3:
			busy.request_end_day()
		if index % 7 == 5:
			busy.confirm_day_summary()
		busy.tick(13.0)
		per_tick_most = maxi(per_tick_most, _count("save_requested") - before)
	_check_equal(per_tick_most, 1, "at most one save_requested per tick")


func _test_confirm_inside_day_ended() -> void:
	# A receiver that confirms the summary from inside day_ended.
	var core: GameCore = _new_core()
	core.tick(0.0)
	_events.clear()
	_confirm_on_day_end = core
	core.tick(500.0)
	_check_equal(_names(), ["day_ended", "day_started", "confirm", "save_requested"], "the order of events")
	_check_equal(_count("save_requested"), 1, "one save for the tick")
	_check_equal(core.state.day, 2, "day 2")
	_check_equal(core.state.phase, &"playing", "playing")
	_check_equal(core.state.day_time_left, 100.0, "a full day")
	_confirm_on_day_end = null
	core.tick(1.0)
	_check_equal(_count("save_requested"), 1, "nothing left to save in the next tick")


func _test_save_data_round_trip() -> void:
	# Mid-day.
	var core: GameCore = GameCore.create_new(_balance())
	core.tick(1000.0)
	core.confirm_day_summary()
	core.tick(37.25)
	var data: Dictionary = core.to_save_data()
	_check_equal(data["version"], 2, "the format version is in the data")
	_check_equal(typeof(data["phase"]), TYPE_STRING, "phase is saved as text")
	var loaded: GameCore = GameCore.create_from_save_data(_balance(), data)
	_check(loaded != null, "mid-day data is accepted")
	_check_equal(_snapshot(loaded), _snapshot(core), "mid-day: the same state")
	_check_equal(typeof(loaded.state.phase), TYPE_STRING_NAME, "phase is a StringName again")
	# Through JSON text, as the save file does.
	var from_text: Variant = JSON.parse_string(JSON.stringify(data, "\t", true, true))
	var loaded_text: GameCore = GameCore.create_from_save_data(_balance(), from_text)
	_check(loaded_text != null, "mid-day data through JSON is accepted")
	_check_equal(_snapshot(loaded_text), _snapshot(core), "mid-day through JSON: the same state")
	_check_equal(typeof(loaded_text.state.day), TYPE_INT, "day is an int again")

	# A loaded game goes on from where it was, and does not ask to be saved.
	_listen(loaded)
	loaded.tick(0.0)
	_check_equal(_count("save_requested"), 0, "a loaded game does not ask for a save")
	loaded.tick(2.75)
	_check_equal(loaded.state.day_time_left, 60.0, "the clock goes on from the saved time")
	_check_equal(loaded.state.day, 2, "the day is kept")

	# In the summary.
	var ended: GameCore = GameCore.create_new(_balance())
	ended.tick(12.5)
	ended.request_end_day()
	ended.tick(0.0)
	var ended_data: Variant = JSON.parse_string(JSON.stringify(ended.to_save_data(), "\t", true, true))
	var loaded_ended: GameCore = GameCore.create_from_save_data(_balance(), ended_data)
	_check(loaded_ended != null, "summary data is accepted")
	_check_equal(_snapshot(loaded_ended), _snapshot(ended), "summary: the same state")
	_check_equal(loaded_ended.state.last_summary, {"day": 1, "ended_by": &"request", "time_used": 12.5}, "the summary is kept")
	_check_equal(typeof(loaded_ended.state.last_summary["ended_by"]), TYPE_STRING_NAME, "ended_by is a StringName again")
	_check_ok(loaded_ended.confirm_day_summary(), "the loaded summary can be confirmed")
	_check_equal(loaded_ended.state.day, 2, "day 2 after that")

	# Ended by time.
	var timed: GameCore = GameCore.create_new(_balance())
	timed.tick(1000.0)
	var loaded_timed: GameCore = GameCore.create_from_save_data(_balance(), timed.to_save_data())
	_check_equal(_snapshot(loaded_timed), _snapshot(timed), "ended by time: the same state")

	# Fields the core does not know are ignored.
	var extra: Dictionary = _valid_save_data()
	extra["something_new"] = [1, 2, 3]
	_check(GameCore.create_from_save_data(_balance(), extra) != null, "unknown fields are ignored")
	_check_equal(GameCore.save_data_problem(_valid_save_data()), "", "valid data has no problem")
	_check_equal(GameCore.save_data_problem(_valid_summary_save_data()), "", "valid summary data has no problem")


func _test_save_data_refused() -> void:
	var cases: Array = []
	cases.append(["not a dictionary", [1, 2]])
	cases.append(["text", "save"])
	cases.append(["null", null])
	cases.append(["empty", {}])
	for field: String in ["version", "day", "day_length", "day_time_left", "phase", "last_summary"]:
		var missing: Dictionary = _valid_save_data()
		missing.erase(field)
		cases.append(["no %s" % field, missing])
	var changes: Array = [
		["version", 1], ["version", 3], ["version", 0], ["version", "2"], ["version", 2.5],
		["day_length", 0], ["day_length", 0.0], ["day_length", -100.0], ["day_length", INF], ["day_length", NAN],
		["day_length", "100"], ["day_length", null], ["day_length", [100]], ["day_length", 30.0],
		["day", 0], ["day", -3], ["day", 1.5], ["day", "2"], ["day", null], ["day", INF],
		["day_time_left", -1.0], ["day_time_left", 100.5], ["day_time_left", 100000.0],
		["day_time_left", "40"], ["day_time_left", null], ["day_time_left", NAN], ["day_time_left", INF],
		["phase", "paused"], ["phase", ""], ["phase", 3], ["phase", null],
		["last_summary", []], ["last_summary", null], ["last_summary", "none"],
		["last_summary", {"day": 3, "ended_by": "request", "time_used": 60.0}],
	]
	for change: Array in changes:
		var changed: Dictionary = _valid_save_data()
		changed[change[0]] = change[1]
		cases.append(["%s = %s" % [change[0], str(change[1])], changed])
	# In the summary.
	var no_summary: Dictionary = _valid_summary_save_data()
	no_summary["last_summary"] = {}
	cases.append(["summary without a summary", no_summary])
	for field: String in ["day", "ended_by", "time_used"]:
		var missing_summary: Dictionary = _valid_summary_save_data()
		(missing_summary["last_summary"] as Dictionary).erase(field)
		cases.append(["summary without %s" % field, missing_summary])
	var summary_changes: Array = [
		["day", 2], ["day", 4], ["day", "3"], ["day", 3.5],
		["ended_by", "magic"], ["ended_by", 1], ["ended_by", null],
		["time_used", -1.0], ["time_used", 150.0], ["time_used", "60"], ["time_used", 10.0], ["time_used", NAN],
	]
	for change: Array in summary_changes:
		var changed_summary: Dictionary = _valid_summary_save_data()
		(changed_summary["last_summary"] as Dictionary)[change[0]] = change[1]
		cases.append(["summary %s = %s" % [change[0], str(change[1])], changed_summary])
	# Ended by time with time left.
	var time_with_time_left: Dictionary = _valid_summary_save_data()
	(time_with_time_left["last_summary"] as Dictionary)["ended_by"] = "time"
	cases.append(["ended by time with time left", time_with_time_left])

	for case: Array in cases:
		var before: String = var_to_str(case[1])
		_check(GameCore.save_data_problem(case[1]) != "", "%s: no problem was found" % case[0])
		_check(GameCore.create_from_save_data(_balance(), case[1]) == null, "%s: a game was made from it" % case[0])
		_check_equal(var_to_str(case[1]), before, "%s: the data was changed" % case[0])
	print("[%s]   %d kinds of bad save data were refused" % [TAG, cases.size()])

	# The day length in the save data decides, not the balance
	# (docs/roles/leader/outputs/14 design, section 2). Before 14 the data was
	# refused when the balance had a day shorter than the time left.
	_check(GameCore.create_from_save_data(_balance(100.0), _valid_save_data()) != null, "40 seconds left of a saved day of 100, balance 100")
	_check(GameCore.create_from_save_data(_balance(30.0), _valid_save_data()) != null, "40 seconds left of a saved day of 100, balance 30")
	var short_saved_day: Dictionary = _valid_save_data()
	short_saved_day["day_length"] = 30.0
	_check(GameCore.create_from_save_data(_balance(100.0), short_saved_day) == null, "40 seconds left does not fit a saved day of 30")
	# A save in the format of version 1, as the 13 work wrote it.
	var version_1: Dictionary = {"version": 1, "day": 3, "day_time_left": 40.0, "phase": "playing", "last_summary": {}}
	_check(GameCore.create_from_save_data(_balance(), version_1) == null, "a version 1 save is refused")
	_check(GameCore.save_data_problem(version_1).contains("version"), "and the reason names the version")
	# Whole numbers that arrive as floats (JSON) are accepted.
	var as_floats: Dictionary = {"version": 2.0, "day": 3.0, "day_length": 100, "day_time_left": 40, "phase": "playing", "last_summary": {}}
	_check(GameCore.create_from_save_data(_balance(), as_floats) != null, "whole numbers as floats are accepted")


## docs/roles/leader/outputs/14 design, section 2: the day in progress keeps
## the length it was saved with; the next day takes the balance's length.
func _test_day_length_is_saved() -> void:
	# Saved mid-day with a day of 100: 70 seconds left.
	var saved_core: GameCore = GameCore.create_new(_balance(100.0))
	saved_core.tick(30.0)
	var data: Dictionary = saved_core.to_save_data()
	_check_equal(data["day_length"], 100.0, "the day length is in the save data")
	for new_length: float in [40.0, 250.0, 100.0]:
		var tag: String = "balance %d" % int(new_length)
		var from_text: Variant = JSON.parse_string(JSON.stringify(data, "\t", true, true))
		var core: GameCore = GameCore.create_from_save_data(_balance(new_length), from_text)
		_check(core != null, "%s: the save is read" % tag)
		if core == null:
			continue
		_events.clear()
		_listen(core)
		_check_equal(core.state.day_length, 100.0, "%s: the day in progress keeps its saved length" % tag)
		_check_equal(core.state.day_time_left, 70.0, "%s: the time left is as saved" % tag)
		_check_equal(core.to_save_data(), data, "%s: saving again gives the same data" % tag)
		core.tick(69.0)
		_check_equal(core.state.phase, &"playing", "%s: not over with 1 second left" % tag)
		core.tick(1000.0)
		_check_equal(core.state.last_summary, {"day": 1, "ended_by": &"time", "time_used": 100.0}, "%s: the day ends at its saved length" % tag)
		_check_equal(core.state.day_length, 100.0, "%s: the length is unchanged in the summary" % tag)
		_check_equal(core.to_save_data()["day_length"], 100.0, "%s: the summary is saved with that length" % tag)
		_check_ok(core.confirm_day_summary(), "%s: confirm" % tag)
		_check_equal(core.state.day_length, new_length, "%s: the next day has the balance's length" % tag)
		_check_equal(core.state.day_time_left, new_length, "%s: and a full day of it" % tag)
		_check_equal(core.to_save_data()["day_length"], new_length, "%s: which is what gets saved" % tag)
		core.tick(100000.0)
		_check_equal(core.state.last_summary, {"day": 2, "ended_by": &"time", "time_used": new_length}, "%s: day 2 ends at the new length" % tag)
		_check_equal(_count("day_ended"), 2, "%s: two days ended" % tag)

	# Ended early by the door sign after loading: the time used is counted from the saved length.
	var early: GameCore = GameCore.create_from_save_data(_balance(40.0), data.duplicate(true))
	early.tick(20.0)
	early.request_end_day()
	early.tick(0.0)
	_check_equal(early.state.last_summary, {"day": 1, "ended_by": &"request", "time_used": 50.0}, "the time used counts from the saved length")

	# Saved in the summary, by the door sign and by time.
	var by_request: GameCore = GameCore.create_new(_balance(100.0))
	by_request.tick(30.0)
	by_request.request_end_day()
	by_request.tick(0.0)
	var by_time: GameCore = GameCore.create_new(_balance(100.0))
	by_time.tick(1000.0)
	for source: GameCore in [by_request, by_time]:
		var summary_data: Dictionary = source.to_save_data()
		var summary_before: Dictionary = source.state.last_summary.duplicate()
		for new_length: float in [40.0, 250.0]:
			var tag: String = "summary by %s, balance %d" % [summary_before["ended_by"], int(new_length)]
			var from_text: Variant = JSON.parse_string(JSON.stringify(summary_data, "\t", true, true))
			var core: GameCore = GameCore.create_from_save_data(_balance(new_length), from_text)
			_check(core != null, "%s: the save is read" % tag)
			if core == null:
				continue
			_check_equal(core.state.phase, &"summary", "%s: still the summary" % tag)
			_check_equal(core.state.last_summary, summary_before, "%s: the summary is as saved" % tag)
			_check_equal(core.state.day_length, 100.0, "%s: the ended day keeps its saved length" % tag)
			_check_equal(core.to_save_data(), summary_data, "%s: saving again gives the same data" % tag)
			_check_ok(core.confirm_day_summary(), "%s: confirm" % tag)
			_check_equal(core.state.day, 2, "%s: day 2" % tag)
			_check_equal(core.state.day_length, new_length, "%s: the next day has the balance's length" % tag)
			_check_equal(core.state.day_time_left, new_length, "%s: and a full day of it" % tag)

	# The summary is checked against the saved length, not the balance.
	var summary_check: Dictionary = by_request.to_save_data()
	_check_equal(GameCore.save_data_problem(summary_check), "", "time used 30 of a saved day of 100 is fine")
	summary_check["day_length"] = 90.0
	_check(GameCore.save_data_problem(summary_check) != "", "time used 30 with 70 left does not fit a saved day of 90")

	# A game that was never saved and loaded: every day has the balance's length.
	var plain: GameCore = GameCore.create_new(_balance(100.0))
	plain.tick(1000.0)
	plain.confirm_day_summary()
	_check_equal(plain.state.day_length, 100.0, "without a change the next day has the same length")


func _test_failed_commands_change_nothing() -> void:
	# Playing.
	var core: GameCore = _new_core()
	core.tick(20.0)
	_events.clear()
	var before: Dictionary = _snapshot(core)
	_check_fails(core.confirm_day_summary(), &"not_in_summary", "confirm while playing")
	_check_fails(core.end_activity(), &"no_activity", "end_activity without an activity")
	_check_equal(_snapshot(core), before, "playing: the state is the same")
	_check_equal(_events.size(), 0, "playing: no signal")
	core.tick(1.0)
	_check_equal(core.state.day_time_left, 79.0, "playing: the day simply goes on")
	_check_equal(_events.size(), 0, "playing: nothing happened in the next tick")

	# During an activity.
	core.begin_activity()
	before = _snapshot(core)
	_check_fails(core.request_end_day(), &"activity_active", "request during an activity")
	_check_fails(core.begin_activity(), &"activity_active", "begin during an activity")
	_check_fails(core.confirm_day_summary(), &"not_in_summary", "confirm during an activity")
	_check_equal(_snapshot(core), before, "activity: the state is the same")
	core.tick(1.0)
	_check_equal(_events.size(), 0, "activity: the refused request did not end the day")
	core.end_activity()

	# After a request.
	core.request_end_day()
	before = _snapshot(core)
	_check_fails(core.request_end_day(), &"day_ending", "a second request")
	_check_fails(core.begin_activity(), &"day_ending", "begin after a request")
	_check_equal(_snapshot(core), before, "after a request: the state is the same")
	core.tick(0.0)
	_check_equal(_count("day_ended"), 1, "after a request: the day ends once")

	# In the summary.
	_events.clear()
	before = _snapshot(core)
	_check_fails(core.request_end_day(), &"not_playing", "request in the summary")
	_check_fails(core.begin_activity(), &"not_playing", "begin in the summary")
	_check_fails(core.end_activity(), &"no_activity", "end_activity in the summary")
	_check_equal(_snapshot(core), before, "summary: the state is the same")
	core.tick(5.0)
	_check_equal(_snapshot(core), before, "summary: the state is the same after a tick")
	_check_equal(_events.size(), 0, "summary: no signal")
	# The error is a StringName.
	_check_equal(typeof(core.request_end_day()["error"]), TYPE_STRING_NAME, "the error is a StringName")
