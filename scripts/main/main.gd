extends Control
## Screen host: the main scene of the game (docs/roles/leader/outputs/13 design, section 6).
##
## It keeps one screen as a child and swaps it. Which screen is shown follows
## the state of the game:
##   no game in progress            -> title screen
##   game in progress, &"playing"   -> workshop
##   game in progress, &"summary"   -> day summary
## The host reacts to Game.game_started / game_ended and to the core's
## day_ended / day_started by bringing the shown screen in line with that.
##
## The host starts and ends games (new_game, continue_game, end_game). The
## screens send commands to the core themselves. Nobody here saves: Game does.
##
## By default the game object is the autoload "Game". Call set_game() before
## adding the host to the tree to use another object (tests do this).

const GameAccess: GDScript = preload("res://scripts/common/game_access.gd")
const UiStyle: GDScript = preload("res://scripts/common/ui_style.gd")
const UiText: GDScript = preload("res://scripts/common/ui_text.gd")

const TITLE_SCENE: PackedScene = preload("res://scenes/title/title_screen.tscn")
const WORKSHOP_SCENE: PackedScene = preload("res://scenes/workshop/workshop_screen.tscn")
const DAY_SUMMARY_SCENE: PackedScene = preload("res://scenes/day/day_summary_screen.tscn")
const DIALOG_SCENE: PackedScene = preload("res://scenes/common/dialog_panel.tscn")

const KIND_NONE: StringName = &""
const KIND_TITLE: StringName = &"title"
const KIND_WORKSHOP: StringName = &"workshop"
const KIND_DAY_SUMMARY: StringName = &"day_summary"

# --- Contract (docs/roles/leader/outputs/13 design, section 5) ------------------------------
const PHASE_SUMMARY: String = "summary"
const BLOCK_TRANSITION: StringName = &"transition"
const SIGNAL_GAME_STARTED: StringName = &"game_started"
const SIGNAL_GAME_ENDED: StringName = &"game_ended"
const SIGNAL_DAY_ENDED: StringName = &"day_ended"
const SIGNAL_DAY_STARTED: StringName = &"day_started"

var _game: Object = null
var _game_ready: bool = false
## The core whose signals the host is connected to. A weak reference: the host
## must not keep a game alive (13 design 8.2, rule 5).
var _connected_core: WeakRef = null

## The shown screen, or null while one screen is going and the next is not yet
## there.
var _screen: Control = null
var _screen_kind: StringName = KIND_NONE
var _transitioning: bool = false
## Set when a game starts: the next screen is made anew even when a screen of
## the same kind is shown.
var _force_new_screen: bool = false
## A notice to show as soon as the panel in front has left the tree.
var _pending_notice: String = ""

@onready var _background: ColorRect = %Background
@onready var _screen_holder: Control = %ScreenHolder
@onready var _overlay_layer: Control = %OverlayLayer


## Sets the game object to use instead of the autoload "Game".
## Must be called before the host enters the tree.
func set_game(game: Object) -> void:
	if is_inside_tree():
		push_error("Main.set_game(): 트리에 들어간 뒤에는 게임 객체를 바꿀 수 없습니다.")
		return
	_game = game


## The kind of the shown screen: &"title", &"workshop", &"day_summary", or &""
## while the screen is being swapped.
func get_screen_kind() -> StringName:
	return _screen_kind


## The shown screen, or null while the screen is being swapped. Do not keep it.
func get_screen() -> Control:
	return _screen


## True from the moment the old screen is sent away until the new one is shown.
func is_transitioning() -> bool:
	return _transitioning


func _enter_tree() -> void:
	_game = GameAccess.resolve(self, _game, "Main")
	_game_ready = _game != null
	if not _game_ready:
		return
	if not _game.is_connected(SIGNAL_GAME_STARTED, _on_game_started):
		_game.connect(SIGNAL_GAME_STARTED, _on_game_started)
	if not _game.is_connected(SIGNAL_GAME_ENDED, _on_game_ended):
		_game.connect(SIGNAL_GAME_ENDED, _on_game_ended)
	_connect_core()
	if is_node_ready():
		_sync_screen()


func _exit_tree() -> void:
	_disconnect_core()
	if _has_game():
		if _game.is_connected(SIGNAL_GAME_STARTED, _on_game_started):
			_game.disconnect(SIGNAL_GAME_STARTED, _on_game_started)
		if _game.is_connected(SIGNAL_GAME_ENDED, _on_game_ended):
			_game.disconnect(SIGNAL_GAME_ENDED, _on_game_ended)
	if _transitioning:
		# The swap will not be finished. Do not leave the clock stopped.
		_transitioning = false
		_set_transition_blocked(false)


