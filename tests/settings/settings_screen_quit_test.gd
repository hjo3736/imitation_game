extends Node
## Headless test: a settings screen that is the root of the running scene quits
## the game when it closes (docs/leader/08 work order, 3.1).
##
## Run:
##   godot --headless --path . res://tests/settings/settings_screen_quit_test.tscn -- --settings-path=user://test_settings.cfg
## Exit code 0 means the screen quit the game after flushing and emitting
## closed. Exit code 1 means it did not, or the run was not isolated from the
## player's settings file (docs/leader/11 design, section 3).

const SCREEN_SCENE: PackedScene = preload("res://scenes/settings/settings_screen.tscn")
const FakeSettings: GDScript = preload("res://tests/settings/fake_settings.gd")
const Isolation: GDScript = preload("res://tests/common/settings_isolation.gd")

const SCENE_PATH: String = "res://tests/settings/settings_screen_quit_test.tscn"
const TAG: String = "settings_screen_quit_test"

const WAIT_FRAMES: int = 30

var _fake: Node = null
var _closed_count: int = 0
var _frames_left: int = -1


func _ready() -> void:
	_start.call_deferred()


func _start() -> void:
	if not Isolation.begin(get_tree(), TAG, SCENE_PATH, true):
		get_tree().quit(1)
		return
	_fake = FakeSettings.new()
	var screen: Control = SCREEN_SCENE.instantiate()
	screen.set_settings(_fake)
	screen.closed.connect(_on_screen_closed)
	var tree: SceneTree = get_tree()
	tree.root.add_child(screen)
	# Make the screen the root of the running scene, as when it runs alone.
	tree.current_scene = screen
	screen.close()
	print("[settings_screen_quit_test] flush=%d closed=%d queued_for_deletion=%s" % [
		_fake.flush_count, _closed_count, screen.is_queued_for_deletion(),
	])
	if _fake.flush_count != 1 or _closed_count != 1:
		print("[settings_screen_quit_test] FAILED: flush or closed was not handled once")
		_fake.free()
		tree.quit(1)
		return
	if not Isolation.finish(tree, TAG):
		print("[settings_screen_quit_test] FAILED: the player's settings file changed or the test settings file is still there")
		tree.quit(1)
		return
	# close() asked the tree to quit with code 0. If the game is still running
	# after WAIT_FRAMES, the screen did not quit it.
	_frames_left = WAIT_FRAMES
	print("[settings_screen_quit_test] PASSED if the exit code is 0")


func _process(_delta: float) -> void:
	if _frames_left < 0:
		return
	_frames_left -= 1
	if _frames_left == 0:
		print("[settings_screen_quit_test] FAILED: the game is still running")
		get_tree().quit(1)


func _exit_tree() -> void:
	if _fake != null and is_instance_valid(_fake):
		_fake.free()


func _on_screen_closed() -> void:
	_closed_count += 1
