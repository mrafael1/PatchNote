extends WeaponTrait
## Well rank 2 (its card says magnet): the fields pull gems to their centre too. The id is
## not `magnet`, a v6 mutation id.


func passive_ready(_weapon: Weapon, node: Node) -> void:
	node.gem_magnet = true
