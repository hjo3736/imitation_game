extends Node
## Preview of the title screen in a real window (docs/leader/10 work order,
## 3.6). Not a game screen and not registered as the main scene.
##
## This preview scene, not the title screen, moves the real window. It does so
## directly, without going through Settings, so nothing is saved.
##
## The settings screen opened from the menu uses the real autoload Settings.
## The automatic check below never changes a setting. When run by hand,
## changing a setting in the settings screen is saved to user://settings.cfg
## exactly as in the game.
##
## Run by hand:
##   godot --path . res://tests/ui/title_screen_preview.tscn
##   F1 1600x900 (16:9)   F2 1440x900 (16:10)   F3 1680x720 (21:9)
##   F4 1280x720          F11 fullscreen        "종료" quits
##
## Run the automatic check (window sizes one after another, a picture of each):
##   godot --path . res://tests/ui/title_screen_preview.tscn -- --capture=<folder>
## Exit code 0 means every size had the expected visible area and no layout
## problem, and no setting changed. The pictures are written to <folder>.

const TITLE_SCENE: PackedScene = preload("res://ui/title/title_screen.tscn")
const LayoutCheck: GDScript = preload("res://tests/ui/layout_check.gd")

# Preview-only values. All of them fit a 1920x1080 monitor.
const PREVIEW_SIZES: Array[Vector2i] = [
	Vector2i(1600, 900), Vector2i(1440, 900), Vector2i(1680, 720), Vector2i(1280, 720),
]
const PREVIEW_KEYS: Array[Key] = [KEY_F1, KEY_F2, KEY_F3, KEY_F4]
const OVERLAY_BUTTONS: Array[String] = ["SettingsButton", "CreditsButton", "NewGameButton"]
const CAPTURE_ARGUMENT: String = "--capture="
const SETTINGS_FILE: String = "user://settings.cfg"
const SETTLE_FRAMES: int = 20
const BASE_SIZE: Vector2 = Vector2(1920.0, 1080.0)

var _screen: Control = null
var _capture_folder: String = ""
var _capture_failures: int = 0


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(CAPTURE_ARGUMENT):
			_capture_folder = argument.substr(CAPTURE_ARGUMENT.length())
	_screen = TITLE_SCENE.instantiate()
	add_child(_screen)
	if _capture_folder != "":
		_run_capture.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var index: int = PREVIEW_KEYS.find(key_event.keycode)
	if index >= 0:
		get_viewport().set_input_as_handled()
		_set_windowed(PREVIEW_SIZES[index])
	elif key_event.keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		get_window().mode = Window.MODE_FULLSCREEN


func _set_windowed(window_size: Vector2i) -> void:
	var window: Window = get_window()
	if window.mode != Window.MODE_WINDOWED:
		# Leaving fullscreen on a monitor as large as the restored window ends
		# in exclusive fullscreen. Limiting the size while the mode changes
		# keeps it a window (same as app/settings.gd does).
		window.max_size = window_size
		window.mode = Window.MODE_WINDOWED
		window.max_size = Vector2i.ZERO
	window.size = window_size
	var screen_index: int = window.current_screen
	var screen_position: Vector2i = DisplayServer.screen_get_position(screen_index)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen_index)
	window.position = screen_position + (screen_size - window_size) / 2


# --- Automatic check ---------------------------------------------------------

