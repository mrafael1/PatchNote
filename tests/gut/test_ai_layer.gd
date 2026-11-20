extends GutTest
## The AI layer (PLAN v4 1.1 and 1.2): the medium and boss-only tiers, the DB rules,
## add / remove / expire, the layer order, the big swap's AI drops, can_add_ai_list,
## and the replay-equivalence invariant extended with AI operations.

const Fx := preload("res://tests/gut/fixtures.gd")
## What a live AI fixture puts in the world: EventBus listeners, and the entity group
## its component goes on (fixtures.gd).
const AI_LIVE := {
	&"fx_med_a": {"listeners": 1, "group": &"enemy"},
	&"fx_med_on_a": {"listeners": 1, "group": &""},
	&"fx_med_against_b": {"listeners": 0, "group": &"player"},
	&"fx_boss_hazard": {"listeners": 1, "group": &"enemy"},
}

var smalls: Array[Mutation]
var big_a: Mutation
var big_b: Mutation
var under_a: Mutation
var med_a: Mutation
var med_on_a: Mutation
var med_against_b: Mutation
var boss_hazard: Mutation
var against_med: Mutation
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
	smalls.append_array([under_a, bigs[3], bigs[4]])
	var ai_set := Fx.make_ai_set()
	med_a = ai_set[0]
	med_on_a = ai_set[1]
	med_against_b = ai_set[2]
	boss_hazard = ai_set[3]
	against_med = ai_set[4]
	smalls.append(against_med)


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


func _ids(patches: Array[Mutation]) -> Array[String]:
	var out: Array[String] = []
	for m in patches:
		out.append(String(m.id))
	return out


# --- Tiers -----------------------------------------------------------------------

func test_tier_flags_and_is_ai_tier() -> void:
	assert_true(med_a.is_ai_tier())
	assert_true(boss_hazard.is_ai_tier())
	assert_false(against_med.is_ai_tier())
	assert_false(big_a.is_ai_tier())


func test_the_gravity_pair_is_medium_with_its_boss_weights() -> void:
	var gravity := MutationDB.get_mutation(&"gravity_on")
	var reversed := MutationDB.get_mutation(&"gravity_reversed")
	assert_true(gravity.is_medium)
	assert_true(reversed.is_medium)
	assert_true(gravity.is_mode_switch, "a gravity change keeps the long transition")
	assert_true(&"turn_mode" in gravity.conflicts)
	assert_eq(gravity.boss_weight, 1.0)
	assert_eq(reversed.boss_weight, 0.5)
	assert_false(gravity.starter)


func test_the_starter_flags_are_the_six_kept_smalls_and_the_two_bigs() -> void:
	var starters: Array[String] = []
	for m in MutationDB.all:
		if m.starter:
			starters.append(String(m.id))
			assert_false(m.is_ai_tier(), "%s: AI-tier patches are not offered" % m.id)
	assert_eq(starters, ["auto_attack", "bouncing_projectiles", "enemies_split", "explode_on_hit",
			"horde_mode", "jump_button", "motion_time", "turn_mode"])


func test_summary_line_marks_mediums() -> void:
	var line := MutationDB.summary_line()
	assert_string_contains(line, "gravity_on (MED)")
	assert_string_contains(line, "gravity_reversed (MED)")
	assert_false(line.contains("horde_mode ("), "a small patch is not marked")


# --- DB rules --------------------------------------------------------------------

func test_the_db_rejects_two_tier_flags() -> void:
	var both := Fx.make_medium(Fx.FxMedA, &"fx_bad_tiers")
	both.boss_only = true
	assert_gt(MutationDB.problems(both).size(), 0, "medium and boss-only")
	var big_med := Fx.make_big(Fx.FxBigA, &"fx_bad_big_med")
	big_med.is_medium = true
	assert_gt(MutationDB.problems(big_med).size(), 0, "big and medium")
	var big_boss := Fx.make_big(Fx.FxBigA, &"fx_bad_big_boss")
	big_boss.boss_only = true
	big_boss.boss_weight = 1.0
	assert_gt(MutationDB.problems(big_boss).size(), 0, "big and boss-only")
	assert_eq(MutationDB.problems(med_a), [] as Array[String])
	assert_eq(MutationDB.problems(boss_hazard), [] as Array[String])


