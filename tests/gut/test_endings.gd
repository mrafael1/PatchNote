extends GutTest
## M47.6c1 (PLAN v9.4 0.8, design 2.6 and 3): Stage 1's endings. A `clear` session ends when
## its fixed set is dead (the spawner's budget spent, no `at` / `kills` spawn cue to come,
## nobody alive), a `script` session a quiet tail after its script is done; the last few of a
## set come to you; no campaign HUD shows goal text; S4's walls grow in from the middle out.


func after_each() -> void:
	CampaignDB.active = false
	SaveGame.go_inert()
	Look.use(Unlocks.FULL_LOOK)
	RunState.invincible = false
	RunState.reset(0)
	RunState.world = null


## The game scene playing session `id` on the in-memory save (its enemy fork answered first).
func _game(id: StringName) -> Main:
	SaveGame.go_inert()
	CampaignDB.answer_fork(&"fork_enemy", &"enemy_bomber")
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	if game.stage_card != null:
		game.stage_card.skip()
	await wait_physics_frames(2)
	RunState.invincible = true
	return game


func _kill_all() -> void:
	for e in get_tree().get_nodes_in_group(&"enemy"):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			e.queue_free()


# --- The data -------------------------------------------------------------------------

func test_stage_1_plays_endings_and_no_session_lists_a_goal_text() -> void:
	var want := {&"s1_00_nothing": [SessionDef.SCRIPT], &"s1_01_move": [SessionDef.SCRIPT],
			&"s1_02_enemies": [SessionDef.OVERRUN], &"s1_03_shooting": [SessionDef.CLEAR],
			&"s1_04_level": [SessionDef.CLEAR], &"s1_05_wrong": [SessionDef.CLEAR, SessionDef.SCRIPT],
			&"s1_06_playground": [SessionDef.CLEAR]}
	for id: StringName in want:
		var s := CampaignDB.get_session(id)
		assert_eq(s.end_kinds(), want[id] as Array[StringName], String(id))
		assert_eq(s.problems(), [] as Array[String], String(id))
	assert_eq(CampaignDB.get_session(&"s1_00_nothing").end_after, 5.0, "about 12 s (7 + 5)")
	assert_eq(CampaignDB.get_session(&"s2_01_tryout").enemy_total, -1, "S7 keeps no budget in M47.6c1")


## A clear session shaped like S3 (a new resource each time: the parse is cached).
func _clear(cues: Array, total := 0) -> SessionDef:
	var s := SessionDef.new()
	s.id = &"x"
	s.title = "x"
	s.goal = SessionDef.CLEAR
	s.basics = [&"movement", &"enemies"]
	s.enemies = [&"chaser"]
	s.enemy_total = total
	s.cues = PackedStringArray(cues)
	return s


func _has(s: SessionDef, words: String) -> bool:
	return s.problems().any(func(p: String) -> bool: return p.contains(words))


func test_the_ending_lints() -> void:
	assert_eq(_clear(["at 1: spawn chaser 2", "kills 2: spawn chaser 1"]).problems(), [] as Array[String],
			"S3's shape: the third on the second kill")
	assert_true(_has(_clear(["at 1: spawn chaser 2", "kills 3: spawn chaser 1"]), "can never fire"), "a kills cue past the set")
	assert_true(_has(_clear([], -1), "enemy_total >= 0"))
	var s := _clear([], 5)
	s.end_line = "happy: Done."
	assert_true(_has(s, "end_line needs a script"))
	s = _clear([], 5)
	s.ends = [SessionDef.SCRIPT] as Array[StringName]
	assert_true(_has(s, "must list the goal"))
	s = _clear([], 5)
	s.spawn_weights = {&"fork:fork_enemy": 0.5, &"shooter": 0.6}
	assert_true(_has(s, "sum below 1"))
	s = _clear([], 5)
	s.spawn_weights = {&"fork:fork_enemy": 0.4}
	assert_eq(s.problems(), [] as Array[String], "a fork key is a weight too")


# --- The spawner's budget and weights --------------------------------------------------

func test_a_budget_counts_only_the_spawners_own_draws() -> void:
	var game := await _game(&"s1_06_playground")
	var sp := game.spawner
	assert_eq(sp.budget, 28)
	sp.budget = sp.spawned + 2
	sp.spawn_one()
	sp.spawn_one()
	assert_true(sp.budget_spent())
	var drawn := sp.spawned
	game.genre.spawn_archetype(&"chaser", 3)
	assert_eq(sp.spawned, drawn, "a cue spawn never counts")
	await wait_physics_frames(240)
	assert_eq(sp.spawned, drawn, "a spent spawner draws nothing more")


func test_no_budget_set_on_a_session_without_one() -> void:
	var game := await _game(&"s1_02_enemies")
	assert_eq(game.spawner.budget, -1)
	assert_false(game.spawner.budget_spent())
	assert_false(game.run_loop.wave_closed(), "no set: never closed")


