extends Node
## Headless test for the title screen (docs/leader/10 work order, 3.5).
##
## Run:
##   godot --headless --path . res://tests/title/title_screen_test.tscn -- --settings-path=user://test_settings.cfg
## Exit code 0 means every check passed. Any failure gives exit code 1.
## Without the argument the run is not isolated from the player's settings
## file: it does nothing and exits with 1 (docs/leader/11 design, section 3).
##
## The settings screen opens with the real autoload Settings, which uses the
## test settings file named on the command line. Some tests change settings on
## purpose; they bring Settings back to its defaults before they end. Settings
## is only used through its contract.

const TITLE_SCENE: PackedScene = preload("res://scenes/title/title_screen.tscn")
const TitleUnderTest: GDScript = preload("res://tests/title/title_screen_under_test.gd")
const CREDITS_SCENE: PackedScene = preload("res://scenes/title/credits_panel.tscn")
const LayoutCheck: GDScript = preload("res://tests/common/layout_check.gd")
const Isolation: GDScript = preload("res://tests/common/settings_isolation.gd")

const SCENE_PATH: String = "res://tests/title/title_screen_test.tscn"
const TAG: String = "title_screen_test"
const SETTINGS_SCENE_PATH: String = "res://scenes/settings/settings_screen.tscn"
const CREDITS_SCENE_PATH: String = "res://scenes/title/credits_panel.tscn"
const MENU_BUTTONS: Array[String] = [
	"NewGameButton", "ContinueButton", "SettingsButton", "CreditsButton", "QuitButton",
]
const MENU_TEXTS: Array[String] = ["새 게임", "이어 하기", "설정", "제작진", "종료"]
const OPEN_CLOSE_CYCLES: int = 10
# Window sizes for the layout check: 16:9, 16:10, 21:9 and the smallest window.
const LAYOUT_SIZES: Array[Vector2i] = [
	Vector2i(1920, 1080), Vector2i(1920, 1200), Vector2i(2520, 1080),
	Vector2i(1600, 900), Vector2i(1600, 1000), Vector2i(1680, 720),
	Vector2i(1280, 720), Vector2i(1280, 800),
]

var _checks: int = 0
var _failures: int = 0
var _new_game_count: int = 0
var _continue_count: int = 0
var _closed_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not Isolation.begin(get_tree(), TAG, SCENE_PATH, true):
		get_tree().quit(1)
		return
	var settings: Node = get_node_or_null("/root/Settings")
	print("[title_screen_test] autoload Settings present: %s" % (settings != null))
	_equal(settings != null, true, "the autoload Settings exists")
	var values_before: Dictionary = _settings_values(settings)

	# The headless window starts with an arbitrary size.
	get_window().size = Vector2i(1920, 1080)
	await _frames(2)

	await _test_menu()
	await _test_continue()
	await _test_new_game()
	await _test_settings()
	await _test_credits()
	await _test_one_overlay_at_a_time()
	await _test_escape()
	await _test_input_in_the_closing_frame()
	await _test_keyboard_and_mouse()
	await _test_clicks_behind_the_settings_screen()
	await _test_settings_change_is_saved()
	await _test_quit()
	await _test_credits_panel_alone()
	await _test_layout()
	await _test_no_leaks()

	_section("the settings are as they were, and the run stayed isolated")
	_equal(_settings_values(settings), values_before, "every value of Settings is the same as before the test")
	# Through the contract only: when Settings is told to write out what is
	# waiting and no file appears, it had no save waiting.
	var storage_path: String = settings.call(&"get_storage_path")
	_equal(FileAccess.file_exists(storage_path), false, "no test settings file is left by the tests")
	settings.call(&"flush")
	_equal(FileAccess.file_exists(storage_path), false, "Settings has no save waiting")
	_equal(Isolation.finish(get_tree(), TAG), true, "the test settings file is removed and the player's settings file is as before")

	print("")
	print("[title_screen_test] checks=%d failures=%d" % [_checks, _failures])
	print("[title_screen_test] %s" % ("PASSED" if _failures == 0 else "FAILED"))
	get_tree().quit(0 if _failures == 0 else 1)


# --- Tests -------------------------------------------------------------------

