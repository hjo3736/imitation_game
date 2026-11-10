extends Node
## Headless tests for the settings manager (app/settings.gd).
## Run:  godot --headless --path . res://tests/app/settings_test.tscn
## Exit code 0 when every check passes, 1 otherwise.
## The tests use their own files under user:// and remove them afterwards.
## They never write user://settings.cfg.

const SettingsUnderTest: GDScript = preload("res://tests/app/settings_under_test.gd")

const REAL_SETTINGS_PATH: String = "user://settings.cfg"
const TEST_PATH: String = "user://settings_test_tmp.cfg"
const FLOAT_TOLERANCE: float = 0.0001

var _check_count: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _current_test: String = ""
var _received: Array[StringName] = []
var _instances: Array[Node] = []


func _ready() -> void:
	var real_file_existed: bool = FileAccess.file_exists(REAL_SETTINGS_PATH)
	var real_file_time: int = FileAccess.get_modified_time(REAL_SETTINGS_PATH) if real_file_existed else 0

	_run("contract", _test_contract)
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

	_current_test = "real_file_untouched"
	_check(FileAccess.file_exists(REAL_SETTINGS_PATH) == real_file_existed, "user://settings.cfg was created or removed")
	if real_file_existed:
		_check(FileAccess.get_modified_time(REAL_SETTINGS_PATH) == real_file_time, "user://settings.cfg was modified")
	_check(not FileAccess.file_exists(TEST_PATH), "test file was left behind")

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
	add_child(settings)
	settings.changed.connect(_on_changed)
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
	for method: String in ["get_value", "set_value", "get_options", "get_default", "reset_to_defaults", "flush"]:
		_check(Settings.has_method(method), "method %s is missing" % method)


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

	# The stored 1920x1080 cannot be used on a 1920x1080 monitor: largest usable size instead.
	var after_move: Node = _make(Vector2i(1920, 1080))
	_check_equal(after_move.get_value(Settings.WINDOW_SIZE), Vector2i(1600, 900), "stored size replaced")
	_check_equal(after_move.write_count, 0, "replacing on load does not write")
	_discard(after_move)
	_remove_test_file()

	# The default 1600x900 cannot be used on a 1600x900 monitor.
	var small: Node = _make(Vector2i(1600, 900))
	_check_equal(small.get_options(Settings.WINDOW_SIZE), [Vector2i(1280, 720)], "1600x900 monitor")
	_check_equal(small.get_value(Settings.WINDOW_SIZE), Vector2i(1280, 720), "default replaced")
	small.set_value(Settings.VOLUME_SFX, 0.5)
	small.reset_to_defaults()
	_check_equal(small.get_value(Settings.WINDOW_SIZE), Vector2i(1280, 720), "reset keeps a usable size")
	_discard(small)

	# Wider but not taller than a listed size: both sides must be smaller.
	var wide: Node = _make(Vector2i(2560, 900))
	_check_equal(wide.get_options(Settings.WINDOW_SIZE), [Vector2i(1280, 720)], "2560x900 monitor")
	_discard(wide)

	# No usable size at all. The behaviour is not decided yet; only check that nothing breaks.
	var tiny: Node = _make(Vector2i(1280, 720))
	_check_equal(tiny.get_options(Settings.WINDOW_SIZE), [], "1280x720 monitor")
	_check(tiny.set_value(Settings.WINDOW_MODE, &"windowed"), "window mode can still be set")
	_discard(tiny)
