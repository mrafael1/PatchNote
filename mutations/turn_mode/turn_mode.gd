extends Mutation
## Big patch B2 (PLAN v3 section 3): the world only runs when the player acts. The
## TurnClock reads the rule; this patch only sets it.

@export var turn_duration := 0.25   ## game seconds the world runs per player action


func apply_rules(rules: WorldRules) -> void:
	rules.turn_based = true
	rules.turn_duration = turn_duration   # assigned: only the big patch in the slot owns it
