extends Node
## Preview of the whole flow of the screens in a real window (docs/leader/13
## work order, 3.8). Not a game screen and not registered as the main scene.
##
## The screen host gets tests/common/fake_game.gd, so no save file is read or
## written. The settings screen opened from the menus uses the real autoload
## Settings; every run must name a test settings file, and without the argument
## the run does nothing and exits with 1 (docs/roles/common.md, section 8).
## This preview scene, not the game, moves the real window, and it does so
## without going through Settings, so nothing is saved by that.
##
## Run by hand (the fake game runs its clock; --day-length is a test value):
##   godot --path . res://tests/main/game_flow_preview.tscn -- --settings-path=user://test_settings.cfg [--day-length=30]
##   F1 1600x900 (16:9)   F2 1440x900 (16:10)   F3 1680x720 (21:9)
##   F4 1280x720          F11 fullscreen        "종료" on the title screen quits
##
## Run the automatic check (every screen and panel at every window size, a
## picture of each; it takes a few seconds and then quits by itself):
##   godot --path . res://tests/main/game_flow_preview.tscn -- --settings-path=user://test_settings.cfg --capture=<folder>
## Exit code 0 means every size had the expected visible area and no layout
## problem, and no setting changed. The pictures are written to <folder>.

const MAIN_SCENE: PackedScene = preload("res://scenes/main/main.tscn")
const FakeGame: GDScript = preload("res://tests/common/fake_game.gd")
const LayoutCheck: GDScript = preload("res://tests/common/layout_check.gd")
const Isolation: GDScript = preload("res://tests/common/settings_isolation.gd")

const SCENE_PATH: String = "res://tests/main/game_flow_preview.tscn"
const TAG: String = "flow_preview"

# Preview-only values. All of them fit a 1920x1080 monitor.
const PREVIEW_SIZES: Array[Vector2i] = [
	Vector2i(1600, 900), Vector2i(1440, 900), Vector2i(1680, 720), Vector2i(1280, 720),
]
const PREVIEW_KEYS: Array[Key] = [KEY_F1, KEY_F2, KEY_F3, KEY_F4]
const CAPTURE_ARGUMENT: String = "--capture="
const DAY_LENGTH_ARGUMENT: String = "--day-length="
const SETTLE_FRAMES: int = 20
const STEP_FRAMES: int = 4
const BASE_SIZE: Vector2 = Vector2(1920.0, 1080.0)

var _game: Node = null
var _host: Control = null
var _capture_folder: String = ""
var _capture_failures: int = 0
var _pictures: int = 0


func _ready() -> void:
	var day_length: float = 0.0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(CAPTURE_ARGUMENT):
			_capture_folder = argument.substr(CAPTURE_ARGUMENT.length())
		elif argument.begins_with(DAY_LENGTH_ARGUMENT):
			day_length = argument.substr(DAY_LENGTH_ARGUMENT.length()).to_float()
	if not Isolation.begin(get_tree(), TAG, SCENE_PATH, false, "[--capture=<folder>] [--day-length=<seconds>]"):
		get_tree().quit(1)
		return
	_game = FakeGame.new()
	_game.name = "FakeGame"
	if day_length > 0.0:
		_game.test_day_length = day_length
	# By hand the fake game runs its clock like the real one. The automatic
	# check moves the clock itself.
	_game.auto_tick = _capture_folder == ""
	add_child(_game)
	_host = MAIN_SCENE.instantiate()
	_host.set_game(_game)
	add_child(_host)
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
		# keeps it a window (same as scripts/settings/settings.gd does).
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
	var values_before: Dictionary = _settings_values(settings)
	var screen_size: Vector2i = DisplayServer.screen_get_size(get_window().current_screen)
	print("[%s] monitor=%dx%d  Settings present: %s  game object: %s" % [
		TAG, screen_size.x, screen_size.y, settings != null, _game.get_script().resource_path])

	await _wait(SETTLE_FRAMES)
	await _capture_flow("fullscreen")
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
		await _capture_flow(tag)

	if not _game.blocked_reasons().is_empty():
		_fail("clock", "reasons to stop the clock are left: %s" % [_game.blocked_reasons()])
	if _settings_values(settings) != values_before:
		_fail("settings", "a value of Settings changed")
	# Nothing was changed, so Settings has nothing to save: no test settings
	# file may appear when it is told to write out what is waiting.
	settings.call(&"flush")
	if FileAccess.file_exists(settings.call(&"get_storage_path")):
		_fail("settings", "Settings saved something although no setting was changed")
	if not Isolation.finish(get_tree(), TAG):
		_fail("settings", "the player's settings file changed or the test settings file is still there")
	print("[%s] pictures=%d" % [TAG, _pictures])
	print("[%s] %s" % [TAG, "PASSED" if _capture_failures == 0 else "FAILED: %d problem(s)" % _capture_failures])
	get_tree().quit(0 if _capture_failures == 0 else 1)


