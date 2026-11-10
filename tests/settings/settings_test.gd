extends Node
## Headless tests for the settings manager (scripts/settings/settings.gd).
## Run:
##   godot --headless --path . res://tests/settings/settings_test.tscn -- --settings-path=user://test_settings.cfg
## Exit code 0 when every check passes, 1 otherwise. Without the argument the
## run is not isolated from the player's settings file: it does nothing and
## exits with 1.
##
## The autoload Settings uses the file named on the command line. The managers
## the tests create themselves use TEST_PATH. Both files are removed at the end.

const SettingsUnderTest: GDScript = preload("res://tests/settings/settings_under_test.gd")
const Isolation: GDScript = preload("res://tests/common/settings_isolation.gd")

const SCENE_PATH: String = "res://tests/settings/settings_test.tscn"
const TAG: String = "settings_test"
const TEST_PATH: String = "user://settings_test_tmp.cfg"
const FLOAT_TOLERANCE: float = 0.0001

var _check_count: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _current_test: String = ""
var _received: Array[StringName] = []
var _instances: Array[Node] = []
var _reentrant_target: Node = null
var _reentrant_seen: Array = []


func _ready() -> void:
	if not Isolation.begin(get_tree(), TAG, SCENE_PATH, true):
		get_tree().quit(1)
		return

	_run("contract", _test_contract)
	_run("storage_path", _test_storage_path)
	_run("defaults", _test_defaults)
	_run("set_value", _test_set_value)
	_run("same_value", _test_same_value)
	_run("invalid", _test_invalid)
	_run("volume_clamp", _test_volume_clamp)
	_run("reset_to_defaults", _test_reset_to_defaults)
	_run("save_and_reload", _test_save_and_reload)
	_run("file_format", _test_file_format)
	_run("broken_file", _test_broken_file)
	_run("bad_entries", _test_bad_entries)
	_run("save_once", _test_save_once)
	_run("flush", _test_flush)
	_run("save_on_exit", _test_save_on_exit)
	_run("audio_buses", _test_audio_buses)
	_run("window_size_options", _test_window_size_options)
	_run("fullscreen_start_keeps_size", _test_fullscreen_start_keeps_size)
	_run("no_usable_size", _test_no_usable_size)
	_run("size_replaced_when_windowed", _test_size_replaced_when_windowed)
	_run("reentrant_changed", _test_reentrant_changed)
	_run("get_options_table", _test_get_options_table)

	_current_test = "isolation"
	_check(not FileAccess.file_exists(TEST_PATH), "test file was left behind")
	_check(Isolation.finish(get_tree(), TAG), "the player's settings file changed or the test settings file is still there")

	print("[settings_test] checks=%d failures=%d" % [_check_count, _failures.size()])
	for failure: String in _failures:
		print("[settings_test] FAIL ", failure)
	print("[settings_test] RESULT ", "PASS" if _failures.is_empty() else "FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)


# --- Helpers ------------------------------------------------------------------

func _run(test_name: String, test: Callable) -> void:
	_current_test = test_name
	_remove_test_file()
	_received.clear()
	var failures_before: int = _failures.size()
	test.call()
	_free_instances()
	_remove_test_file()
	print("[settings_test] %s %s" % ["ok  " if _failures.size() == failures_before else "FAIL", test_name])


func _check(condition: bool, message: String) -> void:
	_check_count += 1
	if not condition:
		_failures.append("%s: %s" % [_current_test, message])


func _check_equal(actual: Variant, expected: Variant, what: String) -> void:
	var same: bool = typeof(actual) == typeof(expected) and actual == expected
	_check(same, "%s: expected %s (%s), got %s (%s)" % [
		what, str(expected), type_string(typeof(expected)), str(actual), type_string(typeof(actual))])


func _check_float(actual: Variant, expected: float, what: String) -> void:
	var same: bool = typeof(actual) == TYPE_FLOAT and absf(float(actual) - expected) <= FLOAT_TOLERANCE
	_check(same, "%s: expected %f, got %s" % [what, expected, str(actual)])


func _make(screen_size: Vector2i = Vector2i(1920, 1080)) -> Node:
	var settings: Node = SettingsUnderTest.new()
	settings.test_storage_path = TEST_PATH
	settings.test_screen_size = screen_size
	# Connected before the node enters the tree, so signals sent on start are seen too.
	settings.changed.connect(_on_changed)
	add_child(settings)
	_instances.append(settings)
	return settings


## Frees an instance. A pending change is written to the test file on the way out.
func _discard(settings: Node) -> void:
	_instances.erase(settings)
	settings.changed.disconnect(_on_changed)
	remove_child(settings)
	settings.free()


func _free_instances() -> void:
	for settings: Node in _instances.duplicate():
		_discard(settings)


func _remove_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _write_text(text: String) -> void:
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _bus_index(bus_name: StringName) -> int:
	return AudioServer.get_bus_index(bus_name)


func _on_changed(key: StringName) -> void:
	_received.append(key)


# --- Tests --------------------------------------------------------------------

func _test_contract() -> void:
	_check(get_node_or_null("/root/Settings") != null, "autoload Settings is missing")
	_check_equal(Settings.WINDOW_MODE, &"graphics/window_mode", "WINDOW_MODE")
	_check_equal(Settings.WINDOW_SIZE, &"graphics/window_size", "WINDOW_SIZE")
	_check_equal(Settings.VSYNC, &"graphics/vsync", "VSYNC")
	_check_equal(Settings.VOLUME_MASTER, &"audio/volume_master", "VOLUME_MASTER")
	_check_equal(Settings.VOLUME_MUSIC, &"audio/volume_music", "VOLUME_MUSIC")
	_check_equal(Settings.VOLUME_SFX, &"audio/volume_sfx", "VOLUME_SFX")
	_check(Settings.has_signal(&"changed"), "signal changed is missing")
	for method: String in ["get_value", "set_value", "get_options", "get_default", "reset_to_defaults", "flush", "get_storage_path"]:
		_check(Settings.has_method(method), "method %s is missing" % method)


## docs/roles/leader/outputs/11 design, section 3. The cases that need another command line
## (no argument, a path outside user://) are in settings_path_check.tscn.
func _test_storage_path() -> void:
	var given: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(Isolation.ARGUMENT):
			given = argument.substr(Isolation.ARGUMENT.length())
	_check(given.begins_with("user://"), "this run was given a user:// path")
	_check_equal(Settings.get_storage_path(), given, "the autoload uses the path from the command line")
	_check(Settings.get_storage_path() != Isolation.DEFAULT_PATH, "the autoload does not use the default path")
	_check_equal(typeof(Settings.get_storage_path()), TYPE_STRING, "get_storage_path returns a String")
	# The path does not change while running.
	Settings.flush()
	Settings.reset_to_defaults()
	_check_equal(Settings.get_storage_path(), given, "the path is the same after flush and reset")
	# A manager made by the tests reports its own file.
	var settings: Node = _make()
	_check_equal(settings.get_storage_path(), TEST_PATH, "a test manager reports its test path")
	settings.set_value(Settings.VSYNC, false)
	settings.flush()
	_check(FileAccess.file_exists(TEST_PATH), "it writes to the path it reports")
	_check(not FileAccess.file_exists(given), "nothing was written to the autoload's file")


func _test_defaults() -> void:
	var settings: Node = _make()
	_check_equal(settings.get_value(Settings.WINDOW_MODE), &"fullscreen", "window mode")
	_check_equal(settings.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "window size")
	_check_equal(settings.get_value(Settings.VSYNC), true, "vsync")
	_check_float(settings.get_value(Settings.VOLUME_MASTER), 1.0, "master")
	_check_float(settings.get_value(Settings.VOLUME_MUSIC), 0.8, "music")
	_check_float(settings.get_value(Settings.VOLUME_SFX), 1.0, "sfx")
	_check_equal(settings.get_default(Settings.WINDOW_MODE), &"fullscreen", "default window mode")
	_check_equal(settings.get_default(Settings.WINDOW_SIZE), Vector2i(1600, 900), "default window size")
	_check_equal(settings.get_default(Settings.VSYNC), true, "default vsync")
	_check_float(settings.get_default(Settings.VOLUME_MASTER), 1.0, "default master")
	_check_float(settings.get_default(Settings.VOLUME_MUSIC), 0.8, "default music")
	_check_float(settings.get_default(Settings.VOLUME_SFX), 1.0, "default sfx")
	_check_equal(settings.get_options(Settings.WINDOW_MODE), [&"fullscreen", &"windowed"], "window mode options")
	_check_equal(settings.get_options(Settings.VSYNC), [true, false], "vsync options")
	_check_equal(settings.get_options(Settings.VOLUME_MASTER), [], "volume options")
	_check_equal(settings.get_options(&"unknown/key"), [], "unknown key options")
	_check_equal(settings.get_value(&"unknown/key"), null, "unknown key value")
	_check_equal(settings.get_default(&"unknown/key"), null, "unknown key default")
	_check_equal(settings.write_count, 0, "nothing is written on start")
	_check(not FileAccess.file_exists(TEST_PATH), "no file is created on start")


func _test_set_value() -> void:
	var settings: Node = _make()
	_check(settings.set_value(Settings.WINDOW_MODE, &"windowed"), "set window mode")
	_check(settings.set_value(Settings.WINDOW_SIZE, Vector2i(1280, 720)), "set window size")
	_check(settings.set_value(Settings.VSYNC, false), "set vsync")
	_check(settings.set_value(Settings.VOLUME_MASTER, 0.5), "set master")
	_check(settings.set_value(Settings.VOLUME_MUSIC, 0.25), "set music")
	_check(settings.set_value(Settings.VOLUME_SFX, 0.0), "set sfx")
	_check_equal(settings.get_value(Settings.WINDOW_MODE), &"windowed", "window mode")
	_check_equal(settings.get_value(Settings.WINDOW_SIZE), Vector2i(1280, 720), "window size")
	_check_equal(settings.get_value(Settings.VSYNC), false, "vsync")
	_check_float(settings.get_value(Settings.VOLUME_MASTER), 0.5, "master")
	_check_float(settings.get_value(Settings.VOLUME_MUSIC), 0.25, "music")
	_check_float(settings.get_value(Settings.VOLUME_SFX), 0.0, "sfx")
	var expected: Array[StringName] = [
		Settings.WINDOW_MODE, Settings.WINDOW_SIZE, Settings.VSYNC,
		Settings.VOLUME_MASTER, Settings.VOLUME_MUSIC, Settings.VOLUME_SFX,
	]
	_check_equal(_received, expected, "changed signals")
	# A String is accepted for the window mode and kept as a StringName.
	_check(settings.set_value(Settings.WINDOW_MODE, "fullscreen"), "set window mode with a String")
	_check_equal(settings.get_value(Settings.WINDOW_MODE), &"fullscreen", "window mode after String")


func _test_same_value() -> void:
	var settings: Node = _make()
	_check(settings.set_value(Settings.VOLUME_MUSIC, 0.8), "same volume returns true")
	_check(settings.set_value(Settings.WINDOW_MODE, &"fullscreen"), "same window mode returns true")
	_check(settings.set_value(Settings.WINDOW_SIZE, Vector2i(1600, 900)), "same window size returns true")
	_check(settings.set_value(Settings.VSYNC, true), "same vsync returns true")
	_check(settings.set_value(Settings.VOLUME_MASTER, 1.5), "clamped to the same value returns true")
	_check_equal(_received.size(), 0, "changed count")
	settings._process(10.0)
	_check_equal(settings.write_count, 0, "no save is scheduled")


func _test_invalid() -> void:
	var settings: Node = _make()
	_check(not settings.set_value(&"unknown/key", 1), "unknown key")
	_check(not settings.set_value(Settings.WINDOW_MODE, &"borderless"), "unknown window mode")
	_check(not settings.set_value(Settings.WINDOW_MODE, 1), "window mode with an int")
	_check(not settings.set_value(Settings.WINDOW_SIZE, Vector2i(800, 600)), "size not in the list")
	_check(not settings.set_value(Settings.WINDOW_SIZE, Vector2i(1920, 1080)), "size as large as the monitor")
	_check(not settings.set_value(Settings.WINDOW_SIZE, "1280x720"), "size with a String")
	_check(not settings.set_value(Settings.WINDOW_SIZE, Vector2(1280.0, 720.0)), "size with a Vector2")
	_check(not settings.set_value(Settings.VSYNC, 1), "vsync with an int")
	_check(not settings.set_value(Settings.VSYNC, "true"), "vsync with a String")
	_check(not settings.set_value(Settings.VOLUME_MASTER, "loud"), "volume with a String")
	_check(not settings.set_value(Settings.VOLUME_MASTER, NAN), "volume with NaN")
	_check(not settings.set_value(Settings.VOLUME_MASTER, null), "volume with null")
	_check_equal(settings.get_value(Settings.WINDOW_MODE), &"fullscreen", "window mode unchanged")
	_check_equal(settings.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "window size unchanged")
	_check_equal(settings.get_value(Settings.VSYNC), true, "vsync unchanged")
	_check_float(settings.get_value(Settings.VOLUME_MASTER), 1.0, "master unchanged")
	_check_equal(_received.size(), 0, "changed count")
	settings._process(10.0)
	_check_equal(settings.write_count, 0, "no save is scheduled")


func _test_volume_clamp() -> void:
	var settings: Node = _make()
	_check(settings.set_value(Settings.VOLUME_MUSIC, 1.5), "above the range")
	_check_float(settings.get_value(Settings.VOLUME_MUSIC), 1.0, "clamped to 1.0")
	_check(settings.set_value(Settings.VOLUME_MUSIC, -0.2), "below the range")
	_check_float(settings.get_value(Settings.VOLUME_MUSIC), 0.0, "clamped to 0.0")
	_check(settings.set_value(Settings.VOLUME_MUSIC, 1), "int value")
	_check_float(settings.get_value(Settings.VOLUME_MUSIC), 1.0, "int kept as float")
	_check_equal(_received.size(), 3, "changed count")


func _test_reset_to_defaults() -> void:
	var settings: Node = _make()
	settings.set_value(Settings.WINDOW_MODE, &"windowed")
	settings.set_value(Settings.WINDOW_SIZE, Vector2i(1280, 720))
	settings.set_value(Settings.VOLUME_MUSIC, 0.1)
	_received.clear()
	settings.reset_to_defaults()
	_check_equal(settings.get_value(Settings.WINDOW_MODE), &"fullscreen", "window mode")
	_check_equal(settings.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "window size")
	_check_equal(settings.get_value(Settings.VSYNC), true, "vsync")
	_check_float(settings.get_value(Settings.VOLUME_MASTER), 1.0, "master")
	_check_float(settings.get_value(Settings.VOLUME_MUSIC), 0.8, "music")
	_check_float(settings.get_value(Settings.VOLUME_SFX), 1.0, "sfx")
	var expected: Array[StringName] = [Settings.WINDOW_MODE, Settings.WINDOW_SIZE, Settings.VOLUME_MUSIC]
	_check_equal(_received, expected, "changed only for the keys that changed")
	_check_float(AudioServer.get_bus_volume_db(_bus_index(&"Music")), linear_to_db(0.8), "music bus after reset")
	settings.flush()
	_check_equal(settings.write_count, 1, "reset schedules a save")
	_received.clear()
	settings.reset_to_defaults()
	_check_equal(_received.size(), 0, "second reset changes nothing")
	settings.flush()
	_check_equal(settings.write_count, 1, "second reset schedules nothing")


func _test_save_and_reload() -> void:
	var first: Node = _make()
	first.set_value(Settings.WINDOW_MODE, &"windowed")
	first.set_value(Settings.WINDOW_SIZE, Vector2i(1280, 720))
	first.set_value(Settings.VSYNC, false)
	first.set_value(Settings.VOLUME_MASTER, 0.6)
	first.set_value(Settings.VOLUME_MUSIC, 0.0)
	first.set_value(Settings.VOLUME_SFX, 0.35)
	first.flush()
	_discard(first)
	_received.clear()
	var second: Node = _make()
	_check_equal(second.get_value(Settings.WINDOW_MODE), &"windowed", "window mode")
	_check_equal(second.get_value(Settings.WINDOW_SIZE), Vector2i(1280, 720), "window size")
	_check_equal(second.get_value(Settings.VSYNC), false, "vsync")
	_check_float(second.get_value(Settings.VOLUME_MASTER), 0.6, "master")
	_check_float(second.get_value(Settings.VOLUME_MUSIC), 0.0, "music")
	_check_float(second.get_value(Settings.VOLUME_SFX), 0.35, "sfx")
	_check_equal(second.write_count, 0, "loading does not write")
	# Loaded values are applied on start.
	_check_float(AudioServer.get_bus_volume_db(_bus_index(&"Master")), linear_to_db(0.6), "master bus after load")
	_check(AudioServer.is_bus_mute(_bus_index(&"Music")), "music bus muted after load")
	_check_float(AudioServer.get_bus_volume_db(_bus_index(&"SFX")), linear_to_db(0.35), "sfx bus after load")


func _test_file_format() -> void:
	var settings: Node = _make()
	settings.set_value(Settings.VOLUME_SFX, 0.5)
	settings.flush()
	var config: ConfigFile = ConfigFile.new()
	_check_equal(config.load(TEST_PATH), OK, "file can be read")
	_check(config.has_section_key("meta", "version"), "format version is present")
	_check_equal(typeof(config.get_value("meta", "version", null)), TYPE_INT, "format version type")
	_check_equal(config.get_value("graphics", "window_mode", null), "fullscreen", "stored window mode")
	_check_equal(config.get_value("graphics", "window_size", null), Vector2i(1600, 900), "stored window size")
	_check_equal(config.get_value("graphics", "vsync", null), true, "stored vsync")
	_check_float(config.get_value("audio", "volume_sfx", null), 0.5, "stored sfx")


func _test_broken_file() -> void:
	_write_text("this is [not a settings file\n=== 12 ::\n\u0001\u0002")
	var settings: Node = _make()
	_check_equal(settings.get_value(Settings.WINDOW_MODE), &"fullscreen", "window mode")
	_check_equal(settings.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "window size")
	_check_equal(settings.get_value(Settings.VSYNC), true, "vsync")
	_check_float(settings.get_value(Settings.VOLUME_MUSIC), 0.8, "music")
	_check(settings.set_value(Settings.VOLUME_MUSIC, 0.4), "still usable after a broken file")


func _test_bad_entries() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("meta", "version", 1)
	config.set_value("graphics", "window_mode", 123)                # wrong type
	config.set_value("graphics", "window_size", Vector2i(800, 600)) # not in the list
	config.set_value("graphics", "vsync", false)                    # valid
	config.set_value("graphics", "shadow_quality", "ultra")         # unknown key
	config.set_value("audio", "volume_master", "loud")              # wrong type
	config.set_value("audio", "volume_music", 7.0)                  # out of range
	config.set_value("audio", "volume_sfx", 0.3)                    # valid
	config.set_value("gameplay", "difficulty", 3)                   # unknown section
	config.save(TEST_PATH)
	var settings: Node = _make()
	_check_equal(settings.get_value(Settings.WINDOW_MODE), &"fullscreen", "wrong type falls back")
	_check_equal(settings.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "unknown size falls back")
	_check_equal(settings.get_value(Settings.VSYNC), false, "valid vsync is kept")
	_check_float(settings.get_value(Settings.VOLUME_MASTER), 1.0, "wrong type volume falls back")
	_check_float(settings.get_value(Settings.VOLUME_MUSIC), 0.8, "out of range volume falls back")
	_check_float(settings.get_value(Settings.VOLUME_SFX), 0.3, "valid volume is kept")
	_check_equal(settings.get_value(&"graphics/shadow_quality"), null, "unknown key is ignored")


func _test_save_once() -> void:
	var settings: Node = _make()
	# A slider being dragged: ten changes, 0.1 s apart.
	for step: int in 10:
		settings.set_value(Settings.VOLUME_MASTER, 0.9 - 0.05 * float(step))
		settings._process(0.1)
	_check_equal(_received.size(), 10, "every change is applied and signalled")
	_check_float(AudioServer.get_bus_volume_db(_bus_index(&"Master")), linear_to_db(0.45), "last value is applied")
	_check_equal(settings.write_count, 0, "nothing is written while the value keeps changing")
	settings._process(0.3)
	_check_equal(settings.write_count, 0, "nothing is written 0.4 s after the last change")
	settings._process(0.15)
	_check_equal(settings.write_count, 1, "written once 0.55 s after the last change")
	settings._process(5.0)
	_check_equal(settings.write_count, 1, "not written again")
	var config: ConfigFile = ConfigFile.new()
	config.load(TEST_PATH)
	_check_float(config.get_value("audio", "volume_master", null), 0.45, "the last value is stored")


func _test_flush() -> void:
	var settings: Node = _make()
	settings.flush()
	_check_equal(settings.write_count, 0, "flush without changes writes nothing")
	settings.set_value(Settings.VSYNC, false)
	_check_equal(settings.write_count, 0, "not written before flush")
	settings.flush()
	_check_equal(settings.write_count, 1, "flush writes at once")
	_check(FileAccess.file_exists(TEST_PATH), "file exists after flush")
	settings.flush()
	settings._process(5.0)
	_check_equal(settings.write_count, 1, "nothing left to write")


func _test_save_on_exit() -> void:
	var settings: Node = _make()
	settings.set_value(Settings.VOLUME_SFX, 0.2)
	settings.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	_check_equal(settings.write_count, 1, "close request writes the pending change")
	settings.set_value(Settings.VOLUME_SFX, 0.7)
	remove_child(settings)
	_check_equal(settings.write_count, 2, "leaving the tree writes the pending change")
	add_child(settings)
	var config: ConfigFile = ConfigFile.new()
	config.load(TEST_PATH)
	_check_float(config.get_value("audio", "volume_sfx", null), 0.7, "the last value is stored")


func _test_audio_buses() -> void:
	_check_equal(AudioServer.bus_count, 3, "bus count")
	_check_equal(AudioServer.get_bus_name(0), "Master", "bus 0")
	_check_equal(AudioServer.get_bus_name(1), "Music", "bus 1")
	_check_equal(AudioServer.get_bus_name(2), "SFX", "bus 2")
	_check_equal(AudioServer.get_bus_send(1), &"Master", "Music sends to Master")
	_check_equal(AudioServer.get_bus_send(2), &"Master", "SFX sends to Master")
	var settings: Node = _make()
	var master: int = _bus_index(&"Master")
	var music: int = _bus_index(&"Music")
	var sfx: int = _bus_index(&"SFX")
	# Defaults are applied on start.
	_check_float(AudioServer.get_bus_volume_db(master), linear_to_db(1.0), "master default")
	_check_float(AudioServer.get_bus_volume_db(music), linear_to_db(0.8), "music default")
	_check_float(AudioServer.get_bus_volume_db(sfx), linear_to_db(1.0), "sfx default")
	_check(not AudioServer.is_bus_mute(master), "master not muted")
	_check(not AudioServer.is_bus_mute(music), "music not muted")
	_check(not AudioServer.is_bus_mute(sfx), "sfx not muted")
	settings.set_value(Settings.VOLUME_MASTER, 0.5)
	_check_float(AudioServer.get_bus_volume_db(master), linear_to_db(0.5), "master at 0.5")
	_check(not AudioServer.is_bus_mute(master), "master not muted at 0.5")
	settings.set_value(Settings.VOLUME_MUSIC, 0.0)
	_check(AudioServer.is_bus_mute(music), "music muted at 0.0")
	_check(not AudioServer.is_bus_mute(sfx), "sfx unaffected")
	settings.set_value(Settings.VOLUME_MUSIC, 0.25)
	_check(not AudioServer.is_bus_mute(music), "music unmuted at 0.25")
	_check_float(AudioServer.get_bus_volume_db(music), linear_to_db(0.25), "music at 0.25")
	settings.set_value(Settings.VOLUME_SFX, -3.0)
	_check(AudioServer.is_bus_mute(sfx), "sfx muted when clamped to 0.0")


func _test_window_size_options() -> void:
	var full_hd: Node = _make(Vector2i(1920, 1080))
	_check_equal(full_hd.get_options(Settings.WINDOW_SIZE), [Vector2i(1280, 720), Vector2i(1600, 900)], "1920x1080 monitor")
	_check_equal(full_hd.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "1920x1080 monitor value")
	_discard(full_hd)

	var qhd: Node = _make(Vector2i(2560, 1440))
	_check_equal(qhd.get_options(Settings.WINDOW_SIZE),
		[Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)], "2560x1440 monitor")
	_check(qhd.set_value(Settings.WINDOW_SIZE, Vector2i(1920, 1080)), "1920x1080 is allowed on 2560x1440")
	qhd.flush()
	_discard(qhd)

	# The stored 1920x1080 cannot be used on a 1920x1080 monitor. The mode is
	# fullscreen, so the kept size is left alone (docs/roles/leader/outputs/11 design, 1.1).
	# Before 11 it was replaced by 1600x900 on start.
	var after_move: Node = _make(Vector2i(1920, 1080))
	_check_equal(after_move.get_value(Settings.WINDOW_SIZE), Vector2i(1920, 1080), "stored size kept in fullscreen")
	_check_equal(after_move.write_count, 0, "loading does not write")
	_discard(after_move)
	_remove_test_file()

	# The default 1600x900 cannot be used on a 1600x900 monitor. In fullscreen
	# it is kept all the same. Before 11 it was replaced by 1280x720 on start
	# and by reset_to_defaults.
	var small: Node = _make(Vector2i(1600, 900))
	_check_equal(small.get_options(Settings.WINDOW_SIZE), [Vector2i(1280, 720)], "1600x900 monitor")
	_check_equal(small.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "default kept in fullscreen")
	small.set_value(Settings.VOLUME_SFX, 0.5)
	small.reset_to_defaults()
	_check_equal(small.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "reset gives the default size")
	_discard(small)

	# Wider but not taller than a listed size: both sides must be smaller.
	var wide: Node = _make(Vector2i(2560, 900))
	_check_equal(wide.get_options(Settings.WINDOW_SIZE), [Vector2i(1280, 720)], "2560x900 monitor")
	_discard(wide)

	# No usable size at all. What follows from that is checked in _test_no_usable_size.
	var tiny: Node = _make(Vector2i(1280, 720))
	_check_equal(tiny.get_options(Settings.WINDOW_SIZE), [], "1280x720 monitor")
	_discard(tiny)


