extends GutTest
## M6: the run loop (PLAN 8). Release-candidate wave, win, lose, the report,
## telemetry and the start screen's seed field. One compressed end-to-end run with
## the bot plays every phase in the real arena.

const TEST_LOG := "user://playtest_test/runs.jsonl"
const TUNING_KEYS: Array[String] = ["transition_long", "transition_short", "prompt_input_delay",
		"rc_duration", "report_delay", "first_prompt_min_gap", "prompt_min_gap", "prompt_max_gap", "first_prompt_kills",
		"toast_time"]

var game: Main
var ended: Array[StringName] = []
var _saved := {}


func before_each() -> void:
	for key in TUNING_KEYS:
		_saved[key] = Tuning.get(key)
	Tuning.transition_long = 0.0
	Tuning.transition_short = 0.0
	Tuning.prompt_input_delay = 0.0
	Tuning.rc_duration = 1.0
	Tuning.report_delay = 0.2
	ended.clear()
	EventBus.run_ended.connect(_on_run_ended)
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)


func after_each() -> void:
	EventBus.run_ended.disconnect(_on_run_ended)
	for key: String in _saved:
		Tuning.set(key, _saved[key])
	RunState.reset(0)
	RunState.world = null
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(TEST_LOG)


func _on_run_ended(outcome: StringName) -> void:
	ended.append(outcome)


func _kill_player() -> void:
	var health := Component.find(game.player, Health) as Health
	health.take(DamageInfo.make(999, &"contact", &"enemy"))


func _wait_report(max_frames := 120) -> void:
	for i in max_frames:
		if game.report.is_open():
			return
		await wait_physics_frames(1)


func test_last_prompt_starts_the_release_candidate_and_surviving_it_wins() -> void:
	RunState.invincible = true
	game.director.enabled = false
	assert_eq(game.run_loop.phase, RunLoop.PLAY)
	assert_eq(game.run_loop.rc_time_left(), -1.0)
	game.director.prompt_index = Tuning.prompts_per_run
	await wait_physics_frames(2)
	assert_eq(game.run_loop.phase, RunLoop.RELEASE_CANDIDATE)
	assert_eq(game.spawner.phase_rate, Tuning.rc_spawn_rate)
	assert_eq(game.spawner.phase_cap, Tuning.rc_spawn_cap)
	assert_gt(game.run_loop.rc_time_left(), 0.0)
	assert_eq(ended, [] as Array[StringName], "not over yet")

	await wait_physics_frames(int(Tuning.rc_duration * 60) + 5)
	assert_eq(ended, [&"win"] as Array[StringName])
	assert_false(game.spawner.enabled, "spawner stops")
	assert_false(game.director.enabled, "director stops")
	assert_false(game.report.is_open(), "the report waits a beat")
	await _wait_report()
	assert_true(game.report.is_open())
	assert_true(RunState.is_paused_for(&"report"))
	assert_true(game.report.text().begins_with("PLAYTEST OF v0.0.0  -  BUILD SURVIVED"))
	assert_true(game.run_loop.record.reached_release_candidate)


func test_a_pending_prompt_holds_the_release_candidate_back() -> void:
	RunState.invincible = true
	game.director.enabled = false
	game.director.prompt_index = Tuning.prompts_per_run
	game.director.pending = Offer.new()
	await wait_physics_frames(5)
	assert_eq(game.run_loop.phase, RunLoop.PLAY)
	game.director.pending = null
	await wait_physics_frames(2)
	assert_eq(game.run_loop.phase, RunLoop.RELEASE_CANDIDATE)


func test_dying_loses_once_and_closes_the_other_panels() -> void:
	game.director.enabled = false
	_kill_player()
	_kill_player()
	await wait_physics_frames(2)
	assert_eq(ended, [&"lose"] as Array[StringName])
	assert_true(game.patch_history.locked)
	assert_false(game.patch_history.open(), "no build log after the end")
	# A prompt that was about to open never shows.
	var offer := Offer.new()
	offer.cards = [MutationDB.all[0]]
	offer.line = "late"
	game.prompt_panel.open(offer)
	await wait_physics_frames(1)
	assert_false(game.prompt_panel.is_open())
	await _wait_report()
	assert_true(game.report.is_open())
	assert_true(game.report.text().begins_with("PLAYTEST OF v0.0.0  -  CRASHED AT BUILD 1"))
	# Winning afterwards changes nothing.
	game.run_loop.end(&"win")
	assert_eq(ended, [&"lose"] as Array[StringName])
	assert_eq(game.run_loop.outcome, &"lose")


func test_dying_with_a_prompt_open_dismisses_it() -> void:
	game.director.enabled = false
	game.director.open_prompt()
	await wait_physics_frames(1)
	assert_true(game.prompt_panel.is_open())
	_kill_player()
	assert_false(game.prompt_panel.is_open())
	assert_false(RunState.is_paused_for(&"prompt"))
	await _wait_report()
	assert_true(game.report.is_open())


