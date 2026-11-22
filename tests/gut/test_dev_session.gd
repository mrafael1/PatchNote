extends GutTest
## The dev session: M29 (PLAN v5 4), reshaped around forks in M31 (PLAN v6 1.1-1.4).
## Every test that makes the save live points it at TEST_PATH; after_each puts the save
## back to inert and deletes the scratch files.

const TEST_PATH := "user://save_session_test/save.json"
const ALL: Array[String] = ["basic_movement", "basic_world", "enemy_bomber", "enemy_lancer",
		"enemy_tank", "look_1_arcade", "look_1_clean", "look_1_punchy", "patch_auto_attack",
		"patch_echo", "patch_elite", "patch_horde_mode", "patch_hunter", "patch_magnet",
		"patch_motion_time", "patch_orbit", "patch_well"]
const FORKS: Array[String] = ["fork_enemy", "fork_hands", "fork_odd", "fork_pressure", "look_1"]
const LOOKS: Array[String] = ["look_1_punchy", "look_1_clean", "look_1_arcade"]

var _changes: Array[Change] = []
var _forks: Array[Fork] = []
var _every := 0
var _rework_after := 0


func before_each() -> void:
	_delete_files()
	_every = Tuning.ai_own_ship_every
	_rework_after = Tuning.rework_after_forks


func after_each() -> void:
	assert_ne(SaveGame.save_path if SaveGame.persist else "", SaveGame.DEFAULT_PATH,
			"no test may leave the real save live")
	Tuning.ai_own_ship_every = _every
	Tuning.rework_after_forks = _rework_after
	SaveGame.go_inert()
	_delete_files()
	for f in _forks:
		ChangeDB.unregister_fork(f)
	_forks.clear()
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


## A fresh live save that has played `runs` runs (each one a pending session). The
## basics (v5 4.8) are shipped first unless told otherwise (v0.0.2): most tests are
## about what comes after them; tests/gut/test_first_builds.gd covers them.
func _live(runs := 1, basics := true) -> void:
	SaveGame.go_live(TEST_PATH, true)
	if basics:
		for id: StringName in [&"basic_movement", &"basic_world"]:
			SaveGame.ship(id, GameVersion.PATCH)
	for i in runs:
		SaveGame.record_run(&"topdown", &"lose", 60.0, SaveGame.state().taste)


func _ids(session: DevSession) -> Array:
	return session.cards.map(func(c: Dictionary) -> String: return c.id)


func _fork(id: StringName) -> Fork:
	return ChangeDB.get_fork(id)


## A test fork with `n` new options (unlocking nothing), registered until after_each.
func _test_fork(id: String, n := 3, tags: Array[StringName] = [], requires: Array[StringName] = []) -> Fork:
	var f := Fork.new()
	f.id = StringName(id)
	f.question = "Question %s?" % id
	f.tags = tags
	f.requires_forks = requires
	for i in n:
		var c := Change.new()
		c.id = StringName("%s_o%d" % [id, i])
		c.title = "Option %d of %s" % [i, id]
		c.pitch = "pitch"
		c.tags = tags.duplicate()
		if i == 1:
			c.tags.append(&"fx_disliked")   # option 1 is the one a test can make least liked
		ChangeDB.register(c)
		_changes.append(c)
		f.options.append(c.id)
	ChangeDB.register_fork(f)
	_forks.append(f)
	return f


## Ships every option of every fork: all answered, nothing on the shelf (as a v5 save
## that shipped everything loads).
func _ship_everything() -> void:
	for c in ChangeDB.all:
		SaveGame.ship(c.id, GameVersion.PATCH)


func _answer(fork_id: StringName, option := 0) -> Change:
	var c: Change = _fork(fork_id).changes()[option]
	SaveGame.ship(c.id, _fork(fork_id).bump)
	return c


# --- The content -------------------------------------------------------------------

