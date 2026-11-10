class_name GameCore
extends RefCounted
## The rules and the state of the game (docs/roles/leader/outputs/13 design,
## sections 5.2 and 5.3). For now: the day, the day clock, the end of a day and
## the conversion to and from save data.
##
## The core is not a Node. It does not touch the scene tree, input, files, the
## system clock or the global random functions. Time only passes in tick().

# --- Contract (13 design, 5.2). Do not change. --------------------------------
signal day_started(day: int)
signal day_end_pending
signal day_ended(summary: Dictionary)
signal save_requested

var state: GameState

# --- Names --------------------------------------------------------------------
const ENDED_BY_TIME: StringName = &"time"
const ENDED_BY_REQUEST: StringName = &"request"

## The "error" of a failed command.
const ERROR_NOT_PLAYING: StringName = &"not_playing"
const ERROR_NOT_IN_SUMMARY: StringName = &"not_in_summary"
const ERROR_ACTIVITY_ACTIVE: StringName = &"activity_active"
const ERROR_NO_ACTIVITY: StringName = &"no_activity"
const ERROR_DAY_ENDING: StringName = &"day_ending"

## Balance keys the core reads.
const KEY_DAY_LENGTH: StringName = &"day_length_seconds"
const REQUIRED_BALANCE_KEYS: Array[StringName] = [KEY_DAY_LENGTH]

# --- Save data format ---------------------------------------------------------
## 2: the length of the day in progress is saved (14 design, section 2).
const SAVE_VERSION: int = 2
const _SAVE_TIME_TOLERANCE: float = 0.001

## Read when a day starts: the next day takes its length from here.
var _balance: Balance = null
var _end_requested: bool = false
var _activity_active: bool = false
var _day_end_pending_announced: bool = false
var _save_needed: bool = false


# --- Making a core ------------------------------------------------------------

## What is wrong with the balance for the core. Empty when nothing is.
static func balance_problems(balance: Balance) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if balance == null:
		problems.append("there is no balance")
		return problems
	for key: StringName in REQUIRED_BALANCE_KEYS:
		if not balance.has_key(key):
			problems.append("'%s' is missing" % key)
		elif not balance.has_number(key):
			problems.append("'%s' is not a number" % key)
	if balance.has_number(KEY_DAY_LENGTH) and balance.get_number(KEY_DAY_LENGTH) <= 0.0:
		problems.append("'%s' must be greater than 0" % KEY_DAY_LENGTH)
	return problems


## A new game on day 1. Null when the balance cannot be used. The new game is
## marked to be saved: the first tick() emits save_requested.
static func create_new(balance: Balance) -> GameCore:
	if not balance_problems(balance).is_empty():
		push_error("GameCore: cannot start a game: %s." % ", ".join(balance_problems(balance)))
		return null
	var core: GameCore = GameCore.new()
	core._balance = balance
	core.state = GameState.new()
	core.state.day = 1
	core.state.day_length = balance.get_number(KEY_DAY_LENGTH)
	core.state.day_time_left = core.state.day_length
	core.state.phase = GameState.PHASE_PLAYING
	core.state.last_summary = {}
	core._save_needed = true
	return core


## A game from save data. Null when the balance cannot be used or the save data
## is refused. Save data is never repaired.
## The day in progress keeps the length it was saved with, whatever the balance
## says now; the balance gives the length of the days that start later
## (docs/roles/leader/outputs/14 design, section 2).
static func create_from_save_data(balance: Balance, data: Variant) -> GameCore:
	if not balance_problems(balance).is_empty():
		push_error("GameCore: cannot load a game: %s." % ", ".join(balance_problems(balance)))
		return null
	if save_data_problem(data) != "":
		return null
	var saved: Dictionary = data
	var core: GameCore = GameCore.new()
	core._balance = balance
	core.state = GameState.new()
	core.state.day = int(saved["day"])
	core.state.day_length = float(saved["day_length"])
	core.state.day_time_left = float(saved["day_time_left"])
	core.state.phase = StringName(saved["phase"])
	core.state.last_summary = {}
	if core.state.phase == GameState.PHASE_SUMMARY:
		var summary: Dictionary = saved["last_summary"]
		core.state.last_summary = {
			"day": int(summary["day"]),
			"ended_by": StringName(summary["ended_by"]),
			"time_used": float(summary["time_used"]),
		}
	return core