func test_the_db_rejects_a_boss_only_patch_without_a_boss_weight() -> void:
	var bad := Fx.make_boss_only(Fx.FxBossHazard, &"fx_bad_boss")
	bad.boss_weight = 0.0
	assert_gt(MutationDB.problems(bad).size(), 0)


func test_an_ai_tier_patch_may_require_only_mediums() -> void:
	var on_gravity := Fx.make_medium(Fx.FxMedA, &"fx_low", [&"gravity_on"])
	assert_eq(MutationDB.problems(on_gravity), [] as Array[String], "requires a medium")
	var on_small := Fx.make_medium(Fx.FxMedA, &"fx_bad_on_small", [&"horde_mode"])
	assert_gt(MutationDB.problems(on_small).size(), 0, "requires a small")
	var on_big := Fx.make_medium(Fx.FxMedA, &"fx_bad_on_big", [&"turn_mode"])
	assert_gt(MutationDB.problems(on_big).size(), 0, "requires a big")
	var boss_on_small := Fx.make_boss_only(Fx.FxBossHazard, &"fx_bad_boss_on_small")
	boss_on_small.requires.assign([&"horde_mode"])
	assert_gt(MutationDB.problems(boss_on_small).size(), 0, "boss-only requires a small")
	var conflicts_big := Fx.make_medium(Fx.FxMedA, &"fx_against_turns", [], [&"turn_mode"])
	assert_eq(MutationDB.problems(conflicts_big), [] as Array[String], "may conflict with a big")


func test_a_small_patch_may_not_require_an_ai_tier_patch() -> void:
	var bad := Fx.make(Fx.FxRules, &"fx_bad_small", [&"gravity_on"])
	assert_gt(MutationDB.problems(bad).size(), 0)
	var ok := Fx.make(Fx.FxRules, &"fx_ok_small", [], [&"gravity_on"])
	assert_eq(MutationDB.problems(ok), [] as Array[String], "it may conflict with one")


# --- Add / remove / expire ------------------------------------------------------

func test_add_ai_applies_everything_and_logs() -> void:
	watch_signals(EventBus)
	var build := RunState.build_number
	assert_true(RunState.can_add_ai(med_a))
	assert_true(RunState.add_ai(med_a, &"stage"))
	assert_eq(RunState.ai, [med_a] as Array[Mutation])
	assert_eq(RunState.ai_owner, {&"fx_med_a": &"stage"})
	assert_true(RunState.has_patch(&"fx_med_a"))
	assert_false(RunState.stack.has(med_a), "an AI patch never enters the stack")
	assert_almost_eq(RunState.rules.turn_duration, RunState.base_rules.turn_duration + 0.25, 0.0001)
	assert_eq(_components_from(&"fx_med_a"), 2, "both enemies")
	assert_eq(_connections_from(&"fx_med_a"), 1)
	assert_eq(RunState.build_number, build + 1)
	var entry: Dictionary = RunState.run_log[-1]
	assert_eq(entry.event, &"ai_apply")
	assert_eq(entry.id, &"fx_med_a")
	assert_eq(entry.owner, &"stage")
	assert_signal_emitted_with_parameters(EventBus, "ai_patch_added", [med_a, &"stage"])
	assert_false(RunState.add_ai(med_a, &"boss"), "already live")
	assert_eq(RunState.build_number, build + 1)


