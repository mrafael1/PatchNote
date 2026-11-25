extends WeaponTrait
## Shotgun rank 6 (M50.1a, deep curve only): a pellet that hits nothing leaves a caltrop where it
## ends (1 damage to the first enemy that touches it); it lasts 3 -> 3.5 -> 4 -> 5 s. Caltrops
## are a hazard group capped at Caltrop.CAP (the oldest goes), never projectiles.

const ShrapnelMod := preload("res://weapons/traits/shrapnel_mod.gd")


func steps() -> Array:
	return [{&"life": 3.0}, {&"life": 3.5}, {&"life": 4.0}, {&"life": 5.0}]


func overflow_keys() -> Array:
	return [&"life"]


func describe(at_level: int) -> String:
	return "shrapnel: missed pellets leave caltrops (%s s)" % WeaponCurve.num(float(value_at(at_level, &"life", 3.0)))


func spawned(_weapon: Weapon, projectile: Node) -> void:
	var mod := ShrapnelMod.new()
	mod.life = float(step_value(&"life", 3.0))
	projectile.add_mod(mod)
