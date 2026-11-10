extends Node
## Real-window check for the settings manager. It needs a real window, so it
## does not work with --headless.
##
## It never reads or writes user://settings.cfg. It drives its own instance of
## the manager (tests/app/settings_under_test.gd) that stores its values in
## user://settings_window_check_tmp.cfg. The autoload "Settings" is left alone,
## so stopping this check half-way cannot change the player's settings.
##
## Run the phases in order:
##   godot --path . res://tests/app/settings_window_check.tscn -- --phase=1
##   godot --path . res://tests/app/settings_window_check.tscn -- --phase=2
##   godot --path . res://tests/app/settings_window_check.tscn -- --phase=3
##
## Phase 1: fullscreen <-> windowed, window sizes, centering, minimum size,
##          vsync. Leaves "windowed 1280x720" in the test file.
## Phase 2: a new run that starts from that file must come up windowed.
##          Removes the test file.
## Phase 3: a monitor on which no window size fits (the monitor size is
##          replaced by 1280x720): windowed mode is refused and the real window
##          stays in normal fullscreen. Then a kept size that stops fitting.
##          Removes the test file.
## Exit code 0 when every check passes, 1 otherwise.

const SettingsUnderTest: GDScript = preload("res://tests/app/settings_under_test.gd")

const REAL_SETTINGS_PATH: String = "user://settings.cfg"
const CHECK_PATH: String = "user://settings_window_check_tmp.cfg"
const MIN_WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
# Check-only values.
const FRAMES_PER_STEP: int = 20
const TOO_SMALL_SIZE: Vector2i = Vector2i(800, 600)
const NO_FIT_SCREEN_SIZE: Vector2i = Vector2i(1280, 720)
const SMALLER_SCREEN_SIZE: Vector2i = Vector2i(1600, 900)

var _settings: Node = null
var _phase: int = 0
var _step: int = 0
var _frames_left: int = FRAMES_PER_STEP
var _failures: int = 0
var _expected_mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN
var _expected_size: Vector2i = Vector2i.ZERO
var _expect_centered: bool = false
var _expect_not_below_minimum: bool = false
var _step_name: String = ""
var _received: Array[StringName] = []
var _real_file_existed: bool = false
var _real_file_time: int = 0


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="):
			_phase = int(argument.trim_prefix("--phase="))
	if DisplayServer.get_name() == "headless":
		print("[window_check] needs a real window; do not use --headless")
		_finish(1)
		return
	if _phase < 1 or _phase > 3:
		print("[window_check] pass -- --phase=1, -- --phase=2 or -- --phase=3")
		_finish(1)
		return
	_real_file_existed = FileAccess.file_exists(REAL_SETTINGS_PATH)
	_real_file_time = FileAccess.get_modified_time(REAL_SETTINGS_PATH) if _real_file_existed else 0
	print("[window_check] phase=%d screen=%s real_settings_file_exists=%s" % [
		_phase, str(_screen_size()), str(_real_file_existed)])

	match _phase:
		1:
			_remove_check_file()
			_make_settings(true, Vector2i.ZERO)
			_step_name = "start with no settings file"
			_expect(DisplayServer.WINDOW_MODE_FULLSCREEN, _screen_size(), false)
		2:
			if not FileAccess.file_exists(CHECK_PATH):
				print("[window_check] run phase 1 first")
				_finish(1)
				return
			_make_settings(true, Vector2i.ZERO)
			_step_name = "start with windowed 1280x720 saved"
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i(1280, 720), true)
		3:
			_remove_check_file()
			_write_check_file("windowed", Vector2i(1280, 720))
			_make_settings(false, NO_FIT_SCREEN_SIZE)
			_step_name = "no size fits (monitor taken as 1280x720), windowed saved: start in fullscreen"
			_check_equal(_settings.get_value(Settings.WINDOW_MODE), &"fullscreen", "kept window mode on start")
			_check_equal(_settings.get_options(Settings.WINDOW_MODE), [&"fullscreen"], "window mode options")
			_check_equal(_settings.get_options(Settings.WINDOW_SIZE), [], "window size options")
			_expect(DisplayServer.WINDOW_MODE_FULLSCREEN, _screen_size(), false)
	print("[window_check] size_options=%s mode_options=%s" % [
		str(_settings.get_options(Settings.WINDOW_SIZE)), str(_settings.get_options(Settings.WINDOW_MODE))])


func _exit_tree() -> void:
	if _settings != null and _settings.changed.is_connected(_on_changed):
		_settings.changed.disconnect(_on_changed)


