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

const MAX_RANK := 3          ## the classic curve's top (Survival, Auto, no path)
const PISTOL := &"pistol"
const OrbitWeaponShards := preload("res://weapons/orbit_weapon_shards.gd")
## M50.1b: the misfuse's wrong ways, one every other shot: left, right, back.
const MISFUSE_TURNS: Array[float] = [-PI / 2.0, PI / 2.0, PI]

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
## M50.1a: the path's top rank (PathDef.rank_cap; 0 = none, Arsenal) and rank curve
## (PathDef.rank_curve, handed to every Weapon). No path: MAX_RANK and the classic curve.
var rank_cap := MAX_RANK
var curve: StringName = &"classic"
## M50.1b (Arsenal's misfuse, PathRunner): switching is locked while it lasts, and its shots
## leave in a fixed wrong-way cycle (MISFUSE_TURNS by shot count, no RNG) drawn as
## `misfuse_skin`. The slots never change: it is an overlay.
var switch_locked := false
var misfuse_skin: StringName = &""
var misfuse_shots := 0
var _battery := {}                          ## M47: passive id -> seconds left (manual_ammo)
## M50.4a (Auto depth design 2.1): every weapon, aimed or passive-mode, takes one of max_slots
## (PathDef.shared_slots, set by apply_path; false elsewhere). _add enforces it.
var shared_slots := false
## M50.4a: the `boost` filler's stacks (+BOOST_STEP damage each, every held weapon, this
## session; Weapon.mods). 0 = none: every value() is the old one.
var boost := 0
const BOOST_STEP := 0.05
## M50.4b (Auto depth design 4): the passive items held (ItemDef at a level), in the order
## taken; at most max_items (PathDef.max_items, set by apply_path; 0 elsewhere). Items own no
## node: each held weapon's mods carry them (_apply_mods).
var items: Array[Item] = []
var max_items := 0

var _drawn := false

var _passive_nodes := {}   ## weapon id -> its node on the host


func _ready() -> void:
	if slots.is_empty():
		slots = [Weapon.new(WeaponDB.get_weapon(PISTOL), 1, curve)]


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
	var shots: Array[Node]
	if misfuse_skin != &"":
		shots = s.fire(w, dir, auto, m, misfuse_turn(misfuse_shots), misfuse_skin)
	else:
		shots = s.fire(w, dir, auto, m)
	if shots.is_empty():
		return false   # refused at the cap: still armed, nothing logged
	if misfuse_skin != &"":
		misfuse_shots += 1
	QuickDraw.spent(self, m)
	_drawn = false
	w.ready_in = float(w.value(&"cooldown"))
	w.shots += 1
	if fire_mode == &"manual_ammo" and w.ammo_left > 0:
		w.ammo_left -= 1
		if w.ammo_left == 0:
			to_sidearm()
	return true


## M50.1b: the misfuse's turn for its shot `n` (0 on even shots, then left, right, back).
static func misfuse_turn(n: int) -> float:
	if n % 2 == 0:
		return 0.0
	return MISFUSE_TURNS[floori(n / 2.0) % MISFUSE_TURNS.size()]


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


## M50.1b: the held card for weapon `id`: the weapon itself, else a held fusion with `id` as a
## parent (a parent's card feeds it), else null.
func holder(id: StringName) -> Weapon:
	var w := held(id)
	if w != null:
		return w
	for s in slots + passives:
		if id in s.def.parents:
			return s
	return null


## M50.1b: aimed slots holding `a` and `b` become one fused card `fused_id` at `rank`. It takes
## the active parent's slot (else the first of the two), the other slot goes, and it is the
## active card (not a switch: no quick-draw). Its shots are the parents' (most-fired stays
## fair). False unless both are held aimed cards and `fused_id` is a fusion.
func fuse(a: StringName, b: StringName, fused_id: StringName, rank: int) -> bool:
	var def := WeaponDB.get_weapon(fused_id)
	var ia := -1
	var ib := -1
	for i in slots.size():
		if slots[i].def.id == a:
			ia = i
		elif slots[i].def.id == b:
			ib = i
	if def == null or not def.is_fusion() or ia < 0 or ib < 0:
		return false
	var at := ia if active == ia else (ib if active == ib else mini(ia, ib))
	var gone := ib if at == ia else ia
	var w := Weapon.new(def, cap(rank), curve)
	w.shots = slots[ia].shots + slots[ib].shots
	slots[at] = w
	slots.remove_at(gone)
	active = slots.find(w)
	EventBus.weapon_changed.emit(def.id, w.rank)
	return true


