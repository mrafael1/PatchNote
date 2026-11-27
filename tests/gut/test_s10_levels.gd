extends GutTest
## M50.3c (PLAN v9 1.8, 1.9, 3.2 S10): S10 "Level one". The session as data (the last one;
## S9 asks fork_layout), the layout answer picking the stage set, a level played in three
## parts on enemy counts (the budget per part, the stage-clear beat, the next arena, the
## door of the rooms layout, the hidden cap), `room N [at s]` cues, the three new enemies
## (the shielder's front, the sniper's locked line and fast shot, the swarm's pack),
## edit_hot_edges, each path's basics and launcher, the known pool, and what must not move
## (a one-arena session, the enemy sprites' id list). Every game is jumped to on an inert
## save; time is moved, never waited on, and nothing waits while a debrief is open.

const TEST_LOG := "user://save_s10_levels_test/runs.jsonl"
const S10 := &"s2_04_levels"
const S9 := &"s2_03_paint"
const PATHS: Array[StringName] = [&"arsenal", &"auto", &"survival"]
const LAYOUTS := {&"layout_rooms": &"breakout", &"layout_gauntlet": &"gauntlet", &"layout_shifting": &"shifting"}

var game: Main


func before_each() -> void:
	Telemetry.log_path = TEST_LOG
	Skins.disabled = false
	Skins.use(null)


func after_each() -> void:
	await wait_physics_frames(2)   # deferred spawns land before the game is freed
	assert_false(FileAccess.file_exists(TEST_LOG), "no telemetry written")
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.invincible = false
	CampaignDB.active = false
	SaveGame.go_inert()
	Skins.disabled = false
	Skins.use(null)
	RunState.reset(0)
	RunState.world = null


func _jump(id: StringName, p: StringName, layout: StringName, invincible: bool) -> Main:
	SaveGame.go_inert()
	assert_true(CampaignDB.answer_fork(&"fork_path", StringName("path_%s" % p)))
	if layout != &"":
		assert_true(CampaignDB.answer_fork(&"fork_layout", layout))
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var g: Main = load("res://main.tscn").instantiate()
	add_child_autofree(g)
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	game = g
	RunState.invincible = invincible
	return g


func _s10(p: StringName = &"arsenal", layout: StringName = &"layout_gauntlet", invincible := true) -> Main:
	return await _jump(S10, p, layout, invincible)


func _at(seconds: float) -> void:
	game.run_loop.goal_clock = seconds - 0.01
	await wait_physics_frames(3)


func _quiet() -> void:
	game.spawner.enabled = false
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()
	await wait_physics_frames(3)


## This part's share is out and dead: its budget spent, its room cues fired, nobody left.
func _finish_part() -> void:
	var loop := game.run_loop
	game.spawner.spawned = game.spawner.budget
	loop.stage_started_at = RunState.game_time - 200.0
	await wait_physics_frames(4)
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()
	await wait_physics_frames(4)


func _skip_beat() -> void:
	game.run_loop._clear_until = RunState.game_time
	await wait_physics_frames(3)


func _variant(id: StringName) -> Array:
	return get_tree().get_nodes_in_group(&"enemy").filter(func(e: Node) -> bool:
		return e.get(&"variant") == id and not e.is_queued_for_deletion())


# --- Data ----------------------------------------------------------------------------------