func test_the_changes_and_forks_are_valid() -> void:
	var ids: Array[String] = []
	for c in ChangeDB.all:
		ids.append(String(c.id))
		assert_eq(ChangeDB.problems(c), [] as Array[String], String(c.id))
		assert_ne(c.title, "", String(c.id))
		assert_ne(c.pitch, "", String(c.id))
	assert_eq(ids, ALL)
	var fork_ids: Array[String] = []
	for f in ChangeDB.forks:
		fork_ids.append(String(f.id))
		assert_eq(ChangeDB.fork_problems(f), [] as Array[String], String(f.id))
		assert_ne(f.question, "", String(f.id))
	assert_eq(fork_ids, FORKS)
	# Every change but the basics answers exactly one fork.
	for c in ChangeDB.all:
		assert_eq(c.fork != &"", not c.is_basic(), "%s: in a fork unless a basic" % c.id)
	var look := _fork(&"look_1")
	assert_true(look.mockup)
	assert_eq(look.bump, GameVersion.MINOR)
	assert_eq(look.due_after_run, 1)
	assert_eq(look.options.map(func(o: StringName) -> String: return String(o)), LOOKS)
	for c in look.changes():
		var preset := c.take.preset as LookPreset
		assert_eq(preset.tier, 1)
		assert_eq(preset.take, c.take.id)
		assert_eq(Look.path_for(1, String(c.take.id)), preset.resource_path, "Look finds the take's preset")
		assert_eq(c.short_name(), c.take.title)
	assert_eq(_fork(&"fork_enemy").options, [&"enemy_tank", &"enemy_bomber", &"enemy_lancer"] as Array[StringName])
	assert_eq(_fork(&"fork_hands").options, [&"patch_auto_attack", &"patch_motion_time", &"patch_orbit"] as Array[StringName])
	assert_eq(_fork(&"fork_pressure").options, [&"patch_horde_mode", &"patch_hunter", &"patch_elite"] as Array[StringName])
	assert_eq(_fork(&"fork_pressure").requires_forks, [&"fork_enemy"] as Array[StringName], "was horde requires tank")
	assert_eq(_fork(&"fork_odd").requires_forks, [&"fork_hands"] as Array[StringName])
	for f in ChangeDB.forks:
		assert_eq(f.options.size(), 3, "%s: three answers (PLAN v6 3)" % f.id)
	# Dependencies sit on forks now (PLAN v6 1.1): no change requires another.
	for c in ChangeDB.all:
		if not c.is_basic():
			assert_true(c.requires.is_empty(), "%s requires nothing" % c.id)
	# Every patch and enemy that is not a starter ships through a change.
	var unlocked := []
	for c in ChangeDB.all:
		unlocked.append_array(c.unlocks)
	for m in MutationDB.offerable():
		assert_true(m.starter or unlocked.has(m.id), "%s ships through a change" % m.id)
	for a in Unlocks.ARCHETYPES:
		assert_true(a in Tuning.starter_enemies or unlocked.has(a), "%s ships through a change" % a)


func test_fork_problems_catch_each_bad_case() -> void:
	var lone := _test_fork("fx_lone", 1)
	assert_string_contains(" ".join(ChangeDB.fork_problems(lone)), "1 options, not 2 or 3")
	var ghost := _test_fork("fx_ghost", 2)
	ghost.options.append(&"no_such_change")
	assert_string_contains(" ".join(ChangeDB.fork_problems(ghost)), "unknown change 'no_such_change'")
	var thief := _test_fork("fx_thief", 2)
	thief.options[1] = &"enemy_tank"
	ChangeDB._link_forks()
	assert_string_contains(" ".join(ChangeDB.fork_problems(thief)), "'enemy_tank' is in two forks")
	var shown := _test_fork("fx_shown", 2)
	shown.mockup = true
	assert_string_contains(" ".join(ChangeDB.fork_problems(shown)), "no still")
	var a := _test_fork("fx_a", 2, [], [&"fx_b"])
	var b := _test_fork("fx_b", 2, [], [&"fx_a"])
	assert_string_contains(" ".join(ChangeDB.fork_problems(a)), "requires cycle")
	assert_string_contains(" ".join(ChangeDB.fork_problems(b)), "requires cycle")
	b.requires_forks = [&"fx_nowhere"]
	assert_string_contains(" ".join(ChangeDB.fork_problems(b)), "unknown fork 'fx_nowhere'")


# --- Which fork --------------------------------------------------------------------

func test_the_first_fork_session_is_the_look_mockup() -> void:
	_live(1)
	var s := DevSession.plan(5)
	assert_eq(s.shape, DevSession.FORK)
	assert_eq(s.fork.id, &"look_1")
	assert_eq(_ids(s), LOOKS)
	assert_true(s.agenda_card().is_empty(), "a mockup has no agenda card")
	assert_eq(s.number, 1)
	assert_eq(s.after_run, 1)
	assert_false(s.opening.contains(s.fork.question), "the question is the screen's title, not in the line")


func test_a_mockup_fork_waits_until_it_is_due() -> void:
	_live(0)   # F9 before any run: look_1 is due after run 1
	for run_seed in 10:
		var s := DevSession.plan(run_seed)
		assert_eq(s.shape, DevSession.FORK)
		assert_ne(s.fork.id, &"look_1", "seed %d" % run_seed)


func test_a_fork_is_ready_once_its_required_forks_are_answered_whatever_the_answer() -> void:
	var late := _test_fork("fx_late", 2, [], [&"fork_enemy"])
	_live(1)
	assert_false(late in DevSession.ready_forks())
	_answer(&"fork_enemy", 1)   # the bomber: any answer will do
	assert_true(late in DevSession.ready_forks())
	late.play_runs = 5
	assert_false(late in DevSession.ready_forks(), "its play threshold: 5 runs, 1 played")
	for i in 4:
		SaveGame.record_run(&"topdown", &"win", 60.0, {})
	assert_true(late in DevSession.ready_forks())
	late.due_after_run = 9
	assert_false(late in DevSession.ready_forks(), "not due yet")


