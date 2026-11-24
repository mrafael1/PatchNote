extends GutTest
## M42.2 (owner, after M42.1: "dash option after first prompt: mouse or keyboard
## directions"): right after the dash pick, S3's debrief asks where it goes
## (fork_dash_aim): where you aim (PlayerInput.aim_dir: the mouse, or the right stick) or
## where you move. Dasher.aims plays it (Unlocks.dash_aims(); false outside a session).

const Fx := preload("res://tests/gut/fixtures.gd")
const T := 48.0
## Block Rect2(20, 19, 2, 2) of arena_0: its left face is at x = 20 tiles, rows 19-20.
const BLOCK_LEFT := 20.0 * T
const BEFORE_BLOCK := Vector2(15, 20)
## Open space on the bottom lane (as in test_dash_styles).
const OPEN := Vector2(34, 20)
## M43: answer: conditions may name these before their changes exist (the path changes
## land with fork_path in M47, which empties this list); a typo still fails.
const PLANNED_CHANGES: Array[StringName] = [&"path_arsenal", &"path_auto", &"path_survival"]

var game: Main
var player: CharacterBody2D
var dasher: Dasher
var input: Fx.ScriptedInput


func after_each() -> void:
	SaveGame.go_inert()
	CampaignDB.active = false
	RunState.session = null
	RunState.session_added.clear()
	RunState.invincible = false
	RunState.reset(0)
	RunState.world = null


## S4 with `style` and `aim` shipped (&"" = that fork unanswered), the spawner and cues off.
func _game(style: StringName, aim: StringName) -> Main:
	SaveGame.go_inert()
	if style != &"":
		SaveGame.ship(StringName("dash_%s" % style), GameVersion.PATCH)
	if aim != &"":
		SaveGame.ship(StringName("dashdir_%s" % aim), GameVersion.PATCH)
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(&"s1_04_level"))
	Main.next_seed = 7
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	await wait_physics_frames(2)
	game.session_runner.set_physics_process(false)
	player = game.player
	dasher = player.dasher
	input = Fx.ScriptedInput.new()
	player.set_input(input)
	return game


func _place(tile: Vector2) -> void:
	player.global_position = tile * T
	player.velocity = Vector2.ZERO


## Moves along move_dir and aims along aim_dir, presses the dash on the same frame, then
## lets go of the stick.
func _press(move_dir: Vector2, aim_dir: Vector2) -> void:
	input.move = move_dir
	input.aim_dir = aim_dir
	input.tap_dash()
	await wait_physics_frames(1)
	input.move = Vector2.ZERO


func _free_game() -> void:
	game.queue_free()
	await wait_physics_frames(2)


func _debrief() -> DebriefScreen:
	var d := DebriefScreen.new()
	add_child_autofree(d)
	d.input_delay = 0.0
	return d


# --- The question ---------------------------------------------------------------------

