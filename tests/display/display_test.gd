extends Control
## Display settings check scene (docs/leader/07 design, section 6).
## This is not a game screen and is not registered as the main scene.
## Esc quits. F11 toggles fullscreen / windowed (check-only feature).

# --- Confirmed values (docs/leader/07 design, section 4) ---------------------
const SAFE_AREA_SIZE: Vector2 = Vector2(1920.0, 1080.0)
const WIDEST_VIEW_SIZE: Vector2 = Vector2(2520.0, 1080.0)
const TALLEST_VIEW_SIZE: Vector2 = Vector2(1920.0, 1200.0)

# --- Check-only values --------------------------------------------------------
# Everything below exists only to make this test scene readable.
# None of it is a game number or a design decision.
const ASPECT_TOLERANCE: float = 0.005
const COLOR_OUT_OF_RANGE: Color = Color(0.45, 0.10, 0.45)
const COLOR_BACKGROUND: Color = Color(0.16, 0.24, 0.36)
const COLOR_SAFE_AREA: Color = Color(0.10, 0.11, 0.13)
const COLOR_SAFE_BORDER: Color = Color(1.0, 0.85, 0.2)
const COLOR_CROSSHAIR: Color = Color(0.3, 0.9, 0.5)
const COLOR_SHAPE: Color = Color(0.92, 0.92, 0.92)
const COLOR_TEXT: Color = Color(0.95, 0.95, 0.95)
const COLOR_CORNER: Color = Color(0.9, 0.25, 0.2)
const SAFE_BORDER_WIDTH: float = 4.0
const CROSSHAIR_WIDTH: float = 2.0
const CORNER_MARKER_SIZE: Vector2 = Vector2(96.0, 96.0)
const CORNER_FONT_SIZE: int = 32
const INFO_FONT_SIZE: int = 30
const INFO_POSITION: Vector2 = Vector2(140.0, 50.0)
const SAMPLE_FONT_SIZES: Array[int] = [12, 16, 20, 24, 32, 48, 72]
const SAMPLE_TEXT: String = "Imitation game 0123456789"
const SAMPLE_POSITION: Vector2 = Vector2(140.0, 580.0)
const SAMPLE_LINE_GAP: float = 14.0
const LINE_WIDTHS: Array[float] = [1.0, 2.0, 3.0, 4.0]
const LINE_ORIGIN: Vector2 = Vector2(1180.0, 120.0)
const LINE_LENGTH: float = 600.0
const LINE_GAP: float = 30.0
const CIRCLE_CENTER: Vector2 = Vector2(1580.0, 790.0)
const CIRCLE_RADII: Array[float] = [60.0, 120.0, 180.0]
const CIRCLE_WIDTH: float = 2.0
const CIRCLE_POINT_COUNT: int = 128
const CENTER_CIRCLE_RADIUS: float = 100.0

var _safe_area: Control = null
var _info_label: Label = null
var _last_printed: String = ""


func _enter_tree() -> void:
	if _safe_area == null:
		_build()
	var viewport: Viewport = get_viewport()
	if not viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.connect(_on_viewport_size_changed)
	if not _safe_area.draw.is_connected(_on_safe_area_draw):
		_safe_area.draw.connect(_on_safe_area_draw)


func _ready() -> void:
	_update_info()


func _exit_tree() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.disconnect(_on_viewport_size_changed)
	if _safe_area != null and _safe_area.draw.is_connected(_on_safe_area_draw):
		_safe_area.draw.disconnect(_on_safe_area_draw)


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		get_tree().quit()
	elif key_event.keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		_toggle_fullscreen()


