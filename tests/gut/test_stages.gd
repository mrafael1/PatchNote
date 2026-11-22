extends GutTest
## M34: stage plumbing and arenas as data (PLAN v6 4). Arenas load from
## levels/arenas/ and pass the top-down checks; a run plays a StageSet: play, stage
## clear, next stage (new arena, same stack), and the last stage's release candidate;
## the same seed gives the same 3-stage run.

const TUNING_KEYS: Array[String] = ["transition_long", "transition_short", "prompt_input_delay",
		"rc_duration", "report_delay", "stage_clear_time", "first_prompt_min_gap", "prompt_min_gap",
		"prompt_max_gap", "first_prompt_max_gap"]
const STAGE_TIME := 1.0

var game: Main
var stage_ends: Array[int] = []
var _saved := {}


func before_each() -> void:
	for key in TUNING_KEYS:
		_saved[key] = Tuning.get(key)
	Tuning.transition_long = 0.0
	Tuning.transition_short = 0.0
	Tuning.prompt_input_delay = 0.0
	Tuning.rc_duration = 1.0
	Tuning.report_delay = 0.2
	Tuning.stage_clear_time = 0.3
	stage_ends.clear()
	EventBus.stage_ended.connect(_on_stage_ended)


func after_each() -> void:
	EventBus.stage_ended.disconnect(_on_stage_ended)
	await _drop_game()
	StageSet.override = null
	for key: String in _saved:
		Tuning.set(key, _saved[key])


func _on_stage_ended(index: int) -> void:
	stage_ends.append(index)


## Three short stages on the three arenas, one prompt each.
func _short_set() -> StageSet:
	var set := StageSet.new()
	set.id = &"test_three"
	var defs: Array[Resource] = []
	for i in 3:
		var s := StageDef.new()
		s.arena = load("res://levels/arenas/arena_%d.tres" % i) as ArenaDef
		s.duration = STAGE_TIME
		s.prompts = 1
		s.spawn_rate = 1.0 + 0.5 * i
		defs.append(s)
	set.stages = defs
	return set


func _start(run_seed: int, set: StageSet) -> void:
	await wait_physics_frames(1)   # a physics frame boundary, as test_grid_enemies does
	StageSet.override = set
	Main.next_seed = run_seed
	game = load("res://main.tscn").instantiate() as Main
	add_child(game)
	await wait_physics_frames(2)


func _drop_game() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await wait_physics_frames(1)
	game = null
	RunState.reset(0)
	RunState.world = null


func _wait_phase(phase: StringName, max_frames := 600) -> void:
	for i in max_frames:
		if game.run_loop.phase == phase:
			return
		await wait_physics_frames(1)


# --- Arenas as data ----------------------------------------------------------

func test_every_arena_passes_its_genre_checks() -> void:
	var ids: Array[String] = []
	for f in DirAccess.get_files_at("res://levels/arenas/"):
		if not f.ends_with(".tres"):
			continue
		var def := load("res://levels/arenas/" + f) as ArenaDef
		assert_not_null(def, f)
		assert_eq(String(def.id), f.get_basename(), "the id is the file name")
		for g in def.genres:
			assert_eq(def.problems(g), [] as Array[String], "%s for %s" % [f, g])
		ids.append(f.get_basename())
	assert_eq(ids, ["arena_0", "arena_1", "arena_2"])


func test_arena_0_is_the_m14_arena() -> void:
	var arena := Arena.new()
	assert_eq(arena.def.id, &"arena_0", "the default arena")
	assert_eq(arena.blocks.size(), 4 + 21 + 4, "border, 21 ledges, 4 chunks")
	var t := Tuning.TILE
	assert_eq(arena.blocks[4], Rect2(6 * t, 18 * t, 6 * t, t), "first ledge, in M14's order")
	assert_eq(arena.blocks[28], Rect2(56 * t, 1 * t, 2 * t, 2 * t), "last chunk")
	assert_eq(arena.spawn_points.size(), 14)
	assert_eq(arena.spawn_points[3], Vector2(62.5, 5) * t)
	assert_eq(arena.player_start, Vector2(33, 14) * t)
	arena.free()


