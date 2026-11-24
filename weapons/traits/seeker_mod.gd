extends ProjectileMod
## The seeker's steering (pistol rank 3).

const RANGE := 4.0 * Tuning.TILE
const TURN_DEG := 60.0   ## per second at most


func steer(p: Node2D, delta: float) -> void:
	var target := nearest(p.global_position)
	if target == null:
		return
	var v: Vector2 = p.velocity
	var want := (target.global_position - p.global_position).angle()
	var diff := wrapf(want - v.angle(), -PI, PI)
	var step := deg_to_rad(TURN_DEG) * delta
	p.velocity = v.rotated(clampf(diff, -step, step))


## The nearest live enemy within RANGE (a strictly nearer one wins: ties keep tree order).
static func nearest(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := RANGE * RANGE
	for e in RunState.get_tree().get_nodes_in_group(&"enemy"):
		var n := e as Node2D
		if n == null or n.is_queued_for_deletion():
			continue
		var d := from.distance_squared_to(n.global_position)
		if (best == null and d <= best_d) or (best != null and d < best_d):
			best_d = d
			best = n
	return best