func _run_capture() -> void:
	DirAccess.make_dir_recursive_absolute(_capture_folder)
	var settings: Node = get_node_or_null("/root/Settings")
	var file_before: String = _settings_file_state()
	var values_before: Dictionary = _settings_values(settings)
	var screen_size: Vector2i = DisplayServer.screen_get_size(get_window().current_screen)
	print("[preview] monitor=%dx%d  Settings present: %s  %s before: %s" % [
		screen_size.x, screen_size.y, settings != null, SETTINGS_FILE, file_before,
	])

	await _wait(SETTLE_FRAMES)
	await _capture_all("fullscreen")
	for window_size: Vector2i in PREVIEW_SIZES:
		_set_windowed(window_size)
		await _wait(SETTLE_FRAMES)
		var tag: String = "%dx%d" % [window_size.x, window_size.y]
		# Ask the display server, not the Window node: the node can report a
		# size that the real window does not have.
		var real_size: Vector2i = DisplayServer.window_get_size()
		var real_mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
		if real_size != window_size or real_mode != DisplayServer.WINDOW_MODE_WINDOWED:
			_fail(tag, "the real window is %dx%d mode=%d" % [real_size.x, real_size.y, real_mode])
		await _capture_all(tag)

	var focused: Control = get_viewport().gui_get_focus_owner()
	print("[preview] focus at the end: %s" % (String(focused.name) if focused != null else "(none)"))
	var file_after: String = _settings_file_state()
	print("[preview] %s after: %s" % [SETTINGS_FILE, file_after])
	if file_after != file_before:
		_fail("settings", "the settings file changed: %s -> %s" % [file_before, file_after])
	if _settings_values(settings) != values_before:
		_fail("settings", "a value of Settings changed")
	print("[preview] %s" % ("PASSED" if _capture_failures == 0 else "FAILED: %d problem(s)" % _capture_failures))
	get_tree().quit(0 if _capture_failures == 0 else 1)


## The title screen alone, then with each of the three windows over it.
func _capture_all(tag: String) -> void:
	await _capture(tag + "_title", _screen.get_node("%Content"))
	for button_name: String in OVERLAY_BUTTONS:
		(_screen.get_node("%" + button_name) as Button).pressed.emit()
		await _wait(3)
		var layer: Node = _screen.get_node("%OverlayLayer")
		if layer.get_child_count() != 1:
			_fail(tag, "%s opened %d windows" % [button_name, layer.get_child_count()])
			continue
		var overlay: Control = layer.get_child(0)
		await _capture("%s_%s" % [tag, button_name.trim_suffix("Button").to_snake_case()], overlay.get_node("%Panel"))
		overlay.call(&"close")
		await _wait(3)
		if layer.get_child_count() != 0:
			_fail(tag, "%s did not close" % button_name)


func _capture(tag: String, checked: Control) -> void:
	var visible: Vector2 = get_viewport().get_visible_rect().size
	var real_size: Vector2i = DisplayServer.window_get_size()
	var scale: float = minf(float(real_size.x) / BASE_SIZE.x, float(real_size.y) / BASE_SIZE.y)
	var expected: Vector2 = Vector2(real_size) / scale
	var problems: PackedStringArray = LayoutCheck.find_layout_problems(checked)
	var safe: Rect2 = LayoutCheck.safe_rect(get_viewport())
	print("[preview] %s window=%dx%d mode=%d visible=%s safe=%s %s=%s items=%d problems=%d" % [
		tag, real_size.x, real_size.y, DisplayServer.window_get_mode(), visible, safe,
		checked.name, checked.get_global_rect(), LayoutCheck.count_items(checked), problems.size(),
	])
	if visible.distance_to(expected) > 1.5:
		_fail(tag, "visible area %s, expected about %s" % [visible, expected])
	if checked.get_global_rect().get_center().distance_to(safe.get_center()) > 1.0:
		_fail(tag, "%s is not centered" % checked.name)
	for problem: String in problems:
		_fail(tag, problem)

	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = _capture_folder.path_join("title_%s.png" % tag)
	var error: Error = image.save_png(path)
	if error != OK:
		_fail(tag, "could not write %s (error %d)" % [path, error])


func _fail(tag: String, what: String) -> void:
	_capture_failures += 1
	print("[preview] FAIL %s: %s" % [tag, what])


func _settings_values(settings: Node) -> Dictionary:
	var values: Dictionary = {}
	if settings == null:
		return values
	for constant_name: StringName in [&"WINDOW_MODE", &"WINDOW_SIZE", &"VSYNC", &"VOLUME_MASTER", &"VOLUME_MUSIC", &"VOLUME_SFX"]:
		values[constant_name] = settings.call(&"get_value", settings.get(constant_name))
	return values


func _settings_file_state() -> String:
	if not FileAccess.file_exists(SETTINGS_FILE):
		return "absent"
	return "md5=%s modified=%d" % [FileAccess.get_md5(SETTINGS_FILE), FileAccess.get_modified_time(SETTINGS_FILE)]


func _wait(frames: int) -> void:
	for index: int in frames:
		await get_tree().process_frame
