class_name BotInput
extends PlayerInput
## Simple scripted player for automated runs: aim at the nearest enemy, hold fire,
## back away from close threats, jump now and then. Deliberately dumb. Under B2 it
## plays one action per turn from the clock's danger map instead (_turn_policy).

## B2: a shot's path is followed this far ahead when the bot looks for a tile to go to.
const LANE_TILES := 16

var keep_distance := 220.0
## PLAN v9 4 (M45a): the live path's bot policy (PathDef.bot_policy, read each tick; "" =
## today's code byte for byte) and a degenerate probe (--probe=afk: no move, no dash, no
## jump, no fire; Auto still fires by itself). M46: `no_switch` (the arsenal policy never
## switches) and `first_pick` (bot_runs only: card 0, its own pick_rng draw still consumed;
## offers stay paired with the default only while the hands match). M47: `no_pickup` (the
## survival policy never detours to pickups; it still takes what it walks over).
var policy: StringName = &""
var probe: StringName = &""
var _tick := 0

## Auto's kiting: the sectors around the bot and how far it looks.
const SECTORS := 8
const CROWD_REACH := 6.0 * 48.0
const GEM_CLEAR := 3.0 * 48.0

## Arsenal (M46): when each card is wanted, and how long a choice is held (a policy constant:
## switches_per_min reads it).
const SHOTGUN_REACH := 4.0 * 48.0
const LASER_REACH := 12.0 * 48.0
const LASER_CORRIDOR := 0.5 * 48.0
const GROUP := 3
const HOLD_TICKS := 30
var _card: StringName = &""
var _card_tick := -1000000

## Survival (M47): with no enemy within GREED_CLEAR it walks to the best pickup along one
## multi-source BFS field, rebuilt every FIELD_EVERY ticks.
const GREED_CLEAR := 4.0 * 48.0
const FIELD_EVERY := 15
var _field: PickupField
var _field_tick := -1000000
## M47 review: the aimed gun the bot last swapped away from, and the one it held (so a
## dropped gun is never walked back to while another aimed gun is in hand).
var _dropped: StringName = &""
var _held: StringName = &""


func _physics_process(_delta: float) -> void:
	# M47.3 (PLAN 1.16): the pause menu is invisible to the policy (no tick, nothing moves).
	if RunState.is_paused_for(RunState.MENU):
		return
	_tick += 1
	dash_pressed = false
	jump_pressed = false
	wait_pressed = false
	select_slot = -1   # M46: only the arsenal policy sets it
	if RunState.rules.turn_based:
		_turn_policy()
		return
	var path := RunState.path_def()
	policy = path.bot_policy if path != null else &""
	if probe == &"afk":
		move = Vector2.ZERO
		fire = false
		jump_held = false
		return
	if policy == &"auto":
		_auto_policy()
		return
	if policy == &"arsenal":
		_arsenal_policy()
		return
	if policy == &"survival":
		_survival_policy()
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
	# Breakout (M35): an open exit gate is where to go; shoot on the way.
	var gate := get_tree().get_first_node_in_group(ExitGate.GROUP) as ExitGate
	if nearest == null:
		fire = false
		move = gate.direction_from(here) if gate else Vector2.RIGHT.rotated(_tick * 0.01)
		return
	var to_enemy := nearest.global_position - here
	aim_dir = to_enemy.normalized()
	fire = true
	if to_enemy.length() < keep_distance:
		move = -aim_dir.rotated(0.6)
	elif _hunting():
		move = _hunt_dir(here, nearest)   # M47.6c1: the set is all out: go and get them
	else:
		move = aim_dir.rotated(1.2) * 0.6
	if gate:
		move = gate.direction_from(here)
	jump_pressed = _tick % 90 == 0
	dash_pressed = _tick % 150 == 75
	jump_held = _tick % 90 < 12


## M47.6c1 (design 4.2): the bot hunts only once a clear session's set is all out (budget
## spent, no spawn cue to come: RunState.wave_closed, never set elsewhere) and its shots hurt
## (`hits`). Then it walks the arena's tile field to the nearest enemy instead of orbiting.
const HUNT_EVERY := 15
var _hunt_field: PickupField
var _hunt_tick := -1000000


func _hunting() -> bool:
	return RunState.wave_closed and RunState.session != null and Unlocks.has_basic(&"hits")


func _hunt_dir(here: Vector2, target: Node2D) -> Vector2:
	if _hunt_field == null:
		_hunt_field = PickupField.new(RunState.session.arena_def())
	if _tick - _hunt_tick >= HUNT_EVERY:
		var sources: Array[Vector2] = [target.global_position]
		_hunt_field.build(sources)
		_hunt_tick = _tick
	var dir := _hunt_field.direction_from(here)
	return dir if dir != Vector2.ZERO else aim_dir


