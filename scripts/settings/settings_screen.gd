extends Control
## Settings screen (docs/roles/leader/outputs/08 design).
##
## Shows the graphics and audio settings and asks the settings object to change
## them. This screen never touches the window, the audio buses or the settings
## file. It talks to the settings object only through the contract in section 4
## of the 08 design: get_value, set_value, get_options, reset_to_defaults, flush
## and the changed signal.
##
## By default the settings object is the autoload "Settings". Call set_settings()
## before adding the screen to the tree to use another object (tests do this).

## Emitted once when the screen closes, right before it frees itself.
signal closed

# --- Contract (docs/roles/leader/outputs/08 design, section 4) -----------------------------
const SETTINGS_AUTOLOAD_PATH: NodePath = ^"/root/Settings"
const REQUIRED_SIGNAL: StringName = &"changed"
const REQUIRED_METHODS: Array[StringName] = [
	&"get_value", &"set_value", &"get_options", &"reset_to_defaults", &"flush",
]
# Names of the key constants that the settings object declares.
const KEY_CONSTANT_NAMES: Array[StringName] = [
	&"WINDOW_MODE", &"WINDOW_SIZE", &"VSYNC",
	&"VOLUME_MASTER", &"VOLUME_MUSIC", &"VOLUME_SFX",
]
const MODE_FULLSCREEN: StringName = &"fullscreen"
const MODE_WINDOWED: StringName = &"windowed"

# --- Display names -----------------------------------------------------------
const MODE_NAMES: Dictionary = {
	"fullscreen": "전체 화면",
	"windowed": "창 모드",
}
const TEXT_ON: String = "켬"
const TEXT_OFF: String = "끔"
const SIZE_FORMAT: String = "%d×%d"
const PERCENT_FORMAT: String = "%d%%"
const PERCENT_MAX: float = 100.0
const PERCENT_STEP: float = 1.0
const ERROR_NO_SETTINGS: String = "설정 객체가 없습니다. 전역 객체 Settings가 등록되지 않았고 set_settings()로 지정한 객체도 없습니다."
const ERROR_NO_SETTINGS_SHORT: String = "설정 객체가 없습니다 (전역 객체 Settings 없음)."
const ERROR_BAD_SETTINGS: String = "설정 객체가 계약을 따르지 않습니다. 없는 것: %s"
const ERROR_BAD_SETTINGS_SHORT: String = "설정 객체가 계약을 따르지 않습니다. 오류 기록을 보십시오."

# --- Temporary look (docs/roles/leader/outputs/08 design 2.3: design comes later) ----------
# Everything below is a placeholder until the art direction is decided.
# No line here is thinner than 2 (08 design 5.4, rule 13).
const COLOR_BACKGROUND: Color = Color(0.10, 0.11, 0.13)
const COLOR_PANEL: Color = Color(0.17, 0.19, 0.23)
const COLOR_PANEL_BORDER: Color = Color(0.55, 0.58, 0.65)
const COLOR_DIM: Color = Color(0.0, 0.0, 0.0, 0.6)
const COLOR_ERROR: Color = Color(1.0, 0.45, 0.4)
const PANEL_BORDER_WIDTH: int = 2
const SEPARATOR_WIDTH: int = 2
const FONT_SIZE: int = 32
const TITLE_FONT_SIZE: int = 48
const SECTION_FONT_SIZE: int = 38
const PANEL_MARGIN: int = 48
const ROW_SEPARATION: int = 20
const GRID_H_SEPARATION: int = 40
const GRID_V_SEPARATION: int = 16
const BUTTON_SEPARATION: int = 24
const CONTROL_MIN_SIZE: Vector2 = Vector2(360.0, 60.0)
const SLIDER_MIN_SIZE: Vector2 = Vector2(480.0, 60.0)
const VALUE_LABEL_MIN_WIDTH: float = 120.0
const BUTTON_MIN_SIZE: Vector2 = Vector2(220.0, 64.0)

var _settings: Object = null
var _settings_ready: bool = false
var _settings_error: String = ""
var _settings_error_short: String = ""
var _updating: bool = false
var _closing: bool = false

var _key_window_mode: StringName = &""
var _key_window_size: StringName = &""
var _key_vsync: StringName = &""
var _key_volume_master: StringName = &""
var _key_volume_music: StringName = &""
var _key_volume_sfx: StringName = &""

var _mode_options: Array = []
var _size_options: Array = []

