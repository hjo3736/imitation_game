extends "res://app/settings.gd"
## Settings manager with a test storage path and a test monitor size.
## Used only by the tests in tests/app/. It never touches user://settings.cfg.

var test_storage_path: String = ""
var test_screen_size: Vector2i = Vector2i(1920, 1080)
## When true the real monitor size is used instead of test_screen_size.
var use_real_screen_size: bool = false
var write_count: int = 0


func _get_storage_path() -> String:
	return test_storage_path


func _get_screen_size() -> Vector2i:
	if use_real_screen_size:
		return super._get_screen_size()
	return test_screen_size


func _write_file() -> void:
	write_count += 1
	super._write_file()
