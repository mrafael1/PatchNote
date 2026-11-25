class_name UiTheme
extends RefCounted
## M47.4 (PLAN 1.16): the menus' Theme, built in code. Applied only to the roots of the title,
## the menus, pause, the polished debrief and the stage card; never as the project theme,
## never to the HUD or the corner mascot.
##
## Neutral until a look is picked (M48.5's `use(look)`): its default font and size are the
## engine's fallback ones, so every control that sets no type variation renders exactly as it
## did (M47.2's band layout and bubble sizing do not move; test_front_door re-measures them).
## The type variations below are used only by the new controls (title buttons, the menu
## panel, the chat window and its bar, key chips).

const TITLE_BUTTON := &"TitleButton"
const MENU_PANEL := &"MenuPanel"
const CHAT_WINDOW := &"ChatWindow"
const CHAT_BAR := &"ChatBar"
const KEY_CHIP := &"KeyChip"

static var _theme: Theme


## The engine's fallback font until a look is picked.
static func font() -> Font:
	return ThemeDB.fallback_font


static func theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


## Sets `root.theme` (the only way this theme reaches a control).
static func apply(root: Control) -> void:
	if root != null:
		root.theme = theme()


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = ThemeDB.fallback_font_size
	# Title buttons: a quiet dark face, a 2 px accent bar on the left when lit.
	t.set_type_variation(TITLE_BUTTON, &"Button")
	var normal := _box(Color(Palette.UI_PANEL, 0.0), Color(1, 1, 1, 0), 0)
	normal.content_margin_left = 18.0
	var lit := _box(Color(1, 1, 1, 0.07), Palette.ACCENT, 0)
	lit.border_width_left = 3
	lit.content_margin_left = 18.0
	t.set_stylebox(&"normal", TITLE_BUTTON, normal)
	t.set_stylebox(&"disabled", TITLE_BUTTON, normal)
	for state: StringName in [&"hover", &"pressed", &"focus", &"hover_pressed"]:
		t.set_stylebox(state, TITLE_BUTTON, lit)
	t.set_color(&"font_color", TITLE_BUTTON, Palette.UI_SOFT)
	t.set_color(&"font_hover_color", TITLE_BUTTON, Palette.UI_TEXT)
	t.set_color(&"font_focus_color", TITLE_BUTTON, Palette.ACCENT)
	t.set_color(&"font_pressed_color", TITLE_BUTTON, Palette.ACCENT)
	t.set_color(&"font_disabled_color", TITLE_BUTTON, Color(1, 1, 1, 0.3))
	t.set_font_size(&"font_size", TITLE_BUTTON, 24)
	t.set_constant(&"align_to_largest_stylebox", TITLE_BUTTON, 1)
	# The menu panel and the chat window: the UI panel colour, a 1 px accent frame.
	t.set_type_variation(MENU_PANEL, &"PanelContainer")
	var panel := _box(Palette.UI_PANEL, Color(Palette.ACCENT, 0.35), 1)
	panel.set_content_margin_all(14.0)
	t.set_stylebox(&"panel", MENU_PANEL, panel)
	t.set_type_variation(CHAT_WINDOW, &"PanelContainer")
	var window := _box(Palette.UI_PANEL, Palette.ACCENT, 1)
	window.set_content_margin_all(0.0)
	t.set_stylebox(&"panel", CHAT_WINDOW, window)
	t.set_type_variation(CHAT_BAR, &"Label")
	t.set_color(&"font_color", CHAT_BAR, Palette.UI_DIM)
	t.set_font_size(&"font_size", CHAT_BAR, 14)
	# A key chip: "[1]", "[Enter]" in a small outlined box.
	t.set_type_variation(KEY_CHIP, &"Label")
	var chip := _box(Color(Palette.SCRIM, 0.6), Color(1, 1, 1, 0.35), 1)
	chip.content_margin_left = 6.0
	chip.content_margin_right = 6.0
	chip.content_margin_top = 1.0
	chip.content_margin_bottom = 1.0
	t.set_stylebox(&"normal", KEY_CHIP, chip)
	t.set_color(&"font_color", KEY_CHIP, Palette.UI_SOFT)
	t.set_font_size(&"font_size", KEY_CHIP, 14)
	return t


static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(4)
	return b


## The chat window's frame (DebriefScreen, StageCard): this theme's, or the look's UI panel.
static func window_style() -> StyleBox:
	if Skins.is_on(&"ui_panel") and Skins.current.ui_panel() != null:
		return Skins.current.ui_panel(false)
	return theme().get_stylebox(&"panel", CHAT_WINDOW)


## M47.5a: the raw terminal's monospace font, made in code (no font file): the first of
## these the system has, else Godot's own fallback.
static var _mono: SystemFont


static func mono_font() -> Font:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "DejaVu Sans Mono",
				"Courier New", "monospace"])
		_mono.fallbacks = [ThemeDB.fallback_font]
	return _mono


## A key chip Label ("1", "Enter"): the KeyChip variation.
static func key_chip(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = KEY_CHIP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l
