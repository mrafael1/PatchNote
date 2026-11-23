extends GutTest
## PLAN v8 M39: the AI's live reactions (ReactionDef, Reactions, the speaking rules).

const TEST_PATH := "user://save_reactions_test/save.json"


func before_each() -> void:
	SaveGame.go_live(TEST_PATH, true)


func after_each() -> void:
	SaveGame.go_inert()
	CampaignDB.active = false
	RunState.session = null
	RunState.invincible = false


func _game(id: StringName) -> Main:
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	return game


## A game whose reactions only tick when the test says so, with nothing being spoken.
func _quiet_game(id := &"s1_04_level", keep_script := false) -> Main:
	var game := await _game(id)
	game.reactions.set_physics_process(false)
	if not keep_script:
		game.reactions._busy_until = -1.0
	game.reactions._last_reaction_at = -1000.0
	RunState.invincible = true
	_game_now = game
	return game


## Only these of the real reactions listen (the others would react to the test too).
func _only(game: Main, ids: Array[StringName]) -> void:
	game.reactions._defs.assign(CampaignDB.reactions.filter(func(r: ReactionDef) -> bool: return r.id in ids))


func _def(trigger: String, lines: Array[String], priority := 1) -> ReactionDef:
	var d := ReactionDef.new()
	d.id = &"test_reaction"
	d.trigger = trigger
	d.lines = PackedStringArray(lines)
	d.priority = priority
	return d


func _ids(game: Main) -> Array[String]:
	return game.reactions.fired_ids()


var _game_now: Main


## A kill and a hit as the reactions hear them (the bus's other listeners want real ones).
func _kill() -> void:
	_game_now.reactions._on_enemy_killed(null, null)


func _hit() -> void:
	_game_now.reactions._on_player_hit(null)


# --- The content --------------------------------------------------------------------

func test_the_reactions_are_about_thirty_and_valid() -> void:
	var defs := CampaignDB.reactions
	assert_between(defs.size(), 25, 40, "about 30 (PLAN v8 3.3)")
	var ids := {}
	for d in defs:
		assert_eq(d.problems(), [] as Array[String], String(d.id))
		assert_false(ids.has(d.id), "unique ids")
		ids[d.id] = true
		assert_gte(d.min_session, 3, "%s: nothing before the AI can talk (S3)" % d.id)
		for l in d.line_list():
			assert_true(l.text.length() <= 60, "%s: short lines fit the bubble: %s" % [d.id, l.text])
	assert_eq(CampaignDB.problems(), [] as Array[String])
	# Every trigger the plan names has at least one reaction.
	var used := {}
	for d in defs:
		used[d.trigger_name()] = true
	for t in ReactionDef.TRIGGERS:
		assert_true(used.has(t), "a reaction for %s" % t)


func test_a_bad_reaction_says_why() -> void:
	assert_string_contains(str(_def("dancing", ["Hi."]).problems()), "unknown trigger")
	assert_string_contains(str(_def("kill_streak", ["Hi."]).problems()), "needs a number")
	assert_string_contains(str(_def("first_kill 3", ["Hi."]).problems()), "takes nothing")
	assert_string_contains(str(_def("enemy_seen", ["Hi."]).problems()), "needs one word")
	assert_string_contains(str(_def("first_kill", ["mascot:blob happy: Eep."]).problems()), "the others would say nothing")
	assert_string_contains(str(_def("first_kill", []).problems()), "no lines")
	assert_eq(_def("kill_streak 4", ["happy: Combo!"]).problems(), [] as Array[String])


# --- Which sessions react -----------------------------------------------------------

func test_reactions_start_with_s3() -> void:
	var early := await _game(&"s1_02_enemies")
	assert_eq(early.reactions.active_ids(), [] as Array[StringName], "the AI can't talk yet")
	var s3 := await _game(&"s1_03_shooting")
	assert_gt(s3.reactions.active_ids().size(), 0)
	for d in CampaignDB.reactions:
		assert_eq(d.id in s3.reactions.active_ids(), d.min_session <= 3, String(d.id))


func test_mute_ai_says_nothing() -> void:
	var game := await _quiet_game()
	game.reactions.muted = true
	game.reactions.set_physics_process(true)
	_kill()
	await wait_physics_frames(30)
	assert_eq(_ids(game), [] as Array[String])


# --- Triggers -----------------------------------------------------------------------

func test_the_first_kill_is_noticed_once() -> void:
	var game := await _quiet_game()
	_only(game, [&"first_kill"])
	_kill()
	game.reactions.tick()
	assert_eq(_ids(game), ["first_kill"])
	assert_true(game.reactions.fired[0].text in ["First one!", "Got one!"])
	assert_eq(game.reactions.fired[0].priority, 2)


