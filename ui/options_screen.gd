class_name OptionsScreen
extends Control
## PLAN v9.1 1.16 (M47.3): the options, one screen with 4 tabs (Q / E or LB / RB switch
## them; Esc, the pad's B or Back returns). Opened from pause (and from the title in
## M47.4). Every change goes through Settings.set_value (applied at once, nothing written);
## close() commits once. Audio: the 4 bus sliders and "Mute when unfocused". Video: window
## mode, vsync, the fps cap, window scale (greyed with a note where they cannot apply:
## headless, --fixed-fps, tools). Controls: read-only, every action with its key on the
## player's layout and its Xbox pad name. Accessibility: reduce flashing, shake, text
## speed, key hints, mascot chatter.

signal closed

const TABS: Array[String] = ["Audio", "Video", "Controls", "Accessibility"]
const WINDOW_MODES: Array[String] = ["Windowed", "Fullscreen", "Borderless"]
const FPS_CAPS: Array[int] = [0, 30, 60, 120, 144]
const SCALES: Array[float] = [1.0, 1.5, 2.0]
const TEXT_SPEEDS: Array[int] = [30, 45, 70, 0]
const TEXT_SPEED_NAMES: Array[String] = ["Slow", "Normal", "Fast", "Instant"]
const REMAP_LINE := "Remapping comes in a later patch."
const IGNORED := "(ignored in this build)"
## The Controls tab: label, actions (their keys joined), the keyboard text when no key
## is bound (the mouse), the pad text when the actions' own pad binds are not the name.
const CONTROL_ROWS: Array = [
	["Move", [&"move_up", &"move_left", &"move_down", &"move_right"], "", "Left stick"],
	["Aim", [], "Mouse", "Right stick"],
	["Shoot", [&"shoot"], "", ""],
	["Dash", [&"dash"], "", ""],
	["Jump", [&"jump"], "", ""],
	["Wait a turn (grid)", [&"wait"], "", ""],
	["Previous weapon", [&"weapon_prev"], "", ""],
	["Next weapon", [&"weapon_next"], "", ""],
	["Weapon 1 / 2 / 3", [&"weapon_1", &"weapon_2", &"weapon_3"], "", "LB / RB"],
	["Build log", [&"patch_history"], "", ""],
	["Pause", [&"pause"], "", ""],
	["Choose a card", [&"choose_1", &"choose_2", &"choose_3", &"choose_4"], "", "D-pad + A"],
]
const PAD_BUTTONS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}
const PAD_AXES := {
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
	JOY_AXIS_LEFT_X: "Left stick", JOY_AXIS_LEFT_Y: "Left stick",
	JOY_AXIS_RIGHT_X: "Right stick", JOY_AXIS_RIGHT_Y: "Right stick",
}
const MOUSE_BUTTONS := {
	MOUSE_BUTTON_LEFT: "Left click", MOUSE_BUTTON_RIGHT: "Right click",
	MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down",
}

