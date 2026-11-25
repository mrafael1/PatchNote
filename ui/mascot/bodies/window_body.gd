extends MascotBody
## The window (PLAN v8 1.3): a small OS-style window, title bar "ai.exe" and _ □ ×, with
## two eyes and a mouth in its body. Surprise maximises it for a moment (the pose's pop);
## panic turns the bar red and "Not Responding"; point_at grows an arrow from its side.

const BODY := Palette.WINDOW_BODY
const BAR := Palette.WINDOW_BAR
const BAR_PANIC := Palette.WINDOW_PANIC
const BAR_GUILTY := Palette.WINDOW_GUILTY
const HALF := Vector2(46, 38)
const BAR_H := 18.0


## M47.2: the window, its shadow and (pointing) the arrow's tip at its longest.
func outline() -> PackedVector2Array:
	var pts := PackedVector2Array([-HALF, Vector2(HALF.x, -HALF.y), HALF + Vector2(4, 5), Vector2(-HALF.x, HALF.y + 5)])
	if pointing():
		var edge := Vector2(signf(_point_dir.x) * HALF.x if absf(_point_dir.x) > absf(_point_dir.y) else 0.0,
				signf(_point_dir.y) * HALF.y if absf(_point_dir.y) >= absf(_point_dir.x) else 0.0)
		pts.append(edge + _point_dir * 28.0)
		pts.append(edge + _point_dir.orthogonal() * 7.0)
		pts.append(edge - _point_dir.orthogonal() * 7.0)
	return pts


func _paint() -> void:
	var box := Rect2(-HALF, HALF * 2.0)
	draw_rect(Rect2(box.position + Vector2(4, 5), box.size), col(Color(Palette.SHADOW, 0.3)))
	draw_rect(box, col(BODY))
	var bar_color := BAR
	if expression == &"panic":
		bar_color = BAR_PANIC
	elif expression == &"guilty":
		bar_color = BAR_GUILTY
	draw_rect(Rect2(box.position, Vector2(box.size.x, BAR_H)), col(bar_color))
	var font := ThemeDB.fallback_font
	var title := "(Not Responding)" if expression == &"panic" else "ai.exe"
	var size := 9 if expression == &"panic" else 11
	draw_string(font, box.position + Vector2(5, 13), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col(Color.WHITE))
	if expression != &"panic":
		# _ □ ×
		var x := HALF.x - 9.0
		var y := -HALF.y + BAR_H * 0.5
		var w := Color(1, 1, 1, 0.95)
		draw_line(Vector2(x - 3, y - 3), Vector2(x + 3, y + 3), col(w), 1.6, true)
		draw_line(Vector2(x - 3, y + 3), Vector2(x + 3, y - 3), col(w), 1.6, true)
		draw_rect(Rect2(Vector2(x - 15, y - 3), Vector2(6, 6)), col(w), false, 1.4)
		draw_line(Vector2(x - 27, y + 3), Vector2(x - 21, y + 3), col(w), 1.6, true)
	draw_rect(box, col(INK), false, 3.0)
	if pointing():
		var edge := Vector2(signf(_point_dir.x) * HALF.x if absf(_point_dir.x) > absf(_point_dir.y) else 0.0,
				signf(_point_dir.y) * HALF.y if absf(_point_dir.y) >= absf(_point_dir.x) else 0.0)
		var grow := 10.0 + 4.0 * sin(t * 10.0)
		var tip := edge + _point_dir * (14.0 + grow)
		var side := _point_dir.orthogonal() * 7.0
		draw_colored_polygon(PackedVector2Array([tip, edge + side, edge - side]), col(bar_color))
	var face_y := BAR_H * 0.5
	draw_eye(Vector2(-17, face_y - 4), 9.5, -1.0, BODY)
	draw_eye(Vector2(17, face_y - 4), 9.5, 1.0, BODY)
	draw_mouth(Vector2(0, face_y + 16), 22.0)
