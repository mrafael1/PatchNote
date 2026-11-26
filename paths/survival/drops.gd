extends Node
# path:survival
## Survival's drops (PLAN v9 1.6, M47; PLAN names systems/drops.gd, built here so path_lines
## counts it). PathRunner makes it while Survival is live. With `pickups` armed: a player
## kill drops something 10% of the time (tank and bomber 35%), drawn on RunState.loot_rng
## only: holding a gun, weapon or ammo 50/50; on the sidearm, a weapon. A weapon comes from
## the live pool minus guns at max rank in hand (the pistol only while on the sidearm).
## Outside a tryout, crates: 2 at once, then 1 every 20 s, at most 3 on the ground, on the
## arena's free pickup tiles. With `kill_heal` armed: every 5th player kill counted from
## the arming heals 1 HP (`heals` counts only the ones that restored HP). Everything goes through RunState.spawn (the pickup cap).

const PICKUP := preload("res://entities/pickup.tscn")
const CHANCE := 0.10
const BIG_CHANCE := 0.35
const BIG: Array[StringName] = [&"tank", &"bomber"]
const CRATES_FIRST := 2
const CRATE_EVERY := 20.0
const CRATES_MAX := 3
const HEAL_EVERY := 5
const FREE_RADIUS := 1.0   ## tiles: a pickup tile is free with no pickup this close

var runner: Node            ## the PathRunner
var crates := false         ## crates come (not a tryout)
var pickups_on := false
var heal_on := false
var heals := 0
var crates_taken := 0
var _heal_kills := 0
var _tick := 0
var _next_crate := -1
var _mine: Array[Pickup] = []   ## spawned here (a deferred spawn is not in the group yet)


## (Freed with its path: Godot drops the connection with the node.)
func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)


func arm_pickups() -> void:
	if pickups_on:
		return
	pickups_on = true
	if crates:
		for i in CRATES_FIRST:
			_crate(_draw_weapon(), _free_tiles(_far_first()))
		_next_crate = _tick + roundi(CRATE_EVERY * Engine.physics_ticks_per_second)


func arm_kill_heal() -> void:
	if not heal_on:
		heal_on = true
		_heal_kills = 0


func _physics_process(_delta: float) -> void:
	_tick += 1
	if _next_crate >= 0 and _tick >= _next_crate:
		_next_crate = _tick + roundi(CRATE_EVERY * Engine.physics_ticks_per_second)
		if _crates_down() < CRATES_MAX:
			_crate(_draw_weapon(), _free_tiles(_far_first()))


func _on_enemy_killed(enemy: Node, info: RefCounted) -> void:
	if (info as DamageInfo).faction != &"player" or not enemy is Node2D:
		return
	if heal_on:
		_heal_kills += 1
		if _heal_kills % HEAL_EVERY == 0:
			_heal()
	if not pickups_on:
		return
	var archetype: Variant = enemy.get(&"archetype")
	var big := archetype != null and StringName(archetype) in BIG
	var rng := RunState.loot_rng
	if rng.randf() >= (BIG_CHANCE if big else CHANCE):
		return
	var lo := _loadout()
	var weapon := lo == null or lo.on_sidearm() or rng.randf() < 0.5
	var pos := (enemy as Node2D).global_position
	if not weapon:
		spawn_pickup(&"ammo", &"", pos)
		return
	var id := _draw_weapon()
	if id != &"":
		spawn_pickup(&"weapon", id, pos)


## A weapon id from the live pool (loot_rng), or &"" when nothing fits.
func _draw_weapon() -> StringName:
	var lo := _loadout()
	var pool: Array[StringName] = []
	for id: StringName in runner.call(&"offer_pool"):
		var w := lo.held(id) if lo != null else null
		if w != null and w.rank >= Loadout.MAX_RANK:
			continue
		if lo != null and lo.sidearm != null and id == lo.sidearm.def.id and not lo.on_sidearm():
			continue
		pool.append(id)
	if pool.is_empty():
		return &""
	return pool[RunState.loot_rng.randi_range(0, pool.size() - 1)]


func spawn_pickup(kind: StringName, id: StringName, pos: Vector2, crate := false) -> Pickup:
	var p := RunState.spawn(PICKUP, pos, {&"pickup_kind": kind, &"weapon_id": id, &"crate": crate}) as Pickup
	if p != null:
		watch(p)
		_mine.append(p)
	return p


