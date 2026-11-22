extends GutTest
## M35: the shooter's Stages step (PLAN v6 4). The `stages` question comes once the look
## and the enemy are answered and the shooter has 6 runs; its three takes are stage
## sets (Gauntlet, Shifting, Breakout); shipping one writes the genre step and every
## later run plays that set; a rework swaps the set and never goes back to one arena.
## Breakout's exit gate opens once a stage's time is up and ends it when reached;
## Shifting keeps the player where it stands when the layout moves.

const TEST_PATH := "user://save_stages_test/save.json"
const TAKES: Array[StringName] = [&"stages_gauntlet", &"stages_shifting", &"stages_breakout"]
const TUNING_KEYS: Array[String] = ["transition_long", "transition_short", "prompt_input_delay",
		"rc_duration", "report_delay", "stage_clear_time"]

var game: Main
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


func after_each() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await wait_physics_frames(1)
	game = null
	RunState.reset(0)
	RunState.world = null
	StageSet.override = null
	for key: String in _saved:
		Tuning.set(key, _saved[key])
	assert_ne(SaveGame.save_path if SaveGame.persist else "", SaveGame.DEFAULT_PATH,
			"no test may leave the real save live")
	SaveGame.go_inert()
	for path in [TEST_PATH, TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## A live save with the basics, the look and the enemy answered, and `runs` runs.
func _live(runs: int) -> void:
	SaveGame.go_live(TEST_PATH, true)
	for id: StringName in [&"basic_movement", &"basic_world", &"look_1_clean", &"enemy_tank"]:
		SaveGame.ship(id, GameVersion.MINOR if id == &"look_1_clean" else GameVersion.PATCH)
	for i in runs:
		SaveGame.record_run(&"topdown", &"lose", 60.0, SaveGame.state().taste)


func _start(run_seed: int, set: StageSet) -> void:
	await wait_physics_frames(1)
	StageSet.override = set
	Main.next_seed = run_seed
	game = load("res://main.tscn").instantiate() as Main
	add_child(game)
	await wait_physics_frames(2)


func _set_of(arena_ids: Array, goal: StringName, keep := false, duration := 1.0) -> StageSet:
	var set := StageSet.new()
	set.id = &"test_set"
	set.keep_position = keep
	var defs: Array[Resource] = []
	for a: String in arena_ids:
		var s := StageDef.new()
		s.arena = load("res://levels/arenas/%s.tres" % a) as ArenaDef
		s.duration = duration
		s.goal = goal
		defs.append(s)
	set.stages = defs
	return set


func _wait(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await wait_physics_frames(1)
	return cond.call()


# --- The question --------------------------------------------------------------

func test_the_takes_are_three_different_stage_sets() -> void:
	var f := ChangeDB.get_fork(&"stages")
	assert_not_null(f)
	assert_eq(f.options, TAKES)
	assert_true(f.mockup, "shown as stills")
	assert_eq(f.bump, GameVersion.MINOR, "a maturity step")
	assert_eq(f.genre, &"topdown")
	assert_eq(f.play_runs, 6)
	assert_eq(f.requires_forks, [&"look_1", &"fork_enemy"] as Array[StringName])
	var sets: Array[StageSet] = []
	for id in TAKES:
		var c := ChangeDB.get_change(id)
		assert_eq(c.kind, &"stages")
		assert_not_null(c.take.image, "%s has its still" % id)
		assert_eq((c.take.preset as StageSet).problems(), [] as Array[String], String(id))
		sets.append(c.take.preset as StageSet)
	for s in sets:
		assert_eq(s.size(), 3, "three stages each")
	var g := sets[0]
	var sh := sets[1]
	var b := sets[2]
	assert_eq(range(3).map(func(i: int) -> StringName: return g.stage(i).arena.id), [&"arena_0", &"arena_1", &"arena_2"])
	assert_true(range(3).all(func(i: int) -> bool: return g.stage(i).goal == StageDef.SURVIVE))
	# Shifting: one yard, its frame fixed, its middle moving.
	assert_true(sh.keep_position)
	var frame := sh.stage(0).arena.blocks.slice(0, 8)
	for i in 3:
		assert_eq(sh.stage(i).arena.blocks.slice(0, 8), frame, "the same frame in stage %d" % i)
	assert_ne(sh.stage(0).arena.blocks, sh.stage(1).arena.blocks)
	assert_ne(sh.stage(1).arena.blocks, sh.stage(2).arena.blocks)
	# Breakout: an exit every stage.
	assert_true(range(3).all(func(i: int) -> bool: return b.stage(i).goal == StageDef.EXIT))
	assert_false(g.keep_position or b.keep_position)


func test_the_question_waits_for_the_look_the_enemy_and_six_runs() -> void:
	_live(5)
	assert_false(ChangeDB.get_fork(&"stages") in DevSession.ready_forks(), "5 shooter runs")
	SaveGame.record_run(&"topdown", &"lose", 60.0, SaveGame.state().taste)
	assert_true(ChangeDB.get_fork(&"stages") in DevSession.ready_forks(), "6 shooter runs")
	SaveGame.unship(&"enemy_tank")
	assert_false(ChangeDB.get_fork(&"stages") in DevSession.ready_forks(), "the enemy question first")


func test_shipping_a_take_writes_the_step_and_every_later_run_plays_it() -> void:
	_live(6)
	assert_eq(StageSet.for_run().id, &"single", "before the step: the one-arena run")
	assert_eq(SaveGame.genre_entry(&"topdown").step, "playable")
	var s := DevSession.plan(3)
	assert_eq(s.fork.id, &"stages")
	var ids: Array = s.cards.map(func(c: Dictionary) -> String: return c.id)
	assert_true(s.pick(ids.find("stages_shifting")))
	assert_eq(SaveGame.genre_entry(&"topdown").step, "stages")
	assert_eq(SaveGame.version().label(), "v0.2.0", "a minor bump")
	assert_eq(StageSet.for_run().id, &"shifting")
	assert_has(s.notes_lines(), "    New run: Shifting, 3 stages")
	# A rework swaps the run's flavour and keeps the step.
	SaveGame.record_run(&"topdown", &"lose", 60.0, SaveGame.state().taste)
	var r := DevSession.plan(4)
	assert_true(r.can_rework())
	assert_true(r.rework(&"stages", &"stages_breakout"))
	assert_eq(StageSet.for_run().id, &"breakout")
	assert_eq(SaveGame.genre_entry(&"topdown").step, "stages", "a maturity step never goes back")
	# Inert (tests, bots, the parked build): the one-arena run.
	SaveGame.go_inert()
	assert_eq(StageSet.for_run().id, &"single")


func test_a_live_game_builds_the_shipped_take() -> void:
	_live(6)
	SaveGame.ship(&"stages_gauntlet", GameVersion.MINOR)
	await _start(5, null)
	assert_eq(game.run_loop.stages.id, &"gauntlet")
	assert_eq(game.arena.def.id, &"arena_0")
	assert_true("Stage 1/3" in game.hud._label.text)


# --- Breakout ------------------------------------------------------------------

func test_the_exit_opens_after_the_time_and_reaching_it_ends_the_stage() -> void:
	await _start(21, _set_of(["arena_2", "arena_1"], StageDef.EXIT))
	RunState.invincible = true
	game.director.enabled = false
	await wait_physics_frames(int(1.0 * 60) + 5)
	assert_false(game.run_loop.exit_open, "the prompt holds it shut")
	game.director.prompt_index = game.director.limit()
	assert_true(await _wait(func() -> bool: return game.run_loop.exit_open, 30))
	await wait_physics_frames(1)
	var gate := get_tree().get_first_node_in_group(ExitGate.GROUP) as ExitGate
	assert_not_null(gate)
	assert_gt(gate.steps_from(game.player.global_position), 25, "on the far side")
	assert_true("EXIT OPEN" in game.hud._label.text)
	await wait_physics_frames(30)
	assert_eq(game.run_loop.phase, RunLoop.PLAY, "open is not reached")
	game.player.global_position = gate.global_position
	assert_true(await _wait(func() -> bool: return game.run_loop.phase == RunLoop.STAGE_CLEAR, 10))
	await wait_physics_frames(2)
	assert_false(is_instance_valid(gate), "the clear sweeps the gate")
	assert_true(await _wait(func() -> bool: return game.run_loop.phase == RunLoop.PLAY, 60))
	assert_false(game.run_loop.exit_open, "the next stage starts shut")
	var events := RunState.run_log.map(func(e: Dictionary) -> StringName: return e.event)
	assert_eq(events.count(&"exit_open"), 1)
	assert_eq(events.count(&"exit_reached"), 1)


## The gate's walking field leads to it from anywhere walkable, in every Breakout arena.
func test_the_way_to_the_gate_is_found_around_every_block() -> void:
	for stage in (ChangeDB.get_change(&"stages_breakout").take.preset as StageSet).stages:
		var arena := Arena.new((stage as StageDef).arena)
		add_child_autofree(arena)
		var walker := Node2D.new()
		add_child_autofree(walker)
		walker.global_position = arena.player_start
		var gate := ExitGate.new()
		add_child_autofree(gate)
		gate.setup(arena, walker)
		for from: Vector2 in [arena.player_start] + arena.spawn_points:
			var p := from
			var steps := 0
			while p.distance_to(gate.global_position) > ExitGate.RADIUS * Tuning.TILE and steps < 2000:
				p += gate.direction_from(p) * 8.0
				steps += 1
			assert_lt(steps, 2000, "%s: from %s" % [arena.def.id, from])


func test_the_bot_walks_out_of_a_breakout_run() -> void:
	await _start(22, _set_of(["arena_2", "arena_0"], StageDef.EXIT))
	RunState.invincible = true
	game.player.set_bot(true)
	game.director.enabled = false
	game.director.prompt_index = 99
	assert_true(await _wait(func() -> bool: return game.run_loop.phase == RunLoop.RELEASE_CANDIDATE, 60 * 60),
			"two exits reached within a minute")
	assert_eq(game.run_loop.stage_index, 1)


# --- Shifting ------------------------------------------------------------------

func test_shifting_keeps_the_player_where_it_stands_unless_a_block_moves_in() -> void:
	await _start(23, _set_of(["arena_3a", "arena_3b", "arena_3c"], StageDef.SURVIVE, true))
	RunState.invincible = true
	game.director.enabled = false
	game.director.prompt_index = 99
	var spot := Vector2(10.5, 11.5) * Tuning.TILE   # clear in every layout
	game.player.global_position = spot
	assert_true(await _wait(func() -> bool: return game.run_loop.stage_index == 1, 200))
	assert_eq(game.player.global_position, spot, "it stays put while the middle moves")
	assert_eq(game.arena.def.id, &"arena_3b")
	# Free in 3b, inside 3c's second stair: the next layout moves the player to its start.
	var stair := Vector2(26.5, 9.5) * Tuning.TILE
	assert_gte(game.arena.distance_to_blocks(stair), Tuning.TILE * 0.5)
	game.player.global_position = stair
	assert_true(await _wait(func() -> bool: return game.run_loop.stage_index == 2, 200))
	assert_eq(game.arena.def.id, &"arena_3c")
	assert_eq(game.player.global_position, game.arena.player_start, "a block moved in: back to the start")
