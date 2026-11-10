extends Node
## Real-window check for the settings manager. It needs a real window, so it
## does not work with --headless. It drives the real autoload "Settings".
##
## Run both phases in order:
##   godot --path . res://tests/app/settings_window_check.tscn -- --phase=1
##   godot --path . res://tests/app/settings_window_check.tscn -- --phase=2
##
## Phase 1 switches between fullscreen and windowed, changes the window size,
## tries to shrink the window below the minimum, and leaves "windowed" saved.
## Phase 2 checks that the game starts windowed, then removes the settings
## file again. Phase 1 refuses to run when user://settings.cfg already exists,
## so a real settings file is never overwritten or removed.
## Exit code 0 when every check passes, 1 otherwise.

const SETTINGS_PATH: String = "user://settings.cfg"
const MARKER_PATH: String = "user://settings_window_check.marker"
const MIN_WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
# Check-only values.
const FRAMES_PER_STEP: int = 20
const TOO_SMALL_SIZE: Vector2i = Vector2i(800, 600)

var _phase: int = 0
var _step: int = 0
var _frames_left: int = FRAMES_PER_STEP
var _failures: int = 0
var _expected_mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN
var _expected_size: Vector2i = Vector2i.ZERO
var _expect_centered: bool = false
var _expect_not_below_minimum: bool = false
var _step_name: String = ""


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="):
			_phase = int(argument.trim_prefix("--phase="))
	if DisplayServer.get_name() == "headless":
		print("[window_check] needs a real window; do not use --headless")
		_finish(1)
		return
	if _phase != 1 and _phase != 2:
		print("[window_check] pass -- --phase=1 or -- --phase=2")
		_finish(1)
		return
	var screen_size: Vector2i = _screen_size()
	print("[window_check] phase=%d screen=%s size_options=%s" % [
		_phase, str(screen_size), str(Settings.get_options(Settings.WINDOW_SIZE))])
	if _phase == 1:
		if FileAccess.file_exists(SETTINGS_PATH):
			print("[window_check] user://settings.cfg already exists; not touching it")
			_finish(1)
			return
		_step_name = "start with no settings file"
		_expected_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
		_expected_size = screen_size
		_expect_centered = false
	else:
		if not FileAccess.file_exists(MARKER_PATH):
			print("[window_check] phase 1 has not been run; not touching user://settings.cfg")
			_finish(1)
			return
		_step_name = "start with windowed 1280x720 saved"
		_expected_mode = DisplayServer.WINDOW_MODE_WINDOWED
		_expected_size = Vector2i(1280, 720)
		_expect_centered = true


func _process(_delta: float) -> void:
	if _phase == 0:
		return
	_frames_left -= 1
	if _frames_left > 0:
		return
	_frames_left = FRAMES_PER_STEP
	_report()
	_step += 1
	if _phase == 1:
		_next_step_phase_1()
	else:
		_next_step_phase_2()


