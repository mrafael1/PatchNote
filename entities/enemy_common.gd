class_name EnemyCommon
extends RefCounted
## Helpers shared by the enemy scripts.


## Soft push away from nearby enemies. Enemy bodies do not collide with each other.
static func separation(me: Node2D) -> Vector2:
	var push := Vector2.ZERO
	var radius := Tuning.enemy_separation_radius
	for other in me.get_tree().get_nodes_in_group(&"enemy"):
		if other == me:
			continue
		var away: Vector2 = me.global_position - (other as Node2D).global_position
		var dist := away.length()
		if dist > 0.01 and dist < radius:
			push += away / dist * (1.0 - dist / radius)
	return push


static func ray_hits_world(me: Node2D, from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, Tuning.LAYER_WORLD)
	return not me.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


static func find_player(me: Node) -> Node2D:
	return me.get_tree().get_first_node_in_group(&"player") as Node2D