func test_a_streak_is_kills_close_together() -> void:
	var game := await _quiet_game()
	_only(game, [&"first_kill", &"streak_3"])
	_kill()
	game.reactions.tick()   # first_kill
	game.reactions._busy_until = -1.0
	RunState.game_time += 10.0
	_kill()
	_kill()
	game.reactions.tick()
	assert_false("streak_3" in _ids(game), "two kills are not a streak of 3")
	_kill()
	game.reactions.tick()
	assert_true("streak_3" in _ids(game))
	RunState.game_time += ReactionDef.STREAK_WINDOW + 0.1
	game.reactions.tick()
	assert_eq(game.reactions._kill_times.size(), 0, "old kills leave the window")


func test_an_edge_fires_once_while_it_holds() -> void:
	var game := await _quiet_game()
	game.reactions._defs.assign([_def("enemy_count_at_least 1", ["worried: One."])])
	game.reactions._defs[0].cooldown = 0.0
	game.spawn_wave(2)
	await wait_physics_frames(1)
	game.reactions.tick()
	assert_eq(_ids(game).size(), 1)
	RunState.game_time += 20.0
	game.reactions._busy_until = -1.0
	game.reactions.tick()
	assert_eq(_ids(game).size(), 1, "still 1+ enemies: not again")
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.free()
	game.reactions.tick()
	game.spawn_wave(1)
	await wait_physics_frames(1)
	RunState.game_time += 20.0
	game.reactions.tick()
	assert_eq(_ids(game).size(), 2, "it climbed back: again")


func test_low_hp_is_important_and_talks_over_a_cue() -> void:
	var game := await _quiet_game()
	_only(game, [&"hp_last", &"hp_two"])
	game.reactions.note_spoken(Line.make("A long line from the script, still being read."), SessionRunner.PRIORITY)
	assert_true(game.reactions.speaking())
	var health := Component.find(game.player, Health) as Health
	health.hp_ratio = 1.0 / health.max_hp()
	RunState.invincible = false
	game.reactions.tick()
	assert_true("hp_last" in _ids(game), "priority 3 ignores the speaking rule")
	assert_eq(game.reactions.fired[-1].priority, 3)


func test_a_cue_being_spoken_drops_lower_reactions() -> void:
	var game := await _quiet_game()
	_only(game, [&"first_kill"])
	game.reactions.note_spoken(Line.make("Oh. That works."), SessionRunner.PRIORITY)
	_kill()
	game.reactions.tick()
	assert_eq(_ids(game), [] as Array[String], "dropped, not queued")
	RunState.game_time += 10.0
	game.reactions.tick()
	assert_eq(_ids(game), [] as Array[String], "the moment has passed")


func test_chatter_waits_the_gap() -> void:
	var game := await _quiet_game()
	var a := _def("player_hit", ["Ow."])
	var b := _def("near_miss", ["Close."])
	b.id = &"test_b"
	game.reactions._defs.assign([a, b])
	_hit()
	game.reactions.tick()
	assert_eq(_ids(game), ["test_reaction"])
	RunState.game_time += Reactions.speak_seconds("Ow.") + 0.1   # done speaking
	game.reactions._near_misses = 1
	game.reactions.tick()
	assert_eq(_ids(game).size(), 1, "chatter within 8 s of the last reaction: dropped")
	RunState.game_time += Reactions.GAP
	game.reactions._near_misses = 1
	game.reactions.tick()
	assert_eq(_ids(game), ["test_reaction", "test_b"])


func test_cooldown_and_once_per_session() -> void:
	var game := await _quiet_game()
	var d := _def("player_hit", ["Ow."], 2)
	d.cooldown = 30.0
	game.reactions._defs.assign([d])
	for i in 3:
		_hit()
		game.reactions.tick()
		RunState.game_time += 10.5   # 3 x 10.5: past the 30 s cooldown, without float doubt
		game.reactions._busy_until = -1.0
	assert_eq(_ids(game).size(), 1, "cooldown 30 s")
	_hit()
	game.reactions.tick()
	assert_eq(_ids(game).size(), 2, "after the cooldown")
	d.once_per_session = true
	RunState.game_time += 40.0
	_hit()
	game.reactions.tick()
	assert_eq(_ids(game).size(), 2, "once per session")