func _build() -> void:
	# 1. Solid fill for aspect ratios outside the supported range.
	var fill: ColorRect = ColorRect.new()
	fill.name = "OutOfRangeFill"
	fill.color = COLOR_OUT_OF_RANGE
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fill)

	# 2. Background that covers the widest and the tallest supported view.
	var background: ColorRect = ColorRect.new()
	background.name = "Background"
	background.color = COLOR_BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_place_centered(background, Vector2(WIDEST_VIEW_SIZE.x, TALLEST_VIEW_SIZE.y))

	# 3. Safe area, always centered. Shapes are drawn in _on_safe_area_draw.
	_safe_area = ColorRect.new()
	_safe_area.name = "SafeArea"
	(_safe_area as ColorRect).color = COLOR_SAFE_AREA
	_safe_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe_area)
	_place_centered(_safe_area, SAFE_AREA_SIZE)

	_info_label = _make_label("", INFO_FONT_SIZE)
	_info_label.name = "Info"
	_info_label.position = INFO_POSITION
	_safe_area.add_child(_info_label)

	var sample_y: float = SAMPLE_POSITION.y
	for font_size: int in SAMPLE_FONT_SIZES:
		var sample: Label = _make_label("%d px  %s" % [font_size, SAMPLE_TEXT], font_size)
		sample.position = Vector2(SAMPLE_POSITION.x, sample_y)
		_safe_area.add_child(sample)
		sample_y += float(font_size) + SAMPLE_LINE_GAP

	# 4. Markers pinned to the four corners of the real screen.
	_add_corner_marker("TL", Vector2(0.0, 0.0))
	_add_corner_marker("TR", Vector2(1.0, 0.0))
	_add_corner_marker("BL", Vector2(0.0, 1.0))
	_add_corner_marker("BR", Vector2(1.0, 1.0))


func _place_centered(control: Control, control_size: Vector2) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 0.5
	control.anchor_bottom = 0.5
	control.offset_left = -control_size.x * 0.5
	control.offset_right = control_size.x * 0.5
	control.offset_top = -control_size.y * 0.5
	control.offset_bottom = control_size.y * 0.5