func _process(_delta: float) -> void:
	if _phase == 0:
		return
	_frames_left -= 1
	if _frames_left > 0:
		return
	_frames_left = FRAMES_PER_STEP
	_report()
	_step += 1
	match _phase:
		1:
			_next_step_phase_1()
		2:
			_next_step_phase_2()
		3:
			_next_step_phase_3()


func _next_step_phase_1() -> void:
	match _step:
		1:
			_step_name = "fullscreen -> windowed (default size 1600x900)"
			_check(_settings.set_value(Settings.WINDOW_MODE, &"windowed"), "set_value windowed")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, _settings.get_value(Settings.WINDOW_SIZE), true)
		2:
			_step_name = "windowed: size -> 1280x720"
			_check(_settings.set_value(Settings.WINDOW_SIZE, Vector2i(1280, 720)), "set_value 1280x720")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i(1280, 720), true)
		3:
			_step_name = "windowed -> fullscreen"
			_check(_settings.set_value(Settings.WINDOW_MODE, &"fullscreen"), "set_value fullscreen")
			_expect(DisplayServer.WINDOW_MODE_FULLSCREEN, _screen_size(), false)
		4:
			_step_name = "fullscreen: size -> 1600x900 (kept, not applied)"
			_check(_settings.set_value(Settings.WINDOW_SIZE, Vector2i(1600, 900)), "set_value 1600x900")
			_expect(DisplayServer.WINDOW_MODE_FULLSCREEN, _screen_size(), false)
		5:
			_step_name = "fullscreen -> windowed (kept size 1600x900)"
			_check(_settings.set_value(Settings.WINDOW_MODE, &"windowed"), "set_value windowed")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i(1600, 900), true)
		6:
			_step_name = "reset_to_defaults (windowed 1600x900 -> fullscreen)"
			_settings.reset_to_defaults()
			_expect(DisplayServer.WINDOW_MODE_FULLSCREEN, _screen_size(), false)
		7:
			_step_name = "mode and size changed in the same frame (-> windowed 1280x720)"
			_check(_settings.set_value(Settings.WINDOW_SIZE, Vector2i(1280, 720)), "set_value 1280x720")
			_check(_settings.set_value(Settings.WINDOW_MODE, &"windowed"), "set_value windowed")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i(1280, 720), true)
		8:
			_step_name = "windowed -> fullscreen"
			_check(_settings.set_value(Settings.WINDOW_MODE, &"fullscreen"), "set_value fullscreen")
			_expect(DisplayServer.WINDOW_MODE_FULLSCREEN, _screen_size(), false)
		9:
			_step_name = "same frame, other order: mode first, then size (-> windowed 1600x900)"
			_check(_settings.set_value(Settings.WINDOW_MODE, &"windowed"), "set_value windowed")
			_check(_settings.set_value(Settings.WINDOW_SIZE, Vector2i(1600, 900)), "set_value 1600x900")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i(1600, 900), true)
		10:
			_step_name = "try to shrink the window to 800x600 (must stay at or above 1280x720)"
			get_window().size = TOO_SMALL_SIZE
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i.ZERO, false)
			_expect_not_below_minimum = true
		11:
			_step_name = "windowed: size -> 1280x720 (state left for phase 2)"
			_check(_settings.set_value(Settings.WINDOW_SIZE, Vector2i(1280, 720)), "set_value 1280x720")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i(1280, 720), true)
		12:
			_check(_settings.set_value(Settings.VSYNC, false), "set_value vsync off")
			var vsync_off: DisplayServer.VSyncMode = DisplayServer.window_get_vsync_mode()
			_check(vsync_off == DisplayServer.VSYNC_DISABLED, "vsync mode is disabled")
			_check(_settings.set_value(Settings.VSYNC, true), "set_value vsync on")
			var vsync_on: DisplayServer.VSyncMode = DisplayServer.window_get_vsync_mode()
			_check(vsync_on == DisplayServer.VSYNC_ENABLED, "vsync mode is enabled")
			print("[window_check] vsync off -> mode=%d (expected %d), vsync on -> mode=%d (expected %d)" % [
				vsync_off, DisplayServer.VSYNC_DISABLED, vsync_on, DisplayServer.VSYNC_ENABLED])
			_settings.flush()
			_check(FileAccess.file_exists(CHECK_PATH), "test settings file written")
			_finish_checked(false)


func _next_step_phase_2() -> void:
	_finish_checked(true)


