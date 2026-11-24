class_name ArenaDef
extends Resource
## One arena as data (PLAN v6 4), in levels/arenas/<id>.tres. Every arena has the same
## size, Arena.COLS x Arena.ROWS tiles with a one-tile border the Arena adds itself;
## the parked turn grid and the camera rely on it. Units are tiles.

@export var id: StringName
@export var title := ""
## Solid rectangles inside the border, in tiles (x = column, y = row). Their order is
## the collision shapes' order.
@export var blocks: Array[Rect2] = []
## Off-screen spawn markers (the spawner picks among them), in tiles.
@export var spawn_tiles: PackedVector2Array = PackedVector2Array()
@export var player_start := Vector2(33, 14)
## Where Survival's crates and cue drops land (PLAN v9 1.6, M47), in tiles; empty = the
## fallback (Drops: the spawn markers farthest from enemies first).
@export var pickup_tiles: PackedVector2Array = PackedVector2Array()
## The genres this layout is checked for (problems()). Only the top-down rules exist;
## arena_0's gravity reachability is tests/gut/test_gravity.gd's own check.
@export var genres: Array[StringName] = [&"topdown"]

const MIN_SPAWNS := 8
const MIN_PICKUP_TILES := 4   ## M47: when pickup_tiles is set, 4-8 of them
const MAX_PICKUP_TILES := 8
const CLEARANCE := 0.5   ## tiles from any block for the start and every marker


## What is wrong with this layout for a genre; empty when it is fine. Top-down: every
## block inside the border, the start and markers clear of blocks, enough markers, and
## every marker reachable from the start by walking (4-connected free tiles).
func problems(genre_id: StringName = &"topdown") -> Array[String]:
	var out: Array[String] = []
	if not genres.has(genre_id):
		out.append("%s is not made for %s" % [id, genre_id])
		return out
	var inner := Rect2(1, 1, Arena.COLS - 2, Arena.ROWS - 2)
	for b in blocks:
		if not inner.encloses(b) or b.size.x <= 0 or b.size.y <= 0:
			out.append("%s: block %s is outside the border or empty" % [id, b])
	if spawn_tiles.size() < MIN_SPAWNS:
		out.append("%s: %d spawn markers, needs %d" % [id, spawn_tiles.size(), MIN_SPAWNS])
	var points: Array[Vector2] = [player_start]
	points.append_array(Array(spawn_tiles))
	for p in points:
		if not inner.has_point(p) or _distance_to_blocks(p) < CLEARANCE:
			out.append("%s: %s is inside or against a block" % [id, p])
	var reach := _reachable(Vector2i(player_start.floor()))
	for p in spawn_tiles:
		if not reach.has(Vector2i(p.floor())):
			out.append("%s: marker %s cannot be walked to from the start" % [id, p])
	if not pickup_tiles.is_empty():
		if pickup_tiles.size() < MIN_PICKUP_TILES or pickup_tiles.size() > MAX_PICKUP_TILES:
			out.append("%s: %d pickup tiles, needs %d-%d" % [id, pickup_tiles.size(), MIN_PICKUP_TILES,
					MAX_PICKUP_TILES])
		for p in pickup_tiles:
			if not inner.has_point(p) or _distance_to_blocks(p) < CLEARANCE:
				out.append("%s: pickup tile %s is inside or against a block" % [id, p])
			elif not reach.has(Vector2i(p.floor())):
				out.append("%s: pickup tile %s cannot be walked to from the start" % [id, p])
	return out


func _distance_to_blocks(p: Vector2) -> float:
	var best := INF
	for r in blocks:
		var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
		var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
		best = minf(best, Vector2(dx, dy).length())
	return best


func _free(cell: Vector2i) -> bool:
	if cell.x < 1 or cell.y < 1 or cell.x > Arena.COLS - 2 or cell.y > Arena.ROWS - 2:
		return false
	var r := Rect2(Vector2(cell), Vector2.ONE)
	for b in blocks:
		if b.intersects(r):
			return false
	return true


func _reachable(from: Vector2i) -> Dictionary:
	var seen := {}
	if not _free(from):
		return seen
	var todo: Array[Vector2i] = [from]
	seen[from] = true
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := c + d
			if not seen.has(n) and _free(n):
				seen[n] = true
				todo.append(n)
	return seen