## One walk through every screen and panel, starting and ending at the title
## screen: title, new game question, workshop, nameplate question, pause,
## settings over pause, day summary, and the notice for a save that cannot be
## read.
func _capture_flow(tag: String) -> void:
	_game.save_exists = true
	_game.continue_succeeds = true
	await _capture(tag + "_1_title", _screen().get_node("%Content"))

	_press(_screen().get_node("%NewGameButton"))
	await _wait(STEP_FRAMES)
	await _capture(tag + "_2_new_game_question", _host_overlay().get_node("%Panel"))
	_press(_host_overlay().get_node("%AcceptButton"))
	await _settle()
	_expect_kind(tag, &"workshop")
	_game.tick(187.9)
	await _wait(STEP_FRAMES)
	await _capture(tag + "_3_workshop", _screen().get_node("%Content"))

	_press(_screen().get_node("%NameplateButton"))
	await _wait(STEP_FRAMES)
	var question: Control = _screen_overlay()
	await _capture(tag + "_4_nameplate_question", question.get_node("%Panel"))
	_press(question.get_node("%CloseButton"))
	await _wait(STEP_FRAMES)

	_press_escape()
	await _wait(STEP_FRAMES)
	var pause: Control = _screen_overlay()
	await _capture(tag + "_5_pause", pause.get_node("%Panel"))
	_press(pause.get_node("%SettingsButton"))
	await _wait(STEP_FRAMES)
	var settings_screen: Control = pause.get_node("%OverlayLayer").get_child(0)
	await _capture(tag + "_6_pause_settings", settings_screen.get_node("%Panel"))
	settings_screen.call(&"close")
	await _wait(STEP_FRAMES)
	_press(pause.get_node("%ResumeButton"))
	await _wait(STEP_FRAMES)

	# The day ends by the nameplate.
	_press(_screen().get_node("%NameplateButton"))
	await _wait(STEP_FRAMES)
	_press(_screen_overlay().get_node("%AcceptButton"))
	await _wait(STEP_FRAMES)
	_game.tick(0.0)
	await _settle()
	_expect_kind(tag, &"day_summary")
	await _capture(tag + "_7_day_summary", _screen().get_node("%Content"))
	_press(_screen().get_node("%NextDayButton"))
	await _settle()
	_expect_kind(tag, &"workshop")

	# Back to the title screen, then a save that cannot be read.
	_press_escape()
	await _wait(STEP_FRAMES)
	_press(_screen_overlay().get_node("%TitleButton"))
	await _settle()
	_expect_kind(tag, &"title")
	_game.continue_succeeds = false
	_press(_screen().get_node("%ContinueButton"))
	await _wait(STEP_FRAMES)
	await _capture(tag + "_8_continue_failed_notice", _host_overlay().get_node("%Panel"))
	_press(_host_overlay().get_node("%CloseButton"))
	await _wait(STEP_FRAMES)
	if not _game.blocked_reasons().is_empty():
		_fail(tag, "reasons to stop the clock are left: %s" % [_game.blocked_reasons()])


func _capture(tag: String, checked: Control) -> void:
	var visible: Vector2 = get_viewport().get_visible_rect().size
	var real_size: Vector2i = DisplayServer.window_get_size()
	var scale: float = minf(float(real_size.x) / BASE_SIZE.x, float(real_size.y) / BASE_SIZE.y)
	var expected: Vector2 = Vector2(real_size) / scale
	var problems: PackedStringArray = LayoutCheck.find_layout_problems(checked)
	var safe: Rect2 = LayoutCheck.safe_rect(get_viewport())
	print("[%s] %s window=%dx%d mode=%d visible=%s %s=%s items=%d problems=%d" % [
		TAG, tag, real_size.x, real_size.y, DisplayServer.window_get_mode(), visible,
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
	var path: String = _capture_folder.path_join("flow_%s.png" % tag)
	var error: Error = image.save_png(path)
	if error != OK:
		_fail(tag, "could not write %s (error %d)" % [path, error])
	else:
		_pictures += 1


func _screen() -> Control:
	return _host.get_screen()


func _host_overlay() -> Control:
	return _host.get_node("%OverlayLayer").get_child(0)


func _screen_overlay() -> Control:
	return _screen().get_node("%OverlayLayer").get_child(0)


func _press(button: Node) -> void:
	(button as Button).pressed.emit()


func _press_escape() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		Input.parse_input_event(event)


func _expect_kind(tag: String, kind: StringName) -> void:
	if _host.get_screen_kind() != kind:
		_fail(tag, "the host shows '%s', expected '%s'" % [_host.get_screen_kind(), kind])


## Waits until the swap of the screen has ended and the new screen is ready.
func _settle() -> void:
	for attempt: int in 10:
		await get_tree().process_frame
		if not _host.is_transitioning() and _host.get_screen() != null:
			break
	await _wait(STEP_FRAMES)


func _fail(tag: String, what: String) -> void:
	_capture_failures += 1
	print("[%s] FAIL %s: %s" % [TAG, tag, what])


func _settings_values(settings: Node) -> Dictionary:
	var values: Dictionary = {}
	if settings == null:
		return values
	for constant_name: StringName in [&"WINDOW_MODE", &"WINDOW_SIZE", &"VSYNC", &"VOLUME_MASTER", &"VOLUME_MUSIC", &"VOLUME_SFX"]:
		values[constant_name] = settings.call(&"get_value", settings.get(constant_name))
	return values


func _wait(frames: int) -> void:
	for index: int in frames:
		await get_tree().process_frame
