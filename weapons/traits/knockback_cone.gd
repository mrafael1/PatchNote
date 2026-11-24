extends WeaponTrait
## Shotgun rank 2: each pellet pushes an enemy back about half a tile.

const KNOCKBACK := 420.0   ## the impulse that moves a chaser ~0.5 tile (test_weapons)


func shot(_weapon: Weapon, _index: int, params: Dictionary) -> void:
	params[&"knockback"] = KNOCKBACK
