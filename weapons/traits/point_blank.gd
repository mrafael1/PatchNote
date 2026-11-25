extends WeaponTrait
## Shotgun rank 3: double damage when a pellet lands within 2 tiles of the muzzle. (The
## tighter cone is rank 3's spread_deg; on the deep curve WeaponDef.mechanic_values.) M50.1a
## (deep curve): x2 within 2 T -> x2.25 / 2.25 T -> x2.5 / 2.5 T -> x3 / 2.5 T.

const PointBlankMod := preload("res://weapons/traits/point_blank_mod.gd")


func steps() -> Array:
	return [{&"mult": 2.0, &"range": 2.0}, {&"mult": 2.25, &"range": 2.25}, {&"mult": 2.5, &"range": 2.5},
			{&"mult": 3.0, &"range": 2.5}]


func overflow_keys() -> Array:
	return [&"mult"]


func describe(at_level: int) -> String:
	return "point blank x%s within %s T" % [WeaponCurve.num(float(value_at(at_level, &"mult", 2.0))),
			WeaponCurve.num(float(value_at(at_level, &"range", 2.0)))]


func spawned(_weapon: Weapon, projectile: Node) -> void:
	var mod := PointBlankMod.new()
	mod.range_px = float(step_value(&"range", 2.0)) * Tuning.TILE
	mod.mult = float(step_value(&"mult", 2.0))
	projectile.add_mod(mod)
