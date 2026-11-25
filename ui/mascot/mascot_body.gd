class_name MascotBody
extends Node2D
## One body of the AI mascot (PLAN v8 1.3). Drawn with _draw() from shapes in a 100 x 100
## box centred on the origin; whoever holds it scales it (112 px in the corner, 3x in the
## debrief, a card in fork_mascot). Real time drives it, so it moves while the game is
## paused (the debrief).
##
## Every body carries the 8 expressions (Line.EXPRESSIONS) the same way: a pose (bounce,
## tilt, squash) from pose(), eyes from draw_eye() and a mouth from draw_mouth(). A body
## only draws its shape around them in _paint(). talking opens and closes the mouth;
## point_at() leans toward a spot; glitch() splits the colours for a moment.

const IDS: Array[StringName] = Change.MASCOTS
const CARET := &"caret"   ## before the face (SessionDef.face = false): a blinking caret
const DEFAULT := &"cursor"
## Loaded by path in make(): a preload here would be a cycle (the bodies extend this).
const SCRIPTS := {
	&"cursor": "res://ui/mascot/bodies/cursor_body.gd",
	&"window": "res://ui/mascot/bodies/window_body.gd",
	&"blob": "res://ui/mascot/bodies/blob_body.gd",
	&"caret": "res://ui/mascot/bodies/caret_body.gd",
}

const INK := Palette.MASCOT_INK
const EYE_WHITE := Palette.MASCOT_EYE
const SWEAT := Palette.MASCOT_SWEAT

var id: StringName = &""
var expression: StringName = &"idle"
var talking := false
var t := 0.0          ## seconds alive (real time)
var expr_t := 0.0     ## seconds since the expression changed
## Captures and tests: time stands still unless advance() is called.
var frozen := false
## reduce_flashing (set by whoever holds the body): a glitch only wobbles.
var gentle := false

## M47.2 (owner G14a): the highest the drawn body may reach, in this node's own (posed)
## space's y (-INF: no limit). The corner sets it so a hop, a pop or a pointing lean never
## rises into the HUD's top-right band; the pose is pushed down by what it would overshoot.
var top_limit := -INF
## The glitch ghosts' sideways reach (k = 3 + 2 sin in _draw) and the outlines' stroke.
const GHOST_REACH := 5.0
const STROKE := 2.0

var _glitch_left := 0.0
var _point_dir := Vector2.ZERO
var _point_left := 0.0
var _tint := Color.WHITE


## A new body for `body_id` (cursor, window, blob or caret); an unknown id is the cursor.
static func make(body_id: StringName) -> MascotBody:
	var script: GDScript = load(SCRIPTS.get(body_id, SCRIPTS[DEFAULT]))
	var b: MascotBody = script.new()
	b.id = body_id if SCRIPTS.has(body_id) else DEFAULT
	return b


static func is_body(body_id: StringName) -> bool:
	return body_id in IDS


func set_expression(e: StringName) -> void:
	if not e in Line.EXPRESSIONS:
		e = &"idle"
	if e != expression:
		expr_t = 0.0
	expression = e
	queue_redraw()


func say_start() -> void:
	talking = true


func say_end() -> void:
	talking = false
	queue_redraw()


## Leans (cursor: flies a little, window: an arrow, blob: a pseudopod) toward `target`,
## a point in this node's parent's space, for `seconds`. The rule-book warning uses it.
func point_at(target: Vector2, seconds := 1.5) -> void:
	var d := target - position
	_point_dir = d.normalized() if d.length() > 1.0 else Vector2.ZERO
	_point_left = seconds


func pointing() -> bool:
	return _point_left > 0.0 and _point_dir != Vector2.ZERO


## Colour split and jitter for `seconds` (events). With reduce_flashing only a slow
## wobble is left.
func glitch(seconds: float) -> void:
	_glitch_left = maxf(_glitch_left, seconds)


func glitching() -> bool:
	return _glitch_left > 0.0


func _process(delta: float) -> void:
	if not frozen:
		advance(delta)


func advance(delta: float) -> void:
	t += delta
	expr_t += delta
	_glitch_left = maxf(0.0, _glitch_left - delta)
	_point_left = maxf(0.0, _point_left - delta)
	queue_redraw()


func _draw() -> void:
	var p := posed()
	if glitching() and not gentle:
		var k := 3.0 + 2.0 * sin(t * 40.0)
		_tint = Palette.GLITCH_RED
		draw_set_transform(p["offset"] + Vector2(k, 0), p["angle"], p["scale"])
		_paint()
		_tint = Palette.GLITCH_CYAN
		draw_set_transform(p["offset"] - Vector2(k, 0), p["angle"], p["scale"])
		_paint()
	_tint = Color.WHITE
	draw_set_transform(p["offset"], p["angle"], p["scale"])
	_paint()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The body's shape, eyes and mouth, in the posed space. Each body overrides it.
func _paint() -> void:
	pass


## M47.2: points (body space, before the pose) that bound everything _paint() draws at this
## moment: the shape, its shadow, the pointing arrow or pseudopod. Each body overrides it.
func outline() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-50, -50), Vector2(50, -50), Vector2(50, 50), Vector2(-50, 50)])


