extends Control
## The layer of a screen that holds a panel opened over it (docs/roles/leader/outputs/10
## design 5.1; docs/roles/leader/outputs/13 design 8.2, rule 7).
##
##   - One panel at a time: open() refuses while one is open or closing.
##   - While a panel is open, what is behind it takes neither the mouse nor
##     the keyboard focus. Set what is behind with set_blocked().
##   - The panel frees itself (or is thrown away with discard()). When it has
##     left the tree the layer forgets it, unlocks what is behind and gives the
##     focus back to where it was.
##
## The same handling exists in scripts/title/title_screen.gd for the title
## screen's own panels.

## Emitted after the panel has left the tree and the layer is free again.
## The layer is still busy removing the panel when this is emitted: a handler
## that wants to open another panel must do so with call_deferred.
signal overlay_gone

var _blocked: Control = null
var _overlay: Control = null
var _focus_before: Control = null


## The control (with everything under it) that is locked while a panel is open.
func set_blocked(blocked: Control) -> void:
	_blocked = blocked


## True while a panel is open, and until a closing one has left the tree.
func has_overlay() -> bool:
	return _overlay != null


## The open panel, or null. Do not keep it.
func get_overlay() -> Control:
	return _overlay


## Opens the panel over the screen. Returns false, and frees the panel, when
## another one is open or the layer is not in the tree.
func open(overlay: Control) -> bool:
	if overlay == null:
		return false
	if _overlay != null or not is_inside_tree() or is_queued_for_deletion():
		overlay.free()
		return false
	_overlay = overlay
	_focus_before = get_viewport().gui_get_focus_owner()
	# One-shot: the connection is gone once the signal has been emitted.
	overlay.tree_exited.connect(_on_overlay_tree_exited, CONNECT_ONE_SHOT)
	_set_locked(true)
	add_child(overlay)
	_focus_inside(overlay)
	return true


## Throws the open panel away without waiting for it to close itself.
func discard() -> void:
	if _overlay != null and is_instance_valid(_overlay) and not _overlay.is_queued_for_deletion():
		_overlay.queue_free()


func _exit_tree() -> void:
	# Normally the panel has left the tree before the layer does and the
	# connection is gone. This covers a panel that is not under the layer.
	if _overlay != null and is_instance_valid(_overlay):
		if _overlay.tree_exited.is_connected(_on_overlay_tree_exited):
			_overlay.tree_exited.disconnect(_on_overlay_tree_exited)
	_overlay = null
	_focus_before = null


## The panel has left the tree. Nothing here touches the panel itself.
func _on_overlay_tree_exited() -> void:
	var focus_before: Control = _focus_before
	_overlay = null
	_focus_before = null
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_set_locked(false)
	if focus_before != null and is_instance_valid(focus_before) and focus_before.is_inside_tree() \
			and not focus_before.is_queued_for_deletion() \
			and focus_before.get_focus_mode_with_override() != Control.FOCUS_NONE:
		focus_before.grab_focus()
	overlay_gone.emit()


func _set_locked(locked: bool) -> void:
	if _blocked == null or not is_instance_valid(_blocked):
		return
	if locked:
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused != null and (focused == _blocked or _blocked.is_ancestor_of(focused)):
			focused.release_focus()
		_blocked.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
		_blocked.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	else:
		_blocked.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
		_blocked.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED


## Puts the keyboard focus inside the panel, unless the panel took it itself.
func _focus_inside(overlay: Control) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and overlay.is_ancestor_of(focused):
		return
	var first: Control = overlay.find_next_valid_focus()
	if first != null and overlay.is_ancestor_of(first):
		first.grab_focus()
