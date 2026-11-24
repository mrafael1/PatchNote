class_name PickupField
extends RefCounted
## Bot code (PLAN v9 4, M47): one multi-source BFS distance field over a set of pickups on
## the arena's tile grid (4-connected; ExitGate's field pattern), so the survival policy
## walks around blocks to the pickup nearest by path, not by air. Walkable = a tile no
## block of the ArenaDef covers (ArenaDef._free). No RNG.

var _def: ArenaDef
var _dist := PackedInt32Array()


func _init(def: ArenaDef = null) -> void:
	_def = def if def != null else load(StageSet.ARENA_0) as ArenaDef


static func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / Tuning.TILE), floori(p.y / Tuning.TILE))


static func _index(t: Vector2i) -> int:
	return t.y * Arena.COLS + t.x


func walkable(t: Vector2i) -> bool:
	return _def._free(t)


## Steps from the nearest source to every tile (-1: unreachable or no source).
func build(sources: Array[Vector2]) -> void:
	_dist.resize(Arena.COLS * Arena.ROWS)
	_dist.fill(-1)
	var queue: Array[Vector2i] = []
	for p in sources:
		var t := _near(tile_of(p))
		if t.x >= 0 and _dist[_index(t)] < 0:
			_dist[_index(t)] = 0
			queue.append(t)
	var head := 0
	while head < queue.size():
		var t := queue[head]
		head += 1
		for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var n := t + dir
			if walkable(n) and _dist[_index(n)] < 0:
				_dist[_index(n)] = _dist[_index(t)] + 1
				queue.append(n)


func steps_from(p: Vector2) -> int:
	var t := _near(tile_of(p))
	return -1 if t.x < 0 or _dist.is_empty() else _dist[_index(t)]


## The way to walk from `p` toward the nearest source (ZERO when none is reachable).
func direction_from(p: Vector2) -> Vector2:
	var t := _near(tile_of(p))
	if t.x < 0 or _dist.is_empty() or _dist[_index(t)] < 0:
		return Vector2.ZERO
	var best := _dist[_index(t)]
	var next := t
	for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var n := t + dir
		if walkable(n) and _dist[_index(n)] >= 0 and _dist[_index(n)] < best:
			best = _dist[_index(n)]
			next = n
	var to := (Vector2(next) + Vector2(0.5, 0.5)) * Tuning.TILE - p
	return to.normalized() if to.length() > 1.0 else Vector2.ZERO


func _near(t: Vector2i) -> Vector2i:
	if walkable(t):
		return t
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var n := t + Vector2i(dx, dy)
			if walkable(n):
				return n
	return Vector2i(-1, -1)
