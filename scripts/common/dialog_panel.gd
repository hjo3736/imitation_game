extends "res://scripts/common/closable_panel.gd"
## A question or a notice that opens over a screen.
##
## Call setup() before adding it to the tree.
##   - A question has two buttons. The first one emits accepted and closes;
##     the second one, and Esc, only close.
##   - A notice has one button that closes.
## accepted is emitted at most once, before closed.

const UiStyle: GDScript = preload("res://scripts/common/ui_style.gd")

## Emitted once when the first button of a question is pressed.
signal accepted

var _message: String = ""
var _accept_text: String = ""
var _close_text: String = ""

@onready var _dim: ColorRect = %Dim
@onready var _message_label: Label = %Message
@onready var _accept_button: Button = %AcceptButton
@onready var _close_button: Button = %CloseButton


## The text to show, the text of the accepting button ("" for a notice) and
## the text of the button that only closes.
func setup(message: String, accept_text: String, close_text: String) -> void:
	_message = message
	_accept_text = accept_text
	_close_text = close_text


func _ready() -> void:
	theme = UiStyle.make_panel_theme()
	_dim.color = UiStyle.COLOR_DIM
	_message_label.text = _message
	_accept_button.text = _accept_text
	_accept_button.visible = _accept_text != ""
	_close_button.text = _close_text
	_accept_button.custom_minimum_size = UiStyle.PANEL_BUTTON_MIN_SIZE
	_close_button.custom_minimum_size = UiStyle.PANEL_BUTTON_MIN_SIZE
	# Connections to the panel's own children: freed together with the panel.
	_accept_button.pressed.connect(_on_accept_pressed)
	_close_button.pressed.connect(_on_close_pressed)
	# The harmless choice has the focus.
	_close_button.grab_focus()


func _on_accept_pressed() -> void:
	if _closing or not _accept_button.visible:
		return
	accepted.emit()
	close()


func _on_close_pressed() -> void:
	close()