func test_the_checks_catch_a_bad_layout() -> void:
	var good := load("res://levels/arenas/arena_1.tres") as ArenaDef
	var bad := good.duplicate() as ArenaDef
	bad.id = &"bad"
	bad.blocks = good.blocks.duplicate()
	bad.blocks.append(Rect2(64, 3, 4, 1))                       # through the border
	bad.blocks.append(Rect2(bad.player_start.x - 1, bad.player_start.y - 1, 2, 2))   # on the start
	var lines := bad.problems()
	assert_true(lines.any(func(l: String) -> bool: return "outside the border" in l), str(lines))
	assert_true(lines.any(func(l: String) -> bool: return "inside or against a block" in l), str(lines))
	var walled := good.duplicate() as ArenaDef
	walled.id = &"walled"
	walled.blocks = good.blocks.duplicate()
	walled.blocks.append(Rect2(10, 1, 1, 20))   # cuts the left markers off
	lines = walled.problems()
	assert_true(lines.any(func(l: String) -> bool: return "cannot be walked to" in l), str(lines))
	var few := good.duplicate() as ArenaDef
	few.spawn_tiles = PackedVector2Array([Vector2(3, 3)])
	assert_true(few.problems().any(func(l: String) -> bool: return "spawn markers" in l))
	assert_true(good.problems(&"platformer").size() > 0, "a layout is only checked for its genres")


func test_every_stage_set_loads_with_valid_stages() -> void:
	var ids := StageSet.ids()
	assert_has(ids, &"gauntlet")
	for set_id in ids:
		var set := StageSet.named(set_id)
		assert_eq(set.id, set_id)
		assert_gt(set.size(), 0)
		for i in set.size():
			var s := set.stage(i)
			assert_not_null(s, "%s stage %d is a StageDef" % [set_id, i])
			assert_not_null(s.arena, "%s stage %d has an arena" % [set_id, i])
			assert_eq(s.goal, StageDef.SURVIVE)
			assert_gt(s.duration, 0.0)
	var g := StageSet.named(&"gauntlet")
	assert_eq(g.size(), 3)
	var arenas := range(3).map(func(i: int) -> StringName: return g.stage(i).arena.id)
	assert_eq(arenas, [&"arena_0", &"arena_1", &"arena_2"], "three arenas in a row")
	assert_null(StageSet.named(&"nope"))


# --- The run ----------------------------------------------------------------

func test_without_stages_a_run_is_one_stage_on_arena_0() -> void:
	await _start(11, null)
	assert_eq(game.run_loop.stages.id, &"single")
	assert_eq(game.run_loop.stages.size(), 1)
	assert_eq(game.arena.def.id, &"arena_0")
	assert_eq(game.director.prompt_limit, -1, "the one-stage run keeps Tuning.prompts_per_run")
	assert_false("Stage" in game.hud._label.text, "no stage line on a one-stage run")
	RunState.invincible = true
	game.director.enabled = false
	game.director.prompt_index = Tuning.prompts_per_run
	await wait_physics_frames(2)
	assert_eq(game.run_loop.phase, RunLoop.RELEASE_CANDIDATE, "no stage clear: straight to the RC")
	game.run_loop.end(&"win")
	assert_eq(game.run_loop.record.stages, {"set": "single", "total": 1, "reached": 1, "starts": [0.0]})
	assert_eq(stage_ends, [] as Array[int])


