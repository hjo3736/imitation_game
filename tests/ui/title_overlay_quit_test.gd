extends Node
## Headless test: a credits panel that is the root of the running scene quits
## the game when it closes, the same way the settings screen does
## (docs/leader/10 work order, 3.2).
##
## Run:
##   godot --headless --path . res://tests/ui/title_overlay_quit_test.tscn -- --settings-path=user://test_settings.cfg
## Exit code 0 means the panel emitted closed once and quit the game.
## Exit code 1 means it did not, or the run was not isolated from the player's
## settings file (docs/leader/11 design, section 3).

const CREDITS_SCENE: PackedScene = preload("res://ui/title/credits_panel.tscn")
const Isolation: GDScript = preload("res://tests/app/settings_isolation.gd")

const SCENE_PATH: String = "res://tests/ui/title_overlay_quit_test.tscn"
const TAG: String = "title_overlay_quit_test"

const WAIT_FRAMES: int = 30

var _closed_count: int = 0
var _frames_left: int = -1


func _ready() -> void:
	_start.call_deferred()


func _start() -> void:
	var tree: SceneTree = get_tree()
	if not Isolation.begin(tree, TAG, SCENE_PATH, true):
		tree.quit(1)
		return
	var panel: Control = CREDITS_SCENE.instantiate()
	panel.connect(&"closed", _on_panel_closed)
	tree.root.add_child(panel)
	# Make the panel the root of the running scene, as when it runs alone.
	tree.current_scene = panel
	panel.call(&"close")
	panel.call(&"close")
	print("[title_overlay_quit_test] closed=%d queued_for_deletion=%s" % [_closed_count, panel.is_queued_for_deletion()])
	if _closed_count != 1:
		print("[title_overlay_quit_test] FAILED: closed was not emitted once")
		tree.quit(1)
		return
	if not Isolation.finish(tree, TAG):
		print("[title_overlay_quit_test] FAILED: the player's settings file changed or the test settings file is still there")
		tree.quit(1)
		return
	# close() asked the tree to quit with code 0. If the game is still running
	# after WAIT_FRAMES, the panel did not quit it.
	_frames_left = WAIT_FRAMES
	print("[title_overlay_quit_test] PASSED if the exit code is 0")


func _process(_delta: float) -> void:
	if _frames_left < 0:
		return
	_frames_left -= 1
	if _frames_left == 0:
		print("[title_overlay_quit_test] FAILED: the game is still running")
		get_tree().quit(1)


func _on_panel_closed() -> void:
	_closed_count += 1
