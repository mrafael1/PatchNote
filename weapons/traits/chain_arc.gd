extends Node2D
## Chain's hop (M50.1a): a line flash from the kill to the next target for FRAMES physics
## frames. Visual only: not an entity, nothing hits it. Colour: the player_shot role (the look's).

const FRAMES := 2

var from := Vector2.ZERO
var to := Vector2.ZERO
var _left := FRAMES


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	queue_redraw()


func _physics_process(_delta: float) -> void:
	_left -= 1
	if _left <= 0:
		queue_free()


func _draw() -> void:
	var c := Palette.color(&"player_shot")
	draw_line(from, to, Color(c, 0.9), 3.0)
	draw_line(from, to, Color(1, 1, 1, 0.7), 1.0)
