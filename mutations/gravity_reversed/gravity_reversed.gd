extends Mutation
## Flips whichever way gravity currently points. The camera does not rotate and
## left/right keep their meaning; only "down" changes.


func apply_rules(rules: WorldRules) -> void:
	rules.gravity_dir = -rules.gravity_dir