func test_s10_is_the_last_session_and_s9_asks_the_layout() -> void:
	assert_eq(CampaignDB.index_of(S10), 10)
	assert_eq(CampaignDB.size(), 12, "M51: S11 follows S10")
	var s := CampaignDB.get_session(S10)
	assert_eq(s.problems(), [] as Array[String])
	assert_eq(CampaignDB.problems(), [] as Array[String], "nothing in the campaign is unbuilt or wrong")
	assert_eq([s.title, s.stage, s.goal, s.stages, s.fork, s.bump], ["Level one", 2, SessionDef.CLEAR,
			&"fork:fork_layout", &"", &"patch"])
	assert_eq(s.weapons, [&"pistol", &"shotgun", &"laser", &"launcher"] as Array[StringName])
	assert_eq(s.known, [&"shotgun", &"laser", &"nova"] as Array[StringName])
	assert_eq(s.enemies, CampaignDB.get_session(S9).enemies, "S9's three; the new ones come by cue")
	assert_true(s.fresh_start)
	assert_gt(s.time_limit, 0.0, "a hidden cap")
	for p in PATHS:
		assert_gt(s.enemy_total_for(p), 0, String(p))
	assert_eq(Array(s.notes), ["Levels, in three parts", "The launcher", "Three new enemies (all of them stay)"])
	assert_eq(CampaignDB.get_session(S9).fork, &"fork_layout", "S9's debrief asks the shape")
	# The three enemies, one per part, in order, each with its line; the edit in part 3.
	var spawns: Array = []
	var edits: Array = []
	for c in s.cue_list():
		assert_eq(c.problem, "", c.source)
		if c.action == &"spawn":
			spawns.append([int(c.value), String(c.archetype)])
			assert_eq(c.when, &"room", c.source)
		elif c.action == &"edit":
			edits.append([String(c.when), int(c.value), String(c.target)])
	assert_eq(spawns[0], [1, "shielder"])
	assert_true([2, "sniper"] in spawns and [3, "swarm"] in spawns)
	assert_true([2, "shielder"] in spawns and [3, "shielder"] in spawns and [3, "sniper"] in spawns, "all three stay")
	assert_false([1, "sniper"] in spawns or [1, "swarm"] in spawns or [2, "swarm"] in spawns, "announced in order")
	assert_eq(edits, [["room", 3, "edit_hot_edges"]])
	var text := " | ".join(Array(s.cues))
	for line in ["It has a shield. Go around it.", "Don't stand on the red line.", "Number three is five tiny ones!",
			"at 4: give launcher", "answer:path_auto at 0: add evolve", "answer:path_arsenal at 0: add fusion",
			"answer:path_auto at 12 [haste]: say thinking: Your passives are back. Haste first.",
			"answer:path_auto at 20 [area]: say happy: Area too. Launcher blasts get bigger.",
			"say made:cluster proud: A Cluster! Shells full of shells."]:
		assert_string_contains(text, line)


func test_fork_layout_is_campaign_data_on_the_v6_sets() -> void:
	var f := ChangeDB.get_fork(&"fork_layout")
	assert_not_null(f)
	assert_true(f.campaign)
	assert_eq(f.options, [&"layout_rooms", &"layout_gauntlet", &"layout_shifting"] as Array[StringName])
	for id: StringName in LAYOUTS:
		var c := ChangeDB.get_change(id)
		assert_eq(ChangeDB.problems(c), [] as Array[String], String(id))
		assert_eq([c.kind, c.genre], [&"layout", &""])
		assert_eq((c.take.preset as StageSet).id, LAYOUTS[id])
		assert_eq((c.take.preset as StageSet).size(), 3)
	var bad := Change.new()
	bad.id = &"layout_probe"
	bad.kind = &"layout"
	assert_string_contains(str(ChangeDB.problems(bad)), "no take with a stage set")
	# The v6 stages fork is never a campaign fork, and no session names it.
	var v6 := ChangeDB.get_fork(&"stages")
	assert_true(v6 == null or not v6.campaign)
	for i in CampaignDB.size():
		var s := CampaignDB.session(i)
		assert_false(&"stages" in s.asked_forks() or &"stages" in s.fork_refs(), String(s.id))


func test_the_layout_answer_picks_the_stage_set() -> void:
	var s := CampaignDB.get_session(S10)
	SaveGame.go_inert()
	assert_eq(s.stage_set().id, &"breakout", "unanswered (an old save, a jump): the first option")
	for id: StringName in LAYOUTS:
		SaveGame.go_inert()
		assert_true(CampaignDB.answer_fork(&"fork_layout", id))
		assert_eq(s.stage_set().id, LAYOUTS[id])
		assert_eq(s.arena_def(), s.stage_set().stage(0).arena, "the session's arena is its first part's")
	SaveGame.go_inert()
	assert_null(CampaignDB.get_session(S9).stage_set(), "a one-arena session has none")
	var probe := SessionDef.new()
	probe.id = &"probe"
	probe.stages = &"gauntlet"
	probe.goal = SessionDef.SURVIVE
	assert_string_contains(str(probe.problems()), "goal stages and a stage set go together")
	probe.goal = SessionDef.CLEAR
	probe.enemy_total = 9
	assert_false("go together" in str(probe.problems()))
	assert_eq(probe.stage_set().id, &"gauntlet")


