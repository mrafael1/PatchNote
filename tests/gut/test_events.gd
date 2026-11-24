extends GutTest
## PLAN v8 M41: scripted events. ScriptedEvent and EventDB, the event:<id> line
## condition, EventPlayer (one at a time, its own ticks, once per save, abort), the
## rule book's posed warning and swap, wrong_variable in S5, the debrief after it, F2,
## telemetry, the arena under sideways gravity, determinism.

const SPEED_LINE := "Enemies feel slow. One sec, I'll bump their speed."
const GRAVITY := [&"edit_gravity_left", &"edit_gravity_up", &"edit_gravity_down"]
const EVENT_FRAMES := 1200   ## the event takes 1140 ticks (19.0 s, M43.2); a margin


func before_each() -> void:
	SaveGame.go_inert()


func after_each() -> void:
	SaveGame.go_inert()
	CampaignDB.active = false
	RunState.session = null
	RunState.invincible = false
	RunState.reset(0)
	RunState.world = null
	Engine.time_scale = 1.0


func _game(id := &"s1_05_wrong") -> Main:
	await wait_physics_frames(1)   # a physics frame boundary
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	return game


## S5, invincible, no spawner, the AI's reactions on. S5's "at 15" version cues are
## dropped: _to_event jumps the clock past them, and their line would queue with the event's.
func _event_game() -> Main:
	var game := await _game()
	game.spawner.enabled = false
	game.session_runner.drop_cues(&"say")
	game.session_runner.drop_cues(&"add")
	RunState.invincible = true
	return game


## Moves S5's clock to the cue and waits for the event to start.
func _to_event(game: Main) -> void:
	game.run_loop.goal_clock = 20.0
	for i in 10:
		await wait_physics_frames(1)
		if game.event_player.is_playing():
			return
	fail_test("the event did not start")


## Game time of the first run-log entry of `event` (with `key` == value), or -1.
func _logged_at(event: StringName, key := "", value: Variant = null) -> float:
	for e: Dictionary in RunState.run_log:
		if e.get("event") == event and (key == "" or e.get(key) == value):
			return float(e.time)
	return -1.0


func _frames(seconds: float) -> int:
	return roundi(seconds * Engine.physics_ticks_per_second)


# --- data -------------------------------------------------------------------------------

func test_the_events_load_and_are_fine() -> void:
	var ids: Array = EventDB.all().map(func(e: ScriptedEvent) -> StringName: return e.id)
	assert_eq(ids, [&"wrong_variable"])
	var ev := EventDB.get_event(&"wrong_variable")
	assert_eq(EventDB.problems(ev), [] as Array[String])
	assert_true(ev.once_per_save)
	assert_true(ev.photosensitive)
	assert_eq(ev.steps, 6)
	for key: StringName in ev.lines:
		assert_eq(ev.line(key).problem, "", String(key))
		assert_eq(ev.line(key).when, &"", String(key))


func test_event_problems_are_reported() -> void:
	var bare := ScriptedEvent.new()
	bare.id = &"bare"
	bare.steps = 0
	bare.lines = {&"a": "happy:", &"b": "died happy: too late"}
	var text := "\n".join(EventDB.problems(bare))
	for expected in ["steps must be >= 1", "line a: empty line", "line b cannot have a condition", "no play()"]:
		assert_string_contains(text, expected)


func test_the_event_line_condition() -> void:
	var l := Line.parse("event:wrong_variable guilty: x")
	assert_eq([l.when, l.expression, l.problem], [&"event:wrong_variable", &"guilty", ""])
	assert_true(l.passes({"events": ["wrong_variable"]}))
	assert_false(l.passes({"events": []}))
	assert_false(l.passes({}))


