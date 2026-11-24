extends WeaponTrait
## Orbit rank 2: a dash flares the shards out to twice their radius for 0.6 s.


func passive_ready(_weapon: Weapon, node: Node) -> void:
	node.flare = true
