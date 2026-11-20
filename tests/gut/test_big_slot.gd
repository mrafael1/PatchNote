extends GutTest
## The big slot (PLAN v3 1.2): swap, revert guard, cascade, exclusivity, time
## ownership, and the replay-equivalence invariant extended with swaps.

const Fx := preload("res://tests/gut/fixtures.gd")

var smalls: Array[Mutation]
var big_a: Mutation
var big_b: Mutation
var under_a: Mutation
var against_b: Mutation
var on_against_b: Mutation
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
	smalls = Fx.make_all()
	var bigs := Fx.make_bigs()
	big_a = bigs[0]
	big_b = bigs[1]
	under_a = bigs[2]
	against_b = bigs[3]
	on_against_b = bigs[4]
	smalls.append_array([under_a, against_b, on_against_b])


func after_each() -> void:
	RunState.reset(0)
	RunState.world = null


func _snap() -> String:
	return JSON.stringify(RunState.snapshot(), "", true)


func _components_from(id: StringName) -> int:
	var n := 0
	for e in RunState.live_entities():
		for c in e.get_children():
			if c is Component and c.source_patch == id:
				n += 1
	return n


func _connections_from(id: StringName) -> int:
	var n := 0
	for sig: Dictionary in EventBus.get_signal_list():
		for conn: Dictionary in EventBus.get_signal_connection_list(sig.name):
			var obj := (conn.callable as Callable).get_object()
			if obj is Mutation and (obj as Mutation).id == id:
				n += 1
	return n


func _by_id(id: StringName) -> Mutation:
	for m in smalls:
		if m.id == id:
			return m
	return null


# --- Slot basics -------------------------------------------------------------

func test_swap_fills_the_slot_and_applies_everything() -> void:
	var build := RunState.build_number
	var dropped := RunState.swap_big(big_a)
	assert_eq(dropped.size(), 0)
	assert_eq(RunState.big, big_a)
	assert_true(RunState.has_patch(&"fx_big_a"))
	assert_false(RunState.stack.has(big_a), "a big patch never enters the stack")
	assert_eq(RunState.rules.turn_duration, 0.5)
	assert_eq(_components_from(&"fx_big_a"), 3, "player and both enemies")
	assert_eq(_connections_from(&"fx_big_a"), 1)
	assert_eq(RunState.build_number, build + 1)
	assert_eq(RunState.run_log[-1].event, &"big_swap")


func test_big_rules_come_before_small_rules() -> void:
	RunState.swap_big(big_a)
	RunState.apply(under_a)
	# Big assigns 0.5, then the small patch doubles it. The other order would give 0.5.
	assert_eq(RunState.rules.turn_duration, 1.0)


func test_new_entities_get_the_big_patch() -> void:
	RunState.swap_big(big_a)
	world.add_child(Fx.make_entity(&"enemy", "E3"))
	assert_eq(_components_from(&"fx_big_a"), 4)


func test_swap_replaces_the_old_big_patch_completely() -> void:
	RunState.swap_big(big_a)
	RunState.swap_big(big_b)
	assert_eq(RunState.big, big_b)
	assert_false(RunState.has_patch(&"fx_big_a"))
	assert_eq(_components_from(&"fx_big_a"), 0)
	assert_eq(_connections_from(&"fx_big_a"), 0)
	assert_false(RunState.patch_state.has(&"fx_big_a"))
	assert_eq(_components_from(&"fx_big_b"), 1, "player only")
	assert_eq(RunState.rules.turn_duration, 0.1)
	assert_true(RunState.rules.time_follows_motion)
	assert_eq(RunState.rules.camera_zoom, RunState.base_rules.camera_zoom, "A's zoom is gone")


func test_swapping_in_the_same_patch_changes_nothing() -> void:
	RunState.swap_big(big_a)
	var before := _snap()
	var build := RunState.build_number
	assert_eq(RunState.swap_big(big_a).size(), 0)
	assert_eq(_snap(), before)
	assert_eq(RunState.build_number, build)


func test_swap_refuses_null_and_small_patches() -> void:
	var before := _snap()
	RunState.swap_big(null)
	RunState.swap_big(smalls[0])
	assert_null(RunState.big)
	assert_eq(_snap(), before)


func test_reset_empties_the_slot() -> void:
	RunState.swap_big(big_a)
	RunState.reset(2)
	assert_null(RunState.big)
	assert_eq(_components_from(&"fx_big_a"), 0)
	assert_eq(_connections_from(&"fx_big_a"), 0)
	assert_eq(RunState.rules.to_dict(), RunState.base_rules.to_dict())


