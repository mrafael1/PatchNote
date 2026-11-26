extends WeaponTrait
## Launcher rank 6 (M50.3a, deep curve only): every 3rd shell also drops a mine where it left
## the muzzle (weapons/traits/mine.gd: arms after 0.5 s, blows on the first enemy within 0.5 T,
## the launcher's damage x `damage_mult`, fizzles after 12 s). Every 3rd / 3rd / 2nd / 2nd shot,
## 4 / 5 / 5 / 6 alive (the oldest goes); overflow strengthens the mine's damage. Only a shell
## that spawned counts (a shell refused at the player budget drops none and is not counted:
## Loadout counts a shot only when fire() spawned it).

const Mine := preload("res://weapons/traits/mine.gd")

var _laid_at := -1   ## the shot a mine was laid for (one per shot, whatever the pellets)


func steps() -> Array:
	return [{&"every": 3, &"max": 4, &"damage_mult": 1.0}, {&"every": 3, &"max": 5, &"damage_mult": 1.0},
			{&"every": 2, &"max": 5, &"damage_mult": 1.0}, {&"every": 2, &"max": 6, &"damage_mult": 1.0}]


func overflow_keys() -> Array:
	return [&"damage_mult"]


func describe(at_level: int) -> String:
	var text := "mine layer: every %s shot drops a mine (%d max)" % [
			WeaponCurve.ordinal(int(value_at(at_level, &"every", 3))), int(value_at(at_level, &"max", 4))]
	if at_level > steps().size():
		text += " (x%s)" % WeaponCurve.num(float(value_at(at_level, &"damage_mult", 1.0)))
	return text


func spawned(weapon: Weapon, projectile: Node) -> void:
	# Loadout counts a shot after fire() returns, so this shot is number shots + 1.
	var n := weapon.shots + 1
	if n == _laid_at or n % int(step_value(&"every", 3)) != 0 or not is_instance_valid(RunState.world):
		return
	_laid_at = n
	Mine.drop(projectile.get(&"origin"), float(weapon.value(&"damage")) * float(step_value(&"damage_mult", 1.0)),
			int(step_value(&"max", 4)), projectile.get(&"source_patch"))
