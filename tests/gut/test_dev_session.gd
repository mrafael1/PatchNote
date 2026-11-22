extends GutTest
## M29: the dev session (PLAN v5 4). Every test that makes the save live points it at
## TEST_PATH; after_each puts the save back to inert and deletes the scratch files.

const TEST_PATH := "user://save_session_test/save.json"
const ALL_SIX: Array[String] = ["enemy_bomber", "enemy_tank", "look_1", "patch_auto_attack",
		"patch_horde_mode", "patch_motion_time"]

var _changes: Array[Change] = []
var _every := 0


func before_each() -> void:
	_delete_files()
	_every = Tuning.ai_own_ship_every


func after_each() -> void:
	assert_ne(SaveGame.save_path if SaveGame.persist else "", SaveGame.DEFAULT_PATH,
			"no test may leave the real save live")
	Tuning.ai_own_ship_every = _every
	SaveGame.go_inert()
	_delete_files()
	for c in _changes:
		ChangeDB.unregister(c)
	_changes.clear()
	StartScreen.save_live = true
	Main.next_seed = -1
	Taste.clear_session()
	Look.use(Unlocks.FULL_LOOK)
	RunState.reset(0)
	RunState.world = null


func _delete_files() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", "user://save_session_test/save.bad.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## A fresh live save that has played `runs` runs (each one a pending session).
func _live(runs := 1) -> void:
	SaveGame.go_live(TEST_PATH, true)
	for i in runs:
		SaveGame.record_run(&"topdown", &"lose", 60.0, SaveGame.state().taste)


func _ship_all_but(left: Array) -> void:
	for c in ChangeDB.all:
		if not String(c.id) in left:
			SaveGame.ship(c.id, c.bump)


func _ids(session: DevSession) -> Array:
	return session.cards.map(func(c: Dictionary) -> String: return c.id)


# --- The content -------------------------------------------------------------------

func test_the_six_changes_are_valid() -> void:
	var ids: Array[String] = []
	for c in ChangeDB.all:
		ids.append(String(c.id))
		assert_eq(ChangeDB.problems(c), [] as Array[String], String(c.id))
		assert_ne(c.title, "", String(c.id))
		assert_ne(c.pitch, "", String(c.id))
	assert_eq(ids, ALL_SIX)
	var look := ChangeDB.get_change(&"look_1")
	assert_true(look.is_mockup())
	assert_eq(look.bump, GameVersion.MINOR)
	assert_eq(look.due_after_run, 1)
	assert_eq(look.takes.map(func(t: MockupTake) -> String: return String(t.id)), ["punchy", "clean", "arcade"])
	for t in look.takes:
		var preset := t.preset as LookPreset
		assert_not_null(preset, String(t.id))
		assert_eq(preset.tier, 1)
		assert_eq(preset.take, t.id)
		assert_eq(Look.path_for(1, String(t.id)), preset.resource_path, "Look finds the take's preset")
	assert_eq(ChangeDB.get_change(&"patch_horde_mode").requires, [&"enemy_tank"] as Array[StringName])
	assert_eq(ChangeDB.get_change(&"enemy_bomber").requires, [&"enemy_tank"] as Array[StringName])
	# Every patch that is not a starter, and every enemy that is not, has a change.
	var unlocked := []
	for c in ChangeDB.all:
		unlocked.append_array(c.unlocks)
	for m in MutationDB.offerable():
		assert_true(m.starter or unlocked.has(m.id), "%s ships through a change" % m.id)
	for a in Unlocks.ARCHETYPES:
		assert_true(a in Tuning.starter_enemies or unlocked.has(a), "%s ships through a change" % a)


# --- Which cards -------------------------------------------------------------------

func test_the_first_session_is_the_look_mockup() -> void:
	_live(1)
	var s := DevSession.plan(5)
	assert_eq(s.shape, DevSession.MOCKUP)
	assert_eq(s.mockup.id, &"look_1")
	assert_eq(_ids(s), ["look_1:punchy", "look_1:clean", "look_1:arcade"])
	assert_true(s.agenda_card().is_empty(), "takes have no agenda card")
	assert_eq(s.number, 1)
	assert_eq(s.after_run, 1)
	assert_string_contains(s.opening, DevSession.MOCKUP_LINE)


