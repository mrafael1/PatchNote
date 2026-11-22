extends GutTest
## M27: the save, the game's version and what it unlocks (PLAN v5 1.5, 1.6).
## Every test that makes the save live points it at TEST_PATH; after_each puts the
## save back to inert and deletes the scratch files.

const Fx := preload("res://tests/gut/fixtures.gd")
const TEST_PATH := "user://save_test/save.json"

var _changes: Array[Change] = []
var _starters := {}   ## mutation -> starter flag to put back, even if a test fails


func before_each() -> void:
	_delete_files()


func after_each() -> void:
	assert_ne(SaveGame.save_path if SaveGame.persist else "", SaveGame.DEFAULT_PATH,
			"no test may leave the real save live")
	SaveGame.go_inert()
	_delete_files()
	for c in _changes:
		ChangeDB.unregister(c)
	_changes.clear()
	for m: Mutation in _starters:
		m.starter = _starters[m]
	_starters.clear()
	StartScreen.save_live = true
	Taste.clear_session()
	RunState.reset(0)
	RunState.world = null


func _delete_files() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", "user://save_test/save.bad.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _write(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_PATH.get_base_dir())
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read() -> String:
	return FileAccess.get_file_as_string(TEST_PATH)


func _change(id: StringName, unlocks: Array = [], requires: Array = [], kind := &"patch") -> Change:
	var c := Change.new()
	c.id = id
	c.title = String(id)
	c.kind = kind
	c.unlocks.assign(unlocks)
	c.requires.assign(requires)
	ChangeDB.register(c)
	_changes.append(c)
	return c


# --- Inert by default ------------------------------------------------------------

func test_the_save_is_inert_by_default() -> void:
	assert_false(SaveGame.persist)
	assert_true(SaveGame.unlock_all)
	assert_eq(SaveGame.save_path, SaveGame.DEFAULT_PATH)
	assert_ne(TEST_PATH, SaveGame.DEFAULT_PATH, "tests never use the real save")
	assert_eq(SaveGame.write(), ERR_UNAVAILABLE, "an inert save never writes")
	assert_false(SaveGame.record_run(&"topdown", &"win", 10.0, {}))
	assert_eq(int(SaveGame.state().runs), 0)


func test_a_new_save_is_v0_0_0_with_nothing_shipped() -> void:
	var s := SaveGame.new_state()
	assert_eq(s.schema, SaveGame.SCHEMA)
	assert_eq(s.version, [0, 0, 0])
	assert_eq(s.runs, 0)
	assert_eq(s.wins, 0)
	assert_eq(s.shipped, [])
	assert_eq(s.look, {"tier": 0, "take": ""})
	assert_eq(s.taste, {"by_id": {}, "by_tag": {}})
	assert_eq(s.sessions, [])
	assert_false(s.pending_session)
	assert_eq(s.genres, {"topdown": {"step": "playable", "runs": 0, "play_time": 0.0}})


# --- Round trip and writes -----------------------------------------------------------

func test_a_live_save_round_trips() -> void:
	SaveGame.go_live(TEST_PATH, true)
	assert_false(FileAccess.file_exists(TEST_PATH), "nothing is written until a run ends")
	var taste := {"by_id": {"auto_attack": 1.25, "look:punchy": 0.5}, "by_tag": {"weapon": 0.5}}
	assert_true(SaveGame.record_run(&"topdown", &"win", 12.5, taste))
	assert_true(SaveGame.record_run(&"topdown", &"lose", 30.25, taste))
	assert_true(FileAccess.file_exists(TEST_PATH))
	assert_false(FileAccess.file_exists(TEST_PATH + ".tmp"), "the write is atomic: no .tmp left")
	var written := SaveGame.state().duplicate(true)
	assert_eq(written.runs, 2)
	assert_eq(written.wins, 1)
	assert_eq(written.genres.topdown.runs, 2)
	assert_almost_eq(float(written.genres.topdown.play_time), 42.75, 0.0001)
	assert_true(written.pending_session)
	assert_eq(written.taste, taste)

	SaveGame.go_inert()
	SaveGame.go_live(TEST_PATH)
	assert_eq(SaveGame.last_load, SaveGame.LOADED)
	assert_eq(SaveGame.state(), written)


