extends Node
## Test-only game object for the screens.
##
## Follows the contract in docs/roles/leader/outputs/13 design, section 5 (Game, GameCore,
## GameState), but keeps everything in memory: it reads and writes no file.
## The real ones are in scripts/game/ (worker-01). Nothing under scenes/ or
## scripts/ may depend on this script.
##
## The day length here is a test value, not a number of the game.

signal game_started
signal game_ended

## The game in progress, or null. A FakeCore.
var core: RefCounted = null

# --- Test hooks (not part of the contract) -----------------------------------
## What has_save() answers. new_game() sets it to true.
var save_exists: bool = false
## When false, new_game() fails and changes nothing.
var new_game_succeeds: bool = true
## When false, continue_game() fails and changes nothing.
var continue_succeeds: bool = true
## The state a continued game starts in.
var saved_day: int = 1
var saved_time_left: float = 600.0
var saved_phase: StringName = &"playing"
var saved_summary: Dictionary = {}
## Length of a day for games made by this object (test value).
var test_day_length: float = 600.0
## When true the object ticks its core every frame, like the real Game.
var auto_tick: bool = false
## Every contract call, in order, as text.
var calls: PackedStringArray = PackedStringArray()

var _blocked: Dictionary = {}


func _process(delta: float) -> void:
	if auto_tick:
		tick(delta)


# --- Contract ----------------------------------------------------------------

func has_save() -> bool:
	return save_exists


func new_game() -> bool:
	calls.append("new_game")
	if not new_game_succeeds:
		return false
	_blocked.clear()
	core = FakeCore.new(1, test_day_length, test_day_length, &"playing", {})
	save_exists = true
	game_started.emit()
	return true


func continue_game() -> bool:
	calls.append("continue_game")
	if not save_exists or not continue_succeeds:
		return false
	_blocked.clear()
	core = FakeCore.new(saved_day, test_day_length, saved_time_left, saved_phase, saved_summary)
	game_started.emit()
	return true


func end_game() -> void:
	calls.append("end_game")
	if core != null:
		# What a later continue_game() starts from.
		saved_day = core.state.day
		saved_time_left = core.state.day_time_left
		saved_phase = core.state.phase
		saved_summary = core.state.last_summary
	core = null
	_blocked.clear()
	game_ended.emit()


func set_time_blocked(reason: StringName, blocked: bool) -> void:
	calls.append("set_time_blocked(%s, %s)" % [reason, blocked])
	if blocked:
		_blocked[reason] = true
	else:
		_blocked.erase(reason)


func is_time_blocked() -> bool:
	return not _blocked.is_empty()


func get_save_path() -> String:
	return "user://fake_game_writes_no_file.json"


# --- Test hooks --------------------------------------------------------------

## Advances the game like the real Game does every frame: not at all while a
## reason to stop the clock is set.
func tick(delta: float) -> void:
	if core != null and _blocked.is_empty():
		core.tick(delta)


## The reasons that stop the clock now, sorted.
func blocked_reasons() -> Array:
	var reasons: Array = _blocked.keys()
	reasons.sort()
	return reasons


func count_calls(text: String) -> int:
	var count: int = 0
	for entry: String in calls:
		if entry == text:
			count += 1
	return count


## Test-only state (13 design, 5.2).
class FakeState extends RefCounted:
	var day: int = 1
	var day_length: float = 0.0
	var day_time_left: float = 0.0
	var phase: StringName = &"playing"
	var last_summary: Dictionary = {}


## Test-only core (13 design, 5.2 and 5.3), without saving.
class FakeCore extends RefCounted:
	signal day_started(day: int)
	signal day_end_pending
	signal day_ended(summary: Dictionary)
	signal save_requested

	var state: FakeState = FakeState.new()
	## Every command call, in order, as text.
	var calls: PackedStringArray = PackedStringArray()

	var _end_requested: bool = false
	var _in_activity: bool = false
	var _pending_announced: bool = false

	func _init(day: int, day_length: float, time_left: float, phase: StringName, summary: Dictionary) -> void:
		state.day = day
		state.day_length = day_length
		state.day_time_left = time_left
		state.phase = phase
		state.last_summary = summary

	func tick(delta: float) -> void:
		var save_needed: bool = false
		# 1. The clock.
		if state.phase == &"playing":
			state.day_time_left = maxf(state.day_time_left - maxf(delta, 0.0), 0.0)
		# 2. (orders: empty)  3. (sales: empty)
		# 4. End of the day.
		if state.phase == &"playing" and (state.day_time_left <= 0.0 or _end_requested):
			if _in_activity and not _end_requested:
				if not _pending_announced:
					_pending_announced = true
					day_end_pending.emit()
			else:
				var summary: Dictionary = {
					"day": state.day,
					"ended_by": &"request" if _end_requested else &"time",
					"time_used": state.day_length - state.day_time_left,
				}
				_end_requested = false
				_pending_announced = false
				state.last_summary = summary
				state.phase = &"summary"
				save_needed = true
				day_ended.emit(summary)
		# 5. Saving.
		if save_needed:
			save_requested.emit()

	func request_end_day() -> Dictionary:
		calls.append("request_end_day")
		if state.phase != &"playing" or _end_requested or _in_activity:
			return {"ok": false, "error": &"not_allowed"}
		_end_requested = true
		return {"ok": true}

	func confirm_day_summary() -> Dictionary:
		calls.append("confirm_day_summary")
		if state.phase != &"summary":
			return {"ok": false, "error": &"not_in_summary"}
		state.day += 1
		state.day_time_left = state.day_length
		state.phase = &"playing"
		day_started.emit(state.day)
		save_requested.emit()
		return {"ok": true}

	func begin_activity() -> Dictionary:
		calls.append("begin_activity")
		if state.phase != &"playing" or _in_activity:
			return {"ok": false, "error": &"not_allowed"}
		_in_activity = true
		return {"ok": true}

	func end_activity() -> Dictionary:
		calls.append("end_activity")
		if not _in_activity:
			return {"ok": false, "error": &"not_allowed"}
		_in_activity = false
		return {"ok": true}

	func count_calls(text: String) -> int:
		var count: int = 0
		for entry: String in calls:
			if entry == text:
				count += 1
		return count
