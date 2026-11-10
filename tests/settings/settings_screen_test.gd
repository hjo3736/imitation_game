extends Node
## Headless test for the settings screen (docs/roles/leader/outputs/08 work order, 3.4).
##
## Run:
##   godot --headless --path . res://tests/settings/settings_screen_test.tscn -- --settings-path=user://test_settings.cfg
## Exit code 0 means every check passed. Any failure gives exit code 1.
## Without the argument the run is not isolated from the player's settings
## file: it does nothing and exits with 1 (docs/roles/leader/outputs/11 design, section 3).
##
## The screen is tested against tests/settings/fake_settings.gd, never against the
## real settings manager. The autoload Settings is created all the same, which
## is why the run must be isolated.

const SCREEN_SCENE: PackedScene = preload("res://scenes/settings/settings_screen.tscn")
const FakeSettings: GDScript = preload("res://tests/settings/fake_settings.gd")
const LayoutCheck: GDScript = preload("res://tests/common/layout_check.gd")
const Isolation: GDScript = preload("res://tests/common/settings_isolation.gd")

const SCENE_PATH: String = "res://tests/settings/settings_screen_test.tscn"
const TAG: String = "settings_screen_test"

const OPEN_CLOSE_CYCLES: int = 25
# Window sizes for the layout check: 16:9, 16:10, 21:9 and the smallest window.
const LAYOUT_SIZES: Array[Vector2i] = [
	Vector2i(1920, 1080), Vector2i(1920, 1200), Vector2i(2520, 1080),
	Vector2i(1600, 900), Vector2i(1600, 1000), Vector2i(1680, 720),
	Vector2i(1280, 720), Vector2i(1280, 800),
]

var _checks: int = 0
var _failures: int = 0
var _closed_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not Isolation.begin(get_tree(), TAG, SCENE_PATH, true):
		get_tree().quit(1)
		return
	# The headless window starts with an arbitrary size.
	get_window().size = Vector2i(1920, 1080)
	await _frames(2)
	await _test_shows_values()
	await _test_controls_call_set_value()
	await _test_outside_change_updates_controls()
	await _test_window_size_disabled_in_fullscreen()
	await _test_refused_value_is_reverted()
	await _test_reset_needs_confirmation()
	await _test_close()
	await _test_escape()
	await _test_missing_settings()
	await _test_bad_settings()
	await _test_set_settings_after_enter()
	await _test_layout()
	await _test_no_leaks()

	_section("isolation")
	_equal(Isolation.finish(get_tree(), TAG), true, "the test settings file is removed and the player's settings file is as before")

	print("")
	print("[settings_screen_test] checks=%d failures=%d" % [_checks, _failures])
	print("[settings_screen_test] %s" % ("PASSED" if _failures == 0 else "FAILED"))
	get_tree().quit(0 if _failures == 0 else 1)


# --- Tests -------------------------------------------------------------------

func _test_shows_values() -> void:
	_section("opening shows the values of the settings object")
	var fake: Node = _new_fake()
	fake.change_from_outside(fake.WINDOW_MODE, &"windowed")
	fake.change_from_outside(fake.WINDOW_SIZE, Vector2i(1280, 720))
	fake.change_from_outside(fake.VSYNC, false)
	fake.change_from_outside(fake.VOLUME_MASTER, 0.5)
	fake.change_from_outside(fake.VOLUME_MUSIC, 0.25)
	fake.change_from_outside(fake.VOLUME_SFX, 0.0)
	var screen: Control = await _open(fake)

	var mode: OptionButton = screen.get_node("%WindowModeOption")
	var size_option: OptionButton = screen.get_node("%WindowSizeOption")
	var vsync: CheckButton = screen.get_node("%VsyncCheck")
	_equal(mode.item_count, 2, "window mode has two choices")
	_equal(mode.get_item_text(0), "전체 화면", "first mode name")
	_equal(mode.get_item_text(1), "창 모드", "second mode name")
	_equal(mode.selected, 1, "windowed is selected")
	_equal(size_option.item_count, 2, "window size shows the options of the settings object")
	_equal(size_option.get_item_text(0), "1280×720", "first size text")
	_equal(size_option.get_item_text(1), "1600×900", "second size text")
	_equal(size_option.selected, 0, "1280x720 is selected")
	_equal(vsync.button_pressed, false, "vsync is off")
	_equal(vsync.text, "끔", "vsync text is off")
	_equal(_slider(screen, "Master").value, 50.0, "master slider")
	_equal(_label(screen, "Master").text, "50%", "master percent")
	_equal(_slider(screen, "Music").value, 25.0, "music slider")
	_equal(_label(screen, "Music").text, "25%", "music percent")
	_equal(_slider(screen, "Sfx").value, 0.0, "sfx slider")
	_equal(_label(screen, "Sfx").text, "0%", "sfx percent")
	_equal(fake.set_calls.size(), 0, "opening calls set_value zero times")
	await _close_and_free(screen, fake)

	# Defaults of the fake (08 design, section 2).
	fake = _new_fake()
	screen = await _open(fake)
	mode = screen.get_node("%WindowModeOption")
	vsync = screen.get_node("%VsyncCheck")
	_equal(mode.selected, 0, "default: fullscreen is selected")
	_equal(vsync.button_pressed, true, "default: vsync is on")
	_equal(vsync.text, "켬", "default: vsync text is on")
	_equal(_label(screen, "Master").text, "100%", "default: master percent")
	_equal(_label(screen, "Music").text, "80%", "default: music percent")
	_equal(_label(screen, "Sfx").text, "100%", "default: sfx percent")
	await _close_and_free(screen, fake)


