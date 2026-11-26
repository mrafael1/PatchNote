extends WeaponTrait
## Launcher rank 2: the shell sticks to what it hits (following an enemy) and blows 0.6 s
## later (game time) at 1.2x the radius; no blast on contact. M50.3a (deep curve): the radius
## multiplier grows 1.2 -> 1.3 -> 1.4 -> 1.5 (the fuse stays 0.6 s); overflow keeps growing it.

const StickyMod := preload("res://weapons/traits/sticky_mod.gd")


func steps() -> Array:
	return [{&"radius_mult": 1.2}, {&"radius_mult": 1.3}, {&"radius_mult": 1.4}, {&"radius_mult": 1.5}]


func overflow_keys() -> Array:
	return [&"radius_mult"]


func describe(at_level: int) -> String:
	return "sticky: shells stick, then blow bigger (x%s)" % WeaponCurve.num(
			float(value_at(at_level, &"radius_mult", StickyMod.RADIUS_MULT)))


func spawned(_weapon: Weapon, projectile: Node) -> void:
	var mod := StickyMod.new()
	mod.radius_mult = float(step_value(&"radius_mult", StickyMod.RADIUS_MULT))
	projectile.add_mod(mod)
