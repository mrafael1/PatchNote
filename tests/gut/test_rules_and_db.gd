extends GutTest
## WorldRules canary and the mutation registry.


func before_each() -> void:
	RunState.reset(1)


func test_every_rule_field_is_exported_and_survives_duplicate() -> void:
	var rules := WorldRules.new()
	var seen := 0
	for p: Dictionary in rules.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			seen += 1
			assert_true(p.usage & PROPERTY_USAGE_STORAGE != 0, "%s must be @export" % p.name)
			assert_true(p.type in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_VECTOR2, TYPE_STRING_NAME],
					"%s must be a value type" % p.name)
	assert_gt(seen, 8)
	rules.gravity_enabled = true
	rules.gravity_dir = Vector2(0, -1)
	rules.max_enemies = 77
	rules.enemy_hp_mult = 0.25
	rules.jumps = 2
	var copy := rules.duplicate() as WorldRules
	assert_eq(JSON.stringify(copy.to_dict()), JSON.stringify(rules.to_dict()))


func test_recompute_is_deterministic() -> void:
	var horde := MutationDB.get_mutation(&"horde_mode")
	RunState.apply(horde)
	var first := JSON.stringify(RunState.rules.to_dict())
	RunState.recompute()
	RunState.recompute()
	assert_eq(JSON.stringify(RunState.rules.to_dict()), first)


func test_registry_loads_and_sorts_mutations() -> void:
	assert_gt(MutationDB.all.size(), 0, "found mutations under res://mutations/")
	var previous := ""
	for m in MutationDB.all:
		assert_ne(m.id, &"")
		assert_ne(m.title, "", "%s has a card title" % m.id)
		assert_ne(m.description, "", "%s has a description" % m.id)
		assert_ne(m.line_proposal, "", "%s has a proposal line" % m.id)
		assert_ne(m.line_applied, "", "%s has an applied line" % m.id)
		assert_true(String(m.id) > previous, "sorted by id")
		previous = String(m.id)
		assert_eq(MutationDB.get_mutation(m.id), m)
		for ref in m.requires + m.conflicts:
			assert_not_null(MutationDB.get_mutation(ref), "%s references %s" % [m.id, ref])


func test_horde_mode_rules() -> void:
	var horde := MutationDB.get_mutation(&"horde_mode")
	assert_not_null(horde)
	RunState.apply(horde)
	assert_eq(RunState.rules.max_enemies, 75)
	assert_almost_eq(RunState.rules.spawn_rate_mult, 3.0, 0.0001)
	assert_almost_eq(RunState.rules.camera_zoom, 0.75, 0.0001)
	assert_almost_eq(RunState.rules.enemy_hp_mult, 0.6, 0.0001)