func test_the_same_steps_write_the_same_file() -> void:
	var texts: Array[String] = []
	for i in 2:
		_delete_files()
		SaveGame.go_live(TEST_PATH, true)
		SaveGame.record_run(&"topdown", &"win", 101.5, {"by_id": {"auto_attack": 1.0}, "by_tag": {}})
		SaveGame.ship(&"fx_unknown_is_fine_in_memory", GameVersion.PATCH)
		SaveGame.finish_session({"after_run": 1, "pick": "x"})
		texts.append(_read())
		SaveGame.go_inert()
	assert_eq(texts[0], texts[1])
	assert_string_contains(texts[0], "\"schema\": 1")


func test_a_missing_file_is_a_new_save_and_writes_nothing() -> void:
	SaveGame.go_live(TEST_PATH)
	assert_eq(SaveGame.last_load, SaveGame.NEW)
	assert_eq(SaveGame.version().label(), "v0.0.0")
	assert_false(FileAccess.file_exists(TEST_PATH))


func test_a_missing_key_takes_its_default() -> void:
	_write("{\"schema\": 1, \"runs\": 3, \"version\": [0, 1, 2]}")
	SaveGame.go_live(TEST_PATH)
	assert_eq(SaveGame.last_load, SaveGame.LOADED)
	assert_eq(SaveGame.state().runs, 3)
	assert_eq(SaveGame.state().wins, 0)
	assert_eq(SaveGame.version().label(), "v0.1.2")
	assert_eq(SaveGame.state().look, {"tier": 0, "take": ""})
	assert_true(SaveGame.state().genres.has("topdown"))


func test_a_corrupt_file_is_moved_aside_and_play_starts_from_a_new_save() -> void:
	for text in ["{not json", "[1, 2]", "{\"runs\": \"three\"}", "{\"version\": [0, -1, 2]}",
			"{\"genres\": {\"topdown\": 5}}", "{\"shipped\": [3]}", "{\"look\": {\"tier\": \"x\"}}",
			"{\"genres\": {\"topdown\": {\"runs\": \"x\"}}}", "{\"genres\": {\"topdown\": {\"step\": \"huge\"}}}",
			"{\"genres\": {\"topdown\": {\"play_time\": -4}}}", "{\"taste\": {\"by_id\": {\"auto_attack\": \"high\"}}}",
			"{\"taste\": {\"by_tag\": []}}"]:
		_delete_files()
		_write(text)
		SaveGame.go_live(TEST_PATH)
		assert_eq(SaveGame.last_load, SaveGame.CORRUPT, text)
		assert_false(FileAccess.file_exists(TEST_PATH), "%s: moved aside" % text)
		assert_eq(FileAccess.get_file_as_string("user://save_test/save.bad.json"), text)
		assert_eq(SaveGame.state().runs, 0)
		assert_false(SaveGame.read_only)
		SaveGame.go_inert()


func test_a_snapshot_read_never_moves_a_corrupt_file() -> void:
	_write("{not json")
	SaveGame.use_snapshot(TEST_PATH)
	assert_eq(SaveGame.last_load, SaveGame.CORRUPT)
	assert_true(FileAccess.file_exists(TEST_PATH))
	assert_false(FileAccess.file_exists("user://save_test/save.bad.json"))


func test_a_newer_file_is_read_only_and_never_overwritten() -> void:
	var text := "{\"schema\": 99, \"runs\": 5}"
	_write(text)
	SaveGame.go_live(TEST_PATH)
	assert_eq(SaveGame.last_load, SaveGame.NEWER)
	assert_true(SaveGame.read_only)
	assert_false(SaveGame.can_reset())
	assert_eq(SaveGame.state().runs, 0, "used as a new save in memory")
	assert_false(SaveGame.record_run(&"topdown", &"win", 5.0, {}))
	assert_false(SaveGame.reset())
	assert_eq(SaveGame.write(), ERR_UNAVAILABLE)
	assert_eq(_read(), text, "never overwritten")
	assert_eq(StartScreen.save_line(), "Save from a newer build (read-only)")


## A newer build's file is read-only: taste falls back to the session carry, so the
## report's ratings still reach the next run of the session.
func test_a_read_only_save_keeps_the_session_carry() -> void:
	_write("{\"schema\": 99}")
	SaveGame.go_live(TEST_PATH)
	assert_false(SaveGame.is_live())
	Taste.carried = {&"horde_mode": 1}
	assert_gt(Taste.from_session().score(MutationDB.get_mutation(&"horde_mode")), 0.0)


