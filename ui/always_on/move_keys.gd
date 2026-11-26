class_name MoveKeys
extends Control
## M47.6a (PLAN v9.4 2.2): the movement keys drawn bottom-left of the game view while the
## build cannot move yet (S0), and for the first SHOW_S seconds of the session that first
## has `movement` (S1: the same keys now work), then they fade (reduce flashing: a plain hide).
##
## Four keycaps in an inverted T, labelled by layout (InputSetup.key_label: Z Q S D on AZERTY,
## W A S D on QWERTY). A cap lights while its direction is held: the Input singleton while
## the tree is paused (the play gate), the player's input while the sim runs (bots light them
## too; arrows and the stick light the same caps). Presentation only, PROCESS_MODE_ALWAYS.

const CAP := 40.0
const GAP := 6.0
const MARGIN := 24.0
const SHOW_S := 6.0
const FADE_S := 0.6
const FONT_SIZE := 18
const ACTIONS: Array[StringName] = [&"move_up", &"move_left", &"move_down", &"move_right"]

var player: Node
## Seconds of game time the keys stay once the build can move (-1: only while it cannot;
## 0: never shown).
var show_for := -1.0
var gentle := false
var to_label := Callable()   ## tests: a keyboard layout of their own
var lit: Array[bool] = [false, false, false, false]   ## up, left, down, right
var _fade := 1.0


## How long the keys show in session `s`: -1 while it has no movement, SHOW_S in the first
## session that has it (the one before it had none), else 0 (never).
static func show_seconds(s: SessionDef) -> float:
	if s == null:
		return 0.0
	if not &"movement" in s.basics:
		return -1.0
	var i := CampaignDB.index_of(s.id)
	if i <= 0 or CampaignDB.campaign == null or i > CampaignDB.campaign.sessions.size():
		return 0.0
	var before := CampaignDB.campaign.sessions[i - 1]
	return SHOW_S if before != null and not &"movement" in before.basics else 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := CAP * 3.0 + GAP * 2.0
	var h := CAP * 2.0 + GAP
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = MARGIN
	offset_right = MARGIN + w
	offset_top = -MARGIN - h
	offset_bottom = -MARGIN
	visible = show_for != 0.0


func labels() -> Array[String]:
	var out: Array[String] = []
	for a in ACTIONS:
		out.append(InputSetup.key_label(a, to_label))
	return out


## The cap rects, in this control's space: up on top in the middle, then left, down, right.
static func cap_rects() -> Array[Rect2]:
	var s := Vector2(CAP, CAP)
	return [Rect2(Vector2(CAP + GAP, 0), s), Rect2(Vector2(0, CAP + GAP), s),
			Rect2(Vector2(CAP + GAP, CAP + GAP), s), Rect2(Vector2((CAP + GAP) * 2.0, CAP + GAP), s)]


func _move() -> Vector2:
	if get_tree().paused or player == null or not is_instance_valid(player):
		return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var input: Variant = player.get(&"input")
	return input.get(&"move") if input is Object and input != null else Vector2.ZERO


func _process(delta: float) -> void:
	if show_for == 0.0:
		visible = false
		return
	var m := _move()
	var now: Array[bool] = [m.y < -0.3, m.x < -0.3, m.y > 0.3, m.x > 0.3]
	if now != lit:
		lit = now
		queue_redraw()
	if show_for > 0.0 and RunState.game_time >= show_for:
		if gentle or SaveGame.reduce_flashing():
			_fade = 0.0
		else:
			_fade = maxf(0.0, _fade - delta / FADE_S)
		modulate.a = _fade
		if _fade <= 0.0:
			visible = false
			show_for = 0.0


func _draw() -> void:
	var font := UiTheme.mono_font()
	if font == null:
		font = ThemeDB.fallback_font
	var names := labels()
	var rects := cap_rects()
	for i in rects.size():
		var r := rects[i]
		draw_rect(r, Palette.KEYCAP_LIT if lit[i] else Palette.KEYCAP_FACE)
		draw_rect(r, Palette.KEYCAP_LIT if lit[i] else Palette.KEYCAP_EDGE, false, 2.0)
		var t := names[i]
		var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var at := r.position + Vector2((r.size.x - ts.x) * 0.5, (r.size.y + font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) * 0.5)
		draw_string(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
				Palette.KEYCAP_FACE if lit[i] else Palette.KEYCAP_TEXT)
