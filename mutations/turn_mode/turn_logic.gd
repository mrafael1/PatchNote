extends RefCounted
## B2's enemy half (PLAN v3 3b): everything hostile decides on tiles at the start of a
## turn and resolves on tiles at its end. Plans every grid actor in attach order,
## resolves the hits against P, removes spent shots and publishes the next danger map
## on the TurnClock. Holds nothing itself: what lasts between turns lives on the
## GridActor components and in the patch's state().

const GridActor := preload("res://mutations/turn_mode/grid_actor.gd")
const PROJECTILE := preload("res://entities/projectile.tscn")

## Moves are 4-way; ties break in this order (3b.2).
const DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
const AROUND: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP,
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]
const RING_LIMIT := 80   ## snapping gives up past this many tiles (the arena is 66 wide)


## Every live grid actor, in attach order.
static func actors(clock: TurnClock) -> Array[GridActor]:
	var out: Array[GridActor] = []
	for e in clock.get_tree().get_nodes_in_group(TurnClock.GRID_GROUP):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			var a := Component.find(e, GridActor) as GridActor
			if a:
				out.append(a)
	out.sort_custom(func(x: GridActor, y: GridActor) -> bool: return x.order < y.order)
	return out


static func next_order(state: Dictionary) -> int:
	state[&"order"] = int(state.get(&"order", 0)) + 1
	return state[&"order"]


# --- Joining the grid --------------------------------------------------------

## An enemy enters the grid (B2 entry, spawn, split, RC wave): it takes the nearest
## tile that is free and not held, claimed at once. Between turns the danger map is
## rebuilt, since the newcomer acts on the next turn.
static func join(a: GridActor, clock: TurnClock) -> void:
	if clock == null or not clock.active:
		return
	var held := {TurnClock.tile_of(clock.player_tile): true,
			TurnClock.tile_of(clock.player.global_position): true}
	for other in actors(clock):
		if other != a and other.role != GridActor.SHOT:
			held[other.tile] = true
	var host := a.get_parent() as Node2D
	a.tile = _nearest_open(clock, host.global_position, held)
	a.settle()
	if not clock.in_turn():
		publish_danger(clock)


## Nearest tile to p that is free and not held. The search widens ring by ring; once a
## ring holds a candidate, the rings that could still hold a nearer one are searched too.
static func _nearest_open(clock: TurnClock, p: Vector2, held: Dictionary) -> Vector2i:
	var home := TurnClock.tile_of(p)
	var best := home
	var best_d := INF
	var last_ring := RING_LIMIT
	for r in RING_LIMIT + 1:
		if r > last_ring:
			break
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var t := home + Vector2i(dx, dy)
				if held.has(t) or not clock.free_tile(t):
					continue
				var d := TurnClock.centre_of(t).distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = t
		if best_d < INF and last_ring == RING_LIMIT:
			last_ring = mini(RING_LIMIT, ceili(r * 1.415) + 1)
	return best


# --- Start of a turn -----------------------------------------------------------

## The player's action is fixed: each enemy takes one action in attach order, then
## the shots compute the tiles they enter (3b.1, steps 2 and 3).
static func plan(clock: TurnClock, patch: Mutation) -> void:
	var state := patch.state()
	state[&"fired"] = {}
	var p := TurnClock.tile_of(clock.player_tile)
	var all := actors(clock)
	var field := _distance_field(clock, p)
	var held := {p: true}
	for a in all:
		if a.role != GridActor.SHOT:
			held[a.tile] = true
	for a in all:
		if a.role == GridActor.SHOT:
			continue
		a.begin_turn()
		match a.role:
			GridActor.CHASER:
				_plan_melee(a, p, field, held, DIRS)
			GridActor.TANK:
				if a.turns_seen % 2 == 0:
					_plan_melee(a, p, field, held, AROUND)
			GridActor.SHOOTER:
				_plan_shooter(a, p, field, held, clock, patch)
	for a in all:
		if a.role == GridActor.SHOT:
			_plan_shot(a, clock)


## Breadth-first distances from P over free tiles, 4-way, once per turn.
static func _distance_field(clock: TurnClock, p: Vector2i) -> Dictionary:
	var field := {p: 0}
	var queue: Array[Vector2i] = [p]
	var i := 0
	while i < queue.size():
		var t := queue[i]
		i += 1
		for d in DIRS:
			var n := t + d
			if not field.has(n) and clock.free_tile(n):
				field[n] = int(field[t]) + 1
				queue.append(n)
	return field


