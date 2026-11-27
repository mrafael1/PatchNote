class_name ShieldArc
extends Node2D
## The shielder's shield (M50.3c, PLAN v9 1.9): an arc in front of the body, drawn in the
## `accent` role; a blocked shot lights it for a moment (not under reduce flashing).
## Presentation only: the walker owns the facing and decides what is blocked.

const WIDTH := 5.0
const FLASH := 0.18   ## seconds a blocked shot lights the arc

var arc_deg := 100.0
var radius := 30.0
var facing := Vector2.RIGHT:
	set(v):
		if not v.is_equal_approx(facing):
			facing = v
			queue_redraw()
var _lit_until := -1.0


func _ready() -> void:
	z_index = 2


func blocked() -> void:
	if SaveGame.reduce_flashing():
		return
	_lit_until = RunState.real_time() + FLASH
	queue_redraw()


func _process(_delta: float) -> void:
	if _lit_until >= 0.0 and RunState.real_time() >= _lit_until:
		_lit_until = -1.0
		queue_redraw()


func _draw() -> void:
	var half := deg_to_rad(arc_deg) * 0.5
	var a := facing.angle()
	var lit := _lit_until >= 0.0
	var c := Color.WHITE if lit else Color(Palette.color(&"accent"), 0.9)
	draw_arc(Vector2.ZERO, radius, a - half, a + half, 14, Color(Palette.color(&"outline"), 0.9), WIDTH + 3.0)
	draw_arc(Vector2.ZERO, radius, a - half, a + half, 14, c, WIDTH)
