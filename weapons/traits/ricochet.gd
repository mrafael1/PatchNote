extends WeaponTrait
## Laser rank 3: the shot bounces once off a wall, and that bounce restores its pierce.
## M50.1a (deep curve): wall bounces 1 -> 2 -> 2 -> 3, pierce resets each.

const RicochetMod := preload("res://weapons/traits/ricochet_mod.gd")


func steps() -> Array:
	return [{&"bounces": 1}, {&"bounces": 2}, {&"bounces": 2}, {&"bounces": 3}]


func overflow_keys() -> Array:
	return [&"bounces"]


func describe(at_level: int) -> String:
	var n := int(value_at(at_level, &"bounces", 1))
	return "ricochet %d wall%s" % [n, "" if n == 1 else "s"]


func shot(_weapon: Weapon, _index: int, params: Dictionary) -> void:
	params[&"bounces_left"] = maxi(int(params[&"bounces_left"]), int(step_value(&"bounces", 1)))


func spawned(weapon: Weapon, projectile: Node) -> void:
	var mod := RicochetMod.new()
	mod.pierce = int(weapon.value(&"pierce"))
	projectile.add_mod(mod)
