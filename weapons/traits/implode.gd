extends WeaponTrait
## Launcher rank 3: just before the sticky shell blows, every enemy in its range is pulled
## in, then the blast.

const StickyMod := preload("res://weapons/traits/sticky_mod.gd")


func spawned(_weapon: Weapon, projectile: Node) -> void:
	for m in projectile.get_children():
		if m.get_script() == StickyMod:
			m.implode = true
