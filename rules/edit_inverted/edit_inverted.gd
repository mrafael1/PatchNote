extends RuleEdit
## Inverted controls (PLAN v8 1.4): Movement input turned 180 degrees.

const HINT := preload("res://rules/edit_inverted/inverted_hint.gd")


func apply_rules(rules: WorldRules) -> void:
	rules.input_rotation_deg += 180.0


## G13b (M43.2): arrows around the player for the first seconds, each input's new way.
## Campaign only (no session: none).
func landed_hint(player: Node2D) -> Node2D:
	if RunState.session == null or not is_instance_valid(player):
		return null
	var hint: Node2D = HINT.new()
	hint.set(&"gentle", SaveGame.reduce_flashing())
	return hint
