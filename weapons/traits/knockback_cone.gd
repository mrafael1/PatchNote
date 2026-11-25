extends WeaponTrait
## Shotgun rank 2: each pellet pushes an enemy back about half a tile. M50.1a (deep curve):
## push x1 -> 1.3 -> 1.6 -> 1.8 of KNOCKBACK.

const KNOCKBACK := 420.0   ## the impulse that moves a chaser ~0.5 tile (test_weapons)


func steps() -> Array:
	return [{&"knockback": KNOCKBACK}, {&"knockback": KNOCKBACK * 1.3}, {&"knockback": KNOCKBACK * 1.6},
			{&"knockback": KNOCKBACK * 1.8}]


func overflow_keys() -> Array:
	return [&"knockback"]


func describe(at_level: int) -> String:
	if at_level <= 1:
		return "knockback cone: pellets shove enemies back"
	return "knockback x%s" % WeaponCurve.num(float(value_at(at_level, &"knockback", KNOCKBACK)) / KNOCKBACK)


func shot(_weapon: Weapon, _index: int, params: Dictionary) -> void:
	params[&"knockback"] = float(step_value(&"knockback", KNOCKBACK))