func test_unknown_ids_are_dropped_on_load() -> void:
	_change(&"fx_ch_a")
	_write(JSON.stringify({"schema": 1,
		"genres": {"topdown": {"step": "playable", "runs": 2, "play_time": 9.5}, "gone_genre": {"runs": 1}},
		"shipped": ["fx_ch_a", "gone_change", "fx_ch_a"],
		"taste": {"by_id": {"auto_attack": 1.0, "gone_patch": 2.0, "look:clean": 0.5}, "by_tag": {"weapon": 1.0}}}))
	SaveGame.go_live(TEST_PATH)
	assert_eq(SaveGame.last_load, SaveGame.LOADED)
	assert_eq(SaveGame.state().genres.keys(), ["topdown"])
	assert_eq(SaveGame.state().genres.topdown.runs, 2)
	assert_eq(SaveGame.shipped(), [&"fx_ch_a"] as Array[StringName])
	assert_eq(SaveGame.state().taste.by_id, {"auto_attack": 1.0, "look:clean": 0.5})


func test_reset_writes_a_new_save() -> void:
	SaveGame.go_live(TEST_PATH, true)
	SaveGame.record_run(&"topdown", &"win", 5.0, {})
	assert_true(SaveGame.reset())
	assert_eq(SaveGame.state().runs, 0)
	SaveGame.go_inert()
	SaveGame.go_live(TEST_PATH)
	assert_eq(SaveGame.last_load, SaveGame.LOADED)
	assert_eq(SaveGame.state().runs, 0)


func test_shipping_bumps_the_version_once() -> void:
	SaveGame.go_live(TEST_PATH, true)
	assert_true(SaveGame.ship(&"look_x", GameVersion.MINOR))
	assert_true(SaveGame.ship(&"patch_x", GameVersion.PATCH))
	assert_true(SaveGame.ship(&"patch_y", GameVersion.PATCH))
	assert_eq(SaveGame.version().label(), "v0.1.2")
	assert_false(SaveGame.ship(&"patch_x", GameVersion.PATCH), "already shipped")
	assert_false(SaveGame.ship(&"patch_z", &"huge"), "unknown bump")
	assert_eq(SaveGame.version().label(), "v0.1.2")
	assert_true(SaveGame.has_shipped(&"look_x"))
	SaveGame.finish_session({"after_run": 1})
	assert_false(SaveGame.state().pending_session)
	assert_eq(SaveGame.state().sessions.size(), 1)


## A scene that is not the running game (every test-instanced Main) never writes the
## save, even when it is live.
func test_a_game_that_is_not_live_writes_no_save() -> void:
	SaveGame.go_live(TEST_PATH, true)
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.run_loop.end(&"win")
	await wait_physics_frames(2)
	assert_false(FileAccess.file_exists(TEST_PATH))
	assert_eq(int(SaveGame.state().runs), 0)


# --- Taste ---------------------------------------------------------------------------

func test_taste_round_trips_through_the_save_form() -> void:
	var t := Taste.new()
	t.on_offer([MutationDB.get_mutation(&"auto_attack"), MutationDB.get_mutation(&"horde_mode")],
			MutationDB.get_mutation(&"auto_attack"))
	var back := Taste.from_save(t.to_save())
	assert_eq(back.to_save(), t.to_save())
	assert_almost_eq(back.score(MutationDB.get_mutation(&"auto_attack")),
			t.score(MutationDB.get_mutation(&"auto_attack")), 0.001)


func test_a_live_save_replaces_the_session_carry() -> void:
	Taste.carried = {&"horde_mode": 1}
	var inert := Taste.from_session()
	assert_gt(inert.score(MutationDB.get_mutation(&"horde_mode")), 0.0, "inert: the session carry")
	SaveGame.go_live(TEST_PATH, true)
	SaveGame.record_run(&"topdown", &"lose", 1.0, {"by_id": {"auto_attack": 2.0}, "by_tag": {}})
	var live := Taste.from_session()
	assert_eq(live.score(MutationDB.get_mutation(&"horde_mode")), 0.0, "live: the carry is not used")
	assert_gt(live.score(MutationDB.get_mutation(&"auto_attack")), 0.0, "live: the save's taste")