func rank_of(id: StringName) -> int:
	var w := held(id)
	return w.rank if w != null else 0


## The session hands out a weapon (the `give` cue, F2). Held: one rank up, or to `rank`
## if that is higher (capped at rank_cap; false at the cap). Not held: an aimed weapon
## takes a free slot at `rank` (a full hand replaces the weakest slot that is not the
## active one: lowest rank, then oldest); a passive attaches. No auto-switch.
func give(id: StringName, rank := 1) -> bool:
	var def := WeaponDB.get_weapon(id)
	if def == null:
		return false
	var have := held(id)
	if have != null:
		var to := cap(maxi(have.rank + 1, rank))
		if to == have.rank:
			return false
		_rank_to(have, to)
		return true
	_add(def, cap(rank))
	return true


## Exact rank (bot --loadout, bench, tests): held -> that rank, else added at it.
func set_weapon(id: StringName, rank: int) -> bool:
	var def := WeaponDB.get_weapon(id)
	if def == null:
		return false
	rank = cap(rank)
	var have := held(id)
	if have != null:
		_rank_to(have, rank)
		return true
	_add(def, rank)
	return true


## `by` ranks up (M50.1a: a rare card is 2); false at rank_cap or when not held.
func upgrade(id: StringName, by := 1) -> bool:
	var have := held(id)
	if have == null or (rank_cap > 0 and have.rank >= rank_cap):
		return false
	_rank_to(have, cap(have.rank + maxi(1, by)))
	return true


## M50.1a: `rank` within 1..rank_cap (no top when rank_cap is 0).
func cap(rank: int) -> int:
	return clampi(rank, 1, rank_cap) if rank_cap > 0 else maxi(1, rank)


## M50.1a: every aimed slot is taken.
func hand_full() -> bool:
	return slots.size() >= max_slots


## M50.1a (Arsenal's replace): aimed slot `i` becomes weapon `id` at `rank`; the old card and
## its ranks go. The slot keeps its position, so an active slot stays active (no switch, no
## quick-draw). False out of range or for an unknown or passive weapon.
func replace_slot(i: int, id: StringName, rank: int) -> bool:
	var def := WeaponDB.get_weapon(id)
	if def == null or def.is_passive() or i < 0 or i >= slots.size():
		return false
	slots[i] = Weapon.new(def, cap(rank), curve)
	EventBus.weapon_changed.emit(def.id, slots[i].rank)
	return true


## Cycles the aimed slots (a no-op with one, or while the misfuse locks switching).
func switch(step: int) -> void:
	if slots.size() <= 1 or step == 0 or switch_locked:
		return
	var was := active
	active = posmod(active + step, slots.size())
	if active != was:
		_switched()
	EventBus.weapon_changed.emit(slots[active].def.id, slots[active].rank)


## Keys 1-3 (M46): makes aimed slot `i` (0-based) active. False (nothing happens) out of
## range or when it is already active, so Stage 1's one pistol never moves.
func select_slot(i: int) -> bool:
	if i < 0 or i >= slots.size() or i == active or switch_locked:
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
	slots = [Weapon.new(WeaponDB.get_weapon(PISTOL), 1, curve)]
	active = 0
	_drawn = false
	_battery.clear()
	boost = 0
	items.clear()
	if sidearm != null:
		sidearm = slots[0]   # M47: manual_ammo keeps a sidearm
	EventBus.weapon_changed.emit(PISTOL, 1)


## A path starts (M45a, PathRunner): back to nothing, the path's fire mode and slots, then its
## start weapons at exactly rank 1 (never give(), which ranks a held pistol up). null: the
## no-path state (manual_one, 3 slots, the pistol at rank 1).
func apply_path(def: PathDef) -> void:
	rank_cap = def.rank_cap if def != null else MAX_RANK
	curve = def.rank_curve if def != null else &"classic"
	clear()
	quick_draw_mult = 1.0
	sidearm = null
	_battery.clear()
	fire_mode = def.fire_mode if def != null else &"manual_one"
	max_slots = def.max_slots if def != null else 3
	shared_slots = def != null and def.shared_slots
	max_items = def.max_items if def != null else 0
	if def == null or def.start.is_empty():
		return
	slots.clear()
	for id in def.start:
		set_weapon(id, 1)
	if slots.is_empty():
		slots = [Weapon.new(WeaponDB.get_weapon(PISTOL), 1, curve)]
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