func test_s3_asks_the_direction_right_after_the_dash() -> void:
	SaveGame.go_inert()
	var s3 := CampaignDB.get_session(&"s1_03_shooting")
	assert_eq(s3.asked_forks(), [&"fork_mascot", &"fork_dash", &"fork_dash_aim"] as Array[StringName])
	var f := ChangeDB.get_fork(&"fork_dash_aim")
	assert_not_null(f)
	assert_true(f.campaign)
	assert_eq(f.requires_forks, [&"fork_dash"] as Array[StringName])
	assert_eq(f.changes().map(func(c: Change) -> StringName: return c.take.id), Change.DASH_AIMS, "aim first")
	var d := _debrief()
	d.open(s3, &"stopped", 0)
	d.finish_lines()
	assert_eq(d.fork().id, &"fork_mascot")
	assert_true(d.pick(0))
	d.finish_lines()
	assert_eq(d.fork().id, &"fork_dash")
	assert_true(d.pick(2))
	d.finish_lines()
	assert_eq(d.phase, DebriefScreen.FORK)
	assert_eq(d.fork().id, &"fork_dash_aim")
	assert_eq(d.said[-1], "And should it go where you aim, or where you're moving?")
	assert_eq(d._cards.get_child_count(), 2, "two cards")
	assert_eq(d.fork_options()[0].id, &"dashdir_aim")
	assert_eq(d.choices(), [] as Array[String])
	assert_true(d.pick(1))
	d.finish_lines()
	assert_eq(d.said[-1], "Where your feet go. Simple.")
	assert_eq(d.choices(), [DebriefScreen.NEXT])
	assert_eq(d.more_picks().map(func(c: Change) -> StringName: return c.id),
			[&"dash_teleport", &"dashdir_move"])
	var notes := DebriefScreen.notes_text(s3, d.picked, d.more_picks())
	assert_eq(notes.count("\n  • "), s3.notes.size() + 3, "three pick bullets")
	assert_string_contains(notes, "The dash goes where you move")
	var after := CampaignDB.version_after(s3).label()
	CampaignDB.complete(s3, d.picked, d.more_picks())
	assert_true(SaveGame.has_shipped(&"dashdir_move"))
	assert_eq(SaveGame.version().label(), after, "S3's single bump, none per pick")
	d.close()


func test_the_answer_reads_the_save_and_only_counts_in_a_session() -> void:
	SaveGame.go_inert()
	RunState.session = null
	assert_eq(Unlocks.dash_aim_answer(), &"move", "unanswered: move")
	SaveGame.ship(&"dashdir_aim", GameVersion.PATCH)
	assert_eq(Unlocks.dash_aim_answer(), &"aim")
	assert_false(Unlocks.dash_aims(), "outside a session: never")
	RunState.session = CampaignDB.get_session(&"s1_04_level")
	assert_true(Unlocks.dash_aims())


func test_answer_dash_aim_checks_the_direction() -> void:
	SaveGame.go_inert()
	assert_false(CampaignDB.answer_dash_aim(&"nope"))
	assert_false(SaveGame.has_shipped(&"dashdir_aim"))
	assert_false(SaveGame.has_shipped(&"dashdir_move"))
	assert_true(CampaignDB.answer_dash_aim(&"aim"))
	assert_true(SaveGame.has_shipped(&"dashdir_aim"))
	assert_true(CampaignDB.answer_dash_aim(&"move"), "answered already: ships nothing more")
	assert_false(SaveGame.has_shipped(&"dashdir_move"))


func test_change_db_checks_a_dash_aim_take() -> void:
	for c in ChangeDB.get_fork(&"fork_dash_aim").changes():
		assert_eq(c.kind, &"dash_aim")
		assert_eq(ChangeDB.problems(c), [] as Array[String])
	var bad := Change.new()
	bad.id = &"dashdir_bad"
	bad.kind = &"dash_aim"
	assert_eq(ChangeDB.problems(bad).size(), 1, "a dash-aim change needs a take naming a direction")
	var wrong := MockupTake.new()
	wrong.id = &"sideways"
	bad.take = wrong
	assert_eq(ChangeDB.problems(bad).size(), 1)
	for c in ChangeDB.all:
		assert_eq(ChangeDB.problems(c), [] as Array[String], String(c.id))


func test_telemetry_records_the_direction() -> void:
	SaveGame.go_inert()
	var s3 := CampaignDB.get_session(&"s1_03_shooting")
	var more: Array[Change] = [ChangeDB.get_change(&"dash_grapple"), ChangeDB.get_change(&"dashdir_aim")]
	var rec := CampaignDB.telemetry_record(s3, {}, &"stopped", 0, &"next", "", ChangeDB.get_change(&"mascot_blob"),
			[] as Array[String], [], [], more)
	assert_eq(rec.dash_aim, "aim")
	assert_eq(rec.dash, "grapple")
	assert_eq((rec.forks as Array).size(), 3)
	assert_eq(rec.forks[0].id, "fork_mascot")
	assert_eq(rec.forks[2], {"id": "fork_dash_aim", "pick": "dashdir_aim", "shelved": ["dashdir_move"]})
	assert_eq(rec.schema, Telemetry.CAMPAIGN_SCHEMA)
	var plain := CampaignDB.telemetry_record(s3, {}, &"stopped", 0, &"next")
	assert_eq(plain.dash_aim, "move", "unanswered: move")