func test_room_cues_are_built() -> void:
	var c := Cue.parse("room 2 at 5: spawn sniper 2")
	assert_eq([c.problem, c.unbuilt(), c.when, int(c.value), c.at_seconds], ["", "", &"room", 2, 5.0])
	assert_false(c.due({"room": 1, "room_clock": 50.0}))
	assert_false(c.due({"room": 2, "room_clock": 4.9}))
	assert_true(c.due({"room": 2, "room_clock": 5.0}))
	assert_false(c.due({"room": 2, "room_clock": -1.0}), "not during the beat between two parts")
	assert_ne(Cue.parse("boss_hp 50: say happy: x").unbuilt(), "", "boss_hp is still unbuilt")


# --- Parts ---------------------------------------------------------------------------------

func test_a_level_plays_in_three_parts_on_enemy_counts() -> void:
	await _s10(&"arsenal", &"layout_gauntlet")
	var loop := game.run_loop
	var set := loop.stages
	assert_true(loop.in_parts())
	assert_eq([set.id, set.size()], [&"gauntlet", 3])
	var total := CampaignDB.get_session(S10).enemy_total_for(&"arsenal")
	assert_eq(loop.enemy_total, total)
	assert_eq([loop.part_budget(0), loop.part_budget(1), loop.part_budget(2)],
			[roundi(total / 3.0), roundi(total * 2.0 / 3.0), total])
	assert_eq(game.spawner.budget, loop.part_budget(0), "part 1 draws a third of the set")
	assert_eq(game.session_runner.room(), 1)
	assert_eq(game.arena.def, set.stage(0).arena)
	assert_almost_eq(game.spawner.phase_rate, set.stage(0).spawn_rate * 1.3, 0.001, "the session's rate on the part's")
	assert_false(loop.part_closed(), "budget left")
	game.spawner.spawned = game.spawner.budget
	await wait_physics_frames(2)
	assert_false(loop.part_closed(), "this part's room cues are still to fire")
	assert_eq(loop.phase, RunLoop.PLAY)
	await _finish_part()
	assert_eq(loop.phase, RunLoop.STAGE_CLEAR, "its share dead: the beat")
	assert_eq(game.session_runner.room_clock(), -1.0)
	assert_eq(_variant(&"shielder").size(), 0, "the field is swept")
	var clock := loop.goal_clock
	await _skip_beat()
	assert_eq([loop.phase, loop.stage_index, game.session_runner.room()], [RunLoop.PLAY, 1, 2])
	assert_eq(game.arena.def, set.stage(1).arena, "the next arena")
	assert_eq(game.spawner.budget, loop.part_budget(1))
	assert_almost_eq(loop.goal_clock, clock, 0.1, "the beat is not on the session clock")
	assert_false(RunState.wave_closed or RunState.survivors_chase, "a new part: nobody is hunted yet")
	assert_eq(get_tree().get_nodes_in_group(ExitGate.GROUP).size(), 0, "a gauntlet has no door")
	await _finish_part()
	await _skip_beat()
	assert_eq(loop.stage_index, 2)
	assert_eq(game.spawner.budget, total)
	assert_false(loop.is_over())
	await _finish_part()
	assert_true(loop.is_over(), "the last part cleared: won")
	assert_eq([loop.outcome, loop.end_reason], [&"win", &"cleared"])
	assert_eq([loop.record.stages.set, loop.record.stages.total, loop.record.stages.reached], ["gauntlet", 3, 3])
	assert_eq(loop.record.end, "cleared")


