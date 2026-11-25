extends Node2D
## A burning line (laser rank 2). Not an entity: not registered, nothing hits it. The line
## is the shot's path (`points`, a polyline: muzzle, each bounce, the end). Each enemy whose
## centre is within its half width + MARGIN of any of its segments takes DAMAGE every TICK
## seconds of game time, for LIFE seconds. Plain colours (no Look reads; M48).

const LIFE := 1.0
const TICK := 0.5
const DAMAGE := 1.0
const MARGIN := 4.0
const COLOR := Palette.BURN
## M50.1a: on the deep curve at most this many lines are alive (the oldest goes).
const DEEP_CAP := 12
const GROUP := &"burn_line_zone"

var points := PackedVector2Array()
var source: StringName = &""
var hits := 0                      ## tests
var life := LIFE                   ## M50.1a: per line (the trait's level)
var _born := -1.0
var _next := {}                    ## enemy -> game time it may burn again


## The point of the line closest to `pos` (pos itself when the line is empty).
func closest_point(pos: Vector2) -> Vector2:
	if points.is_empty():
		return pos
	var best := points[0]
	for i in range(1, points.size()):
		var c := Geometry2D.get_closest_point_to_segment(pos, points[i - 1], points[i])
		if c.distance_squared_to(pos) < best.distance_squared_to(pos):
			best = c
	return best


func _enter_tree() -> void:
	add_to_group(GROUP)


## M50.1a: frees the oldest lines (tree order) until fewer than `cap` are alive.
static func make_room(cap: int) -> void:
	var alive: Array[Node] = []
	for z in RunState.get_tree().get_nodes_in_group(GROUP):
		if not z.is_queued_for_deletion():
			alive.append(z)
	var i := 0
	while alive.size() - i >= cap and i < alive.size():
		alive[i].remove_from_group(GROUP)
		alive[i].queue_free()
		i += 1


func _physics_process(_delta: float) -> void:
	if _born < 0.0:
		_born = RunState.game_time
	var age := RunState.game_time - _born
	if age >= life or points.size() < 2:
		queue_free()
		return
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := e as Node2D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		var half: float = enemy.get(&"half_width") if enemy.get(&"half_width") != null else 15.0
		var closest := closest_point(enemy.global_position)
		if closest.distance_to(enemy.global_position) > half + MARGIN:
			continue
		if RunState.game_time < float(_next.get(enemy, -1.0)):
			continue
		_next[enemy] = RunState.game_time + TICK
		var hp := Component.find(enemy, Health) as Health
		if hp and hp.take(DamageInfo.make(DAMAGE, &"burn", &"player", closest, source)):
			hits += 1
	queue_redraw()


func _draw() -> void:
	if points.size() < 2:
		return
	var age := RunState.game_time - _born if _born >= 0.0 else 0.0
	var a := clampf(1.0 - age / life, 0.0, 1.0)
	draw_polyline(points, Color(Palette.color(&"burn"), 0.55 * a), 5.0)
