extends GutTest
## M48b (PLAN 1.7.1, 3.2 S9 v9.2): S9 "Fresh paint", the transformation. The cue grammar
## and its refusals, S9 as data, the specimen (still and harmless until `release`), the
## spawner's quiet 9 s, the per-id reveal on every hook, SkinMorph's steps (<= 3 flashes/s,
## a crossfade under reduce flashing), the three bugs (each restores the exact draw state),
## `skin enemies` with its lines, the end state (every skinned node revealed and at
## Skins.version), `--skins=off`, and S9 per path (the laser at 80 s, nova's line on Auto).
## Every game is jumped to on an inert save, invincible; the clock is moved, never waited
## on, and nothing waits while the debrief is open.

const TEST_LOG := "user://save_s9_paint_test/runs.jsonl"
const S9 := &"s2_03_paint"
const PATHS: Array[StringName] = [&"arsenal", &"auto", &"survival"]

var game: Main


func before_each() -> void:
	Telemetry.log_path = TEST_LOG
	Skins.disabled = false
	Skins.use(null)


func after_each() -> void:
	await wait_physics_frames(2)   # deferred spawns land before the game is freed
	assert_false(FileAccess.file_exists(TEST_LOG), "no telemetry written")
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.invincible = false
	CampaignDB.active = false
	SaveGame.go_inert()
	Skins.disabled = false
	Skins.use(null)
	RunState.reset(0)
	RunState.world = null


func _s9(p: StringName = &"arsenal", invincible := true) -> Main:
	SaveGame.go_inert()
	assert_true(CampaignDB.answer_fork(&"fork_path", StringName("path_%s" % p)))
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(S9))
	var g: Main = load("res://main.tscn").instantiate()
	add_child_autofree(g)
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	game = g
	RunState.invincible = invincible
	return g


func _at(seconds: float) -> void:
	game.run_loop.goal_clock = seconds - 0.01
	await wait_physics_frames(3)


func _specimen() -> Node:
	var all := get_tree().get_nodes_in_group(&"specimen")
	return all[0] if not all.is_empty() else null


func _chasers() -> Array:
	return get_tree().get_nodes_in_group(&"enemy").filter(func(e: Node) -> bool:
		return Skins.id_for(e.get_node(^"Visual")) == &"chaser")


func _session(cues: Array, skin := &"pixel", reveal := &"manual") -> SessionDef:
	var s := SessionDef.new()
	s.id = &"m48b_probe"
	s.basics = [&"movement", &"enemies"]
	s.enemies = [&"chaser"]
	s.skin = skin
	s.look_reveal = reveal
	s.cues = PackedStringArray(cues)
	return s


# --- Grammar and data ------------------------------------------------------------------