## Why the save data is refused. Empty when it is accepted. Everything is
## checked against the day length in the save data itself, not the balance.
static func save_data_problem(data: Variant) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "the save data is not a dictionary"
	var saved: Dictionary = data
	if not saved.has("version"):
		return "'version' is missing"
	if not _is_whole_number(saved["version"]):
		return "'version' is not a whole number"
	if int(saved["version"]) != SAVE_VERSION:
		return "'version' is %d, expected %d" % [int(saved["version"]), SAVE_VERSION]
	for field: String in ["day", "day_length", "day_time_left", "phase", "last_summary"]:
		if not saved.has(field):
			return "'%s' is missing" % field
	if not _is_whole_number(saved["day"]):
		return "'day' is not a whole number"
	if int(saved["day"]) < 1:
		return "'day' is less than 1"
	if not _is_number(saved["day_length"]):
		return "'day_length' is not a finite number"
	var day_length: float = float(saved["day_length"])
	if day_length <= 0.0:
		return "'day_length' is not greater than 0"
	if not _is_number(saved["day_time_left"]):
		return "'day_time_left' is not a number"
	var time_left: float = float(saved["day_time_left"])
	if time_left < 0.0:
		return "'day_time_left' is negative"
	if time_left > day_length:
		return "'day_time_left' is longer than a day"
	if typeof(saved["phase"]) != TYPE_STRING and typeof(saved["phase"]) != TYPE_STRING_NAME:
		return "'phase' is not text"
	var phase: StringName = StringName(saved["phase"])
	if phase != GameState.PHASE_PLAYING and phase != GameState.PHASE_SUMMARY:
		return "'phase' is not a known phase"
	if typeof(saved["last_summary"]) != TYPE_DICTIONARY:
		return "'last_summary' is not a dictionary"
	var summary: Dictionary = saved["last_summary"]
	if phase == GameState.PHASE_PLAYING:
		if not summary.is_empty():
			return "'last_summary' is not empty while playing"
		return ""
	for field: String in ["day", "ended_by", "time_used"]:
		if not summary.has(field):
			return "'last_summary.%s' is missing" % field
	if not _is_whole_number(summary["day"]) or int(summary["day"]) != int(saved["day"]):
		return "'last_summary.day' is not the day"
	if typeof(summary["ended_by"]) != TYPE_STRING and typeof(summary["ended_by"]) != TYPE_STRING_NAME:
		return "'last_summary.ended_by' is not text"
	var ended_by: StringName = StringName(summary["ended_by"])
	if ended_by != ENDED_BY_TIME and ended_by != ENDED_BY_REQUEST:
		return "'last_summary.ended_by' is not a known value"
	if not _is_number(summary["time_used"]):
		return "'last_summary.time_used' is not a number"
	var time_used: float = float(summary["time_used"])
	if time_used < 0.0 or time_used > day_length:
		return "'last_summary.time_used' is outside the day"
	if absf(time_used - (day_length - time_left)) > _SAVE_TIME_TOLERANCE:
		return "'last_summary.time_used' does not match 'day_time_left'"
	if ended_by == ENDED_BY_TIME and time_left > 0.0:
		return "the day ended by time but 'day_time_left' is not 0"
	return ""


## The state as save data: only numbers, text and dictionaries.
func to_save_data() -> Dictionary:
	var summary: Dictionary = {}
	if state.phase == GameState.PHASE_SUMMARY:
		summary = {
			"day": int(state.last_summary["day"]),
			"ended_by": String(state.last_summary["ended_by"]),
			"time_used": float(state.last_summary["time_used"]),
		}
	return {
		"version": SAVE_VERSION,
		"day": state.day,
		"day_length": state.day_length,
		"day_time_left": state.day_time_left,
		"phase": String(state.phase),
		"last_summary": summary,
	}


# --- Time ---------------------------------------------------------------------

