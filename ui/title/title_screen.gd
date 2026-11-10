extends Control
## Title screen with the main menu (docs/leader/10 design).
##
## Menu, top to bottom: new game, continue, settings, credits, quit.
## The settings screen, the credits panel and the "not ready yet" notice open
## over this screen, one at a time (10 design, 5.1). Each of them is created
## when it opens, emits closed when it closes and frees itself. This screen
## keeps no reference to a closed one.
##
## "New game" and "continue" are placeholders: there is no game and no save
## data yet. They only emit new_game_requested and continue_requested.

const TitleStyle: GDScript = preload("res://ui/title/title_style.gd")

## Emitted when "new game" is chosen.
signal new_game_requested
## Emitted when "continue" is chosen. Only possible after
## set_continue_enabled(true).
signal continue_requested

const SETTINGS_SCENE: PackedScene = preload("res://ui/settings/settings_screen.tscn")
const CREDITS_SCENE: PackedScene = preload("res://ui/title/credits_panel.tscn")
const NOTICE_SCENE: PackedScene = preload("res://ui/title/notice_panel.tscn")
## Every overlay must have this signal (08 design section 4 for the settings
## screen; ui/title/overlay_panel.gd for the others).
const OVERLAY_CLOSED_SIGNAL: StringName = &"closed"

var _continue_enabled: bool = false
var _quit_requested: bool = false
## The overlay that is open now, or null. Cleared when it leaves the tree.
var _overlay: Control = null
## True from the overlay's closed signal until the overlay has left the tree.
var _overlay_closed: bool = false
## The menu button that opened the overlay. Focus returns to it.
var _overlay_opener: Button = null

@onready var _background: ColorRect = %Background
@onready var _content: VBoxContainer = %Content
@onready var _title: Label = %Title
@onready var _menu: VBoxContainer = %Menu
@onready var _new_game_button: Button = %NewGameButton
@onready var _continue_button: Button = %ContinueButton
@onready var _settings_button: Button = %SettingsButton
@onready var _credits_button: Button = %CreditsButton
@onready var _quit_button: Button = %QuitButton
@onready var _overlay_layer: Control = %OverlayLayer


## Makes "continue" pressable or not. It starts not pressable, because there is
## no save data yet. Whoever owns the save data calls this later.
func set_continue_enabled(enabled: bool) -> void:
	_continue_enabled = enabled
	if is_node_ready():
		_apply_continue_enabled()


## True while a settings screen, a credits panel or a notice is open.
func has_overlay() -> bool:
	return _overlay != null