# --- Version ---------------------------------------------------------------------------

func test_version_bumps_and_labels() -> void:
	var v := GameVersion.new()
	assert_eq(v.label(), "v0.0.0")
	assert_true(v.bump(GameVersion.PATCH))
	assert_true(v.bump(GameVersion.PATCH))
	assert_eq(v.label(), "v0.0.2")
	assert_true(v.bump(GameVersion.MINOR))
	assert_eq(v.label(), "v0.1.0", "a minor step resets the patch number")
	assert_false(v.bump(&"major"))
	assert_eq(v.short(), "0.1.0")
	assert_eq(v.to_array(), [0, 1, 0])
	assert_true(GameVersion.from_array([1, 2, 3]).equals(GameVersion.make(1, 2, 3)))
	for bad: Variant in [null, [], [0, 1], ["a", 0, 0], [0, -1, 0], {"a": 1}]:
		assert_eq(GameVersion.from_array(bad).label(), "v0.0.0", str(bad))


func test_the_hud_and_the_report_name_the_game_version() -> void:
	RunState.reset(3)
	assert_eq(Hud.version_text(), "v0.0.0 · build 1")
	SaveGame.go_live(TEST_PATH, true)
	SaveGame.ship(&"look_x", GameVersion.MINOR)
	assert_eq(Hud.version_text(), "v0.1.0 · build 1")
	var win := ReportScreen.report_text(&"win", {"game_version": "v0.1.0", "build_number": 4})
	assert_true(win.begins_with("PLAYTEST OF v0.1.0  -  BUILD SURVIVED"), win.get_slice("\n", 0))
	assert_string_contains(win, "Version     v0.1.0 · build 4")
	var lose := ReportScreen.report_text(&"lose", {"game_version": "v0.1.0", "build_number": 3})
	assert_true(lose.begins_with("PLAYTEST OF v0.1.0  -  CRASHED AT BUILD 3"), lose.get_slice("\n", 0))


func test_the_run_record_names_the_game_version_and_genre() -> void:
	RunState.reset(3)
	var rec := Telemetry.build_record(&"win")
	assert_eq(rec.game_version, "v0.0.0")
	assert_eq(rec.genre, "topdown")
	assert_eq(rec.build_number, 1)


# --- Unlocks --------------------------------------------------------------------------

func test_inert_unlocks_everything() -> void:
	assert_eq(Unlocks.pool(), MutationDB.offerable())
	assert_eq(Unlocks.enemies(), Unlocks.ARCHETYPES)
	assert_eq(Unlocks.look(), {"tier": 1, "take": "punchy"})


func test_the_archetypes_are_the_spawners() -> void:
	var keys: Array[StringName] = []
	keys.assign(Spawner.SCENES.keys())
	keys.sort()
	var archetypes := Unlocks.ARCHETYPES.duplicate()
	archetypes.sort()
	assert_eq(archetypes, keys)
	for a in Tuning.starter_enemies:
		assert_has(Unlocks.ARCHETYPES, a)


func test_a_new_save_unlocks_the_starters_and_shipped_changes_add_to_them() -> void:
	_change(&"fx_ch_patch", [&"auto_attack"])
	_change(&"fx_ch_enemy", [&"tank"], [], &"enemy")
	SaveGame.go_live(TEST_PATH, true)
	var auto_attack := MutationDB.get_mutation(&"auto_attack")
	assert_eq(Unlocks.pool().map(func(m: Mutation) -> String: return String(m.id)),
			["bouncing_projectiles", "enemies_split", "explode_on_hit", "jump_button"], "PLAN v5 2.3")
	assert_does_not_have(Unlocks.pool(), auto_attack, "not a starter, not shipped")
	assert_eq(Unlocks.enemies(), Tuning.starter_enemies)
	assert_eq(Unlocks.look(), {"tier": 0, "take": ""})
	SaveGame.ship(&"fx_ch_patch", GameVersion.PATCH)
	SaveGame.ship(&"fx_ch_enemy", GameVersion.PATCH)
	assert_has(Unlocks.pool(), MutationDB.get_mutation(&"auto_attack"))
	assert_has(Unlocks.enemies(), &"tank")
	assert_eq(Unlocks.shipped_unlocks(), [&"auto_attack", &"tank"] as Array[StringName])
	for m in Unlocks.pool():
		assert_false(m.parked)


