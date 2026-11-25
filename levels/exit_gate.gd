class_name ExitGate
extends Node2D
## Breakout's exit (PLAN v6 4, M35): once a stage's time is up and its prompt is done,
## the gate opens on the far side of the arena (the spawn marker farthest to walk from
## the player) and the stage ends when the player reaches it. It keeps a walking
## distance field over the arena's tiles, so the bot (and the arrow) can find the way
## around blocks. It lives in the world, so the stage clear sweeps it.

signal reached

const GROUP := &"exit_gate"
const RADIUS := 1.0          ## tiles: the player within this of its centre reaches it
const ARROW_FROM := 72.0     ## px from the player, the arrow that points to the gate
const COLOR := Color(0.35, 1.0, 0.6)

var player: Node2D
var _arena: Arena
var _dist := PackedInt32Array()   ## steps to the gate per tile, -1 = blocked or cut off
var _done := false
var _t := 0.0


## Places the gate for `p_arena` and the player where it stands now; returns its position.
func setup(p_arena: Arena, p_player: Node2D) -> Vector2:
	_arena = p_arena
	player = p_player
	var from := _field(_tile_of(p_player.global_position))
	var best := -1
	var at := p_arena.player_start
	for p in p_arena.spawn_points:
		var d := from[_index(_tile_of(p))]
		if d > best:
			best = d
			at = p
	global_position = at
	_dist = _field(_tile_of(at))
	return at


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 5


func _physics_process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _done or not is_instance_valid(player):
		return
	if player.global_position.distance_to(global_position) <= RADIUS * Tuning.TILE:
		_done = true
		reached.emit()


## Walking steps from a point to the gate (-1: no way).
func steps_from(p: Vector2) -> int:
	var t := _free_near(_tile_of(p))
	return -1 if t.x < 0 else _dist[_index(t)]


## The way to walk from `p`: toward the centre of the next tile on the shortest path,
## straight at the gate once within a tile of it.
func direction_from(p: Vector2) -> Vector2:
	if p.distance_to(global_position) <= 1.5 * Tuning.TILE:
		return (global_position - p).normalized()
	var t := _free_near(_tile_of(p))
	if t.x < 0:
		return (global_position - p).normalized()
	var best := _dist[_index(t)]
	var next := t
	for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var n := t + dir
		if not _inside(n):
			continue
		var d := _dist[_index(n)]
		if d >= 0 and d < best:
			best = d
			next = n
	var to := (Vector2(next) + Vector2(0.5, 0.5)) * Tuning.TILE - p
	return to.normalized() if to.length() > 1.0 else (global_position - p).normalized()


func _draw() -> void:
	var r := RADIUS * Tuning.TILE
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	if Skins.current == null or not Skins.current.has(&"gate"):
		draw_circle(Vector2.ZERO, r, Color(COLOR, 0.18 + 0.12 * pulse))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, COLOR, 3.0)
		draw_arc(Vector2.ZERO, r * (0.55 + 0.3 * pulse), 0.0, TAU, 32, Color(COLOR, 0.6), 2.0)
	else:
		# The Pixel preview (PLAN 1.7): the gate sprite filling today's circle.
		var skin := Skins.current
		var s := maxf(1.0, roundf(2.0 * r / maxf(skin.size_of(&"gate").x, 1.0)))
		skin.draw(self, &"gate", Vector2.ZERO, s, skin.idle_frame(&"gate", RunState.real_time()))
	if not is_instance_valid(player) or _done:
		return
	var to := global_position - player.global_position
	if to.length() < 6.0 * Tuning.TILE:
		return
	var dir := to.normalized()
	var tip := to_local(player.global_position + dir * (ARROW_FROM + 14.0))
	var base := to_local(player.global_position + dir * ARROW_FROM)
	var side := dir.orthogonal() * 9.0
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color(COLOR, 0.85))


# --- The distance field ----------------------------------------------------------

func _tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / Tuning.TILE), floori(p.y / Tuning.TILE))


func _inside(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < Arena.COLS and t.y < Arena.ROWS


func _index(t: Vector2i) -> int:
	return t.y * Arena.COLS + t.x


func _walkable(t: Vector2i) -> bool:
	return _inside(t) and _arena.distance_to_blocks((Vector2(t) + Vector2(0.5, 0.5)) * Tuning.TILE) > 0.0


## A walkable tile at or next to `t` (a player hugging a wall can stand on a blocked
## tile's edge); (-1, -1) when none.
func _free_near(t: Vector2i) -> Vector2i:
	if _walkable(t) and (_dist.is_empty() or _dist[_index(t)] >= 0):
		return t
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var n := t + Vector2i(dx, dy)
			if _walkable(n) and (_dist.is_empty() or _dist[_index(n)] >= 0):
				return n
	return Vector2i(-1, -1)


## Steps from `start` to every tile (4-connected walk), -1 where it cannot go.
func _field(start: Vector2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(Arena.COLS * Arena.ROWS)
	out.fill(-1)
	var s := _free_near(start) if _dist.is_empty() else start
	if s.x < 0 or not _walkable(s):
		return out
	out[_index(s)] = 0
	var queue: Array[Vector2i] = [s]
	var head := 0
	while head < queue.size():
		var t := queue[head]
		head += 1
		for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var n := t + dir
			if _walkable(n) and out[_index(n)] < 0:
				out[_index(n)] = out[_index(t)] + 1
				queue.append(n)
	return out