func test_the_session_refuses_bad_transformation_data() -> void:
	assert_eq(_session(["at 1: spawn chaser 1 specimen", "at 3: skin chaser morph", "at 9: release"]).problems(),
			[] as Array[String])
	assert_eq(_session(["at 9: release", "at 1: spawn chaser 1 specimen"]).problems(), [] as Array[String],
			"M48b review: in time order, whatever the list order")
	assert_eq(_session(["answer:path_auto at 1: spawn chaser 1 specimen", "answer:path_auto at 9: release"]).problems(),
			[] as Array[String], "a release with its specimen's own condition")
	assert_string_contains("
".join(_session(["at 9: release", "at 9: spawn chaser 1 specimen"]).problems()),
			"never released", "the same second: the release must come after it in the list")
	var cases := {
		"skin cues need a skin": _session(["at 3: skin chaser"], &"", &"all"),
		"look_reveal manual": _session(["at 3: skin chaser"], &"pixel", &"all"),
		"needs a skin": _session([], &"", &"manual"),
		"unknown skin": _session([], &"neon"),
		"release needs an earlier": _session(["at 9: release", "at 10: spawn chaser 1 specimen"]),
		"never released": _session(["at 1: spawn chaser 1 specimen"]),
		"only a walker": _session(["at 1: spawn shooter 1 specimen", "at 9: release"]),
		# M48b review: times and conditions, not list positions.
		"specimen': a specimen is never released": _session(["at 1: spawn chaser 1 specimen", "at 0.5: release"]),
		"narrower": _session(["at 1: spawn chaser 1 specimen", "answer:path_auto at 9: release"]),
		"release must be an 'at' cue": _session(["at 1: spawn chaser 1 specimen", "kills 3: release", "at 9: release"]),
	}
	for want: String in cases:
		assert_string_contains("\n".join((cases[want] as SessionDef).problems()), want)
	var s := _session([])
	s.reveal_lines = PackedStringArray(["happy: Another one!"])
	assert_string_contains("\n".join(s.problems()), "reveal_lines need a 'skin enemies' cue")
	s.spawn_after = -1.0
	assert_string_contains("\n".join(s.problems()), "spawn_after must be >= 0")
	assert_eq(Cue.parse("at 3: skin bug flip 3").problem, "", "3 s is the longest bug")
	assert_ne(Cue.parse("at 3: skin bug flip 3.5").problem, "")


func test_s9_is_data_and_matches_the_plan() -> void:
	var s := CampaignDB.get_session(S9)
	assert_eq(s.problems(), [] as Array[String])
	assert_eq(CampaignDB.problems(), [] as Array[String])
	assert_eq(CampaignDB.index_of(S9), 9, "after S8, the last playable session")
	assert_eq([s.stage, s.path, s.goal, s.goal_value, s.skin, s.look_reveal, s.spawn_after, s.bump, s.fork, s.look],
			[2, &"fork:fork_path", SessionDef.SURVIVE, 150.0, &"pixel", &"manual", 9.0, &"patch", &"", ""])
	assert_eq(s.weapons, [&"pistol", &"shotgun", &"laser"] as Array[StringName])
	assert_eq(s.notes, PackedStringArray(["A new look: Pixel", "The laser"]))
	assert_eq(s.basics, CampaignDB.get_session(&"s2_02_day_one").basics)
	assert_true(s.goal_by_path.is_empty(), "survive 150 on every path")
	assert_eq(s.reveal_lines.size(), 4)
	var want := {"at 1: spawn chaser 1 specimen": 1.0, "at 3: skin chaser morph": 3.0, "at 9: release": 9.0,
			"at 14: skin player morph": 14.0, "at 20: skin shots": 20.0, "at 20: skin enemies": 20.0,
			"at 28: skin bug swap 3": 28.0, "at 40: skin arena morph": 40.0, "at 44: skin bug tiles 2.5": 44.0,
			"at 55: skin ui": 55.0, "at 62: skin bug flip 2": 62.0, "at 70: skin mascot": 70.0,
			"at 72: skin all": 72.0, "at 80: give laser": 80.0}
	for src: String in want:
		var hit := s.cue_list().filter(func(c: Cue) -> bool: return c.source == src)
		assert_eq(hit.size(), 1, src)
	# Each bug has its fix line half a second later.
	for pair: Array in [[28.0, "Why are they all you?"], [44.0, "Too much brick"], [62.0, "upside down"]]:
		var said := s.cue_list().filter(func(c: Cue) -> bool:
			return c.action == &"say" and c.line.text.contains(pair[1]))
		assert_eq(said.size(), 1, pair[1])
		assert_eq((said[0] as Cue).value, float(pair[0]) + 0.5)


# --- The specimen and the quiet start --------------------------------------------------

