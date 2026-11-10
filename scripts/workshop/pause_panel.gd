extends "res://scripts/common/closable_panel.gd"
## Pause panel of the workshop (docs/leader/13 design, section 6, item 5).
##
##   continue            closes the panel (so does Esc)
##   settings            opens the existing settings screen over this panel
##   to the title screen emits title_requested once, then closes
##
## The panel does not touch the clock: the workshop stops it for as long as
## this panel is in the tree.

const UiStyle: GDScript = preload("res://scripts/common/ui_style.gd")
const UiText: GDScript = preload("res://scripts/common/ui_text.gd")

const SETTINGS_SCENE: PackedScene = preload("res://scenes/settings/settings_screen.tscn")

## Emitted once when "to the title screen" is chosen, right before closing.
signal title_requested

@onready var _dim: ColorRect = %Dim
@onready var _panel: PanelContainer = %Panel
@onready var _heading: Label = %Heading
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _title_button: Button = %TitleButton
@onready var _overlay_layer: Control = %OverlayLayer


## True while the settings screen is open over this panel.
func has_overlay() -> bool:
	return _overlay_layer != null and _overlay_layer.call(&"has_overlay")


func _ready() -> void:
	theme = UiStyle.make_panel_theme()
	_dim.color = UiStyle.COLOR_DIM
	_heading.text = UiText.PAUSE_HEADING
	_heading.add_theme_font_size_override(&"font_size", UiStyle.PANEL_HEADING_FONT_SIZE)
	_resume_button.text = UiText.PAUSE_RESUME
	_settings_button.text = UiText.PAUSE_SETTINGS
	_title_button.text = UiText.PAUSE_TO_TITLE
	for button: Button in [_resume_button, _settings_button, _title_button]:
		button.custom_minimum_size = UiStyle.PANEL_MENU_BUTTON_MIN_SIZE
	_overlay_layer.call(&"set_blocked", _panel)
	# Connections to the panel's own children: freed together with the panel.
	_resume_button.pressed.connect(_on_resume_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_title_button.pressed.connect(_on_title_pressed)
	_resume_button.grab_focus()


## While the settings screen is in front, Esc is its key.
func _takes_escape() -> bool:
	return not has_overlay()


func _can_act() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and not _closing and not has_overlay()


func _on_resume_pressed() -> void:
	if not _can_act():
		return
	close()


func _on_settings_pressed() -> void:
	if not _can_act():
		return
	# The settings screen emits closed and frees itself (08 design, section 4).
	# The layer notices when it has left the tree.
	var settings_screen: Control = SETTINGS_SCENE.instantiate() as Control
	_overlay_layer.call(&"open", settings_screen)


func _on_title_pressed() -> void:
	if not _can_act():
		return
	title_requested.emit()
	close()
