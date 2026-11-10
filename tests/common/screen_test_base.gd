extends Node
## Base of the headless screen tests added in the 13 work: counting checks,
## waiting for frames, real key and mouse input, layout checks, and the
## isolation from the player's settings file (docs/roles/common.md, section 8).
##
## A test extends this script, sets TAG-like values through _tag() and
## _scene_path(), and implements _run_tests().

const LayoutCheck: GDScript = preload("res://tests/common/layout_check.gd")
const Isolation: GDScript = preload("res://tests/common/settings_isolation.gd")

# Window sizes for the layout checks: 16:9, 16:10, 21:9 and the smallest window.
const LAYOUT_SIZES: Array[Vector2i] = [
	Vector2i(1920, 1080), Vector2i(1920, 1200), Vector2i(2520, 1080),
	Vector2i(1600, 900), Vector2i(1600, 1000), Vector2i(1680, 720),
	Vector2i(1280, 720), Vector2i(1280, 800),
]
const BASE_SIZE: Vector2 = Vector2(1920.0, 1080.0)

var _checks: int = 0
var _failures: int = 0


## Name printed in front of the test's lines.
func _tag() -> String:
	return "screen_test"


## res:// path of the test scene, for the "run it like this" line.
func _scene_path() -> String:
	return ""


## The tests themselves.
func _run_tests() -> void:
	pass


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not Isolation.begin(get_tree(), _tag(), _scene_path(), true):
		get_tree().quit(1)
		return
	# The headless window starts with an arbitrary size.
	get_window().size = Vector2i(1920, 1080)
	await _frames(2)

	await _run_tests()

	_section("the run stayed isolated from the player's settings file")
	_equal(Isolation.finish(get_tree(), _tag()), true, "the test settings file is removed and the player's settings file is as before")
	print("")
	print("[%s] checks=%d failures=%d" % [_tag(), _checks, _failures])
	print("[%s] %s" % [_tag(), "PASSED" if _failures == 0 else "FAILED"])
	get_tree().quit(0 if _failures == 0 else 1)


# --- Waiting and input -------------------------------------------------------

func _frames(count: int) -> void:
	for index: int in count:
		await get_tree().process_frame


func _press_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)


## A left click in the middle of the control, as real mouse input.
func _click(control: Control) -> void:
	# Viewport coordinates to window coordinates.
	var position: Vector2 = get_viewport().get_final_transform() * control.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		Input.parse_input_event(event)


func _focus_name() -> String:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return String(focused.name) if focused != null else "(none)"


func _focus_inside(root: Control) -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return focused != null and root != null and is_instance_valid(root) and root.is_ancestor_of(focused)


## How many controls under root can take the keyboard focus / the mouse now.
func _reachable(root: Control) -> Vector2i:
	var counts: Vector2i = Vector2i.ZERO
	for node: Node in root.find_children("*", "BaseButton", true, false):
		var button: BaseButton = node
		if button.get_focus_mode_with_override() != Control.FOCUS_NONE:
			counts.x += 1
		if button.get_mouse_filter_with_override() != Control.MOUSE_FILTER_IGNORE:
			counts.y += 1
	return counts


# --- Counting ----------------------------------------------------------------

func _connection_count(object: Object, signal_name: StringName) -> int:
	if object == null or not object.has_signal(signal_name):
		return -1
	return object.get_signal_connection_list(signal_name).size()


func _node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _orphan_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _object_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


# --- Layout ------------------------------------------------------------------

## Sets the (headless) window size and checks what the viewport then shows.
func _set_window_size(window_size: Vector2i) -> String:
	var tag: String = "%dx%d" % [window_size.x, window_size.y]
	get_window().size = window_size
	await _frames(3)
	var visible: Vector2 = get_viewport().get_visible_rect().size
	var scale: float = minf(float(window_size.x) / BASE_SIZE.x, float(window_size.y) / BASE_SIZE.y)
	var expected: Vector2 = Vector2(window_size) / scale
	_equal(visible.distance_to(expected) < 1.5, true, "%s shows %s (expected about %s)" % [tag, visible, expected])
	return tag


## The checked control is centered in the safe area, and nothing under it is
## outside the safe area, cut or overlapping.
func _check_layout(checked: Control, what: String) -> void:
	var safe: Rect2 = LayoutCheck.safe_rect(get_viewport())
	_equal(checked.get_global_rect().get_center().distance_to(safe.get_center()) < 1.0, true, "%s is centered" % what)
	_no_problems(LayoutCheck.find_layout_problems(checked), what)


## The control covers everything the viewport shows.
func _check_covers_view(control: Control, what: String) -> void:
	var visible: Vector2 = get_viewport().get_visible_rect().size
	_equal(control.get_global_rect().size.distance_to(visible) < 0.01, true, "%s covers the visible area" % what)


# --- Checks ------------------------------------------------------------------

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


func _no_problems(problems: PackedStringArray, what: String) -> void:
	_checks += 1
	if problems.is_empty():
		print("  ok   %s: no layout problem" % what)
	else:
		_failures += 1
		print("  FAIL %s: %d layout problem(s)" % [what, problems.size()])
		for problem: String in problems:
			print("       " + problem)


func _no_thin_lines(root: Node, what: String) -> void:
	var thin: PackedStringArray = LayoutCheck.find_thin_lines(root)
	for line: String in thin:
		print("    thin line: " + line)
	_equal(thin.size(), 0, "%s: no style box draws a line thinner than 2" % what)
