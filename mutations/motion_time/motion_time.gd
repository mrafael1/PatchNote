extends Mutation
## Big patch B1 (PLAN v3 section 2): time moves when you move. RunState turns the
## rule into a time scale every tick; this patch only sets the rules.


func apply_rules(rules: WorldRules) -> void:
	rules.time_follows_motion = true
	rules.idle_time_scale *= 0.08