# --- How it plays ---------------------------------------------------------------------

func test_a_classic_aim_dash_goes_where_you_aim() -> void:
	await _game(&"classic", &"aim")
	assert_true(dasher.aims)
	_place(OPEN)
	await wait_physics_frames(1)
	var start := player.global_position
	await _press(Vector2.RIGHT, Vector2.LEFT)
	await wait_physics_frames(30)
	assert_between(start.x - player.global_position.x, 3.3 * T, 4.6 * T, "along the aim (left)")
	assert_almost_eq(player.global_position.y, start.y, 2.0)
	# No aim (only a scripted provider): the move direction.
	await wait_physics_frames(30)
	_place(OPEN)
	start = player.global_position
	await _press(Vector2.RIGHT, Vector2.ZERO)
	await wait_physics_frames(30)
	assert_between(player.global_position.x - start.x, 3.3 * T, 4.6 * T, "a zero aim falls back to move")


func test_a_classic_move_dash_ignores_the_aim() -> void:
	await _game(&"classic", &"move")
	assert_false(dasher.aims)
	_place(OPEN)
	await wait_physics_frames(1)
	var start := player.global_position
	await _press(Vector2.RIGHT, Vector2.LEFT)
	await wait_physics_frames(30)
	assert_between(player.global_position.x - start.x, 3.3 * T, 4.6 * T, "along the move (right)")


## A spot where a hook thrown along dir catches nothing.
func _miss_spot(dir: Vector2) -> Vector2:
	for row in range(2, 20):
		for col in range(2, 64):
			var p := Vector2(col + 0.5, row + 0.5) * T
			player.global_position = p
			if Dasher.grapple_target(player, dir).is_empty() \
					and not Dasher.grapple_target(player, Vector2.UP).is_empty():
				return p
	return Vector2.INF


func test_an_aimed_hook_follows_the_aim() -> void:
	await _game(&"grapple", &"aim")
	assert_true(dasher.aims)
	var spot := _miss_spot(Vector2.RIGHT)
	assert_ne(spot, Vector2.INF, "a spot with open air to the right and a wall above")
	watch_signals(EventBus)
	player.global_position = spot
	player.velocity = Vector2.ZERO
	await _press(Vector2.RIGHT, Vector2.UP)
	assert_signal_emit_count(EventBus, "player_hooked", 1, "the hook goes up, at the wall")
	assert_signal_not_emitted(EventBus, "player_hook_missed")
	await wait_physics_frames(90)
	# The same throw along the move direction misses.
	dasher.aims = false
	player.global_position = spot
	player.velocity = Vector2.ZERO
	await _press(Vector2.RIGHT, Vector2.UP)
	assert_signal_emit_count(EventBus, "player_hook_missed", 1, "move: the hook goes right, at nothing")


func test_an_aimed_teleport_lands_along_the_aim() -> void:
	await _game(&"teleport", &"aim")
	_place(OPEN)
	await wait_physics_frames(1)
	var from := player.global_position
	var expected := Dasher.teleport_target(player, Vector2.LEFT)
	assert_lt(expected.x, from.x - T)
	await _press(Vector2.RIGHT, Vector2.LEFT)
	assert_almost_eq(player.global_position.x, expected.x, 6.0, "left, along the aim")
	assert_almost_eq(player.global_position.y, from.y, 2.0)


