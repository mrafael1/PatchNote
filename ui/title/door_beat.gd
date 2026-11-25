class_name DoorBeat
extends Control
## M47.4 (PLAN 3.2, v9.1): the front door being built, on S7's stage card before its cook beat
## (and a 6 s cut of it on the title: the unveil). The raw start column shows; the mascot
## says why; under a glitch wipe (a crossfade under reduce flashing) the logo assembles, the
## buttons slide into a menu, the seed / flashing / fullscreen / volume rows fly into
## "Options" and a pause chip shows `{key:pause}`; then two more lines.
##
## Deterministic: every pose is a function of `elapsed` (frame time, driven by its owner's
## step(); no RNG, Engine.time_scale never read). The replica is built from StartScreen's
## own texts; it never instantiates StartScreen (no save, no autostart).

signal say(line: Line)
signal finished

const LENGTH := 12.0
## Each line is said once the one before has typed at the slowest text speed (30 cps) and
## stayed up for SessionRunner.read_seconds() (review: line 2 was cut after 0.6 s).
const LINE_AT: Array[float] = [0.3, 7.0, 11.2]
const WIPE_FROM := 3.0
const WIPE_TO := 4.0
const LOGO_FROM := 4.0
const LOGO_TO := 6.0
const SLIDE_FROM := 6.0
const SLIDE_TO := 7.5
const FLY_FROM := 7.5
const FLY_TO := 9.0
const FLY_EACH := 0.9        ## one row's flight; the rows leave FLY_STAGGER apart
const FLY_STAGGER := 0.15
const CHIP_AT := 9.0
const CUT_FROM := 3.0        ## the title's unveil: the wipe to the pause chip, no lines
const CUT_TO := 9.0
const SKIP_AFTER := 0.5
## The raw column, as StartScreen builds it (the replica's texts; test_front_door checks them
## against the recorded raw screen).
const RAW_ROWS: Array[String] = ["Seed", "Less flashing", "Fullscreen", "Volume"]
const RAW_SEED := "Seed (empty = random)"
const COLUMN_W := 420.0
const COLUMN_SEP := 16.0
const BIG_H := 54.0
const ROW_LABEL_W := 110.0

var lines: Array[Line] = []
var cut := false
var gentle := false
var elapsed := 0.0
var said := 0

var _done := false
var _built := false
var _start := {}             ## item -> Rect2 in the raw column
var _bg: ColorRect
var _backdrop: TitleBackdrop
var _raw_title: Label
var _raw_sub: Label
var _save: Label
var _buttons: Array[Button] = []   ## Continue, New game, Quit
var _rows: Array[Control] = []
var _logo: TitleLogo
var _version: Label
var _panel: PanelContainer
var _options: Button
var _pause: Label
var _glitch: ColorRect
var _dressed := {}           ## ghost button -> the look dress it wears (Skins.version, titled)


func setup(p_lines: Array[Line], p_cut := false, p_gentle := false) -> void:
	lines = p_lines
	cut = p_cut
	gentle = p_gentle
	elapsed = CUT_FROM if cut else 0.0


func start_at() -> float:
	return CUT_FROM if cut else 0.0


func end_at() -> float:
	return CUT_TO if cut else LENGTH


func is_done() -> bool:
	return _done


func said_count() -> int:
	return said


## The wipe's glitch strength now: one pulse 0 -> 1 -> 0 over the wipe; 0 under reduce
## flashing.
func glitch_strength() -> float:
	if gentle or elapsed <= WIPE_FROM or elapsed >= WIPE_TO:
		return 0.0
	return sin(PI * (elapsed - WIPE_FROM) / (WIPE_TO - WIPE_FROM))


