extends RuleEdit
## Tiny enemies (PLAN v8 1.4): Enemies x0.5 size, x1.4 speed, 1 HP.


func apply_rules(rules: WorldRules) -> void:
	rules.enemy_scale_mult *= 0.5
	rules.enemy_speed_mult *= 1.4
	rules.enemy_hp_one = true