func test_under_inverted_controls_the_aim_is_not_turned() -> void:
	for aim: StringName in Change.DASH_AIMS:
		await _game(&"classic", aim)
		RunState.add_ai(RuleDB.get_edit(&"edit_inverted"), &"edit")
		assert_eq(fposmod(RunState.rules.input_rotation_deg, 360.0), 180.0)
		_place(OPEN)
		await wait_physics_frames(1)
		var start := player.global_position
		# The keys say left: turned, the player moves right. The aim says left.
		await _press(Vector2.LEFT, Vector2.LEFT)
		await wait_physics_frames(30)
		var dx := player.global_position.x - start.x
		if aim == &"aim":
			assert_between(-dx, 3.0 * T, 4.6 * T, "aim: along the unturned aim (left)")
		else:
			assert_between(dx, 3.0 * T, 4.6 * T, "move: along the turned keys (right)")
		await _free_game()


func test_an_old_save_past_s3_stays_on_move_and_is_never_asked() -> void:
	SaveGame.go_inert()
	SaveGame.ship(&"mascot_blob", GameVersion.PATCH)
	SaveGame.set_mascot(&"blob")
	SaveGame.ship(&"dash_grapple", GameVersion.PATCH)
	for id: StringName in [&"s1_04_level", &"s1_05_wrong", &"s1_06_playground"]:
		var d := _debrief()
		d.open(CampaignDB.get_session(id), &"win", 0)
		d.finish_lines()
		assert_true(d.fork() == null or d.fork().id != &"fork_dash_aim", "%s never asks where it goes" % id)
		d.close()
	await _game(&"grapple", &"")
	assert_false(ChangeDB.get_fork(&"fork_dash_aim").is_answered())
	assert_eq(dasher.style, &"grapple")
	assert_false(dasher.aims, "an unanswered save plays move")


func test_outside_a_session_the_dash_never_aims() -> void:
	SaveGame.go_inert()
	SaveGame.ship(&"dash_teleport", GameVersion.PATCH)
	SaveGame.ship(&"dashdir_aim", GameVersion.PATCH)
	CampaignDB.active = false
	RunState.session = null
	Main.next_seed = 7
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	assert_null(RunState.session)
	assert_eq(game.player.dasher.style, &"classic")
	assert_false(game.player.dasher.aims)


# --- The lines ------------------------------------------------------------------------

func test_every_line_parses_and_every_answer_condition_names_a_change() -> void:
	assert_ne(Line.parse("dash_aim:nope: x").problem, "")
	assert_string_contains(Line.parse("dash_aim:nope: x").problem, "unknown dash direction")
	assert_eq(Line.parse("dash_aim:aim: x").problem, "")
	var lines: Array[Line] = []
	for s in CampaignDB.campaign.sessions:
		lines.append_array(s.intro_lines())
		lines.append_array(s.debrief_lines())
		for c in s.cue_list():
			if c.line != null:
				lines.append(c.line)
	for r in CampaignDB.reactions:
		lines.append_array(r.line_list())
	assert_gt(lines.size(), 20)
	# M43: lines, reaction whens and cue conditions, each "&" part with "!" stripped.
	var conds: Array[String] = []
	for l in lines:
		assert_eq(l.problem, "", l.text)
		conds.append(String(l.when))
	for r in CampaignDB.reactions:
		conds.append(r.when)
	for s in CampaignDB.campaign.sessions:
		for c in s.cue_list():
			conds.append(c.cond)
	var named := 0
	for cond in conds:
		for w in Line.condition_parts(cond):
			if w.begins_with("answer:"):
				named += 1
				var id := StringName(w.trim_prefix("answer:"))
				assert_true(ChangeDB.get_change(id) != null or id in PLANNED_CHANGES, w)
	assert_gt(named, 0, "the audit's !answer:path_auto gates are checked too")
	assert_false(&"path_atuo" in PLANNED_CHANGES)