## docs/roles/leader/outputs/11 design, 1.1: starting in fullscreen changes nothing and saves nothing.
func _test_fullscreen_start_keeps_size() -> void:
	# No settings file, a monitor that cannot use the default 1600x900.
	for screen_size: Vector2i in [Vector2i(1600, 900), Vector2i(1366, 768), Vector2i(1280, 720)]:
		var tag: String = "%dx%d" % [screen_size.x, screen_size.y]
		_received.clear()
		var settings: Node = _make(screen_size)
		_check_equal(settings.get_value(Settings.WINDOW_MODE), &"fullscreen", "%s: starts in fullscreen" % tag)
		_check_equal(settings.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "%s: the kept size is the default" % tag)
		_check_equal(_received.size(), 0, "%s: no changed on start" % tag)
		_check_equal(settings.write_count, 0, "%s: nothing written on start" % tag)
		settings._process(0.6)
		settings._process(10.0)
		_check_equal(settings.write_count, 0, "%s: nothing written as time passes" % tag)
		_check(not FileAccess.file_exists(TEST_PATH), "%s: no settings file appears" % tag)
		settings.flush()
		settings.notification(NOTIFICATION_WM_CLOSE_REQUEST)
		_check_equal(settings.write_count, 0, "%s: nothing written by flush or on close" % tag)
		_discard(settings)
		_check(not FileAccess.file_exists(TEST_PATH), "%s: no settings file after the manager is gone" % tag)

	# The same monitor, then the player chooses windowed: now the size is replaced.
	_received.clear()
	var chosen: Node = _make(Vector2i(1600, 900))
	_check_equal(chosen.get_options(Settings.WINDOW_SIZE), [Vector2i(1280, 720)], "1600x900 monitor sizes")
	_check(chosen.set_value(Settings.WINDOW_MODE, &"windowed"), "windowed accepted")
	_check_equal(chosen.get_value(Settings.WINDOW_SIZE), Vector2i(1280, 720), "largest usable size is kept")
	var expected: Array[StringName] = [Settings.WINDOW_MODE, Settings.WINDOW_SIZE]
	_check_equal(_received, expected, "changed for the mode and for the replaced size")
	_check_equal(chosen.write_count, 0, "not written at once")
	chosen._process(0.6)
	_check_equal(chosen.write_count, 1, "a save was scheduled")
	_check_equal(_stored("graphics", "window_size"), Vector2i(1280, 720), "the replaced size is stored")
	_discard(chosen)
	_remove_test_file()

	# A settings file with fullscreen and a size that does not fit: left as it is.
	_write_settings_file("fullscreen", Vector2i(1920, 1080))
	var file_before: String = Isolation.file_state(TEST_PATH)
	_received.clear()
	var stored: Node = _make(Vector2i(1600, 900))
	_check_equal(stored.get_value(Settings.WINDOW_SIZE), Vector2i(1920, 1080), "the stored size is kept")
	_check_equal(_received.size(), 0, "no changed on start with a stored size")
	stored._process(10.0)
	_check_equal(stored.write_count, 0, "the file is not rewritten")
	_discard(stored)
	_check_equal(Isolation.file_state(TEST_PATH), file_before, "the settings file is unchanged")
	_remove_test_file()

	# reset_to_defaults in fullscreen with nothing changed: nothing happens.
	_received.clear()
	var untouched: Node = _make(Vector2i(1600, 900))
	untouched.reset_to_defaults()
	_check_equal(_received.size(), 0, "reset with defaults changes nothing")
	untouched._process(10.0)
	_check_equal(untouched.write_count, 0, "reset with defaults saves nothing")