## Auto (PLAN v9 4, M45a): never holds fire (Auto fires by itself; today's bot always held
## it, which would never test auto-fire). With an enemy within keep_distance it kites away
## from the densest of 8 sectors within 6 T; else, with no enemy within 3 T, it walks to the
## nearest gem; else today's orbit. The aim still follows the nearest enemy (dash aim), the
## exit gate still wins. No RNG.
func _auto_policy() -> void:
	fire = false
	var here := origin()
	var nearest: Node2D = null
	var best := INF
	for e in get_tree().get_nodes_in_group(&"enemy") + get_tree().get_nodes_in_group(&"threat"):
		var n := e as Node2D
		if n == null or n.is_queued_for_deletion():
			continue
		var d := here.distance_squared_to(n.global_position)
		if d < best:
			best = d
			nearest = n
	var gate := get_tree().get_first_node_in_group(ExitGate.GROUP) as ExitGate
	var gem := _nearest_gem(here)
	if nearest == null:
		# The open gate wins over a gem here too (review M45a).
		if gate:
			move = gate.direction_from(here)
		elif gem != null:
			move = (gem.global_position - here).normalized()
		else:
			move = Vector2.RIGHT.rotated(_tick * 0.01)
		return
	var to_enemy := nearest.global_position - here
	aim_dir = to_enemy.normalized()
	if to_enemy.length() < keep_distance:
		move = -_densest_dir(here, aim_dir).rotated(0.6)
	elif gem != null and to_enemy.length() > GEM_CLEAR:
		move = (gem.global_position - here).normalized()
	else:
		move = aim_dir.rotated(1.2) * 0.6
	if gate:
		move = gate.direction_from(here)
	jump_pressed = _tick % 90 == 0
	dash_pressed = _tick % 150 == 75
	jump_held = _tick % 90 < 12


## Arsenal (PLAN v9 4, M46): today's movement, aim and fire (aim nearest, hold fire, kite at
## keep_distance, the gate wins), plus the hand. The card it wants: the shotgun with an enemy
## within 4 T, the laser with >= 3 enemies in a 0.5 T corridor along the aim to 12 T, the
## launcher into a group of >= 3 within its blast (aimed there), else the highest rank (ties:
## slot order); a choice is held HOLD_TICKS. It switches through select_slot, as keys 1-3 do.
## The flank rule (contract for M50's shielder): a target with `shield_arc_deg` > 0 whose
## front arc (around `facing`) covers the bot is stepped around (90 degrees, the shorter way
## out) with fire held. No RNG.
func _arsenal_policy() -> void:
	var here := origin()
	var nearest: Node2D = null
	var best := INF
	for e in get_tree().get_nodes_in_group(&"enemy") + get_tree().get_nodes_in_group(&"threat"):
		var n := e as Node2D
		if n == null or n.is_queued_for_deletion():
			continue
		var d := here.distance_squared_to(n.global_position)
		if d < best:
			best = d
			nearest = n
	var gate := get_tree().get_first_node_in_group(ExitGate.GROUP) as ExitGate
	if nearest == null:
		fire = false
		move = gate.direction_from(here) if gate else Vector2.RIGHT.rotated(_tick * 0.01)
		return
	var to_enemy := nearest.global_position - here
	aim_dir = to_enemy.normalized()
	fire = true
	if to_enemy.length() < keep_distance:
		move = -aim_dir.rotated(0.6)
	else:
		move = aim_dir.rotated(1.2) * 0.6
	var lo := Component.find(get_parent(), Loadout) as Loadout
	var group_at := _choose_card(lo, here, to_enemy.length())
	if group_at != null:   # the launcher (or Cluster) aims at its group
		aim_dir = (group_at.global_position - here).normalized()
	if lo != null and probe != &"no_switch":
		for i in lo.slots.size():
			if lo.slots[i].def.id == _card and i != lo.active:
				select_slot = i
	var step := flank_step(here, nearest)
	if step != Vector2.ZERO:
		move = step
		fire = false
	if gate:
		move = gate.direction_from(here)
	jump_pressed = _tick % 90 == 0
	dash_pressed = _tick % 150 == 75
	jump_held = _tick % 90 < 12