func test_add_ai_refuses_small_and_big_patches_and_unmet_requires() -> void:
	var before := _snap()
	assert_false(RunState.add_ai(null, &"stage"))
	assert_false(RunState.add_ai(against_med, &"stage"))
	assert_false(RunState.add_ai(against_med, &"stage", true), "not even forced")
	assert_false(RunState.add_ai(big_a, &"stage", true))
	assert_false(RunState.can_add_ai(med_on_a), "requires fx_med_a")
	assert_false(RunState.add_ai(med_on_a, &"stage"))
	assert_eq(_snap(), before)
	assert_true(RunState.add_ai(med_on_a, &"stage", true), "the console may force it")


func test_apply_and_can_apply_refuse_ai_tier_patches() -> void:
	assert_false(RunState.can_apply(med_a))
	assert_false(RunState.apply(med_a))
	assert_false(RunState.apply(med_a, true), "not even forced")
	assert_false(RunState.can_apply(boss_hazard))
	assert_eq(RunState.stack.size(), 0)


func test_conflicts_hold_across_the_stack_and_the_ai_layer() -> void:
	RunState.add_ai(med_a, &"stage")
	assert_false(RunState.can_apply(against_med), "the small conflicts with a live medium")
	RunState.remove_ai(med_a, &"rollback")
	assert_true(RunState.apply(against_med))
	assert_false(RunState.can_add_ai(med_a), "the medium conflicts with a stacked small")
	RunState.swap_big(big_b)
	assert_false(RunState.can_add_ai(med_against_b), "the medium conflicts with the big")
	RunState.swap_big(big_a)
	assert_true(RunState.can_add_ai(med_against_b))


func test_requires_are_never_met_across_layers() -> void:
	# Never in shipped data (the DB rejects it). A removal cascades within one layer
	# only, so a cross-layer requirement would strand its dependent: both are refused.
	var on_med := Fx.make(Fx.FxRules, &"fx_on_med", [&"fx_med_a"])
	RunState.add_ai(med_a, &"stage")
	assert_true(RunState.has_patch(&"fx_med_a"))
	assert_false(RunState.can_apply(on_med), "a live medium does not meet a small's requires")
	assert_false(RunState.apply(on_med))
	var on_small := Fx.make_medium(Fx.FxMedOnA, &"fx_med_on_small", [&"fx_rules"])
	assert_true(RunState.apply(smalls[0]), "fx_rules")
	assert_false(RunState.can_add_ai(on_small), "a stacked small does not meet an AI patch's requires")
	assert_false(RunState.add_ai(on_small, &"stage"))
	RunState.swap_big(big_a)
	assert_true(RunState.can_apply(under_a), "the big slot still meets a small's requires")
	assert_true(RunState.can_add_ai(med_on_a), "the AI layer meets an AI patch's requires")


func test_layer_order_is_base_big_ai_stack() -> void:
	RunState.swap_big(big_a)
	RunState.apply(under_a)
	RunState.add_ai(med_a, &"stage")
	# big assigns 0.5, AI adds 0.25, the small doubles: 1.5. Any other order differs.
	assert_almost_eq(RunState.rules.turn_duration, 1.5, 0.0001)
	RunState.add_ai(med_on_a, &"stage")
	assert_almost_eq(RunState.rules.turn_duration, 4.5, 0.0001, "AI patches in add order")
	var preview := RunState.preview_rules([] as Array[Mutation], big_a, [med_a] as Array[Mutation])
	assert_almost_eq(preview.turn_duration, 0.75, 0.0001)
	var live := RunState.preview_rules(RunState.stack)
	assert_eq(live.to_dict(), RunState.rules.to_dict(), "defaults are the live layers")


func test_new_entities_get_big_then_ai_then_stack() -> void:
	RunState.swap_big(big_a)
	RunState.add_ai(med_a, &"stage")
	RunState.apply(smalls[1])   # fx_component
	world.add_child(Fx.make_entity(&"enemy", "E3"))
	var e3 := world.get_node("E3")
	var order: Array[StringName] = []
	for c in e3.get_children():
		if c is Component:
			order.append(c.source_patch)
	assert_eq(order, [&"fx_big_a", &"fx_med_a", &"fx_component"] as Array[StringName])


