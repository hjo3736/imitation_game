extends RefCounted
## Keeps a test run away from the player's settings file
## (docs/leader/11 design, section 3, rules 5 to 7).
##
## Every test and check scene in tests/app/ and tests/ui/ calls begin() first.
## It only uses the contract of the autoload "Settings".
##
##   begin()   false when the run is not isolated; the caller must then stop
##             without doing anything else and exit with a failure.
##   finish()  removes the test settings file and reports whether the player's
##             settings file is the same as when the run began.

const DEFAULT_PATH: String = "user://settings.cfg"
const ARGUMENT: String = "--settings-path="
const SUGGESTED_PATH: String = "user://test_settings.cfg"

static var _real_file_state: String = ""


## The command line that runs a scene isolated.
static func command(scene_path: String, headless: bool, extra_arguments: String = "") -> String:
	var text: String = "godot %s--path . %s -- %s%s" % [
		"--headless " if headless else "", scene_path, ARGUMENT, SUGGESTED_PATH]
	if extra_arguments != "":
		text += " " + extra_arguments
	return text


## Call first. Prints what is wrong and returns false when the run would use
## the player's settings file. Otherwise brings Settings back to its defaults
## when an earlier run left a test settings file behind, and removes that file.
## With keep_existing_file the test settings file of an earlier run is kept
## (a check that continues from what the run before it saved).
static func begin(tree: SceneTree, tag: String, scene_path: String, headless: bool, extra_arguments: String = "", keep_existing_file: bool = false) -> bool:
	var settings: Node = tree.root.get_node_or_null("Settings")
	if settings == null or not settings.has_method(&"get_storage_path"):
		print("[%s] NOT ISOLATED: the autoload Settings with get_storage_path() was not found." % tag)
		return false
	var path: String = settings.call(&"get_storage_path")
	if path == DEFAULT_PATH:
		print("[%s] NOT ISOLATED: this run would use the player's settings file (%s)." % [tag, DEFAULT_PATH])
		print("[%s] Nothing was done. Run it like this instead:" % tag)
		print("[%s]   %s" % [tag, command(scene_path, headless, extra_arguments)])
		return false
	_real_file_state = file_state(DEFAULT_PATH)
	print("[%s] settings file for this run: %s (player's file: %s)" % [tag, path, _real_file_state])
	if FileAccess.file_exists(path) and not keep_existing_file:
		print("[%s] a test settings file was left by an earlier run; back to defaults" % tag)
		settings.call(&"reset_to_defaults")
		settings.call(&"flush")
		_remove(path)
	return true


## Call last. Writes out what Settings still has to save, removes the test
## settings file, and returns true when the player's settings file is the same
## as at begin(). With keep_file the test settings file is left for the run
## that continues from it.
static func finish(tree: SceneTree, tag: String, keep_file: bool = false) -> bool:
	var settings: Node = tree.root.get_node_or_null("Settings")
	if settings == null or not settings.has_method(&"get_storage_path"):
		return false
	var path: String = settings.call(&"get_storage_path")
	if path == DEFAULT_PATH:
		return false
	settings.call(&"flush")
	if not keep_file:
		_remove(path)
	var state_now: String = file_state(DEFAULT_PATH)
	var untouched: bool = state_now == _real_file_state
	print("[%s] test settings file exists: %s; player's file: %s%s" % [
		tag, str(FileAccess.file_exists(path)), state_now, "" if untouched else " (CHANGED, was %s)" % _real_file_state])
	return untouched and (keep_file or not FileAccess.file_exists(path))


## Brings Settings back to its defaults and removes the test settings file.
## For a test that changed settings on purpose and wants the next test to
## start clean. Does nothing when the run is not isolated.
static func restore_defaults(tree: SceneTree) -> void:
	var settings: Node = tree.root.get_node_or_null("Settings")
	if settings == null or not settings.has_method(&"get_storage_path"):
		return
	var path: String = settings.call(&"get_storage_path")
	if path == DEFAULT_PATH:
		return
	settings.call(&"reset_to_defaults")
	settings.call(&"flush")
	_remove(path)


static func file_state(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "absent"
	return "md5=%s modified=%d" % [FileAccess.get_md5(path), FileAccess.get_modified_time(path)]


static func _remove(path: String) -> void:
	if path != DEFAULT_PATH and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