## M50.4a: every held weapon, aimed slots then passive-mode ones (the shared slots' order).
func weapons() -> Array[Weapon]:
	return slots + passives


func weapon_count() -> int:
	return slots.size() + passives.size()


## M50.4a: the `boost` filler: one more stack on every held weapon (a node weapon re-reads its
## numbers, its clock kept: reconfigure).
func add_boost() -> void:
	boost += 1
	_apply_mods()


## M50.4a: the role multipliers every held weapon gets now ({} with no boost and no item).
## M50.4b: each held item multiplies its role (Might and the boost multiply together).
func mods_now() -> Dictionary:
	var m := {}
	if boost > 0:
		m[&"might"] = 1.0 + BOOST_STEP * boost
	for it in items:
		m[it.def.stat] = float(m.get(it.def.stat, 1.0)) * it.def.mult(it.level)
	return m


## M50.4b: the held item `id` (null: not held).
func item(id: StringName) -> Item:
	for it in items:
		if it.def.id == id:
			return it
	return null


func item_level(id: StringName) -> int:
	var it := item(id)
	return it.level if it != null else 0


## M50.4b: item `id` joins at level 1 while a slot is free (false: unknown, unbuilt, held or
## full). Every held weapon re-reads its numbers (node weapons keep their clocks).
func add_item(id: StringName) -> bool:
	var def := WeaponDB.item(id)
	if def == null or not def.built() or item(id) != null or items.size() >= max_items:
		return false
	items.append(Item.new(def, 1))
	_apply_mods()
	EventBus.item_changed.emit(id, 1)
	return true


## M50.4b: held item `id` one level up, to rank_cap (false: not held or at the top).
func level_item(id: StringName) -> bool:
	var it := item(id)
	if it == null or (rank_cap > 0 and it.level >= rank_cap):
		return false
	it.level += 1
	_apply_mods()
	EventBus.item_changed.emit(id, it.level)
	return true


## "haste:2,area:1" (the order taken; "" with none).
func items_summary() -> String:
	var parts: Array[String] = []
	for it in items:
		parts.append("%s:%d" % [it.def.id, it.level])
	return ",".join(parts)


func _apply_mods() -> void:
	var m := mods_now()
	for w in weapons():
		w.mods = m.duplicate()
	for w in passives:
		var node: Node = _passive_nodes.get(w.def.id)
		if not is_instance_valid(node):
			continue
		if node.has_method(&"reconfigure"):
			node.call(&"reconfigure", w)
		elif &"damage" in node:
			node.set(&"damage", float(w.value(&"damage")))


## "pistol:1,shotgun:2" (slot order, then passives).
func summary() -> String:
	var parts: Array[String] = []
	for w in slots + passives:
		parts.append("%s:%d" % [w.def.id, w.rank])
	return ",".join(parts)


func passive_node(id: StringName) -> Node:
	return _passive_nodes.get(id)


func _add(def: WeaponDef, rank: int) -> void:
	var w := Weapon.new(def, rank, curve)
	if boost > 0 or not items.is_empty():
		w.mods = mods_now()
	if shared_slots and fire_mode != &"manual_ammo" and weapon_count() >= max_slots:
		_drop_weakest()   # M50.4a: never a 4th weapon (give, F2, --loadout, the bench)
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


## M50.4a (shared slots full): the weakest weapon that is not the active one goes, across
## weapons() (lowest rank; ties: the last in weapons() order); a passive-mode one's node is
## freed. The active slot never goes.
func _drop_weakest() -> void:
	var cur := current()
	var victim: Weapon = null
	for x in weapons():
		if x == cur:
			continue
		if victim == null or x.rank <= victim.rank:
			victim = x
	if victim == null:
		return
	var i := slots.find(victim)
	if i >= 0:
		slots.remove_at(i)
		if i < active:
			active -= 1
		active = clampi(active, 0, maxi(0, slots.size() - 1))
	else:
		passives.erase(victim)
		_free_node(victim.def.id)
		_battery.erase(victim.def.id)
	RunState.log_event(&"weapon_dropped", {"weapon": String(victim.def.id), "rank": victim.rank})


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