func test_remove_ai_takes_ai_dependents_in_one_build() -> void:
	RunState.add_ai(med_a, &"stage")
	RunState.add_ai(boss_hazard, &"boss")
	RunState.add_ai(med_on_a, &"boss")
	assert_eq(RunState.ai_dependents_of(med_a), [med_on_a] as Array[Mutation])
	assert_eq(RunState.ai_dependents_of(boss_hazard), [] as Array[Mutation])
	watch_signals(EventBus)
	var build := RunState.build_number
	var removed := RunState.remove_ai(med_a, &"rollback")
	assert_eq(removed, [med_on_a, med_a] as Array[Mutation], "dependents first")
	assert_eq(RunState.ai, [boss_hazard] as Array[Mutation])
	assert_eq(RunState.ai_owner, {&"fx_boss_hazard": &"boss"})
	assert_eq(RunState.build_number, build + 1, "one build")
	assert_eq(_components_from(&"fx_med_a"), 0)
	assert_eq(_connections_from(&"fx_med_a"), 0)
	assert_eq(_connections_from(&"fx_med_on_a"), 0)
	assert_false(RunState.patch_state.has(&"fx_med_a"))
	var entry: Dictionary = RunState.run_log[-1]
	assert_eq(entry.event, &"ai_remove")
	assert_eq(entry.ids, ["fx_med_on_a", "fx_med_a"])
	assert_eq(entry.reason, &"rollback")
	assert_signal_emit_count(EventBus, "ai_patch_removed", 2)
	assert_signal_emitted_with_parameters(EventBus, "ai_patch_removed", [med_a, &"rollback"])
	assert_eq(RunState.remove_ai(med_a, &"rollback").size(), 0, "no longer live")
	assert_eq(RunState.build_number, build + 1)


func test_remove_ai_ignores_stack_and_big_patches() -> void:
	RunState.swap_big(big_a)
	RunState.apply(smalls[0])
	var before := _snap()
	assert_eq(RunState.remove_ai(smalls[0], &"rollback").size(), 0)
	assert_eq(RunState.remove_ai(big_a, &"rollback").size(), 0)
	assert_eq(_snap(), before)


func test_revert_ignores_ai_patches() -> void:
	RunState.add_ai(med_a, &"stage")
	var before := _snap()
	assert_eq(RunState.revert(med_a).size(), 0)
	assert_eq(RunState.dependents_of(med_a).size(), 0, "dependents_of stays stack-only")
	assert_eq(_snap(), before)


func test_expire_ai_removes_one_owner_as_one_build() -> void:
	RunState.add_ai(med_a, &"stage")
	RunState.add_ai(boss_hazard, &"boss")
	RunState.add_ai(med_against_b, &"stage")
	var build := RunState.build_number
	var removed := RunState.expire_ai(&"stage")
	assert_eq(removed, [med_against_b, med_a] as Array[Mutation])
	assert_eq(RunState.ai, [boss_hazard] as Array[Mutation])
	assert_eq(RunState.build_number, build + 1)
	assert_eq(RunState.run_log[-1].reason, &"expired")
	assert_eq(RunState.expire_ai(&"stage").size(), 0, "nothing left of that owner")
	assert_eq(RunState.build_number, build + 1, "and no build for nothing")


func test_expire_takes_dependents_of_another_owner() -> void:
	RunState.add_ai(med_a, &"stage")
	RunState.add_ai(med_on_a, &"boss")
	assert_eq(RunState.expire_ai(&"stage"), [med_on_a, med_a] as Array[Mutation])
	assert_eq(RunState.ai.size(), 0)