func _write_settings_file(window_mode: String, window_size: Vector2i) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("meta", "version", 1)
	config.set_value("graphics", "window_mode", window_mode)
	config.set_value("graphics", "window_size", window_size)
	config.save(TEST_PATH)


func _stored(section: String, entry: String) -> Variant:
	var config: ConfigFile = ConfigFile.new()
	config.load(TEST_PATH)
	return config.get_value(section, entry, null)


## docs/roles/leader/outputs/09 design, section 2.
func _test_no_usable_size() -> void:
	var tiny: Node = _make(Vector2i(1280, 720))
	_check_equal(tiny.get_options(Settings.WINDOW_SIZE), [], "no usable size")
	_check_equal(tiny.get_options(Settings.WINDOW_MODE), [&"fullscreen"], "only fullscreen can be chosen")
	_received.clear()
	_check(not tiny.set_value(Settings.WINDOW_MODE, &"windowed"), "windowed is refused")
	_check(not tiny.set_value(Settings.WINDOW_MODE, "windowed"), "windowed as a String is refused")
	_check(not tiny.set_value(Settings.WINDOW_SIZE, Vector2i(1280, 720)), "a window size is refused")
	_check_equal(tiny.get_value(Settings.WINDOW_MODE), &"fullscreen", "window mode unchanged")
	_check_equal(tiny.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "window size unchanged")
	_check_equal(_received.size(), 0, "changed count")
	tiny._process(10.0)
	_check_equal(tiny.write_count, 0, "no save is scheduled")
	_check(tiny.set_value(Settings.WINDOW_MODE, &"fullscreen"), "fullscreen is still accepted")
	_check(tiny.set_value(Settings.VSYNC, false), "other settings still work")
	_discard(tiny)
	_remove_test_file()

	# Windowed mode stored in the file, but no size fits: start in fullscreen.
	_write_settings_file("windowed", Vector2i(1280, 720))
	_received.clear()
	var stored_windowed: Node = _make(Vector2i(1280, 720))
	_check_equal(stored_windowed.get_value(Settings.WINDOW_MODE), &"fullscreen", "starts in fullscreen")
	_check_equal(stored_windowed.get_options(Settings.WINDOW_MODE), [&"fullscreen"], "only fullscreen on start")
	_check_equal(_received.size(), 0, "no changed on start")
	stored_windowed._process(10.0)
	_check_equal(stored_windowed.write_count, 0, "the file is not rewritten on start")
	_check_equal(_stored("graphics", "window_mode"), "windowed", "the file still holds windowed")
	_discard(stored_windowed)

	# The same file on a monitor where a size fits: windowed is used again.
	var back_on_large: Node = _make(Vector2i(1920, 1080))
	_check_equal(back_on_large.get_value(Settings.WINDOW_MODE), &"windowed", "windowed again on a larger monitor")
	_check_equal(back_on_large.get_value(Settings.WINDOW_SIZE), Vector2i(1280, 720), "stored size is used")
	_discard(back_on_large)
	_remove_test_file()

	# The limits: both sides of the monitor must be larger than the smallest size.
	for screen_size: Vector2i in [Vector2i(1280, 800), Vector2i(1366, 720), Vector2i(1024, 768)]:
		var none: Node = _make(screen_size)
		_check_equal(none.get_options(Settings.WINDOW_MODE), [&"fullscreen"], "fullscreen only on %s" % str(screen_size))
		_check(not none.set_value(Settings.WINDOW_MODE, &"windowed"), "windowed refused on %s" % str(screen_size))
		_discard(none)
	var just_enough: Node = _make(Vector2i(1366, 768))
	_check_equal(just_enough.get_options(Settings.WINDOW_SIZE), [Vector2i(1280, 720)], "1366x768 monitor sizes")
	_check_equal(just_enough.get_options(Settings.WINDOW_MODE), [&"fullscreen", &"windowed"], "1366x768 monitor modes")
	_check(just_enough.set_value(Settings.WINDOW_MODE, &"windowed"), "windowed accepted on 1366x768")
	_check_equal(just_enough.get_value(Settings.WINDOW_SIZE), Vector2i(1280, 720), "1366x768 monitor size")