func _test_menu() -> void:
	_section("the menu has five items in order and the title")
	var screen: Control = await _open_title()
	var menu: Control = screen.get_node("%Menu")
	_equal(menu.get_child_count(), 5, "five menu items")
	for index: int in mini(menu.get_child_count(), MENU_BUTTONS.size()):
		var button: Button = menu.get_child(index) as Button
		_equal(String(button.name), MENU_BUTTONS[index], "item %d node" % (index + 1))
		_equal(button.text, MENU_TEXTS[index], "item %d text" % (index + 1))
	_equal((screen.get_node("%Title") as Label).text, "Imitation game", "the game title")
	var title_rect: Rect2 = (screen.get_node("%Title") as Control).get_global_rect()
	_equal(title_rect.end.y <= menu.get_global_rect().position.y, true, "the title is above the menu")
	_equal(_button(screen, "ContinueButton").disabled, true, "continue cannot be pressed")
	for name: String in ["NewGameButton", "SettingsButton", "CreditsButton", "QuitButton"]:
		_equal(_button(screen, name).disabled, false, "%s can be pressed" % name)
	_equal(_focus_name(), "NewGameButton", "the first pressable item has the focus")
	_equal(screen.has_overlay(), false, "no overlay at first")
	_equal(_overlay_count(screen), 0, "the overlay layer is empty at first")
	await _free_title(screen)


func _test_continue() -> void:
	_section("continue: not pressable until it is enabled from outside")
	var screen: Control = await _open_title()
	var button: Button = _button(screen, "ContinueButton")
	button.pressed.emit()
	_equal(_continue_count, 0, "a press while disabled does nothing")
	_equal(button.focus_mode, Control.FOCUS_NONE, "the keyboard skips it while disabled")
	screen.set_continue_enabled(true)
	_equal(button.disabled, false, "set_continue_enabled(true) makes it pressable")
	_equal(button.focus_mode, Control.FOCUS_ALL, "the keyboard reaches it when enabled")
	button.pressed.emit()
	_equal(_continue_count, 1, "a press emits continue_requested once")
	_equal(_overlay_count(screen), 0, "continue opens nothing")
	screen.set_continue_enabled(false)
	_equal(button.disabled, true, "set_continue_enabled(false) makes it not pressable")
	button.pressed.emit()
	_equal(_continue_count, 1, "a press while disabled again does nothing")
	await _free_title(screen)

	# Enabled before the screen enters the tree.
	var early: Control = _new_title()
	early.set_continue_enabled(true)
	add_child(early)
	await get_tree().process_frame
	_equal(_button(early, "ContinueButton").disabled, false, "enabling before entering the tree is kept")
	await _free_title(early)


func _test_new_game() -> void:
	# Changed in the 13 work (docs/roles/leader/outputs/13 design, section 6, item 7): "new
	# game" no longer shows the "not ready yet" notice. The title screen only
	# emits new_game_requested, once for every press; the screen host decides
	# what one request does and ignores repeated ones (tests/main/main_test).
	_section("new game: emits new_game_requested and opens nothing")
	var screen: Control = await _open_title()
	var button: Button = _button(screen, "NewGameButton")
	button.pressed.emit()
	_equal(_new_game_count, 1, "a press emits new_game_requested")
	_equal(_overlay_count(screen), 0, "no window opens")
	_equal(screen.has_overlay(), false, "the screen holds no overlay")
	_equal(ResourceLoader.exists("res://scenes/title/notice_panel.tscn"), false, "the notice panel scene is gone")
	await _frames(2)
	_equal(_overlay_count(screen), 0, "still no window two frames later")
	_equal(_focus_name(), "NewGameButton", "the focus stays on the menu")
	_check_menu_is_unlocked(screen)
	button.pressed.emit()
	button.pressed.emit()
	_equal(_new_game_count, 3, "every press emits: the listener decides what a repeated request does")
	# By real input.
	_press_key(KEY_ENTER)
	await _frames(2)
	_equal(_new_game_count, 4, "enter on the focused new game emits")
	_click(button)
	await _frames(2)
	_equal(_new_game_count, 5, "a click on new game emits")
	# Not while a window is open, and not once the screen is being freed.
	_button(screen, "CreditsButton").pressed.emit()
	await _frames(2)
	button.pressed.emit()
	_equal(_new_game_count, 5, "a press while a window is open does nothing")
	_overlay(screen).close()
	await _frames(3)
	button.pressed.emit()
	_equal(_new_game_count, 6, "new game works again after the window closed")
	# Not while something outside the screen keeps the mouse off the menu, as
	# the screen host does while it shows a question over the title screen.
	screen.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	button.pressed.emit()
	_button(screen, "SettingsButton").pressed.emit()
	_button(screen, "CreditsButton").pressed.emit()
	_button(screen, "QuitButton").pressed.emit()
	_equal(_new_game_count, 6, "a press while the screen is locked from outside does nothing")
	_equal(_overlay_count(screen), 0, "and no window opens")
	_equal(screen.quit_count, 0, "and quit is not requested")
	screen.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED
	button.pressed.emit()
	_equal(_new_game_count, 7, "unlocked again, a press emits")
	screen.queue_free()
	button.pressed.emit()
	_equal(_new_game_count, 7, "a press on a screen that is being freed does nothing")
	await _frames(2)
	_equal(is_instance_valid(screen), false, "the title screen is freed")


