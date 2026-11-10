extends RefCounted
## Temporary look shared by the game screens (docs/leader/13 design 8.4,
## rule 15): the screen host, the workshop, the day summary and the panels in
## scenes/common/. Every colour, font size and spacing of those is here.
## All of it is a placeholder until the art direction is decided.
## No line here is thinner than 2 (rule 14).
##
## The title screen still has its own copy in scripts/title/title_style.gd.

const COLOR_BACKGROUND: Color = Color(0.10, 0.11, 0.13)
const COLOR_PANEL: Color = Color(0.17, 0.19, 0.23)
const COLOR_PANEL_BORDER: Color = Color(0.55, 0.58, 0.65)
const COLOR_DIM: Color = Color(0.0, 0.0, 0.0, 0.6)
const PANEL_BORDER_WIDTH: int = 2

const FONT_SIZE: int = 36
const HEADING_FONT_SIZE: int = 64
const PANEL_HEADING_FONT_SIZE: int = 48

const SCREEN_ROW_SEPARATION: int = 36
const SCREEN_BUTTON_MIN_SIZE: Vector2 = Vector2(420.0, 76.0)

const PANEL_MARGIN: int = 48
const PANEL_ROW_SEPARATION: int = 28
const PANEL_BUTTON_SEPARATION: int = 24
const PANEL_BUTTON_MIN_SIZE: Vector2 = Vector2(220.0, 64.0)
const PANEL_MENU_BUTTON_MIN_SIZE: Vector2 = Vector2(420.0, 72.0)
## A question or notice wider than this is wrapped to this width.
const DIALOG_MESSAGE_MAX_WIDTH: float = 900.0


## Theme for the content of a whole screen.
static func make_screen_theme() -> Theme:
	var screen_theme: Theme = Theme.new()
	screen_theme.default_font_size = FONT_SIZE
	screen_theme.set_constant(&"separation", &"VBoxContainer", SCREEN_ROW_SEPARATION)
	return screen_theme


## Theme for a panel that opens over a screen.
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
	panel_theme.set_constant(&"separation", &"HBoxContainer", PANEL_BUTTON_SEPARATION)
	return panel_theme
