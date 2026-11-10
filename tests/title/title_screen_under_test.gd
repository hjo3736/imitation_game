extends "res://scripts/title/title_screen.gd"
## Title screen that counts quit requests instead of quitting.
## Used only by the tests in tests/title/.

var quit_count: int = 0


func _quit_game() -> void:
	quit_count += 1