func test_nothing_but_the_basics_while_one_is_missing() -> void:
	_live(1, false)
	assert_true(DevSession.ready_forks().is_empty())
	assert_eq(DevSession.plan(1).shape, DevSession.BASIC)


func test_a_fork_shows_its_options_with_the_least_liked_as_the_ais_wish_last() -> void:
	_live(1)
	_answer(&"look_1")
	_answer(&"fork_enemy")
	_answer(&"fork_pressure")   # left: fork_hands (fork_odd waits for it)
	var taste := Taste.new()
	taste.by_tag[&"time"] = -3.0
	taste.by_tag[&"weapon"] = 2.0
	SaveGame.state().taste = taste.to_save()
	for run_seed in 8:
		var s := DevSession.plan(run_seed)
		assert_eq(s.fork.id, &"fork_hands")
		var ids := _ids(s)
		ids.sort()
		assert_eq(ids, ["patch_auto_attack", "patch_motion_time", "patch_orbit"])
		assert_eq(s.cards.filter(func(c: Dictionary) -> bool: return c.agenda).size(), 1)
		assert_eq(s.agenda_card().id, "patch_motion_time", "the AI's wish is what the player likes least")
		assert_eq(s.cards[-1].id, "patch_motion_time", "and it is shown last")
		assert_eq(DevSession.card_line(s.agenda_card()), DevSession.AGENDA_LINE)


func test_same_seed_and_same_save_ask_the_same_fork() -> void:
	_live(1)
	_answer(&"look_1")   # fork_enemy and fork_hands are both ready, neither due
	var first := DevSession.plan(42)
	var forks := {}
	for run_seed in 30:
		forks[DevSession.plan(run_seed).fork.id] = true
	assert_eq(forks.size(), 2, "seeds choose which fork")
	for i in 5:
		var again := DevSession.plan(42)
		assert_eq(again.fork, first.fork)
		assert_eq(_ids(again), _ids(first))


func test_taste_leans_which_fork_comes_up() -> void:
	_live(1)
	_answer(&"look_1")
	var taste := Taste.new()
	taste.by_tag[&"spawn"] = 4.0
	taste.by_tag[&"weapon"] = -4.0
	taste.by_tag[&"time"] = -4.0
	SaveGame.state().taste = taste.to_save()
	var enemy := 0
	for run_seed in 40:
		if DevSession.plan(run_seed).fork.id == &"fork_enemy":
			enemy += 1
	assert_gt(enemy, 28, "a liked fork comes up more often (%d of 40)" % enemy)


func test_every_fork_answered_with_an_empty_shelf_means_no_bump_and_the_next_run() -> void:
	_live(7)
	_ship_everything()
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

func test_picking_a_look_ships_it_bumps_minor_shelves_the_others_and_writes_taste() -> void:
	_live(1)
	assert_true(SaveGame.state().pending_session)
	var s := DevSession.plan(9)
	assert_true(s.pick(1))   # clean
	assert_true(SaveGame.has_shipped(&"look_1_clean"))
	assert_eq(SaveGame.version().label(), "v0.1.0")
	assert_eq(Unlocks.look(), {"tier": 1, "take": "clean"})
	assert_eq(Look.use(Unlocks.look()).take, &"clean")
	var shelf := s.fork.shelf().map(func(c: Change) -> String: return String(c.id))
	assert_eq(shelf, ["look_1_punchy", "look_1_arcade"])
	var written: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
	assert_false(written.pending_session)
	assert_eq(written.look.take, "clean")
	var entry: Dictionary = written.sessions[0]
	assert_eq(int(entry.after_run), 1)
	entry.erase("after_run")
	assert_eq(entry, {"version": "0.1.0", "shape": "fork", "fork": "look_1", "cards": LOOKS,
			"pick": "look_1_clean", "shelved": ["look_1_punchy", "look_1_arcade"], "agenda": "",
			"ai_ship": "", "ai_fork": "", "rework": "", "kept": false})
	assert_gt(float(written.taste.by_id["look:clean"]), 0.0)
	assert_lt(float(written.taste.by_id["look:punchy"]), 0.0)
	assert_false(s.pick(0), "a session ships once")
	var lines := s.notes_lines()
	assert_eq(lines[0], "Version 0.1.0")
	assert_has(lines, "    New look: Clean")
	assert_has(lines, DevSession.SHELF_LINE % "Punchy, Arcade")