## Chaser (4 tiles) and acting tank (8 tiles): attack if P is in reach, otherwise step
## down the field.
static func _plan_melee(a: GridActor, p: Vector2i, field: Dictionary, held: Dictionary,
		reach: Array[Vector2i]) -> void:
	if (p - a.tile) in reach:
		a.attacks = true
		return
	var here := int(field.get(a.tile, -1))
	if here < 0:
		return   # cut off from P: stay
	var best := a.tile
	var best_d := here + 1   # never uphill: sideways at worst, otherwise stay
	for d in DIRS:
		var n := a.tile + d
		if held.has(n) or not field.has(n):
			continue
		if int(field[n]) < best_d:
			best_d = int(field[n])
			best = n
	_move(a, best, held)


static func _move(a: GridActor, to: Vector2i, held: Dictionary) -> void:
	if to == a.tile:
		return
	held.erase(a.tile)
	held[to] = true
	a.move_to(to)


## Shooter (3b.2): fire along the line it locked last turn, else aim when P is on a
## clear line in range and the cooldown is over, else move toward an aligned tile in
## the band.
static func _plan_shooter(a: GridActor, p: Vector2i, field: Dictionary, held: Dictionary,
		clock: TurnClock, patch: Mutation) -> void:
	if a.aim != Vector2i.ZERO:
		_fire(a, clock, patch)
		a.aim = Vector2i.ZERO
		a.cooldown = Tuning.grid_shooter_cooldown
		return
	var to_p := p - a.tile
	var line := _line_dir(to_p)
	var in_range := maxi(absi(to_p.x), absi(to_p.y)) * Tuning.TILE <= Tuning.shooter_range
	var clear := line != Vector2i.ZERO and in_range and clear_line(clock, a.tile, p)
	if clear and a.cooldown <= 0:
		a.aim = line
		return
	var here := int(field.get(a.tile, -1))
	if here < 0:
		return
	if clear and _in_band(here):
		return   # aligned in the band: hold the line until the cooldown is over
	var options: Array[Vector2i] = []
	for d in DIRS:
		var n := a.tile + d
		if not held.has(n) and field.has(n):
			options.append(n)
	# 1. A tile in the band and aligned with P.
	for n in options:
		if _in_band(int(field[n])) and _misalignment(p - n) == 0:
			_move(a, n, held)
			return
	# 2. The tile in the band that brings it closest to aligned.
	var best := a.tile
	var best_m := 1 << 30
	for n in options:
		var m := _misalignment(p - n)
		if _in_band(int(field[n])) and m < best_m:
			best_m = m
			best = n
	if best != a.tile:
		_move(a, best, held)
		return
	# 3. Toward the band.
	if _in_band(here):
		return
	var far := here > _band_far()
	var best_d := here
	for n in options:
		var d := int(field[n])
		if (far and d < best_d) or (not far and d > best_d):
			best_d = d
			best = n
	_move(a, best, held)


static func _band_near() -> int:
	return roundi(Tuning.shooter_near / Tuning.TILE)


static func _band_far() -> int:
	return roundi(Tuning.shooter_far / Tuning.TILE)


static func _in_band(d: int) -> bool:
	return d >= _band_near() and d <= _band_far()


## In tiles: 0 when v lies on a row, a column or a diagonal.
static func _misalignment(v: Vector2i) -> int:
	var x := absi(v.x)
	var y := absi(v.y)
	return mini(mini(x, y), absi(x - y))


## The 8-way unit step from the origin toward v, or zero if v is not on a row, a
## column or a diagonal (or is zero).
static func _line_dir(v: Vector2i) -> Vector2i:
	if v == Vector2i.ZERO or _misalignment(v) != 0:
		return Vector2i.ZERO
	return Vector2i(signi(v.x), signi(v.y))


## The one wall rule (3b.3): a step is blocked if its tile is not free, and a diagonal
## step also if either orthogonal neighbour is not free (no corner cutting).
static func blocked(clock: TurnClock, from: Vector2i, d: Vector2i) -> bool:
	if not clock.free_tile(from + d):
		return true
	if d.x != 0 and d.y != 0:
		return not clock.free_tile(from + Vector2i(d.x, 0)) or not clock.free_tile(from + Vector2i(0, d.y))
	return false


