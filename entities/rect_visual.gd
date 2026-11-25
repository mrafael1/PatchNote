class_name RectVisual
extends Node2D
## Placeholder visual: a colored rectangle. Visuals are replaceable children and
## carry no gameplay. The readability layer (PLAN v5 2.2) draws here, in every look:
## the hit flash, a shooter's telegraph, a walker's contact rim and the HP bar.

@export var size := Vector2(34, 34):
	set(value):
		size = value
		queue_redraw()
@export var color := Color.WHITE:
	set(value):
		color = value
		queue_redraw()

const FLASH_TIME := 0.09
const TELEGRAPH_GROW := 0.35     ## a full telegraph draws the body this much bigger
const RIM := Color(1.0, 0.15, 0.1)
const RIM_WIDTH := 3.0
const BAR_HEIGHT := 4.0
const BAR_GAP := 5.0

## 0..1: how far into its windup the owner is (a shooter about to fire).
var telegraph := 0.0:
	set(value):
		if not is_equal_approx(value, telegraph):
			telegraph = value
			queue_redraw()
## 0..1: how close a walker is to contact range; 0 draws no rim.
var rim := 0.0:
	set(value):
		if not is_equal_approx(value, rim):
			rim = value
			queue_redraw()
## The owner's HP share; the bar shows only below 1 (set by Feedback on a hit).
var hp_shown := 1.0:
	set(value):
		if not is_equal_approx(value, hp_shown):
			hp_shown = value
			queue_redraw()

var _flash_left := 0.0
## Pixel look preview (PLAN 1.7): the sprite drawn instead of the rect while Skins.current
## is set. &"" = read from the owner (Skins.id_for); a creator may name one.
var skin_id: StringName = &""
var _skin_id: StringName = &""
var _skin_version := -1
var _skin_frame := -1


## Brief white flash, used as hit feedback.
func flash() -> void:
	_flash_left = FLASH_TIME
	queue_redraw()


func is_flashing() -> bool:
	return _flash_left > 0.0


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			queue_redraw()
	if telegraph > 0.0:
		queue_redraw()   # the telegraph flickers
	if Skins.current != null:
		if _resolved_skin_id() == &"aim_arrow":
			queue_redraw()   # the arrow cancels its parent's turn and snaps to whole pixels
			return
		var f := Skins.current.idle_frame(_resolved_skin_id(), RunState.real_time())
		if f != _skin_frame:
			_skin_frame = f
			queue_redraw()   # the idle's next frame


func _draw() -> void:
	if Skins.current != null and _draw_skin():
		return
	var body := size * (1.0 + TELEGRAPH_GROW * telegraph)
	var fill := color
	if _flash_left > 0.0:
		fill = Color.WHITE
	elif telegraph > 0.0:
		# Flicker toward white, faster and brighter as the shot nears.
		# M44: on the unscaled physics clock (not the wall clock), so a same-seed frame is
		# the same picture (the tier-0 screenshot baseline); not game_time, which slow-mo
		# would slow and B1 would freeze.
		var blink := 0.5 + 0.5 * sin(RunState.real_time() * 1000.0 * 0.04 * (1.0 + telegraph))
		fill = color.lerp(Color.WHITE, telegraph * (0.45 + 0.55 * blink))
	var rect := Rect2(-body / 2.0, body)
	draw_rect(rect, fill)
	if rim > 0.0:
		var edge := RIM
		edge.a = 0.35 + 0.65 * rim
		draw_rect(rect.grow(RIM_WIDTH * 0.5 + 1.0), edge, false, RIM_WIDTH * (0.6 + 0.4 * rim))
	if hp_shown < 1.0 and hp_shown > 0.0:
		_draw_hp_bar()


## The Pixel preview: the sprite (centred on the rect, upright for a body), a white
## silhouette over it for the hit flash and the telegraph's glow, then today's rim and HP
## bar. False when this rect has no sprite (it draws the rect).
func _draw_skin() -> bool:
	var skin := Skins.current
	var id := _resolved_skin_id()
	if id == &"" or not skin.has(id):
		return false
	if id == &"aim_arrow":
		return _draw_aim_arrow(skin)
	var grow := 1.0 + TELEGRAPH_GROW * telegraph
	var s := skin.scale_for(id, size.x) * grow
	var frame := skin.idle_frame(id, RunState.real_time())
	var upright := Skins.upright(id)
	if upright:
		draw_set_transform(Vector2.ZERO, -rotation)
	skin.draw(self, id, Vector2.ZERO, s, frame, Color(1, 1, 1, color.a))
	var white := 0.0
	if _flash_left > 0.0:
		white = 0.9
	elif telegraph > 0.0:
		var blink := 0.5 + 0.5 * sin(RunState.real_time() * 1000.0 * 0.04 * (1.0 + telegraph))
		white = telegraph * (0.45 + 0.55 * blink)
	if white > 0.0:
		skin.draw_silhouette(self, id, Vector2.ZERO, s, frame, Color(1, 1, 1, white * color.a))
	if upright:
		draw_set_transform(Vector2.ZERO)
	if rim > 0.0:
		var body := size * grow
		var edge := RIM
		edge.a = 0.35 + 0.65 * rim
		draw_rect(Rect2(-body / 2.0, body).grow(RIM_WIDTH * 0.5 + 1.0), edge, false, RIM_WIDTH * (0.6 + 0.4 * rim))
	if hp_shown < 1.0 and hp_shown > 0.0:
		_draw_hp_bar()
	return true


## The player's aim tip as a pixel arrow: the glyph snaps to 8 directions (aim_arrow by
## exact quarter turns, aim_arrow_diag for the diagonals) while this node keeps circling
## the player on the true aim angle; the glyph's centre lands on a whole screen pixel.
func _draw_aim_arrow(skin: ArtSkin) -> bool:
	var xf := get_global_transform_with_canvas()
	var aim := xf.get_rotation()
	var k := posmod(roundi(aim / (PI / 4.0)), 8)
	var id := &"aim_arrow_diag" if k % 2 == 1 else &"aim_arrow"
	if not skin.has(id):
		return false
	var turn := float(k >> 1) * PI / 2.0  # exact quarter turns only: the pixels stay square
	var snapped := xf.origin.round()      # every glyph is even-sized at 2x: centre on a pixel
	if is_physics_interpolated_and_enabled():
		# Drawn between ticks (Skins.apply_motion): xf is the last tick's place, not the
		# drawn one, so a snap to it would wobble the glyph a pixel within every tick.
		snapped = xf.origin
	var local := xf.affine_inverse() * snapped
	draw_set_transform(local, -aim + turn)
	skin.draw(self, id, Vector2.ZERO, float(ArtSkin.BODY_SCALE), 0, Color(1, 1, 1, color.a))
	draw_set_transform(Vector2.ZERO)
	return true


func _resolved_skin_id() -> StringName:
	if _skin_version != Skins.version:
		_skin_version = Skins.version
		_skin_id = Skins.id_for(self)
	return _skin_id


## A short white bar under the body, drawn upright whatever the body's rotation.
func _draw_hp_bar() -> void:
	var r := rotation
	var half_h := (absf(cos(r)) * size.y + absf(sin(r)) * size.x) * 0.5
	var width := maxf(size.x, 20.0)
	draw_set_transform(Vector2.ZERO, -r)
	var back := Rect2(Vector2(-width / 2.0, half_h + BAR_GAP), Vector2(width, BAR_HEIGHT))
	draw_rect(back, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(back.position, Vector2(width * hp_shown, BAR_HEIGHT)), Color.WHITE)
	draw_set_transform(Vector2.ZERO)