func test_picking_a_change_ships_it_bumps_patch_and_feeds_its_tags() -> void:
	_live(2)
	_answer(&"look_1")
	_answer(&"fork_enemy")
	_answer(&"fork_pressure")
	var s := DevSession.plan(4)
	assert_eq(s.fork.id, &"fork_hands")
	var index := _ids(s).find("patch_auto_attack")
	var picked: Change = s.cards[index].change
	var tags_before: Dictionary = SaveGame.state().taste.by_tag.duplicate()
	assert_true(s.pick(index))
	assert_true(SaveGame.has_shipped(&"patch_auto_attack"))
	assert_false(SaveGame.has_shipped(&"patch_orbit"), "shelved")
	assert_false(SaveGame.has_shipped(&"patch_motion_time"), "shelved")
	assert_eq(SaveGame.version().label(), "v0.1.3", "a pick is a patch step")
	assert_gt(float(SaveGame.state().taste.by_tag.get("weapon", 0.0)), float(tags_before.get("weapon", 0.0)))
	var lines := s.notes_lines()
	assert_eq(lines[1], "• %s: %s" % [picked.title, picked.pitch])
	assert_has(lines, "    New patch in the pool: Automate attacking")
	assert_has(Unlocks.pool(), MutationDB.get_mutation(&"auto_attack"))
	assert_false(Unlocks.pool().has(MutationDB.get_mutation(&"orbit")), "a shelved patch is not in the pool")
	assert_true(_fork(&"fork_odd") in DevSession.ready_forks(), "its answer opens the odd question")


func test_the_ai_answers_another_fork_every_fourth_session() -> void:
	Tuning.ai_own_ship_every = 4
	for id in ["fx_p", "fx_q", "fx_r"]:
		_test_fork(id, 3, [StringName(id)])
	_live(4)
	_answer(&"look_1")
	_answer(&"fork_enemy")
	_answer(&"fork_hands")
	_answer(&"fork_pressure")
	_answer(&"fork_odd")   # left: the 3 test forks
	for i in 3:
		SaveGame.finish_session({"after_run": i + 1})
	var taste := Taste.new()
	taste.by_tag[&"fx_disliked"] = -5.0
	SaveGame.state().taste = taste.to_save()
	var s := DevSession.plan(11)
	assert_eq(s.number, 4)
	var answered_by_player := s.fork
	assert_true(s.pick(0))
	assert_eq(s.shipped.size(), 2, "the pick and the AI's answer")
	var ai: Dictionary = s.shipped[1]
	assert_eq(ai.by, DevSession.AI)
	assert_ne(ai.fork, answered_by_player, "another fork")
	assert_false((ai.fork as Fork).mockup)
	assert_true((ai.fork as Fork).is_answered())
	assert_eq(SaveGame.version().label(), "v0.1.6", "one bump each")
	assert_eq(s.ai_fork(), "%s:%s" % [(ai.fork as Fork).id, (ai.change as Change).id])
	assert_has(s.notes_lines(), DevSession.AI_FORK_LINE % [(ai.fork as Fork).question, (ai.change as Change).short_name()])
	assert_true(String((ai.change as Change).id).ends_with("_o1"), "its wish: the option the player likes least")


func test_the_ai_never_answers_the_players_last_question() -> void:
	Tuning.ai_own_ship_every = 4
	_live(4)
	_answer(&"look_1")
	_answer(&"fork_enemy")
	_answer(&"fork_pressure")
	for i in 3:
		SaveGame.finish_session({"after_run": i + 1})
	var s := DevSession.plan(11)   # fork_hands; its answer opens fork_odd: one left
	assert_eq(s.fork.id, &"fork_hands")
	assert_true(s.pick(0))
	assert_eq(s.shipped.size(), 1)
	assert_eq(DevSession.ready_forks().size(), 1, "the last question stays the player's")
	# 0 turns it off even with plenty of forks.
	Tuning.ai_own_ship_every = 0
	for id in ["fx_p", "fx_q", "fx_r"]:
		_test_fork(id)
	_live(4)
	_answer(&"look_1")
	for i in 3:
		SaveGame.finish_session({"after_run": i + 1})
	var off := DevSession.plan(11)
	assert_true(off.pick(0))
	assert_eq(off.ai_fork(), "")


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


func test_the_session_telemetry_line_is_schema_3() -> void:
	_live(1)
	var s := DevSession.plan(2)
	s.pick(0)
	var rec := s.telemetry_record(3)
	assert_eq(rec.type, "session")
	assert_eq(rec.schema, 3)
	assert_eq(rec.run_index, 3)
	assert_eq(rec.version_before, "v0.0.2")
	assert_eq(rec.version_after, "v0.1.0")
	assert_eq(rec.shape, "fork")
	assert_eq(rec.fork, "look_1")
	assert_eq(rec.pick, "look_1_punchy")
	assert_eq(rec.shelved, ["look_1_clean", "look_1_arcade"])
	assert_eq(rec.rework, null)
	assert_false(rec.kept)
	for key in ["cards", "agenda", "ai_ship", "ai_fork", "session_id"]:
		assert_true(rec.has(key), key)