func _test_controls_call_set_value() -> void:
	_section("changing a control calls set_value with the right key and value")
	var fake: Node = _new_fake()
	var screen: Control = await _open(fake)
	var mode: OptionButton = screen.get_node("%WindowModeOption")
	var size_option: OptionButton = screen.get_node("%WindowSizeOption")
	var vsync: CheckButton = screen.get_node("%VsyncCheck")

	_pick(mode, 1)
	_equal(fake.set_calls.size(), 1, "one call after picking windowed")
	_equal(_last_call(fake), [fake.WINDOW_MODE, &"windowed"], "window mode call")
	_equal(typeof(_last_call(fake)[1]), TYPE_STRING_NAME, "window mode value is a StringName")
	_equal(fake.get_value(fake.WINDOW_MODE), &"windowed", "window mode stored")

	_pick(size_option, 0)
	_equal(fake.set_calls.size(), 2, "one more call after picking a size")
	_equal(_last_call(fake), [fake.WINDOW_SIZE, Vector2i(1280, 720)], "window size call")
	_equal(typeof(_last_call(fake)[1]), TYPE_VECTOR2I, "window size value is a Vector2i")

	vsync.button_pressed = false
	_equal(fake.set_calls.size(), 3, "one more call after turning vsync off")
	_equal(_last_call(fake), [fake.VSYNC, false], "vsync call")
	_equal(vsync.text, "끔", "vsync text follows")

	_slider(screen, "Master").value = 30.0
	_equal(fake.set_calls.size(), 4, "one more call after moving the master slider")
	_equal(_last_call(fake)[0], fake.VOLUME_MASTER, "master key")
	_near(_last_call(fake)[1], 0.3, "master value is 0.0 - 1.0")
	_equal(_label(screen, "Master").text, "30%", "master percent follows")

	_slider(screen, "Music").value = 0.0
	_equal(_last_call(fake)[0], fake.VOLUME_MUSIC, "music key")
	_near(_last_call(fake)[1], 0.0, "music value")
	_equal(_label(screen, "Music").text, "0%", "music percent follows")

	_slider(screen, "Sfx").value = 65.0
	_equal(_last_call(fake)[0], fake.VOLUME_SFX, "sfx key")
	_near(_last_call(fake)[1], 0.65, "sfx value")
	_equal(_label(screen, "Sfx").text, "65%", "sfx percent follows")
	_equal(fake.set_calls.size(), 6, "six calls in total, one per change")

	# Dragging: every step is applied (rule 8: apply every time).
	var before: int = fake.set_calls.size()
	for percent: int in [66, 67, 68, 69, 70]:
		_slider(screen, "Sfx").value = float(percent)
	_equal(fake.set_calls.size() - before, 5, "five slider steps give five set_value calls")
	_equal(fake.flush_count, 0, "the screen does not flush while values change")
	await _close_and_free(screen, fake)


