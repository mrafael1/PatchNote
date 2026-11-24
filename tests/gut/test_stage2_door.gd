extends GutTest
## M43 (PLAN v9 1.2, 1.13, 1.14, 2): the door to Stage 2. The save points at the next
## session by id (an M42.2 file maps its index), the end-of-Stage-1 save continues at S7
## with the stage card, the HP floor, the S7 stub, and the reactions by session id.

const TEST_PATH := "user://save_stage2_door_test/save.json"
const FIXTURE := "res://tests/gut/save_m42_2_stage1_end.json"
const REACTIONS_FIXTURE := "res://tests/gut/stage2_reactions.json"
const STAGE1: Array[StringName] = [&"s1_00_nothing", &"s1_01_move", &"s1_02_enemies", &"s1_03_shooting",
		&"s1_04_level", &"s1_05_wrong", &"s1_06_playground"]
## The 30 reactions' old min_session / max_session (M42.2), frozen: the 1:1 conversion to
## after / until must fit exactly the same Stage 1 sessions.
const OLD_SESSIONS := {
	&"bomber_seen": [5, 5], &"camping": [3, -1], &"crowd_12": [3, -1], &"crowd_5": [4, -1],
	&"crowd_8": [3, -1], &"first_dash": [4, 4], &"first_hit": [4, -1], &"first_kill": [3, -1],
	&"here_they_come": [3, -1], &"hp_last": [3, -1], &"hp_two": [4, -1], &"kills_10": [3, -1],
	&"kills_25": [4, -1], &"kills_50": [6, -1], &"lancer_seen": [5, 5], &"last_seconds": [3, -1],
	&"near_miss": [4, -1], &"no_hit_15": [3, -1], &"no_hit_30": [3, -1], &"no_hit_60": [4, -1],
	&"not_shooting": [3, -1], &"quiet_25": [4, -1], &"session_half": [4, -1], &"shooter_seen": [4, 4],
	&"streak_3": [3, -1], &"streak_4": [4, -1], &"streak_6": [3, -1], &"streak_broken": [3, -1],
	&"tank_seen": [5, 5], &"wave_cleared": [3, -1],
}
## PLAN 1.13's audit: gated off on Auto (camping stays on every path, D8).
const AUTO_GATED: Array[StringName] = [&"not_shooting", &"crowd_12", &"kills_50", &"streak_3", &"streak_4",
		&"streak_6", &"streak_broken"]


func before_each() -> void:
	_delete_files()


func after_each() -> void:
	CampaignDB.active = false
	SaveGame.go_inert()
	_delete_files()
	RunState.reset(0)
	RunState.world = null


func _delete_files() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", "user://save_stage2_door_test/save.bad.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Loads `campaign` (with the rest of a new M42.2-shaped save) through a file, as a real
## old save would load: SaveGame.parse(), never a dict built from today's defaults.
func _load(campaign: Dictionary, shipped: Array = []) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_PATH.get_base_dir())
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema": 2, "version": [0, 7, 0], "shipped": shipped, "campaign": campaign}))
	f.close()
	SaveGame.use_snapshot(TEST_PATH)
	assert_eq(SaveGame.last_load, SaveGame.LOADED)


func _done(n: int) -> Array:
	return STAGE1.slice(0, n).map(func(id: StringName) -> String: return String(id))


func _game(id: StringName) -> Main:
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	if game.stage_card != null:
		game.stage_card.skip()   # it pauses the tree
	await wait_physics_frames(2)
	return game


# --- Save by id --------------------------------------------------------------------------

func test_an_m42_2_save_maps_its_index_through_the_old_order() -> void:
	_load({"index": 7, "done": _done(7), "attempts": {}, "events_seen": ["wrong_variable"], "mascot": "blob"})
	assert_false(SaveGame.campaign().has("next"), "a parsed M42.2 file has no next")
	assert_eq(CampaignDB.current().id, &"s2_01_tryout", "index 7 is the session after s1_06")
	_load({"index": 3, "done": _done(3), "attempts": {}, "mascot": ""})
	assert_eq(CampaignDB.current().id, &"s1_03_shooting")
	_load({"index": 3, "done": _done(1), "attempts": {}, "mascot": ""})
	assert_eq(CampaignDB.current().id, &"s1_03_shooting", "an F9 / --session jump: the index, not the done list")
	_load({"index": 0, "done": [], "attempts": {}, "mascot": ""})
	assert_eq(CampaignDB.current_index(), 0)
	assert_false(CampaignDB.started())