func _next_step_phase_1() -> void:
	match _step:
		1:
			_step_name = "fullscreen -> windowed (default size 1600x900)"
			_check_true(Settings.set_value(Settings.WINDOW_MODE, &"windowed"), "set_value windowed")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Settings.get_value(Settings.WINDOW_SIZE), true)
		2:
			_step_name = "windowed: size -> 1280x720"
			_check_true(Settings.set_value(Settings.WINDOW_SIZE, Vector2i(1280, 720)), "set_value 1280x720")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i(1280, 720), true)
		3:
			_step_name = "windowed -> fullscreen"
			_check_true(Settings.set_value(Settings.WINDOW_MODE, &"fullscreen"), "set_value fullscreen")
			_expect(DisplayServer.WINDOW_MODE_FULLSCREEN, _screen_size(), false)
		4:
			_step_name = "fullscreen: size -> 1600x900 (kept, not applied)"
			_check_true(Settings.set_value(Settings.WINDOW_SIZE, Vector2i(1600, 900)), "set_value 1600x900")
			_expect(DisplayServer.WINDOW_MODE_FULLSCREEN, _screen_size(), false)
		5:
			_step_name = "fullscreen -> windowed (kept size 1600x900)"
			_check_true(Settings.set_value(Settings.WINDOW_MODE, &"windowed"), "set_value windowed")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i(1600, 900), true)
		6:
			_step_name = "reset_to_defaults (windowed 1600x900 -> fullscreen)"
			Settings.reset_to_defaults()
			_expect(DisplayServer.WINDOW_MODE_FULLSCREEN, _screen_size(), false)
		7:
			_step_name = "mode and size changed in the same frame (-> windowed 1280x720)"
			_check_true(Settings.set_value(Settings.WINDOW_SIZE, Vector2i(1280, 720)), "set_value 1280x720")
			_check_true(Settings.set_value(Settings.WINDOW_MODE, &"windowed"), "set_value windowed")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i(1280, 720), true)
		8:
			_step_name = "windowed -> fullscreen"
			_check_true(Settings.set_value(Settings.WINDOW_MODE, &"fullscreen"), "set_value fullscreen")
			_expect(DisplayServer.WINDOW_MODE_FULLSCREEN, _screen_size(), false)
		9:
			_step_name = "same frame, other order: mode first, then size (-> windowed 1600x900)"
			_check_true(Settings.set_value(Settings.WINDOW_MODE, &"windowed"), "set_value windowed")
			_check_true(Settings.set_value(Settings.WINDOW_SIZE, Vector2i(1600, 900)), "set_value 1600x900")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i(1600, 900), true)
		10:
			_step_name = "try to shrink the window to 800x600 (must stay at or above 1280x720)"
			get_window().size = TOO_SMALL_SIZE
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i.ZERO, false)
			_expect_not_below_minimum = true
		11:
			_step_name = "windowed: size -> 1280x720 (state left for phase 2)"
			_check_true(Settings.set_value(Settings.WINDOW_SIZE, Vector2i(1280, 720)), "set_value 1280x720")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i(1280, 720), true)
		12:
			_check_true(Settings.set_value(Settings.VSYNC, false), "set_value vsync off")
			var vsync_off: DisplayServer.VSyncMode = DisplayServer.window_get_vsync_mode()
			_check_true(vsync_off == DisplayServer.VSYNC_DISABLED, "vsync mode is disabled")
			_check_true(Settings.set_value(Settings.VSYNC, true), "set_value vsync on")
			var vsync_on: DisplayServer.VSyncMode = DisplayServer.window_get_vsync_mode()
			_check_true(vsync_on == DisplayServer.VSYNC_ENABLED, "vsync mode is enabled")
			print("[window_check] vsync off -> mode=%d (expected %d), vsync on -> mode=%d (expected %d)" % [
				vsync_off, DisplayServer.VSYNC_DISABLED, vsync_on, DisplayServer.VSYNC_ENABLED])
			Settings.flush()
			_write_marker()
			print("[window_check] saved; settings file exists=", FileAccess.file_exists(SETTINGS_PATH))
			_check_true(FileAccess.file_exists(SETTINGS_PATH), "settings file written")
			_finish(1 if _failures > 0 else 0)


func _next_step_phase_2() -> void:
	# The start state was reported; remove the files phase 1 created.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MARKER_PATH))
	print("[window_check] settings file exists after cleanup=", FileAccess.file_exists(SETTINGS_PATH))
	_check_true(not FileAccess.file_exists(SETTINGS_PATH), "settings file removed")
	_finish(1 if _failures > 0 else 0)


func _write_marker() -> void:
	var file: FileAccess = FileAccess.open(MARKER_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("created by settings_window_check phase 1")
		file.close()


func _expect(mode: DisplayServer.WindowMode, window_size: Vector2i, centered: bool) -> void:
	_expected_mode = mode
	_expected_size = window_size
	_expect_centered = centered
	_expect_not_below_minimum = false


func _report() -> void:
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	var window_size: Vector2i = DisplayServer.window_get_size()
	var position: Vector2i = DisplayServer.window_get_position()
	var screen: int = get_window().current_screen
	var centered_position: Vector2i = DisplayServer.screen_get_position(screen) + (_screen_size() - window_size) / 2
	var ok: bool = mode == _expected_mode
	if _expect_not_below_minimum:
		ok = ok and window_size.x >= MIN_WINDOW_SIZE.x and window_size.y >= MIN_WINDOW_SIZE.y
	else:
		ok = ok and window_size == _expected_size
	if _expect_centered:
		ok = ok and position == centered_position
	print("[window_check] %s | %s | mode=%d (expected %d) size=%s (expected %s) position=%s (center %s) min_size=%s" % [
		"ok  " if ok else "FAIL", _step_name, mode, _expected_mode, str(window_size), str(_expected_size),
		str(position), str(centered_position), str(get_window().min_size)])
	if not ok:
		_failures += 1


func _check_true(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		print("[window_check] FAIL | ", what)


func _screen_size() -> Vector2i:
	return DisplayServer.screen_get_size(get_window().current_screen)


func _finish(exit_code: int) -> void:
	_phase = 0
	print("[window_check] RESULT ", "PASS" if exit_code == 0 else "FAIL")
	get_tree().quit(exit_code)
