class_name Loadout
extends Component
## The player's weapons (PLAN v9 1.4, M44): aimed slots (one active, switched with
## weapon_prev / weapon_next) and passives. Runtime only: power stays in the session, a
## new session starts at the pistol, rank 1.
##
## With no path (Stage 1, the legacy loop) the pistol at rank 1 fires through
## Shooter.try_fire exactly as before M44 (its own cooldown, synced from Tuning by the
## player), so the hashes hold. Every other weapon or rank goes through Shooter.fire, with
## the weapon's own cooldown here.

const MAX_RANK := 3          ## M50.1 raises it (rank-4 evolutions)
const PISTOL := &"pistol"
const OrbitWeaponShards := preload("res://weapons/orbit_weapon_shards.gd")

var slots: Array[Weapon] = []      ## aimed
var passives: Array[Weapon] = []
var active := 0
var fire_mode: StringName = &"manual_one"   ## the only mode in M44 (paths add more, M45a)
var max_slots := 3                          ## no path (D5); paths set their own

var _passive_nodes := {}   ## weapon id -> its node on the host


func _ready() -> void:
	if slots.is_empty():
		slots = [Weapon.new(WeaponDB.get_weapon(PISTOL), 1)]


func _physics_process(delta: float) -> void:
	for w in slots:
		w.ready_in = maxf(0.0, w.ready_in - delta)
	for w in passives:
		w.ready_in = maxf(0.0, w.ready_in - delta)


func shooter() -> Shooter:
	return Component.find(get_parent(), Shooter) as Shooter


func current() -> Weapon:
	return slots[active] if active < slots.size() else null


## No path and the active weapon is the pistol at rank 1: today's gun, today's call.
func legacy_pistol() -> bool:
	var w := current()
	return Weapon._no_path() and w != null and w.def.id == PISTOL and w.rank == 1


func try_fire(dir: Vector2, auto := false) -> bool:
	var s := shooter()
	if legacy_pistol():
		return s.try_fire(dir, auto) != null
	var w := current()
	if w == null or w.ready_in > 0.0 or dir == Vector2.ZERO:
		return false
	if s.fire(w, dir, auto).is_empty():
		return false
	w.ready_in = float(w.value(&"cooldown"))
	w.shots += 1
	return true


func can_fire() -> bool:
	if legacy_pistol():
		return shooter().can_fire()
	var w := current()
	return w != null and w.ready_in <= 0.0


func held(id: StringName) -> Weapon:
	for w in slots + passives:
		if w.def.id == id:
			return w
	return null


func rank_of(id: StringName) -> int:
	var w := held(id)
	return w.rank if w != null else 0


## The session hands out a weapon (the `give` cue, F2). Held: one rank up, or to `rank`
## if that is higher (capped at MAX_RANK; false at the cap). Not held: an aimed weapon
## takes a free slot at `rank` (a full hand replaces the weakest slot that is not the
## active one: lowest rank, then oldest); a passive attaches. No auto-switch.
func give(id: StringName, rank := 1) -> bool:
	var def := WeaponDB.get_weapon(id)
	if def == null:
		return false
	var have := held(id)
	if have != null:
		var to := clampi(maxi(have.rank + 1, rank), 1, MAX_RANK)
		if to == have.rank:
			return false
		_rank_to(have, to)
		return true
	_add(def, clampi(rank, 1, MAX_RANK))
	return true


## Exact rank (bot --loadout, bench, tests): held -> that rank, else added at it.
func set_weapon(id: StringName, rank: int) -> bool:
	var def := WeaponDB.get_weapon(id)
	if def == null:
		return false
	rank = clampi(rank, 1, MAX_RANK)
	var have := held(id)
	if have != null:
		_rank_to(have, rank)
		return true
	_add(def, rank)
	return true


## One rank up; false at MAX_RANK or when not held.
func upgrade(id: StringName) -> bool:
	var have := held(id)
	if have == null or have.rank >= MAX_RANK:
		return false
	_rank_to(have, have.rank + 1)
	return true


## Cycles the aimed slots (a no-op with one).
func switch(step: int) -> void:
	if slots.size() <= 1 or step == 0:
		return
	active = posmod(active + step, slots.size())
	EventBus.weapon_changed.emit(slots[active].def.id, slots[active].rank)


## Makes the aimed weapon `id` active (bot, bench, tests).
func select(id: StringName) -> bool:
	for i in slots.size():
		if slots[i].def.id == id:
			active = i
			return true
	return false


## Back to the pistol at rank 1, passives gone.
func clear() -> void:
	for id: StringName in _passive_nodes.keys():
		_free_node(id)
	passives.clear()
	slots = [Weapon.new(WeaponDB.get_weapon(PISTOL), 1)]
	active = 0
	EventBus.weapon_changed.emit(PISTOL, 1)


## "pistol:1,shotgun:2" (slot order, then passives).
func summary() -> String:
	var parts: Array[String] = []
	for w in slots + passives:
		parts.append("%s:%d" % [w.def.id, w.rank])
	return ",".join(parts)


func passive_node(id: StringName) -> Node:
	return _passive_nodes.get(id)


func _add(def: WeaponDef, rank: int) -> void:
	var w := Weapon.new(def, rank)
	if def.is_passive():
		passives.append(w)
		_attach(w)
	elif slots.size() < max_slots:
		slots.append(w)
	else:
		var weakest := -1
		for i in slots.size():
			if i == active:
				continue
			if weakest < 0 or slots[i].rank < slots[weakest].rank:
				weakest = i
		slots[weakest] = w
	EventBus.weapon_changed.emit(def.id, rank)


func _rank_to(w: Weapon, rank: int) -> void:
	w.set_rank(rank)
	if w.def.is_passive():
		_attach(w)
	EventBus.weapon_changed.emit(w.def.id, rank)


## (Re)builds a passive weapon's node on the host.
func _attach(w: Weapon) -> void:
	_free_node(w.def.id)
	var host := get_parent()
	if host == null:
		return
	var node: Node = OrbitWeaponShards.new()
	node.weapon_id = w.def.id
	node.shard_count = int(w.value(&"pellets"))
	node.damage = float(w.value(&"damage"))
	node.hit_cooldown = float(w.value(&"cooldown"))
	node.name = "Weapon_%s" % w.def.id
	for t in w.traits:
		t.passive_ready(w, node)
	host.add_child(node)
	_passive_nodes[w.def.id] = node


func _free_node(id: StringName) -> void:
	var old: Node = _passive_nodes.get(id)
	_passive_nodes.erase(id)
	if is_instance_valid(old):
		old.get_parent().remove_child(old)
		old.queue_free()
