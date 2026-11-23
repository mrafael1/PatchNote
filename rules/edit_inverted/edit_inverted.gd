extends RuleEdit
## Inverted controls (PLAN v8 1.4): Movement input turned 180 degrees.


func apply_rules(rules: WorldRules) -> void:
	rules.input_rotation_deg += 180.0