func test_s5_is_the_wrong_variable_session() -> void:
	var s := CampaignDB.get_session(&"s1_05_wrong")
	assert_eq([s.goal, s.goal_value, s.time_limit, s.bump, s.fork], [SessionDef.KILLS, 20.0, 150.0, &"minor", &""],
			"M43.2 (G13b): a 20-kill goal")
	assert_true(&"fork:fork_enemy" in s.enemies)
	var cues := s.cue_list()
	var events := cues.filter(func(c: Cue) -> bool: return c.action == &"event")
	assert_eq(events.size(), 1)
	assert_eq([events[0].when, events[0].value, events[0].target], [&"at", 20.0, &"wrong_variable"],
			"M43.2: early, after the version line (15 s + its 4.4 s)")
	var adds := cues.filter(func(c: Cue) -> bool: return c.action == &"add")
	assert_eq(adds.size(), 1, "M42: S5 adds the version stamp live")
	assert_eq([adds[0].when, adds[0].value, adds[0].target], [&"at", 15.0, &"version"])
	assert_false(&"version" in s.basics, "added live, not listed")
	var spawns := cues.filter(func(c: Cue) -> bool: return c.action == &"spawn")
	assert_eq(spawns.size(), 1, "M42 E6: the picked enemy comes with its announcement")
	assert_eq([spawns[0].when, spawns[0].value, spawns[0].archetype, spawns[0].count],
			[&"at", 6.0, &"fork:fork_enemy", 1])
	assert_eq(s.spawn_rate, 0.8, "M42 E4")
	var first := s.debrief_lines()[0]
	assert_eq([first.when, first.expression], [&"event:wrong_variable", &"guilty"])
	assert_eq(s.notes, PackedStringArray(["Gravity fixed (mostly)"]))
	assert_eq(s.problems(), [] as Array[String], "S5 itself is fine")


func test_s5_spawns_the_forked_enemy() -> void:
	var s := CampaignDB.get_session(&"s1_05_wrong")
	assert_false(&"lancer" in s.enemy_types(), "an inert save answers no fork")
	SaveGame.ship(&"enemy_lancer", &"patch")
	assert_eq(ChangeDB.get_fork(&"fork_enemy").answer().id, &"enemy_lancer")
	assert_true(&"lancer" in s.enemy_types())