var tab := 0
var _panel: PanelContainer
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _focus: Array = []          ## per tab: its focusable controls, top to bottom
var _back: Button
var _shake_note: Label
var _shake_value: Label
var _controls := {}             ## key -> the control showing it (tests, refresh)
var _sliders := {}              ## key -> its value label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "OptionsPanel"
	_panel.custom_minimum_size = Vector2(760, 600)
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	margin.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	column.add_child(head)
	var title := Label.new()
	title.text = "OPTIONS"
	title.add_theme_font_size_override(&"font_size", 26)
	title.add_theme_color_override(&"font_color", Palette.UI_TEXT)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var prev := Label.new()
	prev.text = "[%s]" % InputSetup.key_label(&"weapon_prev")
	prev.add_theme_color_override(&"font_color", Palette.UI_DIM)
	head.add_child(prev)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(show_tab.bind(i))
		head.add_child(b)
		_tab_buttons.append(b)
	var next := Label.new()
	next.text = "[%s]" % InputSetup.key_label(&"weapon_next")
	next.add_theme_color_override(&"font_color", Palette.UI_DIM)
	head.add_child(next)

	var pages := Control.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(pages)
	for i in TABS.size():
		var scroll := ScrollContainer.new()
		scroll.name = TABS[i]
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override(&"separation", 12)
		scroll.add_child(page)
		var pad := Control.new()   # the first row's focus frame is not clipped by the scroll
		pad.custom_minimum_size = Vector2(0, 2)
		page.add_child(pad)
		pages.add_child(scroll)
		_pages.append(scroll)
		_focus.append([])
	_build_audio(_pages[0].get_child(0) as Control)
	_build_video(_pages[1].get_child(0) as Control)
	_build_controls(_pages[2].get_child(0) as Control)
	_build_access(_pages[3].get_child(0) as Control)

	var foot := HBoxContainer.new()
	column.add_child(foot)
	var hint := Label.new()
	hint.text = "[%s] back" % InputSetup.key_label(&"pause")
	hint.add_theme_color_override(&"font_color", Palette.UI_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	_back = Button.new()
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(140, 40)
	_back.pressed.connect(close)
	foot.add_child(_back)
	for list: Array in _focus:
		list.append(_back)
	_dress()
	Skins.hub.skin_changed.connect(_on_skin_changed)
	show_tab(0)


func _exit_tree() -> void:
	if Skins.hub.skin_changed.is_connected(_on_skin_changed):
		Skins.hub.skin_changed.disconnect(_on_skin_changed)


func _on_skin_changed(_skin: ArtSkin) -> void:
	_dress()


func _dress() -> void:
	_panel.remove_theme_stylebox_override(&"panel")
	if Skins.is_on(&"ui_panel"):
		Skins.dress_panel(_panel)
	else:
		var box := StyleBoxFlat.new()
		box.bg_color = Palette.UI_PANEL
		box.border_color = Color(1, 1, 1, 0.18)
		box.set_border_width_all(1)
		box.set_corner_radius_all(6)
		_panel.add_theme_stylebox_override(&"panel", box)
	for b in _tab_buttons + [_back]:
		Skins.redress_button(b)


# --- Open / close / tabs -------------------------------------------------------

func open(at_tab := 0) -> void:
	_refresh()
	visible = true
	show_tab(at_tab)


## Back: writes the settings once (inert: memory only) and says so.
func close() -> void:
	if not visible:
		return
	visible = false
	Settings.commit()
	closed.emit()


func show_tab(i: int) -> void:
	tab = posmod(i, TABS.size())
	for j in _pages.size():
		_pages[j].visible = j == tab
		_tab_buttons[j].set_pressed_no_signal(j == tab)
	var list: Array = _focus[tab]
	_wrap(list)
	if visible and is_inside_tree():
		for c: Control in list:
			if c.focus_mode != Control.FOCUS_NONE:
				c.grab_focus()
				break


static func _wrap(list: Array) -> void:
	var live: Array[Control] = []
	for c: Control in list:
		if c.focus_mode != Control.FOCUS_NONE:
			live.append(c)
	for i in live.size():
		var up := live[(i - 1 + live.size()) % live.size()]
		var down := live[(i + 1) % live.size()]
		live[i].focus_neighbor_top = live[i].get_path_to(up)
		live[i].focus_neighbor_bottom = live[i].get_path_to(down)
		live[i].focus_previous = live[i].focus_neighbor_top
		live[i].focus_next = live[i].focus_neighbor_bottom


func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") \
			or _pad_pressed(event, JOY_BUTTON_B):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"weapon_prev") and not event is InputEventMouseButton:
		show_tab(tab - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"weapon_next") and not event is InputEventMouseButton:
		show_tab(tab + 1)
		get_viewport().set_input_as_handled()


static func _pad_pressed(event: InputEvent, button: JoyButton) -> bool:
	var pad := event as InputEventJoypadButton
	return pad != null and pad.pressed and pad.button_index == button


# --- Rows ----------------------------------------------------------------------

func _row(page: Control, text: String, control: Control, note := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(240, 0)
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_color", Palette.UI_TEXT)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	if note != "":
		var n := Label.new()
		n.text = note
		n.add_theme_color_override(&"font_color", Palette.UI_DIM)
		row.add_child(n)
	page.add_child(row)
	return row


func _slider(page: Control, tab_i: int, text: String, key: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(240, 28)
	s.value = float(Settings.get_value(key))
	var row := _row(page, text, s)
	var value := Label.new()
	value.custom_minimum_size = Vector2(56, 0)
	value.add_theme_color_override(&"font_color", Palette.UI_SOFT)
	value.text = "%d%%" % roundi(s.value * 100.0)
	row.add_child(value)
	_sliders[key] = value
	s.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, v)
		value.text = "%d%%" % roundi(v * 100.0)
		if key == "shake":
			_refresh_shake_note())
	_controls[key] = s
	_focus[tab_i].append(s)
	return s


func _check(page: Control, tab_i: int, text: String, key: String, note := "") -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get_value(key)) if key != "reduce_flashing" else SaveGame.reduce_flashing()
	c.toggled.connect(func(on: bool) -> void:
		Settings.set_value(key, on)
		if key == "reduce_flashing":
			_refresh_shake_note())
	_row(page, text, c, note)
	c.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	_controls[key] = c
	_focus[tab_i].append(c)
	return c


