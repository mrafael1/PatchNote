extends "res://weapons/traits/burn_line.gd"
## Prism's burn line (M50.1b, Arsenal depth design 4): the laser's burning line, on the centre
## beam of the fan only, so a 5-beam shot leaves one line and the deep cap of 12 zones stays
## honest. shot() runs for each beam just before it spawns and spawned() right after, so the
## beam's index is known here (no projectile field, no random stream).

var _centre := false


func describe(at_level: int) -> String:
	return "centre beam burns %s s" % WeaponCurve.num(float(value_at(at_level, &"life", BurnLineZone.LIFE)))


func shot(weapon: Weapon, index: int, _params: Dictionary) -> void:
	_centre = index == floori(int(weapon.value(&"pellets")) / 2.0)


func spawned(weapon: Weapon, projectile: Node) -> void:
	if _centre:
		super.spawned(weapon, projectile)
