extends RuleEdit
## Big enemies (PLAN v8 1.4): Enemies x1.8 size, x0.7 speed, +1 HP.


func apply_rules(rules: WorldRules) -> void:
	rules.enemy_scale_mult *= 1.8
	rules.enemy_speed_mult *= 0.7
	rules.enemy_hp_add += 1.0