func test_swap_big_drops_conflicting_ai_patches_and_their_dependents() -> void:
	var on_against := Fx.make_medium(Fx.FxMedOnA, &"fx_on_against", [&"fx_med_against_b"])
	RunState.add_ai(med_a, &"stage")
	RunState.add_ai(med_against_b, &"stage")
	RunState.add_ai(on_against, &"stage")
	RunState.apply(smalls[0])
	assert_eq(RunState.ai_swap_drops(big_b), [on_against, med_against_b] as Array[Mutation])
	watch_signals(EventBus)
	var build := RunState.build_number
	var dropped := RunState.swap_big(big_b)
	assert_eq(dropped, [] as Array[Mutation], "the return value lists small patches only")
	assert_eq(RunState.ai, [med_a] as Array[Mutation])
	assert_eq(RunState.build_number, build + 1, "one build")
	assert_eq(_components_from(&"fx_med_against_b"), 0)
	var removes := RunState.run_log.filter(func(e: Dictionary) -> bool: return e.event == &"ai_remove")
	assert_eq(removes.size(), 1)
	assert_eq(removes[0].ids, ["fx_on_against", "fx_med_against_b"])
	assert_eq(removes[0].reason, &"dropped")
	assert_signal_emitted_with_parameters(EventBus, "ai_patch_removed", [med_against_b, &"dropped"])
	assert_eq(RunState.run_log[-1].event, &"big_swap")


func test_reset_strips_the_layer() -> void:
	RunState.add_ai(med_a, &"stage")
	RunState.add_ai(boss_hazard, &"boss")
	RunState.reset(2)
	assert_eq(RunState.ai.size(), 0)
	assert_eq(RunState.ai_owner.size(), 0)
	assert_eq(_components_from(&"fx_med_a"), 0)
	assert_eq(_connections_from(&"fx_boss_hazard"), 0)
	assert_eq(RunState.rules.to_dict(), RunState.base_rules.to_dict())


func test_snapshot_lists_ai_ids_with_owners() -> void:
	RunState.add_ai(med_a, &"stage")
	RunState.add_ai(boss_hazard, &"boss")
	assert_eq(RunState.snapshot().ai, [["fx_med_a", "stage"], ["fx_boss_hazard", "boss"]])


# --- can_add_ai_list -------------------------------------------------------------

func test_can_add_ai_list_follows_requires_in_list_order() -> void:
	var none: Array[Mutation] = []
	assert_true(RunState.can_add_ai_list([&"gravity_on", &"gravity_reversed"], null, none))
	assert_true(RunState.can_add_ai_list([&"gravity_on"], null, none))
	assert_true(RunState.can_add_ai_list([], null, none), "an empty layer is legal")
	assert_false(RunState.can_add_ai_list([&"gravity_reversed"], null, none), "requires gravity_on")
	assert_false(RunState.can_add_ai_list([&"gravity_reversed", &"gravity_on"], null, none), "order counts")
	assert_false(RunState.can_add_ai_list([&"gravity_on", &"gravity_on"], null, none), "no repeats")
	assert_false(RunState.can_add_ai_list([&"horde_mode"], null, none), "a small is not AI-tier")
	assert_false(RunState.can_add_ai_list([&"turn_mode"], null, none), "a big is not AI-tier")
	assert_false(RunState.can_add_ai_list([&"no_such_patch"], null, none))


func test_can_add_ai_list_checks_the_given_big_and_stack() -> void:
	var none: Array[Mutation] = []
	var turns := MutationDB.get_mutation(&"turn_mode")
	assert_false(RunState.can_add_ai_list([&"gravity_on"], turns, none), "gravity conflicts with B2")
	assert_true(RunState.can_add_ai_list([&"gravity_on"], MutationDB.get_mutation(&"motion_time"), none))
	var against_gravity := Fx.make(Fx.FxRules, &"fx_against_gravity", [], [&"gravity_on"])
	assert_false(RunState.can_add_ai_list([&"gravity_on"], null, [against_gravity] as Array[Mutation]))
	RunState.swap_big(turns)
	assert_true(RunState.can_add_ai_list([&"gravity_on"], null, none), "the live big is not read")


