class_name LockIcon
extends Control
## A small padlock drawn with shapes (no font glyph needed): marks permanent big patches.

var color := Color(1.0, 0.8, 0.45)


func _init(size_px := 22.0, tint := Color(1.0, 0.8, 0.45)) -> void:
	custom_minimum_size = Vector2(size_px, size_px)
	color = tint
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var body := Rect2(o + Vector2(s * 0.12, s * 0.45), Vector2(s * 0.76, s * 0.52))
	draw_arc(o + Vector2(s * 0.5, s * 0.45), s * 0.24, PI, TAU, 12, color, maxf(2.0, s * 0.11))
	draw_rect(body, color)
	draw_circle(body.get_center(), s * 0.07, Color(0, 0, 0, 0.7))