func _choice(page: Control, tab_i: int, text: String, key: String, names: Array, values: Array,
		note := "") -> OptionButton:
	var o := OptionButton.new()
	for n: String in names:
		o.add_item(n)
	o.selected = maxi(0, _index_of(values, Settings.get_value(key)))
	o.item_selected.connect(func(i: int) -> void: Settings.set_value(key, values[i]))
	_row(page, text, o, note)
	_controls[key] = o
	_focus[tab_i].append(o)
	return o


static func _index_of(values: Array, v: Variant) -> int:
	for i in values.size():
		if is_equal_approx(float(values[i]), float(v)):
			return i
	return -1


func _build_audio(page: Control) -> void:
	_slider(page, 0, "Master volume", "vol_master")
	_slider(page, 0, "Sound effects", "vol_sfx")
	_slider(page, 0, "Interface", "vol_ui")
	_slider(page, 0, "The AI's voice", "vol_voice")
	_check(page, 0, "Mute when unfocused", "mute_unfocused")


func _build_video(page: Control) -> void:
	var note := "" if Settings.window_applies() else IGNORED
	var scale_names: Array = []
	for s in SCALES:
		scale_names.append("%sx" % str(s).trim_suffix(".0"))
	var fps_names: Array = []
	for f in FPS_CAPS:
		fps_names.append("Off" if f == 0 else str(f))
	var list: Array[Control] = [
		_choice(page, 1, "Window mode", "window_mode", WINDOW_MODES, [0, 1, 2], note),
		_check(page, 1, "Vsync", "vsync", note),
		_choice(page, 1, "Frame rate cap", "fps_cap", fps_names, Array(FPS_CAPS), note),
		_choice(page, 1, "Window scale", "window_scale", scale_names, Array(SCALES), note),
	]
	if note != "":
		for c in list:
			(c as BaseButton).disabled = true
			c.focus_mode = Control.FOCUS_NONE


func _build_controls(page: Control) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 28)
	grid.add_theme_constant_override(&"v_separation", 3)
	page.add_child(grid)
	for h: String in ["Action", "Keyboard / mouse", "Xbox pad"]:
		grid.add_child(_cell(h, Palette.ACCENT))
	for row: Array in CONTROL_ROWS:
		grid.add_child(_cell(row[0], Palette.UI_TEXT))
		grid.add_child(_cell(keyboard_text(row[1], row[2]), Palette.UI_SOFT))
		grid.add_child(_cell(pad_text(row[1], row[3]), Palette.UI_SOFT))
	var remap := Label.new()
	remap.text = REMAP_LINE
	remap.add_theme_color_override(&"font_color", Palette.UI_DIM)
	page.add_child(remap)


func _cell(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 16)
	l.add_theme_color_override(&"font_color", color)
	return l