func test_the_specimen_stands_still_and_is_harmless_until_release() -> void:
	await _s9(&"arsenal", false)
	await _at(1.0)
	var sp := _specimen()
	assert_not_null(sp, "one specimen at 1 s")
	assert_true(sp.get(&"specimen"))
	assert_lt(sp.global_position.distance_to(game.arena.player_start), 6.0 * Tuning.TILE, "in view, near the start")
	var where: Vector2 = sp.global_position
	var hp := Component.find(sp, Health) as Health
	var hp_before := hp.hp()
	assert_false(hp.take(DamageInfo.make(5.0, &"shot", &"player", where)), "takes no damage")
	assert_eq(hp.hp(), hp_before)
	var ph := Component.find(game.player, Health) as Health
	var player_hp := ph.hp()
	game.player.global_position = where + Vector2(-20, 0)
	await wait_physics_frames(30)
	assert_eq(ph.hp(), player_hp, "deals no damage")
	assert_eq(sp.global_position, where, "stands still")
	assert_eq(sp.get_node(^"Visual").get(&"rim"), 0.0, "no contact rim")
	await _at(9.0)
	assert_false(sp.get(&"specimen"), "released at 9 s")
	assert_false(sp.is_in_group(&"specimen"))
	assert_true(hp.take(DamageInfo.make(1.0, &"shot", &"player", where)), "fights now")
	game.player.global_position = sp.global_position + Vector2(-20, 0)
	await wait_physics_frames(30)
	assert_lt(ph.hp(), player_hp, "and bites")


func test_the_spawner_is_silent_for_9_s() -> void:
	await _s9()
	assert_eq(game.spawner.hold, 9.0)
	await wait_physics_frames(50)
	assert_eq(RunState.count(&"enemy"), 0, "before the specimen: nothing spawned")
	assert_gt(game.spawner.get(&"_held"), 0.5, "the hold counts")
	await _at(1.0)
	assert_eq(RunState.count(&"enemy"), 1, "the specimen only")
	game.spawner.set(&"_held", 9.0)
	await wait_physics_frames(90)
	assert_gt(RunState.count(&"enemy"), 1, "after 9 s of spawner time, waves")


# --- The per-id reveal ---------------------------------------------------------------------

func test_each_hook_draws_tier_0_until_its_reveal() -> void:
	await _s9()
	assert_eq(Skins.current, Skins.pixel(), "S9 wears Pixel")
	assert_false(Skins.all_on(), "manual")
	var pv := game.player.get_node(^"Visual") as RectVisual
	assert_false(pv.draw_key().on, "the player: today's rect")
	assert_eq(game.arena.tile_key(10, 10), &"tier0")
	assert_eq(Palette.color(&"bg"), Palette.tier_0(&"bg"))
	await _at(1.0)
	var sv := _specimen().get_node(^"Visual") as RectVisual
	assert_false(sv.draw_key().on, "the specimen before 3 s: its rect")
	await _at(3.0)
	assert_eq(sv.draw_key().on, true)
	assert_eq(sv.draw_key().morph_step, SkinMorph.PLACEHOLDER, "the morph starts on the placeholder")
	assert_false(pv.draw_key().on, "the player still flat")
	await _at(14.0)
	assert_true(pv.draw_key().on, "the player at 14 s")
	assert_false(Skins.is_on(&"gem") or Skins.is_on(&"shot_dot_player"))
	await _at(20.0)
	assert_true(Skins.is_on(&"gem") and Skins.is_on(&"shot_dot_enemy") and Skins.is_on(&"particle"), "shots at 20 s")
	assert_eq(game.arena.tile_key(10, 10), &"tier0")
	await _at(40.0)
	assert_eq(game.arena.painted_rows(), 0, "the room starts painting")
	RunState.real_frames += 90   # 1.5 s of the 3 s
	assert_eq(game.arena.painted_rows(), 11, "half the rows at 1.5 s")
	assert_ne(game.arena.tile_key(10, 2), &"tier0")
	assert_eq(game.arena.tile_key(10, 15), &"tier0")
	RunState.real_frames += 100
	assert_eq(game.arena.painted_rows(), Arena.ROWS)
	assert_false(Skins.is_on(&"ui_panel"))
	await _at(55.0)
	assert_true(Skins.is_on(&"ui_panel"), "the UI at 55 s")
	assert_false(Skins.is_on(&"mascot"))
	await _at(70.0)
	assert_true(Skins.is_on(&"mascot"), "the mascot at 70 s")
	assert_not_null(game.mascot.get(&"_pixel_view"), "its pixel body")
	await _at(72.0)
	assert_true(Skins.all_on(), "everything at 72 s")