func test_the_s4_intro_says_one_direction_line() -> void:
	var s4 := CampaignDB.get_session(&"s1_04_level")
	for answer: StringName in [&"", &"aim", &"move"]:
		for style: StringName in Change.DASHES:
			SaveGame.go_inert()
			SaveGame.set_mascot(&"blob")
			SaveGame.ship(StringName("dash_%s" % style), GameVersion.PATCH)
			if answer != &"":
				SaveGame.ship(StringName("dashdir_%s" % answer), GameVersion.PATCH)
			var ctx := CampaignDB.line_context(s4)
			var texts := Line.passing(s4.intro_lines(), ctx).map(func(l: Line) -> String: return l.text)
			var said_aim := texts.any(func(t: String) -> bool: return t.ends_with("where you aim."))
			var said_move := texts.any(func(t: String) -> bool: return t.ends_with("where you move."))
			assert_ne(said_aim, said_move, "exactly one direction (%s %s)" % [style, answer])
			assert_eq(said_aim, answer == &"aim", "aim only for aim (%s %s)" % [style, answer])
			assert_eq(texts.size(), 3, "mascot, walls, then the dash and its direction in one line")


## The & join (M42.2 review): both halves must hold. M43 (PLAN v9 1.1): any conditions join.
func test_dash_conditions_join_with_and() -> void:
	var l := Line.parse("dash:grapple&dash_aim:aim happy: x")
	assert_eq([l.problem, l.expression, l.text], ["", &"happy", "x"])
	assert_true(l.passes({dash = &"grapple", dash_aim = &"aim"}))
	assert_false(l.passes({dash = &"grapple", dash_aim = &"move"}))
	assert_false(l.passes({dash = &"classic", dash_aim = &"aim"}))
	assert_false(l.passes({dash = &"grapple"}), "a missing key fails")
	assert_string_contains(Line.parse("dash:grapple&dash_aim:nope: x").problem, "unknown dash direction")
	assert_string_contains(Line.parse("dash:nope&dash_aim:aim: x").problem, "unknown dash")
	var any := Line.parse("won&dash:classic: x")
	assert_eq(any.problem, "", "M43: plain conditions join too")
	assert_true(any.passes({outcome = &"won", dash = &"classic"}))
	assert_false(any.passes({outcome = &"died", dash = &"classic"}))
	var ev := Line.parse("dash:classic&event:x: x")
	assert_eq(ev.problem, "")
	assert_true(ev.passes({dash = &"classic", events = ["x"]}))
	assert_false(ev.passes({dash = &"classic", events = []}))


## M42.2 review: the S4 direction line overran the 12 s bouncy-walls cue (whose warning,
## priority 3, cuts a line and drops it). The mascot holds each line for its typing plus
## its read time (Reactions.speak_seconds), one after another, so every intro, for every
## face, dash style and direction, must be over before the first cue that speaks over
## it (an edit's warning or an event), with a margin for frames.
func test_every_intro_ends_before_its_first_edit_or_event() -> void:
	const MARGIN := 0.25
	var checked := 0
	for s in CampaignDB.campaign.sessions:
		var first := INF
		for c in s.cue_list():
			if c.when == &"at" and c.action in [&"edit", &"event"]:
				first = minf(first, c.value)
		if first == INF:
			continue
		var worst := 0.0
		var worst_combo := ""
		for style: StringName in Change.DASHES:
			for answer: StringName in Change.DASH_AIMS:
				for mascot: StringName in Change.MASCOTS:
					SaveGame.go_inert()
					SaveGame.ship(StringName("dash_%s" % style), GameVersion.PATCH)
					SaveGame.ship(StringName("dashdir_%s" % answer), GameVersion.PATCH)
					SaveGame.set_mascot(mascot)
					var t := 0.0
					for l in Line.passing(s.intro_lines(), CampaignDB.line_context(s)):
						t += Reactions.speak_seconds(l.text)
					if t > worst:
						worst = t
						worst_combo = "%s %s %s" % [mascot, style, answer]
		checked += 1
		assert_lt(worst + MARGIN, first, "%s: the intro takes %.2f s (%s), its first cue is at %.1f s"
				% [s.id, worst, worst_combo, first])
	assert_gt(checked, 0, "S4 at least has an edit cue")
