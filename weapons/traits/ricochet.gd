extends WeaponTrait
## Laser rank 3: the shot bounces once off a wall, and that bounce restores its pierce.

const RicochetMod := preload("res://weapons/traits/ricochet_mod.gd")


func shot(_weapon: Weapon, _index: int, params: Dictionary) -> void:
	params[&"bounces_left"] = maxi(int(params[&"bounces_left"]), 1)


func spawned(weapon: Weapon, projectile: Node) -> void:
	var mod := RicochetMod.new()
	mod.pierce = int(weapon.value(&"pierce"))
	projectile.add_mod(mod)