func _test_settings() -> void:
	_section("settings: opens the settings screen with the real Settings")
	var screen: Control = await _open_title()
	var settings: Node = get_node_or_null("/root/Settings")
	var connections_before: int = _connection_count(settings, &"changed")
	_button(screen, "SettingsButton").pressed.emit()
	_equal(_overlay_count(screen), 1, "one window is open")
	var window: Control = _overlay(screen)
	_equal(window.scene_file_path, SETTINGS_SCENE_PATH, "it is the settings screen")
	await _frames(2)
	_equal((window.get_node("%ErrorLabel") as Label).visible, false, "the settings screen found Settings")
	_equal((window.get_node("%WindowModeOption") as OptionButton).item_count >= 1, true, "it lists the window modes of Settings")
	_equal(_connection_count(settings, &"changed"), connections_before + 1, "it is connected to Settings.changed")
	_equal(_focus_inside(window), true, "the focus is inside the settings screen")
	_check_menu_is_locked(screen, 1)

	_closed_count = 0
	window.connect(&"closed", _on_overlay_closed)
	(window.get_node("%CloseButton") as Button).pressed.emit()
	_equal(_closed_count, 1, "the settings screen emitted closed")
	await _frames(2)
	_equal(is_instance_valid(window), false, "the settings screen is freed")
	_equal(_overlay_count(screen), 0, "the overlay layer is empty")
	_equal(screen.has_overlay(), false, "the screen holds no overlay")
	_equal(_connection_count(settings, &"changed"), connections_before, "no connection left on Settings.changed")
	_equal(_focus_name(), "SettingsButton", "the focus is back on the menu")
	_check_menu_is_unlocked(screen)
	await _free_title(screen)


func _test_credits() -> void:
	_section("credits: opens the credits panel")
	var screen: Control = await _open_title()
	_button(screen, "CreditsButton").pressed.emit()
	_equal(_overlay_count(screen), 1, "one window is open")
	var window: Control = _overlay(screen)
	_equal(window.scene_file_path, CREDITS_SCENE_PATH, "it is the credits panel")
	await _frames(2)
	var lines: Control = window.get_node("%Lines")
	_equal(lines.get_child_count(), 3, "three lines")
	var expected: Array[String] = ["Imitation game", "제작진 정보는 추후 추가됩니다.", "Made with Godot Engine"]
	for index: int in mini(lines.get_child_count(), expected.size()):
		_equal((lines.get_child(index) as Label).text, expected[index], "line %d" % (index + 1))
	_equal(lines.get_parent() is ScrollContainer, true, "the lines are inside a scroll container")
	_equal(_focus_inside(window), true, "the focus is inside the credits panel")
	_check_menu_is_locked(screen, 1)

	(window.get_node("%CloseButton") as Button).pressed.emit()
	await _frames(2)
	_equal(is_instance_valid(window), false, "the credits panel is freed")
	_equal(_overlay_count(screen), 0, "the overlay layer is empty")
	_equal(_focus_name(), "CreditsButton", "the focus is back on the menu")
	_check_menu_is_unlocked(screen)
	await _free_title(screen)


func _test_one_overlay_at_a_time() -> void:
	_section("pressing several times in one frame opens one window")
	var screen: Control = await _open_title()
	for count: int in 4:
		_button(screen, "SettingsButton").pressed.emit()
	_equal(_overlay_count(screen), 1, "four presses on settings open one window")
	await _frames(2)
	_equal(_overlay_count(screen), 1, "still one window two frames later")
	_overlay(screen).close()
	await _frames(2)

	_button(screen, "CreditsButton").pressed.emit()
	_button(screen, "SettingsButton").pressed.emit()
	_button(screen, "NewGameButton").pressed.emit()
	_button(screen, "CreditsButton").pressed.emit()
	_equal(_overlay_count(screen), 1, "different buttons in one frame open one window")
	_equal(_overlay(screen).scene_file_path, CREDITS_SCENE_PATH, "the first press wins")
	_equal(_new_game_count, 0, "new game was not requested behind the window")
	_overlay(screen).close()
	await _frames(2)
	_equal(_overlay_count(screen), 0, "the overlay layer is empty")
	await _free_title(screen)