## docs/roles/leader/outputs/09 design, section 3.
func _test_size_replaced_when_windowed() -> void:
	# While running: the window was moved to a smaller monitor, then windowed is chosen.
	var settings: Node = _make(Vector2i(2560, 1440))
	_check(settings.set_value(Settings.WINDOW_SIZE, Vector2i(1920, 1080)), "1920x1080 kept on 2560x1440")
	settings.flush()
	_check_equal(settings.write_count, 1, "written once before the move")
	settings.test_screen_size = Vector2i(1920, 1080)
	_received.clear()
	_check(settings.set_value(Settings.WINDOW_MODE, &"windowed"), "windowed accepted after the move")
	_check_equal(settings.get_value(Settings.WINDOW_MODE), &"windowed", "window mode")
	_check_equal(settings.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "largest usable size is kept")
	var expected: Array[StringName] = [Settings.WINDOW_MODE, Settings.WINDOW_SIZE]
	_check_equal(_received, expected, "changed for the mode and for the replaced size")
	_check_equal(settings.write_count, 1, "not written at once")
	settings._process(0.6)
	_check_equal(settings.write_count, 2, "a save was scheduled")
	_check_equal(_stored("graphics", "window_size"), Vector2i(1600, 900), "the replaced size is stored")
	_check_equal(_stored("graphics", "window_mode"), "windowed", "windowed is stored")

	# Going to fullscreen does not replace the kept size; going back to windowed does.
	settings.test_screen_size = Vector2i(2560, 1440)
	settings.set_value(Settings.WINDOW_SIZE, Vector2i(1920, 1080))
	settings.test_screen_size = Vector2i(1600, 900)
	_received.clear()
	_check(settings.set_value(Settings.WINDOW_MODE, &"fullscreen"), "fullscreen accepted")
	_check_equal(settings.get_value(Settings.WINDOW_SIZE), Vector2i(1920, 1080), "size untouched by fullscreen")
	var only_mode: Array[StringName] = [Settings.WINDOW_MODE]
	_check_equal(_received, only_mode, "changed only for the mode")
	_received.clear()
	_check(settings.set_value(Settings.WINDOW_MODE, &"windowed"), "windowed accepted on 1600x900")
	_check_equal(settings.get_value(Settings.WINDOW_SIZE), Vector2i(1280, 720), "replaced when windowed is applied")
	_check_equal(_received, expected, "changed for both again")
	_discard(settings)
	_remove_test_file()

	# A size that still fits is left alone.
	var fits: Node = _make(Vector2i(1920, 1080))
	_received.clear()
	_check(fits.set_value(Settings.WINDOW_MODE, &"windowed"), "windowed accepted")
	_check_equal(fits.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "fitting size kept")
	_check_equal(_received, only_mode, "changed only for the mode when the size fits")
	_discard(fits)
	_remove_test_file()

	# On start: windowed with a size this monitor cannot use.
	_write_settings_file("windowed", Vector2i(1920, 1080))
	_received.clear()
	var on_start: Node = _make(Vector2i(1920, 1080))
	_check_equal(on_start.get_value(Settings.WINDOW_MODE), &"windowed", "still windowed on start")
	_check_equal(on_start.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "replaced on start")
	var only_size: Array[StringName] = [Settings.WINDOW_SIZE]
	_check_equal(_received, only_size, "changed for the replaced size on start")
	_check_equal(on_start.write_count, 0, "not written at once on start")
	on_start._process(0.6)
	_check_equal(on_start.write_count, 1, "a save was scheduled on start")
	_check_equal(_stored("graphics", "window_size"), Vector2i(1600, 900), "the replaced size is stored after start")