func _ready() -> void:
	_background.color = UiStyle.COLOR_BACKGROUND
	_overlay_layer.call(&"set_blocked", _screen_holder)
	_overlay_layer.connect(&"overlay_gone", _on_overlay_gone)
	_sync_screen()


func _has_game() -> bool:
	return _game_ready and _game != null and is_instance_valid(_game)


# --- Game and core signals ---------------------------------------------------

func _on_game_started() -> void:
	_connect_core()
	_force_new_screen = true
	_sync_screen()


func _on_game_ended() -> void:
	_disconnect_core()
	_sync_screen()


## Can come whatever the screen is doing (13 design 8.3, rule 12). The workshop
## is replaced, and the panels open over it go with it.
func _on_day_ended(_summary: Dictionary) -> void:
	_sync_screen()


func _on_day_started(_day: int) -> void:
	_sync_screen()


## Connects to the core of the game in progress, after letting go of the core
## of the game before it.
func _connect_core() -> void:
	_disconnect_core()
	var core: Object = GameAccess.core_of(_game) if _has_game() else null
	if core == null:
		return
	var missing: PackedStringArray = PackedStringArray()
	for signal_name: StringName in [SIGNAL_DAY_ENDED, SIGNAL_DAY_STARTED]:
		if not core.has_signal(signal_name):
			missing.append("signal " + String(signal_name))
	if not missing.is_empty():
		push_error("Main: 코어가 계약을 따르지 않습니다. 없는 것: %s" % ", ".join(missing))
		return
	core.connect(SIGNAL_DAY_ENDED, _on_day_ended)
	core.connect(SIGNAL_DAY_STARTED, _on_day_started)
	_connected_core = weakref(core)


func _disconnect_core() -> void:
	if _connected_core == null:
		return
	var core: Object = _connected_core.get_ref()
	_connected_core = null
	if core == null or not is_instance_valid(core):
		return
	if core.is_connected(SIGNAL_DAY_ENDED, _on_day_ended):
		core.disconnect(SIGNAL_DAY_ENDED, _on_day_ended)
	if core.is_connected(SIGNAL_DAY_STARTED, _on_day_started):
		core.disconnect(SIGNAL_DAY_STARTED, _on_day_started)


# --- Which screen ------------------------------------------------------------

func _wanted_kind() -> StringName:
	var state: Object = GameAccess.state_of(_game) if _has_game() else null
	if state == null:
		return KIND_TITLE
	if str(state.get(&"phase")) == PHASE_SUMMARY:
		return KIND_DAY_SUMMARY
	return KIND_WORKSHOP


## Brings the shown screen in line with the state of the game. Does nothing
## while a swap is under way: the swap looks at the state again when it ends.
func _sync_screen() -> void:
	if _transitioning or not is_inside_tree():
		return
	if _screen != null and not _force_new_screen and _screen_kind == _wanted_kind():
		return
	_begin_transition()


# --- Swapping the screen (13 design 8.2 rule 6; 8.3 rules 10 and 11) ---------
# The old screen is sent away first and the new one is made only after the old
# one has left the tree. In between there is no screen that could take input,
# and the clock is stopped with the reason &"transition".

func _begin_transition() -> void:
	_transitioning = true
	_set_transition_blocked(true)
	_pending_notice = ""
	_overlay_layer.call(&"discard")
	if _screen == null:
		_finish_transition()
		return
	var old_screen: Control = _screen
	_screen = null
	_screen_kind = KIND_NONE
	_disconnect_screen(old_screen)
	# One-shot: the connection is gone once the signal has been emitted.
	old_screen.tree_exited.connect(_on_old_screen_tree_exited, CONNECT_ONE_SHOT)
	old_screen.queue_free()


## The old screen has left the tree. Nothing here touches it. The holder is
## still busy removing it, so the new screen is added a moment later.
func _on_old_screen_tree_exited() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_finish_transition.call_deferred()


func _finish_transition() -> void:
	if not _transitioning:
		return
	if not is_inside_tree():
		# _exit_tree has already unblocked the clock.
		return
	_force_new_screen = false
	var kind: StringName = _wanted_kind()
	var screen: Control = _make_screen(kind)
	if screen != null:
		_screen = screen
		_screen_kind = kind
		_screen_holder.add_child(screen)
	# Whether or not the screen could be made, the swap is over.
	_transitioning = false
	_set_transition_blocked(false)
	if screen == null:
		push_error("Main: '%s' 화면을 만들지 못했습니다." % kind)
		return
	# The state may have moved on while the old screen was going away.
	_sync_screen()


