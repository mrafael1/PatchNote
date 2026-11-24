class_name Scavenge
extends RefCounted
# path:survival
## Survival's pickup rules (PLAN v9 1.5, 1.6, M47), static: what walking over a pickup does
## to the Loadout. Same weapon: +1 rank (cap 3) and full ammo. On the sidearm: that weapon at
## the pickup's rank (a dropped weapon keeps its ammo). A pistol pickup always ranks up the
## sidearm and never swaps. Another weapon: a swap, the held one drops at the player's feet,
## untouchable until the player has left it. Ammo: +50% of the gun's ammo, capped. Battery:
## the passive's battery full again.

## Loaded at call time: a class_name script holding a scene preload keeps pickup.gd alive
## at exit ("resources still in use").
const PICKUP_PATH := "res://entities/pickup.tscn"
const AMMO_SHARE := 0.5


## Applies `p` to `lo`; returns the swapped-out weapon's pickup (or null).
static func take(lo: Loadout, p: Pickup, at: Vector2) -> Pickup:
	match p.pickup_kind:
		&"ammo":
			var w := lo.current()
			if w != null and not lo.on_sidearm() and w.def.ammo > 0:
				w.ammo_left = mini(w.def.ammo, w.ammo_left + ceili(w.def.ammo * AMMO_SHARE))
			return null
		&"battery":
			lo.refill_battery()
			return null
		&"weapon":
			return _weapon(lo, p, at)
	return null


static func _weapon(lo: Loadout, p: Pickup, at: Vector2) -> Pickup:
	var def := WeaponDB.get_weapon(p.weapon_id)
	if def == null:
		return null
	if def.id == Loadout.PISTOL:
		if lo.sidearm != null and lo.sidearm.rank < Loadout.MAX_RANK:
			lo.sidearm.set_rank(lo.sidearm.rank + 1)
			EventBus.weapon_changed.emit(def.id, lo.sidearm.rank)
		return null
	if def.is_passive():
		lo.give(def.id, p.rank)
		lo.refill_battery()
		return null
	var held := lo.current()
	if held != null and held.def.id == def.id:
		held.set_rank(mini(Loadout.MAX_RANK, held.rank + 1))
		held.ammo_left = def.ammo
		EventBus.weapon_changed.emit(def.id, held.rank)
		return null
	var out: Pickup = null
	if held != null and not lo.on_sidearm():
		out = RunState.spawn(load(PICKUP_PATH) as PackedScene, at, {&"pickup_kind": &"weapon", &"weapon_id": held.def.id,
				&"rank": held.rank, &"ammo_left": held.ammo_left, &"untouchable": true}) as Pickup
	var w := Weapon.new(def, p.rank)
	if p.ammo_left >= 0:
		w.ammo_left = p.ammo_left
	lo.slots = [w]
	lo.active = 0
	EventBus.weapon_changed.emit(def.id, w.rank)
	return out
