class_name RectVisual
extends Node2D
## Placeholder visual: a colored rectangle. Visuals are replaceable children and
## carry no gameplay.

@export var size := Vector2(34, 34):
	set(value):
		size = value
		queue_redraw()
@export var color := Color.WHITE:
	set(value):
		color = value
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-size / 2.0, size), color)
