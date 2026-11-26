extends WeaponTrait
## Launcher rank 3: just before the sticky shell blows, every enemy in its range is pulled
## in, then the blast. M50.3a (deep curve): the pull grows 455 -> 606 -> 758 -> 910 (level 1
## is StickyMod.IMPLODE_PULL, the classic curve); overflow keeps growing it.

const StickyMod := preload("res://weapons/traits/sticky_mod.gd")


func steps() -> Array:
	return [{&"pull": 455.0}, {&"pull": 606.0}, {&"pull": 758.0}, {&"pull": 910.0}]


func overflow_keys() -> Array:
	return [&"pull"]


func describe(at_level: int) -> String:
	var text := "implode: the blast pulls enemies in"
	var p := float(value_at(at_level, &"pull", StickyMod.IMPLODE_PULL))
	if at_level > 1:
		text += " (pull x%s)" % WeaponCurve.num(p / StickyMod.IMPLODE_PULL)
	return text


func spawned(_weapon: Weapon, projectile: Node) -> void:
	for m in projectile.get_children():
		if m.get_script() == StickyMod:
			m.implode = true
			m.pull = float(step_value(&"pull", StickyMod.IMPLODE_PULL))
