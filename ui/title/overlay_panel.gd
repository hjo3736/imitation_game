extends Control
## A panel that opens over the title screen (docs/leader/10 design, 5.1).
##
## It closes with its close button or Esc. Closing emits closed once and frees
## the panel, the same way the settings screen does. When the panel is the root
## of the running scene, closing quits the game instead.
##
## The notice panel uses this script as it is. The credits panel extends it.

const TitleStyle: GDScript = preload("res://ui/title/title_style.gd")

## Emitted once when the panel closes, right before it frees itself.
signal closed

var _closing: bool = false

@onready var _dim: ColorRect = %Dim
@onready var _close_button: Button = %CloseButton


## Emits closed and frees the panel. Runs only once.
func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	if is_inside_tree() and get_tree().current_scene == self:
		get_tree().quit()
	else:
		queue_free()


func _ready() -> void:
	theme = TitleStyle.make_panel_theme()
	_dim.color = TitleStyle.COLOR_DIM
	_close_button.custom_minimum_size = TitleStyle.PANEL_BUTTON_MIN_SIZE
	# A connection to the panel's own child: freed together with the panel.
	_close_button.pressed.connect(_on_close_pressed)
	_close_button.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_ESCAPE:
		return
	get_viewport().set_input_as_handled()
	close()


func _on_close_pressed() -> void:
	close()