func test_morph_lengths_first_3_s_then_1_s() -> void:
	await _s9()
	await _at(1.0)
	var t0 := RunState.real_time()
	await _at(3.0)
	assert_almost_eq(Skins.morph_of(&"chaser", RunState.real_time()), (RunState.real_time() - RunState.real_time()) / 3.0, 0.02)
	assert_true(Skins.morphing(&"chaser"))
	assert_true(Skins.morphing(&"chaser", RunState.real_time() + 2.9), "3 s for the first asset")
	assert_false(Skins.morphing(&"chaser", RunState.real_time() + 3.01))
	await _at(14.0)
	assert_true(Skins.morphing(&"player", RunState.real_time() + 0.9))
	assert_false(Skins.morphing(&"player", RunState.real_time() + 1.01), "1 s after the first")
	await _at(40.0)
	assert_true(Skins.morphing(&"floor_a", RunState.real_time() + 2.9), "the room over 3 s")
	assert_gte(RunState.real_time(), t0)


func test_morph_steps_flash_at_most_3_times_a_second() -> void:
	for length: float in [1.0, 3.0]:
		var changes: Array[float] = []
		var last := SkinMorph.step(0.0)
		for f in int(length * 60.0) + 60:   # past the end: the plain sprite (no change)
			var u := float(f) / 60.0 / length
			var k := SkinMorph.step(u) if u < 1.0 else SkinMorph.SPRITE
			if k != last:
				changes.append(f / 60.0)
				last = k
		assert_eq(changes.size(), 3, "%s s: 3 step changes" % length)
		for i in changes.size():
			var in_window := changes.filter(func(t: float) -> bool: return t >= changes[i] and t < changes[i] + 1.0)
			assert_lte(in_window.size(), 3, "<= 3 flashes in any 1 s window (%s s)" % length)
	# The sparkle fades out over the last step; reduce flashing has none and crossfades.
	assert_eq(SkinMorph.sparkle(0.76, false) > 0.0, true)
	assert_almost_eq(SkinMorph.sparkle(0.999, false), 0.0, 0.01)
	for f in 61:
		var u := f / 60.0
		assert_eq(SkinMorph.sparkle(u, true), 0.0)
		var b := SkinMorph.blend(u)
		assert_true(b >= 0.0 and b < 1.0)
	assert_almost_eq(SkinMorph.blend(0.125), 0.5, 0.001, "halfway through a step: an even crossfade")


func test_the_morph_draws_each_step_without_errors() -> void:
	Skins.use(Skins.pixel())
	Skins.reset_reveal(true)
	var vis := RectVisual.new()
	vis.skin_id = &"chaser"
	vis.size = Vector2(30, 30)
	add_child_autofree(vis)
	Skins.reveal(&"chaser", 1.0)
	for f in 64:
		RunState.real_frames += 1
		vis.queue_redraw()
		await wait_process_frames(1)
	assert_false(Skins.morphing(&"chaser"))
	assert_eq(vis.draw_key().morph_step, -1, "done: the plain sprite")


# --- The bugs -------------------------------------------------------------------------------