func test_run_records_are_schema_3_with_the_fork_answers() -> void:
	SaveGame.use_snapshot("", true)
	RunState.reset(3)
	var rec := Telemetry.build_record(&"win")
	assert_eq(rec.schema, 3)
	assert_eq(rec.forks, {})
	assert_eq(rec.look, {"tier": 0, "take": ""})
	assert_eq(rec.pool_size, 4)
	assert_eq((rec.pool as Array).size(), 4)
	assert_eq(rec.enemies, ["chaser", "shooter"])
	SaveGame.ship(&"enemy_bomber", GameVersion.PATCH)
	assert_eq(Telemetry.build_record(&"win").forks, {"fork_enemy": "enemy_bomber"})


# --- Old saves (PLAN v6 1.4) ---------------------------------------------------------

func test_a_v5_save_keeps_its_look_and_its_answers() -> void:
	var v5 := SaveGame.new_state()
	v5.shipped = ["basic_movement", "basic_world", "look_1", "enemy_tank", "enemy_bomber"]
	v5.look = {"tier": 1, "take": "clean"}
	var parsed: Dictionary = SaveGame.parse(JSON.parse_string(JSON.stringify(v5)))
	assert_eq(parsed.shipped, ["basic_movement", "basic_world", "look_1_clean", "enemy_tank", "enemy_bomber"])
	SaveGame.go_live(TEST_PATH, true)
	SaveGame.state().shipped = parsed.shipped
	assert_true(_fork(&"fork_enemy").is_answered())
	assert_eq(parsed.shipped.size(), 5, "both shipped, nothing unshipped")
	assert_eq(_fork(&"fork_enemy").shelf(), [ChangeDB.get_change(&"enemy_lancer")] as Array[Change],
			"only the M33 lancer on the shelf")
	# A v5 save that answered with Horde (then in fork_hands) keeps it, and so answers
	# the pressure question; the hands question is asked again (PLAN v6 M33).
	SaveGame.state().shipped = ["basic_movement", "basic_world", "look_1_clean", "enemy_tank", "patch_horde_mode"]
	assert_true(_fork(&"fork_pressure").is_answered())
	assert_eq(_fork(&"fork_pressure").answer(), ChangeDB.get_change(&"patch_horde_mode"))
	assert_false(_fork(&"fork_hands").is_answered())
	assert_true(_fork(&"fork_hands") in DevSession.ready_forks())
	assert_eq(_fork(&"look_1").shelf().size(), 2)
	var no_take := SaveGame.new_state()
	no_take.shipped = ["look_1"]
	assert_eq((SaveGame.parse(JSON.parse_string(JSON.stringify(no_take))) as Dictionary).shipped,
			["look_1_punchy"], "no take on record: punchy, the v5 default")


# --- Rework (PLAN v6 1.3) ------------------------------------------------------------

## Look Punchy and the Tank answered (v0.1.1), fork_hands still open: a fork session
## that offers Rework.
func _two_answered() -> DevSession:
	_live(3)
	_answer(&"look_1")
	_answer(&"fork_enemy")
	var s := DevSession.plan(5)
	assert_eq(s.shape, DevSession.FORK)
	return s


## What the next run plays: the pool, the enemies and the look.
func _next_run() -> Dictionary:
	return {"pool": Unlocks.pool().map(func(m: Mutation) -> String: return String(m.id)),
			"enemies": Unlocks.enemies(), "look": Unlocks.look()}


func test_a_rework_swaps_one_answer_for_a_shelved_one_with_one_patch_step() -> void:
	var s := _two_answered()
	assert_true(s.can_rework())
	var tags_before: Dictionary = SaveGame.state().taste.by_tag.duplicate()
	assert_false(s.rework(&"fork_enemy", &"enemy_tank"), "the answer is not on the shelf")
	assert_false(s.rework(&"fork_hands", &"patch_orbit"), "an open fork has no shelf")
	assert_true(s.rework(&"fork_enemy", &"enemy_bomber"))
	assert_false(SaveGame.has_shipped(&"enemy_tank"))
	assert_true(SaveGame.has_shipped(&"enemy_bomber"))
	assert_eq(SaveGame.version().label(), "v0.1.2")
	assert_true(&"bomber" in Unlocks.enemies())
	assert_false(&"tank" in Unlocks.enemies(), "the next run has no tank")
	assert_eq(_fork(&"fork_enemy").shelf(), [ChangeDB.get_change(&"enemy_tank"),
			ChangeDB.get_change(&"enemy_lancer")] as Array[Change])
	assert_false(_fork(&"fork_hands").is_answered() or _fork(&"fork_pressure").is_answered(),
			"a rework costs the session: no new answer")
	assert_eq(DevSession.answers().size(), 2, "a rework never unanswers a fork")
	assert_false(s.pick(0), "nor a pick after it")
	assert_false(s.rework(&"fork_enemy", &"enemy_tank"), "one rework per session")
	var entry: Dictionary = SaveGame.state().sessions[-1]
	assert_eq(entry.rework, "fork_enemy:enemy_tank->enemy_bomber")
	assert_eq(entry.pick, "")
	assert_eq(entry.shelved, [])
	var rec := s.telemetry_record(4)
	assert_eq(rec.rework, {"fork": "fork_enemy", "from": "enemy_tank", "to": "enemy_bomber"})
	assert_false(rec.kept)
	# A strong signal: the new answer's tags up, the old one's down.
	var tags: Dictionary = SaveGame.state().taste.by_tag
	for tag: StringName in ChangeDB.get_change(&"enemy_bomber").tags:
		if not tag in ChangeDB.get_change(&"enemy_tank").tags:
			assert_gt(float(tags.get(String(tag), 0.0)), float(tags_before.get(String(tag), 0.0)), String(tag))
	var lines := s.notes_lines()
	assert_eq(lines, ["Version 0.1.2",
			DevSession.REWORKED_LINE % [_fork(&"fork_enemy").question, "Tank", "Bomber"],
			"    No more Tanks", "    New enemy: Bomber",
			DevSession.BACK_ON_SHELF_LINE % "Tank"] as Array[String])