func test_can_add_ai_list_never_reads_the_live_layer() -> void:
	var none: Array[Mutation] = []
	RunState.add_ai(MutationDB.get_mutation(&"gravity_on"), &"stage")
	assert_false(RunState.can_add_ai_list([&"gravity_reversed"], null, none),
			"a live gravity_on does not meet the list's requires")
	assert_true(RunState.can_add_ai_list([&"gravity_on"], null, none),
			"a live gravity_on does not make the list a repeat")


# --- Invariant -------------------------------------------------------------------

## Whatever legal sequence of apply / revert / swap_big / add_ai / remove_ai /
## expire_ai / reset reached (big B, AI layer A with owners, stack S), the derived
## state equals reset -> swap_big(B) -> add_ai each of A in order -> apply S in order.
## No ghost after any op: every id in `ai` is live, and every live AI component and
## listener belongs to a patch in `ai`.
func test_replay_equivalence_with_ai_operations() -> void:
	var ai_set: Array[Mutation] = [med_a, med_on_a, med_against_b, boss_hazard]
	var rng := RandomNumberGenerator.new()
	var sequences := 260
	var counts := {&"add_ai": 0, &"remove_ai": 0, &"expire_ai": 0, &"swap": 0, &"spawn": 0}
	var spawned := 0
	for s in sequences:
		rng.seed = 5000 + s
		RunState.reset(s)
		for step in rng.randi_range(5, 35):
			var ops: Array = []
			for m in smalls:
				if RunState.can_apply(m):
					ops.append([&"apply", m])
			for m in RunState.stack:
				ops.append([&"revert", m])
			for m in [big_a, big_b]:
				if m != RunState.big:
					ops.append([&"swap", m])
			for m in ai_set:
				if RunState.can_add_ai(m):
					ops.append([&"add_ai", m])
					ops.append([&"add_ai", m])   # weighted: keep the layer busy
			for m in RunState.ai:
				ops.append([&"remove_ai", m])
			if not RunState.ai.is_empty():
				ops.append([&"expire_ai", &"stage"])
				ops.append([&"expire_ai", &"boss"])
			ops.append([&"spawn", null])
			# Illegal operations must be harmless no-ops.
			for m in RunState.ai:
				ops.append([&"revert_ai", m])
				ops.append([&"apply_ai", m])
			if not RunState.stack.is_empty():
				ops.append([&"remove_small", RunState.stack[0]])
			ops.append([&"add_small", smalls[rng.randi_range(0, smalls.size() - 1)]])
			var op: Array = ops[rng.randi_range(0, ops.size() - 1)]
			var before := ""
			if op[0] in [&"revert_ai", &"apply_ai", &"remove_small", &"add_small"]:
				before = _snap()
			match op[0]:
				&"apply":
					RunState.apply(op[1])
				&"revert", &"revert_ai":
					RunState.revert(op[1])
				&"swap":
					RunState.swap_big(op[1])
				&"add_ai":
					var owner_id: StringName = &"boss" if (op[1] as Mutation).boss_only or rng.randf() < 0.4 \
							else &"stage"
					RunState.add_ai(op[1], owner_id)
				&"remove_ai":
					RunState.remove_ai(op[1], &"rollback")
				&"expire_ai":
					RunState.expire_ai(op[1])
				&"apply_ai":
					RunState.apply(op[1], true)
				&"remove_small":
					RunState.remove_ai(op[1], &"rollback")
				&"add_small":
					RunState.add_ai(op[1], &"stage", true)
				&"spawn":
					spawned += 1
					world.add_child(Fx.make_entity(&"enemy" if rng.randf() < 0.7 else &"player", "S%d" % spawned))
			if counts.has(op[0]):
				counts[op[0]] += 1
			if before != "" and _snap() != before:
				fail_test("seed %d: illegal %s changed the state" % [s, op[0]])
				return
			if rng.randf() < 0.03:
				RunState.reset(s)
			var ghost := _ghost(ai_set)
			if ghost != "":
				fail_test("seed %d step %d (%s): %s" % [s, step, op[0], ghost])
				return
		var final_big := RunState.big
		var final_ai: Array[Mutation] = RunState.ai.duplicate()
		var final_owner := RunState.ai_owner.duplicate()
		var final_stack: Array[Mutation] = RunState.stack.duplicate()
		var reached := _snap()
		RunState.reset(s)
		if final_big:
			RunState.swap_big(final_big)
		for m in final_ai:
			RunState.add_ai(m, final_owner[m.id])
		for m in final_stack:
			RunState.apply(m)
		var replayed := _snap()
		if reached != replayed:
			fail_test("seed %d diverged.\nreached:  %s\nreplayed: %s" % [s, reached, replayed])
			return
		# Keep the world small: drop what this sequence spawned.
		for e in world.get_children():
			if String(e.name).begins_with("S"):
				e.free()
	assert_gt(counts[&"add_ai"], sequences, "AI adds were exercised")
	assert_gt(counts[&"remove_ai"], sequences / 2, "AI removals were exercised")
	assert_gt(counts[&"expire_ai"], sequences / 4, "expiries were exercised")
	assert_gt(counts[&"swap"], sequences / 2, "swaps were exercised")
	assert_gt(counts[&"spawn"], sequences / 2, "spawns were exercised")