func test_a_mockup_waits_until_it_is_due() -> void:
	_live(0)   # F9 before any run: look_1 is due after run 1
	var s := DevSession.plan(5)
	assert_eq(s.shape, DevSession.CHANGES)
	assert_false(_ids(s).has("look_1"), "a mockup is never a plain card")


func test_requires_are_respected() -> void:
	_live(1)
	SaveGame.ship(&"look_1", GameVersion.MINOR)
	var avail := DevSession.available().map(func(c: Change) -> String: return String(c.id))
	assert_eq(avail, ["enemy_tank", "patch_auto_attack", "patch_motion_time"])
	SaveGame.ship(&"enemy_tank", GameVersion.PATCH)
	avail = DevSession.available().map(func(c: Change) -> String: return String(c.id))
	assert_eq(avail, ["enemy_bomber", "patch_auto_attack", "patch_horde_mode", "patch_motion_time"])
	for run_seed in 20:
		var s := DevSession.plan(run_seed)
		for id: String in _ids(s):
			assert_true(id in avail, "seed %d offered %s" % [run_seed, id])


func test_a_session_showing_two_or_more_cards_has_exactly_one_agenda_card() -> void:
	for left: Array in [["enemy_tank", "patch_auto_attack", "patch_motion_time"],
			["patch_auto_attack", "patch_motion_time"],
			["enemy_bomber", "patch_auto_attack", "patch_horde_mode", "patch_motion_time"]]:
		_live(2)   # a fresh save each time
		_ship_all_but(left)
		for run_seed in 12:
			var s := DevSession.plan(run_seed)
			assert_eq(s.shape, DevSession.CHANGES)
			assert_eq(s.cards.size(), mini(Tuning.session_cards, left.size()))
			assert_eq(s.cards.filter(func(c: Dictionary) -> bool: return c.agenda).size(), 1,
					"seed %d, %d left" % [run_seed, left.size()])
			var ids := _ids(s)
			ids.sort()
			for i in range(1, ids.size()):
				assert_ne(ids[i], ids[i - 1], "no card twice")


func test_the_agenda_card_is_the_least_liked_by_tag() -> void:
	_live(2)
	_ship_all_but(["patch_auto_attack", "patch_motion_time"])
	var taste := Taste.new()
	taste.by_tag[&"time"] = -3.0
	taste.by_tag[&"weapon"] = 2.0
	SaveGame.state().taste = taste.to_save()
	for run_seed in 8:
		var s := DevSession.plan(run_seed)
		assert_eq(s.agenda_card().id, "patch_motion_time", "the AI's wish is what the player likes least")
		assert_eq(DevSession.card_line(s.agenda_card()), DevSession.AGENDA_LINE)


func test_same_seed_and_same_save_give_the_same_cards() -> void:
	_live(2)
	SaveGame.ship(&"look_1", GameVersion.MINOR)
	SaveGame.ship(&"enemy_tank", GameVersion.PATCH)   # 4 available, 3 shown: one is left out
	var first := _ids(DevSession.plan(42))
	var sets := {}
	for run_seed in 30:
		var sorted := _ids(DevSession.plan(run_seed))
		sorted.sort()
		sets[str(sorted)] = true
	assert_gt(sets.size(), 1, "seeds choose which cards, not only their order")
	var seen := {}
	for i in 5:
		assert_eq(_ids(DevSession.plan(42)), first)
	for run_seed in 30:
		seen[str(_ids(DevSession.plan(run_seed)))] = true
	assert_gt(seen.size(), 1, "other seeds deal other hands")


func test_with_one_change_left_the_ai_ships_it_and_no_card_is_shown() -> void:
	_live(6)
	_ship_all_but(["patch_motion_time"])
	var before := SaveGame.version()
	var s := DevSession.plan(3)
	assert_eq(s.shape, DevSession.AI_LAST)
	assert_true(s.cards.is_empty())
	assert_false(s.can_pick())
	assert_false(s.pick(0), "no card to pick")
	assert_true(s.finish())
	assert_true(SaveGame.has_shipped(&"patch_motion_time"))
	before.bump(GameVersion.PATCH)
	assert_true(SaveGame.version().equals(before), "the AI's ship bumps")
	assert_eq(s.ai_ship_id(), "patch_motion_time")
	assert_has(s.notes_lines(), DevSession.AI_LAST_LINE)
	var entry: Dictionary = SaveGame.state().sessions[-1]
	assert_eq(entry.shape, "ai_last")
	assert_eq(entry.cards, [])
	assert_eq(entry.pick, "")
	assert_eq(entry.ai_ship, "patch_motion_time")


