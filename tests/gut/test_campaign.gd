extends GutTest
## M37: the campaign spine (PLAN v8 1.1, 1.2, 1.8, 1.9, section 2). Sessions as data,
## their goals, the death flow (Retry / Move on), the save's schema 2, the start screen
## and the reduce-flashing setting. Every test that makes the save live points it at
## TEST_PATH; after_each puts everything back to the v6 defaults.

const TEST_PATH := "user://save_campaign_test/save.json"
const Fx := preload("res://tests/gut/fixtures.gd")


func before_each() -> void:
	_delete_files()


func after_each() -> void:
	assert_ne(SaveGame.save_path if SaveGame.persist else "", SaveGame.DEFAULT_PATH,
			"no test may leave the real save live")
	CampaignDB.active = false
	SaveGame.go_inert()
	_delete_files()
	StartScreen.save_live = true
	StartScreen.legacy_loop = "--legacy-loop" in OS.get_cmdline_user_args()
	Look.use(Unlocks.FULL_LOOK)
	RunState.reset(0)
	RunState.world = null


func _delete_files() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", "user://save_campaign_test/save.bad.json",
			"user://save_campaign_test/save.v1.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _write(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_PATH.get_base_dir())
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## The game scene playing session `id` on the in-memory (inert) save.
func _game(id: StringName) -> Main:
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	return game


func _session(id: StringName, goal := SessionDef.SURVIVE, value := 10.0) -> SessionDef:
	var s := SessionDef.new()
	s.id = id
	s.title = String(id)
	s.goal = goal
	s.goal_value = value
	return s


# --- The data -----------------------------------------------------------------------

func test_the_campaign_has_no_problems() -> void:
	assert_eq(CampaignDB.problems(), [] as Array[String])
	assert_eq(CampaignDB.size(), 8)
	assert_eq(CampaignDB.session(0).id, &"s1_00_nothing", "S0: nothing")
	assert_eq(CampaignDB.index_of(&"s1_03_shooting"), 3)
	assert_eq(CampaignDB.session(4).id, &"s1_04_level")
	assert_eq(CampaignDB.session(5).id, &"s1_05_wrong")
	assert_eq(CampaignDB.session(6).id, &"s1_06_playground", "S6 ends Stage 1 (M42)")
	assert_eq(CampaignDB.session(7).id, &"s2_01_tryout", "S7 opens Stage 2 (M43)")
	assert_null(CampaignDB.session(8))


func test_lines_parse_a_condition_an_expression_and_the_text() -> void:
	var l := Line.parse("died guilty: Too many at once. My bad.")
	assert_eq([l.when, l.expression, l.text, l.problem], [&"died", &"guilty", "Too many at once. My bad.", ""])
	l = Line.parse("happy: Oh. That works.")
	assert_eq([l.when, l.expression, l.text], [&"", &"happy", "Oh. That works."])
	l = Line.parse("mascot:blob proud: I'm squishy.")
	assert_eq([l.when, l.expression, l.text], [&"mascot:blob", &"proud", "I'm squishy."])
	l = Line.parse("Note: this is all text.")
	assert_eq([l.when, l.expression, l.text], [&"", &"idle", "Note: this is all text."], "an unknown word is text")
	l = Line.parse("_ x")
	assert_eq([l.expression, l.text], [&"idle", "_ x"])
	assert_ne(Line.parse("happy:").problem, "", "an empty line is a problem")
	assert_eq(Line.parse("mascot: hi").text, "mascot: hi", "a bare prefix is no condition: text")
	assert_eq(Line.parse("mascot:blob died: hi").text, "mascot:blob died: hi", "two conditions: text")


func test_line_conditions_read_the_context() -> void:
	var ctx := {"outcome": &"died", "hits": 0, "attempt": 2, "mascot": &"blob", "shipped": [&"enemy_tank"]}
	for c: Array in [["died", true], ["won", false], ["hit_none", true], ["hit_lots", false],
			["retry", true], ["first_try", false], ["mascot:blob", true], ["mascot:cursor", false],
			["answer:enemy_tank", true], ["answer:enemy_bomber", false]]:
		assert_eq(Line.make("x", &"idle", StringName(c[0])).passes(ctx), c[1], c[0])
	assert_false(Line.make("x", &"idle", &"died").passes({}), "a missing key fails the line")
	assert_true(Line.make("x").passes({}), "no condition, always said")


func test_cues_parse_and_come_due() -> void:
	var c := Cue.parse("at 15: spawn chaser 2")
	assert_eq([c.when, c.value, c.action, c.archetype, c.count, c.problem], [&"at", 15.0, &"spawn", &"chaser", 2, ""])
	c = Cue.parse("kills 10: say proud: Ten!")
	assert_eq([c.when, c.action, c.line.expression, c.line.text], [&"kills", &"say", &"proud", "Ten!"])
	assert_false(c.due({"kills": 9}))
	assert_true(c.due({"kills": 10}))
	c = Cue.parse("hit: say Ouch.")
	assert_true(c.due({"hit": true}))
	assert_eq(Cue.parse("at 40: event wrong_variable").target, &"wrong_variable")
	for bad in ["at x: say hi", "soon: say hi", "at 5: dance", "at 5: spawn dragon", "at 5 say hi",
			"hit 3: say hi", "at 5: spawn chaser 0", "at 5: edit"]:
		assert_ne(Cue.parse(bad).problem, "", bad)


# --- M42: the hp cue time and the `ended` line condition -----------------------------

func test_hp_cue_parses_and_fires_once_at_or_below() -> void:
	var c := Cue.parse("hp 2: edit edit_slowmo")
	assert_eq([c.problem, c.when, c.value, c.action, c.target], ["", &"hp", 2.0, &"edit", &"edit_slowmo"])
	assert_false(c.due({"hp": 3.0}), "above the threshold")
	assert_true(c.due({"hp": 2.0}), "at it")
	assert_true(c.due({"hp": 1.0}), "below it")
	assert_false(c.due({"hp": 0.0}), "a death never fires it")
	assert_false(c.due({"hp": -1.0}), "-1: no health (or no player)")
	assert_false(c.due({}), "no hp in the context")
	assert_ne(Cue.parse("hp: edit edit_slowmo").problem, "", "hp needs a number")