func test_a_near_miss_is_a_close_shot_that_misses() -> void:
	var game := await _quiet_game()
	game.reactions._defs.assign([_def("near_miss", ["Close!"])])
	var shot := Node2D.new()
	shot.add_to_group(&"enemy_projectile")
	add_child_autofree(shot)
	shot.global_position = game.player.global_position + Vector2(Reactions.near_miss_reach() - 2.0, 0)
	game.reactions._watch_shots()
	game.reactions.tick()
	assert_eq(_ids(game).size(), 0, "not yet: it may still hit")
	RunState.game_time += Reactions.NEAR_MISS_CONFIRM
	game.reactions._watch_shots()
	game.reactions.tick()
	assert_eq(_ids(game).size(), 1)
	# A close shot followed by a hit is not a near miss.
	RunState.game_time += 30.0
	game.reactions._busy_until = -1.0
	game.reactions._last_reaction_at = -1000.0
	var other := Node2D.new()
	other.add_to_group(&"enemy_projectile")
	add_child_autofree(other)
	other.global_position = game.player.global_position
	game.reactions._watch_shots()
	_hit()
	RunState.game_time += Reactions.NEAR_MISS_CONFIRM
	game.reactions._watch_shots()
	game.reactions.tick()
	assert_eq(_ids(game).size(), 1)
	# A shot that reaches the player but does no damage (i-frames, a dash, the grace,
	# an invincible bot) sends no player_hit: it is still not a miss.
	shot.remove_from_group(&"enemy_projectile")
	other.remove_from_group(&"enemy_projectile")
	game.reactions._close_shots.clear()   # the two test shots sat still in reach
	RunState.game_time += 30.0
	game.reactions._busy_until = -1.0
	game.reactions._last_reaction_at = -1000.0
	var blocked := Node2D.new()
	blocked.add_to_group(&"enemy_projectile")
	add_child_autofree(blocked)
	blocked.global_position = game.player.global_position
	game.reactions._watch_shots()
	game.reactions._on_projectile_hit(blocked, game.player, blocked.global_position)
	RunState.game_time += Reactions.NEAR_MISS_CONFIRM
	game.reactions._watch_shots()
	game.reactions.tick()
	assert_eq(_ids(game).size(), 1, "a blocked hit is no near miss")


func test_camping_and_an_idle_gun() -> void:
	var game := await _quiet_game()
	var camp := _def("camping", ["Comfy?"])
	var idle := _def("not_shooting", ["Shoot?"], 2)
	idle.id = &"test_idle"
	game.reactions._defs.assign([camp, idle])
	game.reactions._last_shot_at = RunState.game_time
	game.reactions.tick()
	RunState.game_time += ReactionDef.CAMP_SECONDS
	game.reactions.tick()
	assert_true("test_reaction" in _ids(game), "8 s in one spot")
	game.spawn_wave(1)
	await wait_physics_frames(1)
	game.reactions._busy_until = -1.0
	game.reactions.tick()
	assert_true("test_idle" in _ids(game), "8 s without a shot, enemies around")


func test_enemy_seen_and_first_dash() -> void:
	var game := await _quiet_game()
	game.reactions._defs.assign([_def("enemy_seen shooter", ["Shoots back."], 2)])
	game.genre.spawn_archetype(&"chaser", 1)
	await wait_physics_frames(1)
	game.reactions.tick()
	assert_eq(_ids(game).size(), 0)
	game.genre.spawn_archetype(&"shooter", 1)
	await wait_physics_frames(1)
	game.reactions.tick()
	assert_eq(_ids(game).size(), 1)
	var dash := _def("first_dash", ["Whoosh!"], 2)
	dash.id = &"test_dash"
	game.reactions._defs.assign([dash])
	game.reactions._busy_until = -1.0
	EventBus.player_dashed.emit()
	game.reactions.tick()
	assert_true("test_dash" in _ids(game))


func test_session_half_and_last_seconds_on_a_survive_goal() -> void:
	var game := await _quiet_game()
	var half := _def("session_half", ["Halfway."])
	var last := _def("last_seconds", ["Almost."], 2)
	last.id = &"test_last"
	game.reactions._defs.assign([half, last])
	game.run_loop.goal_clock = 45.0
	game.reactions.tick()
	assert_eq(_ids(game), ["test_reaction"])
	game.run_loop.goal_clock = 86.0
	game.reactions._busy_until = -1.0
	game.reactions.tick()
	assert_eq(_ids(game), ["test_reaction", "test_last"])


# --- Lines ----------------------------------------------------------------------------

