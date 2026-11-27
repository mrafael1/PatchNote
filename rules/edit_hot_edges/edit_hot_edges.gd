extends RuleEdit
## Hot edges (PLAN v9 1.9, M50.3c): the arena's outer tiles hurt while you stand in them
## (HotEdges reads the rule; the band's width is Tuning.hot_edge_tiles).


func apply_rules(rules: WorldRules) -> void:
	rules.hot_edge_tiles += Tuning.hot_edge_tiles
