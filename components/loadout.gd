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
##
## M47 (Survival, fire_mode manual_ammo): one aimed slot. `sidearm` is the pistol at its rank
## (never empty, infinite ammo); slots[0] is the held weapon, else the sidearm. Each trigger
## shot spends one ammo; at 0 the slot is the sidearm again in the same call. A passive's
## ammo is a battery in seconds (WeaponDef.ammo): at 0 its node goes until refilled.

const MAX_RANK := 3          ## M50.1 raises it (rank-4 evolutions)
const PISTOL := &"pistol"
const OrbitWeaponShards := preload("res://weapons/orbit_weapon_shards.gd")

var slots: Array[Weapon] = []      ## aimed
var passives: Array[Weapon] = []
var active := 0
var fire_mode: StringName = &"manual_one"   ## PathDef.FIRE_MODES; set by apply_path (M45a)
var max_slots := 3                          ## no path (D5); paths set their own
## Quick-draw (M46, Arsenal): set by PathRunner once the `quick_draw` basic is live on a path
## with quick_draw_mult > 1 (apply_path resets it). A real change of the active card arms it;
## the next shot that fires spends it (QuickDraw.mult).
var quick_draw_mult := 1.0
var switches := 0                           ## real changes of the active card (fp, M46)
var sidearm: Weapon                         ## M47: manual_ammo only (null otherwise)
var _battery := {}                          ## M47: passive id -> seconds left (manual_ammo)

var _drawn := false

var _passive_nodes := {}   ## weapon id -> its node on the host


func _ready() -> void:
	if slots.is_empty():
		slots = [Weapon.new(WeaponDB.get_weapon(PISTOL), 1)]


func _physics_process(delta: float) -> void:
	for w in slots:
		w.ready_in = maxf(0.0, w.ready_in - delta)
	for w in passives:
		w.ready_in = maxf(0.0, w.ready_in - delta)
	if fire_mode == &"manual_ammo":
		_drain(delta)


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
	var m := QuickDraw.mult(self)
	if s.fire(w, dir, auto, m).is_empty():
		return false   # refused at the cap: still armed, nothing logged
	QuickDraw.spent(self, m)
	_drawn = false
	w.ready_in = float(w.value(&"cooldown"))
	w.shots += 1
	if fire_mode == &"manual_ammo" and w.ammo_left > 0:
		w.ammo_left -= 1
		if w.ammo_left == 0:
			to_sidearm()
	return true


## M47: the held weapon ran dry (or is dropped): the sidearm again, at once.
func to_sidearm() -> void:
	if sidearm == null:
		return
	slots = [sidearm]
	active = 0
	RunState.log_event(&"ammo_empty")
	EventBus.weapon_changed.emit(sidearm.def.id, sidearm.rank)


## M47: only the sidearm in hand (Survival's dry time).
func on_sidearm() -> bool:
	return sidearm != null and current() == sidearm


## M47: seconds of battery left on passive `id` (-1: none tracked).
func battery(id: StringName) -> float:
	return float(_battery.get(id, -1.0))


## M47: a battery pickup: every passive back to its full battery (its node back on).
func refill_battery() -> void:
	for w in passives:
		var full := float(w.def.ammo)
		if full > 0.0:
			_battery[w.def.id] = full
			if not _passive_nodes.has(w.def.id):
				_attach(w)


func _drain(delta: float) -> void:
	for w in passives:
		if not _battery.has(w.def.id) or float(_battery[w.def.id]) <= 0.0:
			continue
		_battery[w.def.id] = float(_battery[w.def.id]) - delta
		if float(_battery[w.def.id]) <= 0.0:
			_battery[w.def.id] = 0.0
			_free_node(w.def.id)


func can_fire() -> bool:
	if legacy_pistol():
		return shooter().can_fire()
	var w := current()
	return w != null and w.ready_in <= 0.0


func held(id: StringName) -> Weapon:
	for w in slots + passives:
		if w.def.id == id:
			return w
	if sidearm != null and sidearm.def.id == id:
		return sidearm   # M47: the pistol in the pocket while another gun is in hand
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
	var was := active
	active = posmod(active + step, slots.size())
	if active != was:
		_switched()
	EventBus.weapon_changed.emit(slots[active].def.id, slots[active].rank)


