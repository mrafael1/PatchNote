extends GutTest
## M43 (PLAN v9 1.1, 1.3): answers generically (Unlocks.answer/take, fork: fields,
## --answer=), the generic Line conditions (&, !, attempts:, died_in:) and the cue grammar
## ([cond] <when> [N] [at s] [[tag]]). Everything runs on in-memory saves.

const STAGE1_FORKS: Array[StringName] = [&"fork_mascot", &"fork_dash", &"fork_dash_aim", &"fork_enemy"]


func before_each() -> void:
	SaveGame.use_snapshot("", true)   # a new save in memory: nothing shipped, nothing written


func after_each() -> void:
	SaveGame.go_inert()
	CampaignDB.active = false
	RunState.session = null


func _session(id: StringName) -> SessionDef:
	var s := SessionDef.new()
	s.id = id
	s.title = String(id)
	s.goal = SessionDef.SURVIVE
	s.goal_value = 10.0
	return s


func _campaign(sessions: Array) -> CampaignDef:
	var c := CampaignDef.new()
	c.stage_titles = CampaignDB.campaign.stage_titles.duplicate()
	c.sessions.assign(sessions)
	return c


# --- Unlocks.answer / take ----------------------------------------------------------

func test_answer_and_take_for_every_stage_1_fork() -> void:
	for fork_id in STAGE1_FORKS:
		var f := ChangeDB.get_fork(fork_id)
		assert_not_null(f, String(fork_id))
		for option in f.changes():
			SaveGame.use_snapshot("", true)
			assert_null(Unlocks.answer(fork_id), "%s unanswered" % fork_id)
			assert_eq(Unlocks.take(fork_id), &"", "%s: no take while unanswered" % fork_id)
			SaveGame.ship(option.id, GameVersion.PATCH)
			assert_eq(Unlocks.answer(fork_id), option, String(option.id))
			assert_eq(Unlocks.take(fork_id), option.take.id if option.take != null else &"", String(option.id))
	assert_null(Unlocks.answer(&"fork_nope"))
	assert_eq(Unlocks.take(&"fork_nope"), &"")


func test_the_dash_readers_stand_on_take() -> void:
	assert_eq(Unlocks.dash_answer(), &"classic", "unanswered: classic")
	assert_eq(Unlocks.dash_aim_answer(), &"move", "unanswered: move")
	SaveGame.ship(&"dash_teleport", GameVersion.PATCH)
	SaveGame.ship(&"dashdir_aim", GameVersion.PATCH)
	assert_eq(Unlocks.dash_answer(), &"teleport")
	assert_eq(Unlocks.dash_aim_answer(), &"aim")
	assert_eq(Unlocks.take(&"fork_dash"), Unlocks.dash_answer())


# --- fork: fields ---------------------------------------------------------------------

## No Stage 2 fork exists yet: fork_dash stands in for fork_path / fork_look.
func test_resolve_and_look_spec_read_fork_fields() -> void:
	var s := _session(&"x")
	s.path = &"arsenal"
	assert_eq(s.resolve(&"path"), &"arsenal")
	s.path = &"fork:fork_dash"
	s.hud = &"fork:fork_dash"
	assert_eq(s.resolve(&"path"), &"", "unanswered")
	SaveGame.ship(&"dash_grapple", GameVersion.PATCH)
	assert_eq(s.resolve(&"path"), &"grapple")
	assert_eq(s.resolve(&"hud"), &"grapple")
	s.look = "punchy"
	assert_eq(s.look_spec(), {"tier": 1, "take": "punchy"})
	s.look = "clean@2"
	assert_eq(s.look_spec(), {"tier": 2, "take": "clean"})
	s.look = ""
	assert_eq(s.look_spec(), {"tier": 0, "take": ""})
	s.look = "fork:fork_dash_aim@2"
	assert_eq(s.look_spec(), {"tier": 0, "take": ""}, "an unanswered fork is tier 0")
	SaveGame.ship(&"dashdir_move", GameVersion.PATCH)
	assert_eq(s.look_spec(), {"tier": 2, "take": "move"})
	assert_eq(SessionDef.fork_of("fork:fork_look@2"), &"fork_look")
	assert_eq(SessionDef.fork_of(&"chaser"), &"")
	s.look = "neon@x"
	assert_string_contains(str(s.problems()), "bad look tier")
	s.look = "punchy@2"
	assert_string_contains(str(s.problems()), "no look punchy@2", "no tier 2 preset yet")


