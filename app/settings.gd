extends Node
## Settings manager. Registered as the autoload "Settings".
## Keeps the setting values, applies them to the window and the audio buses,
## and stores them in a file. Contract: docs/leader/08 design, section 4.
## This node never keeps a reference to a screen node.

# --- Contract (docs/leader/08 design, section 4). Do not change. --------------
signal changed(key: StringName)

const WINDOW_MODE: StringName = &"graphics/window_mode"
const WINDOW_SIZE: StringName = &"graphics/window_size"
const VSYNC: StringName = &"graphics/vsync"
const VOLUME_MASTER: StringName = &"audio/volume_master"
const VOLUME_MUSIC: StringName = &"audio/volume_music"
const VOLUME_SFX: StringName = &"audio/volume_sfx"

# --- Confirmed values (docs/leader/08 design, section 2) ----------------------
const _MODE_FULLSCREEN: StringName = &"fullscreen"
const _MODE_WINDOWED: StringName = &"windowed"
const _WINDOW_MODES: Array[StringName] = [_MODE_FULLSCREEN, _MODE_WINDOWED]
## Ascending order: the last usable entry is the largest usable size.
const _WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const _MIN_WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
const _VOLUME_MIN: float = 0.0
const _VOLUME_MAX: float = 1.0
const _DEFAULTS: Dictionary = {
	WINDOW_MODE: _MODE_FULLSCREEN,
	WINDOW_SIZE: Vector2i(1600, 900),
	VSYNC: true,
	VOLUME_MASTER: 1.0,
	VOLUME_MUSIC: 0.8,
	VOLUME_SFX: 1.0,
}
const _BUS_NAMES: Dictionary = {
	VOLUME_MASTER: &"Master",
	VOLUME_MUSIC: &"Music",
	VOLUME_SFX: &"SFX",
}
const _STORAGE_PATH: String = "user://settings.cfg"
const _SAVE_DELAY_SECONDS: float = 0.5

# --- File format --------------------------------------------------------------
const _FORMAT_VERSION: int = 1
const _META_SECTION: String = "meta"
const _VERSION_KEY: String = "version"

var _values: Dictionary = {}
var _save_pending: bool = false
var _save_time_left: float = 0.0


func _ready() -> void:
	# Saving must keep working while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_values = _DEFAULTS.duplicate()
	_load_file()
	_values[WINDOW_SIZE] = _usable_window_size(_values[WINDOW_SIZE])
	get_window().min_size = _MIN_WINDOW_SIZE
	_apply_all()


func _process(delta: float) -> void:
	if not _save_pending:
		return
	_save_time_left -= delta
	if _save_time_left <= 0.0:
		_write_file()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()


func _exit_tree() -> void:
	flush()


# --- Contract methods ---------------------------------------------------------

func get_value(key: StringName) -> Variant:
	return _values.get(key)


func set_value(key: StringName, value: Variant) -> bool:
	if not _DEFAULTS.has(key):
		return false
	var normalized: Variant = _normalize(key, value, false)
	if normalized == null:
		return false
	if _values[key] == normalized:
		return true
	_values[key] = normalized
	_apply(key)
	changed.emit(key)
	_schedule_save()
	return true


func get_options(key: StringName) -> Array:
	var options: Array = []
	if key == WINDOW_MODE:
		for mode: StringName in _WINDOW_MODES:
			options.append(mode)
	elif key == WINDOW_SIZE:
		var screen_size: Vector2i = _get_screen_size()
		for window_size: Vector2i in _WINDOW_SIZES:
			if window_size.x < screen_size.x and window_size.y < screen_size.y:
				options.append(window_size)
	elif key == VSYNC:
		options.append(true)
		options.append(false)
	return options


func get_default(key: StringName) -> Variant:
	return _DEFAULTS.get(key)


func reset_to_defaults() -> void:
	var changed_keys: Array[StringName] = []
	for key: StringName in _DEFAULTS:
		var target: Variant = _DEFAULTS[key]
		if key == WINDOW_SIZE:
			target = _usable_window_size(target)
		if _values[key] != target:
			_values[key] = target
			changed_keys.append(key)
	if changed_keys.is_empty():
		return
	# Window mode and window size are applied together, in one step.
	if changed_keys.has(WINDOW_MODE) or changed_keys.has(WINDOW_SIZE):
		_apply_window()
	for key: StringName in changed_keys:
		if key != WINDOW_MODE and key != WINDOW_SIZE:
			_apply(key)
	for key: StringName in changed_keys:
		changed.emit(key)
	_schedule_save()


func flush() -> void:
	if _save_pending:
		_write_file()


# --- Hooks that tests override ------------------------------------------------

func _get_storage_path() -> String:
	return _STORAGE_PATH


func _get_screen_size() -> Vector2i:
	return DisplayServer.screen_get_size(get_window().current_screen)


# --- Validation ---------------------------------------------------------------

