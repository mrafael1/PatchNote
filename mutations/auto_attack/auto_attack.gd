extends Mutation
## The weapon fires by itself at the nearest visible enemy while fire is not held.
## Same weapon, same cooldown: holding fire takes manual aim back.


func apply_rules(rules: WorldRules) -> void:
	rules.auto_attack = true
