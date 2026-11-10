extends Node
## Owner of the game in progress. Registered as the autoload "Game"
## (docs/roles/leader/outputs/13 design, 5.1 and section 7).
## It calls the core's tick() every frame, stops time while a reason to block it
## is set, reads the balance file and reads and writes the save file.
## It holds no game rules and no reference to a screen node.

# --- Contract (13 design, 5.1). Do not change. --------------------------------
signal game_started
signal game_ended

var core: GameCore

# --- Names and paths ----------------------------------------------------------
const _BLOCK_REASONS: Array[StringName] = [&"pause_menu", &"transition"]
const _BALANCE_PATH: String = "res://data/balance.json"
const _SAVE_PATH: String = "user://save.json"
const _TEMPORARY_SUFFIX: String = ".tmp"

# --- Path redirection for test runs (13 design, 7.5; same rules as Settings) --
const _PATH_ARGUMENT: String = "--save-path="
const _USER_PREFIX: String = "user://"

var _save_path: String = _SAVE_PATH
var _blocked_by: Dictionary = {}
var _last_save_succeeded: bool = false


func _ready() -> void:
	# The path is chosen once, here, and never changes afterwards.
	_save_path = _choose_save_path()


func _process(delta: float) -> void:
	if core == null or is_time_blocked():
		return
	core.tick(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_on_quit()


func _exit_tree() -> void:
	_save_on_quit()


# --- Contract methods ---------------------------------------------------------

## True when there is a save file, or only the temporary file of a save that
## was cut off while it took the save file's place
## (docs/roles/leader/outputs/14 design, section 4).
func has_save() -> bool:
	return FileAccess.file_exists(_save_path) or FileAccess.file_exists(_temporary_path())


func new_game() -> bool:
	var balance: Balance = _load_balance()
	if balance == null:
		return false
	var new_core: GameCore = GameCore.create_new(balance)
	if new_core == null:
		return false
	_release_core()
	_blocked_by.clear()
	_adopt_core(new_core)
	# A new game is saved right away. The core asks for it at the end of its
	# first tick; no time passes in a tick of 0 seconds.
	_last_save_succeeded = false
	core.tick(0.0)
	if not _last_save_succeeded:
		push_error("Game: the new game could not be saved to '%s'." % _save_path)
		_release_core()
		return false
	game_started.emit()
	return true


func continue_game() -> bool:
	var balance: Balance = _load_balance()
	if balance == null:
		return false
	# The save file is read when it exists; a temporary file next to it is not
	# used. Only when the save file is missing is the temporary file taken as
	# the save (14 design, section 4).
	var from_temporary: bool = false
	var read_path: String = _save_path
	if not FileAccess.file_exists(_save_path):
		if not FileAccess.file_exists(_temporary_path()):
			return false
		from_temporary = true
		read_path = _temporary_path()
	var file: FileAccess = FileAccess.open(read_path, FileAccess.READ)
	if file == null:
		push_warning("Game: could not open '%s' (error %d)." % [read_path, FileAccess.get_open_error()])
		return false
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		push_warning("Game: '%s' is not a readable save file (line %d: %s)." % [
			read_path, json.get_error_line(), json.get_error_message()])
		return false
	var problem: String = GameCore.save_data_problem(json.data)
	if problem != "":
		push_warning("Game: the save file '%s' is refused: %s." % [read_path, problem])
		return false
	var loaded_core: GameCore = GameCore.create_from_save_data(balance, json.data)
	if loaded_core == null:
		return false
	_release_core()
	_blocked_by.clear()
	_adopt_core(loaded_core)
	if from_temporary:
		# The temporary file was good: it becomes the save file. If that fails
		# the game goes on all the same; the next save makes the save file
		# (14 design, section 6).
		var move_error: Error = _replace_file(_temporary_path(), _save_path)
		if move_error != OK:
			push_warning("Game: continued from '%s' but could not move it to '%s' (error %d)." % [
				_temporary_path(), _save_path, move_error])
	game_started.emit()
	return true


func end_game() -> void:
	if core == null:
		return
	_save()
	_release_core()
	_blocked_by.clear()
	game_ended.emit()


func set_time_blocked(reason: StringName, blocked: bool) -> void:
	if not _BLOCK_REASONS.has(reason):
		push_error("Game: '%s' is not a reason to block time. Known reasons: %s." % [reason, _BLOCK_REASONS])
		return
	if blocked:
		_blocked_by[reason] = true
	else:
		_blocked_by.erase(reason)


func is_time_blocked() -> bool:
	return not _blocked_by.is_empty()


func get_save_path() -> String:
	return _save_path


# --- Hooks that tests override ------------------------------------------------

## Called once on start. Development builds accept "--save-path=user://..."
## among the arguments after "--", so that test runs stay away from the real
## save file. Exported release builds ignore the argument.
func _choose_save_path() -> String:
	if not OS.is_debug_build():
		return _SAVE_PATH
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with(_PATH_ARGUMENT):
			continue
		var path: String = argument.substr(_PATH_ARGUMENT.length())
		if _is_acceptable_save_path(path):
			return path
		push_warning("Game: ignoring '%s'. The path must start with '%s' and name a file in the user folder. Using '%s'." % [
			argument, _USER_PREFIX, _SAVE_PATH])
		return _SAVE_PATH
	return _SAVE_PATH


func _get_balance_path() -> String:
	return _BALANCE_PATH


## Puts the file at from_path in the place of the file at to_path. Saving and
## the recovery of a leftover temporary file both go through here.
func _replace_file(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(from_path, to_path)


# --- Core ---------------------------------------------------------------------

func _adopt_core(new_core: GameCore) -> void:
	core = new_core
	core.save_requested.connect(_on_core_save_requested)


func _release_core() -> void:
	if core == null:
		return
	if core.save_requested.is_connected(_on_core_save_requested):
		core.save_requested.disconnect(_on_core_save_requested)
	core = null


func _on_core_save_requested() -> void:
	_save()


func _save_on_quit() -> void:
	if core != null:
		_save()


# --- Balance file -------------------------------------------------------------

## The balance from the balance file. Null, with an error that says what is
## wrong, when the file is missing, cannot be read or lacks a number the core
## needs.
func _load_balance() -> Balance:
	var path: String = _get_balance_path()
	if not FileAccess.file_exists(path):
		push_error("Game: the balance file '%s' does not exist." % path)
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Game: could not open the balance file '%s' (error %d)." % [path, FileAccess.get_open_error()])
		return null
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		push_error("Game: the balance file '%s' is not valid JSON (line %d: %s)." % [
			path, json.get_error_line(), json.get_error_message()])
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("Game: the balance file '%s' does not hold keys and values." % path)
		return null
	var balance: Balance = Balance.from_dictionary(json.data)
	var problems: PackedStringArray = GameCore.balance_problems(balance)
	if not problems.is_empty():
		push_error("Game: the balance file '%s' cannot be used: %s." % [path, ", ".join(problems)])
		return null
	return balance


# --- Save file ----------------------------------------------------------------

func _temporary_path() -> String:
	return _save_path + _TEMPORARY_SUFFIX


func _is_acceptable_save_path(path: String) -> bool:
	if not path.begins_with(_USER_PREFIX) or path.length() <= _USER_PREFIX.length():
		return false
	# Stay inside the user folder.
	return not path.contains("..")


## Writes the state of the game to the save file: all of it to a temporary
## file first, which then takes the place of the save file.
func _save() -> bool:
	_last_save_succeeded = false
	if core == null:
		return false
	var text: String = JSON.stringify(core.to_save_data(), "\t", true, true)
	var temporary_path: String = _temporary_path()
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		push_warning("Game: could not write '%s' (error %d)." % [temporary_path, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		push_warning("Game: could not write '%s' (error %d)." % [temporary_path, write_error])
		return false
	var rename_error: Error = _replace_file(temporary_path, _save_path)
	if rename_error != OK:
		push_warning("Game: could not replace '%s' with the new save (error %d)." % [_save_path, rename_error])
		return false
	_last_save_succeeded = true
	return true