func watch(p: Pickup) -> void:
	p.taken.connect(_on_taken)


func _on_taken(p: Pickup) -> void:
	if p.crate:
		crates_taken += 1
	if p.pickup_kind == &"heal":
		_heal(false)
		return
	var lo := _loadout()
	var player := _player()
	if lo == null or player == null:
		return
	var out := Scavenge.take(lo, p, player.global_position)
	if out != null:
		watch(out)


func _heal(counted := true) -> void:
	var player := _player()
	var h := Component.find(player, Health) as Health if player != null else null
	if h == null or h.dead:
		return
	var before := h.hp()
	h.heal(1.0)
	# M47 review: a heal counts (and logs) only when it restored HP, never at full HP.
	if counted and h.hp() > before + 0.0001:
		heals += 1
		RunState.log_event(&"kill_heal")


func _crate(id: StringName, tiles: Array[Vector2]) -> void:
	if id != &"" and not tiles.is_empty():
		spawn_pickup(&"weapon", id, tiles[0], true)


func _crates_down() -> int:
	return get_tree().get_nodes_in_group(&"pickup").filter(func(p: Node) -> bool:
		return p is Pickup and (p as Pickup).crate and not p.is_queued_for_deletion()).size()


## The `drop` cue (D9): n pickups at the free pickup tiles nearest the player, no draw.
## `what` is a weapon id, ammo or heal. Returns how many landed.
func drop_now(what: StringName, n: int) -> int:
	var tiles := _free_tiles(_nearest_first())
	var made := 0
	var weapon := WeaponDB.has(what)
	for i in mini(n, tiles.size()):
		if spawn_pickup(&"weapon" if weapon else what, what if weapon else &"", tiles[i]) != null:
			made += 1
	return made


## `give` on Survival (1.3): a crate at the free pickup tile nearest the player.
func crate_near_player(id: StringName) -> bool:
	var tiles := _free_tiles(_nearest_first())
	return not tiles.is_empty() and spawn_pickup(&"weapon", id, tiles[0], true) != null


func _loadout() -> Loadout:
	return runner.call(&"loadout") as Loadout


func _player() -> Node2D:
	var game: Node = runner.get(&"game")
	var p: Node = game.get(&"player") if game != null else null
	return p as Node2D if is_instance_valid(p) else null


func _points() -> Array[Vector2]:
	var game: Node = runner.get(&"game")
	var arena: Node = game.get(&"arena") if game != null else null
	var out: Array[Vector2] = []
	if arena == null:
		return out
	var def: ArenaDef = arena.get(&"def")
	if def != null and not def.pickup_tiles.is_empty():
		for t in def.pickup_tiles:
			out.append(t * Tuning.TILE)
	else:
		out.assign(arena.get(&"spawn_points"))
	return out


func _nearest_first() -> Array[Vector2]:
	var player := _player()
	var at := player.global_position if player != null else Vector2.ZERO
	var pts := _points()
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(at) < b.distance_squared_to(at))
	return pts


## Farthest from the nearest enemy first (the fallback order, and the crates').
func _far_first() -> Array[Vector2]:
	var enemies: Array[Vector2] = []
	for e in get_tree().get_nodes_in_group(&"enemy"):
		if e is Node2D and not e.is_queued_for_deletion():
			enemies.append((e as Node2D).global_position)
	var near := func(p: Vector2) -> float:
		var best := INF
		for q in enemies:
			best = minf(best, p.distance_squared_to(q))
		return best
	var pts := _points()
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return near.call(a) > near.call(b))
	return pts


func _free_tiles(order: Array[Vector2]) -> Array[Vector2]:
	var taken: Array[Vector2] = []
	var alive: Array = (_mine as Array).filter(func(p: Variant) -> bool: return is_instance_valid(p) and not (p as Node).is_queued_for_deletion())
	_mine.assign(alive)
	for p in get_tree().get_nodes_in_group(&"pickup") + _mine:
		if p is Node2D and is_instance_valid(p) and not p.is_queued_for_deletion():
			taken.append((p as Node2D).position if not p.is_inside_tree() else (p as Node2D).global_position)
	var out: Array[Vector2] = []
	for t in order:
		if not taken.any(func(q: Vector2) -> bool: return q.distance_to(t) < FREE_RADIUS * Tuning.TILE):
			out.append(t)
			taken.append(t)
	return out