func _test_outside_change_updates_controls() -> void:
	_section("a change from outside updates the controls without calling set_value")
	var fake: Node = _new_fake()
	var screen: Control = await _open(fake)
	var mode: OptionButton = screen.get_node("%WindowModeOption")
	var size_option: OptionButton = screen.get_node("%WindowSizeOption")
	var vsync: CheckButton = screen.get_node("%VsyncCheck")

	fake.change_from_outside(fake.WINDOW_MODE, &"windowed")
	_equal(mode.selected, 1, "mode follows")
	fake.change_from_outside(fake.WINDOW_SIZE, Vector2i(1280, 720))
	_equal(size_option.selected, 0, "size follows")
	fake.change_from_outside(fake.VSYNC, false)
	_equal(vsync.button_pressed, false, "vsync follows")
	_equal(vsync.text, "끔", "vsync text follows")
	fake.change_from_outside(fake.VOLUME_MASTER, 0.1)
	_equal(_slider(screen, "Master").value, 10.0, "master slider follows")
	_equal(_label(screen, "Master").text, "10%", "master percent follows")
	fake.change_from_outside(fake.VOLUME_MUSIC, 0.55)
	_equal(_slider(screen, "Music").value, 55.0, "music slider follows")
	fake.change_from_outside(fake.VOLUME_SFX, 0.07)
	_equal(_slider(screen, "Sfx").value, 7.0, "sfx slider follows")
	_equal(_label(screen, "Sfx").text, "7%", "sfx percent follows")

	# The options themselves can change (for example another monitor).
	fake.window_size_options = [Vector2i(1280, 720)]
	fake.change_from_outside(fake.WINDOW_MODE, &"fullscreen")
	_equal(size_option.item_count, 1, "size options are read again")
	await get_tree().process_frame
	_equal(fake.set_calls.size(), 0, "set_value was never called")
	await _close_and_free(screen, fake)


func _test_window_size_disabled_in_fullscreen() -> void:
	_section("the window size cannot be picked in fullscreen")
	var fake: Node = _new_fake()
	var screen: Control = await _open(fake)
	var mode: OptionButton = screen.get_node("%WindowModeOption")
	var size_option: OptionButton = screen.get_node("%WindowSizeOption")

	_equal(size_option.disabled, true, "disabled in fullscreen")
	_pick(mode, 1)
	_equal(size_option.disabled, false, "enabled in windowed")
	_pick(mode, 0)
	_equal(size_option.disabled, true, "disabled again in fullscreen")
	fake.change_from_outside(fake.WINDOW_MODE, &"windowed")
	_equal(size_option.disabled, false, "enabled after a change from outside")
	fake.window_size_options = []
	fake.change_from_outside(fake.WINDOW_MODE, &"fullscreen")
	fake.change_from_outside(fake.WINDOW_MODE, &"windowed")
	_equal(size_option.disabled, true, "disabled when there is no size to pick")
	await _close_and_free(screen, fake)


func _test_refused_value_is_reverted() -> void:
	_section("a refused value puts the control back")
	var fake: Node = _new_fake()
	fake.change_from_outside(fake.WINDOW_MODE, &"windowed")
	var screen: Control = await _open(fake)
	var size_option: OptionButton = screen.get_node("%WindowSizeOption")
	_equal(size_option.selected, 1, "1600x900 is selected")
	# The fake stops offering 1280x720 after the screen has listed it.
	fake.window_size_options = [Vector2i(1600, 900)]
	_pick(size_option, 0)
	_equal(fake.get_value(fake.WINDOW_SIZE), Vector2i(1600, 900), "the value did not change")
	_equal(size_option.item_count, 1, "the list was read again")
	_equal(size_option.selected, 0, "the control shows the stored value")
	_equal(size_option.get_item_text(size_option.selected), "1600×900", "the shown text is the stored size")
	await _close_and_free(screen, fake)


