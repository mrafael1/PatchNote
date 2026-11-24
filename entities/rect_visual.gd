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


func _draw() -> void:
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