func test_a_save_with_next_reads_the_id() -> void:
	_load({"index": 1, "done": _done(1), "next": "s1_04_level"})
	assert_eq(CampaignDB.current().id, &"s1_04_level", "next wins over the index mirror")
	_load({"index": 9, "done": _done(7) + ["s2_01_tryout"], "next": ""})
	assert_true(CampaignDB.is_done(), "next \"\": after the furthest done")
	_load({"done": _done(2), "next": "s9_gone"})
	assert_eq(CampaignDB.current().id, &"s1_02_enemies", "an unknown id: after the furthest done")
	for bad in [{"next": 3}, {"next": ["s1_00_nothing"]}]:
		DirAccess.make_dir_recursive_absolute(TEST_PATH.get_base_dir())
		var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
		f.store_string(JSON.stringify({"schema": 2, "campaign": bad}))
		f.close()
		SaveGame.go_live(TEST_PATH)
		assert_eq(SaveGame.last_load, SaveGame.CORRUPT, str(bad))
		SaveGame.go_inert()
		_delete_files()


func test_inserting_a_session_moves_no_save() -> void:
	var copy := CampaignDef.new()
	copy.stage_titles = CampaignDB.campaign.stage_titles.duplicate()
	copy.sessions.assign(CampaignDB.campaign.sessions)
	var extra := SessionDef.new()
	extra.id = &"s1_01b_extra"
	extra.title = "Extra"
	copy.sessions.insert(2, extra)
	var real := CampaignDB.campaign
	_load({"index": 3, "done": _done(3), "next": "s1_03_shooting"})
	CampaignDB.campaign = copy
	var by_id := CampaignDB.current().id
	var at := CampaignDB.current_index()
	CampaignDB.campaign = real
	assert_eq(by_id, &"s1_03_shooting")
	assert_eq(at, 4, "the same id, one index later")
	_load({"index": 3, "done": _done(3)})   # an M42.2 file: the frozen order still names s1_03
	CampaignDB.campaign = copy
	by_id = CampaignDB.current().id
	CampaignDB.campaign = real
	assert_eq(by_id, &"s1_03_shooting")


func test_complete_and_jump_write_next() -> void:
	SaveGame.go_live(TEST_PATH, true)
	assert_true(CampaignDB.jump_to(&"s1_05_wrong"))
	assert_eq(SaveGame.campaign().next, "s1_05_wrong")
	assert_eq(SaveGame.campaign().index, 5, "the index mirror")
	CampaignDB.complete(CampaignDB.get_session(&"s1_05_wrong"))
	assert_eq(SaveGame.campaign().next, "s1_06_playground")
	assert_eq(SaveGame.campaign().index, 6)
	var last := CampaignDB.session(CampaignDB.size() - 1)
	CampaignDB.jump_to(last.id)
	CampaignDB.complete(last)
	assert_eq(SaveGame.campaign().next, "")
	assert_eq(SaveGame.campaign().index, CampaignDB.size())
	assert_true(CampaignDB.is_done())
	SaveGame.go_inert()
	SaveGame.go_live(TEST_PATH)
	assert_eq(SaveGame.campaign().next, "", "written and read back")
	assert_true(CampaignDB.is_done())


func test_the_end_of_stage_1_save_continues_at_s7_with_the_card() -> void:
	var before := FileAccess.get_file_as_string(FIXTURE)
	SaveGame.use_snapshot(FIXTURE)
	assert_eq(SaveGame.last_load, SaveGame.LOADED)
	assert_eq(SaveGame.version().label(), "v0.7.0")
	assert_true(CampaignDB.started() and not CampaignDB.is_done(), "Continue is offered")
	var s7 := CampaignDB.current()
	assert_eq(s7.id, &"s2_01_tryout")
	assert_true(CampaignDB.stage_card_due(s7))
	assert_false(CampaignDB.stage_card_due(CampaignDB.get_session(&"s1_06_playground")), "no card for Stage 1")
	SaveGame.count_attempt(s7.id)
	assert_false(CampaignDB.stage_card_due(s7), "Retry does not show it again")
	assert_eq(FileAccess.get_file_as_string(FIXTURE), before, "a snapshot never writes")


