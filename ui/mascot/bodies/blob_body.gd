extends MascotBody
## The blob (PLAN v8 1.3): a squishy round body with two eyes. Squash and stretch carry
## the expressions (its pose squashes harder than the others'); point_at stretches a
## pseudopod toward the target.

const FILL := Palette.BLOB_FILL
const EDGE := Palette.BLOB_EDGE
const R := 40.0
const CENTRE := Vector2(0, 6)
const POINTS := 48


func pose() -> Dictionary:
	var out := super.pose()
	var s: Vector2 = out["scale"]
	# Exaggerate the squash: a blob's whole body is its expression.
	s = Vector2(1.0 + (s.x - 1.0) * 2.2, 1.0 + (s.y - 1.0) * 2.2)
	out["scale"] = s * Vector2(1.0 + 0.025 * sin(t * 2.4), 1.0 - 0.025 * sin(t * 2.4))
	return out


func _outline() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var reach := _point_dir.angle()
	for i in POINTS:
		var a := TAU * float(i) / float(POINTS)
		var r := R * (1.0 + 0.035 * sin(3.0 * a + t * 2.2) + 0.02 * sin(5.0 * a - t * 3.1))
		if pointing():
			r += 26.0 * pow(maxf(0.0, cos(a - reach)), 8.0)
		var v := CENTRE + Vector2(cos(a), sin(a)) * r
		v.y = minf(v.y, CENTRE.y + R * 0.86)   # it sits on a flat bottom
		pts.append(v)
	return pts


## M47.2: the body, its shadow and the sweat drop by the right eye.
func outline() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for v in _outline():
		pts.append(v)
		pts.append(v + Vector2(4, 5))
	var sweat := CENTRE + Vector2(15, -6) + Vector2(16, -6)
	for c in [Vector2(-5, -9), Vector2(5, -9), Vector2(-5, 13), Vector2(5, 13)]:
		pts.append(sweat + c)
	return pts


func _paint() -> void:
	var pts := _outline()
	var shadow := PackedVector2Array()
	for v in pts:
		shadow.append(v + Vector2(4, 5))
	draw_colored_polygon(shadow, col(Color(Palette.SHADOW, 0.3)))
	draw_colored_polygon(pts, col(FILL))
	pts.append(pts[0])
	draw_polyline(pts, col(EDGE), 3.5, true)
	_ellipse(CENTRE + Vector2(-17, -20), Vector2(9, 5.5), col(Color(1, 1, 1, 0.55)))
	if expression in [&"happy", &"proud"] or (talking and expression == &"idle"):
		_ellipse(CENTRE + Vector2(-25, 10), Vector2(6, 3.5), col(Palette.BLOB_CHEEK))
		_ellipse(CENTRE + Vector2(25, 10), Vector2(6, 3.5), col(Palette.BLOB_CHEEK))
	draw_eye(CENTRE + Vector2(-15, -6), 10.0, -1.0, FILL)
	draw_eye(CENTRE + Vector2(15, -6), 10.0, 1.0, FILL)
	draw_mouth(CENTRE + Vector2(0, 14), 22.0)
