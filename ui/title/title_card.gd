class_name TitleCard
extends Control
## M51b (title mockup v2, concept B): one card of the title's menu row, drawn in code behind its
## Button (show_behind_parent). The Button keeps the focus, the mouse, the pad and its text (its
## own drawing is transparent); this draws the card: a paper face at rest, lifted and lit in the
## card's accent when focused, its name, an ink slot with where it leads ("> v0.8.?"), and an up
## arrow toward the odometer.

const NAME_SIZE := 28
const SUB_SIZE := 14
const LIFT := 8.0
const ARROW := ["....KK....", "...KGGK...", "..KGGGGK..", ".KGGGGGGK.", "KKKKGGKKKK", "...KGGK...", "...KKKK..."]

var kind: StringName = &""
var title := ""
var sub := ""
var odometer: TitleOdometer   ## not lit while its boot rolls

var _button: Button


static func make(button: Button, p_kind: StringName) -> TitleCard:
	var c := TitleCard.new()
	c.kind = p_kind
	c.title = button.text
	c._button = button
	c.show_behind_parent = true
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(c)
	for s: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		button.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	for s: StringName in [&"font_color", &"font_hover_color", &"font_focus_color", &"font_pressed_color",
			&"font_hover_pressed_color", &"font_disabled_color"]:
		button.add_theme_color_override(s, Color(1, 1, 1, 0))
	button.focus_entered.connect(c.queue_redraw)
	button.focus_exited.connect(c.queue_redraw)
	button.mouse_entered.connect(func() -> void:
		if button.is_visible_in_tree() and not button.disabled:
			button.grab_focus())
	return c


func lit() -> bool:
	return _button != null and _button.has_focus() and not (odometer != null and odometer.booting())


func _draw() -> void:
	var on := lit()
	var off := _button != null and _button.disabled
	var lift := -LIFT if on else 0.0
	var fill := TitleOdometer.accent(kind) if on else Palette.ODO_PAPER_SHADE
	if kind == TitleOdometer.OPTIONS or kind == TitleOdometer.QUIT:
		fill = Palette.ODO_GOLD if on else fill
	var r := Rect2(Vector2(0, lift), size)
	draw_rect(Rect2(r.position + Vector2(0, 11.0 if on else 5.0), r.size), Palette.ODO_INK)
	draw_rect(r, Palette.ODO_INK)
	draw_rect(r.grow(-4.0), Color(fill, 0.55) if off else fill)
	var bold := UiTheme.pixel_font(true)
	var shown := _button.text if _button != null else title
	draw_string(bold, Vector2(0, lift + 16.0 + bold.get_ascent(NAME_SIZE)), shown, HORIZONTAL_ALIGNMENT_CENTER,
			size.x, NAME_SIZE, Palette.ODO_INK)
	var slot := Rect2(Vector2(21, lift + size.y - 47.0), Vector2(size.x - 42.0, 30))
	draw_rect(slot, Palette.ODO_INK)
	var f := UiTheme.pixel_font()
	draw_string(f, Vector2(slot.position.x, slot.position.y + 7.0 + f.get_ascent(SUB_SIZE)), sub,
			HORIZONTAL_ALIGNMENT_CENTER, slot.size.x, SUB_SIZE, Palette.ODO_GOLD if on else Palette.ODO_LAV_DIM)
	if on:
		var s := 4.0
		var at := Vector2(size.x * 0.5 - 5.0 * s, -LIFT - 7.0 * s - 6.0)
		for y in ARROW.size():
			var row := String(ARROW[y])
			for x in row.length():
				if row[x] != ".":
					draw_rect(Rect2(at + Vector2(x, y) * s, Vector2(s, s)), Palette.ODO_INK if row[x] == "K" else fill)