func test_reworking_back_restores_the_first_state_but_the_version() -> void:
	var s := _two_answered()
	var first := _next_run()
	var shipped_first := SaveGame.shipped()
	shipped_first.sort()
	assert_true(s.rework(&"fork_enemy", &"enemy_bomber"))
	assert_ne(_next_run(), first)
	SaveGame.record_run(&"topdown", &"lose", 60.0, SaveGame.state().taste)
	var again := DevSession.plan(6)
	assert_true(again.rework(&"fork_enemy", &"enemy_tank"))
	assert_eq(_next_run(), first)
	var shipped_now := SaveGame.shipped()
	shipped_now.sort()
	assert_eq(shipped_now, shipped_first)
	assert_eq(SaveGame.version().label(), "v0.1.3", "the version only goes up")
	assert_eq(SaveGame.session_count(), 2)


func test_reworking_a_look_swaps_the_look_with_a_patch_step() -> void:
	var s := _two_answered()
	assert_true(s.rework(&"look_1", &"look_1_arcade"))
	assert_eq(Unlocks.look(), {"tier": 1, "take": "arcade"})
	assert_eq(SaveGame.version().label(), "v0.1.2", "never a minor step, even on a minor fork")
	assert_eq(s.notes_lines(), ["Version 0.1.2",
			DevSession.REWORKED_LINE % [_fork(&"look_1").question, "Punchy", "Arcade"],
			"    New look: Arcade", DevSession.BACK_ON_SHELF_LINE % "Punchy"] as Array[String])
	var taste: Dictionary = SaveGame.state().taste.by_id
	assert_gt(float(taste["look:arcade"]), 0.0)
	assert_lt(float(taste["look:punchy"]), float(taste.get("look:clean", 0.0)), "the old look counts against")


func test_reworking_a_patch_swaps_the_pool() -> void:
	_live(3)
	_answer(&"look_1")
	_answer(&"fork_hands")   # Auto-aim
	var s := DevSession.plan(5)
	assert_true(s.rework(&"fork_hands", &"patch_orbit"))
	var pool: Array = _next_run().pool
	assert_has(pool, "orbit")
	assert_does_not_have(pool, "auto_attack")
	assert_has(s.notes_lines(), "    Out of the pool: %s" % MutationDB.get_mutation(&"auto_attack").title)


func test_the_rework_card_needs_two_answers_and_a_shelf() -> void:
	_live(1)
	_answer(&"look_1")
	var one := DevSession.plan(5)
	assert_eq(one.shape, DevSession.FORK)
	assert_false(one.can_rework(), "one answer: below rework_after_forks")
	assert_false(one.rework(&"look_1", &"look_1_clean"))
	Tuning.rework_after_forks = 1
	assert_true(DevSession.plan(5).can_rework())
	Tuning.rework_after_forks = 2
	# Two answered with an empty shelf (a v5 save that shipped every option).
	for id: StringName in [&"look_1_clean", &"look_1_arcade", &"enemy_tank", &"enemy_bomber", &"enemy_lancer"]:
		SaveGame.ship(id, GameVersion.PATCH)
	var bare := DevSession.plan(5)
	assert_eq(bare.shape, DevSession.FORK)
	assert_false(bare.can_rework(), "nothing on the shelf")
	assert_true(DevSession.rework_rows().is_empty())


