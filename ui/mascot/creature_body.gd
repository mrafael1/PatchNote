class_name CreatureBody
extends MascotBody
## M51a (the owner-approved "Mascot creatures" mockup): the three pickable bodies as small
## creatures, each grown from its old object (cursor: a pointed hood, window: ears and a
## cap, blob: a sprout) with feet, cheeks and one shared set of faces.
##
## Everything sits on the mockup's 26 x 26 cell canvas, centred on the origin. The flat
## look draws smooth shapes over that canvas (a cell is C body units); the pixel look
## (`pixel`, set by PixelBodyView) draws the mockup's own grids, a cell being whole
## viewport pixels. The feet stay planted: an expression moves the body and face over them
## (motion()), in whole cells and the mockup's 0.42 s frames in pixel, smoothly in flat.
##
## The mockup's five faces (happy, proud, thinking, worried, surprised) are used as drawn;
## idle, guilty and panic are this file's, in the same style. Every face is a 10 x 6 grid
## (FACES) and the flat look's primitives (flat_face()); a body only gives its shape.

const CANVAS := 26            ## the mockup's canvas, in cells
const C := 100.0 / CANVAS     ## a cell in the flat look, in body units
const FLOOR := 25             ## the canvas row under the feet (room for the flat shadow)
const TICK := 0.42            ## the mockup's frame (s)
const LINE_W := 0.9           ## the flat outline, in cells

## E ink, G glint, R cheek, C sweat. 10 x 6, at the body's face_at().
const FACES := {
	&"idle": [".GE....GE.", ".EE....EE.", ".EE....EE.", "R........R", "....EE....", ".........."],
	&"happy": [".GE....GE.", ".EE....EE.", ".EE....EE.", "R........R", "...E..E...", "....EE...."],
	&"proud": [".EE....EE.", "E..E..E..E", "..........", "R..EEEE..R", "...ERRE...", "....EE...."],
	&"thinking": ["EG....EG..", "EE....EE..", "..........", "..........", ".....EE...", ".........."],
	&"worried": [".E......E.", ".GE....GE.", ".EE....EE.", ".........C", "....EE...C", "...E..E..."],
	&"surprised": [".EE....EE.", "EGEE..EGEE", "EEEE..EEEE", ".EE....EE.", "....EE....", "....EE...."],
	&"guilty": [".........C", ".EEE..EEEC", ".EE...EE..", "R........R", "...EEEE...", ".........."],
	&"panic": [".EE....EE.", "EGGE..EGGE", "EGEE..EEGE", ".EE....EE.", "..EEEEEE.C", "..ERRRRE.C"],
}
## A blink's eye rows (0-2), per blinking face; the rest of the face stays.
const BLINK := {
	&"idle": ["..........", "..........", "EEE....EEE"],
	&"happy": ["..........", "..........", "EEE....EEE"],
	&"thinking": ["..........", "EEE...EEE.", ".........."],
}
## Talking: rows 3-5, columns 2-7 (the mouth; cheeks and sweat stay) on the open frames.
const TALK := ["......", "..EE..", "..EE.."]
const FACE_RAMP := {"E": Palette.CREATURE_INK, "G": Palette.CREATURE_GLINT,
		"R": Palette.CREATURE_CHEEK, "C": Palette.CREATURE_SWEAT}
const DARK := Palette.CREATURE_INK   ## outlines, eyes and mouths
const SHADOW_A := 0.25

## Flat shapes in cell space, built once per body id (the soft polygons and their clips).
static var _shapes := {}


# --- What a body gives ------------------------------------------------------------------

## The body's grid (top row first), every row the same width; K is the outline.
func grid() -> Array:
	return []


## The feet's rows, drawn under grid() and never moved by an expression.
func feet() -> Array:
	return []


## Each grid letter's colour (K: the ink) for the expression now.
func ramp() -> Dictionary:
	return {}


## The face's top-left cell in grid().
func face_at() -> Vector2:
	return Vector2.ZERO


