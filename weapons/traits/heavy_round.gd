extends WeaponTrait
## Pistol rank 2: every 5th shot is heavy: damage x3, size x2 (visual), pierce 1.

const EVERY := 5


func shot(weapon: Weapon, _index: int, params: Dictionary) -> void:
	# Loadout counts a shot after fire() returns, so this shot is number shots + 1.
	if (weapon.shots + 1) % EVERY != 0:
		return
	params[&"damage"] = float(params[&"damage"]) * 3.0
	params[&"size"] = float(params[&"size"]) * 2.0
	params[&"pierce_left"] = maxi(int(params[&"pierce_left"]), 1)
