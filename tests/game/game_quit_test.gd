extends Node
## Headless test in two runs: the autoload Game saves a game in progress when
## the game really quits, and the next run continues from that moment
## (docs/roles/leader/outputs/13 design, 5.1 and 7.4).
##
## Run the phases in order:
##   godot --headless --path . res://tests/game/game_quit_test.tscn -- --settings-path=user://test_settings.cfg --save-path=user://test_save.json --phase=1
##   godot --headless --path . res://tests/game/game_quit_test.tscn -- --settings-path=user://test_settings.cfg --save-path=user://test_save.json --phase=2
##
## Phase 1 starts a new game, lets some time pass and quits without ending the
##         game. It leaves the test save file for phase 2.
## Phase 2 continues: the time left must be the time left when phase 1 quit,
##         not the full day that was saved when the game was made. It removes
##         the test save file.
## Exit code 0 when the phase passed, 1 otherwise. Without the settings and
## save arguments the run does nothing and exits with 1.

const Isolation: GDScript = preload("res://tests/common/game_isolation.gd")

const SCENE_PATH: String = "res://tests/game/game_quit_test.tscn"
const TAG: String = "game_quit_test"
const NOTE_PATH: String = "user://game_quit_test_note.json"
# Test values.
const PLAY_MSEC: int = 400
const TIME_TOLERANCE: float = 0.000001

var _phase: int = 0
var _quit_at_msec: int = 0


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="):
			_phase = int(argument.trim_prefix("--phase="))
	var phase_text: String = "--phase=%d" % (_phase if _phase == 2 else 1)
	# Phase 2 continues from the save phase 1 left.
	if not Isolation.begin(get_tree(), TAG, SCENE_PATH, true, phase_text, _phase == 2):
		_phase = 0
		get_tree().quit(1)
		return
	if _phase == 1:
		_start_phase_1()
	elif _phase == 2:
		_run_phase_2()
	else:
		print("[%s] pass --phase=1 or --phase=2 after the two paths" % TAG)
		get_tree().quit(1)


func _process(_delta: float) -> void:
	if _phase != 1 or _quit_at_msec == 0 or Time.get_ticks_msec() < _quit_at_msec:
		return
	_phase = 0
	var time_left: float = Game.core.state.day_time_left
	var ok: bool = time_left < Game.core.state.day_length
	print("[%s] phase 1: quitting with a game in progress, time left %.6f of %.6f" % [
		TAG, time_left, Game.core.state.day_length])
	# What phase 2 must find. Game is not told to end or save: quitting does it.
	var note: FileAccess = FileAccess.open(NOTE_PATH, FileAccess.WRITE)
	note.store_string(JSON.stringify({"day_time_left": time_left}, "", true, true))
	note.close()
	ok = Isolation.finish(get_tree(), TAG, true) and ok
	print("[%s] RESULT %s" % [TAG, "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


func _start_phase_1() -> void:
	if not Game.new_game():
		print("[%s] FAIL new_game" % TAG)
		_phase = 0
		get_tree().quit(1)
		return
	print("[%s] phase 1: new game, time left %.6f" % [TAG, Game.core.state.day_time_left])
	_quit_at_msec = Time.get_ticks_msec() + PLAY_MSEC


func _run_phase_2() -> void:
	var ok: bool = true
	if not FileAccess.file_exists(NOTE_PATH) or not Game.has_save():
		print("[%s] run phase 1 first" % TAG)
		ok = false
	else:
		var note: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NOTE_PATH))
		var expected: float = float(note["day_time_left"])
		if not Game.continue_game():
			print("[%s] FAIL continue_game" % TAG)
			ok = false
		else:
			var time_left: float = Game.core.state.day_time_left
			var day_length: float = Game.core.state.day_length
			print("[%s] phase 2: continued with time left %.6f; phase 1 quit at %.6f; a full day is %.6f" % [
				TAG, time_left, expected, day_length])
			if absf(time_left - expected) > TIME_TOLERANCE:
				print("[%s] FAIL the time left is not the time left when the game quit" % TAG)
				ok = false
			if not (time_left < day_length):
				print("[%s] FAIL the save is the one made with the new game, not the one made on quitting" % TAG)
				ok = false
	if FileAccess.file_exists(NOTE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(NOTE_PATH))
	ok = Isolation.finish(get_tree(), TAG) and ok
	print("[%s] RESULT %s" % [TAG, "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)