## v6 (no session) for 120 game seconds from seed 4242, director off, invincible: the enemies
## spawned and the gameplay_rng position. V6_120S was measured with this same body on M47.6b's
## tree (before the budget and the weights), so a budget -1 spawner that reads the weights or
## makes an extra draw fails here, not only in the v6 hash gate.
const V6_120S := {"enemies": 25, "rng_state": "1609827389387231186"}
const V6_LOG := "user://test_endings_v6.jsonl"


func test_no_budget_spawns_as_before() -> void:
	Telemetry.log_path = V6_LOG
	CampaignDB.active = false
	Main.next_seed = 4242
	var enemies := [0]
	var count := func(e: Node) -> void:
		if e.get(&"kind") == &"enemy":
			enemies[0] += 1
	EventBus.entity_spawned.connect(count)
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.director.enabled = false
	RunState.invincible = true
	var budget: Variant = game.spawner.get(&"budget")   # read by name: the same body ran on M47.6b
	var weights: Variant = game.spawner.get(&"weights")
	assert_true(budget == null or budget == -1, "budget -1")
	assert_true(weights == null or (weights as Dictionary).is_empty(), "no weights")
	await wait_physics_frames(7200)
	EventBus.entity_spawned.disconnect(count)
	var got := {"enemies": enemies[0], "rng_state": str(RunState.gameplay_rng.state)}
	gut.p("v6 120 s: %s (game time %.2f)" % [got, RunState.game_time])
	assert_gt(enemies[0], 10, "the spawner ran")
	assert_eq(got, V6_120S, "the same spawns and the same RNG position as before M47.6c1")
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	if FileAccess.file_exists(V6_LOG):
		DirAccess.remove_absolute(V6_LOG)


func test_weights_take_the_roll_first_and_skip_the_delays() -> void:
	var sp := Spawner.new()
	sp.weights = {&"bomber": 0.4}
	RunState.gameplay_rng.seed = 7
	var picks: Array[StringName] = []
	for i in 200:
		picks.append(sp.pick_type())
	var bombers := picks.filter(func(p: StringName) -> bool: return p == &"bomber").size()
	assert_between(bombers, 55, 105, "about 40 %, from the first second (no bomber delay)")
	# Outside the weight the roll is stretched over today's chances, whose bomber delay holds.
	RunState.gameplay_rng.seed = 7
	for i in 200:
		var roll := RunState.gameplay_rng.randf()
		if roll >= 0.4:
			assert_ne(picks[i], &"bomber", "roll %.3f: today's chances, the bomber delay holds" % roll)
	sp.free()


# --- Clear ------------------------------------------------------------------------------

func test_s3_clears_on_its_third_kill_never_in_between() -> void:
	var game := await _game(&"s1_03_shooting")
	var loop := game.run_loop
	assert_eq(game.session_runner.pending_spawns(), 3)
	assert_false(loop.wave_closed(), "budget 0 is spent, but the cues are still to come")
	loop.goal_clock = 1.0
	await wait_physics_frames(3)
	assert_eq(RunState.count(&"enemy"), 2, "the two at 0.5 s")
	assert_eq(game.session_runner.pending_spawns(), 1, "the one on the second kill")
	_kill_all()
	RunState.kills = 2
	await wait_physics_frames(1)
	assert_false(loop.is_over(), "the kills 2 spawn fires before the cleared check")
	await wait_physics_frames(2)
	assert_eq(RunState.count(&"enemy"), 1, "the third")
	assert_true(loop.wave_closed())
	assert_true(RunState.wave_closed)
	assert_true(RunState.survivors_chase, "three or fewer left: they come to you")
	# A spawn still entering the tree (a splitter's child) holds the clear.
	_kill_all()
	RunState.spawn(Spawner.SCENES[&"chaser"], game.arena.player_start + Vector2(400, 0))
	assert_eq(RunLoop.enemies_left(), 1)
	assert_false(loop.cleared())
	await wait_physics_frames(2)
	assert_false(loop.is_over())
	_kill_all()
	RunState.kills = 3
	await wait_physics_frames(2)
	assert_true(loop.is_over())
	assert_eq(loop.outcome, &"win")
	assert_eq(loop.end_reason, &"cleared")
	assert_eq([loop.record.end, loop.record.enemy_total, loop.record.spawned], ["cleared", 0, 0])
	await wait_physics_frames(int(Tuning.report_delay * 60) + 5)
	assert_eq(game.debrief.outcome, &"won")


func test_a_clear_sessions_cap_is_hidden_and_stops_it() -> void:
	var game := await _game(&"s1_03_shooting")
	assert_eq(game.hud.goal_shown(), "")
	game.run_loop.goal_clock = 120.0
	await wait_physics_frames(2)
	assert_eq(game.run_loop.outcome, RunLoop.STOPPED)
	assert_eq(game.run_loop.end_reason, &"limit")


