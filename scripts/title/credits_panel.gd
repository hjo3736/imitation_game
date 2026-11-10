extends "res://scripts/title/overlay_panel.gd"
## Credits panel (docs/leader/10 design, section 3).
## Opens over the title screen, scrolls, and closes with its button or Esc.

# --- Content (docs/leader/10 design, section 3) ------------------------------
# The whole content of the panel is this list, one entry per line. The real
# credits and the sources of the works and fonts used will be added here.
const CREDIT_LINES: Array[String] = [
	"Imitation game",
	"제작진 정보는 추후 추가됩니다.",
	"Made with Godot Engine",
]

@onready var _heading: Label = %Heading
@onready var _scroll: ScrollContainer = %Scroll
@onready var _lines: VBoxContainer = %Lines


func _ready() -> void:
	super._ready()
	_heading.add_theme_font_size_override(&"font_size", TitleStyle.PANEL_TITLE_FONT_SIZE)
	_scroll.custom_minimum_size = TitleStyle.CREDITS_SCROLL_MIN_SIZE
	_lines.add_theme_constant_override(&"separation", TitleStyle.CREDITS_LINE_SEPARATION)
	for line: String in CREDIT_LINES:
		var label: Label = Label.new()
		label.text = line
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lines.add_child(label)
