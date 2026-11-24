class_name AutoFire
extends RefCounted
# path:auto
## Auto's targeting (PLAN v9 1.5): every held weapon fires on its own at the nearest visible
## enemy within 12 T; a weapon with a blast (the launcher) at the densest visible group.
## The same reading as the player's auto_attack target (player._auto_target, left untouched
## for Stage 1 and the legacy loop: D9). No RNG.


static func target_for(host: Node2D, weapon: Weapon) -> Node2D:
	if float(weapon.value(&"blast_radius")) > 0.0:
		return densest(host, Tuning.auto_attack_range, float(weapon.value(&"blast_radius")) * Tuning.TILE)
	return nearest(host, Tuning.auto_attack_range)


## The nearest enemy within `reach` with a clear line from the host.
static func nearest(host: Node2D, reach: float) -> Node2D:
	var best: Node2D = null
	var best_d := reach * reach
	for n in visible(host, reach):
		var d := host.global_position.distance_squared_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


## The visible enemy with the most enemies within `radius` of it (itself included); ties go
## to the nearest.
static func densest(host: Node2D, reach: float, radius: float) -> Node2D:
	var seen := visible(host, reach)
	var all := host.get_tree().get_nodes_in_group(&"enemy")
	var best: Node2D = null
	var best_n := 0
	var best_d := INF
	for n in seen:
		var around := 0
		for e in all:
			var m := e as Node2D
			if m != null and not m.is_queued_for_deletion() \
					and m.global_position.distance_squared_to(n.global_position) <= radius * radius:
				around += 1
		var d := host.global_position.distance_squared_to(n.global_position)
		if around > best_n or (around == best_n and d < best_d):
			best = n
			best_n = around
			best_d = d
	return best


## Enemies within `reach` of the host with no wall between.
static func visible(host: Node2D, reach: float) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for e in host.get_tree().get_nodes_in_group(&"enemy"):
		var n := e as Node2D
		if n == null or n.is_queued_for_deletion():
			continue
		if host.global_position.distance_squared_to(n.global_position) >= reach * reach:
			continue
		if not EnemyCommon.ray_hits_world(host, host.global_position, n.global_position):
			out.append(n)
	return out