func test_each_bug_restores_the_exact_draw_state() -> void:
	Skins.use(Skins.pixel())
	var enemy := RectVisual.new()
	enemy.skin_id = &"shooter"
	enemy.rim = 0.5
	enemy.hp_shown = 0.5
	add_child_autofree(enemy)
	var arena := Arena.new()
	add_child_autofree(arena)
	await wait_process_frames(1)
	var floor_cell := Vector2i(10, 10)
	var wall_cell := Vector2i(0, 0)
	for kind: StringName in Skins.BUGS:
		var before := enemy.draw_key()
		var tiles_before := [arena.tile_key(floor_cell.x, floor_cell.y), arena.tile_key(wall_cell.x, wall_cell.y)]
		Skins.glitch(kind, 3.0)
		var during := enemy.draw_key()
		match kind:
			&"swap":
				assert_eq(during.drawn, &"player", "swap: the enemy wears the player")
			&"flip":
				assert_true(during.flip, "flip: upside down")
			&"tiles":
				assert_eq(arena.tile_key(floor_cell.x, floor_cell.y), &"wall")
				assert_eq(arena.tile_key(wall_cell.x, wall_cell.y), &"floor_a")
		assert_eq(Skins.drawn_id(&"aim_arrow"), &"aim_arrow", "the aim arrow never changes")
		assert_false(Skins.flipped(&"player"), "the player never flips")
		assert_eq([enemy.rim, enemy.hp_shown], [0.5, 0.5], "rim and HP bar untouched")
		RunState.real_frames += 192   # 3.2 s: a whole number of idle periods, past the bug
		assert_eq(Skins.glitch_kind(), &"", "%s ends within 3 s" % kind)
		assert_eq(enemy.draw_key(), before, "%s: the exact draw state again" % kind)
		assert_eq([arena.tile_key(floor_cell.x, floor_cell.y), arena.tile_key(wall_cell.x, wall_cell.y)], tiles_before)
	Skins.glitch(&"swap", 10.0)
	assert_eq(Skins.glitch_kind(RunState.real_time() + 3.01), &"", "capped at 3 s")


func test_s9s_bugs_fire_with_their_lines() -> void:
	await _s9()
	var said: Array[String] = []
	game.session_runner.line_queued.connect(func(l: Line) -> void: said.append(l.text))
	await _at(28.0)
	assert_eq(Skins.glitch_kind(), &"swap")
	await _at(28.5)
	assert_true(said.any(func(t: String) -> bool: return t.contains("Why are they all you?")))
	await _at(44.0)
	assert_eq(Skins.glitch_kind(), &"tiles")
	await _at(62.0)
	assert_eq(Skins.glitch_kind(), &"flip")


# --- skin enemies --------------------------------------------------------------------------

func test_skin_enemies_reveals_each_new_id_once_with_its_line() -> void:
	await _s9()
	var said: Array[String] = []
	game.session_runner.line_queued.connect(func(l: Line) -> void: said.append(l.text))
	await _at(20.0)
	assert_eq(game.session_runner.reveal_said, 0, "the specimen's chaser was named by its own cue")
	assert_false(Skins.is_on(&"shooter"))
	game.genre.spawn_archetype(&"shooter", 1)
	await wait_physics_frames(2)
	assert_true(Skins.is_on(&"shooter"))
	assert_true(Skins.morphing(&"shooter"), "drawn in over 1 s")
	game.genre.spawn_archetype(&"shooter", 1)
	game.genre.spawn_archetype(&"chaser", 1)
	await wait_physics_frames(2)
	assert_eq(game.session_runner.reveal_said, 1, "a second shooter and a chaser: no new line")
	game.genre.spawn_archetype(&"tank", 1)
	game.genre.spawn_archetype(&"bomber", 1)
	await wait_physics_frames(2)
	assert_eq(game.session_runner.reveal_said, 3)
	var pool := CampaignDB.get_session(S9).reveal_line_list().map(func(l: Line) -> String: return l.text)
	var got := said.filter(func(t: String) -> bool: return t in pool)
	assert_eq(got, pool.slice(0, 3), "in order")
	assert_true(Skins.is_on(&"tank") and Skins.is_on(&"bomber"))


