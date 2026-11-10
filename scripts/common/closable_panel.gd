extends Control
## Base of the panels that open over a screen: the question and notice panel
## and the pause panel.
##
## A panel closes with close() or Esc. Closing emits closed once and frees the
## panel, the same way the settings screen does. When the panel is the root of
## the running scene, closing quits the game instead.

## Emitted once when the panel closes, right before it frees itself.
signal closed

var _closing: bool = false


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


## True once close() has run.
func is_closing() -> bool:
	return _closing


## False while a panel that this panel opened over itself is in front; that
## panel takes Esc then. Panels that open nothing keep this as it is.
func _takes_escape() -> bool:
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_ESCAPE or not _takes_escape():
		return
	# Also while closing: the key belongs to this panel, not to what is behind.
	get_viewport().set_input_as_handled()
	close()
