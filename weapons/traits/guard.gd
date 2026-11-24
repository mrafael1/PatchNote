extends WeaponTrait
## Orbit rank 3: a shard that touches an enemy shot eats it; that shard is gone 1 s.


func passive_ready(_weapon: Weapon, node: Node) -> void:
	node.guard = true