func test_a_mascot_with_its_own_lines_says_those() -> void:
	SaveGame.set_mascot(&"blob")
	var game := await _quiet_game()
	var d: ReactionDef = CampaignDB.reactions.filter(func(r: ReactionDef) -> bool: return r.id == &"hp_last")[0]
	for nth in 5:
		assert_eq(game.reactions.pick_line(d, nth).text, "Eep! Careful!")
	SaveGame.set_mascot(&"cursor")
	assert_eq(game.reactions.pick_line(d, 0).text, "I'm pointing at your health. It's low.")
	var shared: ReactionDef = CampaignDB.reactions.filter(func(r: ReactionDef) -> bool: return r.id == &"streak_3")[0]
	assert_eq(game.reactions.pick_line(shared, 2).text, game.reactions.pick_line(shared, 2).text, "the seed picks")


func test_reactions_reach_the_mascot_and_the_telemetry() -> void:
	var game := await _quiet_game()
	_only(game, [&"first_kill"])
	game.mascot.silence()   # the intro lines would come first
	_kill()
	game.reactions.tick()
	game.mascot.step(0.01)
	assert_true(game.mascot.shown.has(game.reactions.fired[0].text), "the mascot says it")
	var rec := CampaignDB.telemetry_record(RunState.session, {}, &"won", 0, &"next", "", null,
			game.reactions.fired_ids())
	assert_eq(rec.reactions, ["first_kill"])


## What Reactions owns is reproducible: the same events at the same game times, with the
## same seed and mascot, say the same lines at the same moments. (Whole-game replay is
## tools/run_hash.gd's, across processes.)
func test_the_same_events_and_seed_react_the_same() -> void:
	var runs: Array = []
	for i in 2:
		Main.next_seed = 77
		SaveGame.set_mascot(&"cursor")
		var game := await _quiet_game(&"s1_04_level", true)
		assert_gt(game.reactions._busy_until, 0.0, "the intro counts as being spoken")
		var r := game.reactions
		var start := 1.0   # fixed: the test's frame waits may differ by one
		# 40 s of scripted play at 60 Hz: kills in bursts, a hit at 12 s and 30 s, a dash.
		for frame in 60 * 40:
			var t := frame / 60.0
			RunState.game_time = start + t
			if frame % 90 == 0 or frame % 90 == 10 or frame % 90 == 20:
				_kill()
			if frame == 60 * 12 or frame == 60 * 30:
				_hit()
			if frame == 60 * 5:
				r._dashed_at = RunState.game_time
			r._physics_process(1.0 / 60.0)
		var times: Array = r.fired.map(func(f: Dictionary) -> Array: return [f.id, snappedf(float(f.at) - start, 0.01), f.text])
		runs.append(times)
		game.queue_free()
		await wait_physics_frames(2)
	assert_gte(runs[0].size(), 2, "40 s of scripted play has things to say")
	assert_eq(runs[0], runs[1])


## A script line counts as being spoken from the moment it is queued (game time), not
## when the runner lets it out (wall clock): a reaction cannot slip in between.
func test_a_queued_script_line_blocks_reactions_at_once() -> void:
	var game := await _quiet_game()
	_only(game, [&"first_kill"])
	game.session_runner.say(Line.parse("happy: Oh. That works."))
	assert_true(game.reactions.speaking())
	_kill()
	game.reactions.tick()
	assert_eq(_ids(game).size(), 0, "dropped: the cue has the moment")


## A new enemy that shows up while the AI is talking is still announced, once the AI is
## free, if that comes within PENDING seconds.
func test_a_new_enemy_seen_while_busy_waits_its_turn() -> void:
	var game := await _quiet_game()
	_only(game, [&"shooter_seen"])
	game.reactions.note_spoken(Line.parse("happy: A long line that keeps the AI busy for a while."), 2)
	game.genre.spawn_archetype(&"shooter", 1)
	await wait_physics_frames(1)
	game.reactions.tick()
	assert_eq(_ids(game).size(), 0, "busy: not now")
	RunState.game_time = game.reactions._busy_until + 0.1
	game.reactions.tick()
	assert_eq(_ids(game), ["shooter_seen"], "said once the AI is free")
	RunState.game_time += 60.0
	game.reactions.tick()
	assert_eq(_ids(game).size(), 1, "once")


func test_a_new_enemy_seen_too_long_ago_is_let_go() -> void:
	var game := await _quiet_game()
	_only(game, [&"shooter_seen"])
	game.genre.spawn_archetype(&"shooter", 1)
	await wait_physics_frames(1)
	RunState.game_time += Reactions.PENDING + 1.0
	game.reactions.tick()
	assert_eq(_ids(game).size(), 0)