func test_nothing_available_means_no_bump_and_straight_to_the_next_run() -> void:
	_live(7)
	_ship_all_but([])
	var before := SaveGame.version()
	var s := DevSession.plan(3)
	assert_eq(s.shape, DevSession.NONE)
	assert_true(s.cards.is_empty())
	assert_string_contains(s.opening, DevSession.NONE_LINE)
	assert_true(s.finish())
	assert_true(SaveGame.version().equals(before))
	assert_true(s.notes_lines().is_empty())
	assert_false(SaveGame.state().pending_session)
	assert_eq(SaveGame.state().sessions[-1].shape, "none")


# --- Shipping ----------------------------------------------------------------------

func test_picking_a_take_ships_the_look_bumps_minor_logs_and_writes_taste() -> void:
	_live(1)
	assert_true(SaveGame.state().pending_session)
	var s := DevSession.plan(9)
	assert_true(s.pick(1))   # clean
	assert_true(SaveGame.has_shipped(&"look_1"))
	assert_eq(SaveGame.version().label(), "v0.1.0")
	assert_eq(Unlocks.look(), {"tier": 1, "take": "clean"})
	assert_eq(Look.use(Unlocks.look()).take, &"clean")
	var written: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
	assert_false(written.pending_session)
	assert_eq(int(written.look.tier), 1)
	assert_eq(written.look.take, "clean")
	assert_eq((written.sessions as Array).size(), 1)
	var entry: Dictionary = written.sessions[0]
	assert_eq(int(entry.after_run), 1)
	entry.erase("after_run")
	assert_eq(entry, {"version": "0.1.0", "shape": "mockup",
			"cards": ["look_1:punchy", "look_1:clean", "look_1:arcade"], "pick": "look_1:clean",
			"agenda": "", "ai_ship": ""}, "unpicked takes stay in the log")
	assert_gt(float(written.taste.by_id["look:clean"]), 0.0)
	assert_lt(float(written.taste.by_id["look:punchy"]), 0.0)
	assert_false(s.pick(0), "a session ships once")
	assert_eq(s.notes_lines()[0], "Version 0.1.0")
	assert_has(s.notes_lines(), "    New look: Clean")


func test_picking_a_change_ships_it_bumps_patch_and_feeds_its_tags() -> void:
	_live(2)
	_ship_all_but(["enemy_tank", "patch_auto_attack", "patch_motion_time"])
	var s := DevSession.plan(4)
	var index := _ids(s).find("patch_auto_attack")
	if index < 0:
		index = 0
	var picked: Change = s.cards[index].change
	var tags_before: Dictionary = SaveGame.state().taste.by_tag.duplicate()
	assert_true(s.pick(index))
	assert_true(SaveGame.has_shipped(picked.id))
	# The test shipped enemy_bomber (v0.0.1), look_1 (v0.1.0) and horde (v0.1.1).
	assert_eq(SaveGame.version().label(), "v0.1.2", "a pick is a patch step")
	var tag := String(picked.tags[0])
	assert_gt(float(SaveGame.state().taste.by_tag.get(tag, 0.0)), float(tags_before.get(tag, 0.0)))
	var lines := s.notes_lines()
	assert_eq(lines[0], "Version 0.1.2")
	assert_eq(lines[1], "• %s: %s" % [picked.title, picked.pitch])
	for line in DevSession.unlock_lines(picked):
		assert_has(lines, "    " + line)
	if picked.id == &"patch_auto_attack":
		assert_has(lines, "    New patch in the pool: Automate attacking")
		assert_has(Unlocks.pool(), MutationDB.get_mutation(&"auto_attack"))