## Returns the value to keep, or null when the value is not acceptable.
## A volume outside the range is clamped when it comes from set_value and
## rejected when it comes from the settings file.
func _normalize(key: StringName, value: Variant, from_file: bool) -> Variant:
	if key == WINDOW_MODE:
		if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
			return null
		var mode: StringName = StringName(value)
		if not _WINDOW_MODES.has(mode):
			return null
		return mode
	if key == WINDOW_SIZE:
		if typeof(value) != TYPE_VECTOR2I:
			return null
		var window_size: Vector2i = value
		if not _WINDOW_SIZES.has(window_size):
			return null
		# From the file any listed size is accepted here; _ready then replaces
		# a size this monitor cannot use.
		if not from_file and not get_options(WINDOW_SIZE).has(window_size):
			return null
		return window_size
	if key == VSYNC:
		if typeof(value) != TYPE_BOOL:
			return null
		return value
	if _BUS_NAMES.has(key):
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return null
		var volume: float = float(value)
		if is_nan(volume):
			return null
		if from_file and (volume < _VOLUME_MIN or volume > _VOLUME_MAX):
			return null
		return clampf(volume, _VOLUME_MIN, _VOLUME_MAX)
	return null


## The given size if this monitor can use it, otherwise the largest usable size.
## When no listed size is usable the given size is returned unchanged.
func _usable_window_size(window_size: Vector2i) -> Vector2i:
	var options: Array = get_options(WINDOW_SIZE)
	if options.is_empty() or options.has(window_size):
		return window_size
	return options.back()


# --- Applying -----------------------------------------------------------------

func _apply_all() -> void:
	_apply_window()
	_apply_vsync()
	for key: StringName in _BUS_NAMES:
		_apply_volume(key)


func _apply(key: StringName) -> void:
	if key == WINDOW_MODE or key == WINDOW_SIZE:
		_apply_window()
	elif key == VSYNC:
		_apply_vsync()
	elif _BUS_NAMES.has(key):
		_apply_volume(key)


## Applies window mode and window size together from the kept values.
## It never reads the current window size to decide what to do.
func _apply_window() -> void:
	var window: Window = get_window()
	if _values[WINDOW_MODE] == _MODE_FULLSCREEN:
		window.mode = Window.MODE_FULLSCREEN
		return
	var window_size: Vector2i = _values[WINDOW_SIZE]
	if not get_options(WINDOW_SIZE).has(window_size):
		# No listed size fits this monitor. What should happen here is not
		# decided yet (reported to the Leader); only the mode is changed.
		window.mode = Window.MODE_WINDOWED
		return
	# Leaving fullscreen restores a window as large as the monitor, which the
	# engine turns into exclusive fullscreen. Capping the size before the mode
	# change keeps the window from ever covering the monitor.
	window.max_size = window_size
	window.mode = Window.MODE_WINDOWED
	window.size = window_size
	window.max_size = Vector2i.ZERO
	window.move_to_center()


func _apply_vsync() -> void:
	var vsync_mode: DisplayServer.VSyncMode = DisplayServer.VSYNC_DISABLED
	if _values[VSYNC]:
		vsync_mode = DisplayServer.VSYNC_ENABLED
	DisplayServer.window_set_vsync_mode(vsync_mode)


func _apply_volume(key: StringName) -> void:
	var bus_name: StringName = _BUS_NAMES[key]
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		push_warning("Settings: audio bus '%s' does not exist." % bus_name)
		return
	var volume: float = _values[key]
	if volume <= _VOLUME_MIN:
		AudioServer.set_bus_mute(bus_index, true)
		return
	AudioServer.set_bus_mute(bus_index, false)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(volume))


# --- Settings file ------------------------------------------------------------

func _schedule_save() -> void:
	_save_pending = true
	_save_time_left = _SAVE_DELAY_SECONDS


func _load_file() -> void:
	var path: String = _get_storage_path()
	if not FileAccess.file_exists(path):
		return
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error != OK:
		push_warning("Settings: could not read '%s' (error %d). Using defaults." % [path, error])
		return
	for key: StringName in _DEFAULTS:
		var section: String = _section_of(key)
		var entry: String = _entry_of(key)
		if not config.has_section_key(section, entry):
			continue
		var normalized: Variant = _normalize(key, config.get_value(section, entry), true)
		if normalized == null:
			push_warning("Settings: invalid value for '%s' in '%s'. Using the default." % [key, path])
			continue
		_values[key] = normalized


func _write_file() -> void:
	_save_pending = false
	_save_time_left = 0.0
	var config: ConfigFile = ConfigFile.new()
	config.set_value(_META_SECTION, _VERSION_KEY, _FORMAT_VERSION)
	for key: StringName in _DEFAULTS:
		var value: Variant = _values[key]
		if typeof(value) == TYPE_STRING_NAME:
			value = String(value)
		config.set_value(_section_of(key), _entry_of(key), value)
	var path: String = _get_storage_path()
	var error: Error = config.save(path)
	if error != OK:
		push_warning("Settings: could not write '%s' (error %d)." % [path, error])


func _section_of(key: StringName) -> String:
	return String(key).get_slice("/", 0)


func _entry_of(key: StringName) -> String:
	return String(key).get_slice("/", 1)