func test_a_fork_field_before_its_fork_is_asked_is_a_problem() -> void:
	var early := _session(&"early")
	early.basics = [&"enemies"]
	early.enemies = [SessionDef.FORK_ENEMY]
	early.look = "fork:fork_mascot"
	var asks := _session(&"asks")
	asks.fork = &"fork_enemy"
	asks.more_forks = [&"fork_mascot"] as Array[StringName]
	var text := "\n".join(CampaignDB.problems(_campaign([early, asks])))
	assert_string_contains(text, "early uses fork:fork_enemy before it is asked")
	assert_string_contains(text, "early uses fork:fork_mascot before it is asked")
	text = "\n".join(CampaignDB.problems(_campaign([asks, early])))
	assert_false("before it is asked" in text, text)
	assert_eq(asks.fork_refs(), [] as Array[StringName])
	assert_eq(early.fork_refs(), [&"fork_enemy", &"fork_mascot"] as Array[StringName])
	var bad := _session(&"bad")
	bad.path = &"fork:fork_nope"
	bad.stages = &"nowhere"
	bad.hud = &"corner"
	assert_string_contains(str(bad.problems()), "path names no fork fork_nope")
	assert_string_contains(str(bad.problems()), "no stage set nowhere")
	assert_string_contains(str(bad.problems()), "hud must be a fork")


# --- --answer= --------------------------------------------------------------------------

func test_answer_args_equal_the_dash_aliases() -> void:
	var a := CampaignDB.answers_from_args(PackedStringArray(["--answer=fork_dash=dash_grapple",
			"--answer=fork_dash_aim=dashdir_aim"]))
	var b := CampaignDB.answers_from_args(PackedStringArray(["--dash=grapple", "--dash-aim=aim"]))
	assert_eq(a, b)
	assert_eq(a, {&"fork_dash": &"dash_grapple", &"fork_dash_aim": &"dashdir_aim"})
	assert_eq(CampaignDB.answers_from_args(PackedStringArray(["--dash=none"])), {}, "none answers nothing")
	assert_eq(CampaignDB.answers_from_args(PackedStringArray(["--answer=fork_dash=dash_teleport",
			"--dash=grapple"])), {&"fork_dash": &"dash_teleport"}, "the first answer for a fork wins")
	var shipped := []
	var versions := []
	for answers: Dictionary in [a, b]:
		SaveGame.use_snapshot("", true)
		for f: StringName in answers:
			assert_true(CampaignDB.answer_fork(f, answers[f]))
		shipped.append(SaveGame.shipped())
		versions.append(SaveGame.version().label())
	assert_eq(shipped[0], shipped[1])
	assert_eq(versions[0], versions[1])


func test_answer_fork_ships_a_patch_and_the_dash_wrappers_use_it() -> void:
	assert_true(CampaignDB.answer_fork(&"fork_dash", &"dash_grapple"))
	assert_eq(SaveGame.version().label(), "v0.0.1", "a patch bump")
	var by_fork := SaveGame.shipped()
	SaveGame.use_snapshot("", true)
	assert_true(CampaignDB.answer_dash(&"grapple"))
	assert_eq(SaveGame.shipped(), by_fork)
	assert_eq(SaveGame.version().label(), "v0.0.1")
	assert_true(CampaignDB.answer_dash(&"teleport"), "answered already: ships nothing more")
	assert_eq(SaveGame.shipped(), by_fork)
	assert_false(CampaignDB.answer_fork(&"fork_dash", &"enemy_tank"), "not one of its options")
	assert_false(CampaignDB.answer_fork(&"fork_nope", &"dash_grapple"))
	assert_true(CampaignDB.answer_fork(&"fork_mascot", &"mascot_window"))
	assert_eq(SaveGame.mascot(), &"window", "a mascot answer gives the AI its body")