func test_hp_cue_needs_health() -> void:
	var s := _session(&"hp_fixture", SessionDef.KILLS, 10.0)
	s.basics = [&"movement", &"shooting"]
	s.cues = PackedStringArray(["hp 2: edit edit_slowmo"])
	assert_string_contains("
".join(s.problems()), "hp needs the health basic")
	s = _session(&"hp_fixture", SessionDef.KILLS, 10.0)
	s.basics = [&"movement", &"shooting", &"health"]
	s.cues = PackedStringArray(["hp 2: edit edit_slowmo"])
	assert_eq(s.problems(), [] as Array[String], "with health: fine")
	s = _session(&"hp_fixture", SessionDef.KILLS, 10.0)
	s.basics = [&"movement"]
	s.cues = PackedStringArray(["at 5: add health", "hp 2: say worried: Careful."])
	assert_eq(s.problems(), [] as Array[String], "a cue that adds health is enough")


func test_the_session_runner_reads_hp_only_with_health() -> void:
	var game := await _game(&"s1_01_move")
	assert_false(Unlocks.has_basic(&"health"))
	assert_eq(game.session_runner._player_hp(), -1.0, "no health yet: hp cues never fire")
	RunState.add_basic(&"health")
	var h := Component.find(game.player, Health) as Health
	assert_eq(game.session_runner._player_hp(), h.hp(), "with health: the player's HP")


func test_ended_condition() -> void:
	var l := Line.parse("ended happy: x")
	assert_eq([l.problem, l.when, l.expression], ["", &"ended", &"happy"])
	assert_true(l.passes({"outcome": &"won"}), "won")
	assert_true(l.passes({"outcome": &"stopped"}), "stopped")
	assert_false(l.passes({"outcome": &"died"}), "died: a Retry may follow")
	assert_false(l.passes({"outcome": &"died", "moved_on": false}))
	assert_true(l.passes({"outcome": &"died", "moved_on": true}), "died, then Move on")
	assert_false(l.passes({}), "no outcome (intro, cues): never")
	var s := _session(&"ended_fixture")
	s.intro = PackedStringArray(["ended happy: too early"])
	assert_string_contains("
".join(s.problems()), "intro line cannot depend on the outcome")
	s = _session(&"ended_fixture")
	s.cues = PackedStringArray(["at 5: say ended happy: x"])
	assert_string_contains("
".join(s.problems()), "cannot depend on the outcome")
	s = _session(&"ended_fixture")
	s.debrief = PackedStringArray(["ended happy: x"])
	assert_eq(s.problems(), [] as Array[String], "a debrief line may wait for the end")
	var ctx := CampaignDB.line_context(s, &"died", 0, [], true)
	assert_true(ctx.moved_on)
	assert_false(CampaignDB.line_context(s, &"died").moved_on)
	assert_false(CampaignDB.line_context(s).has("moved_on"), "no outcome, no moved_on")


## A fixture session with `ended` lines (S6 is content; this pins the code path).
func _ended_session() -> SessionDef:
	var s := _session(&"ended_fixture", SessionDef.KILLS, 10.0)
	s.debrief = PackedStringArray(["died guilty: That one's on me.", "stopped thinking: Time's up.",
			"ended happy: It's over.", "ended thinking: What next?"])
	s.notes = PackedStringArray(["A fixture note"])
	return s


func _debrief() -> DebriefScreen:
	var d := DebriefScreen.new()
	add_child_autofree(d)
	d.input_delay = 0.0
	return d


func test_ended_lines_play_on_a_won_or_stopped_debrief() -> void:
	var d := _debrief()
	d.open(_ended_session(), &"win", 0)
	d.finish_lines()
	assert_eq(d.said, ["It's over.", "What next?"] as Array[String])
	assert_eq(d.choices(), [DebriefScreen.NEXT])
	d.close()


func test_a_death_then_move_on_plays_the_ended_lines_then_the_notes() -> void:
	var d := _debrief()
	d.open(_ended_session(), &"lose", 2)
	assert_false(d.lines.any(func(l: Line) -> bool: return l.when == &"ended"), "Retry may follow: no ending yet")
	d.finish_lines()
	assert_eq(d.said, ["That one's on me."] as Array[String])
	assert_eq(d.choices(), [DebriefScreen.RETRY, DebriefScreen.MOVE_ON])
	assert_eq(d._notes.text, "", "no notes before Move on")
	var moved := []
	d.move_on_requested.connect(func() -> void: moved.append(true))
	assert_true(d.choose(DebriefScreen.MOVE_ON))
	assert_eq(moved.size(), 0, "the ending plays first")
	assert_eq(d.phase, DebriefScreen.LINES)
	d.finish_lines()
	assert_eq(d.said, ["That one's on me.", "It's over.", "What next?"] as Array[String])
	assert_eq(d.choices(), [DebriefScreen.NEXT])
	assert_string_contains(d._notes.text, "A fixture note")
	assert_true(d.choose(DebriefScreen.NEXT))
	assert_eq(moved.size(), 1, "then the way on moves on")
	d.close()


func test_move_on_without_ended_lines_or_a_fork_moves_on_at_once() -> void:
	var d := _debrief()
	var s := _session(&"plain_fixture", SessionDef.KILLS, 10.0)
	s.debrief = PackedStringArray(["died guilty: Oops."])
	d.open(s, &"lose", 0)
	d.finish_lines()
	var moved := []
	d.move_on_requested.connect(func() -> void: moved.append(true))
	assert_true(d.choose(DebriefScreen.MOVE_ON))
	assert_eq(moved.size(), 1, "S0-S5 as before")
	d.close()


# --- M42: S6, the end of Stage 1 ------------------------------------------------------

func test_s6_is_the_playground() -> void:
	var s := CampaignDB.get_session(&"s1_06_playground")
	assert_eq(s.problems(), [] as Array[String])
	assert_eq([s.goal, s.goal_value, s.time_limit, s.spawn_rate, s.spawn_cap, s.bump, s.fork],
			[SessionDef.KILLS, 60.0, 240.0, 1.3, 1.3, &"minor", &""])   # M42 E-S6b: 1.2 -> 1.3
	assert_true(&"version" in s.basics, "the stamp from frame one")
	var edits: Array = s.cue_list().map(func(c: Cue) -> Array: return [c.when, c.value, c.target])
	assert_eq(edits, [[&"at", 10.0, &"edit_gift_explode"], [&"kills", 20.0, &"edit_big_enemies"],
			[&"kills", 40.0, &"edit_inverted"], [&"hp", 2.0, &"edit_slowmo"]])


## M43: the last session is the data's (S7 today); S6 offers Next.
func test_the_last_session_offers_to_be_continued() -> void:
	var last := CampaignDB.session(CampaignDB.size() - 1)
	var d := _debrief()
	d.open(last, &"win", 0)
	d.finish_lines()
	assert_eq(d.choices(), [DebriefScreen.LAST])
	d.close()
	d = _debrief()
	d.open(CampaignDB.get_session(&"s1_06_playground"), &"win", 0)
	d.finish_lines()
	assert_true(d.said.has("Okay. It's a game. A small one."))
	assert_eq(d.choices(), [DebriefScreen.NEXT], "S6 is no longer the last (M43)")
	assert_string_contains(d._notes.text, "A small game")
	d.close()
	d = _debrief()
	d.open(CampaignDB.get_session(&"s1_05_wrong"), &"win", 0)
	d.finish_lines()
	assert_eq(d.choices(), [DebriefScreen.NEXT], "S5 is no longer the last")
	d.close()
	assert_string_contains(DebriefScreen.notes_text(CampaignDB.get_session(&"s1_06_playground")), "A small game")


func test_s6_died_then_move_on_still_ends_the_stage() -> void:
	var d := _debrief()
	d.open(CampaignDB.get_session(&"s1_06_playground"), &"lose", 3)
	d.finish_lines()
	assert_true(d.said.has("That one's on me. Want another go, or should I just patch it?"))
	assert_false(d.said.has("Okay. It's a game. A small one."))
	assert_eq(d.choices(), [DebriefScreen.RETRY, DebriefScreen.MOVE_ON])
	var moved := []
	d.move_on_requested.connect(func() -> void: moved.append(true))
	assert_true(d.choose(DebriefScreen.MOVE_ON))
	assert_eq(moved.size(), 0)
	d.finish_lines()
	assert_true(d.said.has("Okay. It's a game. A small one."))
	assert_true(d.said.has("Next: what kind of shooter is it?"))
	assert_eq(d.choices(), [DebriefScreen.NEXT], "M43: Stage 2 comes next")
	assert_string_contains(d._notes.text, "A small game")
	assert_true(d.choose(DebriefScreen.NEXT))
	assert_eq(moved.size(), 1)
	d.close()


func test_s6_retry_does_not_play_the_ending() -> void:
	var d := _debrief()
	d.open(CampaignDB.get_session(&"s1_06_playground"), &"lose", 3)
	assert_false(d.lines.any(func(l: Line) -> bool: return l.when == &"ended"))
	d.finish_lines()
	var retried := []
	d.retry_requested.connect(func() -> void: retried.append(true))
	assert_true(d.choose(DebriefScreen.RETRY))
	assert_eq(retried.size(), 1)
	assert_false(d.said.has("Okay. It's a game. A small one."))
	d.close()


func test_done_campaign_shows_to_be_continued() -> void:
	SaveGame.go_live(TEST_PATH, true)
	for i in CampaignDB.size():
		assert_false(CampaignDB.is_done(), "not done before session %d" % i)
		CampaignDB.complete(CampaignDB.session(i))
	assert_true(CampaignDB.is_done())
	assert_eq(SaveGame.version().label(), "v0.8.0", "eight minor bumps (M43: S7)")
	assert_true(StartScreen.campaign_line().ends_with("· to be continued"), StartScreen.campaign_line())
	var screen := await _screen()
	assert_false(screen.continue_button.visible)


func test_a_broken_campaign_reports_each_problem() -> void:
	var c := CampaignDef.new()
	var a := _session(&"a")
	a.stage = 2
	a.basics = [&"teleport"]
	a.enemies = [&"chaser"]
	a.intro = PackedStringArray(["won happy: too early"])
	a.cues = PackedStringArray(["at 5: event no_such_event", "at 6: edit edit_nope", "soon: say hi", "at 3: say died: no",
			"at 7: say event:wrong_variable happy: x"])
	a.ships = [&"no_such_change"]
	a.fork = &"fork_enemy"
	var b := _session(&"a", &"dance")
	b.stage = 1
	b.fork = &"fork_enemy"
	b.more_forks = [&"fork_mascot", &"fork_mascot", &"no_such_fork"] as Array[StringName]
	var d := _session(&"d")
	d.stage = 1
	d.more_forks = [&"fork_mascot"] as Array[StringName]
	b.time_limit = 30.0
	b.look = "neon"
	b.bump = &"major"
	c.sessions = [a, b, d]
	var text := "\n".join(CampaignDB.problems(c))
	for expected in ["unknown basic teleport", "enemies listed without the enemies basic",
			"intro line cannot depend on the outcome", "unknown event no_such_event", "a cue line cannot depend on an event", "unknown edit edit_nope", "unknown cue time",
			"cannot depend on the outcome", "ships unknown change no_such_change", "unknown goal dance",
			"time_limit is for kills goals only", "no look neon", "bump must be patch or minor",
			"listed twice", "goes back to stage 1", "fork fork_enemy is asked twice",
			"fork fork_mascot is asked twice", "no fork no_such_fork", "fork fork_mascot is asked twice (a, d)"]:
		assert_string_contains(text, expected)


# --- Goals -------------------------------------------------------------------------

func _loop(kind: StringName, value: float, limit := 0.0) -> RunLoop:
	RunState.reset(7)
	var loop := RunLoop.new()
	loop.set_goal(kind, value, limit)
	add_child_autofree(loop)
	loop.begin()
	return loop


func test_a_survive_goal_wins_when_its_clock_runs_out() -> void:
	var loop := _loop(SessionDef.SURVIVE, 30.0)
	await wait_physics_frames(3)
	assert_false(loop.is_over())
	assert_eq(loop.goal_text().left(7), "Survive")
	loop.goal_clock = 29.99
	await wait_physics_frames(3)
	assert_true(loop.is_over())
	assert_eq(loop.outcome, &"win")
	assert_eq(loop.record.session, "")
	assert_eq(loop.record.goal.kind, "survive")


func test_a_held_clock_does_not_count() -> void:
	var loop := _loop(SessionDef.SURVIVE, 30.0)
	await wait_physics_frames(2)
	loop.hold_clock(&"event", true)
	var held := loop.goal_clock
	await wait_physics_frames(30)
	assert_eq(loop.goal_clock, held)
	assert_true(loop.clock_held())
	loop.hold_clock(&"event", false)
	await wait_physics_frames(30)
	assert_gt(loop.goal_clock, held + 0.3)


func test_a_kills_goal_wins_at_its_count_and_stops_at_its_limit() -> void:
	var loop := _loop(SessionDef.KILLS, 5.0, 60.0)
	await wait_physics_frames(2)
	assert_eq(loop.goal_text(), "Kills 0/5")
	RunState.kills = 5
	await wait_physics_frames(2)
	assert_eq(loop.outcome, &"win")
	loop = _loop(SessionDef.KILLS, 5.0, 60.0)
	loop.goal_clock = 60.0
	await wait_physics_frames(2)
	assert_eq(loop.outcome, RunLoop.STOPPED)


func test_a_stop_goal_ends_stopped_after_the_read_beat() -> void:
	var loop := _loop(SessionDef.STOP, 5.0)
	loop.goal_clock = 5.0
	await wait_physics_frames(2)
	assert_true(loop.stop_said)
	assert_false(loop.is_over(), "the AI's line gets its read time")
	loop.goal_clock = 5.0 + Tuning.smoke_stop_read
	await wait_physics_frames(2)
	assert_eq(loop.outcome, RunLoop.STOPPED)


# --- A session in the game scene ----------------------------------------------------

func test_the_first_session_cannot_move_and_has_nothing() -> void:
	var game := await _game(&"s1_00_nothing")
	assert_eq(RunState.session.id, &"s1_00_nothing")
	assert_true(game.player.movement_locked)
	assert_true(game.player.shooting_locked, "no gun at first (owner, 2026-11-23)")
	assert_true(game.player.dash_locked, "no dash at first")
	assert_false(game.spawner.enabled)
	assert_eq(game.arena.blocks.size(), 4, "no level: an empty box")
	assert_false(game.director.enabled, "no prompts in the campaign")
	assert_eq(Unlocks.pool(), [] as Array[Mutation])
	assert_eq(Unlocks.look(), {"tier": 0, "take": ""})
	assert_eq(game.run_loop.goal, SessionDef.STOP)
	assert_eq(game.session_runner.said, ["_"], "the first intro line is said at once")
	assert_string_contains(Main.boot_line(), "session s1_00_nothing")


func test_movement_comes_alone_for_five_seconds() -> void:
	var game := await _game(&"s1_01_move")
	assert_false(game.player.movement_locked)
	assert_true(game.player.shooting_locked)
	assert_false(game.spawner.enabled, "no enemies basic: nothing spawns")
	assert_eq(game.run_loop.goal, SessionDef.STOP)
	assert_eq(game.hud.goal_shown(), "", "no goal text (owner, 2026-11-23)")
	assert_eq(game.run_loop.goal_value + Tuning.smoke_stop_read, 5.0, "5 s in all")
	game.run_loop.goal_clock = 3.0
	await wait_physics_frames(3)
	assert_eq(game.session_runner.fired_count(), 1, "the AI's 'ok!' at 3 s")
	game.run_loop.goal_clock = 5.0
	await wait_physics_frames(3)
	assert_eq(game.run_loop.outcome, RunLoop.STOPPED)


func test_enemies_overrun_you_and_dying_is_the_way_on() -> void:
	var game := await _game(&"s1_02_enemies")
	assert_true(game.spawner.enabled)
	assert_true(game.player.shooting_locked, "dodge only: the gun ships after this session")
	assert_eq(game.run_loop.goal, SessionDef.OVERRUN)
	assert_eq(game.hud.goal_shown(), "", "no goal text: more just keep coming")
	assert_eq(game.spawner.current_cap(), int(RunState.rules.max_enemies * 0.12))
	game.run_loop.goal_clock = 1.0
	await wait_physics_frames(3)
	assert_gte(RunState.count(&"enemy"), 1, "the AI drops the first chaser by hand")
	game.run_loop.goal_clock = 22.0
	await wait_physics_frames(3)
	assert_gt(RunState.count(&"enemy"), game.spawner.current_cap(),
			"the cues pile on past the spawner's cap")
	game.run_loop.end(&"lose")
	await wait_physics_frames(int(Tuning.report_delay * 60) + 5)
	assert_eq(game.debrief.outcome, &"died")
	assert_true(game.debrief.death_expected())
	_through_lines(game)
	assert_eq(game.debrief.choices(), [DebriefScreen.NEXT], "no Retry: going down is the end")
	assert_false(game.debrief.choose(DebriefScreen.RETRY))
	var texts := game.debrief.lines.map(func(l: Line) -> String: return l.text)
	assert_eq(texts[0], "too many. my fault. sorry.")
	game._end_session(&"next")
	assert_eq(CampaignDB.current().id, &"s1_03_shooting")
	assert_eq(SaveGame.version().label(), "v0.1.0", "the session counts as done")


func test_an_overrun_survived_to_the_end_is_stopped() -> void:
	var loop := _loop(SessionDef.OVERRUN, 45.0, 0.0)
	loop.goal_clock = 45.0
	loop._update_goal()
	assert_eq(loop.outcome, RunLoop.STOPPED)


func test_shooting_comes_with_a_kill_count() -> void:
	var game := await _game(&"s1_03_shooting")
	assert_false(game.player.shooting_locked)
	assert_true(game.player.dash_locked, "the dash ships after this session")
	assert_eq(game.run_loop.goal, SessionDef.KILLS)
	assert_eq(game.hud.goal_shown(), "Kills 0/15")
	RunState.kills = 1
	await wait_physics_frames(3)
	assert_eq(game.session_runner.fired_count(), 1, "the first kill: 'Oh. That works.'")
	RunState.kills = 15
	await wait_physics_frames(3)
	assert_eq(game.run_loop.outcome, &"win")


func test_a_death_offers_retry_and_move_on() -> void:
	var game := await _game(&"s1_03_shooting")
	assert_eq(game.arena.blocks.size(), 4, "the level ships with this session")
	game.run_loop.end(&"lose")
	await wait_physics_frames(int(Tuning.report_delay * 60) + 5)
	assert_true(game.debrief.is_open())
	assert_eq(game.debrief.outcome, &"died")
	assert_eq(game.debrief.choices(), [] as Array[String], "no buttons while the lines play")
	_through_lines(game)
	assert_null(game.debrief.fork(), "a death does not ask the fork before Move on")
	assert_eq(game.debrief.choices(), [DebriefScreen.RETRY, DebriefScreen.MOVE_ON])
	assert_eq(game.debrief.lines.map(func(l: Line) -> String: return l.text)[0],
			"Too many at once. My fault.", "the died line comes first")
	game._end_session(&"retry")
	assert_eq(SaveGame.attempts(&"s1_03_shooting"), 1)
	assert_eq(CampaignDB.current().id, &"s1_03_shooting", "Retry plays the same session")
	assert_eq(CampaignDB.attempt(&"s1_03_shooting"), 2)
	game._end_session(&"move_on")
	assert_eq(CampaignDB.current().id, &"s1_04_level", "Move on counts the session as done")
	assert_eq(SaveGame.version().label(), "v0.1.0")


## A Space tap meant for the line before the cards cannot press the focused card: the
## cards wait input_delay like the buttons (M42.1 review).
func test_the_cards_ignore_a_press_right_after_they_show() -> void:
	var game := await _game(&"s1_03_shooting")
	game.run_loop.goal_clock = 120.0
	await wait_physics_frames(int(Tuning.report_delay * 60) + 5)
	var d := game.debrief
	d.input_delay = 0.0
	d.finish_lines()
	assert_eq(d.phase, DebriefScreen.FORK)
	d.input_delay = 0.4   # the cards' clock started as they showed
	await wait_physics_frames(1)
	assert_false(d.cards_ready())
	(d._cards.get_child(0) as Button).pressed.emit()
	assert_eq(d.phase, DebriefScreen.FORK, "the stray press picked nothing")
	assert_true(d.picks.is_empty())
	d._cards_msec -= 1000   # a second later (the debrief pauses the tree: no wait_seconds)
	assert_true(d.cards_ready())
	(d._cards.get_child(0) as Button).pressed.emit()
	assert_eq(d.picks.size(), 1, "a press after the delay picks")


func test_a_won_session_asks_its_fork_then_shows_its_notes() -> void:
	var game := await _game(&"s1_03_shooting")
	game.run_loop.goal_clock = 120.0
	await wait_physics_frames(int(Tuning.report_delay * 60) + 5)
	assert_true(game.debrief.is_open())
	assert_eq(game.debrief.outcome, &"stopped", "the time limit ran out before 15 kills")
	assert_eq(game.debrief.big_body.id, MascotBody.CARET, "no face yet: the caret")
	var texts := game.debrief.lines.map(func(l: Line) -> String: return l.text)
	assert_false("Too many at once. My fault." in texts)
	assert_true("Time's up. Close enough." in texts)
	game.debrief.input_delay = 0.0
	game.debrief.finish_lines()
	assert_eq(game.debrief.phase, DebriefScreen.FORK)
	assert_eq(game.debrief.said[-1], "I think I need a face. Which one is me?", "the question is its last line")
	assert_eq(game.debrief.fork_options().map(func(c: Change) -> StringName: return c.id),
			[&"mascot_cursor", &"mascot_window", &"mascot_blob"])
	assert_eq(game.debrief.choices(), [] as Array[String], "no way on before a pick")
	assert_true(game.debrief.pick(2))
	assert_eq(game.debrief.big_body.id, &"blob", "the picked body pops in at once")
	# M42.1: then the dash, in the owner's words, three cards.
	assert_eq(RunState.session.asked_forks(), [&"fork_mascot", &"fork_dash", &"fork_dash_aim"] as Array[StringName])
	game.debrief.finish_lines()
	assert_eq(game.debrief.phase, DebriefScreen.FORK)
	assert_true(game.debrief.said.has("Better. Right? I feel... squishy."))
	assert_eq(game.debrief.said[-1], "I think a dash would feel good. What do you want?")
	assert_eq(game.debrief.fork_options().map(func(c: Change) -> StringName: return c.id),
			[&"dash_classic", &"dash_grapple", &"dash_teleport"])
	assert_eq(game.debrief.choices(), [] as Array[String], "no way on before the second pick")
	assert_true(game.debrief.pick(1))
	assert_eq(game.debrief.big_body.id, &"blob", "the body stays")
	game.debrief.finish_lines()
	assert_true(game.debrief.said.has("A hook! I've always wanted to throw something."))
	# M42.2: then where it goes, two cards, aim first.
	assert_eq(game.debrief.phase, DebriefScreen.FORK)
	assert_eq(game.debrief.choices(), [] as Array[String], "no way on before the third pick")
	assert_eq(game.debrief.said[-1], "And should it go where you aim, or where you're moving?")
	assert_eq(game.debrief.fork_options().map(func(c: Change) -> StringName: return c.id),
			[&"dashdir_aim", &"dashdir_move"])
	assert_true(game.debrief.pick(0))
	game.debrief.finish_lines()
	assert_eq(game.debrief.said[-1], "Point and go. I like that.")
	assert_eq(game.debrief.choices(), [DebriefScreen.NEXT])
	assert_eq(game.debrief.picked.id, &"mascot_blob", "picked: the first pick")
	assert_eq(game.debrief.more_picks().map(func(c: Change) -> StringName: return c.id),
			[&"dash_grapple", &"dashdir_aim"])
	assert_eq(DebriefScreen.notes_text(RunState.session, game.debrief.picked, game.debrief.more_picks()),
			"v0.1.0 · what changed\n  • Bullets that hit things now\n  • A level\n  • Enemies that shoot back\n  • A face: Blob\n  • A grappling hook (Shift or right click)\n  • The dash goes where you aim")
	assert_eq(game.debrief._notes.text, DebriefScreen.notes_text(RunState.session, game.debrief.picked,
			game.debrief.more_picks()))
	var rec := CampaignDB.telemetry_record(RunState.session, {}, &"stopped", 0, &"next", "", game.debrief.picked,
			[] as Array[String], [], [], game.debrief.more_picks())
	assert_eq(rec.fork.id, "fork_mascot", "fork: the first pick, as before")
	assert_eq((rec.forks as Array).size(), 3)
	assert_eq(rec.forks[1], {"id": "fork_dash", "pick": "dash_grapple", "shelved": ["dash_classic", "dash_teleport"]})
	assert_eq(rec.forks[2], {"id": "fork_dash_aim", "pick": "dashdir_aim", "shelved": ["dashdir_move"]})
	assert_eq(rec.dash, "grapple")
	assert_eq(rec.dash_aim, "aim")
	assert_eq(rec.mascot, "blob")
	var ended := []
	game.debrief.next_requested.connect(func() -> void: ended.append(true))
	assert_true(game.debrief.choose(DebriefScreen.NEXT))
	assert_eq(ended.size(), 1)
	assert_eq(CampaignDB.current().id, &"s1_04_level")
	assert_eq(SaveGame.campaign().done, ["s1_03_shooting"])
	assert_eq(SaveGame.mascot(), &"blob", "the pick gives the AI its body")
	assert_true(SaveGame.has_shipped(&"mascot_blob"))
	assert_true(ChangeDB.get_fork(&"fork_mascot").is_answered())
	assert_true(SaveGame.has_shipped(&"dash_grapple"))
	assert_eq(Unlocks.dash_answer(), &"grapple")
	assert_true(SaveGame.has_shipped(&"dashdir_aim"))
	assert_eq(Unlocks.dash_aim_answer(), &"aim")
	assert_eq(SaveGame.version().label(), "v0.1.0", "one bump for the session, none per pick")


func test_move_on_asks_the_fork_then_moves_on() -> void:
	var game := await _game(&"s1_03_shooting")
	game.run_loop.end(&"lose")
	await wait_physics_frames(int(Tuning.report_delay * 60) + 5)
	_through_lines(game)
	var moved := []
	game.debrief.move_on_requested.connect(func() -> void: moved.append(true))
	assert_true(game.debrief.choose(DebriefScreen.MOVE_ON))
	assert_eq(moved.size(), 0, "the fork comes first")
	game.debrief.finish_lines()
	assert_eq(game.debrief.phase, DebriefScreen.FORK)
	assert_true(game.debrief.pick(1))
	game.debrief.finish_lines()
	assert_eq(game.debrief.phase, DebriefScreen.FORK, "M42.1: then the dash")
	assert_eq(moved.size(), 0)
	assert_true(game.debrief.pick(2))
	game.debrief.finish_lines()
	assert_eq(game.debrief.phase, DebriefScreen.FORK, "M42.2: then where it goes")
	assert_eq(moved.size(), 0)
	assert_true(game.debrief.pick(1))
	game.debrief.finish_lines()
	assert_eq(game.debrief.choices(), [DebriefScreen.NEXT])
	assert_string_contains(game.debrief._notes.text, "A face: Window")
	assert_string_contains(game.debrief._notes.text, "A teleport (Shift or right click)")
	assert_true(game.debrief.choose(DebriefScreen.NEXT))
	assert_eq(moved.size(), 1, "its Next moves on")
	assert_eq(SaveGame.mascot(), &"window")
	assert_true(SaveGame.has_shipped(&"dash_teleport"))
	assert_false(SaveGame.has_shipped(&"dash_classic"))
	assert_true(SaveGame.has_shipped(&"dashdir_move"))


## M42.1: Retry asks no fork; a save already past S3 (an old save) is never asked the
## dash and plays classic.
func test_retry_asks_no_fork_and_an_old_save_stays_classic() -> void:
	var game := await _game(&"s1_03_shooting")
	game.run_loop.end(&"lose")
	await wait_physics_frames(int(Tuning.report_delay * 60) + 5)
	_through_lines(game)
	assert_null(game.debrief.fork())
	assert_true(game.debrief.choose(DebriefScreen.RETRY))
	assert_true(game.debrief.picks.is_empty())
	assert_false(ChangeDB.get_fork(&"fork_dash").is_answered())
	game.queue_free()
	await wait_physics_frames(2)
	SaveGame.go_inert()
	SaveGame.ship(&"mascot_blob", GameVersion.PATCH)
	SaveGame.set_mascot(&"blob")
	for id: StringName in [&"s1_04_level", &"s1_05_wrong", &"s1_06_playground"]:
		var d := _debrief()
		d.open(CampaignDB.get_session(id), &"win", 0)
		d.finish_lines()
		assert_true(d.fork() == null or d.fork().id != &"fork_dash", "%s never asks the dash" % id)
		d.close()
	var s4 := await _game(&"s1_04_level")
	assert_eq(Unlocks.dash_style(), &"classic")
	assert_eq((Component.find(s4.player, Dasher) as Dasher).style, &"classic")
	await wait_physics_frames(1)
	assert_string_contains(s4.hud._label.text, "dash ready")


func test_a_dash_line_condition_reads_the_saves_answer() -> void:
	SaveGame.go_inert()
	var ctx := CampaignDB.line_context(CampaignDB.get_session(&"s1_04_level"))
	assert_true(Line.parse("dash:classic happy: x").passes(ctx), "unanswered: classic")
	assert_false(Line.parse("dash:teleport happy: x").passes(ctx))
	SaveGame.ship(&"dash_teleport", GameVersion.PATCH)
	ctx = CampaignDB.line_context(CampaignDB.get_session(&"s1_04_level"))
	assert_true(Line.parse("dash:teleport happy: x").passes(ctx))
	assert_false(Line.parse("dash:classic happy: x").passes(ctx))
	assert_eq(Line.parse("dash:teleport happy: x").problem, "")
	assert_string_contains(Line.parse("dash:jetpack happy: x").problem, "unknown dash")


func test_debrief_lines_type_and_can_not_be_skipped_at_once() -> void:
	var game := await _game(&"s1_03_shooting")
	game.run_loop.end(&"lose")   # "Too many at once. My fault." first: a long line
	await wait_physics_frames(int(Tuning.report_delay * 60) + 5)
	var d: DebriefScreen = game.debrief
	assert_eq(d.said.size(), 1, "one line at a time")
	d._line_t = 0.0
	d.advance()
	assert_eq(d.said.size(), 1, "not in its first 0.3 s")
	d._process(DebriefScreen.MIN_LINE)
	d.advance()
	assert_true(d._typed(), "the first press finishes the typing")
	d._line_t = DebriefScreen.MIN_LINE
	d.advance()
	assert_eq(d.said.size(), 2, "the next press moves on")
	assert_true(d.big_body.talking, "it talks while it types")


## Plays the debrief's lines out at once and lets its buttons work.
func _through_lines(game: Main) -> void:
	game.debrief.input_delay = 0.0
	game.debrief.finish_lines()


func test_a_locked_gun_and_dash_do_nothing() -> void:
	var game := await _game(&"s1_01_move")
	var input := Fx.ScriptedInput.new()
	game.player.set_input(input)
	input.fire = true
	input.aim_dir = Vector2.RIGHT
	input.tap_dash()
	await wait_physics_frames(10)
	assert_eq(RunState.count(&"player_projectile"), 0, "no shot")
	assert_true(game.player.dasher.is_ready(), "no dash: the cooldown never started")
	assert_false(game.player.get_node("Aim").visible, "no barrel drawn")
	assert_eq(game.hud._label.text.contains("dash"), false, "the HUD does not offer a dash")


func test_outside_a_session_the_gun_and_dash_are_always_on() -> void:
	assert_true(Unlocks.has_basic(&"shooting"))
	assert_true(Unlocks.has_basic(&"dash"))
	SaveGame.go_live(TEST_PATH, true)
	assert_true(Unlocks.has_basic(&"shooting"), "the v6 loop never ships them")
	assert_false(Unlocks.has_basic(&"movement"))


func test_a_session_record_is_schema_4() -> void:
	var s := CampaignDB.get_session(&"s1_01_move")
	var rec := CampaignDB.telemetry_record(s, {"duration": 30.0, "goal": {"kind": "survive"}},
			&"won", 2, &"next", "M37")
	assert_eq(rec.schema, 4)
	assert_eq([rec.type, rec.session, rec.stage, rec.attempt, rec.outcome, rec.choice, rec.moved_on],
			["campaign", "s1_01_move", 1, 1, "won", "next", false])
	assert_eq([rec.hits_taken, rec.deaths, rec.duration], [2, 0, 30.0])
	for key in ["reactions", "edits", "events", "fork", "mascot", "reduce_flashing", "game_version"]:
		assert_true(rec.has(key), key)


# --- The save ------------------------------------------------------------------------

func test_a_new_save_is_schema_2_with_a_campaign_and_settings() -> void:
	var s := SaveGame.new_state()
	assert_eq(s.schema, 2)
	assert_eq(s.campaign, {"index": 0, "done": [], "attempts": {}, "events_seen": [], "mascot": "", "next": ""})
	assert_eq(s.settings, {"reduce_flashing": false, "asked": false})


func test_a_schema_1_save_is_kept_aside_and_a_campaign_starts() -> void:
	var text := "{\"schema\": 1, \"runs\": 7, \"shipped\": [\"enemy_tank\"]}"
	_write(text)
	SaveGame.go_live(TEST_PATH)
	assert_eq(SaveGame.last_load, SaveGame.OLD)
	assert_false(FileAccess.file_exists(TEST_PATH))
	assert_eq(FileAccess.get_file_as_string(SaveGame.old_path()), text)
	assert_eq(SaveGame.state().runs, 0)
	assert_eq(CampaignDB.current_index(), 0)
	assert_string_contains(StartScreen.campaign_line(), StartScreen.OLD_SAVE_LINE)


func test_the_campaign_round_trips_and_bad_types_are_corrupt() -> void:
	SaveGame.go_live(TEST_PATH, true)
	SaveGame.count_attempt(&"s1_01_move")
	SaveGame.campaign_done(&"s1_00_nothing", GameVersion.MINOR, [&"enemy_tank"] as Array[StringName], 1, &"s1_01_move")
	SaveGame.campaign_done(&"s1_00_nothing", GameVersion.MINOR, [] as Array[StringName], 1, &"s1_01_move")
	SaveGame.set_mascot(&"blob")
	SaveGame.mark_event_seen(&"wrong_variable")
	SaveGame.set_setting("reduce_flashing", true)
	assert_eq(SaveGame.version().label(), "v0.1.0", "a session done twice bumps once")
	var written: Dictionary = SaveGame.state().duplicate(true)
	SaveGame.go_inert()
	SaveGame.go_live(TEST_PATH)
	assert_eq(SaveGame.last_load, SaveGame.LOADED)
	assert_eq(SaveGame.state().campaign, written.campaign)
	assert_eq(SaveGame.state().settings, written.settings)
	assert_eq(SaveGame.shipped(), [&"enemy_tank"] as Array[StringName])
	SaveGame.go_inert()
	for bad in ["{\"campaign\": {\"index\": \"x\"}}", "{\"campaign\": {\"index\": -1}}",
			"{\"campaign\": {\"done\": [3]}}", "{\"campaign\": {\"attempts\": {\"a\": \"b\"}}}",
			"{\"campaign\": {\"mascot\": 3}}", "{\"settings\": {\"reduce_flashing\": \"yes\"}}",
			"{\"campaign\": []}"]:
		_delete_files()
		_write(bad)
		SaveGame.go_live(TEST_PATH)
		assert_eq(SaveGame.last_load, SaveGame.CORRUPT, bad)
		SaveGame.go_inert()


func test_a_session_reads_the_enemy_fork_answer() -> void:
	SaveGame.go_live(TEST_PATH, true)
	var s := _session(&"x")
	s.basics = [&"movement", &"enemies"]
	s.enemies = [&"chaser", SessionDef.FORK_ENEMY]
	assert_eq(s.enemy_types(), [&"chaser"] as Array[StringName], "unanswered: nothing more")
	SaveGame.ship(&"enemy_lancer", GameVersion.PATCH)
	assert_eq(s.enemy_types(), [&"chaser", &"lancer"] as Array[StringName])
	RunState.session = s
	assert_eq(Unlocks.enemies(), [&"chaser", &"lancer"] as Array[StringName])
	assert_true(Unlocks.has_basic(&"enemies"))
	assert_false(Unlocks.has_basic(&"level"))
	RunState.session = null


# --- The start screen and the settings -----------------------------------------------

func _screen() -> StartScreen:
	StartScreen.save_live = false   # the real save must not go live in a test
	StartScreen.legacy_loop = false
	var screen: StartScreen = load("res://ui/start_screen.tscn").instantiate()
	add_child_autofree(screen)
	await wait_process_frames(2)
	return screen


func test_the_start_screen_offers_continue_once_a_campaign_exists() -> void:
	SaveGame.go_live(TEST_PATH, true)
	var screen := await _screen()
	assert_eq(screen.save_label.text, "New campaign")
	assert_false(screen.continue_button.visible)
	assert_null(screen.start_button, "no v6 Start button")
	SaveGame.campaign_done(&"s1_00_nothing", GameVersion.MINOR, [] as Array[StringName], 1, &"s1_01_move")
	screen.refresh_campaign()
	assert_true(screen.continue_button.visible)
	assert_eq(screen.save_label.text, "Stage 1 · Session 1 · v0.1.0", "S0 was the first")
	screen.press_new_game()
	assert_eq(screen.new_button.text, StartScreen.NEW_ARMED, "the first click arms")


func test_reduce_flashing_is_asked_once_before_the_first_session() -> void:
	SaveGame.go_live(TEST_PATH, true)
	var screen := await _screen()
	var ran := [0]
	screen._ask_then(func() -> void: ran[0] += 1)
	assert_true(screen.flash_panel.visible)
	assert_eq(ran[0], 0)
	screen.answer_flashing(true)
	assert_eq(ran[0], 1)
	assert_true(SaveGame.reduce_flashing())
	assert_true(bool(SaveGame.setting("asked")))
	assert_true(screen.flashing.button_pressed)
	screen._ask_then(func() -> void: ran[0] += 1)
	assert_eq(ran[0], 2, "asked once")
	assert_false(screen.flash_panel.visible)


func test_reduce_flashing_halves_shake_and_drops_the_white_flash() -> void:
	var fx := ScreenFx.new()
	add_child_autofree(fx)
	var rig := CameraRig.new()
	add_child_autofree(rig)
	rig.shake(10.0)
	var full := rig.shake_left()
	SaveGame.state().settings.reduce_flashing = true
	var rig2 := CameraRig.new()
	add_child_autofree(rig2)
	rig2.shake(10.0)
	assert_almost_eq(rig2.shake_left(), full * 0.5, 0.001)
	assert_false(fx.flash(0.3))
	SaveGame.state().settings.reduce_flashing = false
	assert_true(fx.flash(0.3))


## Owner feedback (M39.1): S4 is 30 s, and the AI says what is new in it (the walls
## and the dash) before the player meets them, whatever its body. M42.2: and where the
## dash goes (in the dash's line; move while unanswered).
func test_s4_is_short_and_its_intro_names_the_walls_and_the_dash() -> void:
	var s := CampaignDB.get_session(&"s1_04_level")
	assert_eq(s.goal, &"survive")
	assert_eq(s.goal_value, 30.0)
	assert_true(&"level" in s.basics and &"dash" in s.basics)
	var words := {&"classic": "dash", &"grapple": "hook", &"teleport": "teleport"}
	for style: StringName in Change.DASHES:
		SaveGame.go_inert()
		SaveGame.ship(StringName("dash_%s" % style), GameVersion.PATCH)
		for mascot: StringName in Change.MASCOTS:
			SaveGame.set_mascot(mascot)
			var lines := Line.passing(s.intro_lines(), CampaignDB.line_context(s))
			assert_eq(lines.size(), 3, "3 spoken lines: %s %s" % [mascot, style])
			var said := " ".join(lines.map(func(l: Line) -> String: return l.text)).to_lower()
			assert_string_contains(said, "walls", "%s talks about the walls" % mascot)
			assert_string_contains(said, String(words[style]), "%s talks about the %s" % [mascot, style])
			assert_string_contains(said, "shift", "%s says how to use the %s" % [mascot, style])
			assert_string_contains(said, "where you move", "unanswered direction: move")