## The body's middle and half-size in grid() cells: where a pointing arm leaves it.
func core() -> Rect2:
	return Rect2()


## The pointing arm's colour.
func arm_color() -> Color:
	return DARK


## The flat look's shapes in grid() cells, built once: {name: PackedVector2Array or Array}.
func _build_shapes() -> Dictionary:
	return {}


## The flat look's body over the feet, at grid-cell origin `o` (units), cell `cu`.
func _paint_flat_body(_o: Vector2, _cu: float, _sh: Dictionary) -> void:
	pass


## The flat look's feet.
func _paint_flat_feet(_o: Vector2, _cu: float, _sh: Dictionary) -> void:
	pass


# --- MascotBody -------------------------------------------------------------------------

func grid_unit() -> float:
	return C


## No tilt or squash: the feet stay on the floor. Only a lean toward a point and the
## glitch's jitter move the whole creature.
func pose() -> Dictionary:
	var off := Vector2.ZERO
	if pointing():
		off += Vector2(signf(_point_dir.x) if absf(_point_dir.x) > 0.3 else 0.0, 0.0) * C
	if glitching():
		off.x += 4.0 * sin(t * 61.0) if not gentle else 2.0 * sin(t * 9.0)
	return {"offset": off, "angle": 0.0, "scale": Vector2.ONE}


func _snap(v: Vector2) -> Vector2:
	if pixel and scale.x > 0.0:
		return (v * scale.x).round() / scale.x
	return v


## Everything the creature draws now: its grid moved by either look's motion(), the feet,
## a pointing arm and the flat shadow. Always in flat cells (C): the pixel look's cell is
## never larger, so a holder's keep-out is the same in both looks.
func outline() -> PackedVector2Array:
	var g := grid()
	var o := _origin(C)
	var size := Vector2(g[0].length(), g.size()) * C
	var m := _motion(false) * C
	var mp := _motion(true) * C
	var pts := PackedVector2Array()
	for r in [Rect2(o + m, size), Rect2(o + mp, size), Rect2(o, Vector2(size.x, (g.size() + feet().size()) * C)),
			Rect2(Vector2(-CANVAS * 0.5, FLOOR - 13.6) * C, Vector2(CANVAS, 1.4) * C)]:
		pts.append_array(PackedVector2Array([r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]))
	if pointing():
		for at in [o + m, o + mp]:
			var tip: Vector2 = at + _arm_end(C) * C
			pts.append_array(PackedVector2Array([tip - Vector2(1.5, 1.5) * C, tip + Vector2(1.5, 1.5) * C]))
	return pts


func _paint() -> void:
	var cu := _cu()
	var o := _origin(cu)
	var m := motion() * cu
	var g := grid()
	var feet_o := o + Vector2(0, g.size()) * cu
	var face_o := o + m + (face_at() + face_shift()) * cu
	if pixel:
		_grid(feet(), ramp(), feet_o, cu)
		_grid(g, ramp(), o + m, cu)
		_grid(face_grid(), FACE_RAMP, face_o, cu)
		if pointing():
			_pixel_arm(o + m, cu)
		return
	var sh := shapes()
	_oval(Vector2(0, (FLOOR - 13.4) * cu), Vector2(g[0].length() * 0.4, 0.7) * cu, col(Color(Palette.SHADOW, SHADOW_A)))
	_paint_flat_feet(o, cu, sh)
	_paint_flat_body(o + m, cu, sh)
	for p in flat_face():
		_prim(p, face_o, cu)
	if pointing():
		_flat_arm(o + m, cu)


# --- Motion and the face ------------------------------------------------------------------

## The cell, in body units, this body draws now: C in flat; in pixel the whole viewport
## pixels nearest under C (C itself when a cell would be under one pixel).
func _cu() -> float:
	if pixel and scale.x > 0.0:
		var n := floorf(C * scale.x + 0.0001)
		if n >= 1.0:
			return n / scale.x
	return C