## The raw-to-title crossfade (0..1, monotone): the whole change under reduce flashing.
func crossfade() -> float:
	return clampf((elapsed - WIPE_FROM) / (WIPE_TO - WIPE_FROM), 0.0, 1.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(self)
	_bg = ColorRect.new()
	_bg.color = Palette.TITLE_BG
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_backdrop = TitleBackdrop.new()
	_backdrop.running = false
	add_child(_backdrop)
	_panel = PanelContainer.new()
	_panel.name = "MenuGhost"
	_panel.theme_type_variation = UiTheme.MENU_PANEL
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Skins.dress_panel(_panel)   # the title's menu wears the look's UI panel when it is on
	add_child(_panel)
	_raw_title = _label("PATCH NOTES", 44, Palette.ACCENT)
	_raw_sub = _label("prototype build %s" % Main.BUILD, 16, Color(1, 1, 1, 0.5))
	_save = _label(StartScreen.campaign_line(), 20, Palette.UI_TEXT)
	for text in [StartScreen.CONTINUE, StartScreen.NEW_GAME]:
		var b := _ghost_button(text)
		b.custom_minimum_size = Vector2(0, BIG_H)
		b.add_theme_font_size_override(&"font_size", 24)
		_buttons.append(b)
	for text in RAW_ROWS:
		_rows.append(_raw_row(text))
	_buttons.append(_ghost_button("Quit"))
	_logo = TitleLogo.new()
	_logo.position = TitleScreen.LOGO_AT
	_logo.size = TitleLogo.logo_size()
	add_child(_logo)
	_version = UiTheme.key_chip(SaveGame.version().label())
	_version.position = TitleScreen.CHIP_AT
	add_child(_version)
	_options = _ghost_button("Options")
	_options.theme_type_variation = UiTheme.TITLE_BUTTON
	_options.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_pause = UiTheme.key_chip(InputSetup.expand_keys("{key:pause} pause"))
	add_child(_pause)
	_glitch = ColorRect.new()
	_glitch.name = "Glitch"
	_glitch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = Transition.GLITCH_SHADER
	mat.set_shader_parameter(&"seed", 7.0)
	_glitch.material = mat
	_glitch.visible = false
	add_child(_glitch)
	_layout()
	_pose()


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _ghost_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(b)
	return b


func _raw_row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(ROW_LABEL_W, 0)
	row.add_child(label)
	var control: Control
	match text:
		"Seed":
			var seed_edit := LineEdit.new()
			seed_edit.placeholder_text = RAW_SEED
			seed_edit.editable = false
			control = seed_edit
		"Volume":
			var slider := HSlider.new()
			slider.min_value = 0.0
			slider.max_value = 1.0
			slider.step = 0.05
			slider.value = float(Settings.get_value("vol_master"))
			slider.editable = false
			control = slider
		_:
			var check := CheckButton.new()
			check.button_pressed = text == "Less flashing" and SaveGame.reduce_flashing()
			control = check
	control.focus_mode = Control.FOCUS_NONE
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	add_child(row)
	return row


## Every replica text, in column order (tests compare them with the recorded raw screen).
func replica_texts() -> Array[String]:
	var out: Array[String] = [_raw_title.text, _raw_sub.text]
	for b in _buttons:
		out.append(b.text)
	out.append_array(RAW_ROWS)
	out.append(RAW_SEED)
	return out


## The raw column's rects: StartScreen's CenterContainer + VBox (420 wide, 16 apart),
## worked out from each item's minimum size.
func _layout() -> void:
	var view := get_viewport_rect().size
	var column: Array[Control] = [_raw_title, _raw_sub, _save, _buttons[0], _buttons[1]]
	column.append_array(_rows)
	column.append(_buttons[2])
	var total := COLUMN_SEP * float(column.size() - 1)
	for c in column:
		total += c.get_combined_minimum_size().y
	var y := floorf((view.y - total) * 0.5)
	var x := floorf((view.x - COLUMN_W) * 0.5)
	for c in column:
		var h := c.get_combined_minimum_size().y
		_start[c] = Rect2(x, y, COLUMN_W, h)
		y += h + COLUMN_SEP
	var menu := TitleScreen.menu_rect(4)
	_panel.position = menu.position
	_panel.size = menu.size
	var o := TitleScreen.item_rect(2)
	_options.position = o.position
	_options.size = o.size
	_pause.position = TitleScreen.pause_chip_at(view)
	_built = true


## Drives the beat (its owner's _process, or a test by hand).
func step(delta: float) -> void:
	if _done:
		return
	elapsed = minf(elapsed + delta, end_at())
	_say_due()
	_pose()
	if elapsed >= end_at():
		_done = true
		finished.emit()


## Jumps to the end (a key, the bot): the final pose, no more lines.
func finish() -> void:
	if _done:
		return
	elapsed = end_at()
	said = maxi(said, _lines_before(end_at()))
	_pose()
	_done = true
	finished.emit()


func _lines_before(t: float) -> int:
	if cut:
		return 0
	var n := 0
	for i in mini(lines.size(), LINE_AT.size()):
		if t >= LINE_AT[i]:
			n = i + 1
	return n


func _say_due() -> void:
	var due := _lines_before(elapsed)
	while said < due:
		say.emit(lines[said])
		said += 1


static func _k(t: float, from: float, to: float) -> float:
	return clampf((t - from) / (to - from), 0.0, 1.0)


static func _ease(k: float) -> float:
	return 1.0 - pow(1.0 - k, 3.0)


func _place(c: Control, r: Rect2) -> void:
	c.position = r.position
	c.size = r.size


func _pose() -> void:
	if not _built:
		return
	var t := elapsed
	var wipe := crossfade()
	var strength := glitch_strength()
	_glitch.visible = strength > 0.0
	(_glitch.material as ShaderMaterial).set_shader_parameter(&"strength", strength)
	# The raw title and its build line go under the wipe (fade out under reduce flashing).
	var raw_alpha := (1.0 - wipe) if gentle else (1.0 if t < (WIPE_FROM + WIPE_TO) * 0.5 else 0.0)
	_raw_title.modulate.a = raw_alpha
	_raw_sub.modulate.a = raw_alpha
	_place(_raw_title, _start[_raw_title])
	_place(_raw_sub, _start[_raw_sub])
	_backdrop.modulate.a = wipe
	_backdrop.scroll = TitleBackdrop.SPEED * t
	_backdrop.queue_redraw()
	# The logo assembles.
	_logo.visible = t >= LOGO_FROM or (gentle and wipe > 0.0)
	_logo.modulate.a = wipe if gentle else 1.0
	_logo.assembled = _k(t, LOGO_FROM, LOGO_TO)
	# The buttons slide into the menu; the save line moves under the logo.
	var slide := _ease(_k(t, SLIDE_FROM, SLIDE_TO))
	_panel.modulate.a = _k(t, SLIDE_FROM, SLIDE_TO)
	var targets := [TitleScreen.item_rect(0), TitleScreen.item_rect(1), TitleScreen.item_rect(3)]
	for i in _buttons.size():
		var b := _buttons[i]
		var from: Rect2 = _start[b]
		var to: Rect2 = targets[i]
		_place(b, Rect2(from.position.lerp(to.position, slide), from.size.lerp(to.size, slide)))
		var titled := slide >= 0.5
		b.theme_type_variation = UiTheme.TITLE_BUTTON if titled else &""
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT if titled else HORIZONTAL_ALIGNMENT_CENTER
		_dress_ghost(b, titled)
		if titled:
			b.remove_theme_font_size_override(&"font_size")
		elif i < 2:
			b.add_theme_font_size_override(&"font_size", 24)
	var save_from: Rect2 = _start[_save]
	var save_to := Rect2(TitleScreen.save_line_at(), Vector2(COLUMN_W, save_from.size.y))
	_place(_save, Rect2(save_from.position.lerp(save_to.position, slide), save_from.size))
	_save.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if slide >= 0.5 else HORIZONTAL_ALIGNMENT_CENTER
	_version.modulate.a = _k(t, SLIDE_FROM, SLIDE_FROM + 0.5)
	# The rows fly into Options, one after another, shrinking.
	_options.modulate.a = _k(t, FLY_FROM, FLY_FROM + 0.3)
	var into := TitleScreen.item_rect(2).get_center()
	for i in _rows.size():
		var row := _rows[i]
		var from: Rect2 = _start[row]
		var k := _ease(_k(t, FLY_FROM + FLY_STAGGER * i, FLY_FROM + FLY_STAGGER * i + FLY_EACH))
		var s := lerpf(1.0, 0.15, k)
		row.size = from.size
		row.pivot_offset = from.size * 0.5
		row.scale = Vector2(s, s)
		row.position = from.position.lerp(into - from.size * 0.5, k)
		row.modulate.a = 1.0 - _k(k, 0.6, 1.0)
	_pause.visible = t >= CHIP_AT
	_pause.modulate.a = _k(t, CHIP_AT, CHIP_AT + 0.3)
	_dress_ghost(_options, true)


## A ghost button wears what TitleScreen._dress gives the real one once it is in the menu
## (the look's UI panel when the `ui` group is on), so the end pose matches the title.
func _dress_ghost(b: Button, titled: bool) -> void:
	var key := Vector2i(Skins.version, int(titled))
	if _dressed.get(b) == key:
		return
	_dressed[b] = key
	if titled:
		Skins.redress_button(b)
	else:
		for state: StringName in [&"normal", &"disabled", &"hover", &"pressed", &"focus", &"hover_pressed"]:
			b.remove_theme_stylebox_override(state)


## The backdrop's scroll at this pose (the title carries on from it).
func backdrop_scroll() -> Vector2:
	return TitleBackdrop.SPEED * elapsed