@onready var _background: ColorRect = %Background
@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %Title
@onready var _graphics_title: Label = %GraphicsTitle
@onready var _audio_title: Label = %AudioTitle
@onready var _window_mode_option: OptionButton = %WindowModeOption
@onready var _window_size_option: OptionButton = %WindowSizeOption
@onready var _vsync_check: CheckButton = %VsyncCheck
@onready var _master_slider: HSlider = %MasterSlider
@onready var _master_value: Label = %MasterValue
@onready var _music_slider: HSlider = %MusicSlider
@onready var _music_value: Label = %MusicValue
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _sfx_value: Label = %SfxValue
@onready var _error_label: Label = %ErrorLabel
@onready var _reset_button: Button = %ResetButton
@onready var _close_button: Button = %CloseButton
@onready var _confirm_layer: Control = %ConfirmLayer
@onready var _confirm_dim: ColorRect = %ConfirmDim
@onready var _confirm_yes_button: Button = %ConfirmYesButton
@onready var _confirm_no_button: Button = %ConfirmNoButton


## Sets the settings object to use instead of the autoload "Settings".
## Must be called before the screen enters the tree.
func set_settings(settings: Object) -> void:
	if is_inside_tree():
		push_error("SettingsScreen.set_settings(): 트리에 들어간 뒤에는 설정 객체를 바꿀 수 없습니다.")
		return
	_settings = settings


## Flushes the settings, emits closed and frees the screen. When the screen is
## the root of the running scene, quits the game instead. Runs only once.
func close() -> void:
	if _closing:
		return
	_closing = true
	if _has_settings():
		_settings.flush()
	closed.emit()
	if is_inside_tree() and get_tree().current_scene == self:
		get_tree().quit()
	else:
		queue_free()


func _enter_tree() -> void:
	_resolve_settings()
	if _settings_ready and not _settings.is_connected(REQUIRED_SIGNAL, _on_settings_changed):
		_settings.connect(REQUIRED_SIGNAL, _on_settings_changed)
	if is_node_ready():
		_refresh_all()


func _exit_tree() -> void:
	if _settings != null and is_instance_valid(_settings) and _settings.has_signal(REQUIRED_SIGNAL):
		if _settings.is_connected(REQUIRED_SIGNAL, _on_settings_changed):
			_settings.disconnect(REQUIRED_SIGNAL, _on_settings_changed)


func _ready() -> void:
	_apply_style()
	for slider: HSlider in [_master_slider, _music_slider, _sfx_slider]:
		slider.min_value = 0.0
		slider.max_value = PERCENT_MAX
		slider.step = PERCENT_STEP
	# These are connections to the screen's own children. They are freed
	# together with the screen, so they need no manual disconnect.
	_window_mode_option.item_selected.connect(_on_window_mode_selected)
	_window_size_option.item_selected.connect(_on_window_size_selected)
	_vsync_check.toggled.connect(_on_vsync_toggled)
	_master_slider.value_changed.connect(_on_master_slider_changed)
	_music_slider.value_changed.connect(_on_music_slider_changed)
	_sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_close_button.pressed.connect(_on_close_pressed)
	_confirm_yes_button.pressed.connect(_on_confirm_yes_pressed)
	_confirm_no_button.pressed.connect(_on_confirm_no_pressed)
	_refresh_all()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_ESCAPE:
		return
	get_viewport().set_input_as_handled()
	if _confirm_layer.visible:
		_hide_confirm()
	else:
		close()


# --- Settings object ---------------------------------------------------------

func _resolve_settings() -> void:
	_settings_ready = false
	_settings_error = ""
	_settings_error_short = ""
	if _settings == null or not is_instance_valid(_settings):
		_settings = get_node_or_null(SETTINGS_AUTOLOAD_PATH)
	if _settings == null:
		_settings_error = ERROR_NO_SETTINGS
		_settings_error_short = ERROR_NO_SETTINGS_SHORT
		push_error("SettingsScreen: " + _settings_error)
		return

	var missing: PackedStringArray = PackedStringArray()
	if not _settings.has_signal(REQUIRED_SIGNAL):
		missing.append("signal " + String(REQUIRED_SIGNAL))
	for method: StringName in REQUIRED_METHODS:
		if not _settings.has_method(method):
			missing.append(String(method) + "()")
	var keys: Dictionary = {}
	for constant_name: StringName in KEY_CONSTANT_NAMES:
		var key: Variant = _settings.get(constant_name)
		if key is StringName or key is String:
			keys[constant_name] = StringName(key)
		else:
			missing.append(String(constant_name))
	if not missing.is_empty():
		_settings_error = ERROR_BAD_SETTINGS % ", ".join(missing)
		_settings_error_short = ERROR_BAD_SETTINGS_SHORT
		push_error("SettingsScreen: " + _settings_error)
		return

	_key_window_mode = keys[&"WINDOW_MODE"]
	_key_window_size = keys[&"WINDOW_SIZE"]
	_key_vsync = keys[&"VSYNC"]
	_key_volume_master = keys[&"VOLUME_MASTER"]
	_key_volume_music = keys[&"VOLUME_MUSIC"]
	_key_volume_sfx = keys[&"VOLUME_SFX"]
	_settings_ready = true