func test_a_jump_answers_every_earlier_fork_with_option_0() -> void:
	CampaignDB.answer_fork(&"fork_dash", &"dash_teleport")   # as an --answer= would, first
	CampaignDB.answer_earlier_forks(&"s1_05_wrong")
	assert_eq(Unlocks.take(&"fork_mascot"), &"cursor")
	assert_eq(SaveGame.mascot(), &"cursor")
	assert_eq(Unlocks.dash_answer(), &"teleport", "--answer= wins over option 0")
	assert_eq(Unlocks.dash_aim_answer(), &"aim")
	assert_eq(Unlocks.answer(&"fork_enemy").id, &"enemy_tank")
	SaveGame.use_snapshot("", true)
	CampaignDB.answer_earlier_forks(&"s1_03_shooting")
	assert_eq(SaveGame.shipped(), [] as Array[StringName], "S3 asks them itself")


func test_shelf_of_stage_1_is_the_unpicked_options() -> void:
	assert_eq(CampaignDB.shelf(1), [] as Array[Change], "nothing answered: nothing shelved")
	for id: StringName in [&"mascot_blob", &"dash_grapple", &"dashdir_aim", &"enemy_tank"]:
		SaveGame.ship(id, GameVersion.PATCH)
	var ids := CampaignDB.shelf(1).map(func(c: Change) -> StringName: return c.id)
	assert_eq(ids, [&"mascot_cursor", &"mascot_window", &"dash_classic", &"dash_teleport", &"dashdir_move",
			&"enemy_bomber", &"enemy_lancer"])
	assert_eq(CampaignDB.shelf(2), [] as Array[Change])


func test_without_session_the_game_reads_no_answer() -> void:
	# The bot's own flags (no --session=) must not reach the game (map Step 10, M43 review).
	var bot_flags := PackedStringArray(["--campaign", "--only=s1_04_level", "--dash=grapple",
			"--answer=fork_enemy=enemy_tank", "--dash-aim=aim", "--answer=fork_dash=dash_teleport", "3i"])
	CampaignDB.active = false
	assert_false(CampaignDB.read_jump_args(bot_flags), "no --session=: no jump")
	assert_false(CampaignDB.active, "the run loop")
	assert_eq(SaveGame.shipped(), [] as Array[StringName], "nothing answered")
	assert_false(CampaignDB.read_jump_args(PackedStringArray(["--dash=none"])))
	assert_eq(SaveGame.shipped(), [] as Array[StringName])
	# The game boot itself reads the real (GUT) command line: no --session= there either.
	var was := CampaignDB._arg_read
	CampaignDB._arg_read = false
	assert_null(CampaignDB.session_for_game(), "no --session=: the run loop")
	CampaignDB._arg_read = was


func test_a_session_jump_ships_its_answers() -> void:
	assert_true(CampaignDB.read_jump_args(PackedStringArray(["--autostart", "--dash=grapple",
			"--session=s1_04_level", "--answer=fork_enemy=enemy_lancer"])))
	assert_true(CampaignDB.active)
	assert_eq(CampaignDB.current().id, &"s1_04_level")
	var shipped := SaveGame.shipped()
	assert_true(&"dash_grapple" in shipped, str(shipped))
	assert_false(&"dash_classic" in shipped, "the alias, not option 0")
	assert_true(&"enemy_lancer" in shipped, str(shipped))
	assert_eq(Unlocks.answer(&"fork_mascot"), ChangeDB.get_fork(&"fork_mascot").changes()[0], "earlier forks: option 0")
	assert_false(CampaignDB.read_jump_args(PackedStringArray(["--session=s9_nope"])), "an unknown session")


func test_one_rule_for_which_answer_wins() -> void:
	var a := CampaignDB.answers_from_args(PackedStringArray(["--dash=grapple", "--answer=fork_dash=dash_teleport"]))
	assert_eq(a, {&"fork_dash": &"dash_teleport"}, "--answer= wins over its alias wherever it stands")
	a = CampaignDB.answers_from_args(PackedStringArray(["--dash=grapple", "--dash=teleport"]))
	assert_eq(a, {&"fork_dash": &"dash_grapple"}, "the first --dash= wins")
	a = CampaignDB.answers_from_args(PackedStringArray(["--dash=grapple", "--dash=none"]))
	assert_eq(a, {&"fork_dash": &"dash_grapple"})
	a = CampaignDB.answers_from_args(PackedStringArray(["--dash=none", "--dash=grapple"]))
	assert_eq(a, {}, "a first --dash=none answers nothing, and decides")
	a = CampaignDB.answers_from_args(PackedStringArray(["--dash-aim=move", "--dash-aim=aim",
			"--answer=fork_enemy=enemy_tank", "--answer=fork_enemy=enemy_bomber"]))
	assert_eq(a, {&"fork_dash_aim": &"dashdir_move", &"fork_enemy": &"enemy_tank"})


