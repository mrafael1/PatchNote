extends MascotBody
## The cursor (PLAN v8 1.3): a mouse pointer with two dot eyes and a blinking caret for a
## mouth. Tilt and bounce carry the expressions; point_at flies it toward the target.

const FILL := Palette.CURSOR_FILL
const CARET_COLOR := Palette.CURSOR_CARET
## The classic pointer, tip at (0, 0), in a 50 x 80 box.
const ARROW := [Vector2(0, 0), Vector2(0, 76), Vector2(19, 60), Vector2(31, 86),
		Vector2(44, 80), Vector2(32, 55), Vector2(60, 55)]
const CENTRE := Vector2(27, 43)
const SCALE := 1.1


static func p(v: Vector2) -> Vector2:
	return (v - CENTRE) * SCALE


func pose() -> Dictionary:
	var out := super.pose()
	out["angle"] = float(out["angle"]) + 0.06 * sin(t * 1.3)
	if pointing():
		var tip := (Vector2.ZERO - CENTRE).angle()
		out["angle"] = _point_dir.angle() - tip
		out["offset"] = Vector2(out["offset"]) + _point_dir * 14.0
	return out


## M47.2: the arrow and its shadow (the eyes and mouth sit inside it).
func outline() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for v in ARROW:
		pts.append(p(v))
		pts.append(p(v) + Vector2(4, 5))
	return pts


func _paint() -> void:
	var pts := PackedVector2Array()
	for v in ARROW:
		pts.append(p(v))
	var shadow := PackedVector2Array()
	for v in pts:
		shadow.append(v + Vector2(4, 5))
	draw_colored_polygon(shadow, col(Color(Palette.SHADOW, 0.3)))
	draw_colored_polygon(pts, col(FILL))
	pts.append(pts[0])
	draw_polyline(pts, col(INK), 3.5, true)
	draw_eye(p(Vector2(10, 35)), 6.6, -1.0, FILL)
	draw_eye(p(Vector2(27, 39)), 6.6, 1.0, FILL)
	var m := p(Vector2(17, 50))
	if talking:
		var h := 4.0 + 6.0 * absf(sin(t * 13.0))
		draw_rect(Rect2(m + Vector2(-1.5, -h * 0.5), Vector2(3.0, h)), col(CARET_COLOR))
	elif expression in [&"idle", &"thinking", &"proud"]:
		if fmod(t, 1.0) < 0.6:
			draw_rect(Rect2(m + Vector2(-1.5, -5.0), Vector2(3.0, 10.0)), col(CARET_COLOR))
	else:
		draw_mouth(m, 15.0)
