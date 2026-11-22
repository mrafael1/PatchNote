class_name KillPop
extends Node2D
## The kill confirmation (PLAN v5 2.2): a ring that pops out and fades at the kill
## position, in every look. Presentation only.

const LIFETIME := 0.22
const RADIUS_FROM := 8.0
const RADIUS_TO := 30.0
const WIDTH := 4.0

var color := Color.WHITE
var scale_mult := 1.0

var _age := 0.0


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_age / LIFETIME, 0.0, 1.0)
	var eased := 1.0 - (1.0 - t) * (1.0 - t)
	var radius := lerpf(RADIUS_FROM, RADIUS_TO, eased) * scale_mult
	var c := color.lerp(Color.WHITE, 0.5)
	c.a = 1.0 - t
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, c, WIDTH * (1.0 - 0.6 * t) * maxf(scale_mult, 0.5), true)
