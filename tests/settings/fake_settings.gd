extends Node
## Test-only settings object for the settings screen.
##
## Follows the contract in docs/leader/08 design, section 4, but only keeps the
## values. It never touches the window, the audio buses or any file. The real
## settings manager is scripts/settings/settings.gd (worker-01). Nothing under ui/ may depend
## on this script.

signal changed(key: StringName)

const WINDOW_MODE: StringName = &"graphics/window_mode"
const WINDOW_SIZE: StringName = &"graphics/window_size"
const VSYNC: StringName = &"graphics/vsync"
const VOLUME_MASTER: StringName = &"audio/volume_master"
const VOLUME_MUSIC: StringName = &"audio/volume_music"
const VOLUME_SFX: StringName = &"audio/volume_sfx"

# Options and defaults from docs/leader/08 design, section 2.
const WINDOW_MODES: Array[StringName] = [&"fullscreen", &"windowed"]
const ALL_WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
]
const DEFAULTS: Dictionary = {
	WINDOW_MODE: &"fullscreen",
	WINDOW_SIZE: Vector2i(1600, 900),
	VSYNC: true,
	VOLUME_MASTER: 1.0,
	VOLUME_MUSIC: 0.8,
	VOLUME_SFX: 1.0,
}

# --- Test hooks (not part of the contract) -----------------------------------
## Window sizes that get_options(WINDOW_SIZE) returns. Tests may replace it.
var window_size_options: Array = [Vector2i(1280, 720), Vector2i(1600, 900)]
## Every set_value call as [key, value], in order.
var set_calls: Array = []
var flush_count: int = 0
var reset_count: int = 0

var _values: Dictionary = DEFAULTS.duplicate()


func get_value(key: StringName) -> Variant:
	return _values.get(key)


func set_value(key: StringName, value: Variant) -> bool:
	set_calls.append([key, value])
	return _store(key, value)


func get_options(key: StringName) -> Array:
	if key == WINDOW_MODE:
		return WINDOW_MODES.duplicate()
	if key == WINDOW_SIZE:
		return window_size_options.duplicate()
	return []


func get_default(key: StringName) -> Variant:
	return DEFAULTS.get(key)


func reset_to_defaults() -> void:
	reset_count += 1
	for key: StringName in DEFAULTS:
		_store(key, DEFAULTS[key])


func flush() -> void:
	flush_count += 1


## Test hook: changes a value the way some other part of the game would,
## without recording it in set_calls.
func change_from_outside(key: StringName, value: Variant) -> bool:
	return _store(key, value)


func _store(key: StringName, value: Variant) -> bool:
	if not _values.has(key):
		return false
	var accepted: Variant = null
	if key == WINDOW_MODE:
		if not (value is StringName or value is String) or not WINDOW_MODES.has(StringName(value)):
			return false
		accepted = StringName(value)
	elif key == WINDOW_SIZE:
		if not value is Vector2i or not window_size_options.has(value):
			return false
		accepted = value
	elif key == VSYNC:
		if not value is bool:
			return false
		accepted = value
	else:
		if not (value is float or value is int):
			return false
		accepted = clampf(float(value), 0.0, 1.0)
	if _values[key] == accepted:
		return true
	_values[key] = accepted
	changed.emit(key)
	return true