# --- Revert guard and exclusivity ------------------------------------------

func test_a_big_patch_cannot_be_reverted() -> void:
	RunState.swap_big(big_a)
	var before := _snap()
	var build := RunState.build_number
	assert_eq(RunState.revert(big_a).size(), 0)
	assert_eq(RunState.big, big_a)
	assert_eq(_snap(), before)
	assert_eq(RunState.build_number, build)


func test_a_big_patch_never_goes_through_apply() -> void:
	assert_false(RunState.can_apply(big_a))
	assert_false(RunState.apply(big_a))
	assert_false(RunState.apply(big_a, true), "not even forced")
	assert_null(RunState.big)
	assert_eq(RunState.stack.size(), 0)


func test_the_db_rejects_a_big_patch_with_requires_or_conflicts() -> void:
	assert_eq(MutationDB.problems(big_a).size(), 0)
	var bad := Fx.make_big(Fx.FxBigA, &"fx_bad_big")
	bad.requires.assign([&"fx_big_b"])
	assert_gt(MutationDB.problems(bad).size(), 0)
	var bad2 := Fx.make_big(Fx.FxBigA, &"fx_bad_big2")
	bad2.conflicts.assign([&"fx_big_b"])
	assert_gt(MutationDB.problems(bad2).size(), 0)


func test_real_mutations_pass_validation() -> void:
	for m in MutationDB.all:
		assert_eq(MutationDB.problems(m), [] as Array[String], String(m.id))


# --- Cascade -----------------------------------------------------------------

func test_a_small_patch_can_require_a_big_patch() -> void:
	assert_false(RunState.can_apply(under_a))
	RunState.swap_big(big_a)
	assert_true(RunState.can_apply(under_a))


func test_swapping_out_drops_dependents_without_a_rollback() -> void:
	RunState.swap_big(big_a)
	RunState.apply(under_a)
	RunState.apply(_by_id(&"fx_rules"))
	var dropped := RunState.swap_big(big_b)
	assert_eq(dropped, [under_a] as Array[Mutation])
	assert_false(RunState.has_patch(&"fx_under_a"))
	assert_true(RunState.has_patch(&"fx_rules"), "unrelated small patches stay")
	assert_eq(_connections_from(&"fx_under_a"), 0)
	var entry: Dictionary = RunState.run_log[-1]
	assert_eq(entry.event, &"big_swap")
	assert_eq(entry.dropped, ["fx_under_a"])
	for e in RunState.run_log:
		assert_ne(e.event, &"revert", "a drop is not a rollback")


func test_a_small_patch_that_conflicts_with_the_slotted_big_cannot_be_applied() -> void:
	assert_true(RunState.can_apply(against_b))
	RunState.swap_big(big_b)
	assert_false(RunState.can_apply(against_b), "the small patch lists the big one")
	assert_false(RunState.apply(against_b))
	RunState.swap_big(big_a)
	assert_true(RunState.can_apply(against_b))
	# The other direction: a big patch that lists the small one.
	var picky := Fx.make_big(Fx.FxBigA, &"fx_picky_big")
	picky.conflicts.assign([&"fx_rules"])
	RunState.swap_big(picky)
	assert_false(RunState.can_apply(_by_id(&"fx_rules")))


func test_swapping_in_drops_conflicting_patches_and_their_dependents() -> void:
	RunState.swap_big(big_a)
	RunState.apply(under_a)
	RunState.apply(against_b)
	RunState.apply(_by_id(&"fx_rules"))
	RunState.apply(on_against_b)
	watch_signals(EventBus)
	var build := RunState.build_number
	var dropped := RunState.swap_big(big_b)
	assert_eq(dropped, [under_a, on_against_b, against_b] as Array[Mutation], "dependents first")
	assert_eq(RunState.stack, [_by_id(&"fx_rules")] as Array[Mutation], "unrelated small patches stay")
	assert_eq(RunState.build_number, build + 1, "one build")
	assert_eq(_components_from(&"fx_against_b"), 0)
	assert_eq(_connections_from(&"fx_on_against_b"), 0)
	assert_eq(RunState.run_log[-1].dropped, ["fx_under_a", "fx_on_against_b", "fx_against_b"])
	assert_signal_emitted_with_parameters(EventBus, "big_swapped", [big_a, big_b, dropped])
	for e in RunState.run_log:
		assert_ne(e.event, &"revert", "a drop is not a rollback")