## Survival (PLAN v9 4, M47): today's move, aim and fire (aim nearest, hold fire, kite at
## keep_distance, the gate wins) and the flank rule; with no enemy within GREED_CLEAR it
## walks to a pickup along the BFS field: the wanted ones (a gun it holds, any gun while on
## the sidearm, ammo under half) first, the others last. --probe=no_pickup never detours.
## No RNG.
func _survival_policy() -> void:
	var here := origin()
	var nearest: Node2D = null
	var best := INF
	for e in get_tree().get_nodes_in_group(&"enemy") + get_tree().get_nodes_in_group(&"threat"):
		var n := e as Node2D
		if n == null or n.is_queued_for_deletion():
			continue
		var d := here.distance_squared_to(n.global_position)
		if d < best:
			best = d
			nearest = n
	var gate := get_tree().get_first_node_in_group(ExitGate.GROUP) as ExitGate
	var to_pickup := _pickup_dir(here) if probe != &"no_pickup" else Vector2.ZERO
	if nearest == null:
		fire = false
		if gate:
			move = gate.direction_from(here)
		elif to_pickup != Vector2.ZERO:
			move = to_pickup
		else:
			move = Vector2.RIGHT.rotated(_tick * 0.01)
		return
	var to_enemy := nearest.global_position - here
	aim_dir = to_enemy.normalized()
	fire = true
	if to_pickup != Vector2.ZERO and to_enemy.length() > GREED_CLEAR:
		move = to_pickup
	elif to_enemy.length() < keep_distance:
		move = -aim_dir.rotated(0.6)
	else:
		move = aim_dir.rotated(1.2) * 0.6
	var step := flank_step(here, nearest)
	if step != Vector2.ZERO:
		move = step
		fire = false
	if gate:
		move = gate.direction_from(here)
	jump_pressed = _tick % 90 == 0
	dash_pressed = _tick % 150 == 75
	jump_held = _tick % 90 < 12


## Toward the best pickup (ZERO: none). The field is rebuilt every FIELD_EVERY ticks.
func _pickup_dir(here: Vector2) -> Vector2:
	var wanted: Array[Vector2] = []
	var others: Array[Vector2] = []
	var lo := Component.find(get_parent(), Loadout) as Loadout
	_note_swap(lo)
	for g in get_tree().get_nodes_in_group(&"pickup"):
		var p := g as Pickup
		if p == null or p.is_queued_for_deletion() or p.is_gem() or p.untouchable:
			continue
		if _would_bounce(lo, p, _dropped):
			continue
		(wanted if _wants(lo, p) else others).append(p.global_position)
	var sources := wanted if not wanted.is_empty() else others
	if sources.is_empty():
		return Vector2.ZERO
	if _field == null or _tick - _field_tick >= FIELD_EVERY:
		if _field == null:
			_field = PickupField.new(RunState.session.arena_def() if RunState.session != null else null)
		_field.build(sources)
		_field_tick = _tick
	var dir := _field.direction_from(here)
	if dir == Vector2.ZERO:
		var near := sources[0]
		for s in sources:
			if here.distance_squared_to(s) < here.distance_squared_to(near):
				near = s
		dir = (near - here).normalized() if here.distance_to(near) > 1.0 else Vector2.ZERO
	return dir


## Remembers the aimed gun the bot just swapped away from.
func _note_swap(lo: Loadout) -> void:
	var w := lo.current() if lo != null else null
	var now: StringName = w.def.id if w != null and not lo.on_sidearm() else &""
	if now != _held:
		if _held != &"" and now != &"":
			_dropped = _held
		_held = now


## True for a weapon pickup that would swap out the aimed gun in hand for another one,
## while that gun still has half its ammo, or for the gun just dropped (M47 review: no
## leave-and-come-back loop between two guns). A pistol or passive pickup never swaps.
static func _would_bounce(lo: Loadout, p: Pickup, dropped: StringName) -> bool:
	if lo == null or p.pickup_kind != &"weapon" or lo.on_sidearm():
		return false
	var w := lo.current()
	if w == null or w.def.id == p.weapon_id or (lo.sidearm != null and p.weapon_id == lo.sidearm.def.id):
		return false
	var def := WeaponDB.get_weapon(p.weapon_id)
	if def == null or def.is_passive():
		return false
	return p.weapon_id == dropped or w.def.ammo <= 0 or w.ammo_left * 2 >= w.def.ammo


static func _wants(lo: Loadout, p: Pickup) -> bool:
	if lo == null:
		return true
	var w := lo.current()
	if p.pickup_kind == &"weapon":
		return lo.on_sidearm() or (w != null and w.def.id == p.weapon_id)
	if p.pickup_kind == &"ammo":
		return w != null and not lo.on_sidearm() and w.def.ammo > 0 and w.ammo_left * 2 < w.def.ammo
	return p.pickup_kind == &"heal"


