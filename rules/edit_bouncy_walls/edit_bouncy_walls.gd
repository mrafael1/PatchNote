extends RuleEdit
## Bouncy walls (PLAN v8 1.4): Bodies bounce off walls; shots bounce twice more.


func apply_rules(rules: WorldRules) -> void:
	rules.wall_bounce = true
	rules.projectile_max_bounces += 2
