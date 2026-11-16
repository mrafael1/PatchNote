extends Mutation
## Turns the top-down arena into a platformer: gravity on, and with it one jump.


func apply_rules(rules: WorldRules) -> void:
	rules.gravity_enabled = true
	rules.jumps += 1