## M42 E6: "spawn fork:<id>" spawns the enemy that fork's answer unlocks.
func test_a_spawn_cue_can_name_the_forked_enemy() -> void:
	var c := Cue.parse("at 6: spawn fork:fork_enemy 1")
	assert_eq([c.problem, c.archetype, c.count], ["", &"fork:fork_enemy", 1])
	assert_ne(Cue.parse("at 6: spawn fork: 1").problem, "", "a fork needs an id")
	assert_ne(Cue.parse("at 6: spawn dragon 1").problem, "")
	assert_eq(SessionRunner._resolve_archetype(&"tank"), &"tank")
	assert_eq(SessionRunner._resolve_archetype(&"fork:fork_enemy"), &"", "unanswered: nothing")
	SaveGame.ship(&"enemy_lancer", &"patch")
	assert_eq(SessionRunner._resolve_archetype(&"fork:fork_enemy"), &"lancer")
	var s := CampaignDB.get_session(&"s1_05_wrong").duplicate() as SessionDef
	s.cues = PackedStringArray(["at 6: spawn fork:no_such_fork 1"])
	assert_string_contains("
".join(s.problems()), "no fork no_such_fork")


func test_s5_spawns_the_picked_enemy_at_6_s() -> void:
	SaveGame.ship(&"enemy_tank", &"patch")
	var game := await _game()
	RunState.invincible = true
	game.spawner.enabled = false
	game.run_loop.goal_clock = 6.0
	await wait_physics_frames(3)
	var tanks := get_tree().get_nodes_in_group(&"enemy").filter(
			func(n: Node) -> bool: return n.scene_file_path.ends_with("enemy_tank.tscn"))
	assert_eq(tanks.size(), 1, "one tank, from the cue")


## M42 E5: the spawner rests while an event holds the clock, derived, never back on
## after the run is over.
func test_spawns_pause_while_the_event_holds_the_clock() -> void:
	var game := await _game()
	RunState.invincible = true
	game.session_runner.drop_cues(&"say")
	assert_true(game.spawner.enabled)
	await _to_event(game)
	for i in 200:
		if game.run_loop.clock_held():
			break
		await wait_physics_frames(1)
	assert_true(game.run_loop.clock_held())
	assert_false(game.spawner.enabled, "no spawns while the clock is held")
	for i in EVENT_FRAMES:
		if not game.run_loop.clock_held():
			break
		await wait_physics_frames(1)
	assert_true(game.spawner.enabled, "back once the clock runs again")
	game.genre.hold_session_clock(&"test", true)
	game.run_loop.end(&"win")
	game.genre.hold_session_clock(&"test", false)
	assert_false(game.spawner.enabled, "never back on after the end")


## M42 E7 (D15): the AI gives 1 HP back at the clear ("Speed was the other slider.").
func test_the_clear_gives_one_hp_back() -> void:
	var game := await _event_game()
	RunState.invincible = false
	var h := Component.find(game.player, Health) as Health
	h.hp_ratio = 2.0 / h.max_hp()
	await _to_event(game)
	for i in EVENT_FRAMES:
		if not game.event_player.is_playing():
			break
		await wait_physics_frames(1)
	assert_true(game.event_player.played[0].completed)
	assert_almost_eq(h.hp(), 3.0, 0.001)


## --session=s1_05_wrong on a fresh save still plays a forked enemy (option 0).
func test_a_jump_answers_the_sessions_forks() -> void:
	var s := CampaignDB.get_session(&"s1_05_wrong")
	var fork := ChangeDB.get_fork(&"fork_enemy")
	assert_false(fork.is_answered())
	CampaignDB.answer_forks(s)
	assert_eq(fork.answer(), fork.changes()[0])
	assert_eq(s.enemy_types().size(), 3, "chaser, shooter and the forked one")
	CampaignDB.answer_forks(s)
	assert_eq(SaveGame.shipped().size(), 1, "an answered fork is left alone")


func test_intro_and_cue_lines_cannot_depend_on_an_event() -> void:
	var s := SessionDef.new()
	s.id = &"x"
	s.title = "x"
	s.intro = PackedStringArray(["event:wrong_variable happy: x"])
	s.cues = PackedStringArray(["at 5: say event:wrong_variable happy: x"])
	s.debrief = PackedStringArray(["event:nope happy: x"])
	var text := "\n".join(s.problems())
	for expected in ["an intro line cannot depend on an event", "a cue line cannot depend on an event",
			"unknown event nope"]:
		assert_string_contains(text, expected)


# --- the rule book's new moves ------------------------------------------------------------

func test_a_posed_warning_shows_one_edit_and_lands_another() -> void:
	var game := await _event_game()
	game.session_runner.set_physics_process(false)
	var book := game.rule_book
	assert_true(book.request(&"edit_gravity_left", &"event", 0.0, true, &"edit_enemy_speed"))
	assert_true(book.said.has(SPEED_LINE), "the speed warning is said")
	assert_eq(book._marker.target, &"enemies", "and its icon shown")
	assert_true(game.mascot.body.pointing())
	assert_eq(String(RunState.run_log.back().get("as")), "edit_enemy_speed")
	await wait_physics_frames(_frames(1.5) + 3)
	assert_true(book.is_live(&"edit_gravity_left"), "gravity lands")
	assert_almost_eq(_logged_at(&"edit_landed", "id", "edit_gravity_left") - _logged_at(&"edit_requested"), 1.5, 0.02,
			"after the speed edit's warning")
	assert_false(book.is_live(&"edit_enemy_speed") or book.is_pending(&"edit_enemy_speed"))


func test_a_posed_warning_is_gentle_with_reduce_flashing() -> void:
	SaveGame.set_setting("reduce_flashing", true)
	var game := await _event_game()
	game.session_runner.set_physics_process(false)
	var book := game.rule_book
	book.request(&"edit_gravity_left", &"event", 0.0, true, &"edit_enemy_speed")
	assert_true(book._marker.gentle, "gravity is photosensitive: the posed marker is gentle")
	book.request(&"edit_big_enemies")
	book.remove(&"edit_big_enemies")   # re-shows the posed one
	assert_true(book._marker.is_showing())
	assert_true(book._marker.gentle, "still gentle when shown again")
	assert_eq(book._marker.target, &"enemies")


func test_swap_replaces_a_gravity_edit_in_one_frame() -> void:
	var game := await _event_game()
	game.session_runner.set_physics_process(false)
	var book := game.rule_book
	book.request(&"edit_gravity_left", &"event", 0.0, false)
	await wait_physics_frames(2)
	assert_true(book.swap(&"edit_gravity_left", &"edit_gravity_up"))
	assert_true(RunState.rules.gravity_enabled, "never without gravity")
	assert_eq(RunState.rules.gravity_dir, Vector2.UP)
	assert_true(RunState.in_grace())
	assert_eq(book.landed.map(func(l: Dictionary) -> String: return l.id), ["edit_gravity_left", "edit_gravity_up"])
	assert_true(RunState.run_log.any(func(e: Dictionary) -> bool:
			return e.get("event") == &"ai_remove" and e.get("reason") == &"replaced"))
	book.remove(&"edit_gravity_up")
	assert_true(book.swap(&"edit_gravity_up", &"edit_gravity_down"), "from an edit not live: a request")
	await wait_physics_frames(2)
	assert_true(book.is_live(&"edit_gravity_down"))


func test_the_mascot_can_cut_its_own_line_and_set_a_face() -> void:
	var game := await _event_game()
	var mascot := game.mascot
	mascot.silence()
	mascot.say(Line.parse("first"), 3)
	mascot.say(Line.parse("second"), 3)
	assert_eq(mascot.current_text(), "first", "equal priority queues")
	mascot.say(Line.parse("surprised: third"), 3, true)
	assert_eq(mascot.current_text(), "third", "cut replaces it now")
	mascot.show_expression(&"panic")
	assert_eq(mascot.body.expression, &"panic")


func test_reactions_hold_all_but_priority_3() -> void:
	var game := await _event_game()
	var r := game.reactions
	var low := ReactionDef.new()
	low.id = &"low"
	low.priority = 2
	var high := ReactionDef.new()
	high.id = &"high"
	high.priority = 3
	r.hold(&"event", true)
	assert_false(r._allowed(low, 100.0))
	assert_true(r._allowed(high, 100.0))
	var e := RunState.spawn(load("res://entities/enemy_tank.tscn"), game.player.global_position + Vector2(600, 0))
	await wait_physics_frames(2)
	assert_eq(r._seen.get("tank"), -INF, "seen during the hold: never announced")
	r.hold(&"event", false)
	assert_false(r.held())
	assert_not_null(e)


# --- wrong_variable ------------------------------------------------------------------------

func test_wrong_variable_plays_its_steps_in_order() -> void:
	var game := await _event_game()
	await _to_event(game)
	var t0 := _logged_at(&"event_started")
	assert_true(game.rule_book.said.has(SPEED_LINE), "step 1: the speed warning")
	assert_true(game.rule_book._marker.is_showing())
	assert_false(RunState.rules.gravity_enabled, "nothing yet")
	await wait_physics_frames(EVENT_FRAMES)
	var steps: Array = []
	for n in range(1, 7):
		steps.append(snappedf(_logged_at(&"event_step", "step", n) - t0, 0.05))
	assert_eq(steps, [0.0, 0.0, 1.5, 8.0, 13.5, 19.0], "the steps' times (M43.2: +2.5 s per direction)")
	var lands: Array = []
	for id: StringName in GRAVITY:
		lands.append(snappedf(_logged_at(&"edit_landed", "id", String(id)) - t0, 0.05))
	assert_eq(lands, [1.5, 8.0, 13.5], "left, up, down")
	assert_eq(game.rule_book.landed.map(func(l: Dictionary) -> String: return l.id),
			["edit_gravity_left", "edit_gravity_up", "edit_gravity_down"])
	assert_false(RunState.rules.gravity_enabled, "gravity is off again")
	assert_almost_eq(RunState.rules.enemy_speed_mult, 1.15, 0.0001, "the speed it meant")
	assert_eq(RunState.ai_owner.get(&"edit_enemy_speed"), &"event")
	var ev := EventDB.get_event(&"wrong_variable")
	assert_eq(game.event_player.said, [ev.line(&"not_speed").text, ev.line(&"wrong_one").text,
			ev.line(&"nope").text, ev.line(&"other_slider").text] as Array[String])
	var rec: Dictionary = game.event_player.played[0]
	assert_true(rec.completed)
	assert_eq(rec.steps_done, 6)


func test_wrong_variable_holds_the_clock_from_the_first_flip_to_the_clear() -> void:
	var game := await _event_game()
	await _to_event(game)
	while not game.run_loop.clock_held():
		await wait_physics_frames(1)
	assert_eq(game.mascot.body.expression, &"surprised", "the face turns as left lands, before its line")
	assert_false(game.event_player.said.has("That's… not speed."), "the line comes 0.8 s later")
	var held_at := RunState.game_time
	var clock := game.run_loop.goal_clock
	assert_almost_eq(clock, 21.5, 0.1, "the warning counts toward the goal")
	await wait_physics_frames(300)
	assert_true(game.run_loop.clock_held())
	assert_almost_eq(game.run_loop.goal_clock, clock, 0.02, "held")
	while game.run_loop.clock_held():
		await wait_physics_frames(1)
	assert_almost_eq(RunState.game_time - held_at, 17.5, 0.05, "held 17.5 s (M43.2)")
	await wait_physics_frames(30)
	assert_gt(game.run_loop.goal_clock, clock + 0.4, "and running again")


func test_gravity_never_drops_out_between_flips_and_each_flip_has_a_grace() -> void:
	var game := await _event_game()
	await _to_event(game)
	var dirs: Array = []
	var dropped := false
	var graceless := 0
	for i in EVENT_FRAMES:
		await wait_physics_frames(1)
		var r := RunState.rules
		if game.run_loop.clock_held() and not r.gravity_enabled and game.event_player.is_playing() \
				and int(game.event_player.played[0].steps_done) < 6:
			dropped = true
		var key: Variant = r.gravity_dir if r.gravity_enabled else null
		if dirs.is_empty() or dirs.back() != key:
			if not dirs.is_empty() and not RunState.in_grace():
				graceless += 1
			dirs.append(key)
	assert_false(dropped, "no frame without gravity between left and down")
	assert_eq(dirs, [null, Vector2.LEFT, Vector2.UP, Vector2.DOWN, null])
	assert_eq(graceless, 0, "every change starts a grace")


func test_wrong_variable_leaves_no_edit_live() -> void:
	var game := await _event_game()
	await _to_event(game)
	await wait_physics_frames(EVENT_FRAMES)
	assert_eq(game.rule_book.live_ids(), [] as Array[StringName])
	assert_eq(RunState.ai.map(func(m: Mutation) -> StringName: return m.id), [&"edit_enemy_speed"])
	game.run_loop.end(&"win")
	await wait_physics_frames(3)
	assert_true(RunState.ai.is_empty(), "the session's end takes the speed back")
	assert_almost_eq(RunState.rules.enemy_speed_mult, 1.0, 0.0001)


func test_once_per_save_then_skipped_and_the_session_still_completes() -> void:
	var game := await _event_game()
	await _to_event(game)
	assert_true(SaveGame.event_seen(&"wrong_variable"), "seen when it starts")
	game.queue_free()
	await wait_physics_frames(2)
	RunState.reset(0)
	var again := await _event_game()   # same save
	again.run_loop.goal_clock = 20.0
	await wait_physics_frames(10)
	assert_false(again.event_player.is_playing())
	assert_true(again.event_player.played[0].skipped)
	assert_false(again.run_loop.clock_held())
	assert_true(RunState.ai.is_empty())
	assert_eq(again.event_player.said, [] as Array[String])
	assert_eq(again.event_player.played_ids(), [] as Array[String])
	RunState.kills = 20   # M43.2: a kills goal
	await wait_physics_frames(10)
	assert_eq(again.run_loop.outcome, &"win", "the session plays on and is won")


## M43.2 (G13b): S5 is a 20-kill goal, so the goal can be reached while the event plays.
## No goal ends during an event (from its start, warning included, to its end): the win
## waits for the clear, then lands on the next tick.
func _kills_during_event(at_step: int) -> Main:
	var game := await _event_game()
	await _to_event(game)
	while int(game.event_player.played[0].steps_done) < at_step:
		await wait_physics_frames(1)
	RunState.kills = 20
	await wait_physics_frames(2)
	assert_eq(game.run_loop.phase, RunLoop.PLAY, "step %d: the goal waits for the event" % at_step)
	assert_true(game.run_loop.goal_held())
	assert_eq(game.run_loop.goal_text(), "Kills 20/20")
	RunState.kills = 21
	assert_eq(game.run_loop.goal_text(), "Kills 20/20", "the shown kills stop at the goal")
	for i in EVENT_FRAMES:
		if game.run_loop.phase != RunLoop.PLAY:
			break
		await wait_physics_frames(1)
	var rec: Dictionary = game.event_player.played[0]
	assert_true(rec.completed, "the event played to its end")
	assert_eq(rec.steps_done, 6)
	assert_eq(game.run_loop.outcome, &"win", "then the session is won")
	var ended_at := _logged_at(&"event_ended")
	assert_gte(_logged_at(&"run_ended") if _logged_at(&"run_ended") >= 0.0 else RunState.game_time, ended_at)
	assert_eq(RunState.run_log.filter(func(e: Dictionary) -> bool: return e.get("event") == &"goal_waited").size(), 1,
			"logged once")
	assert_false(game.run_loop.goal_held(), "released at the end")
	return game


func test_a_kill_goal_reached_in_the_warning_waits_for_the_event() -> void:
	var game := await _kills_during_event(2)
	assert_false(game.run_loop.clock_held())


func test_a_kill_goal_reached_mid_flip_waits_for_the_event() -> void:
	await _kills_during_event(4)


func test_a_held_goal_never_ends_and_a_released_one_does() -> void:
	var game := await _event_game()
	game.session_runner.drop_cues(&"event")
	game.run_loop.hold_goal(&"test", true)
	RunState.kills = 20
	await wait_physics_frames(3)
	assert_eq(game.run_loop.phase, RunLoop.PLAY)
	game.run_loop.goal_clock = 200.0   # past the time limit too
	await wait_physics_frames(2)
	assert_eq(game.run_loop.phase, RunLoop.PLAY, "the time limit waits as well")
	game.run_loop.hold_goal(&"test", false)
	await wait_physics_frames(2)
	assert_eq(game.run_loop.outcome, &"win")


func test_a_death_during_the_event_still_ends_the_session() -> void:
	var game := await _event_game()
	await _to_event(game)
	EventBus.player_died.emit()
	await wait_physics_frames(3)
	assert_ne(game.run_loop.phase, RunLoop.PLAY, "a death is not held")
	await wait_physics_frames(3)
	assert_false(game.run_loop.goal_held())


func test_the_debrief_opens_on_guilty_only_after_the_event() -> void:
	var game := await _event_game()
	await _to_event(game)
	await wait_physics_frames(EVENT_FRAMES)
	game.run_loop.end(&"win")
	for i in 600:
		if game.debrief.is_open():
			break
		await wait_physics_frames(1)
	assert_true(game.debrief.is_open())
	assert_eq(game.debrief.events, ["wrong_variable"] as Array[String])
	var first: Line = game.debrief.lines[0]
	assert_eq([first.expression, first.text], [&"guilty", "So. About the gravity thing."])
	assert_eq(game.debrief.lines[1].text, "Let's never speak of it.")
	# A retry skips the event: the same debrief never mentions gravity.
	var s := CampaignDB.get_session(&"s1_05_wrong")
	var lines := Line.passing(s.debrief_lines(), CampaignDB.line_context(s, &"won", 2, []))
	assert_eq(lines[0].expression, &"happy")
	assert_false(lines.any(func(l: Line) -> bool: return l.text.contains("gravity")))


func test_a_death_mid_event_stops_the_script_and_releases_everything() -> void:
	var game := await _event_game()
	await _to_event(game)
	await wait_physics_frames(200)
	assert_true(game.rule_book.is_live(&"edit_gravity_left"))
	game.run_loop.end(&"lose")
	await wait_physics_frames(3)
	assert_false(game.run_loop.clock_held(), "the clock is released")
	assert_false(game.reactions.held())
	assert_true(RunState.ai.is_empty(), "no edit stays")
	var rec: Dictionary = game.event_player.played[0]
	assert_true(rec.aborted)
	assert_false(rec.completed)
	assert_gte(float(rec.end), float(rec.start))
	var said := game.event_player.said.size()
	var landed := game.rule_book.landed.size()
	await wait_physics_frames(600)
	assert_eq(game.event_player.said.size(), said, "no more lines")
	assert_eq(game.rule_book.landed.size(), landed, "no more flips")
	assert_true(RunState.ai.is_empty())


func test_freeing_the_game_mid_event_is_safe() -> void:
	var game := await _event_game()
	await _to_event(game)
	await wait_physics_frames(200)
	var rec: Dictionary = game.event_player.played[0]
	game.queue_free()
	await wait_physics_frames(30)
	assert_true(rec.aborted, "the script was stopped")
	assert_gte(float(rec.end), float(rec.start))
	assert_true(RunState.run_log.any(func(e: Dictionary) -> bool: return e.get("event") == &"event_ended"))
	var after := RunState.run_log.size()
	await wait_physics_frames(400)
	assert_eq(RunState.run_log.size(), after, "nothing more happens: no step, no flip")


## After the event the speed is the event's own: freeing the scene takes it back.
func test_freeing_the_game_after_the_event_takes_its_speed_back() -> void:
	var game := await _event_game()
	await _to_event(game)
	await wait_physics_frames(EVENT_FRAMES)
	assert_true(RunState.ai.any(func(m: Mutation) -> bool: return m.id == &"edit_enemy_speed"))
	game.queue_free()
	await wait_physics_frames(2)
	assert_false(RunState.ai.any(func(m: Mutation) -> bool: return m.id == &"edit_enemy_speed"),
			"no x1.15 left for the next scene")

func test_muted_the_event_still_flips_gravity_silently() -> void:
	var game := await _event_game()
	game.event_player.muted = true
	game.rule_book.muted = true
	await _to_event(game)
	await wait_physics_frames(200)
	assert_true(game.run_loop.clock_held())
	await wait_physics_frames(EVENT_FRAMES - 200)
	assert_eq(game.event_player.said, [] as Array[String])
	assert_eq(game.rule_book.said, [] as Array[String])
	assert_eq(game.rule_book.landed.size(), 3)
	assert_true(game.event_player.played[0].completed)


func test_reactions_are_held_during_the_event() -> void:
	var game := await _event_game()
	await _to_event(game)
	assert_true(game.reactions.held())
	await wait_physics_frames(EVENT_FRAMES)
	assert_false(game.reactions.held(), "released at the end")


func test_reduce_flashing_plays_the_gentle_variant() -> void:
	for gentle: bool in [false, true]:
		SaveGame.go_inert()
		SaveGame.set_setting("reduce_flashing", gentle)
		var game := await _event_game()
		await _to_event(game)
		while int(game.event_player.played[0].steps_done) < 3:
			await wait_physics_frames(1)
		assert_eq(game.mascot.body.gentle, gentle)
		assert_true(game.mascot.body.glitching(), "the mascot glitches either way")
		if gentle:
			assert_almost_eq(game.transition.glitch_strength(), 0.0, 0.001, "no screen glitch")
		else:
			assert_gt(game.transition.glitch_strength(), 0.0, "the screen glitches")
		game.queue_free()
		await wait_physics_frames(2)
		RunState.reset(0)


func test_f2_plays_an_event_ignoring_once_per_save() -> void:
	var game := await _event_game()
	game.session_runner.set_physics_process(false)
	SaveGame.mark_event_seen(&"wrong_variable")
	assert_true(game.debug.play_event(&"wrong_variable"), "seen, and played anyway")
	assert_eq(game.event_player.played[0].by, "console")
	assert_false(game.event_player.played[0].skipped)


func test_f2_marks_nothing_seen() -> void:
	var game := await _event_game()
	game.session_runner.set_physics_process(false)
	assert_true(game.debug.play_event(&"wrong_variable"))
	assert_false(SaveGame.event_seen(&"wrong_variable"), "the player's one time is not spent")
	assert_eq((SaveGame.campaign().events_seen as Array).size(), 0)


func test_one_event_at_a_time() -> void:
	var game := await _event_game()
	await _to_event(game)
	assert_false(game.event_player.play(&"wrong_variable", &"console", true))
	assert_eq(game.event_player.played.size(), 1)


func test_events_land_in_the_telemetry() -> void:
	var s := CampaignDB.get_session(&"s1_05_wrong")
	var rec := CampaignDB.telemetry_record(s, {}, &"won", 0, &"next", "", null, [], [], ["wrong_variable"])
	assert_eq(rec.events, ["wrong_variable"])
	assert_eq(CampaignDB.telemetry_record(s, {}, &"won", 0, &"next").events, [])


# --- the arena ---------------------------------------------------------------------------

func test_sideways_gravity_lights_the_face_you_stand_on() -> void:
	var r := Rect2(100, 200, 64, 32)
	assert_eq(Arena.standable_strip(r, Vector2.LEFT), Rect2(r.end.x - Arena.STRIP, 200, Arena.STRIP, 32))
	assert_eq(Arena.standable_strip(r, Vector2.RIGHT), Rect2(100, 200, Arena.STRIP, 32))
	assert_eq(Arena.standable_strip(r, Vector2.DOWN), Rect2(100, 200, 64, Arena.STRIP))
	assert_eq(Arena.standable_strip(r, Vector2.UP), Rect2(100, r.end.y - Arena.STRIP, 64, Arena.STRIP))


# --- determinism ---------------------------------------------------------------------------

func test_same_seed_same_event_same_session() -> void:
	var traces: Array[Array] = []
	var logs: Array[String] = []
	for run in 2:
		SaveGame.go_inert()   # or the second run skips the event
		SaveGame.set_mascot(&"cursor")
		await wait_physics_frames(1)
		Main.next_seed = 4343
		var game := await _game()
		RunState.invincible = true
		game.player.set_bot(true)
		game.session_runner.drop_cues(&"event")
		game.session_runner.inject("at 2: event wrong_variable")
		var trace: Array[int] = []
		for f in 1380:   # the event at 2 s takes 19 s (M43.2)
			if f % 10 == 0:
				trace.append(_world_hash(game))
			await wait_physics_frames(1)
		assert_true(game.event_player.played[0].completed, "run %d played it" % run)
		var kinds := ["ai_apply", "ai_remove", "edit_requested", "edit_landed", "event_started", "event_step", "event_ended"]
		logs.append(JSON.stringify(RunState.run_log.filter(func(e: Dictionary) -> bool:
				return String(e.get("event", "")) in kinds)))
		traces.append(trace)
		game.queue_free()
		await wait_physics_frames(1)
		RunState.reset(0)
		RunState.world = null
	assert_eq(logs[0], logs[1], "the same edits and steps on the same frames")
	for i in mini(traces[0].size(), traces[1].size()):
		if traces[0][i] != traces[1][i]:
			fail_test("diverges at frame %d" % (i * 10))
			break
	assert_eq(hash(traces[0]), hash(traces[1]))


func _world_hash(game: Main) -> int:
	var parts: Array[String] = []
	var p := game.player.global_position
	parts.append("p%.2f,%.2f" % [p.x, p.y])
	var ents: Array[String] = []
	for e: Node in RunState.live_entities():
		var pos := (e as Node2D).global_position
		ents.append("%s%.2f,%.2f" % [e.get(&"kind"), pos.x, pos.y])
	ents.sort()
	parts.append_array(ents)
	parts.append("k%d b%d" % [RunState.kills, RunState.build_number])
	return hash("|".join(parts))