## docs/roles/leader/outputs/09 design, section 5: a receiver may call set_value from inside changed.
func _test_reentrant_changed() -> void:
	var settings: Node = SettingsUnderTest.new()
	settings.test_storage_path = TEST_PATH
	settings.test_screen_size = Vector2i(2560, 1440)
	add_child(settings)
	_instances.append(settings)
	settings.changed.connect(_on_changed)
	settings.set_value(Settings.WINDOW_SIZE, Vector2i(1920, 1080))
	settings.flush()
	settings.test_screen_size = Vector2i(1920, 1080)
	_received.clear()
	_reentrant_target = settings
	_reentrant_seen.clear()
	settings.changed.connect(_on_changed_reentrant)
	_check(settings.set_value(Settings.WINDOW_MODE, &"windowed"), "set_value returns")
	settings.changed.disconnect(_on_changed_reentrant)
	_reentrant_target = null
	# The receiver saw the replaced size already when the mode change arrived.
	_check_equal(_reentrant_seen.size(), 3, "receiver was called three times, not endlessly")
	if _reentrant_seen.size() == 3:
		_check_equal(_reentrant_seen[0], [Settings.WINDOW_MODE, &"windowed", Vector2i(1600, 900)], "state seen on the mode change")
		_check_equal(_reentrant_seen[1], [Settings.VOLUME_SFX, &"windowed", Vector2i(1600, 900)], "state seen on the nested change")
		_check_equal(_reentrant_seen[2], [Settings.WINDOW_SIZE, &"windowed", Vector2i(1600, 900)], "state seen on the size change")
	_check_float(settings.get_value(Settings.VOLUME_SFX), 0.5, "the nested set_value took effect")
	_check_equal(settings.get_value(Settings.WINDOW_MODE), &"windowed", "window mode after")
	_check_equal(settings.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "window size after")
	settings._process(0.6)
	_check_equal(settings.write_count, 2, "one save for the whole change")
	_check_float(_stored("audio", "volume_sfx"), 0.5, "the nested change is stored")


