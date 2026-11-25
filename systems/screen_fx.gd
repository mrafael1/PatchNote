class_name ScreenFx
extends Control
## Screen-space feedback over the game (PLAN v5 2.2): the red edge vignette when the
## player is hit, in every look, and the white flash of looks with `screen_flash`.
## Timed in unscaled seconds, so hit stop and slow motion do not stretch it.
## Presentation only.

const VIGNETTE_TIME := 0.3
const VIGNETTE := Palette.VIGNETTE
const VIGNETTE_ALPHA := 0.55
const VIGNETTE_DEPTH := 0.14   ## share of the shorter screen side
const FLASH_TIME := 0.08
## One flash per this many real seconds: exploding shots go off several times a second
## and the flashes strobed (owner feedback after M34, 2026-11-22).
const FLASH_COOLDOWN := 0.5

var _vignette_left := 0.0
var _flash_left := 0.0
var _flash_alpha := 0.0
var _flash_ready_in := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func vignette() -> void:
	_vignette_left = VIGNETTE_TIME
	queue_redraw()


## Returns false when a flash went off too recently (it is skipped).
func flash(alpha := 0.35) -> bool:
	if _flash_ready_in > 0.0 or SaveGame.reduce_flashing():   # PLAN v8 1.9: no white flash
		return false
	_flash_ready_in = FLASH_COOLDOWN
	_flash_left = FLASH_TIME
	_flash_alpha = alpha
	queue_redraw()
	return true


func vignette_left() -> float:
	return _vignette_left


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.0001)
	_flash_ready_in = maxf(0.0, _flash_ready_in - real)
	if _vignette_left <= 0.0 and _flash_left <= 0.0:
		return
	_vignette_left = maxf(0.0, _vignette_left - real)
	_flash_left = maxf(0.0, _flash_left - real)
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	if _flash_left > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, _flash_alpha * _flash_left / FLASH_TIME))
	if _vignette_left <= 0.0:
		return
	var a := VIGNETTE_ALPHA * _vignette_left / VIGNETTE_TIME
	var d := minf(s.x, s.y) * VIGNETTE_DEPTH
	var outer := Color(Palette.color(&"vignette"), a)
	var inner := Color(Palette.color(&"vignette"), 0.0)
	# Four bands, opaque at the screen edge and clear inside.
	_band([Vector2.ZERO, Vector2(s.x, 0), Vector2(s.x - d, d), Vector2(d, d)], outer, inner)
	_band([Vector2(0, s.y), Vector2(s.x, s.y), Vector2(s.x - d, s.y - d), Vector2(d, s.y - d)], outer, inner)
	_band([Vector2.ZERO, Vector2(0, s.y), Vector2(d, s.y - d), Vector2(d, d)], outer, inner)
	_band([Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x - d, s.y - d), Vector2(s.x - d, d)], outer, inner)


## Points 0 and 1 are on the screen edge, 2 and 3 inside.
func _band(points: Array[Vector2], outer: Color, inner: Color) -> void:
	draw_polygon(PackedVector2Array(points), PackedColorArray([outer, outer, inner, inner]))
