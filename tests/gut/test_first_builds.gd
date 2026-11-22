extends GutTest
## M29b: the broken first builds (PLAN v5 4.8). A new save misses the game's basics:
## v0.0.0 cannot move and has no enemies and no level; its run is a short smoke test.
## The first two dev sessions ship movement, then enemies and the level, before
## anything else.

const TEST_PATH := "user://save_first_builds_test/save.json"


func before_each() -> void:
	_delete_files()


func after_each() -> void:
	assert_ne(SaveGame.save_path if SaveGame.persist else "", SaveGame.DEFAULT_PATH,
			"no test may leave the real save live")
	SaveGame.go_inert()
	_delete_files()
	Taste.clear_session()
	Look.use(Unlocks.FULL_LOOK)
	RunState.reset(0)
	RunState.world = null


func _delete_files() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _run_ended() -> void:
	SaveGame.record_run(&"topdown", &"win", 20.0, SaveGame.state().taste)


func _game() -> Main:
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	return game


# --- What is missing ---------------------------------------------------------------

func test_a_new_save_misses_every_basic_and_inert_misses_none() -> void:
	assert_eq(Unlocks.missing_basics(), [] as Array[StringName], "inert: everything")
	SaveGame.go_live(TEST_PATH, true)
	assert_eq(Unlocks.missing_basics(), Unlocks.BASICS)
	SaveGame.ship(&"basic_movement", GameVersion.PATCH)
	assert_eq(Unlocks.missing_basics(), [&"enemies", &"level"] as Array[StringName])
	SaveGame.ship(&"basic_world", GameVersion.PATCH)
	assert_eq(Unlocks.missing_basics(), [] as Array[StringName])
	assert_string_contains(Unlocks.summary(), "missing=-")


func test_the_first_two_sessions_ship_the_basics_then_the_look_mockup_comes() -> void:
	SaveGame.go_live(TEST_PATH, true)
	var ids := DevSession.available().map(func(c: Change) -> String: return String(c.id))
	assert_eq(ids, ["basic_movement"], "only basics while one is missing")
	var expected := [["basic_movement", "v0.0.1"], ["basic_world", "v0.0.2"]]
	for step: Array in expected:
		_run_ended()
		var s := DevSession.plan(int(SaveGame.state().runs))
		assert_eq(s.shape, DevSession.BASIC)
		assert_true(s.cards.is_empty())
		assert_false(s.can_pick())
		assert_true(s.finish())
		assert_eq(s.ai_ship_id(), step[0])
		assert_eq(SaveGame.version().label(), step[1])
		var notes := s.notes_lines()
		assert_eq(notes[0], "Version %s" % step[1].trim_prefix("v"))
		assert_string_contains(notes[1], (ChangeDB.get_change(StringName(step[0])) as Change).pitch)
		assert_false(notes.has(DevSession.AI_LAST_LINE), "a basic is not the last of anything")
	_run_ended()
	var mock := DevSession.plan(3)
	assert_eq(mock.shape, DevSession.MOCKUP, "the look comes once the game plays")
	assert_true(mock.pick(0))
	assert_eq(SaveGame.version().label(), "v0.1.0")


func test_the_flow_goes_straight_to_the_patch_notes_for_a_basic() -> void:
	SaveGame.go_live(TEST_PATH, true)
	_run_ended()
	var flow := DevSessionFlow.new()
	add_child_autofree(flow)
	flow.start(DevSession.plan(1))
	assert_false(flow.screen.is_open())
	assert_true(flow.notes.is_open())
	assert_string_contains(flow.notes.text(), "Movement")
	assert_eq(flow.notes.play_label(), "Play v0.0.1")


# --- The v0.0.0 build ----------------------------------------------------------------

func test_v0_0_0_cannot_move_has_no_enemies_and_no_level() -> void:
	SaveGame.go_live(TEST_PATH, true)
	var game := await _game()
	assert_eq(game.arena.blocks.size(), 4, "only the border")
	assert_false(game.spawner.enabled)
	assert_false(game.director.enabled)
	assert_true(game.player.movement_locked)
	var input: Object = load("res://tests/gut/fixtures.gd").ScriptedInput.new()
	game.player.set_input(input)
	input.set(&"move", Vector2.RIGHT)
	input.set(&"dash_pressed", true)
	var start: Vector2 = game.player.global_position
	await wait_physics_frames(30)
	assert_almost_eq(game.player.global_position.distance_to(start), 0.0, 1.0, "WASD does nothing yet")
	assert_eq(RunState.count(&"enemy"), 0)