func test_no_question_left_but_a_shelf_is_a_rework_only_session() -> void:
	Tuning.ai_own_ship_every = 1   # the AI answers nothing here even on its cadence
	_live(7)
	for f: String in FORKS:
		_answer(StringName(f))
	var before := SaveGame.version()
	var s := DevSession.plan(3)
	assert_eq(s.shape, DevSession.REWORK)
	assert_true(s.cards.is_empty())
	assert_false(s.can_pick())
	assert_true(s.can_rework())
	assert_string_contains(s.opening, DevSession.REWORK_LINE)
	var rows := DevSession.rework_rows()
	assert_eq(rows.map(func(r: Dictionary) -> String: return String((r.fork as Fork).id)), FORKS)
	assert_eq((rows[0].to as Array).size(), 2, "fork_enemy: two options on the shelf")
	assert_true(s.keep())
	assert_true(SaveGame.version().equals(before), "keep it as it is: no bump")
	assert_true(s.notes_lines().is_empty())
	var entry: Dictionary = SaveGame.state().sessions[-1]
	assert_eq(entry.shape, "rework")
	assert_true(entry.kept)
	assert_eq(entry.ai_fork, "")
	assert_true(s.telemetry_record(1).kept)
	# The next one can swap instead.
	var swap := DevSession.plan(4)
	assert_true(swap.rework(&"fork_hands", &"patch_motion_time"))
	assert_eq(swap.ai_fork(), "")


func test_cards_shrink_to_fit_the_screen() -> void:
	assert_eq(DevSessionScreen.card_width(3, false, false, 1280.0), 340.0, "room enough")
	assert_eq(DevSessionScreen.card_width(2, true, false, 1280.0), 440.0)
	for n in [2, 3]:
		for mockup in [false, true]:
			for rework in [false, true]:
				var w := DevSessionScreen.card_width(n, mockup, rework, 1280.0)
				var total: float = n * w + DevSessionScreen.CARD_GAP * (n - 1) + 2 * DevSessionScreen.SIDE_MARGIN
				if rework:
					total += DevSessionScreen.REWORK_CARD_WIDTH + DevSessionScreen.CARD_GAP
				assert_lte(total, 1280.0, "%d cards, mockup %s, rework %s" % [n, mockup, rework])


func test_the_flow_offers_rework_as_a_fourth_card_and_back() -> void:
	var s := _two_answered()
	var flow := DevSessionFlow.new()
	add_child_autofree(flow)
	var done := []
	flow.session_done.connect(func(d: DevSession) -> void: done.append(d))
	flow.start(s)
	await wait_seconds(Tuning.prompt_input_delay + 0.1)
	assert_true(flow.screen.has_rework_card())
	assert_eq(flow.screen.card_button(s.cards.size()).get_child(0).get_child(0).text,
			"[4]  %s" % DevSession.REWORK_TITLE, "last, on key 4")
	var key := InputEventAction.new()
	key.action = &"choose_4"
	key.pressed = true
	flow.screen._unhandled_input(key)
	assert_true(flow.screen.list_open())
	assert_false(flow.screen.list_ready(), "the input delay again")
	await wait_seconds(Tuning.prompt_input_delay + 0.1)
	var targets := flow.screen.rework_targets().map(func(t: Array) -> String: return "%s:%s" % t)
	assert_eq(targets, ["fork_enemy:enemy_bomber", "fork_enemy:enemy_lancer", "look_1:look_1_clean",
			"look_1:look_1_arcade"])
	assert_null(flow.screen.row_button(1).icon)
	assert_not_null(flow.screen.row_button(2).icon, "a mockup fork shows its shelved stills")
	assert_eq(flow.screen.list_button().text, "Back")
	flow.screen.press_list_button()
	assert_false(flow.screen.list_open())
	await wait_seconds(Tuning.prompt_input_delay + 0.1)
	assert_true(flow.screen.can_pick(), "back on the cards")
	flow.screen.open_rework()
	await wait_seconds(Tuning.prompt_input_delay + 0.1)
	flow.screen.row_button(0).pressed.emit()
	assert_false(flow.screen.is_open())
	assert_eq(done.size(), 1)
	assert_true(SaveGame.has_shipped(&"enemy_bomber"))
	assert_true(flow.notes.is_open())
	assert_string_contains(flow.notes.text(), "Tank → Bomber")


func test_the_flow_of_a_rework_only_session_opens_on_the_list_with_keep() -> void:
	_live(7)
	for f: String in FORKS:
		_answer(StringName(f))
	var flow := DevSessionFlow.new()
	add_child_autofree(flow)
	var played := []
	flow.play_requested.connect(func() -> void: played.append(true))
	flow.start(DevSession.plan(1))
	assert_true(flow.screen.list_open())
	assert_eq(flow.screen.list_button().text, DevSession.KEEP_LABEL)
	flow.screen.play()
	assert_eq(played.size(), 0, "no Play button: keep or swap")
	await wait_seconds(Tuning.prompt_input_delay + 0.1)
	flow.screen.press_list_button()
	assert_eq(played.size(), 1)
	assert_false(flow.notes.is_open(), "nothing shipped: no notes")
	assert_true(SaveGame.state().sessions[-1].kept)


func test_the_f2_rework_swaps_between_runs() -> void:
	_live(3)
	_answer(&"look_1")
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(1)
	var s := game.debug_rework(&"look_1", &"look_1_clean")
	assert_not_null(s)
	assert_eq(Unlocks.look().take, "clean")
	assert_eq(s.rework_id(), "look_1:look_1_punchy->look_1_clean")
	assert_null(game.debug_rework(&"look_1", &"look_1_clean"), "not on the shelf any more")
	SaveGame.go_inert()
	assert_null(game.debug_rework(&"look_1", &"look_1_punchy"), "inert: nothing to swap")


