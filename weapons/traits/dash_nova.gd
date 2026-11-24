extends WeaponTrait
## Nova rank 3: a dash sets the nova off now; the dash trigger then waits 3 s.


func passive_ready(_weapon: Weapon, node: Node) -> void:
	node.dash_nova = true