func test_the_rooms_layout_opens_a_door_and_waits_for_the_player() -> void:
	await _s10(&"arsenal", &"layout_rooms")
	var loop := game.run_loop
	assert_eq(loop.stages.id, &"breakout")
	await _finish_part()
	assert_eq(loop.phase, RunLoop.PLAY, "cleared, but the door is still to reach")
	assert_true(loop.exit_open)
	var gates := get_tree().get_nodes_in_group(ExitGate.GROUP)
	assert_eq(gates.size(), 1)
	var snap := RailState.read(game, {})
	assert_eq(snap.parts, {"part": 1, "of": 3, "door": true})
	await wait_physics_frames(30)
	assert_eq(loop.stage_index, 0, "it waits")
	game.player.global_position = (gates[0] as Node2D).global_position
	await wait_physics_frames(3)
	assert_eq(loop.phase, RunLoop.STAGE_CLEAR)
	await _skip_beat()
	assert_eq(loop.stage_index, 1)
	assert_false(loop.exit_open)
	assert_eq(get_tree().get_nodes_in_group(ExitGate.GROUP).size(), 0, "the door went with the room")
	assert_almost_eq(game.player.global_position.distance_to(game.arena.player_start), 0.0, 8.0)


func test_the_shifting_layout_keeps_the_player_in_place() -> void:
	await _s10(&"survival", &"layout_shifting")
	var loop := game.run_loop
	assert_true(loop.stages.keep_position)
	await _finish_part()
	var before := game.player.global_position
	await _skip_beat()
	assert_eq(loop.stage_index, 1)
	var kept := game.arena.distance_to_blocks(before) >= Tuning.TILE * 0.5
	assert_eq(game.player.global_position.distance_to(before) < 8.0, kept, "kept unless a new wall stands there")


func test_the_hidden_cap_ends_a_part_stopped() -> void:
	await _s10(&"arsenal", &"layout_gauntlet")
	var loop := game.run_loop
	game.spawner.enabled = false
	loop.goal_clock = loop.time_limit + 1.0
	await wait_physics_frames(3)
	assert_true(loop.is_over())
	assert_eq([loop.outcome, loop.end_reason], [RunLoop.STOPPED, &"limit"])
	assert_eq(loop.record.stages.reached, 1)


func test_only_this_parts_room_cues_hold_its_end() -> void:
	await _s10(&"arsenal", &"layout_gauntlet")
	var runner := game.session_runner
	var s := CampaignDB.get_session(S10)
	var per_room := {1: 0, 2: 0, 3: 0}
	var bodies := {1: 0, 2: 0, 3: 0}
	for c in s.cue_list():
		if c.action == &"spawn":
			per_room[int(c.value)] += c.count
			bodies[int(c.value)] += c.count * EnemyDB.variant(c.archetype).pack
	assert_eq(runner.pending_spawns(), per_room[1], "part 1 waits for its own waves only")
	game.run_loop.stage_started_at = RunState.game_time - 200.0
	await wait_physics_frames(4)
	assert_eq(runner.pending_spawns(), 0)
	assert_eq(_variant(&"shielder").size(), bodies[1])
	assert_eq(_variant(&"sniper").size() + _variant(&"swarm").size(), 0, "nothing of a later part yet")


func test_a_one_arena_session_is_not_in_parts() -> void:
	await _jump(S9, &"arsenal", &"layout_gauntlet", true)
	var loop := game.run_loop
	assert_false(loop.in_parts())
	assert_eq(loop.stages.size(), 1)
	assert_eq(game.spawner.budget, CampaignDB.get_session(S9).enemy_total_for(&"arsenal"))
	assert_eq([game.session_runner.room(), game.session_runner.room_clock()], [-1, -1.0])
	assert_eq(RailState.read(game, {}).parts, {"part": 0, "of": 0, "door": false})
	assert_eq(RunState.rules.hot_edge_tiles, 0)
	assert_eq(game.genre.hot_edges.band(), 0.0)


# --- The three enemies ---------------------------------------------------------------------

