extends RuleEdit
## Gravity up (PLAN v8 1.4): Gravity pulls up; one jump.


## One of the three gravity edits (M41's wrong_variable event): the only rule edit
## allowed to assign gravity_dir, since the three conflict pairwise.
func apply_rules(rules: WorldRules) -> void:
	rules.gravity_enabled = true
	rules.gravity_dir = Vector2.UP
	rules.jumps += 1   # never stuck: one jump off whatever it pins you to
