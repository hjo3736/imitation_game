extends "res://scripts/game/game.gd"
## Game with a test save path and a test balance file.
## Used only by the tests in tests/game/. It never touches user://save.json
## and never reads the game's balance file.
##
## It replaces the three hooks Game offers to tests and nothing else: which
## save file to use, which balance file to read, and the step that puts one
## file in the place of another (which a test can make fail).

var test_save_path: String = ""
var test_balance_path: String = ""
## When true, putting a file in the place of another fails, as it would with a
## locked file or a full disk.
var fail_replace: bool = false
var replace_count: int = 0


func _choose_save_path() -> String:
	return test_save_path


func _get_balance_path() -> String:
	return test_balance_path


func _replace_file(from_path: String, to_path: String) -> Error:
	replace_count += 1
	if fail_replace:
		return FAILED
	return super._replace_file(from_path, to_path)
