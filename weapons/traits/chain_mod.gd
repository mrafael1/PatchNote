extends ProjectileMod
## Chain (pistol rank 6, M50.1a): when the shot kills, it turns toward the nearest other live
## enemy within range_px (ties: group order) and flies on, hops_left times. A 2-frame arc
## (ChainArc) shows the hop. No spawn: the same projectile, so the player budget never moves.

const ChainArc := preload("res://weapons/traits/chain_arc.gd")

var hops_left := 3
var range_px := 5.0 * Tuning.TILE
var hops := 0   ## tests


func after_hit(p: Node2D, target: Node, killed: bool) -> bool:
	if not killed or hops_left <= 0 or float(p.blast_radius) > 0.0:
		return false
	var next := nearest(p.global_position, target, range_px)
	if next == null:
		return false
	hops_left -= 1
	hops += 1
	var speed: float = (p.velocity as Vector2).length()
	p.velocity = (next.global_position - p.global_position).normalized() * speed
	if is_instance_valid(RunState.world):
		var arc := ChainArc.new()
		arc.from = p.global_position
		arc.to = next.global_position
		RunState.world.add_child.call_deferred(arc)
	return true


## The nearest live enemy within `reach` of `from`, other than `skip` (a strictly nearer one
## wins: ties keep group order).
static func nearest(from: Vector2, skip: Node, reach: float) -> Node2D:
	var best: Node2D = null
	var best_d := reach * reach
	for e in RunState.get_tree().get_nodes_in_group(&"enemy"):
		var n := e as Node2D
		if n == null or n == skip or n.is_queued_for_deletion():
			continue
		var h := Component.find(n, Health) as Health
		if h != null and h.dead:
			continue
		var d := from.distance_squared_to(n.global_position)
		if (best == null and d <= best_d) or (best != null and d < best_d):
			best_d = d
			best = n
	return best
