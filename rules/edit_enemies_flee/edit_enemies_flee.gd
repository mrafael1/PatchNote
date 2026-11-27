extends RuleEdit
## Enemies flee (PLAN v9 1.9, M51): walkers steer away from the player while it is live
## (EnemyWalker reads the rule); shooters and snipers still shoot. S11's part-3 breather.


func apply_rules(rules: WorldRules) -> void:
	rules.enemies_flee += 1