## A chained run of sessions from a fresh save: two basics, the look mockup, then one
## fork per session (and the AI's own on its cadence) until none is left, then
## REWORK-only sessions that keep. The same chain writes the same file.
func test_a_chain_of_sessions_answers_every_fork() -> void:
	Tuning.ai_own_ship_every = 4
	var first := _chain()
	assert_eq(first.shapes.slice(0, 3), ["basic", "basic", "fork"])
	assert_eq(first.forks[2], "look_1")
	assert_eq(first.forks.filter(func(f: String) -> bool: return f != "").size() + first.ai_forks,
			FORKS.size(), "every fork answered once, by the player or the AI")
	assert_eq(first.shapes[-1], "rework")
	assert_true(SaveGame.state().sessions[-1].kept, "the chain keeps it as it is")
	assert_eq(first.versions.slice(0, 3), ["v0.0.1", "v0.0.2", "v0.1.0"])
	assert_eq(DevSession.answers().size(), FORKS.size())
	assert_true(DevSession.ready_forks().is_empty())
	assert_eq(SaveGame.shipped().size(), 2 + FORKS.size(), "one answer per fork, the rest shelved")
	assert_eq(_chain().file, first.file, "the same chain writes the same save")


func _chain() -> Dictionary:
	_live(0, false)
	var out := {"versions": [], "shapes": [], "forks": [], "ai_forks": 0, "file": ""}
	for run in 9:
		SaveGame.record_run(&"topdown", &"lose", 60.0, SaveGame.state().taste)
		var s := DevSession.plan(100 + run)
		out.shapes.append(String(s.shape))
		out.forks.append(String(s.fork.id) if s.fork else "")
		if s.can_pick():
			assert_true(s.pick(run % s.cards.size()))
			if s.ai_fork() != "":
				out.ai_forks += 1
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
	assert_false(SaveGame.has_shipped(&"look_1_punchy"))
	await wait_seconds(Tuning.prompt_input_delay + 0.1)
	assert_true(flow.screen.can_pick())
	var sizes := flow.screen.still_sizes()
	assert_eq(flow.screen.still_size(1), sizes[0])
	flow.screen.card_button(2).mouse_entered.emit()
	assert_eq(flow.screen.still_size(2), sizes[1], "hover enlarges the still")
	assert_gt(sizes[1].x, sizes[0].x)
	flow.screen.card_button(2).mouse_exited.emit()
	assert_eq(flow.screen.still_size(2), sizes[0])
	# Every card fits the screen (three mockup cards overflowed from M29 to M32).
	var right := 0.0
	for i in 3:
		right = maxf(right, flow.screen.card_button(i).get_global_rect().end.x)
	assert_lte(right, 1280.0, "the cards fit the 1280 px screen")
	assert_lte(flow.screen.card_button(1).size.x, 400.0)
	flow.screen.pick(2)
	assert_false(flow.screen.is_open())
	assert_true(flow.notes.is_open())
	assert_eq(done.size(), 1)
	assert_eq(Unlocks.look().take, "arcade")
	assert_string_contains(flow.notes.text(), "Version 0.1.0")
	assert_string_contains(flow.notes.text(), "On the shelf: Punchy, Clean.")
	assert_eq(flow.notes.play_label(), "Play v0.1.0")
	flow.notes.play()
	assert_eq(played.size(), 1)


func test_the_flow_with_nothing_to_ship_offers_play_only() -> void:
	_live(7)
	_ship_everything()
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
	assert_eq(game.dev_flow.session.fork.id, &"look_1")
	RunState.set_pause(&"dev_session", false)
	RunState.set_pause(&"report", false)


func test_shift_f9_answers_the_next_fork_without_the_screen() -> void:
	_live(1)
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(1)
	var s := game.ship_next_change()
	assert_eq(s.fork.id, &"look_1")
	assert_true(SaveGame.has_shipped(&"look_1_punchy"), "its first option")
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


func test_short_names() -> void:
	assert_eq(ChangeDB.get_change(&"enemy_tank").short_name(), "Tank")
	assert_eq(ChangeDB.get_change(&"patch_auto_attack").short_name(), "Auto-aim")
	assert_eq(ChangeDB.get_change(&"look_1_arcade").short_name(), "Arcade")
	assert_eq(DevSession.unlock_lines(ChangeDB.get_change(&"enemy_bomber")), ["New enemy: Bomber"] as Array[String])
	assert_eq(DevSession.unlock_lines(ChangeDB.get_change(&"basic_world")), [] as Array[String],
			"a basic is not an enemy")


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
	assert_eq(screen.dev_flow.session.fork.id, &"look_1")
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
	assert_string_contains(screen.save_label.text, "1/%d forks" % FORKS.size())