# --- The stage card ---------------------------------------------------------------------

func _card() -> StageCard:
	var card := StageCard.new()
	card.setup(2, "The shooter")
	add_child_autofree(card)
	return card


func _key() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_SPACE
	e.pressed = true
	return e


func test_the_stage_card_waits_half_a_second_for_a_key() -> void:
	var card := _card()
	assert_true(card.is_open())
	assert_true(RunState.is_paused_for(&"stage_card"))
	assert_true(get_tree().paused)
	card._input(_key())
	assert_true(card.is_open(), "a key before 0.5 s is ignored")
	card.elapsed = 0.6
	card._input(_key())
	assert_false(card.is_open())
	assert_false(get_tree().paused)


func test_skip_closes_at_any_time_and_the_card_closes_itself_at_3_s() -> void:
	var card := _card()
	card.skip()
	assert_false(card.is_open(), "skip() is never refused (the bot)")
	assert_false(RunState.is_paused_for(&"stage_card"))
	var timed := _card()
	timed._process(1.0)
	timed._process(1.0)
	assert_true(timed.is_open())
	assert_gt(timed._title_label.visible_characters, 0, "the title types")
	timed._process(1.0)
	assert_false(timed.is_open(), "3 s")


func test_closing_the_card_keeps_other_pause_reasons() -> void:
	RunState.set_pause(&"history", true)
	var card := _card()
	card.skip()
	assert_true(get_tree().paused, "Tab's history still pauses")
	RunState.set_pause(&"history", false)
	assert_false(get_tree().paused)


func test_the_card_shows_the_mascot_and_writes_no_telemetry() -> void:
	SaveGame.set_mascot(&"window")
	var log_text := FileAccess.get_file_as_string(Telemetry.log_path) if FileAccess.file_exists(Telemetry.log_path) else ""
	var card := _card()
	assert_not_null(card.mascot)
	assert_true(card.mascot.face)
	assert_eq(card.mascot.body_id, &"window", "the save's body")
	assert_eq(card.mascot.current_text(), StageCard.LINE)
	card.skip()
	var after := FileAccess.get_file_as_string(Telemetry.log_path) if FileAccess.file_exists(Telemetry.log_path) else ""
	assert_eq(after, log_text, "the card is not a session")


func test_every_stage_needs_a_title() -> void:
	assert_eq(CampaignDB.campaign.stage_titles, {1: "The prototype", 2: "The shooter"})
	var copy := CampaignDef.new()
	copy.sessions.assign(CampaignDB.campaign.sessions)
	copy.stage_titles = {1: "The prototype"}
	assert_string_contains(str(CampaignDB.problems(copy)), "stage 2 (s2_01_tryout) has no title")


func test_the_real_boot_opens_the_card_once() -> void:
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(&"s2_01_tryout"))
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	assert_not_null(game.stage_card)
	assert_true(game.stage_card.is_open())
	assert_eq(game.stage_card.title, "The shooter")
	game.stage_card.skip()
	await wait_physics_frames(2)
	assert_false(get_tree().paused)
	game.free()
	var s3 := await _game(&"s1_03_shooting")
	assert_null(s3.stage_card, "no card in Stage 1")


# --- The HP floor ---------------------------------------------------------------------

func _hits_on(floor: int, hits: int) -> Health:
	RunState.reset(0)
	RunState.rules.hp_floor = floor
	var body := Node2D.new()
	body.add_to_group(&"player")
	add_child_autofree(body)
	var h := Health.new()
	h.base_max_hp = 3.0
	h.scales_with_enemy_rule = false
	body.add_child(h)
	for i in hits:
		h.take(DamageInfo.make(1.0, &"contact", &"enemy"))
	return h


func test_the_hp_floor() -> void:
	var none := _hits_on(0, 3)
	assert_true(none.dead, "floor 0: three hits kill")
	var floored := _hits_on(1, 2)
	assert_almost_eq(floored.hp(), 1.0, 0.001)
	var seen := []
	var on_hit := func(_i: DamageInfo) -> void: seen.append(true)
	EventBus.player_hit.connect(on_hit)
	floored.take(DamageInfo.make(1.0, &"contact", &"enemy"))
	floored.take(DamageInfo.make(5.0, &"contact", &"enemy"))
	EventBus.player_hit.disconnect(on_hit)
	assert_almost_eq(floored.hp(), 1.0, 0.001, "hits at the floor leave 1 HP")
	assert_false(floored.dead)
	assert_eq(seen.size(), 2, "the hits still count")
	RunState.reset(0)
	assert_eq(RunState.rules.hp_floor, 0, "no session: no floor")
	assert_eq(WorldRules.new().to_dict().hp_floor, 0)


