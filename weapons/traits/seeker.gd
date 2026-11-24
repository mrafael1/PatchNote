extends WeaponTrait
## Pistol rank 3: the shot turns toward the nearest enemy within 4 tiles, at most
## 60 degrees a second (re-picked each tick; ties: distance, then tree order).

const SeekerMod := preload("res://weapons/traits/seeker_mod.gd")


func spawned(_weapon: Weapon, projectile: Node) -> void:
	projectile.add_mod(SeekerMod.new())