func _test_escape() -> void:
	_section("Esc: nothing without a window, closes only the window with one")
	var screen: Control = await _open_title()
	_press_key(KEY_ESCAPE)
	await _frames(2)
	_equal(is_instance_valid(screen) and screen.is_inside_tree(), true, "Esc without a window leaves the title screen")
	_equal(screen.quit_count, 0, "Esc without a window does not quit")
	_equal(_overlay_count(screen), 0, "Esc without a window opens nothing")
	_equal(_focus_name(), "NewGameButton", "Esc without a window keeps the focus")

	for name: String in ["CreditsButton", "SettingsButton"]:
		_button(screen, name).pressed.emit()
		await _frames(2)
		_equal(_overlay_count(screen), 1, "%s: a window is open" % name)
		_press_key(KEY_ESCAPE)
		await _frames(3)
		_equal(_overlay_count(screen), 0, "%s: Esc closed the window" % name)
		_equal(is_instance_valid(screen) and screen.is_inside_tree(), true, "%s: the title screen is still there" % name)
		_equal(screen.quit_count, 0, "%s: Esc did not quit" % name)
		_equal(_focus_name(), name, "%s: the focus is back on the menu" % name)
		_press_key(KEY_ESCAPE)
		await _frames(2)
		_equal(screen.quit_count, 0, "%s: a second Esc does nothing" % name)
	await _free_title(screen)


func _test_input_in_the_closing_frame() -> void:
	_section("input in the frame a window closes is ignored and breaks nothing")
	var screen: Control = await _open_title()
	for name: String in ["SettingsButton", "CreditsButton"]:
		_button(screen, name).pressed.emit()
		await _frames(2)
		var window: Control = _overlay(screen)
		window.close()
		# Same frame: the window is closing but still in the tree.
		window.close()
		_button(screen, "CreditsButton").pressed.emit()
		_button(screen, "SettingsButton").pressed.emit()
		_button(screen, "NewGameButton").pressed.emit()
		_button(screen, "QuitButton").pressed.emit()
		_press_key(KEY_ESCAPE)
		_equal(_overlay_count(screen), 1, "%s: only the closing window is in the layer" % name)
		_equal(screen.quit_count, 0, "%s: quit was not requested" % name)
		_equal(_new_game_count, 0, "%s: new game was not requested" % name)
		await _frames(3)
		_equal(is_instance_valid(window), false, "%s: the window is freed" % name)
		_equal(_overlay_count(screen), 0, "%s: the overlay layer is empty" % name)
		_equal(screen.has_overlay(), false, "%s: the screen holds no overlay" % name)
		_check_menu_is_unlocked(screen)
	# The menu works again in the next frame.
	_button(screen, "CreditsButton").pressed.emit()
	_equal(_overlay_count(screen), 1, "the menu opens a window again")
	_overlay(screen).close()
	await _frames(2)
	await _free_title(screen)


func _test_keyboard_and_mouse() -> void:
	_section("keyboard and mouse: reach the menu without a window, not with one")
	var screen: Control = await _open_title()
	# Keyboard: down, down, enter. Continue is skipped.
	_press_key(KEY_DOWN)
	await _frames(2)
	_equal(_focus_name(), "SettingsButton", "down moves from new game to settings (continue is skipped)")
	_press_key(KEY_DOWN)
	await _frames(2)
	_equal(_focus_name(), "CreditsButton", "down moves to credits")
	_press_key(KEY_ENTER)
	await _frames(2)
	_equal(_overlay_count(screen), 1, "enter opens the credits panel")
	var window: Control = _overlay(screen)
	_equal(window != null and window.scene_file_path == CREDITS_SCENE_PATH, true, "it is the credits panel")
	# With the window open the keyboard cannot reach the menu.
	_press_key(KEY_UP)
	_press_key(KEY_TAB)
	await _frames(2)
	_equal(_focus_inside(window), true, "arrow and tab keep the focus inside the window")
	# The mouse cannot reach the menu either. Menu items that lie under the
	# window's own close button are left out: a click there is a click on that
	# button, not on the menu. (The same clicks with the settings screen in
	# front are in _test_clicks_behind_the_settings_screen.)
	var close_rect: Rect2 = (window.get_node("%CloseButton") as Control).get_global_rect()
	var clicked: int = 0
	for button_name: String in MENU_BUTTONS:
		var target: Button = _button(screen, button_name)
		if close_rect.grow(4.0).has_point(target.get_global_rect().get_center()):
			continue
		_click(target)
		clicked += 1
	await _frames(2)
	_equal(clicked >= 3, true, "at least three menu items were clicked behind the window (%d)" % clicked)
	_equal(_overlay_count(screen), 1, "clicks on the menu behind the window open nothing")
	_equal(_overlay(screen) == window, true, "the same window is still open")
	_equal(screen.quit_count, 0, "clicks behind the window do not quit")
	_equal(_new_game_count, 0, "clicks behind the window do not request a new game")
	# Enter goes to the window's own button and closes it.
	_press_key(KEY_ENTER)
	await _frames(3)
	_equal(_overlay_count(screen), 0, "enter pressed the window's close button")
	_equal(_focus_name(), "CreditsButton", "the focus is back on the menu")

	# Without a window a click does reach the menu (so the checks above mean something).
	_click(_button(screen, "CreditsButton"))
	await _frames(2)
	_equal(_overlay_count(screen), 1, "a click on credits opens the credits panel")
	window = _overlay(screen)
	_click(window.get_node("%CloseButton") as Control)
	await _frames(3)
	_equal(_overlay_count(screen), 0, "a click on the window's close button closes it")

	await _free_title(screen)


