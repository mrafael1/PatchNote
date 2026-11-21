extends PatchTake
## Top-down take (PLAN v5 1.2).
## The weapon fires by itself at the nearest visible enemy while fire is not held.
## Same weapon, same cooldown: holding fire takes manual aim back.


func apply_rules(rules: WorldRules) -> void:
	rules.auto_attack = true
