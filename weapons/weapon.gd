class_name Weapon
extends RefCounted
## A held weapon (PLAN v9 1.4): its def at a rank, its own cooldown and ammo. Runtime
## only, never saved: power stays in the session.
##
## M50.1a: `curve` is the path's rank curve (PathDef.rank_curve, passed by Loadout, never read
## from RunState): &"classic" reads WeaponDef.ranks 2-3 as before; &"deep" routes value() and
## the traits through WeaponCurve (no top rank, trait levels).

var def: WeaponDef
var rank := 1
var curve: StringName = &"classic"
var ammo_left := -1
## M47.6d1 (the revolver, WeaponDef.magazine > 0): rounds in the load, and the game seconds
## left of an automatic reload (0: not reloading). Sim state, never saved.
var mag_left := 0
var reload_left := 0.0
var ready_in := 0.0        ## seconds until it may fire again (its own cooldown)
var shots := 0             ## shots fired (heavy round counts them)
var traits: Array[WeaponTrait] = []
## M50.4a (Auto depth design 4): role -> multiplier from the path's items and boost (Loadout
## writes it). Empty (every path but Auto with a boost or an item): value() is exactly the old
## code. M50.4b: each role scales the field its def names (WeaponDef.stat_fields, else
## DEFAULT_FIELDS); `area` also reaches node knobs through stat_mult.
var mods := {}
## M50.4c1 (Auto depth design 6): the evolution's launch numbers (field -> value; its def's
## launch_values) while a `nerf` cue holds them, read before mods; {} = the steady numbers.
var launch := {}

## M50.4b: the field each item role scales when the def names none.
const DEFAULT_FIELDS := {&"haste": &"cooldown", &"might": &"damage", &"area": &"blast_radius"}


func _init(p_def: WeaponDef = null, p_rank := 1, p_curve: StringName = &"classic") -> void:
	def = p_def
	curve = p_curve
	if def != null:
		ammo_left = def.ammo
		mag_left = def.magazine
		set_rank(p_rank)


func deep() -> bool:
	return curve == WeaponCurve.DEEP


func set_rank(r: int) -> void:
	rank = r
	traits.clear()
	if deep():
		for pair: Array in WeaponCurve.traits(def, rank):
			traits.append(WeaponTrait.make(pair[0], pair[1], true))
		return
	for t in def.traits_at(rank):
		traits.append(WeaponTrait.make(t))


func id() -> StringName:
	return def.id


## M47.6d1: a magazine weapon (the revolver).
func has_magazine() -> bool:
	return def.magazine > 0


## M47.6d1: empty and reloading (a magazine weapon only).
func reloading() -> bool:
	return has_magazine() and reload_left > 0.0


## M47.6d1: one round spent; the last one starts the reload (reload_s at this rank).
func spend_round() -> void:
	if not has_magazine():
		return
	mag_left = maxi(0, mag_left - 1)
	if mag_left == 0:
		reload_left = float(value(&"reload_s"))


## M47.6d1: `delta` game seconds of reload; full again when it runs out.
func tick_reload(delta: float) -> void:
	if reload_left <= 0.0:
		return
	reload_left -= delta
	if reload_left <= 0.0:
		reload_left = 0.0
		mag_left = def.magazine
## M50.3b (Cluster): after the Loadout fired `shots` for `faction`, a weapon with a burst gives
## each player shell its ClusterMod (after the traits' mods, so it reads point blank's damage).
## Only the Loadout calls this, and not for the misfuse: Shooter.fire (shared with enemies and
## the misfuse) never attaches a burst.
func attach(shots: Array[Node], faction: StringName) -> void:
	if def.burst <= 0 or faction != &"player":
		return
	for p in shots:
		var mod: ProjectileMod = (load("res://weapons/cluster_mod.gd") as GDScript).new()
		mod.count = def.burst
		mod.angle = (p.get(&"velocity") as Vector2).angle()
		p.add_mod(mod)


## A field at this weapon's rank. The pistol with no path (Stage 1, the legacy loop)
## reads Tuning's cooldown and speed at every rank, so --set= tuning reaches it (M44 D3).
func value(field: StringName) -> Variant:
	if def.id == &"pistol" and _no_path():
		if field == &"cooldown":
			return Tuning.shoot_cooldown
		if field == &"speed":
			return Tuning.projectile_speed
	var v: Variant = WeaponCurve.value(def, field, rank) if deep() else def.value(field, rank)
	if not launch.is_empty() and launch.has(field):
		v = launch[field]
	if mods.is_empty():
		return v
	var map: Dictionary = def.stat_fields if not def.stat_fields.is_empty() else DEFAULT_FIELDS
	for role: StringName in mods:
		if StringName(map.get(role, &"")) == field:
			v = float(v) * float(mods[role])
	return v


## M50.4a: the multiplier of role `role` (1.0 without it), for knobs that are not a field.
func stat_mult(role: StringName) -> float:
	return float(mods.get(role, 1.0))


func has_trait(trait_id: StringName) -> bool:
	return traits.any(func(t: WeaponTrait) -> bool: return t.id == trait_id)


## The level of mechanic `trait_id` (0: not held).
func trait_level(trait_id: StringName) -> int:
	for t in traits:
		if t.id == trait_id:
			return t.level
	return 0


## "Shotgun II"; on the deep curve the digit ("Shotgun 7"); M50.4c1: an evolution its name
## ("MINIGUN": it has no ranks).
func label() -> String:
	if def.is_evolution():
		return def.title.to_upper()
	if deep():
		return "%s %d" % [def.title, rank]
	return "%s %s" % [def.title, ["I", "II", "III", "IV"][clampi(rank, 1, 4) - 1]]


## No live path (M45a: RunState.live_path(), which reads S7's / F2's session_path first):
## Stage 1 and the legacy loop, where the pistol is today's gun.
static func _no_path() -> bool:
	return RunState.live_path() == &""
