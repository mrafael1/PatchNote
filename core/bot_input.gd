class_name BotInput
extends PlayerInput
## Simple scripted player for automated runs: aim at the nearest enemy, hold fire,
## back away from close threats, jump now and then. Deliberately dumb. Under B2 it
## plays one action per turn from the clock's danger map instead (_turn_policy).

## B2: a shot's path is followed this far ahead when the bot looks for a tile to go to.
const LANE_TILES := 16

var keep_distance := 220.0
var _tick := 0


func _physics_process(_delta: float) -> void:
	_tick += 1
	dash_pressed = false
	jump_pressed = false
	wait_pressed = false
	if RunState.rules.turn_based:
		_turn_policy()
		return
	var here := origin()
	var nearest: Node2D = null
	var best := INF
	# Enemies, and "threat" nodes that are not enemies but hurt on contact (M33: a
	# patch's stalker). Without them the bot walked into what a player would dodge.
	for e in get_tree().get_nodes_in_group(&"enemy") + get_tree().get_nodes_in_group(&"threat"):
		var n := e as Node2D
		if n == null or n.is_queued_for_deletion():
			continue
		var d := here.distance_squared_to(n.global_position)
		if d < best:
			best = d
			nearest = n
	if nearest == null:
		fire = false
		move = Vector2.RIGHT.rotated(_tick * 0.01)
		return
	var to_enemy := nearest.global_position - here
	aim_dir = to_enemy.normalized()
	fire = true
	if to_enemy.length() < keep_distance:
		move = -aim_dir.rotated(0.6)
	else:
		move = aim_dir.rotated(1.2) * 0.6
	jump_pressed = _tick % 90 == 0
	dash_pressed = _tick % 150 == 75
	jump_held = _tick % 90 < 12


## B2 (PLAN v3 3b.7): one action per turn, chosen from TurnClock.danger when the clock
## waits for it. With an enemy in a clear line and this tile unmarked, shoot it.
## Otherwise go to an unmarked tile in reach (a step, or a dash when it is ready),
## preferring one with a clear line to an enemy, then one off the enemy shots' lanes,
## then one away from walls, then the one farthest from enemies. Otherwise wait, and
## shoot while waiting if it can: killing the attacker during the turn cancels its hit.
## Move and fire are never set together; wait is always set too, so a refused step or
## a shot on cooldown still passes the turn.
func _turn_policy() -> void:
	jump_held = false
	move = Vector2.ZERO
	fire = false
	var clock := TurnClock.current()
	if clock == null or not clock.is_waiting() or RunState.is_paused_except(&"turn"):
		return
	wait_pressed = true
	var here := TurnClock.tile_center(origin())
	var enemies := _enemies_by_distance(here)
	var here_marked := _marked(clock, here)
	var target := _line_target(here, enemies)
	if target != null:
		aim_dir = (target.global_position - here).normalized()
		if not here_marked:
			fire = true
			return
	var lanes := _lanes(clock)
	var best_score := Vector4(-1.0, -1.0, -1.0, -1.0)
	var best_dir := Vector2.ZERO
	var best_dash := false
	for option in _reachable(clock, here):
		var tile: Vector2 = option.tile
		if _marked(clock, tile):
			continue
		var in_line := _line_target(tile, enemies) != null
		if not here_marked and not in_line:
			continue   # safe where it stands: only move to gain a line
		var score := Vector4(1.0 if in_line else 0.0, 0.0 if lanes.has(tile) else 1.0,
				_open_around(clock, tile), _distance_to_nearest(tile, enemies))
		if score > best_score:
			best_score = score
			best_dir = option.dir
			best_dash = option.dash
	move = best_dir
	dash_pressed = best_dash
	fire = best_dir == Vector2.ZERO and target != null


## The tiles one action can end on, as {"tile", "dir", "dash"}: a step to each free
## neighbour no enemy holds (only sideways under gravity, as TurnClock._step), and
## where the dash is ready the farthest tile it reaches past that (as TurnClock._dash).
func _reachable(clock: TurnClock, here: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rules := RunState.rules
	var held := clock.enemy_tiles()
	var dasher := Component.find(get_parent(), Dasher) as Dasher
	var can_dash := dasher != null and dasher.is_ready() and not rules.gravity_enabled
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if rules.gravity_enabled and absf(dir.dot(rules.gravity_dir.normalized())) > 0.5:
			continue
		var reach := 0
		for i in range(1, TurnClock.DASH_TILES + 1):
			var c := here + dir * Tuning.TILE * i
			if not clock.is_free(c) or held.has(c):
				break
			reach = i
		if reach >= 1:
			out.append({"tile": here + dir * Tuning.TILE, "dir": dir, "dash": false})
		if reach >= 2 and can_dash:
			out.append({"tile": here + dir * Tuning.TILE * reach, "dir": dir, "dash": true})
	return out


## How many of the 8 tiles around this one are free: low next to walls and corners,
## where the danger map can close every way out.
func _open_around(clock: TurnClock, tile: Vector2) -> float:
	var out := 0.0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if (dx != 0 or dy != 0) and clock.is_free(tile + Vector2(dx, dy) * Tuning.TILE):
				out += 1.0
	return out


func _marked(clock: TurnClock, tile: Vector2) -> bool:
	return not (clock.danger.get(tile, []) as Array).is_empty()


## Tiles a locked shooter line or a live shot will cross later (not only next turn),
## from the clock's intents.
func _lanes(clock: TurnClock) -> Dictionary:
	var out := {}
	for intent in clock.intents:
		if intent.kind == &"rest":
			continue
		var tiles: Array = intent.tiles
		for t: Vector2 in tiles:
			out[t] = true
		if intent.kind == &"shot" and not tiles.is_empty():
			var ahead: Vector2 = tiles[-1]
			for i in LANE_TILES:
				ahead += (intent.dir as Vector2) * Tuning.TILE
				if not clock.is_free(ahead):
					break
				out[ahead] = true
	return out


func _enemies_by_distance(from: Vector2) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var n := e as Node2D
		if n != null and not n.is_queued_for_deletion():
			out.append(n)
	out.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return from.distance_squared_to(a.global_position) < from.distance_squared_to(b.global_position))
	return out


## The nearest enemy a shot from `from` reaches with no wall in between (the clear-line
## test of the player's auto-attack), or null.
func _line_target(from: Vector2, enemies: Array[Node2D]) -> Node2D:
	var me := get_parent() as Node2D
	if me == null:
		return null
	for n in enemies:
		if is_instance_valid(n) and not EnemyCommon.ray_hits_world(me, from, n.global_position):
			return n
	return null


func _distance_to_nearest(p: Vector2, enemies: Array[Node2D]) -> float:
	var best := INF
	for n in enemies:
		best = minf(best, p.distance_to(n.global_position))
	return best if best < INF else 0.0