func test_stages_run_in_order_and_the_stack_carries() -> void:
	await _start(12, _short_set())
	RunState.invincible = true
	var loop := game.run_loop
	game.director.enabled = false
	assert_true(RunState.apply(MutationDB.get_mutation(&"orbit")), "a patch picked in stage 1")
	await wait_physics_frames(1)
	var shards := game.player.get_children().filter(func(c: Node) -> bool: return c.get(&"source_patch") == &"orbit")
	assert_eq(shards.size(), 1, "orbit's component is on the player")
	var phases: Array[StringName] = []
	loop.phase_changed.connect(func(p: StringName) -> void: phases.append(p))

	for stage in 3:
		assert_eq(loop.stage_index, stage)
		assert_eq(game.arena.def.id, StringName("arena_%d" % stage))
		assert_eq(game.director.limit(), stage + 1, "one prompt per stage")
		assert_eq(game.spawner.phase_rate, 1.0 + 0.5 * stage, "the stage's spawn preset")
		assert_true(("Stage %d/3" % (stage + 1)) in game.hud._label.text)
		game.spawn_wave(4)
		await wait_physics_frames(2)
		assert_gt(RunState.count(&"enemy"), 0)
		game.director.prompt_index = game.director.limit()   # this stage's prompt is answered
		if stage < 2:
			await _wait_phase(RunLoop.STAGE_CLEAR)
			assert_almost_eq(RunState.game_time - loop.stage_started_at, STAGE_TIME, 0.05, "after its duration")
			assert_false(game.spawner.enabled, "no spawns during the clear")
			await wait_physics_frames(1)
			assert_eq(RunState.count(&"enemy"), 0, "the field is cleared")
			assert_true(RunState.in_grace())
			await _wait_phase(RunLoop.PLAY)
			assert_true(game.spawner.enabled)
			assert_eq(game.player.global_position, game.arena.player_start, "at the new start")
			assert_eq(game.camera.limit_right, int(game.arena.bounds.end.x))
			assert_eq(game.spawner.arena, game.arena)
			assert_eq(game.turn_clock.arena, game.arena)
			assert_eq(game.get_node("Genre").get_children().filter(func(c: Node) -> bool: return c is Arena).size(), 1, "one arena at a time")
		else:
			await _wait_phase(RunLoop.RELEASE_CANDIDATE)
	assert_eq(stage_ends, [0, 1] as Array[int], "the shell hears the two stage ends")
	assert_eq(phases, [RunLoop.STAGE_CLEAR, RunLoop.PLAY, RunLoop.STAGE_CLEAR, RunLoop.PLAY,
			RunLoop.RELEASE_CANDIDATE] as Array[StringName])
	assert_true(RunState.has_patch(&"orbit"), "the stack carries")
	assert_eq(shards[0].get_parent(), game.player, "and the player keeps its components")
	await _wait_phase(RunLoop.OVER, 200)
	var rec := loop.record
	assert_eq(rec.outcome, "win")
	assert_eq(rec.stages.set, "test_three")
	assert_eq(rec.stages.total, 3)
	assert_eq(rec.stages.reached, 3)
	assert_eq((rec.stages.starts as Array).size(), 3)
	var events := RunState.run_log.map(func(e: Dictionary) -> StringName: return e.event)
	assert_eq(events.count(&"stage_clear"), 2)
	assert_eq(events.count(&"stage_start"), 2)


func test_a_stage_waits_for_its_prompt_and_its_time() -> void:
	await _start(13, _short_set())
	RunState.invincible = true
	game.director.enabled = false
	await wait_physics_frames(int(STAGE_TIME * 60) + 10)
	assert_eq(game.run_loop.phase, RunLoop.PLAY, "time alone does not end it")
	game.director.prompt_index = 1
	game.director.pending = Offer.new()
	await wait_physics_frames(3)
	assert_eq(game.run_loop.phase, RunLoop.PLAY, "an open prompt holds it")
	game.director.pending = null
	await wait_physics_frames(2)
	assert_eq(game.run_loop.phase, RunLoop.STAGE_CLEAR)


