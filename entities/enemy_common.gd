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


## Resize an enemy's collision shape and visual. The shape is duplicated first
## because scenes share one shape resource between instances.
static func apply_size(me: Node, mult: float) -> void:
	if is_equal_approx(mult, 1.0):
		return
	var cs := me.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs and cs.shape is RectangleShape2D:
		var shape := cs.shape.duplicate() as RectangleShape2D
		shape.size *= mult
		cs.shape = shape
	var visual := me.get_node_or_null("Visual") as RectVisual
	if visual:
		visual.size *= mult


## The contact telegraph (PLAN v5 2.2): 0 while the walker is more than
## Tuning.contact_warn_range tiles beyond its contact reach, then from a faint rim
## (0.05) up to 1 at contact. gap = centre distance minus the contact reach.
static func contact_warning(gap: float) -> float:
	var warn := Tuning.contact_warn_range * Tuning.TILE
	if gap >= warn:
		return 0.0
	return clampf(1.0 - gap / warn, 0.05, 1.0)


static func ray_hits_world(me: Node2D, from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, Tuning.LAYER_WORLD)
	return not me.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


static func find_player(me: Node) -> Node2D:
	return me.get_tree().get_first_node_in_group(&"player") as Node2D
