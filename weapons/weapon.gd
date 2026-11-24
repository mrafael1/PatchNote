class_name Weapon
extends RefCounted
## A held weapon (PLAN v9 1.4): its def at a rank, its own cooldown and ammo. Runtime
## only, never saved: power stays in the session.

var def: WeaponDef
var rank := 1
var ammo_left := -1
var ready_in := 0.0        ## seconds until it may fire again (its own cooldown)
var shots := 0             ## shots fired (heavy round counts them)
var traits: Array[WeaponTrait] = []


func _init(p_def: WeaponDef = null, p_rank := 1) -> void:
	def = p_def
	if def != null:
		ammo_left = def.ammo
		set_rank(p_rank)


func set_rank(r: int) -> void:
	rank = r
	traits.clear()
	for t in def.traits_at(rank):
		traits.append(WeaponTrait.make(t))


func id() -> StringName:
	return def.id


## A field at this weapon's rank. The pistol with no path (Stage 1, the legacy loop)
## reads Tuning's cooldown and speed at every rank, so --set= tuning reaches it (M44 D3).
func value(field: StringName) -> Variant:
	if def.id == &"pistol" and _no_path():
		if field == &"cooldown":
			return Tuning.shoot_cooldown
		if field == &"speed":
			return Tuning.projectile_speed
	return def.value(field, rank)


func has_trait(trait_id: StringName) -> bool:
	return traits.any(func(t: WeaponTrait) -> bool: return t.id == trait_id)


## "Shotgun II".
func label() -> String:
	return "%s %s" % [def.title, ["I", "II", "III", "IV"][clampi(rank, 1, 4) - 1]]


## No live path (M45a: RunState.live_path(), which reads S7's / F2's session_path first):
## Stage 1 and the legacy loop, where the pistol is today's gun.
static func _no_path() -> bool:
	return RunState.live_path() == &""