func test_report_lists_the_build_log_sources_and_an_ai_line() -> void:
	game.director.enabled = false
	RunState.apply(MutationDB.get_mutation(&"auto_attack"))
	RunState.kills_by_source[&"base"] = 7
	RunState.kills_by_source[&"auto_attack"] = 2
	RunState.damage_by_source[&"base"] = 21.0
	game.run_loop.end(&"lose")
	var text := ReportScreen.report_text(&"lose", game.run_loop.record)
	var lines := text.split("\n")
	assert_true(lines[0].begins_with("PLAYTEST OF v0.0.0"))
	assert_true(lines[lines.size() - 1].begins_with("AI: "))
	assert_string_contains(text, "v0.2  " + MutationDB.get_mutation(&"auto_attack").title)
	assert_string_contains(text, "Base weapon")
	assert_false(text.contains("Rollbacks"), "rollbacks are parked (PLAN v5 1.3): no line")
	assert_string_contains(text, "Seed        %d" % RunState.run_seed)


func test_telemetry_record_has_the_run_and_appends_one_line_per_run() -> void:
	game.director.enabled = false
	var horde := MutationDB.get_mutation(&"horde_mode")
	RunState.log_event(&"prompt", {"index": 1, "offers": ["horde_mode", "auto_attack"],
			"pick": "horde_mode", "mandatory": false})
	RunState.apply(horde)
	RunState.revert(horde)
	RunState.kills_by_source[&"base"] = 3
	game.run_loop.end(&"lose")
	var rec := game.run_loop.record
	for key in ["schema", "session_id", "run_index", "seed", "outcome", "duration", "version",
			"kills", "kills_by_source", "events", "prompts", "reverts_used", "build", "bot", "charges",
			"ai_events"]:
		assert_true(rec.has(key), "record has %s" % key)
	assert_eq(rec.outcome, "lose")
	assert_eq(rec.build, Main.BUILD)
	assert_eq((rec.events as Array).map(func(e: Dictionary) -> String: return e.event),
			["apply", "revert"])
	assert_eq((rec.prompts as Array)[0].pick, "horde_mode")
	assert_eq(rec.kills_by_source, {"base": 3})

	Telemetry.log_path = TEST_LOG
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(TEST_LOG)
	assert_eq(Telemetry.append(rec), OK)
	var second := Telemetry.build_record(&"win")
	assert_eq(Telemetry.append(second), OK)
	assert_eq(second.run_index, rec.run_index + 1)
	assert_eq(second.session_id, rec.session_id)
	var lines := FileAccess.get_file_as_string(TEST_LOG).strip_edges().split("\n")
	assert_eq(lines.size(), 2)
	var back: Variant = JSON.parse_string(lines[0])
	assert_true(back is Dictionary, "each line is JSON")
	assert_eq((back as Dictionary).seed, float(rec.seed))
	assert_eq((JSON.parse_string(lines[1]) as Dictionary).outcome, "win")


func test_scenes_not_run_as_the_current_scene_write_no_telemetry() -> void:
	Telemetry.log_path = TEST_LOG
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(TEST_LOG)
	game.director.enabled = false
	game.run_loop.end(&"lose")
	assert_false(FileAccess.file_exists(TEST_LOG))


func test_seed_field_parsing() -> void:
	assert_eq(StartScreen.parse_seed(""), -1)
	assert_eq(StartScreen.parse_seed("  "), -1)
	assert_eq(StartScreen.parse_seed("1234"), 1234)
	assert_eq(StartScreen.parse_seed("-55"), 55)
	var word := StartScreen.parse_seed("gravity")
	assert_true(word >= 0)
	assert_eq(StartScreen.parse_seed("gravity"), word, "same text, same seed")


## Every phase in the real arena with the bot: every prompt answered through the
## panel, the release candidate, then the win and the report. No BIG prompt opens and
## nothing is rolled back (PLAN v5 1.3).
func test_compressed_run_end_to_end_with_the_bot() -> void:
	Tuning.first_prompt_min_gap = 0.5
	Tuning.prompt_min_gap = 0.5
	Tuning.prompt_max_gap = 1.0
	Tuning.first_prompt_kills = 1000
	Tuning.rc_duration = 2.0
	RunState.invincible = true
	game.player.set_bot(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 1200:
		if game.report.is_open():
			break
		if game.prompt_panel.can_choose():
			var cards: Array[Mutation] = game.prompt_panel.offer.cards
			game.prompt_panel.choose(rng.randi_range(0, cards.size() - 1))
		await wait_physics_frames(1)
	assert_true(game.report.is_open(), "the run reached its report")
	assert_eq(ended, [&"win"] as Array[StringName])
	var rec := game.run_loop.record
	assert_eq((rec.prompts as Array).size(), Tuning.prompts_per_run)
	assert_eq((rec.big_offers as Array).size(), 0, "no BIG prompt")
	assert_eq((rec.big_swaps as Array).size(), 0)
	assert_eq(rec.final_big, "")
	assert_eq(rec.reverts_used, 0)
	assert_true(rec.reached_release_candidate)
	assert_true(rec.bot)
	assert_gt(rec.duration, Tuning.rc_duration)
	assert_eq(game.director.charges, 0)
	assert_true(RunState.ai.is_empty())
	assert_eq(rec.ai_events, [], "the parked AI layer adds nothing")
	assert_eq(rec.charges, {"start": 0, "earned": 0, "used": 0})