# --- ChangeDB ------------------------------------------------------------------------

func test_change_problems() -> void:
	for c in ChangeDB.all:
		assert_eq(ChangeDB.problems(c), [] as Array[String], String(c.id))
	var good := _change(&"fx_ch_good", [&"auto_attack", &"tank"])
	assert_eq(ChangeDB.problems(good), [] as Array[String])
	var bad := _change(&"fx_ch_bad", [&"turn_mode", &"no_such_thing"], [&"no_such_change"])
	bad.kind = &"weird"
	bad.bump = &"huge"
	bad.genre = &"no_genre"
	var p := ChangeDB.problems(bad)
	assert_has(p, "Change 'fx_ch_bad' unlocks the parked patch 'turn_mode'")
	assert_has(p, "Change 'fx_ch_bad' unlocks 'no_such_thing', which is neither a patch nor an enemy")
	assert_has(p, "Change 'fx_ch_bad' requires unknown change 'no_such_change'")
	assert_has(p, "Change 'fx_ch_bad' has an unknown kind 'weird'")
	assert_has(p, "Change 'fx_ch_bad' has an unknown bump 'huge'")
	assert_has(p, "Change 'fx_ch_bad' names an unknown genre 'no_genre'")
	var loop_a := _change(&"fx_ch_loop_a", [], [&"fx_ch_loop_b"])
	_change(&"fx_ch_loop_b", [], [&"fx_ch_loop_a"])
	assert_has(ChangeDB.problems(loop_a), "Change 'fx_ch_loop_a' is in a requires cycle")
	var look := _change(&"fx_ch_look", [], [], &"look")
	assert_has(ChangeDB.problems(look), "Look change 'fx_ch_look' has no take with a preset")
	look.take = MockupTake.new()
	assert_has(ChangeDB.problems(look), "Look change 'fx_ch_look' has no take with a preset")


# --- Start screen --------------------------------------------------------------------

func test_the_start_screen_shows_the_save_and_resets_it_in_two_clicks() -> void:
	assert_eq(StartScreen.save_line(), "v0.0.0 · 0 runs")
	SaveGame.go_live(TEST_PATH, true)
	SaveGame.record_run(&"topdown", &"win", 5.0, {})
	# A run ended and its dev session never happened: the screen says so (PLAN v5 1.5).
	var pending := "v0.0.0 · 1 run" + char(10) + DevSession.PENDING_LINE
	assert_eq(StartScreen.save_line(), pending)
	StartScreen.save_live = false   # the real save must not go live in a test
	var screen: StartScreen = load("res://ui/start_screen.tscn").instantiate()
	add_child_autofree(screen)   # save_live stays false: after_each puts it back
	assert_true(SaveGame.persist, "the screen kept the test's save")
	assert_eq(SaveGame.save_path, TEST_PATH)
	assert_eq(screen.save_label.text, pending)
	assert_eq(screen.start_button.text, StartScreen.START_PENDING)
	assert_false(screen.reset_button.disabled)
	screen.press_reset()
	assert_eq(int(SaveGame.state().runs), 1, "the first click only arms")
	assert_eq(screen.reset_button.text, StartScreen.RESET_ARMED)
	screen.press_reset()
	assert_eq(int(SaveGame.state().runs), 0)
	assert_eq(screen.save_label.text, "v0.0.0 · 0 runs")
	assert_eq(screen.reset_button.text, StartScreen.RESET_LABEL)


func test_tools_and_smoke_boots_leave_the_real_save_alone() -> void:
	StartScreen.save_live = false
	assert_false(StartScreen.uses_real_save())
	StartScreen.save_live = true
	assert_eq(StartScreen.uses_real_save(), not ("--autostart" in OS.get_cmdline_user_args()
			or "--inert-save" in OS.get_cmdline_user_args()))


func test_an_inert_start_screen_cannot_reset() -> void:
	StartScreen.save_live = false
	var screen: StartScreen = load("res://ui/start_screen.tscn").instantiate()
	add_child_autofree(screen)   # save_live stays false: after_each puts it back
	assert_false(SaveGame.persist)
	assert_true(screen.reset_button.disabled)
	screen.press_reset()
	screen.press_reset()
	assert_eq(screen.reset_button.text, StartScreen.RESET_LABEL)