## grid()'s top-left in body units: centred, the feet on FLOOR.
func _origin(cu: float) -> Vector2:
	var g := grid()
	var cell := Vector2(floori((CANVAS - g[0].length()) / 2.0), FLOOR - g.size() - feet().size())
	return (cell - Vector2(CANVAS, CANVAS) * 0.5) * cu


## The body and face's offset over the feet, in cells (the mockup's moves): happy hops,
## proud puffs, idle, thinking and guilty breathe (guilty sags a little lower in flat),
## worried shivers, surprised jumps, panic shakes and hops. reduce_flashing (gentle) drops the shakes.
func motion() -> Vector2:
	return _motion(pixel)


func _motion(px: bool) -> Vector2:
	var k := floori(t / TICK)
	if px:
		match expression:
			&"happy":
				return Vector2(0, -(k % 2))
			&"proud":
				return Vector2(0, k % 2)
			&"worried":
				return Vector2(0.0 if gentle else (1.0 if k % 2 == 1 else -1.0), 0)
			&"surprised":
				return Vector2(0, -2 * (k % 2))
			&"panic":
				var h := floori(t / (TICK * 0.5))
				return Vector2(0.0 if gentle else (1.0 if h % 2 == 1 else -1.0), -(k % 2))
		return Vector2(0, 0 if k % 4 < 2 else 1)
	var w := PI * t / (TICK * 2.0)   # one hop per two frames, as the mockup
	match expression:
		&"happy":
			return Vector2(0, -1.2 * absf(sin(w)))
		&"proud":
			return Vector2(0, 0.8 * sin(w) * sin(w))
		&"worried":
			return Vector2(0.0 if gentle else 0.55 * sin(t * 26.0), 0.25 * sin(w))
		&"surprised":
			return Vector2(0, -2.0 * absf(sin(w)))
		&"guilty":
			return Vector2(0, 0.45 + 0.25 * sin(t * 1.6))
		&"panic":
			return Vector2(0.0 if gentle else 0.7 * sin(t * 40.0), -1.0 * absf(sin(w * 2.0)))
	return Vector2(0, 0.8 * sin(w * 0.5) * sin(w * 0.5))


## Eyes shut for a moment every few seconds (idle, happy, thinking).
func blinking() -> bool:
	return BLINK.has(expression) and not talking and fmod(t + 0.7, 2.9) < 0.17


## The face's nudge toward a point, in cells.
func face_shift() -> Vector2:
	if not pointing():
		return Vector2.ZERO
	if pixel:
		return Vector2(roundf(_point_dir.x), 0)
	return Vector2(_point_dir.x * 0.8, _point_dir.y * 0.4)


## Talking: the open frames (pixel) or how open the mouth is (flat, 0..1).
func mouth_open() -> float:
	if not talking:
		return 0.0
	if pixel:
		return 1.0 if fmod(t * 7.0, 2.0) < 1.0 else 0.0
	return absf(sin(t * 13.0))


## The face grid now: the expression's, with its blink and the talking mouth.
func face_grid() -> Array:
	var rows: Array = (FACES[expression] as Array).duplicate()
	if blinking():
		var b: Array = BLINK[expression]
		for i in b.size():
			rows[i] = b[i]
	if mouth_open() > 0.5:
		for i in TALK.size():
			var r: String = rows[3 + i]
			rows[3 + i] = r.substr(0, 2) + TALK[i] + r.substr(8)
	return rows