func _has_settings() -> bool:
	return _settings_ready and _settings != null and is_instance_valid(_settings)


## Asks the settings object to change a value, then shows what it really holds.
func _request(key: StringName, value: Variant) -> void:
	if _updating or _closing or not _has_settings():
		return
	_settings.set_value(key, value)
	# The settings object may have refused or adjusted the value.
	_refresh(key)


func _on_settings_changed(key: StringName) -> void:
	if not is_node_ready():
		return
	_refresh(key)


# --- Showing values ----------------------------------------------------------
# Refreshing uses setters that emit no signal, and _updating guards the
# handlers as well, so a refresh can never call set_value again (08 design
# 5.2, rule 7).

func _refresh_all() -> void:
	var usable: bool = _has_settings()
	_error_label.visible = not usable
	# The full text goes to the engine error log (push_error) and the tooltip.
	_error_label.text = _settings_error_short
	_error_label.tooltip_text = _settings_error
	_error_label.mouse_filter = Control.MOUSE_FILTER_PASS if not usable else Control.MOUSE_FILTER_IGNORE
	_window_mode_option.disabled = not usable
	_window_size_option.disabled = true
	_vsync_check.disabled = not usable
	_master_slider.editable = usable
	_music_slider.editable = usable
	_sfx_slider.editable = usable
	_reset_button.disabled = not usable
	if not usable:
		return
	_refresh_window_mode()
	_refresh_window_size()
	_refresh_vsync()
	_refresh_volume(_key_volume_master, _master_slider, _master_value)
	_refresh_volume(_key_volume_music, _music_slider, _music_value)
	_refresh_volume(_key_volume_sfx, _sfx_slider, _sfx_value)


func _refresh(key: StringName) -> void:
	if not _has_settings():
		return
	if key == _key_window_mode:
		_refresh_window_mode()
		_refresh_window_size()
	elif key == _key_window_size:
		_refresh_window_size()
	elif key == _key_vsync:
		_refresh_vsync()
	elif key == _key_volume_master:
		_refresh_volume(_key_volume_master, _master_slider, _master_value)
	elif key == _key_volume_music:
		_refresh_volume(_key_volume_music, _music_slider, _music_value)
	elif key == _key_volume_sfx:
		_refresh_volume(_key_volume_sfx, _sfx_slider, _sfx_value)


func _refresh_window_mode() -> void:
	_updating = true
	_mode_options = _settings.get_options(_key_window_mode)
	var current: Variant = _settings.get_value(_key_window_mode)
	_window_mode_option.clear()
	var selected: int = -1
	for index: int in _mode_options.size():
		var mode: String = str(_mode_options[index])
		_window_mode_option.add_item(MODE_NAMES.get(mode, mode))
		if mode == str(current):
			selected = index
	_window_mode_option.select(selected)
	_updating = false


func _refresh_window_size() -> void:
	_updating = true
	_size_options = _settings.get_options(_key_window_size)
	var current: Variant = _settings.get_value(_key_window_size)
	_window_size_option.clear()
	var selected: int = -1
	for index: int in _size_options.size():
		var option: Variant = _size_options[index]
		if option is Vector2i:
			var option_size: Vector2i = option
			_window_size_option.add_item(SIZE_FORMAT % [option_size.x, option_size.y])
		else:
			_window_size_option.add_item(str(option))
		if typeof(option) == typeof(current) and option == current:
			selected = index
	_window_size_option.select(selected)
	# The window size applies only in windowed mode.
	var windowed: bool = str(_settings.get_value(_key_window_mode)) == String(MODE_WINDOWED)
	_window_size_option.disabled = not windowed or _size_options.is_empty()
	_updating = false


func _refresh_vsync() -> void:
	_updating = true
	var enabled: bool = _settings.get_value(_key_vsync) == true
	_vsync_check.set_pressed_no_signal(enabled)
	_vsync_check.text = TEXT_ON if enabled else TEXT_OFF
	_updating = false


