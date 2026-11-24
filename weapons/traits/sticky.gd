extends WeaponTrait
## Launcher rank 2: the shell sticks to what it hits (following an enemy) and blows 0.6 s
## later (game time) at 1.2x the radius; no blast on contact.

const StickyMod := preload("res://weapons/traits/sticky_mod.gd")


func spawned(_weapon: Weapon, projectile: Node) -> void:
	projectile.add_mod(StickyMod.new())