## The flat face now, as primitives in face cells (0..10 x 0..6, as FACES):
## [kind, ...] with kind oval (c, radii, colour), arc (c, r, from, to, colour, width),
## line (a, b, colour, width), wave (a, b, colour, width), half (c, radii, colour: the
## lower half), drop (c, size, colour) and ring (c, radii, colour, width).
func flat_face() -> Array:
	var e := expression
	var out: Array = []
	var cheeks := [["oval", Vector2(0.5, 3.5), Vector2(0.95, 0.55), Palette.CREATURE_CHEEK],
			["oval", Vector2(9.5, 3.5), Vector2(0.95, 0.55), Palette.CREATURE_CHEEK]]
	var eyes: Array = []
	var mouth: Array = []
	match e:
		&"idle", &"happy":
			eyes = _dot_eyes([Vector2(2, 1.5), Vector2(8, 1.5)], Vector2(0.95, 1.4), Vector2(-0.35, -0.6))
			out.append_array(cheeks)
			if e == &"idle":
				mouth = [["arc", Vector2(5, 3.7), 0.95, 0.5, PI - 0.5, DARK, 0.6]]
			else:
				mouth = [["arc", Vector2(5, 4.1), 1.5, 0.35, PI - 0.35, DARK, 0.7]]
		&"proud":
			for x in [2.0, 8.0]:
				eyes.append(["arc", Vector2(x, 2.1), 1.45, PI + 0.45, TAU - 0.45, DARK, 0.75])
			out.append_array(cheeks)
			var d := PackedVector2Array()
			for i in 13:
				var a := PI * float(i) / 12.0
				d.append(Vector2(5.0 + 1.95 * cos(a), 3.3 + 2.4 * sin(a)))
			mouth = [["poly", d, DARK], ["oval", Vector2(5, 4.85), Vector2(0.95, 0.55), Palette.CREATURE_CHEEK]]
		&"thinking":
			eyes = _dot_eyes([Vector2(1, 1), Vector2(7, 1)], Vector2(0.9, 1.0), Vector2(0.3, -0.4))
			mouth = [["line", Vector2(5.0, 4.6), Vector2(6.9, 4.3), DARK, 0.6]]
		&"worried":
			eyes = [["line", Vector2(0.6, 0.4), Vector2(2.7, -0.35), DARK, 0.55],
					["line", Vector2(9.4, 0.4), Vector2(7.3, -0.35), DARK, 0.55]]
			eyes.append_array(_dot_eyes([Vector2(2, 2), Vector2(8, 2)], Vector2(0.9, 1.0), Vector2(-0.3, -0.4)))
			out.append(["drop", Vector2(9.7, 4.0), 0.6, Palette.CREATURE_SWEAT])
			mouth = [["arc", Vector2(5, 5.7), 1.5, PI + 0.45, TAU - 0.45, DARK, 0.65]]
		&"surprised":
			eyes = _dot_eyes([Vector2(2, 2), Vector2(8, 2)], Vector2(1.85, 1.95), Vector2(-0.55, -0.6))
			mouth = [["oval", Vector2(5, 5.0), Vector2(0.8, 0.95), DARK]]
		&"guilty":
			for x in [2.3, 7.3]:
				eyes.append(["half", Vector2(x - 0.3, 1.3), Vector2(1.0, 1.2), DARK])
				eyes.append(["line", Vector2(x - 1.4, 1.3), Vector2(x + 1.8, 1.3), DARK, 0.55])
			out.append_array(cheeks)
			out.append(["drop", Vector2(9.55, 0.7), 0.55, Palette.CREATURE_SWEAT])
			mouth = [["wave", Vector2(3.1, 4.5), Vector2(6.9, 4.5), DARK, 0.6]]
		&"panic":
			var j := Vector2.ZERO if gentle else Vector2(0.35 * sin(t * 37.0), 0.3 * cos(t * 29.0))
			for x in [2.0, 8.0]:
				var c := Vector2(x, 1.9)
				eyes.append(["oval", c, Vector2(1.8, 1.8), Palette.CREATURE_GLINT])
				eyes.append(["ring", c, Vector2(1.8, 1.8), DARK, 0.5])
				eyes.append(["oval", c + Vector2((5.0 - x) * 0.08, 0.35) + j, Vector2(0.55, 0.6), DARK])
			eyes.append(["line", Vector2(0.4, -0.3), Vector2(2.8, -0.9), DARK, 0.55])
			eyes.append(["line", Vector2(9.6, -0.3), Vector2(7.2, -0.9), DARK, 0.55])
			out.append(["drop", Vector2(9.8, 4.6), 0.55, Palette.CREATURE_SWEAT])
			mouth = [["oval", Vector2(5, 4.9), Vector2(2.3, 1.1), DARK],
					["oval", Vector2(5, 5.45), Vector2(1.4, 0.45), Palette.CREATURE_CHEEK]]
	if blinking():
		eyes = []
		var at: Array = [Vector2(1, 0.9), Vector2(7, 0.9)] if e == &"thinking" else [Vector2(2, 1.3), Vector2(8, 1.3)]
		for c in at:
			eyes.append(["arc", c, 1.1, 0.35, PI - 0.35, DARK, 0.65])
	var open := mouth_open()
	if talking:
		mouth = [["oval", Vector2(5, 4.6), Vector2(0.95, 0.25 + 0.85 * open), DARK]]
	out.append_array(eyes)
	out.append_array(mouth)
	return out


