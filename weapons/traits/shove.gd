extends WeaponTrait
## Nova rank 2: after a blast, every enemy still alive within its radius is pushed ~1 T away.


func passive_ready(_weapon: Weapon, node: Node) -> void:
	node.shove = true
