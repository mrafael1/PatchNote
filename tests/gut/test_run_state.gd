extends GutTest
## The patch stack contract (PLAN 2.5): apply, revert, cascade, reset, and the
## replay-equivalence invariant.

const Fx := preload("res://tests/gut/fixtures.gd")

var muts: Array[Mutation]
var by_id := {}
var world: Node2D


func before_each() -> void:
	RunState.reset(1)
	world = Node2D.new()
	world.name = "FxWorld"
	add_child_autofree(world)
	RunState.world = world
	world.add_child(Fx.make_entity(&"player", "P"))
	world.add_child(Fx.make_entity(&"enemy", "E1"))
	world.add_child(Fx.make_entity(&"enemy", "E2"))
	muts = Fx.make_all()
	by_id.clear()
	for m in muts:
		by_id[m.id] = m


func after_each() -> void:
	RunState.reset(0)
	RunState.world = null


func _snap() -> String:
	return JSON.stringify(RunState.snapshot(), "", true)


func _mutation_connections() -> int:
	var n := 0
	for sig: Dictionary in EventBus.get_signal_list():
		for conn: Dictionary in EventBus.get_signal_connection_list(sig.name):
			if (conn.callable as Callable).get_object() is Mutation:
				n += 1
	return n


func _connection_owner_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for sig: Dictionary in EventBus.get_signal_list():
		for conn: Dictionary in EventBus.get_signal_connection_list(sig.name):
			var obj := (conn.callable as Callable).get_object()
			if obj is Mutation:
				out.append((obj as Mutation).id)
	return out


func _patch_components() -> Array[Component]:
	var out: Array[Component] = []
	for e in RunState.live_entities():
		for c in e.get_children():
			if c is Component and c.source_patch != &"":
				out.append(c)
	return out


func test_apply_changes_rules_and_revert_restores_base() -> void:
	var base := JSON.stringify(RunState.rules.to_dict())
	assert_true(RunState.apply(by_id[&"fx_rules"]))
	assert_eq(RunState.rules.spawn_rate_mult, 2.0)
	assert_eq(RunState.rules.max_enemies, 30)
	RunState.revert(by_id[&"fx_rules"])
	assert_eq(JSON.stringify(RunState.rules.to_dict()), base)


func test_base_rules_resource_is_never_modified() -> void:
	var before := JSON.stringify(RunState.base_rules.to_dict())
	for m in muts:
		RunState.apply(m, true)
	assert_eq(JSON.stringify(RunState.base_rules.to_dict()), before)


func test_cannot_apply_twice() -> void:
	assert_true(RunState.apply(by_id[&"fx_rules"]))
	assert_false(RunState.apply(by_id[&"fx_rules"]))
	assert_eq(RunState.stack.size(), 1)


func test_requires_blocks_until_met() -> void:
	assert_false(RunState.can_apply(by_id[&"fx_dependent"]))
	assert_false(RunState.apply(by_id[&"fx_dependent"]))
	RunState.apply(by_id[&"fx_rules"])
	assert_true(RunState.can_apply(by_id[&"fx_dependent"]))


func test_conflicts_block_in_both_directions() -> void:
	RunState.apply(by_id[&"fx_event"])
	assert_false(RunState.can_apply(by_id[&"fx_conflict"]), "new patch names a stacked one")
	RunState.reset(1)
	RunState.apply(by_id[&"fx_conflict"])
	assert_false(RunState.can_apply(by_id[&"fx_event"]), "stacked patch names the new one")


func test_component_patch_attaches_to_live_and_future_entities() -> void:
	RunState.apply(by_id[&"fx_component"])
	assert_eq(_patch_components().size(), 2, "both live enemies, not the player")
	world.add_child(Fx.make_entity(&"enemy", "E3"))
	assert_eq(_patch_components().size(), 3, "entity spawned after the patch")
	RunState.revert(by_id[&"fx_component"])
	assert_eq(_patch_components().size(), 0, "stripped immediately, not at frame end")


func test_attach_is_idempotent() -> void:
	var m: Mutation = by_id[&"fx_component"]
	RunState.apply(m)
	for e in RunState.live_entities():
		m.on_entity_spawned(e)
	assert_eq(_patch_components().size(), 2)


func test_listeners_are_removed_on_revert() -> void:
	RunState.apply(by_id[&"fx_event"])
	RunState.apply(by_id[&"fx_all"])
	assert_eq(_mutation_connections(), 3)
	RunState.revert(by_id[&"fx_event"])
	assert_eq(_mutation_connections(), 1)
	RunState.revert(by_id[&"fx_all"])
	assert_eq(_mutation_connections(), 0)