func _make_screen(kind: StringName) -> Control:
	var scene: PackedScene = null
	match kind:
		KIND_TITLE:
			scene = TITLE_SCENE
		KIND_WORKSHOP:
			scene = WORKSHOP_SCENE
		KIND_DAY_SUMMARY:
			scene = DAY_SUMMARY_SCENE
	if scene == null:
		return null
	var screen: Control = scene.instantiate() as Control
	if screen == null:
		return null
	if screen.has_method(&"set_game") and _has_game():
		screen.call(&"set_game", _game)
	match kind:
		KIND_TITLE:
			screen.call(&"set_continue_enabled", _has_save())
			screen.connect(&"new_game_requested", _on_new_game_requested)
			screen.connect(&"continue_requested", _on_continue_requested)
		KIND_WORKSHOP:
			screen.connect(&"title_requested", _on_title_requested)
	return screen


## The host stops listening to a screen as soon as it sends it away.
func _disconnect_screen(screen: Control) -> void:
	for pair: Array in [
		[&"new_game_requested", _on_new_game_requested],
		[&"continue_requested", _on_continue_requested],
		[&"title_requested", _on_title_requested],
	]:
		var signal_name: StringName = pair[0]
		var handler: Callable = pair[1]
		if screen.has_signal(signal_name) and screen.is_connected(signal_name, handler):
			screen.disconnect(signal_name, handler)


func _set_transition_blocked(blocked: bool) -> void:
	if _has_game():
		_game.set_time_blocked(BLOCK_TRANSITION, blocked)


# --- Requests from the screens -----------------------------------------------

## False while the screen is being swapped and while a question or a notice is
## open or closing. Every request checks this first, so a request repeated in
## one frame is handled once (13 design 8.3, rule 10).
func _can_take_request(kind: StringName) -> bool:
	return is_inside_tree() and not _transitioning and _screen != null and _screen_kind == kind \
			and not _overlay_layer.call(&"has_overlay")


func _has_save() -> bool:
	return _has_game() and _game.has_save() == true


func _on_new_game_requested() -> void:
	if not _can_take_request(KIND_TITLE):
		return
	if _has_save():
		var question: Control = DIALOG_SCENE.instantiate()
		question.call(&"setup", UiText.NEW_GAME_CONFIRM, UiText.BUTTON_CONFIRM, UiText.BUTTON_CANCEL)
		# A connection to a panel under the host: freed together with it.
		question.connect(&"accepted", _on_new_game_confirmed)
		_overlay_layer.call(&"open", question)
		return
	_start_new_game()


func _on_new_game_confirmed() -> void:
	if _transitioning or _screen_kind != KIND_TITLE:
		return
	_start_new_game()


func _start_new_game() -> void:
	# On success Game emits game_started and the host goes to the workshop.
	if not _has_game() or _game.new_game() != true:
		_show_notice(UiText.NEW_GAME_FAILED)


func _on_continue_requested() -> void:
	if not _can_take_request(KIND_TITLE):
		return
	# On success Game emits game_started and the host goes to the workshop, or
	# to the day summary when the saved game was at one.
	if not _has_game() or _game.continue_game() != true:
		_show_notice(UiText.CONTINUE_FAILED)


func _on_title_requested() -> void:
	if not _can_take_request(KIND_WORKSHOP):
		return
	# Game saves, lets the game go and emits game_ended; the host then goes to
	# the title screen.
	if _has_game():
		_game.end_game()


# --- Notices -----------------------------------------------------------------

## Shows a notice over the title screen. When a question is still closing, the
## notice waits until it has left the tree.
func _show_notice(message: String) -> void:
	if _overlay_layer.call(&"has_overlay"):
		_pending_notice = message
		return
	_open_notice(message)


func _open_notice(message: String) -> void:
	if not is_inside_tree() or _transitioning or _overlay_layer.call(&"has_overlay"):
		return
	var notice: Control = DIALOG_SCENE.instantiate()
	notice.call(&"setup", message, "", UiText.BUTTON_CLOSE)
	_overlay_layer.call(&"open", notice)


func _on_overlay_gone() -> void:
	# The saved game may be gone or new after what the panel was about.
	if _screen != null and _screen_kind == KIND_TITLE and not _transitioning:
		_screen.call(&"set_continue_enabled", _has_save())
	if _pending_notice != "":
		var message: String = _pending_notice
		_pending_notice = ""
		# The layer is still busy removing the old panel.
		_open_notice.call_deferred(message)