func test_the_variants_are_data_and_wear_their_base() -> void:
	assert_eq(EnemyDB.VARIANTS, [&"splitter", &"shielder", &"sniper", &"swarm"] as Array[StringName])
	for id: StringName in [&"shielder", &"sniper", &"swarm"]:
		assert_eq(EnemyDB.variant(id).problems(id), [] as Array[String], String(id))
		assert_false(id in Skins.BODY_IDS, "%s has no sprite of its own" % id)
	assert_eq([EnemyDB.base_of(&"shielder"), EnemyDB.base_of(&"sniper"), EnemyDB.base_of(&"swarm")],
			[&"tank", &"shooter", &"chaser"])
	assert_eq(EnemyDB.variant(&"shielder").shield_arc_deg, 100.0)
	assert_eq([EnemyDB.variant(&"sniper").keep_range, EnemyDB.variant(&"sniper").telegraph], [9.0, 1.0])
	assert_eq([EnemyDB.variant(&"swarm").pack, EnemyDB.variant(&"swarm").scale, EnemyDB.variant(&"swarm").speed_mult,
			EnemyDB.variant(&"swarm").min_hp], [5, 0.6, 1.6, 1.0])
	var bad := EnemyVariant.new()
	bad.id = &"probe"
	bad.base = &"shooter"
	bad.shield_arc_deg = 90.0
	assert_string_contains(str(bad.problems()), "a shield needs a walker base")
	bad.base = &"tank"
	bad.shield_arc_deg = 0.0
	bad.telegraph = 1.0
	assert_string_contains(str(bad.problems()), "a telegraph needs the shooter base")
	var tank := (load("res://entities/enemy_tank.tscn") as PackedScene).instantiate()
	tank.set(&"variant", &"shielder")
	assert_eq(Skins.id_for(tank.get_node("Visual")), &"tank")
	tank.free()


func test_the_shielder_stops_shots_on_its_front_only() -> void:
	await _s10(&"arsenal", &"layout_gauntlet")
	await _quiet()
	assert_true(game.genre.spawn_archetype(&"shielder", 1))
	await wait_physics_frames(3)
	var e: EnemyWalker = _variant(&"shielder")[0]
	e.global_position = game.player.global_position + Vector2(300, 0)
	e.set(&"_faced", false)
	await wait_physics_frames(2)
	assert_almost_eq(absf(e.facing.angle()), PI, 0.2, "it faces the player at once")   # the player is to its left
	assert_not_null(e.get_node_or_null("ShieldArc"))
	var tank_speed := Tuning.tank_speed * RunState.rules.enemy_speed_mult
	assert_almost_eq(e.mover.speed, tank_speed * 0.8, 0.01, "slower than its base")
	var hp := e.health.hp()
	var front := e.global_position + e.facing * 14.0
	var back := e.global_position - e.facing * 14.0
	assert_false(e.health.take(DamageInfo.make(1.0, &"projectile", &"player", front)), "a shot on the shield")
	assert_eq([e.blocked, RunState.shield_blocks, e.health.hp()], [1, 1, hp])
	var through := DamageInfo.make(1.0, &"projectile", &"player", front)
	through.pierces = true
	assert_true(e.health.take(through), "a piercing shot goes through")
	assert_true(e.health.take(DamageInfo.make(1.0, &"explosion", &"player", front)), "a blast is not a shot")
	assert_true(e.health.take(DamageInfo.make(1.0, &"orbit", &"player", front)))
	assert_true(e.health.take(DamageInfo.make(1.0, &"projectile", &"player", back)), "from behind")
	var side := e.global_position + e.facing.rotated(deg_to_rad(60.0)) * 14.0
	assert_true(e.health.take(DamageInfo.make(1.0, &"projectile", &"player", side)), "past the 100 degree arc")
	assert_eq(e.blocked, 1)
	# It turns at 90 degrees a second: the player jumps behind it, half a second later it has
	# turned about 45 degrees.
	var was := e.facing
	game.player.global_position = e.global_position - was * 300.0
	await wait_physics_frames(30)
	var turned := rad_to_deg(absf(was.angle_to(e.facing)))
	assert_between(turned, 35.0, 50.0, "half a second at 90 degrees a second")