func test_the_floor_is_live_in_the_real_boot() -> void:
	var s7 := await _game(&"s2_01_tryout")
	assert_eq(RunState.rules.hp_floor, 1, "main.gd recomputes after the session is set")
	s7.free()
	await _game(&"s1_03_shooting")
	assert_eq(RunState.rules.hp_floor, 0)


# --- S7, the stub -----------------------------------------------------------------------

func test_s7_is_a_stub_that_ends_the_campaign_so_far() -> void:
	var s := CampaignDB.get_session(&"s2_01_tryout")
	assert_eq(s.problems(), [] as Array[String])
	assert_eq([s.stage, s.goal, s.goal_value, s.hp_floor, s.tryout, s.face, s.bump, s.fork],
			[2, SessionDef.SURVIVE, 60.0, 1, true, true, &"minor", &""])
	assert_eq(s.basics, CampaignDB.get_session(&"s1_06_playground").basics, "Stage 1's build")
	assert_eq(CampaignDB.index_of(s.id), CampaignDB.size() - 1, "the last session")
	for pair: Array in [[&"s2_01_tryout", DebriefScreen.LAST], [&"s1_06_playground", DebriefScreen.NEXT]]:
		var d := DebriefScreen.new()
		add_child_autofree(d)
		d.input_delay = 0.0
		d.open(CampaignDB.get_session(pair[0]), &"won", 0)
		d.finish_lines()
		assert_eq(d.choices(), [pair[1]], String(pair[0]))
		d.close()
	var game := await _game(&"s2_01_tryout")
	assert_eq(game.run_loop.goal, SessionDef.SURVIVE)
	assert_eq(game.run_loop.goal_value, 60.0)


# --- Reactions by session id ---------------------------------------------------------------

func test_after_and_until_fit_the_old_sessions() -> void:
	assert_eq(CampaignDB.reactions.size(), OLD_SESSIONS.size())
	for d in CampaignDB.reactions:
		assert_true(OLD_SESSIONS.has(d.id), String(d.id))
		var old: Array = OLD_SESSIONS[d.id]
		for i in STAGE1.size():
			var was: bool = int(old[0]) <= i and (int(old[1]) < 0 or i <= int(old[1]))
			assert_eq(d.fits(STAGE1[i]), was, "%s in %s" % [d.id, STAGE1[i]])
		assert_eq(d.when != "", d.id in AUTO_GATED, "%s: the audit's gates only" % d.id)


func test_the_stage_2_reaction_lists_match_their_fixture() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REACTIONS_FIXTURE))
	assert_eq(fixture.size(), 4, "s2_01_tryout x (none, 3 paths)")
	for key: String in fixture:
		var session := CampaignDB.get_session(StringName(key.get_slice("|", 0)))
		assert_not_null(session, key)
		SaveGame.go_inert()
		var path := key.get_slice("|", 1)
		if path != "-":
			SaveGame.ship(StringName(path), GameVersion.PATCH)   # any id ships in memory
		var ctx := CampaignDB.line_context(session)
		var ids: Array = []
		for d in CampaignDB.reactions:
			if d.fits(session.id) and Line.condition_holds(d.when, ctx):
				ids.append(String(d.id))
		ids.sort()
		assert_eq(ids, fixture[key], key)


func test_a_gated_reaction_is_not_loaded() -> void:
	var plain := await _game(&"s2_01_tryout")
	assert_true(&"not_shooting" in plain.reactions.active_ids())
	assert_true(&"camping" in plain.reactions.active_ids())
	plain.free()
	SaveGame.ship(&"path_auto", GameVersion.PATCH)
	var auto := await _game(&"s2_01_tryout")
	for id in AUTO_GATED:
		assert_false(id in auto.reactions.active_ids(), "%s never on Auto" % id)
	assert_true(&"camping" in auto.reactions.active_ids(), "camping stays (D8)")