func _refresh_volume(key: StringName, slider: HSlider, value_label: Label) -> void:
	_updating = true
	var raw: Variant = _settings.get_value(key)
	var volume: float = float(raw) if (raw is float or raw is int) else 0.0
	var percent: float = roundf(clampf(volume, 0.0, 1.0) * PERCENT_MAX)
	slider.set_value_no_signal(percent)
	value_label.text = PERCENT_FORMAT % int(percent)
	_updating = false


# --- Control handlers --------------------------------------------------------

func _on_window_mode_selected(index: int) -> void:
	if index < 0 or index >= _mode_options.size():
		return
	_request(_key_window_mode, _mode_options[index])


func _on_window_size_selected(index: int) -> void:
	if index < 0 or index >= _size_options.size():
		return
	_request(_key_window_size, _size_options[index])


func _on_vsync_toggled(pressed: bool) -> void:
	_request(_key_vsync, pressed)


func _on_master_slider_changed(percent: float) -> void:
	_request(_key_volume_master, percent / PERCENT_MAX)


func _on_music_slider_changed(percent: float) -> void:
	_request(_key_volume_music, percent / PERCENT_MAX)


func _on_sfx_slider_changed(percent: float) -> void:
	_request(_key_volume_sfx, percent / PERCENT_MAX)


func _on_reset_pressed() -> void:
	if _closing or not _has_settings():
		return
	_show_confirm()


func _on_close_pressed() -> void:
	close()


func _on_confirm_yes_pressed() -> void:
	if not _confirm_layer.visible:
		return
	_hide_confirm()
	if _closing or not _has_settings():
		return
	_settings.reset_to_defaults()
	_refresh_all()


func _on_confirm_no_pressed() -> void:
	_hide_confirm()


func _show_confirm() -> void:
	# Keep keyboard focus out of the controls behind the question.
	_panel.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	_confirm_layer.visible = true
	_confirm_no_button.grab_focus()


func _hide_confirm() -> void:
	_confirm_layer.visible = false
	_panel.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	if _reset_button.is_inside_tree() and not _reset_button.disabled:
		_reset_button.grab_focus()


# --- Temporary look ----------------------------------------------------------

func _apply_style() -> void:
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL
	panel_style.border_color = COLOR_PANEL_BORDER
	panel_style.set_border_width_all(PANEL_BORDER_WIDTH)

	var screen_theme: Theme = Theme.new()
	screen_theme.default_font_size = FONT_SIZE
	screen_theme.set_stylebox(&"panel", &"PanelContainer", panel_style)
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		screen_theme.set_constant(side, &"MarginContainer", PANEL_MARGIN)
	screen_theme.set_constant(&"separation", &"VBoxContainer", ROW_SEPARATION)
	screen_theme.set_constant(&"separation", &"HBoxContainer", BUTTON_SEPARATION)
	screen_theme.set_constant(&"h_separation", &"GridContainer", GRID_H_SEPARATION)
	screen_theme.set_constant(&"v_separation", &"GridContainer", GRID_V_SEPARATION)
	# The default theme draws popup menu separators with a line of width 1.
	# This screen adds no separator, but the style is replaced all the same.
	var separator_style: StyleBoxLine = StyleBoxLine.new()
	separator_style.color = COLOR_PANEL_BORDER
	separator_style.thickness = SEPARATOR_WIDTH
	for style_name: StringName in [&"separator", &"labeled_separator_left", &"labeled_separator_right"]:
		screen_theme.set_stylebox(style_name, &"PopupMenu", separator_style)
	theme = screen_theme

	_background.color = COLOR_BACKGROUND
	_confirm_dim.color = COLOR_DIM
	_title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	_graphics_title.add_theme_font_size_override(&"font_size", SECTION_FONT_SIZE)
	_audio_title.add_theme_font_size_override(&"font_size", SECTION_FONT_SIZE)
	_error_label.add_theme_color_override(&"font_color", COLOR_ERROR)

	_window_mode_option.custom_minimum_size = CONTROL_MIN_SIZE
	_window_size_option.custom_minimum_size = CONTROL_MIN_SIZE
	_vsync_check.custom_minimum_size.y = CONTROL_MIN_SIZE.y
	for slider: HSlider in [_master_slider, _music_slider, _sfx_slider]:
		slider.custom_minimum_size = SLIDER_MIN_SIZE
	for value_label: Label in [_master_value, _music_value, _sfx_value]:
		value_label.custom_minimum_size.x = VALUE_LABEL_MIN_WIDTH
	for button: Button in [_reset_button, _close_button, _confirm_yes_button, _confirm_no_button]:
		button.custom_minimum_size = BUTTON_MIN_SIZE
