extends WeaponTrait
## Laser rank 2: the shot leaves a burning line along its path (1 s, 1 damage per 0.5 s
## to each enemy on it).

const BurnLineMod := preload("res://weapons/traits/burn_line_mod.gd")


func spawned(_weapon: Weapon, projectile: Node) -> void:
	projectile.add_mod(BurnLineMod.new())
