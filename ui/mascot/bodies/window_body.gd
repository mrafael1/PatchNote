extends CreatureBody
## The window (PLAN v8 1.3), M51a: the little window with two blue ears, stub arms and
## feet; the title bar became its cap, the three buttons still on it. Panic turns the cap
## red (not responding), guilt greys it.

const CAP := Palette.WINDOW_CAP
const CAP_PANIC := Palette.WINDOW_PANIC
const CAP_GUILTY := Palette.WINDOW_GUILTY
const CAP_LIGHT := Palette.WINDOW_CAP_LIGHT
const BUTTON := Palette.WINDOW_BUTTON
const FACE := Palette.WINDOW_FACE
const SHADE := Palette.WINDOW_FACE_SHADE
const FEET := Palette.WINDOW_FEET
const GRID := [
	"..KK..............KK..",
	".KBBK............KBBK.",
	".KBBKKKKKKKKKKKKKKBBK.",
	".KBBBBBBBBBBBBBBBBBBK.",
	".KBLLLLBBBBBBWBWBWBBK.",
	".KKKKKKKKKKKKKKKKKKKK.",
	".KPPPPPPPPPPPPPPPPPSK.",
	".KPPPPPPPPPPPPPPPPPSK.",
	".KPPPPPPPPPPPPPPPPPSK.",
	"KKPPPPPPPPPPPPPPPPPSKK",
	"AKPPPPPPPPPPPPPPPPPSKA",
	"KKPPPPPPPPPPPPPPPPPSKK",
	".KPPPPPPPPPPPPPPPPPSK.",
	".KPPPPPPPPPPPPPPPPPSK.",
	".KPPPPPPPPPPPPPPPPSSK.",
	".KSSSSSSSSSSSSSSSSSSK.",
	"..KKKKKKKKKKKKKKKKKK..",
]
const FEET_ROWS := ["....KAAK......KAAK....", "...KAAAK......KAAAK...", "...KKKKK......KKKKK..."]


func grid() -> Array:
	return GRID


func feet() -> Array:
	return FEET_ROWS


func cap() -> Color:
	match expression:
		&"panic":
			return CAP_PANIC
		&"guilty":
			return CAP_GUILTY
	return CAP


func ramp() -> Dictionary:
	return {"K": DARK, "B": cap(), "L": CAP_LIGHT, "W": BUTTON, "P": FACE, "S": SHADE, "A": FEET}


func face_at() -> Vector2:
	return Vector2(6, 7)


func core() -> Rect2:
	return Rect2(Vector2(11, 10), Vector2(10, 7))


func arm_color() -> Color:
	return FEET


func _build_shapes() -> Dictionary:
	var ear := PackedVector2Array([Vector2(2, 0.15), Vector2(4, 0.15), Vector2(5, 1.2), Vector2(5, 4.5),
			Vector2(1, 4.5), Vector2(1, 1.2)])
	var ear_r := PackedVector2Array()
	for v in ear:
		ear_r.append(Vector2(22.0 - v.x, v.y))
	var win := soften(PackedVector2Array([Vector2(2.2, 2), Vector2(19.8, 2), Vector2(21, 3.2),
			Vector2(21, 15.8), Vector2(19.8, 17), Vector2(2.2, 17), Vector2(1, 15.8), Vector2(1, 3.2)]))
	var top := PackedVector2Array([Vector2(0, 0), Vector2(22, 0), Vector2(22, 5.5), Vector2(0, 5.5)])
	return {"ears": [soften(ear), soften(ear_r)], "win": win, "lit": lit(win, Vector2(-1, -1)),
			"cap": Geometry2D.intersect_polygons(win, top),
			"strip": soften(PackedVector2Array([Vector2(2.3, 3.9), Vector2(6, 3.9), Vector2(6, 4.9),
					Vector2(2.3, 4.9)]), 1)}


func _paint_flat_feet(o: Vector2, cu: float, _sh: Dictionary) -> void:
	for x: float in [5.5, 16.5]:
		_bean(o + Vector2(x, 18.6) * cu, Vector2(2.2, 1.35) * cu, FEET, cu)


func _paint_flat_body(o: Vector2, cu: float, sh: Dictionary) -> void:
	for x: float in [0.7, 21.3]:
		_bean(o + Vector2(x, 10.5) * cu, Vector2(0.95, 0.8) * cu, FEET, cu)
	for ear: PackedVector2Array in place(sh["ears"], o, cu):
		fill([ear], cap())
		ink(ear, cu)
	var win: PackedVector2Array = place([sh["win"]], o, cu)[0]
	fill([win], SHADE)
	fill(place(sh["lit"], o, cu), FACE)
	fill(place(sh["cap"], o, cu), cap())
	fill(place([sh["strip"]], o, cu), CAP_LIGHT)
	for x: float in [13.5, 15.5, 17.5]:
		draw_rect(Rect2(o + Vector2(x - 0.45, 3.95) * cu, Vector2(0.9, 0.9) * cu), col(BUTTON))
	draw_line(o + Vector2(1.2, 5.5) * cu, o + Vector2(20.8, 5.5) * cu, col(DARK), LINE_W * cu, true)
	ink(win, cu)