## Left out in the 10 work because the clicks land on the settings screen's
## controls and change settings, which then went to the player's settings
## file. With the run isolated they go to the test settings file.
func _test_clicks_behind_the_settings_screen() -> void:
	_section("mouse: clicks where the menu is, with the settings screen in front, do not reach the menu")
	var settings: Node = get_node_or_null("/root/Settings")
	var screen: Control = await _open_title()
	_button(screen, "SettingsButton").pressed.emit()
	await _frames(2)
	_equal(_overlay_count(screen), 1, "the settings screen is open")
	var window: Control = _overlay(screen)
	_equal(window != null and window.scene_file_path == SETTINGS_SCENE_PATH, true, "it is the settings screen")
	var values_before: Dictionary = _settings_values(settings)
	# Menu items that lie under the settings screen's own close button are left
	# out: a click there is a click on that button, not on the menu.
	var close_rect: Rect2 = (window.get_node("%CloseButton") as Control).get_global_rect()
	var clicked: int = 0
	for button_name: String in MENU_BUTTONS:
		var target: Button = _button(screen, button_name)
		if close_rect.grow(4.0).has_point(target.get_global_rect().get_center()):
			continue
		_click(target)
		clicked += 1
		await _frames(2)
		# A click may have opened a list of the settings screen; put it away so
		# that the next click is a click on the screen again.
		for option_name: String in ["%WindowModeOption", "%WindowSizeOption"]:
			(window.get_node(option_name) as OptionButton).get_popup().hide()
		await _frames(1)
	_equal(clicked >= 3, true, "at least three menu items were clicked behind the settings screen (%d)" % clicked)
	_equal(_overlay_count(screen), 1, "clicks behind the settings screen open nothing")
	_equal(_overlay(screen) == window, true, "the settings screen is still the open window")
	_equal(is_instance_valid(window) and not window.is_queued_for_deletion(), true, "the settings screen was not closed")
	_equal(screen.quit_count, 0, "clicks behind the settings screen do not quit")
	_equal(_new_game_count, 0, "clicks behind the settings screen do not request a new game")
	_check_menu_is_locked(screen, 1)
	# Where the clicks went instead: the settings screen's own controls.
	var values_after: Dictionary = _settings_values(settings)
	var moved: PackedStringArray = PackedStringArray()
	for constant_name: StringName in values_after:
		if values_after[constant_name] != values_before[constant_name]:
			moved.append("%s %s -> %s" % [constant_name, values_before[constant_name], values_after[constant_name]])
	print("  settings changed by the clicks (they landed on the settings screen): %s" % [moved])

	(window.get_node("%CloseButton") as Button).pressed.emit()
	await _frames(3)
	_equal(_overlay_count(screen), 0, "the settings screen closes as usual afterwards")
	_check_menu_is_unlocked(screen)
	# The menu works again, so the checks above were made on a live menu.
	_click(_button(screen, "CreditsButton"))
	await _frames(2)
	_equal(_overlay_count(screen), 1, "a click on credits opens the credits panel once the settings screen is gone")
	_overlay(screen).close()
	await _frames(3)
	await _free_title(screen)
	Isolation.restore_defaults(get_tree())


## Not checked in the 10 work because it would have written the player's
## settings file: a setting changed in the settings screen that was opened from
## the title screen is applied and saved by the real Settings.
func _test_settings_change_is_saved() -> void:
	_section("settings opened from the title screen: a change is applied and saved by Settings")
	var settings: Node = get_node_or_null("/root/Settings")
	var storage_path: String = settings.call(&"get_storage_path")
	var master_key: Variant = settings.get(&"VOLUME_MASTER")
	var master_bus: int = AudioServer.get_bus_index(&"Master")
	_equal(FileAccess.file_exists(storage_path), false, "no test settings file before the change")
	var screen: Control = await _open_title()
	_button(screen, "SettingsButton").pressed.emit()
	await _frames(2)
	var window: Control = _overlay(screen)
	var slider: HSlider = window.get_node("%MasterSlider")
	_equal(is_equal_approx(slider.value, 100.0), true, "the master slider shows the default 100")
	slider.value = 30.0
	_equal(is_equal_approx(float(settings.call(&"get_value", master_key)), 0.3), true, "Settings holds the new master volume")
	_equal(is_equal_approx(AudioServer.get_bus_volume_db(master_bus), linear_to_db(0.3)), true, "the master bus has the new volume")
	(window.get_node("%CloseButton") as Button).pressed.emit()
	await _frames(3)
	_equal(_overlay_count(screen), 0, "the settings screen is closed")
	_equal(FileAccess.file_exists(storage_path), true, "closing the settings screen saved the change")
	var config: ConfigFile = ConfigFile.new()
	_equal(config.load(storage_path), OK, "the test settings file can be read")
	_equal(is_equal_approx(float(config.get_value("audio", "volume_master", -1.0)), 0.3), true, "the saved master volume is 0.3")
	_equal(storage_path != Isolation.DEFAULT_PATH, true, "the file it was saved to is not the player's settings file")

	# Opened again, the settings screen shows the changed value.
	_button(screen, "SettingsButton").pressed.emit()
	await _frames(2)
	window = _overlay(screen)
	_equal(is_equal_approx((window.get_node("%MasterSlider") as HSlider).value, 30.0), true, "the master slider shows 30 when opened again")
	(window.get_node("%CloseButton") as Button).pressed.emit()
	await _frames(3)
	await _free_title(screen)
	Isolation.restore_defaults(get_tree())
	_equal(is_equal_approx(float(settings.call(&"get_value", master_key)), 1.0), true, "the master volume is back at its default")


