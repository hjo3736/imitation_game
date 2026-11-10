extends Node
## Checks which settings file the autoload Settings chose for this run
## (docs/leader/11 design, section 3, rules 1 and 2).
##
## The path is chosen once when the game starts, so each case needs a run of
## its own. --expect names the path that get_storage_path() must return:
##
##   a user:// path is used
##     godot --headless --path . res://tests/settings/settings_path_check.tscn -- --settings-path=user://test_settings.cfg --expect=user://test_settings.cfg
##   a path outside user:// is ignored (the engine prints one warning)
##     godot --headless --path . res://tests/settings/settings_path_check.tscn -- --settings-path=C:/somewhere/settings.cfg --expect=user://settings.cfg
##     godot --headless --path . res://tests/settings/settings_path_check.tscn -- --settings-path=res://settings.cfg --expect=user://settings.cfg
##     godot --headless --path . res://tests/settings/settings_path_check.tscn -- --settings-path=user://../settings.cfg --expect=user://settings.cfg
##     godot --headless --path . res://tests/settings/settings_path_check.tscn -- --settings-path= --expect=user://settings.cfg
##   no argument: the default path
##     godot --headless --path . res://tests/settings/settings_path_check.tscn -- --expect=user://settings.cfg
##
## Exit code 0 when the path is the expected one, 1 otherwise.
##
## This scene is the one exception to "stop when the run is not isolated":
## most of its cases are about the default path. It only reads
## get_storage_path(). It changes no setting, calls nothing else on Settings
## and writes no file.

const EXPECT_ARGUMENT: String = "--expect="


func _ready() -> void:
	var expected: String = ""
	var has_expected: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(EXPECT_ARGUMENT):
			expected = argument.substr(EXPECT_ARGUMENT.length())
			has_expected = true
	if not has_expected:
		print("[settings_path_check] pass -- --expect=<path>; see the top of tests/settings/settings_path_check.gd")
		get_tree().quit(1)
		return
	var actual: String = Settings.get_storage_path()
	var ok: bool = actual == expected
	print("[settings_path_check] arguments=%s" % [OS.get_cmdline_user_args()])
	print("[settings_path_check] get_storage_path()=%s expected=%s debug_build=%s" % [actual, expected, OS.is_debug_build()])
	print("[settings_path_check] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