func test_a_real_shot_dies_on_the_shield() -> void:
	await _s10(&"arsenal", &"layout_gauntlet")
	await _quiet()
	assert_true(game.genre.spawn_archetype(&"shielder", 1))
	await wait_physics_frames(3)
	var e: EnemyWalker = _variant(&"shielder")[0]
	e.global_position = game.player.global_position + Vector2(260, 0)
	e.set(&"_faced", false)
	await wait_physics_frames(2)
	var hp := e.health.hp()
	var shot := RunState.spawn(load("res://entities/projectile.tscn"), game.player.global_position + Vector2(60, 0), {
		&"kind": &"player_projectile", &"faction": &"player", &"velocity": Vector2(900, 0), &"damage": 1.0})
	assert_not_null(shot)
	await wait_physics_frames(25)
	assert_eq(e.blocked, 1, "the shot met the shield")
	assert_eq(e.health.hp(), hp)
	assert_false(is_instance_valid(shot) and not shot.is_queued_for_deletion(), "and stopped there")


## The bot's flank rule (BotInput.flank_step, M46's contract) reads `shield_arc_deg` and
## `facing` on the target: a live shielder must answer both, or the Arsenal and Survival bots
## shoot its front forever (a seed of S10 Survival ran into the hidden cap that way).
func test_the_live_shielder_answers_the_flank_rule() -> void:
	await _s10(&"survival", &"layout_gauntlet")
	await _quiet()
	assert_true(game.genre.spawn_archetype(&"shielder", 1))
	await wait_physics_frames(3)
	var e: EnemyWalker = _variant(&"shielder")[0]
	e.global_position = game.player.global_position + Vector2(200, 0)
	e.set(&"_faced", false)
	await wait_physics_frames(2)
	assert_eq(float(e.get(&"shield_arc_deg")), 100.0)
	var here := game.player.global_position
	var step := BotInput.flank_step(here, e)
	assert_ne(step, Vector2.ZERO, "in front of the shield: step around it")
	assert_almost_eq(absf(step.dot((here - e.global_position).normalized())), 0.0, 0.05, "sideways")
	assert_eq(BotInput.flank_step(e.global_position - e.facing * 200.0, e), Vector2.ZERO, "behind it: no step")
	assert_eq(BotInput.flank_step(e.global_position + e.facing * (BotInput.FLANK_REACH + 10.0), e), Vector2.ZERO,
			"beyond FLANK_REACH it fights as usual")


func test_the_sniper_locks_a_line_then_fires_one_fast_shot() -> void:
	await _s10(&"arsenal", &"layout_gauntlet")
	await _quiet()
	assert_true(game.genre.spawn_archetype(&"sniper", 1))
	await wait_physics_frames(3)
	var e: Node2D = _variant(&"sniper")[0]
	var shooter := e.get_node("Shooter") as Shooter
	assert_eq(shooter.projectile_speed, Tuning.sniper_shot_speed)
	assert_almost_eq(shooter.cooldown, Tuning.sniper_fire_interval - 1.0, 0.001)
	# Stand it 10 tiles away on a clear line.
	var here := game.player.global_position
	var placed := false
	for i in 16:
		var p := here + Vector2.RIGHT.rotated(TAU * i / 16.0) * 10.0 * Tuning.TILE
		if game.arena.bounds.grow(-96.0).has_point(p) and game.arena.distance_to_blocks(p) > 40.0 \
				and not EnemyCommon.ray_hits_world(e, here, p):
			e.global_position = p
			placed = true
			break
	assert_true(placed, "a clear spot 10 tiles from the start")
	var waited := 0
	while not e.is_winding_up() and waited < 400:
		await wait_physics_frames(1)
		waited += 1
	assert_true(e.is_winding_up(), "it aims")
	var line := e.get_node("SniperLine") as SniperLine
	await wait_physics_frames(1)
	assert_true(line.visible)
	assert_true(line.is_in_group(SniperLine.GROUP), "published for a bot")
	var lock: Vector2 = e.get(&"_lock_dir")
	assert_almost_eq(lock.angle_to(here - e.global_position), 0.0, 0.05, "locked on where the player stood")
	var stood := e.global_position
	game.player.global_position = here + lock.orthogonal() * 200.0   # step off the line
	await wait_physics_frames(20)
	assert_true(e.is_winding_up(), "one second of red line")
	assert_almost_eq(e.global_position.distance_to(stood), 0.0, 12.0, "it stands still while it aims")
	assert_almost_eq((line.to - line.from).normalized().angle_to(lock), 0.0, 0.01, "the line does not follow the player")
	waited = 0
	while e.is_winding_up() and waited < 80:
		await wait_physics_frames(1)
		waited += 1
	assert_false(e.is_winding_up())
	assert_false(line.visible)
	assert_false(line.is_in_group(SniperLine.GROUP))
	await wait_physics_frames(2)
	var shots := get_tree().get_nodes_in_group(&"enemy_projectile")
	assert_eq(shots.size(), 1, "one shot")
	if shots.size() == 1:
		var v: Vector2 = shots[0].get(&"velocity")
		assert_almost_eq(v.length(), 1400.0, 1.0)
		assert_almost_eq(v.normalized().angle_to(lock), 0.0, 0.01, "along the locked line")


