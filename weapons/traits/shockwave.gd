extends WeaponTrait
## Nova's C on the deep curve (M50.4a, Auto depth design 3; rank 6 on Auto): each blast also
## sends a ring out to 4 tiles that hits each enemy it passes once, for half the damage
## (nova_pulse.gd, shockwave_ring.gd). No random stream.


func passive_ready(_weapon: Weapon, node: Node) -> void:
	node.shockwave = true


func describe(_at_level: int) -> String:
	return "a shockwave ring to 4 tiles"