func test_intro_and_cue_lines_cannot_lean_on_the_outcome_or_an_event_in_any_part() -> void:
	for intro: String in ["won&first_try happy: x", "hit_none&won happy: x", "!died happy: x",
			"first_try&!ended happy: x"]:
		var s := _session(&"x")
		s.intro = PackedStringArray([intro])
		assert_string_contains(str(s.problems()), "intro line cannot depend on the outcome", intro)
	for intro: String in ["dash:classic&event:wrong_variable happy: x", "!event:wrong_variable happy: x"]:
		var s := _session(&"x")
		s.intro = PackedStringArray([intro])
		assert_string_contains(str(s.problems()), "intro line cannot depend on an event", intro)
	for cue: String in ["at 5: say ended&dash:grapple happy: x", "at 5: say !won happy: x"]:
		var s := _session(&"x")
		s.cues = PackedStringArray([cue])
		assert_string_contains(str(s.problems()), "cannot depend on the outcome", cue)
	var e := _session(&"x")
	e.cues = PackedStringArray(["at 30: say dash:grapple&event:wrong_variable thinking: x"])
	assert_string_contains(str(e.problems()), "a cue line cannot depend on an event")
	var ok := _session(&"x")
	ok.intro = PackedStringArray(["first_try&!answer:dash_grapple happy: x", "retry&dash:classic worried: y"])
	ok.cues = PackedStringArray(["at 5: say !answer:dash_grapple&hit_none happy: x"])
	ok.debrief = PackedStringArray(["won&first_try happy: x", "!died happy: y", "won&event:nope_event happy: z"])
	assert_eq(ok.problems(), ["session x: unknown event nope_event"] as Array[String],
			"debrief lines may; an event is checked per part")


# --- Lines ------------------------------------------------------------------------------

func test_any_conditions_join_and_bang_negates() -> void:
	var l := Line.parse("died&attempts:2 guilty: Again?")
	assert_eq([l.problem, l.when, l.expression, l.text], ["", &"died&attempts:2", &"guilty", "Again?"])
	assert_true(l.passes({outcome = &"died", attempt = 2}))
	assert_true(l.passes({outcome = &"died", attempt = 3}))
	assert_false(l.passes({outcome = &"died", attempt = 1}))
	assert_false(l.passes({outcome = &"won", attempt = 2}))
	var first := Line.parse("won&first_try proud: First go!")
	assert_eq(first.problem, "")
	assert_true(first.passes({outcome = &"won", attempt = 1}))
	assert_false(first.passes({outcome = &"won", attempt = 2}))
	var neg := Line.parse("!answer:dash_grapple happy: x")
	assert_eq(neg.problem, "")
	assert_true(neg.passes({shipped = [&"dash_classic"]}))
	assert_false(neg.passes({shipped = [&"dash_grapple"]}))
	assert_false(neg.passes({}), "a missing key fails, negated or not")
	var mixed := Line.parse("event:wrong_variable&hit_none happy: x")
	assert_eq(mixed.problem, "")
	assert_true(mixed.passes({events = ["wrong_variable"], hits = 0}))