func test_the_swarm_comes_as_packs_of_five_tiny_ones() -> void:
	await _s10(&"arsenal", &"layout_gauntlet")
	await _quiet()
	assert_true(game.genre.spawn_archetype(&"swarm", 2))
	await wait_physics_frames(3)
	var all := _variant(&"swarm")
	assert_eq(all.size(), 10, "two packs of five")
	for e: EnemyWalker in all:
		assert_eq(e.health.max_hp(), 1.0)
		assert_eq(e.size_mult, 0.6)
		assert_almost_eq(e.mover.speed, Tuning.chaser_speed * RunState.rules.enemy_speed_mult * 1.6, 0.01)
	# A plain spawn draws as before: one enemy a count, no pack.
	assert_true(game.genre.spawn_archetype(&"splitter", 2))
	await wait_physics_frames(3)
	assert_eq(_variant(&"splitter").size(), 2)


# --- Hot edges -----------------------------------------------------------------------------

func test_hot_edges_burn_the_outer_two_tiles_and_never_a_door() -> void:
	var edit := RuleDB.get_edit(&"edit_hot_edges")
	assert_not_null(edit)
	assert_eq(RuleDB.problems(edit), [] as Array[String])
	assert_eq([edit.duration, edit.target, edit.conflicts], [10.0, &"walls", [&"edit_bouncy_walls"] as Array[StringName]])
	assert_eq([edit.warn().text, edit.done().text], ["Let's make it cozy.", "Okay, room to breathe."])
	await _s10(&"arsenal", &"layout_gauntlet", false)
	await _quiet()
	var hot: HotEdges = game.genre.hot_edges
	var t := Tuning.TILE
	var b := game.arena.bounds
	assert_false(hot.is_hot(Vector2(2.0 * t, 5.0 * t)), "off: nothing is hot")
	assert_true(game.rule_book.request(&"edit_hot_edges", &"cue", 10.0, false))
	var waited := 0
	while not game.rule_book.is_live(&"edit_hot_edges") and waited < 200:
		await wait_physics_frames(1)
		waited += 1
	assert_true(game.rule_book.is_live(&"edit_hot_edges"))
	assert_eq(RunState.rules.hot_edge_tiles, 2)
	assert_eq(hot.band(), 3.0 * t, "two tiles inside the one-tile border")
	assert_true(hot.is_hot(Vector2(1.5 * t, 5.0 * t)))
	assert_true(hot.is_hot(Vector2(2.9 * t, 5.0 * t)))
	assert_false(hot.is_hot(Vector2(3.1 * t, 5.0 * t)), "the third tile in is safe")
	assert_true(hot.is_hot(Vector2(b.end.x - 1.5 * t, 5.0 * t)) and hot.is_hot(Vector2(20.0 * t, 1.5 * t))
			and hot.is_hot(Vector2(20.0 * t, b.end.y - 1.5 * t)), "all four sides")
	assert_false(hot.is_hot(b.get_center()))
	var gate := Node2D.new()
	gate.add_to_group(ExitGate.GROUP)
	game.world.add_child(gate)
	gate.global_position = Vector2(1.5 * t, 5.0 * t)
	assert_false(hot.is_hot(Vector2(1.5 * t, 5.0 * t)), "never on a door's tiles")
	assert_false(hot.is_hot(Vector2(2.5 * t, 6.0 * t)))
	assert_true(hot.is_hot(Vector2(1.5 * t, 9.0 * t)))
	gate.free()
	# One HP for each second stood in it; stepping out restarts the count.
	var health := Component.find(game.player, Health) as Health
	var spot := game.arena.free_tile_near(Vector2(1.5 * t, 5.5 * t))
	assert_true(hot.is_hot(spot), "a free tile in the band")
	var hp := health.hp()
	game.player.global_position = spot
	await wait_physics_frames(40)
	game.player.global_position = spot
	assert_eq([hot.burns, health.hp()], [0, hp], "not yet")
	await wait_physics_frames(30)
	assert_eq(hot.burns, 1)
	assert_eq(health.hp(), hp - 1.0)
	game.player.global_position = game.arena.player_start
	await wait_physics_frames(3)
	assert_eq(hot.inside, 0.0)
	assert_true(game.rule_book.remove(&"edit_hot_edges"))
	await wait_physics_frames(2)
	assert_eq([RunState.rules.hot_edge_tiles, hot.band()], [0, 0.0], "and exactly back")