func _add_corner_marker(text: String, anchor: Vector2) -> void:
	var marker: ColorRect = ColorRect.new()
	marker.name = "Corner" + text
	marker.color = COLOR_CORNER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.anchor_left = anchor.x
	marker.anchor_right = anchor.x
	marker.anchor_top = anchor.y
	marker.anchor_bottom = anchor.y
	marker.offset_left = -CORNER_MARKER_SIZE.x * anchor.x
	marker.offset_right = CORNER_MARKER_SIZE.x * (1.0 - anchor.x)
	marker.offset_top = -CORNER_MARKER_SIZE.y * anchor.y
	marker.offset_bottom = CORNER_MARKER_SIZE.y * (1.0 - anchor.y)
	add_child(marker)

	var label: Label = _make_label(text, CORNER_FONT_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marker.add_child(label)


func _make_label(text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	return label


func _toggle_fullscreen() -> void:
	var window: Window = get_window()
	if window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		window.mode = Window.MODE_WINDOWED
	else:
		window.mode = Window.MODE_FULLSCREEN


func _update_info() -> void:
	var window: Window = get_window()
	var window_size: Vector2i = window.size
	var visible_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = visible_size.x / visible_size.y if visible_size.y > 0.0 else 0.0
	var min_aspect: float = TALLEST_VIEW_SIZE.x / TALLEST_VIEW_SIZE.y
	var max_aspect: float = WIDEST_VIEW_SIZE.x / WIDEST_VIEW_SIZE.y
	var in_range: bool = aspect >= min_aspect - ASPECT_TOLERANCE and aspect <= max_aspect + ASPECT_TOLERANCE
	var mode_name: String = _mode_name(window.mode)

	var lines: PackedStringArray = PackedStringArray()
	lines.append("Window size: %d x %d px" % [window_size.x, window_size.y])
	lines.append("Visible area: %.1f x %.1f" % [visible_size.x, visible_size.y])
	lines.append("Aspect ratio: %.4f" % aspect)
	lines.append("Supported range %.4f - %.4f: %s" % [min_aspect, max_aspect, "YES" if in_range else "NO"])
	lines.append("Window mode: %s" % mode_name)
	lines.append("Esc: quit    F11: fullscreen / windowed")
	_info_label.text = "\n".join(lines)

	var summary: String = "[display_test] window=%dx%d visible=%.1fx%.1f aspect=%.4f in_range=%s mode=%s" % [
		window_size.x, window_size.y, visible_size.x, visible_size.y, aspect,
		"yes" if in_range else "no", mode_name,
	]
	if summary != _last_printed:
		_last_printed = summary
		print(summary)


func _mode_name(mode: Window.Mode) -> String:
	match mode:
		Window.MODE_WINDOWED:
			return "windowed"
		Window.MODE_MINIMIZED:
			return "minimized"
		Window.MODE_MAXIMIZED:
			return "maximized"
		Window.MODE_FULLSCREEN:
			return "fullscreen"
		Window.MODE_EXCLUSIVE_FULLSCREEN:
			return "exclusive_fullscreen"
	return "unknown"


func _on_viewport_size_changed() -> void:
	_update_info()
	_safe_area.queue_redraw()


func _on_safe_area_draw() -> void:
	var center: Vector2 = SAFE_AREA_SIZE * 0.5

	# Border of the safe area, drawn fully inside it.
	var inset: float = SAFE_BORDER_WIDTH * 0.5
	var border: Rect2 = Rect2(Vector2(inset, inset), SAFE_AREA_SIZE - Vector2(inset, inset) * 2.0)
	_safe_area.draw_rect(border, COLOR_SAFE_BORDER, false, SAFE_BORDER_WIDTH)

	# Crosshair through the center.
	_safe_area.draw_line(Vector2(0.0, center.y), Vector2(SAFE_AREA_SIZE.x, center.y), COLOR_CROSSHAIR, CROSSHAIR_WIDTH)
	_safe_area.draw_line(Vector2(center.x, 0.0), Vector2(center.x, SAFE_AREA_SIZE.y), COLOR_CROSSHAIR, CROSSHAIR_WIDTH)
	_safe_area.draw_arc(center, CENTER_CIRCLE_RADIUS, 0.0, TAU, CIRCLE_POINT_COUNT, COLOR_CROSSHAIR, CROSSHAIR_WIDTH, true)

	# Thin lines: horizontal, vertical and diagonal for each width.
	var index: int = 0
	for width: float in LINE_WIDTHS:
		var step: float = LINE_GAP * float(index)
		var horizontal_from: Vector2 = LINE_ORIGIN + Vector2(0.0, step)
		_safe_area.draw_line(horizontal_from, horizontal_from + Vector2(LINE_LENGTH, 0.0), COLOR_SHAPE, width)
		var vertical_from: Vector2 = LINE_ORIGIN + Vector2(step, LINE_GAP * float(LINE_WIDTHS.size() + 1))
		_safe_area.draw_line(vertical_from, vertical_from + Vector2(0.0, LINE_LENGTH * 0.4), COLOR_SHAPE, width)
		var diagonal_from: Vector2 = LINE_ORIGIN + Vector2(LINE_LENGTH * 0.4 + step * 2.0, LINE_GAP * float(LINE_WIDTHS.size() + 1))
		_safe_area.draw_line(diagonal_from, diagonal_from + Vector2(LINE_LENGTH * 0.4, LINE_LENGTH * 0.4), COLOR_SHAPE, width, true)
		index += 1

	# Circles: must stay round at every aspect ratio.
	for radius: float in CIRCLE_RADII:
		_safe_area.draw_arc(CIRCLE_CENTER, radius, 0.0, TAU, CIRCLE_POINT_COUNT, COLOR_SHAPE, CIRCLE_WIDTH, true)
	_safe_area.draw_circle(CIRCLE_CENTER, CIRCLE_RADII[0] * 0.5, COLOR_SHAPE)
