extends "res://ui/title/title_screen.gd"
## Title screen that counts quit requests instead of quitting.
## Used only by the tests in tests/ui/.

var quit_count: int = 0


func _quit_game() -> void:
	quit_count += 1