func _dot_eyes(at: Array, r: Vector2, glint: Vector2) -> Array:
	var out: Array = []
	for c in at:
		out.append(["oval", c, r, DARK])
		out.append(["oval", c + Vector2(glint.x * r.x, glint.y * r.y), Vector2(0.38, 0.38) * (r.x / 0.95), Palette.CREATURE_GLINT])
	return out


# --- Drawing ------------------------------------------------------------------------------

## `rows` at `o` (units), one cell `cu`: each run of a letter is one rect.
func _grid(rows: Array, colors: Dictionary, o: Vector2, cu: float) -> void:
	for y in rows.size():
		var row: String = rows[y]
		var x := 0
		while x < row.length():
			var ch := row[x]
			var x1 := x + 1
			while x1 < row.length() and row[x1] == ch:
				x1 += 1
			if ch != ".":
				var c: Color = colors.get(ch, Color.MAGENTA)
				draw_rect(Rect2(o + Vector2(x, y) * cu, Vector2(x1 - x, 1) * cu), col(c))
			x = x1


## The arm's tip, in grid cells: three cells past the core's edge toward the point.
func _arm_end(_cu: float) -> Vector2:
	var k := core()
	var d := _point_dir
	var edge := 1.0 / sqrt(pow(d.x / k.size.x, 2.0) + pow(d.y / k.size.y, 2.0))
	return k.position + d * (edge + 3.0)


func _arm_start() -> Vector2:
	var k := core()
	var d := _point_dir
	var edge := 1.0 / sqrt(pow(d.x / k.size.x, 2.0) + pow(d.y / k.size.y, 2.0))
	return k.position + d * (edge - 0.8)


## The pointing arm in whole cells: an outlined row of cells from the body's edge.
func _pixel_arm(o: Vector2, cu: float) -> void:
	var a := _arm_start()
	var b := _arm_end(cu)
	var cells: Array[Vector2] = []
	for i in 9:
		var c := (a.lerp(b, i / 8.0)).floor()
		if not c in cells:
			cells.append(c)
	for c in cells.slice(1):
		draw_rect(Rect2(o + (c - Vector2.ONE) * cu, Vector2(3, 3) * cu), col(DARK))
	for c in cells:
		draw_rect(Rect2(o + c * cu, Vector2(cu, cu)), col(arm_color()))


func _flat_arm(o: Vector2, cu: float) -> void:
	var a := o + _arm_start() * cu
	var b := o + (_arm_end(cu) - _point_dir * 0.6) * cu
	draw_line(a, b, col(DARK), 2.4 * cu, true)
	draw_circle(b, 1.2 * cu, col(DARK))
	draw_line(a + _point_dir * 1.4 * cu, b, col(arm_color()), 0.9 * cu, true)
	draw_circle(b, 0.55 * cu, col(arm_color()))