func _test_quit() -> void:
	_section("quit: asks to quit once, without a question")
	var screen: Control = await _open_title()
	var button: Button = _button(screen, "QuitButton")
	button.pressed.emit()
	_equal(screen.quit_count, 1, "one press asks to quit")
	_equal(_overlay_count(screen), 0, "no question is shown")
	button.pressed.emit()
	button.pressed.emit()
	_equal(screen.quit_count, 1, "more presses do not ask again")
	_button(screen, "SettingsButton").pressed.emit()
	_button(screen, "CreditsButton").pressed.emit()
	_button(screen, "NewGameButton").pressed.emit()
	_equal(_overlay_count(screen), 0, "nothing opens after quit was chosen")
	_equal(_new_game_count, 0, "new game is not requested after quit was chosen")
	await _free_title(screen)

	# Quit pressed several times in one frame, as the first action.
	screen = await _open_title()
	button = _button(screen, "QuitButton")
	for count: int in 5:
		button.pressed.emit()
	_equal(screen.quit_count, 1, "five presses in one frame ask to quit once")
	await _free_title(screen)


func _test_credits_panel_alone() -> void:
	_section("credits panel on its own: closed once, frees itself")
	var panel: Control = CREDITS_SCENE.instantiate()
	_closed_count = 0
	panel.connect(&"closed", _on_overlay_closed)
	add_child(panel)
	await get_tree().process_frame
	(panel.get_node("%CloseButton") as Button).pressed.emit()
	(panel.get_node("%CloseButton") as Button).pressed.emit()
	panel.close()
	_press_key(KEY_ESCAPE)
	_equal(_closed_count, 1, "closed is emitted once")
	_equal(panel.is_queued_for_deletion(), true, "the panel frees itself")
	await _frames(2)
	_equal(is_instance_valid(panel), false, "the panel is freed")
	_equal(_closed_count, 1, "closed is still emitted once")


func _test_layout() -> void:
	_section("layout: inside the safe area, nothing cut, nothing overlapping")
	var window: Window = get_window()
	var original_size: Vector2i = window.size
	var screen: Control = await _open_title()
	var content: Control = screen.get_node("%Content")
	_equal(LayoutCheck.count_items(content), 6, "the check covers the title and the five menu items")
	_no_thin_lines(screen, "title screen")

	for window_size: Vector2i in LAYOUT_SIZES:
		var tag: String = "%dx%d" % [window_size.x, window_size.y]
		window.size = window_size
		await _frames(3)
		var visible: Vector2 = get_viewport().get_visible_rect().size
		var scale: float = minf(float(window_size.x) / 1920.0, float(window_size.y) / 1080.0)
		var expected: Vector2 = Vector2(window_size) / scale
		_equal(visible.distance_to(expected) < 1.5, true, "%s shows %s (expected about %s)" % [tag, visible, expected])
		_equal((screen.get_node("%Background") as Control).get_global_rect().size.distance_to(visible) < 0.01, true,
				"%s: the background covers the visible area" % tag)
		var safe: Rect2 = LayoutCheck.safe_rect(get_viewport())
		_equal(content.get_global_rect().get_center().distance_to(safe.get_center()) < 1.0, true, "%s: the content is centered" % tag)
		_no_problems(LayoutCheck.find_layout_problems(content), "%s: title and menu" % tag)

		for name: String in ["SettingsButton", "CreditsButton"]:
			_button(screen, name).pressed.emit()
			await _frames(3)
			var overlay: Control = _overlay(screen)
			var panel: Control = overlay.get_node("%Panel")
			_equal(overlay.get_global_rect().size.distance_to(visible) < 0.01, true, "%s: %s window covers the visible area" % [tag, name])
			_equal(panel.get_global_rect().get_center().distance_to(safe.get_center()) < 1.0, true, "%s: %s panel is centered" % [tag, name])
			_no_problems(LayoutCheck.find_layout_problems(panel), "%s: %s panel" % [tag, name])
			if window_size == LAYOUT_SIZES[0]:
				_no_thin_lines(overlay, "%s window" % name)
			overlay.close()
			await _frames(3)

	window.size = original_size
	await _frames(2)
	await _free_title(screen)