func test_dying_in_stage_two_records_the_stage_reached() -> void:
	await _start(14, _short_set())
	game.director.enabled = false
	game.director.prompt_index = 1
	await _wait_phase(RunLoop.STAGE_CLEAR)
	await _wait_phase(RunLoop.PLAY)
	assert_eq(game.run_loop.stage_index, 1)
	var health := Component.find(game.player, Health) as Health
	await wait_physics_frames(int(Tuning.stage_start_grace * 60) + 5)
	health.take(DamageInfo.make(999, &"contact", &"enemy"))
	await wait_physics_frames(2)
	assert_eq(game.run_loop.outcome, &"lose")
	assert_eq(game.run_loop.record.stages.reached, 2)


func test_the_hunter_follows_you_into_the_next_stage() -> void:
	await _start(15, _short_set())
	RunState.invincible = true
	game.director.enabled = false
	assert_true(RunState.apply(MutationDB.get_mutation(&"hunter")))
	RunState.game_time = 61.0
	game.run_loop.stage_started_at = RunState.game_time
	await wait_physics_frames(2)
	var hunter := get_tree().get_first_node_in_group(&"threat") as Node2D
	assert_not_null(hunter, "the hunter came")
	game.director.prompt_index = 1
	await _wait_phase(RunLoop.STAGE_CLEAR)
	await wait_physics_frames(1)
	assert_true(is_instance_valid(hunter) and not hunter.is_queued_for_deletion(), "the clear keeps it")
	await _wait_phase(RunLoop.PLAY)
	assert_eq(game.arena.def.id, &"arena_1")
	assert_true(is_instance_valid(hunter), "same hunter")
	var near := game.arena.spawn_points.map(func(m: Vector2) -> float: return m.distance_to(hunter.global_position))
	assert_lt(near.min(), 8.0, "moved to one of the new arena's markers (it has taken a step since)")
	assert_eq(get_tree().get_nodes_in_group(&"threat").size(), 1, "never two")


## Same seed, same 3-stage run: the bot plays two compressed runs with prompts, and
## the world hash every 10 physics frames matches from the first frame to the report.
func test_same_seed_same_three_stage_run() -> void:
	Tuning.first_prompt_min_gap = 0.4
	Tuning.prompt_min_gap = 0.4
	Tuning.prompt_max_gap = 0.8
	Tuning.first_prompt_max_gap = 0.8
	var traces: Array[Array] = []
	var stages_seen: Array[int] = []
	for run in 2:
		await _start(4343, _short_set())
		RunState.invincible = true
		game.player.set_bot(true)
		var rng := RandomNumberGenerator.new()
		rng.seed = 9
		var trace: Array[int] = []
		for f in 1500:
			if game.report.is_open():
				break
			if game.prompt_panel.can_choose():
				game.prompt_panel.choose(rng.randi_range(0, game.prompt_panel.offer.cards.size() - 1))
			if f % 10 == 0:
				trace.append(_world_hash())
			await wait_physics_frames(1)
		assert_true(game.report.is_open(), "run %d reached its report" % run)
		stages_seen.append(game.run_loop.record.stages.reached)
		assert_eq((game.run_loop.record.prompts as Array).size(), 3, "one prompt per stage")
		traces.append(trace)
		await _drop_game()
	assert_eq(stages_seen, [3, 3] as Array[int])
	assert_eq(traces[0].size(), traces[1].size(), "same length")
	for i in mini(traces[0].size(), traces[1].size()):
		if traces[0][i] != traces[1][i]:
			fail_test("diverges at frame %d" % (i * 10))
			break
	assert_eq(hash(traces[0]), hash(traces[1]), "the 3-stage run hash matches")


func _world_hash() -> int:
	var parts: Array[String] = []
	var p := game.player.global_position
	parts.append("p%.2f,%.2f s%d" % [p.x, p.y, game.run_loop.stage_index])
	var ents: Array[String] = []
	for e: Node in RunState.live_entities():
		var pos := (e as Node2D).global_position
		ents.append("%s%.2f,%.2f" % [e.get(&"kind"), pos.x, pos.y])
	ents.sort()
	parts.append_array(ents)
	parts.append("k%d b%d" % [RunState.kills, RunState.build_number])
	for m in RunState.stack:
		parts.append(String(m.id))
	return hash("|".join(parts))