## A face primitive (flat_face()) at face origin `fo`, cell `cu`.
func _prim(p: Array, fo: Vector2, cu: float) -> void:
	match p[0]:
		"oval":
			_oval(fo + p[1] * cu, p[2] * cu, col(p[3]))
		"arc":
			draw_arc(fo + p[1] * cu, p[2] * cu, p[3], p[4], 14, col(p[5]), p[6] * cu, true)
		"line":
			draw_line(fo + p[1] * cu, fo + p[2] * cu, col(p[3]), p[4] * cu, true)
		"wave":
			var pts := PackedVector2Array()
			for i in 9:
				var v: Vector2 = (p[1] as Vector2).lerp(p[2], i / 8.0)
				pts.append(fo + (v + Vector2(0, 0.22 * sin(i * 1.7))) * cu)
			draw_polyline(pts, col(p[3]), p[4] * cu, true)
		"half":
			var pts := PackedVector2Array()
			for i in 11:
				var a := PI * float(i) / 10.0
				pts.append(fo + (p[1] + Vector2(cos(a) * p[2].x, sin(a) * p[2].y)) * cu)
			draw_colored_polygon(pts, col(p[3]))
		"poly":
			var pts := PackedVector2Array()
			for v in p[1]:
				pts.append(fo + v * cu)
			draw_colored_polygon(pts, col(p[2]))
		"drop":
			var c: Vector2 = fo + p[1] * cu
			var s: float = p[2] * cu
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 1.7), c + Vector2(s * 0.72, -s * 0.2), c + Vector2(-s * 0.72, -s * 0.2)]), col(p[3]))
			draw_circle(c, s * 0.75, col(p[3]))
		"ring":
			var pts := _oval_pts(fo + p[1] * cu, p[2] * cu, 24)
			pts.append(pts[0])
			draw_polyline(pts, col(p[3]), p[4] * cu, true)


func _oval_pts(c: Vector2, r: Vector2, n := 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts


func _oval(c: Vector2, r: Vector2, color: Color) -> void:
	draw_colored_polygon(_oval_pts(c, r), color)


## An outlined oval (feet, arms), in units.
func _bean(c: Vector2, r: Vector2, fill: Color, cu: float) -> void:
	var pts := _oval_pts(c, r, 22)
	draw_colored_polygon(pts, col(fill))
	pts.append(pts[0])
	draw_polyline(pts, col(DARK), LINE_W * cu, true)


## The cached flat shapes of this body (cell space).
func shapes() -> Dictionary:
	if not _shapes.has(id):
		_shapes[id] = _build_shapes()
	return _shapes[id]


## cell-space polygons at `o` with cell `cu`.
static func place(polys: Array, o: Vector2, cu: float) -> Array:
	var out: Array = []
	var xf := Transform2D(0.0, Vector2(cu, cu), 0.0, o)
	for poly: PackedVector2Array in polys:
		out.append(xf * poly)
	return out


## Fills each polygon of `polys` (units) with `color`.
func fill(polys: Array, color: Color) -> void:
	for poly: PackedVector2Array in polys:
		if poly.size() >= 3:
			draw_colored_polygon(poly, col(color))


## The closed outline of `poly` (units).
func ink(poly: PackedVector2Array, cu: float) -> void:
	var pts := poly.duplicate()
	pts.append(pts[0])
	draw_polyline(pts, col(DARK), LINE_W * cu, true)


## Chaikin's corner cutting on a closed polygon: soft corners, same shape.
static func soften(pts: PackedVector2Array, rounds := 2) -> PackedVector2Array:
	var cur := pts
	for _r in rounds:
		var nxt := PackedVector2Array()
		for i in cur.size():
			var a := cur[i]
			var b := cur[(i + 1) % cur.size()]
			nxt.append(a.lerp(b, 0.25))
			nxt.append(a.lerp(b, 0.75))
		cur = nxt
	return cur


## A body shape's lit part: what is left of it moved by `away` (the shade shows on the
## edge opposite the light).
static func lit(poly: PackedVector2Array, away: Vector2) -> Array:
	var moved := Transform2D(0.0, away) * poly
	return Geometry2D.intersect_polygons(poly, moved)


## The near rim of `polys` (the highlight): each minus itself moved by `toward`.
static func rim(polys: Array, toward: Vector2) -> Array:
	var out: Array = []
	for poly: PackedVector2Array in polys:
		out.append_array(Geometry2D.clip_polygons(poly, Transform2D(0.0, toward) * poly))
	return out
