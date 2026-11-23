extends RuleEdit
## Faster enemies (PLAN v8 1.5): what wrong_variable means to do. Its warning is the one
## the event poses before gravity lands instead; at the end the event applies it itself.


func apply_rules(rules: WorldRules) -> void:
	rules.enemy_speed_mult *= 1.15