func _ready() -> void:
	_apply_style()
	# Connections to the screen's own children: freed together with the screen.
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_credits_button.pressed.connect(_on_credits_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_apply_continue_enabled()
	_focus_menu(null)


func _exit_tree() -> void:
	# Normally the overlay has already left the tree and both connections are
	# gone. This covers an overlay that somehow outlives its place in the tree.
	_disconnect_overlay()


# --- Hook that tests override ------------------------------------------------

func _quit_game() -> void:
	get_tree().quit()


# --- Menu --------------------------------------------------------------------

## False while an overlay is open or closing, after quit was chosen, and while
## the screen is not in the tree. Every menu handler checks this first, so
## pressing a button several times in one frame is handled once (rule 8).
func _can_act() -> bool:
	return is_inside_tree() and _overlay == null and not _quit_requested


func _on_new_game_pressed() -> void:
	if not _can_act():
		return
	new_game_requested.emit()
	_open_overlay(NOTICE_SCENE, _new_game_button)


func _on_continue_pressed() -> void:
	if not _can_act() or not _continue_enabled:
		return
	continue_requested.emit()


func _on_settings_pressed() -> void:
	_open_overlay(SETTINGS_SCENE, _settings_button)


func _on_credits_pressed() -> void:
	_open_overlay(CREDITS_SCENE, _credits_button)


func _on_quit_pressed() -> void:
	if not _can_act():
		return
	_quit_requested = true
	_set_menu_locked(true)
	_quit_game()


func _apply_continue_enabled() -> void:
	_continue_button.disabled = not _continue_enabled
	# A button that cannot be pressed is skipped by the keyboard as well.
	_continue_button.focus_mode = Control.FOCUS_ALL if _continue_enabled else Control.FOCUS_NONE


## Keeps mouse and keyboard away from the menu while an overlay is open
## (rule 2), and after quit was chosen.
func _set_menu_locked(locked: bool) -> void:
	if locked:
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused != null and _menu.is_ancestor_of(focused):
			focused.release_focus()
		_menu.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
		_menu.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	else:
		_menu.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
		_menu.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED


## Gives the focus to the given button, or to the first pressable menu item
## (rule 15).
func _focus_menu(preferred: Button) -> void:
	if preferred != null and not preferred.disabled and preferred.focus_mode != Control.FOCUS_NONE:
		preferred.grab_focus()
		return
	for button: Button in [_new_game_button, _continue_button, _settings_button, _credits_button, _quit_button]:
		if not button.disabled and button.focus_mode != Control.FOCUS_NONE:
			button.grab_focus()
			return


# --- Overlays ----------------------------------------------------------------

func _open_overlay(scene: PackedScene, opener: Button) -> void:
	if not _can_act():
		return
	var overlay: Control = scene.instantiate() as Control
	if overlay == null or not overlay.has_signal(OVERLAY_CLOSED_SIGNAL):
		push_error("TitleScreen: '%s' cannot be opened over the title screen: it must be a Control with the signal '%s'." % [scene.resource_path, OVERLAY_CLOSED_SIGNAL])
		if overlay != null:
			overlay.free()
		return
	_overlay = overlay
	_overlay_closed = false
	_overlay_opener = opener
	# One-shot: each connection is gone as soon as its signal has been emitted.
	overlay.connect(OVERLAY_CLOSED_SIGNAL, _on_overlay_closed, CONNECT_ONE_SHOT)
	overlay.tree_exited.connect(_on_overlay_tree_exited, CONNECT_ONE_SHOT)
	_set_menu_locked(true)
	_overlay_layer.add_child(overlay)
	_focus_overlay(overlay)


## Puts the keyboard focus inside the overlay, unless the overlay has already
## taken it.
func _focus_overlay(overlay: Control) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and overlay.is_ancestor_of(focused):
		return
	var first: Control = overlay.find_next_valid_focus()
	if first != null and overlay.is_ancestor_of(first):
		first.grab_focus()


## The overlay says it is closing. It frees itself; the menu stays locked until
## it has really left the tree, so input in that frame cannot reach the menu
## or the overlay that is going away (rule 10).
func _on_overlay_closed() -> void:
	_overlay_closed = true


## The overlay has left the tree. Nothing here touches the overlay itself.
func _on_overlay_tree_exited() -> void:
	if not _overlay_closed and is_instance_valid(_overlay) and not _overlay.is_queued_for_deletion():
		# It was taken out of the tree without closing and is not being freed.
		# Do not leave the closed connection behind.
		_disconnect_overlay()
	var opener: Button = _overlay_opener
	_overlay = null
	_overlay_closed = false
	_overlay_opener = null
	if _quit_requested or not is_inside_tree() or is_queued_for_deletion():
		return
	_set_menu_locked(false)
	_focus_menu(opener)


func _disconnect_overlay() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if _overlay.is_connected(OVERLAY_CLOSED_SIGNAL, _on_overlay_closed):
		_overlay.disconnect(OVERLAY_CLOSED_SIGNAL, _on_overlay_closed)
	if _overlay.tree_exited.is_connected(_on_overlay_tree_exited):
		_overlay.tree_exited.disconnect(_on_overlay_tree_exited)


# --- Temporary look ----------------------------------------------------------

func _apply_style() -> void:
	_background.color = TitleStyle.COLOR_BACKGROUND
	# The theme sits on the content, not on the root, so that it does not reach
	# the overlays: the settings screen brings its own look.
	_content.theme = TitleStyle.make_menu_theme()
	_content.add_theme_constant_override(&"separation", TitleStyle.TITLE_MENU_SEPARATION)
	_title.add_theme_font_size_override(&"font_size", TitleStyle.GAME_TITLE_FONT_SIZE)
	for button: Button in [_new_game_button, _continue_button, _settings_button, _credits_button, _quit_button]:
		button.custom_minimum_size = TitleStyle.MENU_BUTTON_MIN_SIZE
