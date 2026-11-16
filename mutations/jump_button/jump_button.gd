extends Mutation
## "Add a jump button": one more jump, and landing hurts whatever is underneath.
## Without gravity that jump is a hop over the ground plane; with gravity it is an
## extra (double) jump. The slam is the same code in both.

const LandingSlam := preload("res://mutations/jump_button/landing_slam.gd")

@export var slam_radius := 90.0
@export var slam_damage := 1.0
@export var slam_knockback := 380.0


func apply_rules(rules: WorldRules) -> void:
	rules.jumps += 1


func on_entity_spawned(entity: Node) -> void:
	if not entity.is_in_group(&"player"):
		return
	var slam := Component.attach(entity, LandingSlam, id)
	slam.set(&"radius", slam_radius)
	slam.set(&"damage", slam_damage)
	slam.set(&"knockback", slam_knockback)