# --- Per path ------------------------------------------------------------------------------

func test_each_path_has_its_basics_its_launcher_and_the_known_guns() -> void:
	var basics := {&"arsenal": [&"cards", &"quick_draw", &"fusion"], &"auto": [&"levelups", &"crowd", &"evolve"],
			&"survival": [&"pickups", &"kill_heal"]}
	for p in PATHS:
		await _s10(p, &"layout_gauntlet")
		game.spawner.enabled = false
		await _at(0.5)
		for b: StringName in basics[p]:
			assert_true(Unlocks.has_basic(b), "%s: %s live from the start" % [p, b])
		var pool := game.path_runner.offer_pool()
		assert_true(&"shotgun" in pool and &"laser" in pool, "%s: the guns of S8 and S9 are known" % p)
		assert_eq(&"nova" in pool, p == &"auto", "%s: nova is Auto's" % p)
		assert_false(&"launcher" in pool, "%s: not before the AI brings it" % p)
		await _at(4.5)
		assert_true(&"launcher" in game.path_runner.offer_pool(), "%s: the launcher is in" % p)
		var lo := game.path_runner.loadout()
		if p == &"arsenal":
			assert_not_null(lo.held(&"launcher"), "Arcade: a card in the free slot")
		elif p == &"auto":
			assert_eq(game.path_runner.get(&"_first"), &"launcher", "Auto: first in the next level-up")
			await _at(21.0)
			assert_true(&"haste" in game.path_runner.offer_pool() and &"area" in game.path_runner.offer_pool(),
					"Auto: the passives are back (Thunderclap needs Area)")
		else:
			var crates := get_tree().get_nodes_in_group(&"pickup").filter(func(n: Node) -> bool:
				return n.get(&"weapon_id") == &"launcher")
			assert_eq(crates.size(), 1, "Survival: a crate")
		game.queue_free()
		await wait_physics_frames(3)
		RunState.reset(0)
		RunState.world = null


func test_the_rail_names_the_part() -> void:
	await _s10(&"arsenal", &"layout_gauntlet")
	var snap := RailState.read(game, {})
	assert_eq(snap.parts, {"part": 1, "of": 3, "door": false})
	var frame := RailFrame.new()
	frame.snap = snap
	assert_string_contains(frame.caption(), "part 1/3")
	assert_false("door" in frame.caption())
	frame.snap = {"stage": 2, "title": "Level one", "path": {"id": &"arsenal"}, "parts": {"part": 2, "of": 3, "door": true}}
	assert_eq(frame.caption(), "stage 2 · level one · arsenal · part 2/3 · door open")
	frame.snap = {"stage": 2, "title": "Fresh paint", "path": {"id": &"arsenal"}, "parts": {"part": 0, "of": 0, "door": false}}
	assert_eq(frame.caption(), "stage 2 · fresh paint · arsenal", "a one-arena session reads as before")
	frame.free()
