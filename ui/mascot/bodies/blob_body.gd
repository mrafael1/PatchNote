extends CreatureBody
## The blob (PLAN v8 1.3), M51a: the round green one with a leaf sprout and feet, lit from
## the top left like the enemies (a light rim, a shine, a shade along the bottom right).

const BODY := Palette.BLOB_BODY
const SHADE := Palette.BLOB_SHADE
const LIGHT := Palette.BLOB_LIGHT
const SHINE := Palette.BLOB_SHINE
const LEAF := Palette.BLOB_LEAF
const FEET := Palette.BLOB_FEET
const GRID := [
	"..........KKK.......",
	".........KLLLK......",
	".........KLLK.......",
	"......KKKKKKKK......",
	"....KKHHHHPPPPKK....",
	"...KHHHHPPPPPPPPK...",
	"..KHHWWPPPPPPPPPPK..",
	".KHHWPPPPPPPPPPPPSK.",
	".KHPPPPPPPPPPPPPPSK.",
	"KHPPPPPPPPPPPPPPPPSK",
	"KHPPPPPPPPPPPPPPPPSK",
	"KPPPPPPPPPPPPPPPPPSK",
	"KPPPPPPPPPPPPPPPPPSK",
	"KPPPPPPPPPPPPPPPPPSK",
	"KPPPPPPPPPPPPPPPPSSK",
	"KSPPPPPPPPPPPPPPPSSK",
	".KSPPPPPPPPPPPPPSSK.",
	".KSSPPPPPPPPPPPSSSK.",
	"..KSSSSSSSSSSSSSSK..",
	"...KKSSSSSSSSSSKK...",
	".....KKKKKKKKKK.....",
]
const FEET_ROWS := ["....KAAK....KAAK....", "....KKKK....KKKK...."]


func grid() -> Array:
	return GRID


func feet() -> Array:
	return FEET_ROWS


func ramp() -> Dictionary:
	return {"K": DARK, "P": BODY, "S": SHADE, "H": LIGHT, "W": SHINE, "L": LEAF, "A": FEET}


func face_at() -> Vector2:
	return Vector2(5, 10)


func core() -> Rect2:
	return Rect2(Vector2(10, 12), Vector2(10, 9))


func arm_color() -> Color:
	return BODY


func _build_shapes() -> Dictionary:
	var body := PackedVector2Array()
	for i in 56:
		var a := TAU * float(i) / 56.0
		var c := cos(a)
		var s := sin(a)
		body.append(Vector2(10.0 + 10.0 * signf(c) * pow(absf(c), 2.0 / 2.4),
				12.05 + 9.05 * signf(s) * pow(absf(s), 2.0 / 2.4)))
	var leaf := soften(PackedVector2Array([Vector2(10.4, 3.4), Vector2(9.2, 1.7), Vector2(10.2, 0.3),
			Vector2(12.3, 0.1), Vector2(13.9, 0.7), Vector2(13.2, 2.1), Vector2(11.7, 3.1)]))
	var lit_part := lit(body, Vector2(-1.4, -1.3))
	return {"body": body, "leaf": leaf, "lit": lit_part, "rim": rim(lit_part, Vector2(1.1, 1.1))}


func _paint_flat_feet(o: Vector2, cu: float, _sh: Dictionary) -> void:
	for x: float in [6.0, 14.0]:
		_bean(o + Vector2(x, 21.9) * cu, Vector2(1.9, 1.1) * cu, FEET, cu)


func _paint_flat_body(o: Vector2, cu: float, sh: Dictionary) -> void:
	var leaf: PackedVector2Array = place([sh["leaf"]], o, cu)[0]
	fill([leaf], LEAF)
	ink(leaf, cu)
	draw_line(o + Vector2(10.9, 2.8) * cu, o + Vector2(13.1, 0.9) * cu, col(SHADE), 0.35 * cu, true)
	var body: PackedVector2Array = place([sh["body"]], o, cu)[0]
	fill([body], SHADE)
	fill(place(sh["lit"], o, cu), BODY)
	fill(place(sh["rim"], o, cu), LIGHT)
	_oval(o + Vector2(6.0, 6.9) * cu, Vector2(1.1, 0.7) * cu, col(SHINE))
	ink(body, cu)