func _test_reset_needs_confirmation() -> void:
	_section("reset calls reset_to_defaults only after the confirmation")
	var fake: Node = _new_fake()
	fake.change_from_outside(fake.VOLUME_MUSIC, 0.2)
	fake.change_from_outside(fake.VSYNC, false)
	var screen: Control = await _open(fake)
	var confirm: Control = screen.get_node("%ConfirmLayer")
	var reset: Button = screen.get_node("%ResetButton")
	var yes: Button = screen.get_node("%ConfirmYesButton")
	var no: Button = screen.get_node("%ConfirmNoButton")

	_equal(confirm.visible, false, "no question at first")
	reset.pressed.emit()
	_equal(confirm.visible, true, "pressing reset asks")
	_equal(fake.reset_count, 0, "nothing is reset before the answer")
	no.pressed.emit()
	_equal(confirm.visible, false, "cancel hides the question")
	_equal(fake.reset_count, 0, "cancel resets nothing")
	_equal(_label(screen, "Music").text, "20%", "values stay after cancel")

	reset.pressed.emit()
	_press_escape()
	await _frames(2)
	_equal(confirm.visible, false, "Esc hides the question")
	_equal(fake.reset_count, 0, "Esc on the question resets nothing")
	_equal(is_instance_valid(screen) and not screen.is_queued_for_deletion(), true, "Esc on the question does not close the screen")
	_equal(fake.flush_count, 0, "Esc on the question does not flush")

	reset.pressed.emit()
	yes.pressed.emit()
	_equal(confirm.visible, false, "confirm hides the question")
	_equal(fake.reset_count, 1, "confirm resets once")
	yes.pressed.emit()
	_equal(fake.reset_count, 1, "pressing confirm again does nothing")
	_equal(_label(screen, "Music").text, "80%", "music is back at the default")
	_equal((screen.get_node("%VsyncCheck") as CheckButton).button_pressed, true, "vsync is back at the default")
	_equal(fake.set_calls.size(), 0, "reset does not go through set_value")
	await _close_and_free(screen, fake)


func _test_close() -> void:
	_section("closing flushes, emits closed once and frees the screen")
	var fake: Node = _new_fake()
	var screen: Control = await _open(fake)
	var close_button: Button = screen.get_node("%CloseButton")
	_closed_count = 0
	screen.closed.connect(_on_screen_closed)

	close_button.pressed.emit()
	close_button.pressed.emit()
	screen.close()
	_equal(fake.flush_count, 1, "flush is called once")
	_equal(_closed_count, 1, "closed is emitted once")
	_equal(screen.is_queued_for_deletion(), true, "the screen frees itself")
	# A change after closing must not reach the settings object.
	_slider(screen, "Master").value = 5.0
	_equal(fake.set_calls.size(), 0, "no set_value after closing")
	await _frames(2)
	_equal(is_instance_valid(screen), false, "the screen is freed")
	_equal(fake.changed.get_connections().size(), 0, "no connection left on changed")
	_equal(fake.flush_count, 1, "flush is still called once")
	_equal(_closed_count, 1, "closed is still emitted once")
	fake.free()


func _test_escape() -> void:
	_section("Esc closes the screen")
	var fake: Node = _new_fake()
	var screen: Control = await _open(fake)
	_closed_count = 0
	screen.closed.connect(_on_screen_closed)
	_press_escape()
	_press_escape()
	await _frames(3)
	_equal(fake.flush_count, 1, "flush is called once")
	_equal(_closed_count, 1, "closed is emitted once")
	_equal(is_instance_valid(screen), false, "the screen is freed")
	fake.free()


func _test_missing_settings() -> void:
	_section("no settings object: an error, no crash")
	if get_node_or_null("/root/Settings") != null:
		print("  SKIP: the autoload Settings exists in this project, so this case cannot be produced")
		return
	print("  (the next engine error line is expected)")
	var screen: Control = SCREEN_SCENE.instantiate()
	add_child(screen)
	await get_tree().process_frame
	var error_label: Label = screen.get_node("%ErrorLabel")
	_equal(error_label.visible, true, "the error is shown")
	_equal(error_label.text.contains("Settings"), true, "the error names what is missing")
	_equal((screen.get_node("%WindowModeOption") as OptionButton).disabled, true, "window mode is disabled")
	_equal((screen.get_node("%WindowSizeOption") as OptionButton).disabled, true, "window size is disabled")
	_equal((screen.get_node("%VsyncCheck") as CheckButton).disabled, true, "vsync is disabled")
	_equal(_slider(screen, "Master").editable, false, "sliders are not editable")
	_equal((screen.get_node("%ResetButton") as Button).disabled, true, "reset is disabled")
	_equal((screen.get_node("%CloseButton") as Button).disabled, false, "close still works")
	_closed_count = 0
	screen.closed.connect(_on_screen_closed)
	(screen.get_node("%CloseButton") as Button).pressed.emit()
	await _frames(2)
	_equal(_closed_count, 1, "closed is emitted once")
	_equal(is_instance_valid(screen), false, "the screen is freed")


