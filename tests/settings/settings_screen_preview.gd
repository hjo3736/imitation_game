extends Node
## Preview of the settings screen in a real window (docs/roles/leader/outputs/08 work order,
## 3.5). Not a game screen and not registered as the main scene.
##
## The screen gets tests/settings/fake_settings.gd, so nothing is saved and no audio
## bus changes. This preview scene, not the settings screen, moves the real
## window: it applies the window mode and size of the fake settings object, so
## the two graphics controls can be tried by hand.
##
## Every run must name a test settings file (docs/roles/leader/outputs/11 design, section 3).
## The screen itself only talks to the fake, but the autoload Settings is
## created with every run. Without the argument the run does nothing and exits
## with 1.
##
## Run by hand:
##   godot --path . res://tests/settings/settings_screen_preview.tscn -- --settings-path=user://test_settings.cfg
##   F1 1600x900 (16:9)   F2 1440x900 (16:10)   F3 1680x720 (21:9)
##   F4 1280x720          F11 fullscreen        Esc or "닫기" quits
##
## Run the automatic check (window sizes one after another, a picture of each):
##   godot --path . res://tests/settings/settings_screen_preview.tscn -- --settings-path=user://test_settings.cfg --capture=<folder>
## Exit code 0 means every size had the expected visible area and no layout
## problem. The pictures are written to <folder>.

const SCREEN_SCENE: PackedScene = preload("res://scenes/settings/settings_screen.tscn")
const FakeSettings: GDScript = preload("res://tests/settings/fake_settings.gd")
const LayoutCheck: GDScript = preload("res://tests/common/layout_check.gd")
const Isolation: GDScript = preload("res://tests/common/settings_isolation.gd")

const SCENE_PATH: String = "res://tests/settings/settings_screen_preview.tscn"
const TAG: String = "preview"

# Preview-only values. All of them fit a 1920x1080 monitor.
const PREVIEW_SIZES: Array[Vector2i] = [
	Vector2i(1600, 900), Vector2i(1440, 900), Vector2i(1680, 720), Vector2i(1280, 720),
]
const PREVIEW_KEYS: Array[Key] = [KEY_F1, KEY_F2, KEY_F3, KEY_F4]
const CAPTURE_ARGUMENT: String = "--capture="
const SETTLE_FRAMES: int = 20
const BASE_SIZE: Vector2 = Vector2(1920.0, 1080.0)

var _fake: Node = null
var _screen: Control = null
var _capture_folder: String = ""
var _capture_failures: int = 0


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(CAPTURE_ARGUMENT):
			_capture_folder = argument.substr(CAPTURE_ARGUMENT.length())
	if not Isolation.begin(get_tree(), TAG, SCENE_PATH, false, "[--capture=<folder>]"):
		get_tree().quit(1)
		return

	_fake = FakeSettings.new()
	_fake.window_size_options = _sizes_smaller_than_screen()
	_fake.changed.connect(_on_fake_changed)

	_screen = SCREEN_SCENE.instantiate()
	_screen.set_settings(_fake)
	_screen.closed.connect(_on_screen_closed)
	add_child(_screen)

	if _capture_folder != "":
		_run_capture.call_deferred()


func _exit_tree() -> void:
	if _fake != null and is_instance_valid(_fake):
		if _fake.changed.is_connected(_on_fake_changed):
			_fake.changed.disconnect(_on_fake_changed)
		_fake.free()
		_fake = null


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


## Sizes from the fake's list that are smaller than the monitor in both
## directions (08 design 2.1).
func _sizes_smaller_than_screen() -> Array:
	var screen_size: Vector2i = DisplayServer.screen_get_size(get_window().current_screen)
	var sizes: Array = []
	for candidate: Vector2i in _fake.ALL_WINDOW_SIZES:
		if candidate.x < screen_size.x and candidate.y < screen_size.y:
			sizes.append(candidate)
	return sizes


func _set_windowed(window_size: Vector2i) -> void:
	var window: Window = get_window()
	if window.mode != Window.MODE_WINDOWED:
		# Leaving fullscreen restores a 1920x1080 window. On a 1920x1080
		# monitor that window fills the screen and the engine turns it into
		# exclusive fullscreen (seen in the 07 review and again here). Limiting
		# the size while the mode changes makes the restored window smaller
		# than the monitor, so it stays a window.
		window.max_size = window_size
		window.mode = Window.MODE_WINDOWED
		window.max_size = Vector2i.ZERO
	window.size = window_size
	var screen_index: int = window.current_screen
	var screen_position: Vector2i = DisplayServer.screen_get_position(screen_index)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen_index)
	window.position = screen_position + (screen_size - window_size) / 2