func test_the_ai_ships_its_own_change_every_fourth_session() -> void:
	Tuning.ai_own_ship_every = 4
	_live(4)
	SaveGame.ship(&"look_1", GameVersion.MINOR)
	for i in 3:
		SaveGame.finish_session({"after_run": i + 1})
	var s := DevSession.plan(11)
	assert_eq(s.number, 4)
	assert_eq(s.shape, DevSession.CHANGES)
	assert_true(s.pick(0))
	assert_eq(s.shipped.size(), 2, "the pick and the AI's own")
	assert_eq(s.shipped[1].by, DevSession.AI)
	assert_eq(SaveGame.version().label(), "v0.1.2", "one bump each")
	assert_ne(s.ai_ship_id(), "")
	assert_ne(s.ai_ship_id(), s.pick_id)
	assert_has(s.notes_lines(), DevSession.AI_OWN_LINE % (s.shipped[1].change as Change).short_name())
	# The AI ships what the player likes least (the agenda rule).
	_live(4)
	SaveGame.ship(&"look_1", GameVersion.MINOR)
	for i in 3:
		SaveGame.finish_session({"after_run": i + 1})
	var taste := Taste.new()
	taste.by_tag[&"time"] = -5.0
	SaveGame.state().taste = taste.to_save()
	var liked := DevSession.plan(11)
	assert_true(liked.pick(maxi(0, _ids(liked).find("patch_auto_attack"))))
	assert_eq(liked.ai_ship_id(), "patch_motion_time")
	# 0 turns it off: the same fourth session, from the same save, ships only the pick.
	Tuning.ai_own_ship_every = 0
	_live(4)
	SaveGame.ship(&"look_1", GameVersion.MINOR)
	for i in 3:
		SaveGame.finish_session({"after_run": i + 1})
	var off := DevSession.plan(11)
	assert_true(off.pick(0))
	assert_eq(off.ai_ship_id(), "")
	assert_eq(off.shipped.size(), 1)


func test_the_opening_line_reads_the_run() -> void:
	_live(1)
	var record := {"outcome": "lose", "prompts": [{"pick": "explode_on_hit"}, {"pick": ""}],
			"genre_hits_by_kind": {"base": {"contact_blocked": 3, "projectile": 1}}}
	var context := DevSession.context_from_record(record)
	assert_eq(context, {"outcome": "lose", "picks": ["explode_on_hit"], "worst_hit": "contact"})
	var s := DevSession.plan(1, context)
	assert_string_contains(s.opening, "crashed")
	assert_string_contains(s.opening, MutationDB.get_mutation(&"explode_on_hit").title)
	assert_string_contains(s.opening, "Contact hits")
	assert_string_contains(DevSession.plan(1, {"pending": true}).opening, DevSession.PENDING_LINE)


func test_the_session_telemetry_line() -> void:
	_live(1)
	var s := DevSession.plan(2)
	s.pick(0)
	var rec := s.telemetry_record(3)
	assert_eq(rec.type, "session")
	assert_eq(rec.schema, 2)
	assert_eq(rec.run_index, 3)
	assert_eq(rec.version_before, "v0.0.0")
	assert_eq(rec.version_after, "v0.1.0")
	assert_eq(rec.shape, "mockup")
	assert_eq(rec.pick, "look_1:punchy")
	for key in ["cards", "agenda", "ai_ship", "session_id"]:
		assert_true(rec.has(key), key)


func test_run_records_are_schema_2_with_look_pool_and_enemies() -> void:
	SaveGame.use_snapshot("", true)
	RunState.reset(3)
	var rec := Telemetry.build_record(&"win")
	assert_eq(rec.schema, 2)
	assert_eq(rec.look, {"tier": 0, "take": ""})
	assert_eq(rec.pool_size, 4)
	assert_eq(rec.enemies, ["chaser", "shooter"])
	for key in ["genre", "game_version", "version", "final_big", "genre_seconds"]:
		assert_true(rec.has(key), "schema 1 key %s is kept" % key)


