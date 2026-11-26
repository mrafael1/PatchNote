extends WeaponTrait
## M50.4c2 (Auto depth design 5): the Supernova's signature, on nova's node (nova_pulse.gd).
## The shockwave ring reaches RING_TO tiles for RING_MULT x the blast's damage, and the shove
## pushes SHOVE_TILES (1.5 T) instead of ~1 T. The blast itself is the def's (2.5 T, 8 damage,
## every 2.0 s). No random stream.

const RING_TO := 6.0
const RING_MULT := 0.75
const SHOVE_TILES := 1.5


func passive_ready(_weapon: Weapon, node: Node) -> void:
	node.ring_to = RING_TO
	node.ring_mult = RING_MULT
	node.shove_impulse = node.SHOVE_IMPULSE * SHOVE_TILES


func describe(_at_level: int) -> String:
	return "a shockwave ring to 6 tiles"