## The only way time passes. The five steps and their order are fixed
## (13 design, 5.3).
func tick(delta: float) -> void:
	# 1. The day clock.
	_step_clock(delta)
	# 2. Commissions: arrival and deadlines.
	_step_commissions()
	# 3. Sales: settlement.
	_step_sales()
	# 4. The end of the day.
	_step_day_end()
	# 5. Saving, once, after everything else.
	_step_save_request()


func _step_clock(delta: float) -> void:
	if state.phase != GameState.PHASE_PLAYING:
		return
	if not (delta > 0.0) or state.day_time_left <= 0.0:
		return
	state.day_time_left = maxf(0.0, state.day_time_left - delta)


## Step 2. Empty for now; commissions go here.
func _step_commissions() -> void:
	pass


## Step 3. Empty for now; the settlement of sales goes here.
func _step_sales() -> void:
	pass


## Step 4. Time running out and the end-of-day request take the same path, and
## the day ends once.
func _step_day_end() -> void:
	if state.phase != GameState.PHASE_PLAYING:
		return
	var time_is_up: bool = state.day_time_left <= 0.0
	if not time_is_up and not _end_requested:
		return
	if _activity_active and not _end_requested:
		# Time is up in the middle of an activity: wait for it to finish.
		if not _day_end_pending_announced:
			_day_end_pending_announced = true
			day_end_pending.emit()
		return
	# What the player did comes first when both happen in the same tick.
	var ended_by: StringName = ENDED_BY_REQUEST if _end_requested else ENDED_BY_TIME
	var summary: Dictionary = {
		"day": state.day,
		"ended_by": ended_by,
		"time_used": state.day_length - state.day_time_left,
	}
	_end_requested = false
	_day_end_pending_announced = false
	state.phase = GameState.PHASE_SUMMARY
	state.last_summary = summary
	_save_needed = true
	day_ended.emit(summary.duplicate())


func _step_save_request() -> void:
	if not _save_needed:
		return
	_save_needed = false
	save_requested.emit()


# --- Commands -----------------------------------------------------------------

## The door sign. Only records the request; the day ends in the next tick().
func request_end_day() -> Dictionary:
	if state.phase != GameState.PHASE_PLAYING:
		return _fail(ERROR_NOT_PLAYING)
	if _activity_active:
		return _fail(ERROR_ACTIVITY_ACTIVE)
	if _end_requested or state.day_time_left <= 0.0:
		return _fail(ERROR_DAY_ENDING)
	_end_requested = true
	return _ok()


## The day summary was read: the next day starts.
func confirm_day_summary() -> Dictionary:
	if state.phase != GameState.PHASE_SUMMARY:
		return _fail(ERROR_NOT_IN_SUMMARY)
	state.day += 1
	# A new day takes the length the balance holds now (14 design, section 2).
	state.day_length = _balance.get_number(KEY_DAY_LENGTH)
	state.day_time_left = state.day_length
	state.phase = GameState.PHASE_PLAYING
	state.last_summary = {}
	_save_needed = true
	day_started.emit(state.day)
	return _ok()


## The start of something that must not be cut off by the end of the day.
func begin_activity() -> Dictionary:
	if state.phase != GameState.PHASE_PLAYING:
		return _fail(ERROR_NOT_PLAYING)
	if _activity_active:
		return _fail(ERROR_ACTIVITY_ACTIVE)
	if _end_requested or state.day_time_left <= 0.0:
		return _fail(ERROR_DAY_ENDING)
	_activity_active = true
	return _ok()


## The end of it. A day end that was waiting happens in the next tick().
func end_activity() -> Dictionary:
	if not _activity_active:
		return _fail(ERROR_NO_ACTIVITY)
	_activity_active = false
	return _ok()


# --- Helpers ------------------------------------------------------------------

func _ok() -> Dictionary:
	return {"ok": true}


func _fail(error: StringName) -> Dictionary:
	return {"ok": false, "error": error}


static func _is_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


## JSON has one number type, so a whole number may arrive as a float.
static func _is_whole_number(value: Variant) -> bool:
	if not _is_number(value):
		return false
	return float(value) == floorf(float(value))