## PLAN v5 6: a chained run of sessions from a fresh save ships all 6 changes by
## session 5 at v0.1.5 when the picks leave two or more cards each time, and session 6
## ships nothing.
func test_a_chain_of_sessions_ships_everything_by_v0_1_5() -> void:
	Tuning.ai_own_ship_every = 4
	var first := _chain()
	assert_eq(first.shapes, ["mockup", "changes", "changes", "changes", "ai_last", "none"])
	assert_eq(first.versions, ["v0.1.0", "v0.1.1", "v0.1.2", "v0.1.4", "v0.1.5", "v0.1.5"])
	assert_eq(SaveGame.shipped().size(), 6)
	assert_true(DevSession.available().is_empty())
	assert_true((first.agendas as Array).any(func(a: String) -> bool: return a != ""),
			"at least one agenda card over the chain")
	assert_eq(_chain().file, first.file, "the same chain writes the same save")


## Six runs and sessions from a fresh save. The tank is picked first, so sessions 3 and
## 4 still show 2+ cards (bot seeds may not, PLAN 4.7).
func _chain() -> Dictionary:
	_live(0)
	var out := {"versions": [], "shapes": [], "agendas": [], "file": ""}
	for run in 6:
		SaveGame.record_run(&"topdown", &"lose", 60.0, SaveGame.state().taste)
		var s := DevSession.plan(100 + run)
		out.shapes.append(String(s.shape))
		out.agendas.append(String(s.agenda_card().get("id", "")))
		if s.can_pick():
			assert_true(s.pick(maxi(0, _ids(s).find("enemy_tank"))))
		else:
			assert_true(s.finish())
		out.versions.append(SaveGame.version().label())
	out.file = FileAccess.get_file_as_string(TEST_PATH)
	return out


# --- Screens and the shell -----------------------------------------------------------

func test_the_report_button_says_dev_session_only_when_the_save_is_live() -> void:
	var report := ReportScreen.new()
	add_child_autofree(report)
	report.open(&"lose", {})
	assert_eq(report.main_button_text(), ReportScreen.NEW_BUILD, "inert")
	_live(1)
	report.open(&"lose", {})
	assert_eq(report.main_button_text(), ReportScreen.DEV_SESSION)
	RunState.set_pause(&"report", false)


func test_the_flow_shows_the_mockup_stills_then_the_patch_notes() -> void:
	_live(1)
	var flow := DevSessionFlow.new()
	add_child_autofree(flow)
	var played := []
	flow.play_requested.connect(func() -> void: played.append(true))
	var done := []
	flow.session_done.connect(func(s: DevSession) -> void: done.append(s))
	flow.start(DevSession.plan(1))
	assert_true(flow.screen.is_open())
	assert_false(flow.screen.can_pick(), "a moment of input delay first")
	flow.screen.pick(0)
	assert_false(SaveGame.has_shipped(&"look_1"))
	await wait_seconds(Tuning.prompt_input_delay + 0.1)
	assert_true(flow.screen.can_pick())
	assert_eq(flow.screen.still_size(1), DevSessionScreen.STILL)
	flow.screen.card_button(2).mouse_entered.emit()
	assert_eq(flow.screen.still_size(2), DevSessionScreen.STILL_BIG, "hover enlarges the still")
	flow.screen.card_button(2).mouse_exited.emit()
	assert_eq(flow.screen.still_size(2), DevSessionScreen.STILL)
	flow.screen.pick(2)
	assert_false(flow.screen.is_open())
	assert_true(flow.notes.is_open())
	assert_eq(done.size(), 1)
	assert_eq(Unlocks.look().take, "arcade")
	assert_string_contains(flow.notes.text(), "Version 0.1.0")
	assert_eq(flow.notes.play_label(), "Play v0.1.0")
	flow.notes.play()
	assert_eq(played.size(), 1)


func test_the_flow_skips_the_screen_when_the_ai_ships_the_last_change() -> void:
	_live(6)
	_ship_all_but(["enemy_bomber"])
	var flow := DevSessionFlow.new()
	add_child_autofree(flow)
	flow.start(DevSession.plan(1))
	assert_false(flow.screen.is_open())
	assert_true(flow.notes.is_open(), "straight to the patch notes")
	assert_string_contains(flow.notes.text(), DevSession.AI_LAST_LINE)
	assert_true(SaveGame.has_shipped(&"enemy_bomber"))