# --- The end state ---------------------------------------------------------------------------

func _assert_all_revealed(why: String) -> void:
	assert_true(Skins.all_on(), why)
	var n := 0
	for node in get_tree().get_nodes_in_group(Skins.SKINNED):
		if node is RectVisual and game.is_ancestor_of(node):
			var key: Dictionary = (node as RectVisual).draw_key()
			if key.id != &"" and Skins.current.has(key.id):
				assert_true(key.on, "%s: %s revealed" % [why, key.id])
				assert_eq(key.get("morph_step", -1), -1, "%s: %s not mid-morph" % [why, key.id])
				n += 1
			assert_eq((node as RectVisual).skin_version(), Skins.version, "%s: at Skins.version" % why)
	assert_gt(n, 0, why)
	assert_eq(game.arena.painted_rows(), Arena.ROWS)
	assert_ne(game.arena.tile_key(10, 10), &"tier0")
	assert_eq(Skins.glitch_kind(), &"")


func test_after_s9_every_skinned_node_is_revealed() -> void:
	await _s9()
	await _at(1.0)
	await _at(149.0)
	await _at(150.0)
	assert_true(game.run_loop.is_over(), "won at 150 s")
	_assert_all_revealed("after S9")


func test_a_death_at_30_s_ends_fully_revealed() -> void:
	await _s9(&"arsenal", false)
	await _at(1.0)
	await _at(30.0)
	assert_false(Skins.all_on())
	(Component.find(game.player, Health) as Health).take(DamageInfo.make(999, &"contact", &"enemy"))
	await wait_physics_frames(2)
	assert_true(game.run_loop.is_over())
	_assert_all_revealed("a death at 30 s")


func test_a_retry_replays_the_transformation() -> void:
	await _s9()
	await _at(80.0)
	assert_true(Skins.all_on())
	game.free()
	await _s9()
	assert_false(Skins.all_on(), "the next boot of S9 starts unrevealed again")
	assert_false(Skins.is_on(&"chaser"))


func test_a_later_skin_session_starts_fully_revealed_and_a_plain_one_takes_it_off() -> void:
	var later := _session([], &"pixel", &"all")
	Skins.apply_session(later)
	assert_true(Skins.all_on(), "skin pixel, look_reveal all: everything from the start")
	Skins.apply_session(CampaignDB.get_session(&"s2_02_day_one"))
	assert_null(Skins.current, "a session's skin comes off in a skin-less session")
	Skins.use(Skins.pixel())
	Skins.apply_session(CampaignDB.get_session(&"s2_02_day_one"))
	assert_true(Skins.all_on(), "a CLI / F10 look stays")


func test_skins_off_keeps_every_look_off() -> void:
	Skins.disabled = true
	await _s9()
	assert_null(Skins.current, "--skins=off: S9 plays tier 0")
	Skins.toggle()
	assert_null(Skins.current, "F10 does nothing")
	Skins.use(Skins.pixel())
	assert_null(Skins.current, "nor the console")
	await _at(80.0)
	assert_null(Skins.current, "nor the skin cues")
	assert_true(game.session_runner.fired_count() > 10, "the cues still fire")


# --- M48b review --------------------------------------------------------------------------

func test_a_reveal_after_everything_is_drawn_starts_no_morph() -> void:
	Skins.use(Skins.pixel())
	Skins.reset_reveal(true)
	Skins.use(Skins.pixel())   # F10 twice: everything drawn
	Skins.reveal(&"player", 1.0)
	Skins.reveal(&"arena", 3.0)
	assert_false(Skins.morphing(&"player"), "a CLI / F10 look: the player stays drawn")
	assert_false(Skins.morphing(&"arena"))
	Skins.reset_reveal(true)
	Skins.reveal_all()   # `skin all`
	Skins.reveal(&"splitter_mini", 1.0)
	assert_false(Skins.morphing(&"splitter_mini"), "after `skin all`: no re-morph")
	assert_true(Skins.all_on())