# --- Script ------------------------------------------------------------------------------

func test_s5_ends_a_quiet_tail_after_its_script_and_waits_for_the_event() -> void:
	var game := await _game(&"s1_05_wrong")
	var loop := game.run_loop
	game.session_runner.drop_cues(&"event")   # the gravity's 19 s: held by hand below instead
	loop.hold_goal(&"test_event", true)
	loop.goal_clock = 21.0
	await wait_physics_frames(3)
	assert_false(loop.script_done(), "an event holding the goal holds the script")
	assert_lt(loop.script_done_at, 0.0)
	loop.hold_goal(&"test_event", false)
	await wait_physics_frames(2)
	assert_gte(loop.script_done_at, 0.0, "every at cue fired and nothing holds it")
	assert_false(game.spawner.enabled, "the tail is quiet: no new wave to cut")
	var texts := game.session_runner.said + game.session_runner.queued_lines().map(func(l: Line) -> String: return l.text)
	assert_has(texts, "Okay. That's the test.", "the AI calls the end")
	RunState.game_time = loop.script_done_at + 4.4
	await wait_physics_frames(1)
	assert_false(loop.is_over(), "4.5 game seconds")
	RunState.game_time = loop.script_done_at + 4.5
	await wait_physics_frames(2)
	assert_eq([loop.outcome, loop.end_reason], [RunLoop.STOPPED, &"script"])


## Review (M47.6c1): S5's set (10 drawn + 8 from cues) is all in before 20 s, so most players
## clear it under the gravity. The release tick must not end it there (cutting the event's
## last line and skipping end_line and the quiet tail): the script window opens instead, and
## the session ends won (cleared) end_after later.
func test_s5_cleared_under_the_gravity_still_gets_its_tail() -> void:
	var game := await _game(&"s1_05_wrong")
	var loop := game.run_loop
	game.session_runner.drop_cues(&"event")   # the gravity, held by hand below
	loop.hold_goal(&"test_event", true)
	loop.goal_clock = 21.0   # every at cue fires (the 8 cue enemies)
	await wait_physics_frames(3)
	game.spawner.budget = game.spawner.spawned   # the 10 drawn
	_kill_all()
	await wait_physics_frames(2)
	assert_true(loop.cleared(), "the set is dead under the gravity")
	assert_false(loop.is_over(), "the event holds the goal")
	assert_eq(RunState.run_log.filter(func(e: Dictionary) -> bool: return e.get("event") == &"goal_waited").size(), 1)
	loop.hold_goal(&"test_event", false)   # the gravity is fixed: "There. Speed was..." is said now
	await wait_physics_frames(2)
	assert_false(loop.is_over(), "not on the release tick")
	assert_gte(loop.script_done_at, 0.0, "the script window opened at the release")
	var texts := game.session_runner.said + game.session_runner.queued_lines().map(func(l: Line) -> String: return l.text)
	assert_has(texts, "Okay. That's the test.", "the AI still calls the end")
	RunState.game_time = loop.script_done_at + loop.end_after - 0.1
	await wait_physics_frames(1)
	assert_false(loop.is_over(), "the quiet tail runs")
	RunState.game_time = loop.script_done_at + loop.end_after
	await wait_physics_frames(2)
	assert_eq([loop.outcome, loop.end_reason], [&"win", &"cleared"])


func test_s0_ends_five_seconds_after_its_last_line() -> void:
	var game := await _game(&"s1_00_nothing")
	game.run_loop.goal_clock = 7.0
	await wait_physics_frames(2)
	assert_gte(game.run_loop.script_done_at, 0.0)
	assert_false(game.run_loop.is_over())
	RunState.game_time = game.run_loop.script_done_at + 5.0
	await wait_physics_frames(2)
	assert_eq(game.run_loop.outcome, RunLoop.STOPPED)
	await wait_physics_frames(int(Tuning.report_delay * 60) + 5)
	assert_eq(game.debrief.outcome, &"stopped", "its debrief line reads stopped")


# --- The last few, the reactions -------------------------------------------------------------

func test_the_set_called_and_the_last_few_come_to_you() -> void:
	var game := await _game(&"s1_06_playground")
	var sp := game.spawner
	sp.budget = sp.spawned   # spent
	game.genre.spawn_archetype(&"shooter", 5)
	await wait_physics_frames(3)
	assert_true(RunState.wave_closed)
	assert_false(RunState.survivors_chase, "five left: not yet")
	var r := game.reactions
	r.set(&"_busy_until", -1.0)
	r.tick()
	assert_has(r.fired_ids(), "wave_done", "That's all of them.")
	var shooters := get_tree().get_nodes_in_group(&"enemy").filter(func(e: Node) -> bool: return not e.is_queued_for_deletion())
	shooters[0].queue_free()
	shooters[1].queue_free()
	shooters[2].queue_free()
	await wait_physics_frames(2)
	assert_true(RunState.survivors_chase, "three left (latched)")
	r.set(&"_busy_until", -1.0)
	r.tick()
	assert_has(r.fired_ids(), "last_two")
	assert_false(game.run_loop.is_over())


