extends WeaponTrait
## Pistol rank 2: every 5th shot is heavy: damage x3, size x2 (visual), pierce 1. M50.1a (deep
## curve): every 5th -> 4th -> 3rd -> 2nd; overflow strengthens the heavy damage.

const EVERY := 5
const MULT := 3.0


func steps() -> Array:
	return [{&"every": 5, &"mult": 3.0}, {&"every": 4, &"mult": 3.0}, {&"every": 3, &"mult": 3.0},
			{&"every": 2, &"mult": 3.0}]


func overflow_keys() -> Array:
	return [&"mult"]


func describe(at_level: int) -> String:
	var every := int(value_at(at_level, &"every", EVERY))
	var text := "heavy every %s shot" % WeaponCurve.ordinal(every)
	if at_level > steps().size():
		text += " (x%.1f)" % float(value_at(at_level, &"mult", MULT))
	return text


func shot(weapon: Weapon, _index: int, params: Dictionary) -> void:
	# Loadout counts a shot after fire() returns, so this shot is number shots + 1.
	if (weapon.shots + 1) % int(step_value(&"every", EVERY)) != 0:
		return
	params[&"damage"] = float(params[&"damage"]) * float(step_value(&"mult", MULT))
	params[&"size"] = float(params[&"size"]) * 2.0
	params[&"pierce_left"] = maxi(int(params[&"pierce_left"]), 1)