func _on_changed_reentrant(key: StringName) -> void:
	_reentrant_seen.append([
		key, _reentrant_target.get_value(Settings.WINDOW_MODE), _reentrant_target.get_value(Settings.WINDOW_SIZE)])
	# What a settings screen does: push the value it just received back in.
	_reentrant_target.set_value(key, _reentrant_target.get_value(key))
	# And a receiver that changes another setting in response.
	if key == Settings.WINDOW_MODE:
		_reentrant_target.set_value(Settings.VOLUME_SFX, 0.5)


## docs/roles/leader/outputs/09 design, section 4.
func _test_get_options_table() -> void:
	var settings: Node = _make(Vector2i(1920, 1080))
	_check_equal(settings.get_options(Settings.WINDOW_MODE), [&"fullscreen", &"windowed"], "window mode")
	_check_equal(settings.get_options(Settings.WINDOW_SIZE), [Vector2i(1280, 720), Vector2i(1600, 900)], "window size")
	_check_equal(settings.get_options(Settings.VSYNC), [true, false], "vsync")
	_check_equal(settings.get_options(Settings.VOLUME_MASTER), [], "master volume")
	_check_equal(settings.get_options(Settings.VOLUME_MUSIC), [], "music volume")
	_check_equal(settings.get_options(Settings.VOLUME_SFX), [], "sfx volume")
	settings.test_screen_size = Vector2i(1280, 720)
	_check_equal(settings.get_options(Settings.WINDOW_MODE), [&"fullscreen"], "window mode without a usable size")
	_check_equal(settings.get_options(Settings.WINDOW_SIZE), [], "window size without a usable size")
	_check_equal(settings.get_options(Settings.VSYNC), [true, false], "vsync without a usable size")
	# The returned array is a copy: changing it does not change the manager.
	settings.test_screen_size = Vector2i(1920, 1080)
	settings.get_options(Settings.WINDOW_MODE).clear()
	_check_equal(settings.get_options(Settings.WINDOW_MODE), [&"fullscreen", &"windowed"], "options are not shared")