func _test_bad_settings() -> void:
	_section("an object that does not follow the contract: an error, no crash")
	print("  (the next engine error line is expected)")
	var bad: Node = Node.new()
	var screen: Control = SCREEN_SCENE.instantiate()
	screen.set_settings(bad)
	add_child(screen)
	await get_tree().process_frame
	var error_label: Label = screen.get_node("%ErrorLabel")
	_equal(error_label.visible, true, "the error is shown")
	_equal(error_label.text.contains("계약"), true, "the shown error says the contract is not followed")
	_equal(error_label.tooltip_text.contains("set_value()"), true, "the full error names a missing function")
	_equal(error_label.tooltip_text.contains("WINDOW_MODE"), true, "the full error names a missing key")
	_equal((screen.get_node("%WindowModeOption") as OptionButton).disabled, true, "window mode is disabled")
	_no_problems(LayoutCheck.find_layout_problems(screen.get_node("%Panel")), "panel with the error text")
	screen.close()
	await _frames(2)
	_equal(is_instance_valid(screen), false, "the screen is freed")
	bad.free()


func _test_set_settings_after_enter() -> void:
	_section("set_settings after entering the tree is refused")
	print("  (the next engine error line is expected)")
	var fake: Node = _new_fake()
	var other: Node = _new_fake()
	var screen: Control = await _open(fake)
	screen.set_settings(other)
	_slider(screen, "Master").value = 40.0
	_equal(fake.set_calls.size(), 1, "the first object is still used")
	_equal(other.set_calls.size(), 0, "the second object is not used")
	await _close_and_free(screen, fake)
	other.free()


func _test_layout() -> void:
	_section("layout: inside the safe area, nothing cut, nothing overlapping")
	var window: Window = get_window()
	var original_size: Vector2i = window.size
	var fake: Node = _new_fake()
	fake.change_from_outside(fake.WINDOW_MODE, &"windowed")
	var screen: Control = await _open(fake)
	var panel: Control = screen.get_node("%Panel")
	var confirm_panel: Control = screen.get_node("%ConfirmPanel")

	_equal(LayoutCheck.count_items(panel), 20, "the check covers 12 labels, 3 sliders and 5 buttons")
	_equal(LayoutCheck.count_items(confirm_panel), 3, "the check covers the question and its 2 buttons")
	var thin: PackedStringArray = LayoutCheck.find_thin_lines(screen)
	for line: String in thin:
		print("    thin line: " + line)
	_equal(thin.size(), 0, "no style box draws a line thinner than 2")

	for window_size: Vector2i in LAYOUT_SIZES:
		window.size = window_size
		await _frames(3)
		var visible: Vector2 = get_viewport().get_visible_rect().size
		var scale: float = minf(float(window_size.x) / 1920.0, float(window_size.y) / 1080.0)
		var expected: Vector2 = Vector2(window_size) / scale
		_equal(visible.is_equal_approx(expected) or visible.distance_to(expected) < 1.5, true,
				"%dx%d shows %s (expected about %s)" % [window_size.x, window_size.y, visible, expected])
		_equal(screen.get_global_rect().size.distance_to(visible) < 0.01, true,
				"%dx%d: the screen covers the visible area" % [window_size.x, window_size.y])
		var safe: Rect2 = LayoutCheck.safe_rect(get_viewport())
		var panel_rect: Rect2 = panel.get_global_rect()
		_equal(panel_rect.get_center().distance_to(safe.get_center()) < 1.0, true,
				"%dx%d: the panel is centered" % [window_size.x, window_size.y])
		_no_problems(LayoutCheck.find_layout_problems(panel), "%dx%d: panel" % [window_size.x, window_size.y])
		(screen.get_node("%ResetButton") as Button).pressed.emit()
		await _frames(2)
		_no_problems(LayoutCheck.find_layout_problems(confirm_panel), "%dx%d: confirmation" % [window_size.x, window_size.y])
		(screen.get_node("%ConfirmNoButton") as Button).pressed.emit()

	window.size = original_size
	await _frames(2)
	await _close_and_free(screen, fake)


