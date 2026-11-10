extends "res://scripts/game/game.gd"
## Game with a test save path and a test balance file.
## Used only by the tests in tests/game/. It never touches user://save.json
## and never reads the game's balance file.
##
## It replaces the two hooks Game offers to tests and nothing else.

var test_save_path: String = ""
var test_balance_path: String = ""


func _choose_save_path() -> String:
	return test_save_path


func _get_balance_path() -> String:
	return test_balance_path
