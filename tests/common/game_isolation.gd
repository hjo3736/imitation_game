extends RefCounted
## Keeps a test run away from the player's save file and settings file
## (docs/roles/leader/outputs/13 design, 7.5, and 11 design, section 3).
##
## A test that runs with the autoload "Game" calls begin() first and finish()
## last. The settings side is left to tests/common/settings_isolation.gd.
## Only the contracts of Game and Settings are used.
##
##   begin()   false when the run is not isolated; the caller must then stop
##             without doing anything else and exit with a failure.
##   finish()  ends a game that is still in progress, removes the test save
##             file and the test settings file, and reports whether the
##             player's files are the same as when the run began.

const SettingsIsolation: GDScript = preload("res://tests/common/settings_isolation.gd")

const DEFAULT_SAVE_PATH: String = "user://save.json"
const SAVE_ARGUMENT: String = "--save-path="
const SUGGESTED_SAVE_PATH: String = "user://test_save.json"
const TEMPORARY_SUFFIX: String = ".tmp"

static var _real_save_state: String = ""


## The command line that runs a scene isolated.
static func command(scene_path: String, headless: bool, extra_arguments: String = "") -> String:
	var text: String = "godot %s--path . %s -- %s%s %s%s" % [
		"--headless " if headless else "", scene_path,
		SettingsIsolation.ARGUMENT, SettingsIsolation.SUGGESTED_PATH, SAVE_ARGUMENT, SUGGESTED_SAVE_PATH]
	if extra_arguments != "":
		text += " " + extra_arguments
	return text


## Call first. Prints what is wrong and returns false when the run would use
## the player's save file or settings file. Otherwise removes a test save file
## that an earlier run left behind, unless keep_existing_save is set (a check
## that continues from what the run before it saved).
static func begin(tree: SceneTree, tag: String, scene_path: String, headless: bool, extra_arguments: String = "", keep_existing_save: bool = false) -> bool:
	var game: Node = tree.root.get_node_or_null("Game")
	var settings: Node = tree.root.get_node_or_null("Settings")
	var problems: PackedStringArray = PackedStringArray()
	if game == null or not game.has_method(&"get_save_path"):
		problems.append("the autoload Game with get_save_path() was not found")
	elif game.call(&"get_save_path") == DEFAULT_SAVE_PATH:
		problems.append("this run would use the player's save file (%s)" % DEFAULT_SAVE_PATH)
	if settings == null or not settings.has_method(&"get_storage_path"):
		problems.append("the autoload Settings with get_storage_path() was not found")
	elif settings.call(&"get_storage_path") == SettingsIsolation.DEFAULT_PATH:
		problems.append("this run would use the player's settings file (%s)" % SettingsIsolation.DEFAULT_PATH)
	if not problems.is_empty():
		for problem: String in problems:
			print("[%s] NOT ISOLATED: %s." % [tag, problem])
		print("[%s] Nothing was done. Run it like this instead:" % tag)
		print("[%s]   %s" % [tag, command(scene_path, headless, extra_arguments)])
		return false
	if not SettingsIsolation.begin(tree, tag, scene_path, headless, extra_arguments):
		return false
	var save_path: String = game.call(&"get_save_path")
	_real_save_state = SettingsIsolation.file_state(DEFAULT_SAVE_PATH)
	print("[%s] save file for this run: %s (player's file: %s)" % [tag, save_path, _real_save_state])
	if not keep_existing_save:
		if FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + TEMPORARY_SUFFIX):
			print("[%s] a test save file was left by an earlier run; removed" % tag)
		remove_test_save(tree)
	return true


## Call last. Returns true when the test files are gone and the player's save
## file and settings file are the same as at begin(). With keep_save the test
## save file is left for the run that continues from it.
static func finish(tree: SceneTree, tag: String, keep_save: bool = false) -> bool:
	var game: Node = tree.root.get_node_or_null("Game")
	if game == null or not game.has_method(&"get_save_path"):
		return false
	var save_path: String = game.call(&"get_save_path")
	if save_path == DEFAULT_SAVE_PATH:
		return false
	if not keep_save:
		if game.get(&"core") != null:
			game.call(&"end_game")
		remove_test_save(tree)
	var state_now: String = SettingsIsolation.file_state(DEFAULT_SAVE_PATH)
	var untouched: bool = state_now == _real_save_state
	print("[%s] test save file exists: %s; player's file: %s%s" % [
		tag, str(FileAccess.file_exists(save_path)), state_now, "" if untouched else " (CHANGED, was %s)" % _real_save_state])
	var settings_ok: bool = SettingsIsolation.finish(tree, tag)
	return settings_ok and untouched and (keep_save or not FileAccess.file_exists(save_path))


## Removes the test save file and its temporary file. Does nothing when the
## run is not isolated.
static func remove_test_save(tree: SceneTree) -> void:
	var game: Node = tree.root.get_node_or_null("Game")
	if game == null or not game.has_method(&"get_save_path"):
		return
	var save_path: String = game.call(&"get_save_path")
	if save_path == DEFAULT_SAVE_PATH:
		return
	for path: String in [save_path, save_path + TEMPORARY_SUFFIX]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
