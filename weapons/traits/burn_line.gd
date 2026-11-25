extends WeaponTrait
## Laser rank 2: the shot leaves a burning line along its path (1 s, 1 damage per 0.5 s
## to each enemy on it). M50.1a (deep curve): burns 1 -> 1.25 -> 1.5 -> 2 s; at most
## BurnLineZone.DEEP_CAP lines alive (the oldest goes), on the deep curve only.

const BurnLineMod := preload("res://weapons/traits/burn_line_mod.gd")
const BurnLineZone := preload("res://weapons/traits/burn_line_zone.gd")


func steps() -> Array:
	return [{&"life": BurnLineZone.LIFE}, {&"life": 1.25}, {&"life": 1.5}, {&"life": 2.0}]


func overflow_keys() -> Array:
	return [&"life"]


func describe(at_level: int) -> String:
	return "burning line %s s" % WeaponCurve.num(float(value_at(at_level, &"life", BurnLineZone.LIFE)))


func spawned(_weapon: Weapon, projectile: Node) -> void:
	var mod := BurnLineMod.new()
	mod.life = float(step_value(&"life", BurnLineZone.LIFE))
	mod.cap = BurnLineZone.DEEP_CAP if deep else 0
	projectile.add_mod(mod)
