extends PatchTake
## Top-down take (PLAN v5 1.2).
## Shots bounce off walls, and arc when the world has gravity.

@export var extra_bounces := 3
@export var gravity_scale := 0.5


func apply_rules(rules: WorldRules) -> void:
	rules.projectile_max_bounces += extra_bounces
	rules.projectile_gravity_scale += gravity_scale
