extends RefCounted
## Temporary look of the title screen and its panels (docs/roles/leader/outputs/10 design
## 5.4, rule 14). Every colour, font size and spacing of scenes/title/ and scripts/title/ is here.
## All of it is a placeholder until the art direction is decided.
## No line here is thinner than 2 (rule 12).

const COLOR_BACKGROUND: Color = Color(0.10, 0.11, 0.13)
const COLOR_PANEL: Color = Color(0.17, 0.19, 0.23)
const COLOR_PANEL_BORDER: Color = Color(0.55, 0.58, 0.65)
const COLOR_DIM: Color = Color(0.0, 0.0, 0.0, 0.6)
const PANEL_BORDER_WIDTH: int = 2

const FONT_SIZE: int = 36
const GAME_TITLE_FONT_SIZE: int = 96
const PANEL_TITLE_FONT_SIZE: int = 48

const TITLE_MENU_SEPARATION: int = 72
const MENU_SEPARATION: int = 20
const MENU_BUTTON_MIN_SIZE: Vector2 = Vector2(420.0, 76.0)

const PANEL_MARGIN: int = 48
const PANEL_ROW_SEPARATION: int = 28
const PANEL_BUTTON_MIN_SIZE: Vector2 = Vector2(220.0, 64.0)
const CREDITS_SCROLL_MIN_SIZE: Vector2 = Vector2(900.0, 420.0)
const CREDITS_LINE_SEPARATION: int = 16


## Theme for the panels that open over the title screen.
static func make_panel_theme() -> Theme:
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL
	panel_style.border_color = COLOR_PANEL_BORDER
	panel_style.set_border_width_all(PANEL_BORDER_WIDTH)

	var panel_theme: Theme = Theme.new()
	panel_theme.default_font_size = FONT_SIZE
	panel_theme.set_stylebox(&"panel", &"PanelContainer", panel_style)
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		panel_theme.set_constant(side, &"MarginContainer", PANEL_MARGIN)
	panel_theme.set_constant(&"separation", &"VBoxContainer", PANEL_ROW_SEPARATION)
	return panel_theme


## Theme for the game title and the menu.
static func make_menu_theme() -> Theme:
	var menu_theme: Theme = Theme.new()
	menu_theme.default_font_size = FONT_SIZE
	menu_theme.set_constant(&"separation", &"VBoxContainer", MENU_SEPARATION)
	return menu_theme