func test_attempts_and_died_in_are_one_word() -> void:
	assert_eq(Line.parse("attempts:2 worried: x").problem, "")
	assert_string_contains(Line.parse("attempts:0 worried: x").problem, "attempts needs a whole number")
	assert_string_contains(Line.parse("attempts:x worried: x").problem, "attempts needs a whole number")
	var d := Line.parse("died_in:s1_05_wrong thinking: Remember the gravity?")
	assert_eq([d.problem, d.when], ["", &"died_in:s1_05_wrong"])
	assert_true(d.passes({attempts_by_session = {"s1_05_wrong": 1}}))
	assert_false(d.passes({attempts_by_session = {"s1_04_level": 2}}))
	assert_false(d.passes({}))
	var s := _session(&"a")
	s.debrief = PackedStringArray(["died_in:s9_nope guilty: x", "died_in:a guilty: y"])
	var text := "\n".join(CampaignDB.problems(_campaign([s])))
	assert_string_contains(text, "died_in names no session s9_nope")
	assert_false(Array(text.split("\n")).any(func(p: String) -> bool: return p.ends_with("no session a")),
			"its own id is a session")
	# line_context carries the save's attempts.
	SaveGame.count_attempt(&"s1_05_wrong")
	var ctx := CampaignDB.line_context(CampaignDB.get_session(&"s1_06_playground"))
	assert_true(d.passes(ctx))


func test_the_empty_condition_holds_and_bang_needs_its_key() -> void:
	assert_true(Line.condition_holds("", {}))
	assert_eq(Line.condition_problem(""), "")
	for cond: String in ["!won", "!died", "!ended", "!hit_none", "!first_try", "!retry", "!attempts:2",
			"!answer:dash_grapple", "!mascot:blob", "!event:x", "!dash:classic", "!dash_aim:aim",
			"!died_in:s1_03_shooting"]:
		assert_eq(Line.condition_problem(cond), "", cond)
		assert_false(Line.condition_holds(cond, {}), "%s fails without its key" % cond)
	assert_string_contains(Line.condition_problem("!nope"), "unknown condition")
	assert_eq(Line.condition_parts("!answer:a&won"), ["answer:a", "won"] as Array[String])


# --- Cues -------------------------------------------------------------------------------

func test_the_cue_grammar() -> void:
	var c := Cue.parse("answer:path_auto at 12: add levelups")
	assert_eq([c.problem, c.cond, c.when, c.value, c.action, c.target],
			["", "answer:path_auto", &"at", 12.0, &"add", &"levelups"])
	c = Cue.parse("!answer:path_auto&first_try kills 5: say happy: x")
	assert_eq([c.problem, c.cond, c.when, c.value, c.line.text], ["", "!answer:path_auto&first_try", &"kills", 5.0, "x"])
	c = Cue.parse("room 2 at 5: say thinking: Room two.")
	assert_eq([c.problem, c.when, c.value, c.at_seconds], ["", &"room", 2.0, 5.0])
	c = Cue.parse("room 3: say x")
	assert_eq([c.problem, c.value, c.at_seconds], ["", 3.0, -1.0])
	c = Cue.parse("boss_hp 50: say worried: Half!")
	assert_eq([c.problem, c.when, c.value], ["", &"boss_hp", 50.0])
	c = Cue.parse("level 3: say x")
	assert_eq([c.problem, c.when, c.value], ["", &"level", 3.0])
	c = Cue.parse("picked 1: say x")
	assert_eq([c.problem, c.when, c.value], ["", &"picked", 1.0])
	c = Cue.parse("at 25 [laser]: say happy: A laser!")
	assert_eq([c.problem, c.when, c.value, c.tag, c.line.text], ["", &"at", 25.0, &"laser", "A laser!"])
	c = Cue.parse("at 3: path auto")
	assert_eq([c.problem, c.action, c.target], ["", &"path", &"auto"])
	c = Cue.parse("at 3: give shotgun 2")
	assert_eq([c.problem, c.target, c.rank], ["", &"shotgun", 2])
	c = Cue.parse("at 3: drop ammo 4")
	assert_eq([c.problem, c.target, c.count], ["", &"ammo", 4])
	c = Cue.parse("at 3: look fork:fork_look@2 10")
	assert_eq([c.problem, c.target, c.seconds], ["", &"fork:fork_look@2", 10.0])
	c = Cue.parse("at 3: boss fork:fork_boss dummy")
	assert_eq([c.problem, c.target, c.dummy], ["", &"fork:fork_boss", true])
	for bad: String in ["room 0: say x", "room 2 at: say x", "boss_hp 101: say x", "level 0: say x",
			"at 3: path nowhere", "at 3: give shotgun 5", "at 3: drop", "at 3: look clean 0",
			"at 3: boss x y", "attempts:0 at 3: say x", "at 3 []: say x", "soon: say x"]:
		assert_ne(Cue.parse(bad).problem, "", bad)
	assert_false(Cue.parse("room 2 at 5: say x").due({"room": 2, "room_clock": 4.0}))
	assert_true(Cue.parse("room 2 at 5: say x").due({"room": 2, "room_clock": 5.0}))
	assert_false(Cue.parse("level 3: say x").due({"clock": 99.0}), "no ctx key in M43: never due")


