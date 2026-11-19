extends Mutation
## Big patch B2 (PLAN v3 section 3): the world only runs when the player acts. The
## TurnClock reads the rule; this patch only sets it.


func apply_rules(rules: WorldRules) -> void:
	rules.turn_based = true
	rules.turn_duration = 0.25   # assigned: only the big patch in the slot owns it