func test_the_console_swap_to_turn_based_drops_gravity_and_reversed_gravity() -> void:
	for e in RunState.live_entities():
		e.free()
	var gravity := MutationDB.get_mutation(&"gravity_on")
	var reversed := MutationDB.get_mutation(&"gravity_reversed")
	var bounce := MutationDB.get_mutation(&"bouncing_projectiles")
	RunState.apply(gravity)
	RunState.apply(reversed)
	RunState.apply(bounce)
	var dropped := RunState.swap_big(MutationDB.get_mutation(&"turn_mode"))
	assert_eq(dropped, [reversed, gravity] as Array[Mutation])
	assert_eq(RunState.stack, [bounce] as Array[Mutation])
	assert_false(RunState.rules.gravity_enabled)
	assert_eq(RunState.run_log[-1].dropped, ["gravity_reversed", "gravity_on"])
	assert_false(RunState.can_apply(gravity), "never offered again under B2")


func test_big_swapped_signal_carries_old_new_and_dropped() -> void:
	watch_signals(EventBus)
	RunState.swap_big(big_a)
	assert_signal_emitted_with_parameters(EventBus, "big_swapped", [null, big_a, []])
	RunState.apply(under_a)
	RunState.swap_big(big_b)
	assert_signal_emitted_with_parameters(EventBus, "big_swapped", [big_a, big_b, [under_a]])


# --- Time ownership ------------------------------------------------------------

func test_only_run_state_writes_engine_time_scale() -> void:
	var offenders: Array[String] = []
	for path in _scripts("res://"):
		if path == "res://core/run_state.gd":
			continue
		var text := FileAccess.get_file_as_string(path)
		var regex := RegEx.create_from_string("Engine\\.time_scale\\s*=[^=]")
		if regex.search(text):
			offenders.append(path)
	assert_eq(offenders, [] as Array[String])


func test_time_scale_follows_rules_with_no_big_patch() -> void:
	assert_eq(RunState.motion_factor(), 1.0)
	await wait_physics_frames(2)
	assert_almost_eq(Engine.time_scale, RunState.rules.time_scale, 0.0001)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for entry in DirAccess.get_directories_at(dir):
		if entry.begins_with(".") or entry in ["addons", "tests", "builds"]:
			continue
		out.append_array(_scripts(dir.path_join(entry)))
	for entry in DirAccess.get_files_at(dir):
		if entry.ends_with(".gd"):
			out.append(dir.path_join(entry))
	return out


# --- Invariant -----------------------------------------------------------------

## Whatever legal sequence of apply / revert / swap_big / reset reached (big B, stack S),
## the derived state equals reset -> swap_big(B) -> apply S in order.
func test_replay_equivalence_with_swaps() -> void:
	var rng := RandomNumberGenerator.new()
	var sequences := 250
	var swaps := 0
	for s in sequences:
		rng.seed = 1000 + s
		RunState.reset(s)
		for step in rng.randi_range(5, 30):
			var ops: Array = []
			for m in smalls:
				if RunState.can_apply(m):
					ops.append([&"apply", m])
			for m in RunState.stack:
				ops.append([&"revert", m])
			for m in [big_a, big_b]:
				if m != RunState.big:
					ops.append([&"swap", m])
			# Illegal operations must be harmless no-ops.
			if RunState.big != null:
				ops.append([&"revert_big", RunState.big])
			var op: Array = ops[rng.randi_range(0, ops.size() - 1)]
			match op[0]:
				&"apply":
					RunState.apply(op[1])
				&"revert", &"revert_big":
					RunState.revert(op[1])
				&"swap":
					RunState.swap_big(op[1])
					swaps += 1
			if rng.randf() < 0.03:
				RunState.reset(s)
			for e in RunState.live_entities():
				for c in e.get_children():
					if c is Component and c.source_patch != &"" and not RunState.has_patch(c.source_patch):
						fail_test("seed %d: component from %s outlived its patch" % [s, c.source_patch])
						return
			for sig: Dictionary in EventBus.get_signal_list():
				for conn: Dictionary in EventBus.get_signal_connection_list(sig.name):
					var obj := (conn.callable as Callable).get_object()
					if obj is Mutation and not RunState.has_patch((obj as Mutation).id):
						fail_test("seed %d: listener from %s outlived its patch" % [s, (obj as Mutation).id])
						return
		var final_big := RunState.big
		var final_stack: Array[Mutation] = RunState.stack.duplicate()
		var reached := _snap()
		RunState.reset(s)
		if final_big:
			RunState.swap_big(final_big)
		for m in final_stack:
			RunState.apply(m)
		var replayed := _snap()
		if reached != replayed:
			fail_test("seed %d diverged.\nreached:  %s\nreplayed: %s" % [s, reached, replayed])
			return
	assert_gt(swaps, sequences, "swaps were exercised")
