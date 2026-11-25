extends WeaponTrait
## Laser rank 6 (M50.1a, deep curve only): every 4th -> 4th (1.25 s) -> 3rd -> 2nd shot also
## throws a beam across the screen along the aim for 1 s (OverchargeBeam: half the shot's
## damage every 0.25 s to each enemy on it). One beam at a time; never a projectile.

const OverchargeBeam := preload("res://weapons/traits/overcharge_beam.gd")


func steps() -> Array:
	return [{&"every": 4, &"life": 1.0}, {&"every": 4, &"life": 1.25}, {&"every": 3, &"life": 1.25},
			{&"every": 2, &"life": 1.25}]


func overflow_keys() -> Array:
	return [&"life"]


func describe(at_level: int) -> String:
	return "overcharge: every %s shot is a %s s beam" % [WeaponCurve.ordinal(int(value_at(at_level, &"every", 4))),
			WeaponCurve.num(float(value_at(at_level, &"life", 1.0)))]


func spawned(weapon: Weapon, projectile: Node) -> void:
	# Loadout counts a shot after fire() returns, so this shot is number shots + 1.
	if (weapon.shots + 1) % int(step_value(&"every", 4)) != 0 or not is_instance_valid(RunState.world):
		return
	var dir := (projectile.get(&"velocity") as Vector2).normalized()
	OverchargeBeam.fire(projectile.get(&"origin"), dir, float(projectile.get(&"damage")) * 0.5,
			float(step_value(&"life", 1.0)), projectile.get(&"source_patch"))
