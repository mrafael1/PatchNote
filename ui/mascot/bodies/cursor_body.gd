extends CreatureBody
## The cursor (PLAN v8 1.3), M51a: a pointed white hood on two orange feet, the arrow
## standing upright, its shade down the right side. It hops when it is happy and shivers
## when it is worried (CreatureBody.motion()).

const HOOD := Palette.CURSOR_HOOD
const SHADE := Palette.CURSOR_HOOD_SHADE
const FEET := Palette.CURSOR_FEET
const GRID := [
	".........KK.........",
	"........KWWK........",
	"........KWWK........",
	".......KWWWWK.......",
	".......KWWWWK.......",
	"......KWWWWWWK......",
	"......KWWWWWWK......",
	".....KWWWWWWWWK.....",
	".....KWWWWWWWWK.....",
	"....KWWWWWWWWWWK....",
	"....KWWWWWWWWWWK....",
	"...KWWWWWWWWWWWSK...",
	"...KWWWWWWWWWWWSK...",
	"..KWWWWWWWWWWWWSSK..",
	"..KWWWWWWWWWWWSSSK..",
	".KWWWWWWWWWWWWSSSSK.",
	".KKKKKWWWWWWSKKKKKK.",
	".....KWWWWWWSK......",
	".....KSWWWWSSK......",
	"......KKKKKKK.......",
]
const FEET_ROWS := ["......KAK.KAK.......", "......KKK.KKK......."]


func grid() -> Array:
	return GRID


func feet() -> Array:
	return FEET_ROWS


func ramp() -> Dictionary:
	return {"K": DARK, "W": HOOD, "S": SHADE, "A": FEET}


func face_at() -> Vector2:
	return Vector2(5, 9)


func core() -> Rect2:
	return Rect2(Vector2(10, 11.5), Vector2(6.5, 7.5))


func arm_color() -> Color:
	return FEET


func _build_shapes() -> Dictionary:
	var hood := soften(PackedVector2Array([Vector2(9.3, 0.15), Vector2(10.7, 0.15), Vector2(19, 15.4),
			Vector2(19, 17), Vector2(14, 17), Vector2(14, 19.2), Vector2(13.2, 20), Vector2(5.8, 20),
			Vector2(5, 19.2), Vector2(5, 17), Vector2(1, 17), Vector2(1, 15.4)]))
	return {"hood": hood, "lit": lit(hood, Vector2(-1.3, -0.9))}


func _paint_flat_feet(o: Vector2, cu: float, _sh: Dictionary) -> void:
	for x: float in [7.5, 11.5]:
		_bean(o + Vector2(x, 20.8) * cu, Vector2(1.5, 1.05) * cu, FEET, cu)


func _paint_flat_body(o: Vector2, cu: float, sh: Dictionary) -> void:
	var hood: PackedVector2Array = place([sh["hood"]], o, cu)[0]
	fill([hood], SHADE)
	fill(place(sh["lit"], o, cu), HOOD)
	ink(hood, cu)
