extends WeaponTrait
## Well rank 3: the fields bite, 1 damage a second to each enemy inside.


func passive_ready(_weapon: Weapon, node: Node) -> void:
	node.teeth = true