## The keyboard and mouse binds of `actions` on the player's layout: each action's first
## key (InputSetup.key_label: AZERTY shows Z Q S D), then its mouse buttons.
static func keyboard_text(actions: Array, fallback := "", to_label := Callable()) -> String:
	if actions.is_empty():
		return fallback
	var keys := PackedStringArray()
	for a: StringName in actions:
		var k := InputSetup.key_label(a, to_label)
		if k != "" and not k in keys:
			keys.append(k)
	var out := " ".join(keys) if actions.size() > 1 else (keys[0] if not keys.is_empty() else "")
	if actions.size() == 1:
		var extra := PackedStringArray()
		for ev in InputMap.action_get_events(actions[0]):
			var k := ev as InputEventKey
			if k != null:
				var label := _key_text(k, to_label)
				if label != out and not label in extra:
					extra.append(label)
			var m := ev as InputEventMouseButton
			if m != null and MOUSE_BUTTONS.has(m.button_index):
				extra.append(MOUSE_BUTTONS[m.button_index])
		if not extra.is_empty():
			if out != "":
				extra.insert(0, out)
			out = " / ".join(extra)
	return out if out != "" else fallback


static func _key_text(k: InputEventKey, to_label: Callable) -> String:
	var code := k.keycode
	if k.physical_keycode != KEY_NONE:
		code = InputSetup.layout_label(k.physical_keycode) if not to_label.is_valid() \
				else to_label.call(k.physical_keycode)
		if code == KEY_NONE:
			code = k.physical_keycode
		code = InputSetup.number_row_label(k.physical_keycode, code)
	return OS.get_keycode_string(code)


## The Xbox names of `actions`' pad binds ("" -> `fallback`).
static func pad_text(actions: Array, fallback := "") -> String:
	if fallback != "":
		return fallback
	var names := PackedStringArray()
	for a: StringName in actions:
		for ev in InputMap.action_get_events(a):
			var n := ""
			if ev is InputEventJoypadButton:
				n = PAD_BUTTONS.get((ev as InputEventJoypadButton).button_index, "")
			elif ev is InputEventJoypadMotion:
				n = PAD_AXES.get((ev as InputEventJoypadMotion).axis, "")
			if n != "" and not n in names:
				names.append(n)
	return " / ".join(names) if not names.is_empty() else "-"


func _build_access(page: Control) -> void:
	_check(page, 3, "Reduce flashing", "reduce_flashing")
	_slider(page, 3, "Screen shake", "shake")
	_shake_note = Label.new()
	_shake_note.add_theme_color_override(&"font_color", Palette.UI_DIM)
	page.add_child(_shake_note)
	_choice(page, 3, "Text speed", "text_speed", TEXT_SPEED_NAMES, Array(TEXT_SPEEDS))
	_check(page, 3, "Key hints", "key_hints")
	_check(page, 3, "Mascot chatter", "chatter", "(the script still speaks)")
	_refresh_shake_note()


func _refresh_shake_note() -> void:
	if _shake_note == null:
		return
	var capped := SaveGame.reduce_flashing() and float(Settings.get_value("shake")) > Settings.REDUCED_SHAKE
	_shake_note.text = "    capped at 50% while Reduce flashing is on" if capped else ""
	_shake_note.visible = capped


## Every control re-reads its setting (the menu opened again after a change elsewhere).
func _refresh() -> void:
	for key: String in _controls:
		var c: Control = _controls[key]
		var v: Variant = SaveGame.reduce_flashing() if key == "reduce_flashing" else Settings.get_value(key)
		if c is HSlider:
			(c as HSlider).set_value_no_signal(float(v))
			if _sliders.has(key):
				(_sliders[key] as Label).text = "%d%%" % roundi(float(v) * 100.0)
		elif c is CheckButton:
			(c as CheckButton).set_pressed_no_signal(bool(v))
		elif c is OptionButton:
			var values: Array = []
			match key:
				"window_mode": values = [0, 1, 2]
				"fps_cap": values = Array(FPS_CAPS)
				"window_scale": values = Array(SCALES)
				"text_speed": values = Array(TEXT_SPEEDS)
			(c as OptionButton).selected = maxi(0, _index_of(values, v))
	_refresh_shake_note()


func control_for(key: String) -> Control:
	return _controls.get(key)