## Sets _card (held HOLD_TICKS once chosen) and returns the launcher's group node (or null).
func _choose_card(lo: Loadout, here: Vector2, nearest_d: float) -> Node2D:
	if lo == null or lo.slots.is_empty():
		return null
	var want := &""
	var group_at: Node2D = null
	# M50.1b: a fused card answers for its parents (Prism: the shotgun's and the laser's rule).
	# M50.3b: Cluster answers for the shotgun and the launcher; the launcher's group rule wins.
	var sg := lo.holder(&"shotgun")
	var ls := lo.holder(&"laser")
	var lc := lo.holder(&"launcher")
	var cluster_group: Node2D = null
	if lc != null and lc in lo.slots and lc.def.is_fusion():
		cluster_group = _group_for(lc)
	if cluster_group != null:
		want = lc.def.id
		group_at = cluster_group
	elif sg != null and sg in lo.slots and nearest_d < SHOTGUN_REACH:
		want = sg.def.id
	elif ls != null and ls in lo.slots and _in_corridor(here) >= GROUP:
		want = ls.def.id
	elif lc != null and lc in lo.slots and not lc.def.is_fusion():
		group_at = _group_for(lc)
		if group_at != null:
			want = lc.def.id
	if want == &"":
		var top: Weapon = null
		for w in lo.slots:
			if top == null or w.rank > top.rank or (w.rank == top.rank and w.def.is_fusion() and not top.def.is_fusion()):
				top = w
		want = top.def.id
	if want != _card and (_card == &"" or _tick - _card_tick >= HOLD_TICKS or lo.held(_card) == null):
		_card = want
		_card_tick = _tick
	return group_at if lc != null and _card == lc.def.id else null


## The densest group within auto-attack range with >= GROUP enemies inside `w`'s blast, or null.
func _group_for(w: Weapon) -> Node2D:
	var radius := float(w.value(&"blast_radius")) * Tuning.TILE
	var at := AutoFire.densest(get_parent() as Node2D, Tuning.auto_attack_range, radius)
	if at != null and _around(at.global_position, radius) >= GROUP:
		return at
	return null


## Enemies in the LASER_CORRIDOR along aim_dir, out to LASER_REACH.
func _in_corridor(here: Vector2) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var m := e as Node2D
		if m == null or m.is_queued_for_deletion():
			continue
		var v := m.global_position - here
		var along := v.dot(aim_dir)
		if along > 0.0 and along <= LASER_REACH and absf(v.cross(aim_dir)) <= LASER_CORRIDOR:
			n += 1
	return n


## Enemies within `radius` of `at`.
func _around(at: Vector2, radius: float) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var m := e as Node2D
		if m != null and not m.is_queued_for_deletion() and m.global_position.distance_squared_to(at) <= radius * radius:
			n += 1
	return n


## The flank rule (M46 contract, M50's shielder): Vector2.ZERO unless `target` exposes
## shield_arc_deg > 0 and facing, and its front arc covers `here`; then the unit step 90
## degrees around it, toward the nearer edge of the arc (ties: counter-clockwise).
static func flank_step(here: Vector2, target: Node2D) -> Vector2:
	var arc: Variant = target.get(&"shield_arc_deg")
	var facing: Variant = target.get(&"facing")
	if arc == null or facing == null or float(arc) <= 0.0 or (facing as Vector2) == Vector2.ZERO:
		return Vector2.ZERO
	var v := here - target.global_position
	if v == Vector2.ZERO:
		return Vector2.ZERO
	var off := (facing as Vector2).angle_to(v)
	if absf(off) >= deg_to_rad(float(arc)) / 2.0:
		return Vector2.ZERO
	return v.normalized().rotated(PI / 2.0 if off >= 0.0 else -PI / 2.0)


## The direction of the most crowded of SECTORS slices within CROWD_REACH (each enemy
## weighs 1 / its distance); `fallback` when none is near.
func _densest_dir(here: Vector2, fallback: Vector2) -> Vector2:
	var weights: Array[float] = []
	weights.resize(SECTORS)
	weights.fill(0.0)
	var any := false
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var n := e as Node2D
		if n == null or n.is_queued_for_deletion():
			continue
		var v := n.global_position - here
		var d := v.length()
		if d > CROWD_REACH:
			continue
		var s := int(fposmod(v.angle(), TAU) / (TAU / SECTORS)) % SECTORS
		weights[s] += 1.0 / maxf(d, 24.0)
		any = true
	if not any:
		return fallback
	var top := 0
	for i in SECTORS:
		if weights[i] > weights[top]:
			top = i
	return Vector2.RIGHT.rotated((top + 0.5) * TAU / SECTORS)


func _nearest_gem(here: Vector2) -> Node2D:
	var out: Node2D = null
	var best := INF
	for g in get_tree().get_nodes_in_group(&"gem"):
		var n := g as Node2D
		if n == null or n.is_queued_for_deletion():
			continue
		var d := here.distance_squared_to(n.global_position)
		if d < best:
			best = d
			out = n
	return out


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