func test_the_flow_with_nothing_to_ship_offers_play_only() -> void:
	_live(7)
	_ship_all_but([])
	var flow := DevSessionFlow.new()
	add_child_autofree(flow)
	var played := []
	flow.play_requested.connect(func() -> void: played.append(true))
	flow.start(DevSession.plan(1))
	assert_true(flow.screen.is_open())
	flow.screen.play()
	assert_eq(played.size(), 1)
	assert_false(flow.notes.is_open(), "no notes: nothing shipped")
	assert_false(SaveGame.state().pending_session)


func test_a_game_opens_the_dev_session_from_its_report_when_the_save_is_live() -> void:
	_live(0)
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.run_loop.end(&"lose")
	SaveGame.record_run(&"topdown", &"lose", 30.0, {})   # what a live game's run end writes
	game.report.open(&"lose", game.genre.run_record())
	assert_eq(game.report.main_button_text(), ReportScreen.DEV_SESSION)
	game.report.new_build(77)
	assert_true(game.dev_flow.is_open())
	assert_false(game.report.is_open())
	assert_eq(game.dev_flow.session.shape, DevSession.MOCKUP)
	RunState.set_pause(&"dev_session", false)
	RunState.set_pause(&"report", false)


func test_shift_f9_ships_the_next_change_without_the_screen() -> void:
	_live(1)
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(1)
	var s := game.ship_next_change()
	assert_eq(s.shape, DevSession.MOCKUP)
	assert_true(SaveGame.has_shipped(&"look_1"))
	assert_false(game.dev_flow.is_open())
	# Mid-run, the run keeps the taste the session wrote (its end writes taste back).
	assert_eq(game.director.taste.to_save(), Taste.from_save(SaveGame.state().taste).to_save())
	# Never while a session is open: that session ships, a second would log twice.
	game.open_dev_session()
	assert_true(game.dev_flow.is_open())
	var sessions := SaveGame.session_count()
	assert_null(game.ship_next_change())
	assert_eq(SaveGame.session_count(), sessions)
	RunState.set_pause(&"dev_session", false)


func test_an_enemy_change_is_named_by_its_enemy() -> void:
	assert_eq(ChangeDB.get_change(&"enemy_tank").short_name(), "Tank")
	assert_eq(ChangeDB.get_change(&"patch_auto_attack").short_name(), "Auto-aim")
	_live(6)
	_ship_all_but(["enemy_bomber"])
	var s := DevSession.plan(1)
	assert_true(s.finish())
	var lines := s.notes_lines()
	assert_eq(lines.count("    New enemy: Bomber"), 0, "the bullet already says it")
	assert_string_contains(lines[1], "New enemy: Bomber")


func test_a_pending_session_opens_first_from_the_start_screen() -> void:
	_live(1)
	StartScreen.save_live = false   # the real save must not go live in a test
	var screen: StartScreen = load("res://ui/start_screen.tscn").instantiate()
	add_child_autofree(screen)
	assert_eq(screen.start_button.text, StartScreen.START_PENDING)
	assert_string_contains(screen.save_label.text, DevSession.PENDING_LINE)
	screen.start()
	assert_true(screen.dev_flow.is_open(), "the session comes before the game")
	assert_string_contains(screen.dev_flow.session.opening, DevSession.PENDING_LINE)
	assert_eq(screen.dev_flow.session.shape, DevSession.MOCKUP)
	await wait_seconds(Tuning.prompt_input_delay + 0.1)
	# Picking ships and writes its telemetry line; the notes' Play would start the game.
	var log_path := Telemetry.log_path
	Telemetry.log_path = "user://save_session_test/runs.jsonl"
	if FileAccess.file_exists(Telemetry.log_path):
		DirAccess.remove_absolute(Telemetry.log_path)
	screen.dev_flow.screen.pick(0)
	var lines := FileAccess.get_file_as_string(Telemetry.log_path).strip_edges().split("\n")
	DirAccess.remove_absolute(Telemetry.log_path)
	Telemetry.log_path = log_path
	assert_eq(lines.size(), 1)
	assert_eq((JSON.parse_string(lines[0]) as Dictionary).get("type"), "session")
	assert_false(SaveGame.state().pending_session)
	assert_true(screen.dev_flow.notes.is_open())
	screen.refresh_save()
	assert_eq(screen.start_button.text, StartScreen.START)