func _test_no_leaks() -> void:
	_section("opening and closing every window %d times leaves nothing behind" % OPEN_CLOSE_CYCLES)
	var settings: Node = get_node_or_null("/root/Settings")
	var screen: Control = await _open_title()
	var buttons: Array[String] = ["SettingsButton", "CreditsButton"]
	# One warm-up round, so one-time allocations are not counted as a leak.
	for name: String in buttons:
		_button(screen, name).pressed.emit()
		await _frames(2)
		_overlay(screen).close()
		await _frames(3)

	_new_game_count = 0
	var nodes_before: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var objects_before: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var connections_before: Dictionary = _connection_snapshot(screen, settings)
	var windows: Array[WeakRef] = []
	var nodes_while_open: int = 0
	var most_overlays: int = 0
	for cycle: int in OPEN_CLOSE_CYCLES:
		# New game opens no window since the 13 work; it is pressed once per
		# cycle so that its signal is part of what must not pile up.
		_button(screen, "NewGameButton").pressed.emit()
		for name: String in buttons:
			_button(screen, name).pressed.emit()
			_button(screen, name).pressed.emit()
			await get_tree().process_frame
			most_overlays = maxi(most_overlays, _overlay_count(screen))
			nodes_while_open = maxi(nodes_while_open, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
			var overlay: Control = _overlay(screen)
			windows.append(weakref(overlay))
			if cycle % 2 == 0:
				(overlay.get_node("%CloseButton") as Button).pressed.emit()
			else:
				_press_key(KEY_ESCAPE)
			overlay = null
			await _frames(3)

	var alive: int = 0
	for reference: WeakRef in windows:
		if reference.get_ref() != null:
			alive += 1
	windows.clear()
	var nodes_after: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var objects_after: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var connections_after: Dictionary = _connection_snapshot(screen, settings)
	print("  nodes %d -> %d (%d while a window is open), orphan nodes %d -> %d, objects %d -> %d" % [
		nodes_before, nodes_after, nodes_while_open, orphans_before, orphans_after, objects_before, objects_after,
	])
	print("  connections before: %s" % [connections_before])
	print("  connections after:  %s" % [connections_after])
	_equal(most_overlays, 1, "never more than one window at a time")
	_equal(nodes_while_open > nodes_before, true, "the node count does rise while a window is open")
	_equal(alive, 0, "every window is freed (%d opened)" % (OPEN_CLOSE_CYCLES * buttons.size()))
	_equal(_overlay_count(screen), 0, "the overlay layer is empty")
	_equal(screen.has_overlay(), false, "the screen holds no overlay")
	_equal(nodes_after, nodes_before, "the node count is back where it was")
	_equal(orphans_after, orphans_before, "no orphan node was added")
	_equal(connections_after, connections_before, "every connection count is back where it was")
	_equal(objects_after - objects_before < OPEN_CLOSE_CYCLES, true, "the object count does not grow with every cycle")
	_equal(_new_game_count, OPEN_CLOSE_CYCLES, "new game was requested once per cycle")
	await _free_title(screen)
	_equal(_connection_count(settings, &"changed"), connections_before["Settings.changed"], "nothing is connected to Settings.changed after the title screen is freed")


# --- Helpers -----------------------------------------------------------------

func _new_title() -> Control:
	var screen: Control = TITLE_SCENE.instantiate()
	# Same scene, with the quit hook replaced so that the test keeps running.
	screen.set_script(TitleUnderTest)
	_new_game_count = 0
	_continue_count = 0
	screen.connect(&"new_game_requested", _on_new_game_requested)
	screen.connect(&"continue_requested", _on_continue_requested)
	return screen


func _open_title() -> Control:
	var screen: Control = _new_title()
	add_child(screen)
	await get_tree().process_frame
	return screen


func _free_title(screen: Control) -> void:
	screen.queue_free()
	await _frames(2)
	_equal(is_instance_valid(screen), false, "the title screen is freed")


func _frames(count: int) -> void:
	for index: int in count:
		await get_tree().process_frame


func _button(screen: Control, button_name: String) -> Button:
	return screen.get_node("%" + button_name) as Button


func _overlay_count(screen: Control) -> int:
	return screen.get_node("%OverlayLayer").get_child_count()


func _overlay(screen: Control) -> Control:
	var layer: Node = screen.get_node("%OverlayLayer")
	if layer.get_child_count() == 0:
		return null
	return layer.get_child(layer.get_child_count() - 1) as Control


func _focus_name() -> String:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return String(focused.name) if focused != null else "(none)"


func _focus_inside(root: Control) -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return focused != null and root != null and root.is_ancestor_of(focused)


## With a window open: presses on the menu do nothing and the menu cannot take
## the focus or the mouse.
func _check_menu_is_locked(screen: Control, overlays: int) -> void:
	var window: Control = _overlay(screen)
	var new_games: int = _new_game_count
	for button_name: String in MENU_BUTTONS:
		_button(screen, button_name).pressed.emit()
	_equal(_overlay_count(screen), overlays, "pressing every menu item opens no other window")
	_equal(_overlay(screen) == window, true, "the same window is still open")
	_equal(_new_game_count, new_games, "new game is not requested behind the window")
	_equal(screen.quit_count, 0, "quit is not requested behind the window")
	var focusable: int = 0
	var clickable: int = 0
	for button_name: String in MENU_BUTTONS:
		var button: Button = _button(screen, button_name)
		if button.get_focus_mode_with_override() != Control.FOCUS_NONE:
			focusable += 1
		if button.get_mouse_filter_with_override() != Control.MOUSE_FILTER_IGNORE:
			clickable += 1
	_equal(focusable, 0, "no menu item can take the keyboard focus")
	_equal(clickable, 0, "no menu item can take the mouse")
	var focused: Control = get_viewport().gui_get_focus_owner()
	_equal(focused == null or not (screen.get_node("%Menu") as Control).is_ancestor_of(focused), true, "the focus is not on the menu")


func _check_menu_is_unlocked(screen: Control) -> void:
	var focusable: int = 0
	var clickable: int = 0
	for button_name: String in MENU_BUTTONS:
		var button: Button = _button(screen, button_name)
		if button.get_focus_mode_with_override() != Control.FOCUS_NONE:
			focusable += 1
		if button.get_mouse_filter_with_override() != Control.MOUSE_FILTER_IGNORE:
			clickable += 1
	_equal(focusable, 4, "four menu items can take the keyboard focus again (continue is disabled)")
	_equal(clickable, 5, "the menu items can take the mouse again")


func _connection_count(object: Object, signal_name: StringName) -> int:
	if object == null or not object.has_signal(signal_name):
		return -1
	return object.get_signal_connection_list(signal_name).size()


## Connection counts that must not grow: Settings.changed, everything that is
## connected to a method of the title screen, and the menu buttons' pressed.
func _connection_snapshot(screen: Control, settings: Node) -> Dictionary:
	var snapshot: Dictionary = {
		"Settings.changed": _connection_count(settings, &"changed"),
		"into the title screen": screen.get_incoming_connections().size(),
	}
	for button_name: String in MENU_BUTTONS:
		snapshot[button_name + ".pressed"] = _connection_count(_button(screen, button_name), &"pressed")
	return snapshot


## Every value the real Settings holds, read through the contract.
func _settings_values(settings: Node) -> Dictionary:
	var values: Dictionary = {}
	if settings == null:
		return values
	for constant_name: StringName in [&"WINDOW_MODE", &"WINDOW_SIZE", &"VSYNC", &"VOLUME_MASTER", &"VOLUME_MUSIC", &"VOLUME_SFX"]:
		var key: Variant = settings.get(constant_name)
		values[constant_name] = settings.call(&"get_value", key)
	return values


func _press_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)


