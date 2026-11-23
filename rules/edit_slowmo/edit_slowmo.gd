extends RuleEdit
## Slow motion (PLAN v8 1.4): Time x0.6.


func apply_rules(rules: WorldRules) -> void:
	rules.time_scale *= 0.6