func test_the_progress_reads_the_fixed_set() -> void:
	var game := await _game(&"s1_06_playground")
	RunState.kills = 14
	assert_almost_eq(game.reactions._progress(), 0.5, 0.001, "14 of 28")


# --- No goal text --------------------------------------------------------------------------

func test_no_campaign_hud_shows_goal_text() -> void:
	for id: StringName in [&"s1_00_nothing", &"s1_02_enemies", &"s1_03_shooting", &"s1_04_level",
			&"s1_05_wrong", &"s1_06_playground"]:
		var game := await _game(id)
		await wait_physics_frames(2)
		assert_eq(game.hud.goal_shown(), "", String(id))
		remove_child(game)
		game.free()
	SaveGame.go_inert()
	assert_true(CampaignDB.answer_fork(&"fork_path", &"path_arsenal"))
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(&"s2_02_day_one"))
	var s8: Main = load("res://main.tscn").instantiate()
	add_child_autofree(s8)
	await wait_physics_frames(3)
	assert_eq(s8.run_loop.goal, SessionDef.SURVIVE, "S8 still survives in M47.6c1")
	assert_ne(s8.run_loop.goal_text(), "", "the run loop still has its text")
	assert_eq(s8.hud.goal_shown(), "", "but no campaign HUD shows it (no survive timer)")


# --- S4: the walls grow in --------------------------------------------------------------------

func test_s4_walls_grow_from_the_middle_out() -> void:
	var game := await _game(&"s1_04_level")
	var arena := game.arena
	var def := arena.def
	assert_eq(arena.blocks.size(), 4, "the border only: the level is the 0.8 s cue")
	assert_true(arena.stripped())
	# The block that grows last: a tile inside it is open (and reachable) now.
	var t := Tuning.TILE
	var full: Array[Rect2] = []
	for r in def.blocks:
		full.append(Rect2(r.position * t, r.size * t))
	var centre := arena.bounds.get_center()
	full.sort_custom(func(a: Rect2, b: Rect2) -> bool:
		return a.get_center().distance_squared_to(centre) < b.get_center().distance_squared_to(centre))
	var last := full[-1]
	var inside := last.position + Vector2(t, t) * 0.5
	assert_true(arena.is_reachable(inside), "open before the growth")
	# The player stands where the first block will land: it is pushed out.
	game.player.global_position = full[0].get_center()
	game.run_loop.goal_clock = 0.8
	await wait_physics_frames(2)
	assert_true(arena.growing())
	await wait_physics_frames(30)
	assert_gte(arena.distance_to_blocks(game.player.global_position), t * 0.45, "pushed to a free tile")
	assert_lt(arena.blocks.size(), 4 + def.blocks.size(), "still growing at 1.3 s")
	await wait_physics_frames(150)
	assert_false(arena.growing())
	assert_eq(arena.blocks.size(), 4 + def.blocks.size(), "every block of the layout")
	for i in range(5, arena.blocks.size()):
		assert_lte(snappedf(arena.blocks[i - 1].get_center().distance_squared_to(centre), 0.01),
				snappedf(arena.blocks[i].get_center().distance_squared_to(centre), 0.01), "middle out")
	assert_false(arena.is_reachable(inside), "a teleport never lands in a grown block (the reach map is rebuilt)")
	assert_eq(game.arena.get_node(^"Blocks").get_child_count(), 4 + def.blocks.size(), "each block has its collision")


func test_a_teleport_mid_growth_never_lands_in_a_block() -> void:
	var game := await _game(&"s1_04_level")
	var arena := game.arena
	game.run_loop.goal_clock = 0.8
	await wait_physics_frames(60)
	assert_true(arena.growing(), "mid-growth")
	var t := Tuning.TILE
	for r in Arena.ROWS:
		for c in Arena.COLS:
			var p := (Vector2(c, r) + Vector2(0.5, 0.5)) * t
			if arena.is_reachable(p):
				assert_gt(arena.distance_to_blocks(p), 0.0, "reachable tile %s is inside a grown block" % [Vector2i(c, r)])
	await wait_physics_frames(150)
	for r in Arena.ROWS:
		for c in Arena.COLS:
			var p := (Vector2(c, r) + Vector2(0.5, 0.5)) * t
			if arena.is_reachable(p):
				assert_gt(arena.distance_to_blocks(p), 0.0)
