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


const FLASH_TIME := 0.09

var _flash_left := 0.0


## Brief white flash, used as hit feedback.
func flash() -> void:
	_flash_left = FLASH_TIME
	queue_redraw()


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-size / 2.0, size), Color.WHITE if _flash_left > 0.0 else color)