## Empty when the AI layer has no ghost; otherwise what is wrong.
func _ghost(ai_set: Array[Mutation]) -> String:
	var ai_ids: Array[StringName] = []
	for m in RunState.ai:
		ai_ids.append(m.id)
		if not RunState.ai_owner.has(m.id):
			return "%s is in ai without an owner" % m.id
	if RunState.ai_owner.size() != RunState.ai.size():
		return "ai_owner has %d entries for %d AI patches" % [RunState.ai_owner.size(), RunState.ai.size()]
	var tier_ids: Array[StringName] = []
	for m in ai_set:
		tier_ids.append(m.id)
	for e in RunState.live_entities():
		for c in e.get_children():
			if not c is Component or c.source_patch == &"":
				continue
			if not RunState.has_patch(c.source_patch):
				return "component from %s outlived its patch" % c.source_patch
			if c.source_patch in tier_ids and not c.source_patch in ai_ids:
				return "AI component from %s is not in ai" % c.source_patch
	for sig: Dictionary in EventBus.get_signal_list():
		for conn: Dictionary in EventBus.get_signal_connection_list(sig.name):
			var obj := (conn.callable as Callable).get_object()
			if obj is Mutation and not RunState.has_patch((obj as Mutation).id):
				return "listener from %s outlived its patch" % (obj as Mutation).id
			if obj is Mutation and (obj as Mutation).id in tier_ids and not (obj as Mutation).id in ai_ids:
				return "AI listener from %s is not in ai" % (obj as Mutation).id
	# Every AI patch is live: its listeners are connected, its component is on every
	# entity of the group it attaches to (and no other), and its rules are in force.
	for m in RunState.ai:
		var want: Dictionary = AI_LIVE[m.id]
		if _connections_from(m.id) != want.listeners:
			return "%s is in ai with %d listeners, not %d" % [m.id, _connections_from(m.id), want.listeners]
		for e in RunState.live_entities():
			var has := false
			for c in e.get_children():
				if c is Component and c.source_patch == m.id:
					has = true
			if has != (want.group != &"" and e.is_in_group(want.group)):
				return "%s is in ai but its component on %s is %s" % [m.id, e.name, "there" if has else "missing"]
	var expected := RunState.preview_rules(RunState.stack, RunState.big, RunState.ai)
	if expected.to_dict() != RunState.rules.to_dict():
		return "rules are not base -> big -> ai -> stack"
	return ""