func test_v0_0_1_moves_but_still_has_nothing_to_shoot() -> void:
	SaveGame.go_live(TEST_PATH, true)
	SaveGame.ship(&"basic_movement", GameVersion.PATCH)
	var game := await _game()
	assert_false(game.player.movement_locked)
	assert_eq(game.arena.blocks.size(), 4)
	assert_false(game.spawner.enabled)
	assert_gt(game.run_loop.smoke_duration, 0.0, "still a smoke test")


func test_v0_0_2_is_the_full_run() -> void:
	SaveGame.go_live(TEST_PATH, true)
	SaveGame.ship(&"basic_movement", GameVersion.PATCH)
	SaveGame.ship(&"basic_world", GameVersion.PATCH)
	var game := await _game()
	assert_false(game.player.movement_locked)
	assert_gt(game.arena.blocks.size(), 4)
	assert_true(game.spawner.enabled)
	assert_true(game.director.enabled)
	assert_eq(game.run_loop.smoke_duration, 0.0)


func test_an_inert_game_is_the_full_run() -> void:
	var game := await _game()
	assert_false(game.player.movement_locked)
	assert_gt(game.arena.blocks.size(), 4)
	assert_eq(game.run_loop.smoke_duration, 0.0)


func test_a_smoke_test_ends_survived_after_its_time_with_no_prompt() -> void:
	SaveGame.go_live(TEST_PATH, true)
	var game := await _game()
	assert_gt(game.run_loop.smoke_time_left(), 0.0)
	RunState.game_time = Tuning.smoke_test_duration
	await wait_physics_frames(2)
	assert_true(game.run_loop.is_over())
	var rec: Dictionary = game.run_loop.record
	assert_eq(rec.outcome, "win")
	assert_true(rec.smoke_test)
	assert_eq(rec.missing_basics, ["movement", "enemies", "level"])
	assert_eq(game.director.prompt_index, 0, "no prompt in a smoke test")
	var text := ReportScreen.report_text(&"win", rec)
	assert_true(text.begins_with("SMOKE TEST OF v0.0.0"))
	assert_string_contains(text, "You tried to move")
	RunState.set_pause(&"report", false)


## Owner, 2026-11-22: the first run is too long. Without movement the AI gives up at
## 5 s, with most of the countdown left, and says so; the run ends once it is read.
func test_the_ai_stops_the_build_that_cannot_move_after_5_seconds() -> void:
	SaveGame.go_live(TEST_PATH, true)
	var game := await _game()
	RunState.game_time = Tuning.smoke_stop_time - 0.5
	await wait_physics_frames(2)
	assert_false(game.run_loop.smoke_stopped)
	assert_gt(game.run_loop.smoke_time_left(), 10.0, "the countdown shows the planned 20 s")
	RunState.game_time = Tuning.smoke_stop_time
	await wait_physics_frames(2)
	assert_true(game.run_loop.smoke_stopped)
	assert_false(game.run_loop.is_over(), "the line gets its time on screen")
	assert_eq(game.transition.last_toast(), "AI: " + TopdownGenre.SMOKE_STOP_LINE)
	assert_lt(game.run_loop.smoke_time_left(), 0.0, "the countdown is gone")
	RunState.game_time = Tuning.smoke_stop_time + Tuning.smoke_stop_read
	await wait_physics_frames(2)
	assert_true(game.run_loop.is_over())
	var rec: Dictionary = game.run_loop.record
	assert_true(rec.smoke_stopped)
	assert_lt(Tuning.smoke_stop_time + Tuning.smoke_stop_read, Tuning.smoke_test_duration)
	var text := ReportScreen.report_text(&"win", rec)
	assert_true(text.begins_with("SMOKE TEST OF v0.0.0  -  STOPPED BY THE AI"), text.get_slice("\n", 0))
	RunState.set_pause(&"report", false)


func test_the_build_that_moves_plays_its_whole_smoke_test() -> void:
	SaveGame.go_live(TEST_PATH, true)
	SaveGame.ship(&"basic_movement", GameVersion.PATCH)
	var game := await _game()
	RunState.game_time = Tuning.smoke_test_duration - 1.0
	await wait_physics_frames(2)
	assert_false(game.run_loop.smoke_stopped)
	assert_false(game.run_loop.is_over())
	RunState.game_time = Tuning.smoke_test_duration
	await wait_physics_frames(2)
	assert_true(game.run_loop.is_over())
	assert_false(game.run_loop.record.smoke_stopped)
	RunState.set_pause(&"report", false)
