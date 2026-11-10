extends RefCounted
## Test-only layout checks for the settings screen (docs/leader/08 design 5.4,
## docs/leader/07 design section 4). Used by the headless test and by the
## preview scene.

const SAFE_AREA_SIZE: Vector2 = Vector2(1920.0, 1080.0)
const MIN_LINE_WIDTH: float = 2.0
# Tolerance for float rounding when comparing rectangles.
const EPSILON: float = 0.01


## The guaranteed area: 1920x1080 in the middle of what the viewport shows.
static func safe_rect(viewport: Viewport) -> Rect2:
	var visible: Rect2 = viewport.get_visible_rect()
	return Rect2(visible.position + (visible.size - SAFE_AREA_SIZE) * 0.5, SAFE_AREA_SIZE)


## Returns one line per layout problem under root. Empty means no problem.
## Checks every visible button, slider and label: inside the guaranteed area,
## not squeezed below its minimum size, and not overlapping another one.
static func find_layout_problems(root: Control) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var safe: Rect2 = safe_rect(root.get_viewport()).grow(EPSILON)
	var root_rect: Rect2 = root.get_global_rect()
	if not safe.encloses(root_rect):
		problems.append("%s %s is outside the safe area %s" % [root.name, root_rect, safe])

	var items: Array[Control] = []
	_collect_items(root, items)
	for item: Control in items:
		var rect: Rect2 = item.get_global_rect()
		if not safe.encloses(rect):
			problems.append("%s %s is outside the safe area %s" % [item.name, rect, safe])
		if not root_rect.grow(EPSILON).encloses(rect):
			problems.append("%s %s sticks out of %s %s" % [item.name, rect, root.name, root_rect])
		var minimum: Vector2 = item.get_combined_minimum_size()
		if rect.size.x + EPSILON < minimum.x or rect.size.y + EPSILON < minimum.y:
			problems.append("%s is cut: size %s < minimum %s" % [item.name, rect.size, minimum])
	for first: int in items.size():
		for second: int in range(first + 1, items.size()):
			var a: Rect2 = items[first].get_global_rect().grow(-EPSILON)
			var b: Rect2 = items[second].get_global_rect().grow(-EPSILON)
			if a.intersects(b):
				problems.append("%s %s overlaps %s %s" % [items[first].name, a, items[second].name, b])
	return problems


## Number of visible buttons, sliders and labels under root.
static func count_items(root: Control) -> int:
	var items: Array[Control] = []
	_collect_items(root, items)
	return items.size()


## Returns one line per style box under root (popup menus included) that draws
## a line thinner than 2. Icons are images and are not covered by this check.
static func find_thin_lines(root: Node) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	_collect_thin_lines(root, problems)
	return problems


static func _collect_items(node: Node, items: Array[Control]) -> void:
	for child: Node in node.get_children():
		var control: Control = child as Control
		if control == null or not control.visible:
			continue
		if control is BaseButton or control is Range or control is Label:
			items.append(control)
		else:
			_collect_items(control, items)


static func _collect_thin_lines(node: Node, problems: PackedStringArray) -> void:
	if node is Control or node is Window:
		var default_theme: Theme = ThemeDB.get_default_theme()
		var type_name: StringName = node.get_class()
		while type_name != &"" and type_name != &"Object":
			for style_name: String in default_theme.get_stylebox_list(type_name):
				var style: StyleBox = node.call(&"get_theme_stylebox", StringName(style_name), type_name)
				var width: float = _thinnest_line(style)
				if width > 0.0 and width < MIN_LINE_WIDTH:
					problems.append("%s: %s/%s draws a line of width %s" % [node.name, type_name, style_name, width])
			type_name = ClassDB.get_parent_class(type_name)
	for child: Node in node.get_children(true):
		_collect_thin_lines(child, problems)


## Thinnest line a style box draws, or 0.0 when it draws none.
static func _thinnest_line(style: StyleBox) -> float:
	var thinnest: float = 0.0
	if style is StyleBoxFlat:
		var flat: StyleBoxFlat = style
		if not flat.draw_center or flat.border_color != flat.bg_color:
			for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				var width: float = float(flat.get_border_width(side))
				if width > 0.0 and (thinnest == 0.0 or width < thinnest):
					thinnest = width
	elif style is StyleBoxLine:
		var line: StyleBoxLine = style
		thinnest = float(line.thickness)
	return thinnest