## Up to `steps` tiles from `from` along d, stopping before the first blocked step.
static func line_tiles(clock: TurnClock, from: Vector2i, d: Vector2i, steps: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var t := from
	for i in steps:
		if blocked(clock, t, d):
			break
		t += d
		out.append(t)
	return out


## A shot from `from` would reach `to` along their row, column or diagonal.
static func clear_line(clock: TurnClock, from: Vector2i, to: Vector2i) -> bool:
	var d := _line_dir(to - from)
	if d == Vector2i.ZERO:
		return false
	var t := from
	while t != to:
		if blocked(clock, t, d):
			return false
		t += d
	return true


## The shot starts on the shooter's tile and enters its first tiles this turn. At the
## projectile cap no shot is made; the patch state remembers which shooters fired what.
static func _fire(a: GridActor, clock: TurnClock, patch: Mutation) -> void:
	var host := a.get_parent() as Node2D
	var weapon := Component.find(host, Shooter) as Shooter
	var shot := RunState.spawn(PROJECTILE, TurnClock.centre_of(a.tile), {
		&"kind": &"enemy_projectile",
		&"faction": &"enemy",
		&"velocity": Vector2(a.aim).normalized() * Tuning.shooter_projectile_speed,
		&"damage": weapon.damage if weapon else 1.0,
	})
	var fired: Dictionary = patch.state()[&"fired"]
	if shot == null:
		fired[a.order] = -1
		return
	var s := Component.attach(shot, GridActor, patch.id) as GridActor
	s.role = GridActor.SHOT
	s.order = next_order(patch.state())
	s.tile = a.tile
	s.dir = a.aim
	s.turns_left = Tuning.grid_shot_turns
	fired[a.order] = s.order
	_plan_shot(s, clock)
	EventBus.projectile_fired.emit(shot)


static func _plan_shot(s: GridActor, clock: TurnClock) -> void:
	s.start = s.tile
	s.path = line_tiles(clock, s.tile, s.dir, Tuning.grid_shot_tiles)
	if not s.path.is_empty():
		s.tile = s.path[-1]
	s.spent = blocked(clock, s.tile, s.dir)   # against a wall: this is its last turn
	s.turns_left -= 1
	s.begin_motion()


# --- End of a turn -------------------------------------------------------------

## Resolution (3b.1 step 5): everyone onto its tile, melee attacks from enemies still
## alive, shots that entered P (or started on it), spent shots out, then the next
## danger map. Logs a turn_danger entry whenever P was marked or the player was hit.
static func resolve(clock: TurnClock, patch: Mutation, number: int) -> void:
	var p := TurnClock.tile_of(clock.player_tile)
	var marked: Array = clock.danger.get(clock.player_tile, [])   # read before a death clears it
	var all := actors(clock)
	for a in all:
		a.settle()
	var health := Component.find(clock.player, Health) as Health
	var log_from := RunState.run_log.size()
	var results := {}   # attach order -> outcome of its hit on P
	for a in all:
		if (a.role == GridActor.CHASER or a.role == GridActor.TANK) and a.attacks:
			var host := a.get_parent() as Node2D
			var amount := float(Tuning.get("%s_contact_damage" % a.role))
			results[a.order] = _hit(health, amount, &"contact", host.global_position)
	for a in all:
		if a.role != GridActor.SHOT:
			continue
		var shot := a.get_parent() as Node2D
		if a.start == p or a.path.has(p):
			results[a.order] = _hit(health, float(shot.get(&"damage")), &"projectile", shot.global_position)
			_remove(shot)
		elif a.spent or a.turns_left <= 0:
			_remove(shot)
	_log_turn(patch, p, number, marked, results, log_from)
	publish_danger(clock)


## Hits the player through Health.take (i-frames, grace and invincible logging apply)
## and returns what happened: &"hit", or why it was blocked.
static func _hit(health: Health, amount: float, kind: StringName, pos: Vector2) -> StringName:
	if health == null or health.dead:
		return &"dead"
	var outcome := &"hit"
	if health.is_invulnerable():
		outcome = &"iframes"
	elif RunState.in_grace():
		outcome = &"grace"
	elif RunState.invincible:
		outcome = &"invincible"
	health.take(DamageInfo.make(amount, kind, &"enemy", pos))
	return outcome


static func _remove(shot: Node) -> void:
	shot.set_physics_process(false)
	shot.queue_free()


## One run-log entry per turn that ended on a marked tile or with a hit or an attack:
## each source the map held on P and what became of it. Outcomes: hit; blocked hits
## (iframes, grace, invincible, dead); exemptions (died: the enemy was killed during the
## turn; removed: the shot was gone; no_shot: the projectile cap refused the shot).
## Anything else ("missed") breaks the danger promise, and so does any entry in
## "unmarked": an attack on P from an actor no source on P stood for, blocked or not
## (i-frames log no player_hit, so only this shows it). "hits" counts player_hit
## entries logged by this resolution.
static func _log_turn(patch: Mutation, p: Vector2i, number: int, sources: Array,
		results: Dictionary, log_from: int) -> void:
	var hits := 0
	for i in range(log_from, RunState.run_log.size()):
		if RunState.run_log[i].event == &"player_hit":
			hits += 1
	var fired: Dictionary = patch.state().get(&"fired", {})
	var outcomes: Array[Dictionary] = []
	var accounted := {}   # attach orders a source on P stood for
	for s: Dictionary in sources:
		var result := "missed"
		var order: int = s.order
		if s.kind == &"aim" and fired.has(order):
			# The shooter fired: the outcome is its shot's.
			order = fired[order]
			if order < 0:
				result = "no_shot"
			elif results.has(order):
				result = String(results[order])
		elif results.has(order):
			result = String(results[order])
		elif not _alive(s.entity):
			result = "removed" if s.kind == &"shot" else "died"
		accounted[order] = true
		outcomes.append({"kind": String(s.kind), "result": result})
	var unmarked: Array[Dictionary] = []
	for order: int in results:
		if not accounted.has(order):
			unmarked.append({"order": order, "result": String(results[order])})
	if sources.is_empty() and hits == 0 and unmarked.is_empty():
		return
	RunState.log_event(&"turn_danger", {"turn": number, "tile": TurnClock.centre_of(p),
			"marked": not sources.is_empty(), "hits": hits, "sources": outcomes,
			"unmarked": unmarked})


static func _alive(entity: Variant) -> bool:
	if not is_instance_valid(entity):
		return false
	var node := entity as Node
	var health := Component.find(node, Health) as Health
	return not node.is_queued_for_deletion() and (health == null or not health.dead)


# --- The danger map -----------------------------------------------------------

## Rebuilds the danger map and the intents for the next turn (3b.4) and hands them to
## the clock (shapes documented on TurnClock.danger and TurnClock.intents).
static func publish_danger(clock: TurnClock) -> void:
	var map := {}
	var intents: Array[Dictionary] = []
	for a in actors(clock):
		var host := a.get_parent() as Node2D
		match a.role:
			GridActor.CHASER:
				_mark(map, clock, a, _around(a.tile, DIRS))
			GridActor.TANK:
				if (a.turns_seen + 1) % 2 == 0:
					_mark(map, clock, a, _around(a.tile, AROUND))
				else:
					intents.append({"kind": &"rest", "entity": host, "tile": TurnClock.centre_of(a.tile)})
			GridActor.SHOOTER:
				if a.aim != Vector2i.ZERO:
					_mark(map, clock, a, line_tiles(clock, a.tile, a.aim, Tuning.grid_shot_tiles), &"aim")
					var reach := Tuning.grid_shot_tiles * Tuning.grid_shot_turns
					intents.append({"kind": &"aim", "entity": host, "dir": Vector2(a.aim),
							"tiles": _centres(line_tiles(clock, a.tile, a.aim, reach))})
			GridActor.SHOT:
				var next := line_tiles(clock, a.tile, a.dir, Tuning.grid_shot_tiles)
				var tiles: Array[Vector2i] = [a.tile]
				tiles.append_array(next)
				_mark(map, clock, a, tiles)
				intents.append({"kind": &"shot", "entity": host, "dir": Vector2(a.dir), "tiles": _centres(next)})
	clock.publish(map, intents)


static func _around(t: Vector2i, offsets: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in offsets:
		out.append(t + d)
	return out


static func _centres(tiles: Array[Vector2i]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for t in tiles:
		out.append(TurnClock.centre_of(t))
	return out


static func _mark(map: Dictionary, clock: TurnClock, a: GridActor, tiles: Array[Vector2i],
		kind: StringName = &"") -> void:
	var source := {"kind": kind if kind != &"" else a.role, "entity": a.get_parent(), "order": a.order}
	for t in tiles:
		if not clock.free_tile(t):
			continue
		var c := TurnClock.centre_of(t)
		if not map.has(c):
			map[c] = []
		(map[c] as Array).append(source)
