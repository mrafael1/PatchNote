extends GutTest
## M0 smoke test: the project skeleton is wired up.


func test_autoloads_exist() -> void:
	for autoload_name: String in ["InputSetup", "Tuning", "EventBus", "RunState", "MutationDB"]:
		assert_not_null(get_tree().root.get_node_or_null(autoload_name), autoload_name + " autoload")


func test_every_action_has_a_binding() -> void:
	for action: StringName in InputSetup.ACTIONS:
		assert_true(InputMap.has_action(action), "action exists: %s" % action)
		if InputMap.has_action(action):
			assert_gt(InputMap.action_get_events(action).size(), 0, "action has events: %s" % action)


func test_jump_and_dash_do_not_share_a_key() -> void:
	var jump_keys: Array = []
	for e in InputMap.action_get_events(&"jump"):
		if e is InputEventKey:
			jump_keys.append(e.physical_keycode)
	for e in InputMap.action_get_events(&"dash"):
		if e is InputEventKey:
			assert_does_not_have(jump_keys, e.physical_keycode, "dash key is not a jump key")


func test_collision_layers_are_named() -> void:
	var expected := ["world", "player_body", "enemy_body", "player_hurtbox", "enemy_hurtbox"]
	for i in expected.size():
		assert_eq(ProjectSettings.get_setting("layer_names/2d_physics/layer_%d" % (i + 1)), expected[i])


func test_player_input_seam_classes_load() -> void:
	var human := HumanInput.new()
	var bot := BotInput.new()
	assert_true(human is PlayerInput)
	assert_true(bot is PlayerInput)
	human.free()
	bot.free()