## Keys 1-3 (M46): makes aimed slot `i` (0-based) active. False (nothing happens) out of
## range or when it is already active, so Stage 1's one pistol never moves.
func select_slot(i: int) -> bool:
	if i < 0 or i >= slots.size() or i == active:
		return false
	active = i
	_switched()
	EventBus.weapon_changed.emit(slots[active].def.id, slots[active].rank)
	return true


## Quick-draw is armed (the next shot gets the bonus once the basic is live).
func drawn() -> bool:
	return _drawn


func _switched() -> void:
	switches += 1
	_drawn = true


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
	_drawn = false
	_battery.clear()
	if sidearm != null:
		sidearm = slots[0]   # M47: manual_ammo keeps a sidearm
	EventBus.weapon_changed.emit(PISTOL, 1)


## A path starts (M45a, PathRunner): back to nothing, the path's fire mode and slots, then its
## start weapons at exactly rank 1 (never give(), which ranks a held pistol up). null: the
## no-path state (manual_one, 3 slots, the pistol at rank 1).
func apply_path(def: PathDef) -> void:
	clear()
	quick_draw_mult = 1.0
	sidearm = null
	_battery.clear()
	fire_mode = def.fire_mode if def != null else &"manual_one"
	max_slots = def.max_slots if def != null else 3
	if def == null or def.start.is_empty():
		return
	slots.clear()
	for id in def.start:
		set_weapon(id, 1)
	if slots.is_empty():
		slots = [Weapon.new(WeaponDB.get_weapon(PISTOL), 1)]
	active = 0
	if fire_mode == &"manual_ammo":
		sidearm = slots[0]


## Auto (fire_mode auto_all, M45a): every aimed weapon off its cooldown fires on its own at
## its target (AutoFire), through Shooter.fire, with try_fire's bookkeeping. Returns the
## weapons that fired this tick.
func auto_tick() -> int:
	var host := get_parent() as Node2D
	var s := shooter()
	if host == null or s == null:
		return 0
	var fired := 0
	for w in slots:
		if w.ready_in > 0.0:
			continue
		var target := AutoFire.target_for(host, w)
		if target == null:
			continue
		if s.fire(w, target.global_position - host.global_position, true).is_empty():
			continue
		w.ready_in = float(w.value(&"cooldown"))
		w.shots += 1
		fired += 1
	return fired


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
	if fire_mode == &"manual_ammo":
		_add_survival(w)
	elif def.is_passive():
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


## M47 (manual_ammo): an aimed weapon replaces slots[0] (the sidearm stays), a passive
## replaces the passive (max one) with its battery full. Never slots[-1].
func _add_survival(w: Weapon) -> void:
	if w.def.is_passive():
		for old in passives:
			_free_node(old.def.id)
			_battery.erase(old.def.id)
		passives = [w]
		if w.def.ammo > 0:
			_battery[w.def.id] = float(w.def.ammo)
		_attach(w)
	elif w.def.id == PISTOL and sidearm != null:
		sidearm.set_rank(maxi(sidearm.rank, w.rank))
		slots = [sidearm]
	else:
		slots = [w]
	active = 0


func _rank_to(w: Weapon, rank: int) -> void:
	w.set_rank(rank)
	if w.def.is_passive():
		_attach(w)
	EventBus.weapon_changed.emit(w.def.id, rank)


## (Re)builds a passive weapon's node on the host. M45b: a def with a node_script builds
## that node instead (configure(w), then its traits); "" keeps the orbit shards.
func _attach(w: Weapon) -> void:
	_free_node(w.def.id)
	var host := get_parent()
	if host == null:
		return
	if w.def.node_script != "":
		var custom: Node = (load(w.def.node_script) as Script).new()
		custom.call(&"configure", w)
		custom.name = "Weapon_%s" % w.def.id
		for t in w.traits:
			t.passive_ready(w, custom)
		host.add_child(custom)
		_passive_nodes[w.def.id] = custom
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