func _test_no_leaks() -> void:
	_section("opening and closing %d times leaves nothing behind" % OPEN_CLOSE_CYCLES)
	var fake: Node = _new_fake()
	# One warm-up cycle, so one-time allocations are not counted as a leak.
	var warm_up: Control = await _open(fake)
	warm_up.close()
	await _frames(3)

	var nodes_before: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var objects_before: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var flushes_before: int = fake.flush_count
	var screens: Array[WeakRef] = []
	var max_connections: int = 0
	var nodes_while_open: int = 0
	for cycle: int in OPEN_CLOSE_CYCLES:
		var screen: Control = await _open(fake)
		screens.append(weakref(screen))
		max_connections = maxi(max_connections, fake.changed.get_connections().size())
		nodes_while_open = maxi(nodes_while_open, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		_slider(screen, "Music").value = float(cycle)
		(screen.get_node("%WindowModeOption") as OptionButton).show_popup()
		await get_tree().process_frame
		if cycle % 2 == 0:
			(screen.get_node("%CloseButton") as Button).pressed.emit()
		else:
			_press_escape()
			await _frames(2)
			# Esc may have closed only the popup; make sure the screen closes.
			if is_instance_valid(screen):
				screen.close()
		screen = null
		await _frames(3)

	var alive: int = 0
	for reference: WeakRef in screens:
		if reference.get_ref() != null:
			alive += 1
	screens.clear()
	var nodes_after: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var objects_after: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	print("  nodes %d -> %d (%d while a screen is open), orphan nodes %d -> %d, objects %d -> %d" % [
		nodes_before, nodes_after, nodes_while_open, orphans_before, orphans_after, objects_before, objects_after,
	])
	_equal(nodes_while_open > nodes_before, true, "the node count does rise while a screen is open")
	_equal(objects_after - objects_before < OPEN_CLOSE_CYCLES, true, "the object count does not grow with every cycle")
	_equal(max_connections, 1, "one connection on changed while a screen is open")
	_equal(fake.changed.get_connections().size(), 0, "no connection left on changed")
	_equal(alive, 0, "every screen is freed")
	_equal(nodes_after, nodes_before, "the node count is back where it was")
	_equal(orphans_after, orphans_before, "no orphan node was added")
	_equal(fake.flush_count - flushes_before, OPEN_CLOSE_CYCLES, "one flush per close")
	fake.free()


# --- Helpers -----------------------------------------------------------------

func _new_fake() -> Node:
	return FakeSettings.new()


func _open(fake: Node) -> Control:
	var screen: Control = SCREEN_SCENE.instantiate()
	screen.set_settings(fake)
	add_child(screen)
	await get_tree().process_frame
	return screen


func _close_and_free(screen: Control, fake: Node) -> void:
	screen.close()
	await _frames(2)
	_equal(is_instance_valid(screen), false, "the screen is freed after close")
	_equal(fake.changed.get_connections().size(), 0, "no connection left on changed after close")
	fake.free()


func _frames(count: int) -> void:
	for index: int in count:
		await get_tree().process_frame


func _slider(screen: Control, prefix: String) -> HSlider:
	return screen.get_node("%" + prefix + "Slider") as HSlider


func _label(screen: Control, prefix: String) -> Label:
	return screen.get_node("%" + prefix + "Value") as Label


## Picks an item the way a click in the popup does: select, then item_selected.
func _pick(option: OptionButton, index: int) -> void:
	option.select(index)
	option.item_selected.emit(index)


func _press_escape() -> void:
	var press: InputEventKey = InputEventKey.new()
	press.keycode = KEY_ESCAPE
	press.physical_keycode = KEY_ESCAPE
	press.pressed = true
	Input.parse_input_event(press)
	var release: InputEventKey = InputEventKey.new()
	release.keycode = KEY_ESCAPE
	release.physical_keycode = KEY_ESCAPE
	release.pressed = false
	Input.parse_input_event(release)


func _last_call(fake: Node) -> Array:
	return fake.set_calls[fake.set_calls.size() - 1]


func _on_screen_closed() -> void:
	_closed_count += 1


func _section(title: String) -> void:
	print("")
	print("[test] " + title)


func _equal(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if typeof(actual) == typeof(expected) and actual == expected:
		print("  ok   " + what)
	else:
		_failures += 1
		print("  FAIL %s: got %s, expected %s" % [what, var_to_str(actual), var_to_str(expected)])


func _near(actual: Variant, expected: float, what: String) -> void:
	_checks += 1
	if (actual is float or actual is int) and absf(float(actual) - expected) < 0.0001:
		print("  ok   " + what)
	else:
		_failures += 1
		print("  FAIL %s: got %s, expected about %s" % [what, var_to_str(actual), expected])


func _no_problems(problems: PackedStringArray, what: String) -> void:
	_checks += 1
	if problems.is_empty():
		print("  ok   %s: no layout problem" % what)
	else:
		_failures += 1
		print("  FAIL %s: %d layout problem(s)" % [what, problems.size()])
		for problem: String in problems:
			print("       " + problem)