## A left click in the middle of the control, as real mouse input.
func _click(control: Control) -> void:
	# Viewport coordinates to window coordinates.
	var position: Vector2 = get_viewport().get_final_transform() * control.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		Input.parse_input_event(event)


func _on_new_game_requested() -> void:
	_new_game_count += 1


func _on_continue_requested() -> void:
	_continue_count += 1


func _on_overlay_closed() -> void:
	_closed_count += 1


func _section(title: String) -> void:
	print("")
	print("[test] " + title)


func _equal(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if typeof(actual) == typeof(expected) and actual == expected:
		print("  ok   " + what)
	else:
		_failures += 1
		print("  FAIL %s: got %s, expected %s" % [what, var_to_str(actual), var_to_str(expected)])


func _no_problems(problems: PackedStringArray, what: String) -> void:
	_checks += 1
	if problems.is_empty():
		print("  ok   %s: no layout problem" % what)
	else:
		_failures += 1
		print("  FAIL %s: %d layout problem(s)" % [what, problems.size()])
		for problem: String in problems:
			print("       " + problem)


func _no_thin_lines(root: Node, what: String) -> void:
	var thin: PackedStringArray = LayoutCheck.find_thin_lines(root)
	for line: String in thin:
		print("    thin line: " + line)
	_equal(thin.size(), 0, "%s: no style box draws a line thinner than 2" % what)