func test_skin_all_ends_the_reveal_lines() -> void:
	await _s9()
	await _at(20.0)
	var before: int = game.session_runner.reveal_said
	await _at(72.0)
	game.genre.spawn_archetype(&"tank", 1)
	game.genre.spawn_archetype(&"bomber", 1)
	await wait_physics_frames(2)
	assert_eq(game.session_runner.reveal_said, before, "after `skin all`: no more 'Another one!' lines")
	assert_false(Skins.morphing(&"tank"))
	assert_false(EventBus.entity_spawned.is_connected(game.session_runner._on_entity_spawned))


func test_the_reduce_flashing_crossfade_never_draws_a_step_twice() -> void:
	for i in 401:
		var u := i / 400.0
		var ls := SkinMorph.layers(u)
		var steps := ls.map(func(l: Array) -> int: return int(l[0]))
		for k in steps:
			assert_eq(steps.count(k), 1, "u=%.3f: step %d once" % [u, k])
		if SkinMorph.step(u) == SkinMorph.SPRITE:
			assert_eq(ls, [[SkinMorph.SPRITE, 1.0]], "u=%.3f: the last step is the sprite at full" % u)
		if SkinMorph.step(u) == SkinMorph.OUTLINE:
			assert_eq(float(ls[0][1]), 1.0, "u=%.3f: the outline stays opaque under the sprite" % u)


func test_a_morph_keeps_the_hit_flash_and_the_telegraph() -> void:
	Skins.use(Skins.pixel())
	Skins.reset_reveal(true)
	var vis := RectVisual.new()
	vis.skin_id = &"shooter"
	vis.size = Vector2(30, 30)
	vis.color = Color(0.8, 0.2, 0.2)
	add_child_autofree(vis)
	var now := RunState.real_time()
	assert_eq(vis.morph_overlay(0.1, now), {"fill": vis.color, "silhouette": 0.0}, "no flash: today's colour")
	vis.telegraph = 1.0
	var tele: Dictionary = vis.morph_overlay(0.1, now)
	assert_ne(tele["fill"], vis.color, "the placeholder flickers toward white")
	assert_gt(float(vis.morph_overlay(0.6, now)["silhouette"]), 0.0, "a sprite step gets the white silhouette")
	vis.telegraph = 0.0
	vis.flash()
	assert_eq(vis.morph_overlay(0.1, now)["fill"], Color.WHITE, "the hit flash on the placeholder")
	assert_almost_eq(float(vis.morph_overlay(0.3, now)["silhouette"]), 0.9, 0.001, "and on the mosaic")
	Skins.reveal(&"shooter", 1.0)
	for f in 8:
		RunState.real_frames += 8
		vis.queue_redraw()
		await wait_process_frames(1)


func test_a_cli_look_survives_s9_then_a_plain_session() -> void:
	Skins.use(Skins.pixel())   # --look=pixel / F10
	Skins.apply_session(CampaignDB.get_session(S9))
	assert_false(Skins.all_on(), "S9 still transforms")
	Skins.apply_session(CampaignDB.get_session(&"s2_02_day_one"))
	assert_eq(Skins.current, Skins.pixel(), "the player's look stays")
	assert_true(Skins.all_on(), "and is whole again")


# --- Per path -----------------------------------------------------------------------------

func test_s9_per_path_the_laser_at_80_and_novas_line_on_auto() -> void:
	for p in PATHS:
		await _s9(p)
		await _at(79.0)
		assert_false(&"laser" in game.path_runner.live_pool, "%s: no laser before 80 s" % p)
		await _at(80.0)
		assert_true(&"laser" in game.path_runner.live_pool, "%s: the laser at 80 s" % p)
		await _at(90.0)
		assert_eq(&"nova" in game.path_runner.live_pool, p == &"auto", "%s: nova announced on Auto only" % p)
		game.free()