func test_patch_state_is_cleared_on_revert() -> void:
	var m: Mutation = by_id[&"fx_event"]
	RunState.apply(m)
	EventBus.enemy_killed.emit(world.get_node("E1"), DamageInfo.make(1, &"contact", &"player"))
	assert_eq(m.state().get("kills"), 1)
	RunState.revert(m)
	assert_false(RunState.patch_state.has(m.id))


func test_revert_cascades_to_dependents() -> void:
	RunState.apply(by_id[&"fx_rules"])
	RunState.apply(by_id[&"fx_event"])
	RunState.apply(by_id[&"fx_dependent"])
	var build := RunState.build_number
	var removed := RunState.revert(by_id[&"fx_rules"])
	assert_eq(removed.size(), 2)
	assert_eq(removed[0].id, &"fx_dependent", "dependents go first")
	assert_eq(removed[1].id, &"fx_rules")
	assert_eq(RunState.stack.size(), 1)
	assert_eq(RunState.build_number, build + 1, "one revert action is one build")
	assert_eq(RunState.rules.gravity_dir, Vector2(0, 1))


func test_version_never_goes_backwards() -> void:
	assert_eq(RunState.version_label(), "v0.1")
	RunState.apply(by_id[&"fx_rules"])
	assert_eq(RunState.version_label(), "v0.2")
	RunState.revert(by_id[&"fx_rules"])
	assert_eq(RunState.version_label(), "v0.3")


func test_reset_returns_to_a_clean_run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for m in muts:
		if rng.randf() < 0.8:
			RunState.apply(m, true)
	RunState.set_pause(&"prompt", true)
	RunState.invincible = true
	RunState.reset(42)
	assert_eq(RunState.stack.size(), 0)
	assert_eq(JSON.stringify(RunState.rules.to_dict()), JSON.stringify(RunState.base_rules.to_dict()))
	assert_eq(_mutation_connections(), 0)
	assert_eq(_patch_components().size(), 0)
	assert_eq(Engine.time_scale, 1.0)
	assert_false(get_tree().paused)
	assert_false(RunState.invincible)
	assert_eq(RunState.build_number, 1)
	assert_eq(RunState.run_seed, 42)
	assert_true(RunState.patch_state.is_empty())


func test_same_seed_gives_same_random_streams() -> void:
	RunState.reset(99)
	var a := [RunState.director_rng.randi(), RunState.gameplay_rng.randi()]
	RunState.reset(99)
	var b := [RunState.director_rng.randi(), RunState.gameplay_rng.randi()]
	assert_eq(a, b)
	assert_ne(a[0], a[1], "director and gameplay streams differ")


func test_pause_reasons_combine() -> void:
	RunState.set_pause(&"prompt", true)
	RunState.set_pause(&"transition", true)
	RunState.set_pause(&"prompt", false)
	assert_true(get_tree().paused, "still paused for the transition")
	RunState.set_pause(&"transition", false)
	assert_false(get_tree().paused)


## The invariant: whatever legal sequence of apply / revert / reset got us to stack S,
## the derived state equals a clean reset followed by applying S in order.
func test_replay_equivalence_over_random_sequences() -> void:
	var rng := RandomNumberGenerator.new()
	var sequences := 300
	var steps_total := 0
	for s in sequences:
		rng.seed = s
		RunState.reset(s)
		for step in rng.randi_range(5, 30):
			var ops: Array = []
			for m in muts:
				if RunState.can_apply(m):
					ops.append([true, m])
			for m in RunState.stack:
				ops.append([false, m])
			var op: Array = ops[rng.randi_range(0, ops.size() - 1)]
			if op[0]:
				RunState.apply(op[1])
			else:
				RunState.revert(op[1])
			if rng.randf() < 0.03:
				RunState.reset(s)
			steps_total += 1
			for c in _patch_components():
				if not RunState.has_patch(c.source_patch):
					fail_test("seed %d: component from %s outlived its patch" % [s, c.source_patch])
					return
			# Checked directly, not only by replay: a leak that also survives reset()
			# would look identical on both sides of the comparison below.
			for owner_id in _connection_owner_ids():
				if not RunState.has_patch(owner_id):
					fail_test("seed %d: listener from %s outlived its patch" % [s, owner_id])
					return
		var final_stack: Array[Mutation] = RunState.stack.duplicate()
		var reached := _snap()
		RunState.reset(s)
		for m in final_stack:
			RunState.apply(m)
		var replayed := _snap()
		if reached != replayed:
			fail_test("seed %d diverged.\nreached:  %s\nreplayed: %s" % [s, reached, replayed])
			return
	pass_test("%d sequences, %d operations" % [sequences, steps_total])