## Every Stage 1 cue parses as the old head reading did (the first ':' ends it).
func test_every_stage_1_cue_parses_as_before() -> void:
	var n := 0
	for s in CampaignDB.campaign.sessions:
		for src in s.cues:
			var c := Cue.parse(src)
			var t := src.strip_edges()
			var colon := t.find(":")
			var head := t.left(colon).strip_edges().split(" ", false)
			var body := t.substr(colon + 1).strip_edges().split(" ", false)
			assert_eq([c.problem, c.cond, c.tag, c.at_seconds], ["", "", &"", -1.0], src)
			assert_eq(c.when, StringName(head[0]), src)
			assert_eq(c.value, head[1].to_float() if head.size() > 1 else 0.0, src)
			assert_eq(c.action, StringName(body[0]), src)
			n += 1
	assert_gt(n, 10)


func test_a_failing_cue_condition_drops_the_cue_at_start() -> void:
	var s := _session(&"x")
	s.cues = PackedStringArray(["answer:dash_grapple at 1: say happy: grapple", "!answer:dash_grapple at 2: say not",
			"at 3: say always"])
	var runner := SessionRunner.new()
	runner.session = s
	add_child_autofree(runner)
	assert_eq(runner._cues.map(func(c: Cue) -> String: return c.line.text), ["not", "always"])
	assert_eq(runner._fired.size(), 2)
	assert_eq(s.cue_list().size(), 3, "the shared parse is untouched")
	SaveGame.ship(&"dash_grapple", GameVersion.PATCH)
	var again := SessionRunner.new()
	again.session = s
	add_child_autofree(again)
	assert_eq(again._cues.map(func(c: Cue) -> String: return c.line.text), ["grapple", "always"])


func test_path_cues_need_a_tryout_and_new_things_are_not_built_yet() -> void:
	var s := _session(&"x")
	s.cues = PackedStringArray(["at 3: path auto"])
	assert_string_contains(str(s.problems()), "path cues need a tryout session")
	s.tryout = true
	assert_false("tryout" in str(s.problems()))
	s.cues = PackedStringArray(["at 3: path auto", "at 25 [laser]: say happy: x", "level 2: say x",
			"room 1: say x", "boss_hp 50: say x"])
	s._parsed = false   # the parse is cached per resource
	assert_string_contains(str(s.problems()), "room needs a stage set")
	assert_string_contains(str(s.problems()), "boss_hp needs a boss")
	s.stages = &"gauntlet"
	s.goal = SessionDef.STAGES
	s.checkpoint = true
	s.weapons = [&"pistol"] as Array[StringName]
	s.spawn_weights = {&"chaser": 2.0}
	s.path = &"auto"
	s.hp_floor = 1
	var text := "\n".join(CampaignDB.problems(_campaign([s])))
	for expected in ["cue 'at 3: path auto': path is not built yet", "[tag] is not built yet",
			"level is not built yet", "room is not built yet", "checkpoint is not built yet",
			"stages are not built yet", "path is not built yet (M45a)",
			"spawn_weights are not built yet"]:
		assert_string_contains(text, expected)
	assert_false("hp_floor" in text, "the floor is built")
	assert_false("weapons" in text, "weapons are built (M44)")
	s.goal = SessionDef.BOSS
	s.stages = &""
	assert_string_contains(str(s.problems()), "goal boss needs a boss and checkpoint")
	s.spawn_weights = {&"dragon": 1.0, &"chaser": 0.0}
	assert_string_contains(str(s.problems()), "unknown enemy dragon")
	assert_string_contains(str(s.problems()), "chaser must be > 0")