## pose() with top_limit applied: the offset is pushed down by what the body would
## overshoot above the limit (only ever down, so nothing else changes).
func posed() -> Dictionary:
	var p := pose()
	if top_limit > -INF:
		var top := _bounds(p).position.y
		if top < top_limit:
			p["offset"] = Vector2(p["offset"]) + Vector2(0, top_limit - top)
	return p


## M47.2: the rect (this node's space) the body draws in right now, posed and clamped,
## with the glitch ghosts' reach and the stroke.
func posed_bounds() -> Rect2:
	return _bounds(posed())


func _bounds(p: Dictionary) -> Rect2:
	var xf := Transform2D(float(p["angle"]), Vector2(p["scale"]), 0.0, Vector2(p["offset"]))
	var pts := outline()
	var r := Rect2(xf * pts[0], Vector2.ZERO)
	for v in pts:
		r = r.expand(xf * v)
	var ghost := GHOST_REACH if glitching() and not gentle else 0.0
	return r.grow_individual(STROKE + ghost, STROKE, STROKE + ghost, STROKE)


## M47.2: the union of posed_bounds() over every expression, 2 s of time (every 1/30 s),
## a fresh and a settled expression, at rest, pointing 8 ways and glitching: everywhere the
## body can ever draw (tests and the HUD layout check). The body's state is restored.
func worst_bounds() -> Rect2:
	var saved := [expression, t, expr_t, talking, _glitch_left, _point_dir, _point_left]
	var out := Rect2()
	var first := true
	var dirs: Array[Vector2] = [Vector2.ZERO]
	for i in 8:
		dirs.append(Vector2.RIGHT.rotated(TAU * i / 8.0))
	for e in Line.EXPRESSIONS:
		expression = e
		for d in dirs:
			_point_dir = d
			_point_left = 1.0 if d != Vector2.ZERO else 0.0
			for g in [0.0, 1.0]:
				_glitch_left = g
				for et in [0.0, 0.35]:
					for i in 60:
						t = i / 30.0
						expr_t = et
						var b := posed_bounds()
						out = b if first else out.merge(b)
						first = false
	expression = saved[0]
	t = saved[1]
	expr_t = saved[2]
	talking = saved[3]
	_glitch_left = saved[4]
	_point_dir = saved[5]
	_point_left = saved[6]
	return out


## A colour through the current tint (the glitch's ghosts).
func col(c: Color) -> Color:
	return c * _tint


## {offset, angle, scale} for the expression at this moment. Bodies may add to it.
func pose() -> Dictionary:
	var off := Vector2.ZERO
	var ang := 0.0
	var sc := Vector2.ONE
	match expression:
		&"idle":
			off.y = 2.0 * sin(t * 2.0)
		&"happy":
			var hop := absf(sin(t * 6.0))
			off.y = -8.0 * hop
			sc = Vector2(1.0 + 0.06 * (1.0 - hop), 1.0 - 0.06 * (1.0 - hop))
		&"proud":
			ang = -0.12
			sc = Vector2(1.04, 1.06)
			off.y = -3.0 + 1.5 * sin(t * 1.5)
		&"worried":
			off.x = 1.5 * sin(t * 23.0)
			sc = Vector2(0.97, 0.97)
		&"surprised":
			var pop := maxf(0.0, 1.0 - expr_t / 0.35)
			off.y = -10.0 * pop
			sc = Vector2.ONE * (1.0 + 0.15 * pop)
		&"guilty":
			ang = 0.18
			off.y = 6.0
			sc = Vector2(1.03, 0.92)
		&"thinking":
			ang = 0.08 * sin(t * 1.2)
			off.y = 1.5 * sin(t * 1.2)
		&"panic":
			off = Vector2(3.0 * sin(t * 47.0), 2.0 * cos(t * 41.0))
			ang = 0.05 * sin(t * 31.0)
	if glitching():
		off.x += 4.0 * sin(t * 61.0) if not gentle else 2.0 * sin(t * 9.0)
	return {"offset": off, "angle": ang, "scale": sc}


## Eyes closed for a moment every few seconds (idle and thinking only).
func blinking() -> bool:
	if not expression in [&"idle", &"thinking", &"proud"]:
		return false
	return fmod(t + 0.7, 3.3) < 0.12


## Where the pupils look, as a fraction of the eye's radius.
func look() -> Vector2:
	if pointing():
		return _point_dir * 0.4
	match expression:
		&"guilty":
			return Vector2(-0.35, 0.45)
		&"thinking":
			return Vector2(0.4, -0.45)
		&"panic":
			return Vector2(0.3 * sin(t * 37.0), 0.3 * cos(t * 29.0))
		&"worried":
			return Vector2(0.0, 0.25)
	return Vector2(0.12 * sin(t * 0.7), 0.0)