func _next_step_phase_3() -> void:
	match _step:
		1:
			_step_name = "no size fits: windowed is refused, window stays in normal fullscreen"
			_received.clear()
			_check(not _settings.set_value(Settings.WINDOW_MODE, &"windowed"), "set_value windowed returns false")
			_check_equal(_settings.get_value(Settings.WINDOW_MODE), &"fullscreen", "kept window mode")
			_check_equal(_received.size(), 0, "changed count")
			_expect(DisplayServer.WINDOW_MODE_FULLSCREEN, _screen_size(), false)
		2:
			_step_name = "real monitor size again: windowed is accepted (kept size 1280x720)"
			_settings.use_real_screen_size = true
			_check_equal(_settings.get_options(Settings.WINDOW_MODE), [&"fullscreen", &"windowed"], "window mode options")
			_check(_settings.set_value(Settings.WINDOW_MODE, &"windowed"), "set_value windowed")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i(1280, 720), true)
		3:
			_step_name = "windowed: size -> 1600x900"
			_check(_settings.set_value(Settings.WINDOW_SIZE, Vector2i(1600, 900)), "set_value 1600x900")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i(1600, 900), true)
		4:
			_step_name = "windowed -> fullscreen"
			_check(_settings.set_value(Settings.WINDOW_MODE, &"fullscreen"), "set_value fullscreen")
			_expect(DisplayServer.WINDOW_MODE_FULLSCREEN, _screen_size(), false)
		5:
			_step_name = "kept 1600x900 stops fitting (monitor taken as 1600x900): windowed uses 1280x720"
			_settings.use_real_screen_size = false
			_settings.test_screen_size = SMALLER_SCREEN_SIZE
			_received.clear()
			_check(_settings.set_value(Settings.WINDOW_MODE, &"windowed"), "set_value windowed")
			_check_equal(_settings.get_value(Settings.WINDOW_SIZE), Vector2i(1280, 720), "kept size replaced")
			var expected: Array[StringName] = [Settings.WINDOW_MODE, Settings.WINDOW_SIZE]
			_check_equal(_received, expected, "changed for the mode and the replaced size")
			_expect(DisplayServer.WINDOW_MODE_WINDOWED, Vector2i(1280, 720), true)
		6:
			_step_name = "no size fits while windowed: back to fullscreen is accepted"
			_settings.test_screen_size = NO_FIT_SCREEN_SIZE
			_check(_settings.set_value(Settings.WINDOW_MODE, &"fullscreen"), "set_value fullscreen")
			_expect(DisplayServer.WINDOW_MODE_FULLSCREEN, _screen_size(), false)
		7:
			_finish_checked(true)


# --- Helpers ------------------------------------------------------------------

func _make_settings(use_real_screen: bool, screen_size: Vector2i) -> void:
	_settings = SettingsUnderTest.new()
	_settings.test_storage_path = CHECK_PATH
	_settings.use_real_screen_size = use_real_screen
	_settings.test_screen_size = screen_size
	_settings.changed.connect(_on_changed)
	add_child(_settings)


func _on_changed(key: StringName) -> void:
	_received.append(key)


func _write_check_file(window_mode: String, window_size: Vector2i) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("meta", "version", 1)
	config.set_value("graphics", "window_mode", window_mode)
	config.set_value("graphics", "window_size", window_size)
	config.save(CHECK_PATH)


func _remove_check_file() -> void:
	if FileAccess.file_exists(CHECK_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHECK_PATH))


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


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures += 1
		print("[window_check] FAIL | ", what)


func _check_equal(actual: Variant, expected: Variant, what: String) -> void:
	var same: bool = typeof(actual) == typeof(expected) and actual == expected
	if not same:
		_failures += 1
		print("[window_check] FAIL | %s: expected %s, got %s" % [what, str(expected), str(actual)])


func _screen_size() -> Vector2i:
	return DisplayServer.screen_get_size(get_window().current_screen)


## Ends the run: frees the manager, optionally removes the test file, and
## checks that the real settings file was not created or modified.
func _finish_checked(remove_check_file: bool) -> void:
	_settings.changed.disconnect(_on_changed)
	remove_child(_settings)
	_settings.free()
	_settings = null
	if remove_check_file:
		_remove_check_file()
	print("[window_check] test file exists=%s real settings file exists=%s" % [
		str(FileAccess.file_exists(CHECK_PATH)), str(FileAccess.file_exists(REAL_SETTINGS_PATH))])
	_check(FileAccess.file_exists(REAL_SETTINGS_PATH) == _real_file_existed, "user://settings.cfg was created or removed")
	if _real_file_existed:
		_check(FileAccess.get_modified_time(REAL_SETTINGS_PATH) == _real_file_time, "user://settings.cfg was modified")
	if remove_check_file:
		_check(not FileAccess.file_exists(CHECK_PATH), "test settings file removed")
	_finish(1 if _failures > 0 else 0)


func _finish(exit_code: int) -> void:
	_phase = 0
	print("[window_check] RESULT ", "PASS" if exit_code == 0 else "FAIL")
	get_tree().quit(exit_code)
