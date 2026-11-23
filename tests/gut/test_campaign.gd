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
	assert_eq(CampaignDB.size(), 4)
	assert_eq(CampaignDB.session(0).id, &"s1_00_nothing", "S0: nothing")
	assert_eq(CampaignDB.index_of(&"s1_03_shooting"), 3)
	assert_null(CampaignDB.session(4))


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


func test_a_broken_campaign_reports_each_problem() -> void:
	var c := CampaignDef.new()
	var a := _session(&"a")
	a.stage = 2
	a.basics = [&"teleport"]
	a.enemies = [&"chaser"]
	a.intro = PackedStringArray(["won happy: too early"])
	a.cues = PackedStringArray(["at 5: edit edit_bouncy_walls", "soon: say hi", "at 3: say died: no"])
	a.ships = [&"no_such_change"]
	a.fork = &"fork_enemy"
	var b := _session(&"a", &"dance")
	b.stage = 1
	b.fork = &"fork_enemy"
	b.time_limit = 30.0
	b.look = "neon"
	b.bump = &"major"
	c.sessions = [a, b]
	var text := "\n".join(CampaignDB.problems(c))
	for expected in ["unknown basic teleport", "enemies listed without the enemies basic",
			"intro line cannot depend on the outcome", "edits come with M40", "unknown cue time",
			"cannot depend on the outcome", "ships unknown change no_such_change", "unknown goal dance",
			"time_limit is for kills goals only", "no look neon", "bump must be patch or minor",
			"listed twice", "goes back to stage 1", "fork fork_enemy is asked twice"]:
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
	game.run_loop.goal_clock = 50.0
	await wait_physics_frames(3)
	assert_gt(RunState.count(&"enemy"), game.spawner.current_cap(),
			"the cues pile on past the spawner's cap")
	game.run_loop.end(&"lose")
	await wait_physics_frames(int(Tuning.report_delay * 60) + 5)
	assert_eq(game.debrief.outcome, &"died")
	assert_true(game.debrief.death_expected())
	assert_eq(game.debrief.choices(), [DebriefScreen.NEXT], "no Retry: going down is the end")
	assert_false(game.debrief.choose(DebriefScreen.RETRY))
	var texts := game.debrief.lines.map(func(l: Line) -> String: return l.text)
	assert_eq(texts[0], "too many. my fault. sorry.")
	game._end_session(&"next")
	assert_eq(CampaignDB.current().id, &"s1_03_shooting")
	assert_eq(SaveGame.version().label(), "v0.1.0", "the session counts as done")


func test_an_overrun_survived_to_the_end_is_stopped() -> void:
	var loop := _loop(SessionDef.OVERRUN, 90.0, 0.0)
	loop.goal_clock = 90.0
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
	assert_eq(game.debrief.choices(), [DebriefScreen.RETRY, DebriefScreen.MOVE_ON])
	assert_eq(game.debrief.lines.map(func(l: Line) -> String: return l.text)[0],
			"Too many at once. My fault.", "the died line comes first")
	game._end_session(&"retry")
	assert_eq(SaveGame.attempts(&"s1_03_shooting"), 1)
	assert_eq(CampaignDB.current().id, &"s1_03_shooting", "Retry plays the same session")
	assert_eq(CampaignDB.attempt(&"s1_03_shooting"), 2)
	game._end_session(&"move_on")
	assert_true(CampaignDB.is_done(), "Move on counts the session as done")
	assert_eq(SaveGame.version().label(), "v0.1.0")


func test_a_won_session_shows_its_notes_and_moves_on() -> void:
	var game := await _game(&"s1_03_shooting")
	game.run_loop.goal_clock = 120.0
	await wait_physics_frames(int(Tuning.report_delay * 60) + 5)
	assert_true(game.debrief.is_open())
	assert_eq(game.debrief.outcome, &"stopped", "the time limit ran out before 15 kills")
	assert_eq(game.debrief.choices(), [DebriefScreen.LAST], "the last session so far")
	var texts := game.debrief.lines.map(func(l: Line) -> String: return l.text)
	assert_false("Too many at once. My fault." in texts)
	assert_true("Time's up. Close enough." in texts)
	assert_eq(DebriefScreen.notes_text(RunState.session), "v0.1.0 · what changed\n  • A level\n  • A dash (Shift or right click)")
	game._end_session(&"next")
	assert_true(CampaignDB.is_done())
	assert_eq(SaveGame.campaign().done, ["s1_03_shooting"])


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
	assert_eq(s.campaign, {"index": 0, "done": [], "attempts": {}, "events_seen": [], "mascot": ""})
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
	SaveGame.campaign_done(&"s1_00_nothing", GameVersion.MINOR, [&"enemy_tank"] as Array[StringName], 1)
	SaveGame.campaign_done(&"s1_00_nothing", GameVersion.MINOR, [] as Array[StringName], 1)
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
	SaveGame.campaign_done(&"s1_00_nothing", GameVersion.MINOR, [] as Array[StringName], 1)
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