## One eye at c, radius r. side is -1 for the left eye, 1 for the right.
func draw_eye(c: Vector2, r: float, side: float, skin: Color) -> void:
	var w := maxf(1.5, r * 0.28)
	if blinking():
		draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), col(INK), w, true)
		return
	match expression:
		&"happy":
			draw_arc(c + Vector2(0, r * 0.35), r * 0.85, PI + 0.25, TAU - 0.25, 12, col(INK), w * 1.2, true)
			return
		&"proud":
			# Half-closed: the lower half of the eye under a flat lid.
			var pts := PackedVector2Array()
			for i in 9:
				var a := PI * float(i) / 8.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, col(EYE_WHITE))
			draw_circle(c + Vector2(0.15 * r * side, 0.45 * r), r * 0.42, col(INK))
			draw_line(c + Vector2(-r * 1.1, 0), c + Vector2(r * 1.1, 0), col(INK), w, true)
			return
	var rr := r
	var pupil := 0.5
	if expression == &"surprised":
		rr = r * 1.25
		pupil = 0.28
	elif expression == &"panic":
		rr = r * 1.2
		pupil = 0.25
	draw_circle(c, rr, col(EYE_WHITE))
	draw_arc(c, rr, 0.0, TAU, 20, col(INK), w * 0.6, true)
	draw_circle(c + look() * rr * 0.55, rr * pupil, col(INK))
	draw_circle(c + look() * rr * 0.55 + Vector2(-0.3, -0.3) * rr * pupil, rr * pupil * 0.3, col(EYE_WHITE))
	# Brows carry worry, guilt, thought and panic.
	var inner := -side   # toward the face's middle
	match expression:
		&"worried", &"guilty", &"panic":
			var lift := 1.55 if expression == &"panic" else 1.4
			draw_line(c + Vector2(r * side * 0.9, -r * 1.25), c + Vector2(r * inner * 0.7, -r * lift - r * 0.35), col(INK), w, true)
		&"thinking":
			if side > 0:
				draw_line(c + Vector2(-r * 0.8, -r * 1.7), c + Vector2(r * 0.8, -r * 1.9), col(INK), w, true)
			else:
				draw_line(c + Vector2(-r * 0.8, -r * 1.35), c + Vector2(r * 0.8, -r * 1.35), col(INK), w, true)
	if expression in [&"guilty", &"panic"] and side > 0:
		_sweat(c + Vector2(r * 1.6, -r * 0.6), r * 0.55)
	var _unused := skin


func _sweat(c: Vector2, s: float) -> void:
	var drip := fmod(t * 0.8, 1.0) * s * 1.5 if expression == &"panic" else 0.0
	var at := c + Vector2(0, drip)
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s * 1.6), at + Vector2(s * 0.75, 0), at + Vector2(-s * 0.75, 0)]), col(SWEAT))
	draw_circle(at, s * 0.78, col(SWEAT))


## The mouth at c, width w. Talking opens and closes it, whatever the expression.
func draw_mouth(c: Vector2, w: float) -> void:
	var lw := maxf(1.5, w * 0.12)
	if talking:
		var open := 0.25 + 0.75 * absf(sin(t * 13.0))
		_ellipse(c, Vector2(w * 0.38, w * 0.3 * open + 1.0), col(INK))
		return
	match expression:
		&"idle":
			draw_arc(c + Vector2(0, -w * 0.25), w * 0.4, 0.5, PI - 0.5, 10, col(INK), lw, true)
		&"happy":
			var pts := PackedVector2Array()
			for i in 11:
				var a := PI * float(i) / 10.0
				pts.append(c + Vector2(cos(a) * w * 0.5, sin(a) * w * 0.42))
			draw_colored_polygon(pts, col(INK))
			draw_circle(c + Vector2(0, w * 0.26), w * 0.16, col(Palette.MASCOT_BLUSH))
		&"proud":
			draw_polyline(PackedVector2Array([c + Vector2(-w * 0.4, 0), c + Vector2(w * 0.15, w * 0.08), c + Vector2(w * 0.45, -w * 0.15)]), col(INK), lw, true)
		&"worried":
			var pts := PackedVector2Array()
			for i in 9:
				var x := -0.45 + 0.9 * float(i) / 8.0
				pts.append(c + Vector2(x * w, sin(float(i) * 1.6) * w * 0.06))
			draw_polyline(pts, col(INK), lw, true)
		&"surprised":
			_ellipse(c, Vector2(w * 0.17, w * 0.22), col(INK))
		&"guilty":
			draw_arc(c + Vector2(0, w * 0.3), w * 0.3, PI + 0.6, TAU - 0.6, 10, col(INK), lw, true)
		&"thinking":
			draw_line(c + Vector2(w * 0.0, w * 0.05), c + Vector2(w * 0.35, -w * 0.02), col(INK), lw, true)
		&"panic":
			var pts := PackedVector2Array()
			for i in 7:
				var x := -0.45 + 0.9 * float(i) / 6.0
				pts.append(c + Vector2(x * w, (w * 0.1) * (1.0 if i % 2 == 0 else -1.0)))
			_ellipse(c, Vector2(w * 0.5, w * 0.24), col(INK))
			draw_polyline(pts, col(EYE_WHITE), lw * 0.8, true)


func _ellipse(c: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 18:
		var a := TAU * float(i) / 18.0
		pts.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, color)