func _on_fake_changed(key: StringName) -> void:
	if key != _fake.WINDOW_MODE and key != _fake.WINDOW_SIZE:
		return
	if _fake.get_value(_fake.WINDOW_MODE) == &"windowed":
		_set_windowed(_fake.get_value(_fake.WINDOW_SIZE))
	else:
		get_window().mode = Window.MODE_FULLSCREEN


func _on_screen_closed() -> void:
	# The screen is a child here, so it frees itself; the preview ends the run.
	if _capture_folder == "":
		Isolation.finish(get_tree(), TAG)
		get_tree().quit()


# --- Automatic check ---------------------------------------------------------

func _run_capture() -> void:
	DirAccess.make_dir_recursive_absolute(_capture_folder)
	var window: Window = get_window()
	var screen_size: Vector2i = DisplayServer.screen_get_size(window.current_screen)
	print("[preview] monitor=%dx%d scale=%s" % [screen_size.x, screen_size.y, DisplayServer.screen_get_scale(window.current_screen)])
	print("[preview] size options given to the screen: %s" % [_fake.window_size_options])

	await _wait(SETTLE_FRAMES)
	await _capture("fullscreen", false)

	var reset_button: Button = _screen.get_node("%ResetButton")
	var cancel_button: Button = _screen.get_node("%ConfirmNoButton")
	var mode_option: OptionButton = _screen.get_node("%WindowModeOption")
	var size_option: OptionButton = _screen.get_node("%WindowSizeOption")
	_fake.change_from_outside(_fake.WINDOW_MODE, &"windowed")
	for window_size: Vector2i in PREVIEW_SIZES:
		_set_windowed(window_size)
		await _wait(SETTLE_FRAMES)
		var tag: String = "%dx%d" % [window_size.x, window_size.y]
		# Ask the display server, not the Window node: the node can report a
		# size that the real window does not have.
		var real_size: Vector2i = DisplayServer.window_get_size()
		var real_mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
		if real_size != window_size or real_mode != DisplayServer.WINDOW_MODE_WINDOWED:
			_capture_failures += 1
			print("[preview] FAIL %s: the real window is %dx%d mode=%d" % [tag, real_size.x, real_size.y, real_mode])
		await _capture(tag, false)
		reset_button.pressed.emit()
		await _wait(3)
		await _capture(tag + "_confirm", true)
		cancel_button.pressed.emit()
		await _wait(3)

	# Open lists at the smallest window, to see their text.
	mode_option.show_popup()
	await _wait(3)
	await _capture("1280x720_mode_list", false)
	mode_option.get_popup().hide()
	size_option.show_popup()
	await _wait(3)
	await _capture("1280x720_size_list", false)
	size_option.get_popup().hide()

	if not Isolation.finish(get_tree(), TAG):
		_capture_failures += 1
		print("[preview] FAIL settings: the player's settings file changed or the test settings file is still there")
	print("[preview] %s" % ("PASSED" if _capture_failures == 0 else "FAILED: %d problem(s)" % _capture_failures))
	get_tree().quit(0 if _capture_failures == 0 else 1)


func _capture(tag: String, confirm_open: bool) -> void:
	var window: Window = get_window()
	var visible: Vector2 = get_viewport().get_visible_rect().size
	var scale: float = minf(float(window.size.x) / BASE_SIZE.x, float(window.size.y) / BASE_SIZE.y)
	var expected: Vector2 = Vector2(window.size) / scale
	var panel: Control = _screen.get_node("%ConfirmPanel" if confirm_open else "%Panel")
	var problems: PackedStringArray = LayoutCheck.find_layout_problems(panel)
	var safe: Rect2 = LayoutCheck.safe_rect(get_viewport())
	var real_size: Vector2i = DisplayServer.window_get_size()
	print("[preview] %s window=%dx%d mode=%d visible=%s safe=%s %s=%s items=%d problems=%d" % [
		tag, real_size.x, real_size.y, DisplayServer.window_get_mode(), visible, safe,
		panel.name, panel.get_global_rect(), LayoutCheck.count_items(panel), problems.size(),
	])
	if visible.distance_to(expected) > 1.5:
		_capture_failures += 1
		print("[preview] FAIL %s: visible area %s, expected about %s" % [tag, visible, expected])
	for problem: String in problems:
		_capture_failures += 1
		print("[preview] FAIL %s: %s" % [tag, problem])

	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = _capture_folder.path_join("settings_%s.png" % tag)
	var error: Error = image.save_png(path)
	if error != OK:
		_capture_failures += 1
		print("[preview] FAIL %s: could not write %s (error %d)" % [tag, path, error])
	else:
		print("[preview] %s picture=%dx%d %s" % [tag, image.get_width(), image.get_height(), path])


func _wait(frames: int) -> void:
	for index: int in frames:
		await get_tree().process_frame
