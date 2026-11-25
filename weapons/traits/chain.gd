extends WeaponTrait
## Pistol rank 6 (M50.1a, deep curve only): a kill sends the same shot on to the nearest enemy
## within 5 T; hops 3 -> 4 -> 5 -> 6. It re-aims the projectile (no spawn); never on a blast
## shot. No RNG: nearest by distance, ties by group order.

const ChainMod := preload("res://weapons/traits/chain_mod.gd")
const RANGE_T := 5.0


func steps() -> Array:
	return [{&"hops": 3, &"range": RANGE_T}, {&"hops": 4, &"range": RANGE_T}, {&"hops": 5, &"range": RANGE_T},
			{&"hops": 6, &"range": RANGE_T}]


func overflow_keys() -> Array:
	return [&"range"]


func describe(at_level: int) -> String:
	return "chain: a kill hops to the next enemy (%d hops)" % int(value_at(at_level, &"hops", 3))


func spawned(_weapon: Weapon, projectile: Node) -> void:
	if float(projectile.get(&"blast_radius")) > 0.0:
		return
	var mod := ChainMod.new()
	mod.hops_left = int(step_value(&"hops", 3))
	mod.range_px = float(step_value(&"range", RANGE_T)) * Tuning.TILE
	projectile.add_mod(mod)
