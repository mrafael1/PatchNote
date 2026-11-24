extends WeaponTrait
## Shotgun rank 3: double damage when a pellet lands within 2 tiles of the muzzle. (The
## tighter cone is rank 3's spread_deg.)

const PointBlankMod := preload("res://weapons/traits/point_blank_mod.gd")


func spawned(_weapon: Weapon, projectile: Node) -> void:
	projectile.add_mod(PointBlankMod.new())
