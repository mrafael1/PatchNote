extends GutTest
## M47 (PLAN v9 3.1, 3.2 S7, 3.5, 1.12, 1.14): the real S7 tryout. Its data and timings (D1),
## the per-cue warnings and the swaps, nothing left behind, the path-scoped `picked`, the
## live-path reactions, the HP floor, the cook beat on its stage card (D2), the saves that
## played the old stub (D3, never bumped twice), fork_path and its debrief, the telemetry
## path keys (D18) and replay-as-path (D17). The card and the debrief pause the tree: these
## tests drive _process by hand and never wait while one is open.

const TEST_DIR := "user://save_s7_tryout_test/"
const TEST_PATH := "user://save_s7_tryout_test/save.json"
const TEST_LOG := "user://save_s7_tryout_test/runs.jsonl"
const OWNER_FIXTURE := "res://tests/gut/save_m43_owner_shape.json"
const M42_FIXTURE := "res://tests/gut/save_m42_2_stage1_end.json"
const S7 := &"s2_01_tryout"
const S8 := &"s2_02_day_one"
## D1: the cue times (the swap lands 1.5 s after its cue).
const TIMES := [[13.0, &"path", &"arsenal"], [15.0, &"add", &"cards"], [15.0, &"give", &"shotgun"],
		[17.0, &"say", &""], [52.0, &"say", &""], [56.0, &"path", &"survival"], [58.0, &"add", &"pickups"],
		[61.0, &"drop", &"shotgun"], [61.0, &"say", &""], [74.0, &"add", &"kill_heal"], [74.0, &"say", &""],
		[95.0, &"say", &""], [99.0, &"path", &"auto"], [103.0, &"say", &""], [107.0, &"add", &"crowd"],
		[107.0, &"say", &""], [112.0, &"add", &"levelups"], [112.0, &"say", &""], [128.0, &"say", &""],
		[143.0, &"path", &"off"], [145.0, &"say", &""]]

var game: Main


func before_each() -> void:
	_delete_files()
	Telemetry.log_path = TEST_LOG
	PathRunner.taste_stills.clear()


func after_each() -> void:
	await wait_physics_frames(2)   # deferred spawns land before the game is freed (no orphan)
	assert_false(FileAccess.file_exists(TEST_LOG), "no telemetry written, not even to the scratch log")
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	PathRunner.taste_stills.clear()
	RunState.invincible = false
	RunState.set_pause(&"stage_card", false)
	CampaignDB.active = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null
	_delete_files()


func _delete_files() -> void:
	for p in [TEST_LOG, TEST_PATH, TEST_PATH + ".tmp", TEST_DIR + "owner.json", TEST_DIR + "owner_next.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _game(id: StringName) -> Main:
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var g: Main = load("res://main.tscn").instantiate()
	add_child_autofree(g)
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	game = g
	RunState.invincible = true
	return g


## A scratch copy of the owner-shaped fixture (never the real save), optionally edited.
func _owner_copy(name: String, next := "") -> String:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OWNER_FIXTURE))
	if next != "":
		(d.campaign as Dictionary)["next"] = next
	var path := TEST_DIR + name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	return path


# --- Data ------------------------------------------------------------------------------

func test_s7_is_real_valid_and_playable() -> void:
	var s := CampaignDB.get_session(S7)
	assert_eq(s.problems(), [] as Array[String])
	assert_eq(CampaignDB.problems(), [] as Array[String])
	assert_false(s.is_cooking())
	assert_false(FileAccess.get_file_as_string("res://campaign/sessions/s2_01_tryout.tres").contains("cooking ="),
			"the cooking line is deleted (M43.2 obligation)")
	assert_eq([s.stage, s.goal, s.goal_value, s.hp_floor, s.tryout, s.face, s.bump, s.fork],
			[2, SessionDef.STOP, 150.0, 1, true, true, &"minor", &"fork_path"])
	assert_eq(s.cook_beat, PackedStringArray(["Trying three kinds of shooter...", "Compiling... mostly.",
			"One of them is on fire.", "Done. Mostly."]))
	assert_eq(s.after_pick_lines().map(func(l: Line) -> String: return l.text),
			["The other two go in a drawer. I never throw anything away."])
	assert_eq(s.notes, PackedStringArray(["The shooter, three ways", "Added a title screen.",
			"Added options (audio, video, controls, accessibility).", "Added a pause menu."]), "M47.4: v0.8.0 gains the front door")
	assert_eq(CampaignDB.index_of(S7), 7)


func test_the_cue_order_and_the_d1_times() -> void:
	var got: Array = []
	for c in CampaignDB.get_session(S7).cue_list():
		if c.when == &"at":
			got.append([c.value, c.action, c.target if c.action != &"say" else &""])
	assert_eq(got, TIMES)
	var picked := CampaignDB.get_session(S7).cue_list().filter(func(c: Cue) -> bool: return c.when == &"picked")
	assert_eq(picked.size(), 1)
	assert_eq((picked[0] as Cue).line.text, "See? Better gun, same card.")


func test_each_path_cue_carries_its_own_warning() -> void:
	var warns := {}
	for c in CampaignDB.get_session(S7).cue_list():
		if c.action == &"path" and c.line != null:
			warns[c.target] = c.line.text
	assert_eq(warns, {&"arsenal": "Version one. Your guns are cards.",
			&"survival": "Version two. No cards. Guns are lying around.",
			&"auto": "Version three. Hands off the trigger."})


# --- The swaps ---------------------------------------------------------------------------

func test_the_arsenal_cue_warns_with_its_line_and_lands_1_5_s_later() -> void:
	await _game(S7)
	var r := game.path_runner
	game.run_loop.goal_clock = 12.99
	await wait_physics_frames(2)
	assert_true(r.swap_pending(), "the cue fired at 13 s")
	assert_true(r.said.has("Version one. Your guns are cards."), "its own warning")
	assert_eq(RunState.live_path(), &"", "not yet")
	await wait_physics_frames(roundi(PathRunner.SWAP_WARN_SECONDS * 60) + 1)
	assert_eq(RunState.live_path(), &"arsenal")


func test_nothing_is_left_behind_after_each_swap() -> void:
	await _game(S7)
	var r := game.path_runner
	for p: StringName in [&"arsenal", &"survival", &"auto", &"off"]:
		RunState.add_basic(&"pickups")
		RunState.add_basic(&"cards")
		RunState.add_basic(&"levelups")
		await wait_physics_frames(3)
		r.swap_now(p)
		await wait_physics_frames(3)
		assert_eq(r.leftovers(), [] as Array[String], "after the swap to %s" % p)
	var logged := RunState.run_log.filter(func(e: Dictionary) -> bool:
		return e.event == &"path_leftovers" and not (e.get("left", []) as Array).is_empty())
	assert_eq(logged.size(), 0)


## A player shot and a Survival kill drop made on the swap tick (both deferred spawns, so
## the swap's own sweep cannot see them); `late` false turns the second sweep's freeing off.
func _swap_tick_spawns(late: bool) -> Array:
	await _game(S7)
	var r := game.path_runner
	RunState.add_basic(&"pickups")
	r.swap_now(&"survival")
	await wait_physics_frames(4)
	r.late_sweep = late
	var lo := Component.find(game.player, Loadout) as Loadout
	lo.current().ready_in = 0.0
	var added: Array = []
	var add := func(n: Node) -> void:
		if n is Pickup or n.is_in_group(&"player_projectile") or n.get(&"kind") == &"player_projectile":
			added.append(n)
	get_tree().node_added.connect(add)
	var drops: Node = r.get(&"_drops")
	assert_not_null(drops.call(&"spawn_pickup", &"ammo", &"", game.player.global_position + Vector2(96, 0)))
	assert_true(lo.try_fire(Vector2.RIGHT), "a shot on the swap tick")
	r.swap_now(&"arsenal")
	await wait_physics_frames(4)
	get_tree().node_added.disconnect(add)
	return added


func test_a_shot_and_a_kill_drop_on_the_swap_tick_are_gone_by_the_check() -> void:
	var made := await _swap_tick_spawns(true)
	assert_gte(made.size(), 2, "a shot and a drop entered after the swap")
	for n in made:
		assert_false(is_instance_valid(n), "gone (freed, not just queued)")
	var r := game.path_runner
	assert_eq(r.leftover_checks.size(), 2)
	assert_eq(r.leftover_checks[-1], [] as Array[String])
	var ev: Array = RunState.run_log.filter(func(e: Dictionary) -> bool: return e.event == &"path_leftovers")
	assert_gt(int((ev[-1] as Dictionary).get("late", 0)), 1, "the second sweep took both")


func test_the_check_reports_them_when_the_second_sweep_frees_nothing() -> void:
	var made := await _swap_tick_spawns(false)
	assert_true(made.any(func(n: Variant) -> bool: return is_instance_valid(n)), "still there")
	var left: Array = game.path_runner.leftover_checks[-1]
	assert_true(left.has("player_projectile"), str(left))
	assert_true(left.has("pickup"), str(left))
	for n in made:
		if is_instance_valid(n):
			(n as Node).queue_free()


func test_each_swap_wipes_once_and_crossfades_under_reduce_flashing() -> void:
	var lands: Array = TIMES.filter(func(t: Array) -> bool: return t[1] == &"path").map(
			func(t: Array) -> float: return float(t[0]) + PathRunner.SWAP_WARN_SECONDS)
	for a: float in lands:
		var in_a_second := lands.filter(func(b: float) -> bool: return b >= a and b < a + 1.0).size()
		assert_lte(in_a_second, 3, "at most 3 wipes a second")
	await _game(S7)
	var r := game.path_runner
	SaveGame.set_setting("reduce_flashing", true)
	r.swap_now(&"arsenal")
	assert_eq(r.wipes, 1)
	assert_almost_eq(game.transition.glitch_strength(), 0.0, 0.001, "reduce flashing: no glitch")
	assert_true(is_instance_valid(r.get(&"_fade")), "the crossfade instead")
	SaveGame.set_setting("reduce_flashing", false)
	r.swap_now(&"survival")
	assert_eq(r.wipes, 2, "one wipe per swap")
	assert_gt(game.transition.glitch_strength(), 0.0, "one glitch pulse")
	assert_lte(PathRunner.GLITCH, 1.0)


func test_the_arsenal_taste_deals_one_card_after_10_kills() -> void:
	await _game(S7)
	var r := game.path_runner
	RunState.add_basic(&"cards")
	r.swap_now(&"arsenal")
	await wait_physics_frames(2)
	var e := _dummy()
	for i in 9:
		_player_kill(e)
	assert_eq(r.cards(), 0, "9 kills: no card")
	_player_kill(e)
	assert_eq(r.cards(), 1, "the 10th: one card")
	for i in 40:
		_player_kill(e)
	assert_eq(r.cards(), 1, "then the meter stops")
	game.free()


func test_the_auto_taste_levels_once_with_no_passive_offered() -> void:
	await _game(S7)
	var r := game.path_runner
	RunState.add_basic(&"levelups")
	r.swap_now(&"auto")
	await wait_physics_frames(2)
	for id: StringName in r.offer_pool():
		assert_false(WeaponDB.get_weapon(id).is_passive(), "%s: no passive in the taste" % id)
	assert_eq(r.level(), 1)
	r.force_level()
	assert_eq(r.level(), 2, "levels once")
	r.force_level()
	assert_eq(r.level(), 2, "and only once")
	game.free()


func test_the_survival_taste_drops_and_heals_with_no_crate() -> void:
	await _game(S7)
	var r := game.path_runner
	RunState.add_basic(&"pickups")
	RunState.add_basic(&"kill_heal")
	r.swap_now(&"survival")
	await wait_physics_frames(3)
	var h := Component.find(game.player, Health) as Health
	h.hp_ratio = (h.max_hp() - 2.0) / h.max_hp()
	var e := _dummy()
	for i in 5:
		_player_kill(e)
	assert_eq(r.heals(), 1, "the 5th kill heals")
	assert_almost_eq(h.hp(), h.max_hp() - 1.0, 0.001)
	for i in 95:
		_player_kill(e)
	await wait_physics_frames(1)
	var pk := get_tree().get_nodes_in_group(&"pickup")
	assert_gt(pk.size(), 0, "kill drops")
	assert_false(pk.any(func(p: Node) -> bool: return (p as Pickup).crate), "no crate in a tryout")


func _dummy() -> Node2D:
	var e := (load("res://entities/enemy_chaser.tscn") as PackedScene).instantiate() as Node2D
	add_child_autofree(e)
	e.set_physics_process(false)
	e.global_position = Vector2(-4000, -4000)
	return e


func _player_kill(e: Node2D) -> void:
	EventBus.enemy_killed.emit(e, DamageInfo.make(1.0, &"shot", &"player"))


func test_picked_binds_to_arsenal_and_expires_at_the_next_swap() -> void:
	await _game(S7)
	var r := game.path_runner
	r.swap_now(&"arsenal")
	await wait_physics_frames(1)
	var sr := game.session_runner
	var idx := -1
	var cues: Array = sr.get(&"_cues")
	for i in cues.size():
		if (cues[i] as Cue).when == &"picked":
			idx = i
	assert_true((sr.get(&"_bound") as Dictionary).has(idx), "bound to Arsenal")
	r.swap_now(&"survival")
	await wait_physics_frames(1)
	assert_true((sr.get(&"_fired") as Array)[idx], "expired at the swap (0 Arsenal picks: no line)")
	assert_eq(RunState.run_log.filter(func(e: Dictionary) -> bool: return e.event == &"cue_expired").size(), 1)
	assert_false(r.said.has("See? Better gun, same card."))


func test_the_auto_gated_reactions_read_the_live_path() -> void:
	await _game(S7)
	var gated := CampaignDB.reactions.filter(func(d: ReactionDef) -> bool: return d.when.contains("answer:path_auto"))
	assert_eq(gated.size(), 7, "the 7 !answer:path_auto reactions")
	var re: Node = game.reactions
	assert_true(&"not_shooting" in re.active_ids(), "all load at start (no live path)")
	game.path_runner.swap_now(&"auto")
	for d: ReactionDef in gated:
		assert_false(re.live_path_holds(d.when), "%s refused during the Auto taste" % d.id)
	game.path_runner.swap_now(&"arsenal")
	for d: ReactionDef in gated:
		assert_true(re.live_path_holds(d.when), "%s back on Arsenal" % d.id)


func test_the_hp_floor_holds() -> void:
	await _game(S7)
	RunState.invincible = false
	assert_eq(RunState.rules.hp_floor, 1)
	var h := Component.find(game.player, Health) as Health
	for i in 20:
		h.take(DamageInfo.make(5.0, &"contact", &"enemy"))
	assert_false(h.dead, "0 deaths over a forced burst")
	assert_almost_eq(h.hp(), 1.0, 0.001)


func test_the_tastes_level_on_their_taste_lists() -> void:
	assert_eq(PathDB.get_def(&"arsenal").threshold(1, true), 10, "Arsenal's taste: one card after 10 kills")
	assert_eq(PathDB.get_def(&"arsenal").threshold(1, false), 25, "S8: the first card at 25 kills (M46 D1)")
	assert_eq(PathDB.get_def(&"arsenal").threshold(2, true), -1, "one card, then the meter stops")
	assert_gt(PathDB.get_def(&"auto").threshold(1, true), 0, "Auto levels once")
	assert_eq(PathDB.get_def(&"auto").threshold(2, true), -1)


func test_the_stop_ends_s7_at_152_s() -> void:
	await _game(S7)
	var loop := game.run_loop
	assert_eq(loop.goal, SessionDef.STOP)
	assert_eq(loop.goal_value, 150.0)
	loop.goal_clock = 149.99
	await wait_physics_frames(2)
	assert_true(loop.stop_said, "the AI stops it at 150 s")
	assert_eq(loop.phase, RunLoop.PLAY, "the read beat first")
	loop.goal_clock = 151.9
	await wait_physics_frames(1)
	assert_eq(loop.phase, RunLoop.PLAY, "still reading just before 152")
	loop.goal_clock = 152.0 - 0.5 / 60.0
	await wait_physics_frames(1)
	assert_eq(loop.outcome, RunLoop.STOPPED, "it ends")
	assert_almost_eq(loop.goal_clock, 152.0, 0.02, "at 152.0 s")


# --- The cook beat on the stage card (D2) -------------------------------------------------

func _beat_card() -> StageCard:
	var card := StageCard.new()
	card.setup_beat(CampaignDB.get_session(S7).cook_beat, "v0.8.0")
	card.setup(2, "The shooter")
	add_child_autofree(card)
	return card


func _key() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_SPACE
	e.pressed = true
	return e


func test_the_beat_shows_its_lines_fills_the_bar_then_the_card() -> void:
	var card := _beat_card()
	assert_true(card.in_beat())
	assert_false(card.is_cooking(), "never the cooking branches")
	assert_false(card._title_label.visible)
	assert_eq(card.beat_shown, 0)
	card._process(0.6)
	assert_eq(card.beat_shown, 1)
	assert_almost_eq(card.beat_bar(), 0.25, 0.001)
	for i in 30:
		card._process(0.1)
	assert_false(card.in_beat())
	assert_eq(card.beat_shown, 4)
	assert_almost_eq(card.beat_bar(), 1.0, 0.001, "the bar fills (never stalls)")
	assert_true(card._title_label.visible)
	assert_eq(card.mascot.current_text(), StageCard.LINE, "then the card's own line")
	assert_true(card.is_open())
	for i in 31:
		card._process(0.1)
	assert_false(card.is_open(), "the card's 3 s after the beat")


func test_a_key_ends_the_beat_and_skip_closes_at_once() -> void:
	var card := _beat_card()
	card.elapsed = 0.6
	card._input(_key())
	assert_false(card.in_beat(), "a key after 0.5 s ends the beat")
	assert_true(card.is_open())
	var other := _beat_card()
	other.skip()
	assert_false(other.is_open(), "skip() closes at once")
	assert_false(other.ended, "never the cooking end")


func test_the_real_boot_shows_the_beat_for_s7_and_none_for_s8() -> void:
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(S7))
	var g: Main = load("res://main.tscn").instantiate()
	add_child_autofree(g)
	assert_not_null(g.stage_card)
	assert_true(g.stage_card.in_beat())
	assert_eq(g.stage_card.building, CampaignDB.version_after(CampaignDB.get_session(S7)).label(), "the version it builds")
	g.stage_card.skip()
	await wait_physics_frames(1)
	g.free()
	SaveGame.go_inert()
	CampaignDB.answer_fork(&"fork_path", &"path_arsenal")
	SaveGame.campaign().done = ["s2_01_tryout"]
	var g8 := await _game(S8)
	assert_null(g8.stage_card, "S8: no card")


# --- Saves (D3) ---------------------------------------------------------------------------

func _owner_rules(path: String) -> void:
	var before := FileAccess.get_file_as_string(path)
	SaveGame.use_snapshot(path)
	assert_eq(SaveGame.version().label(), "v0.8.0")
	assert_true(CampaignDB.stub_era())
	var s7 := CampaignDB.current()
	assert_eq(s7.id, S7)
	assert_true(CampaignDB.stage_card_due(s7), "the card")
	assert_eq(CampaignDB.version_after(s7).label(), "v0.8.0")
	CampaignDB.complete(s7, ChangeDB.get_change(&"path_arsenal"))
	assert_eq(SaveGame.version().label(), "v0.8.0", "never bumped twice")
	assert_eq(SaveGame.campaign().next, String(S8))
	assert_false(CampaignDB.stub_era())
	assert_eq(CampaignDB.current().id, S8)
	assert_false(CampaignDB.stage_card_due(CampaignDB.current()), "no card for S8")
	assert_eq(CampaignDB.version_after(CampaignDB.current()).label(), "v0.8.1")
	CampaignDB.complete(CampaignDB.current())
	assert_eq(SaveGame.version().label(), "v0.8.1")
	assert_eq(CampaignDB.current().id, &"s2_03_paint", "M48b: S9 follows S8")
	CampaignDB.complete(CampaignDB.current())
	assert_eq(SaveGame.version().label(), "v0.8.2")
	assert_true(CampaignDB.is_done())
	assert_eq(FileAccess.get_file_as_string(path), before, "a snapshot never writes")


func test_the_owner_save_plays_s7_with_its_card_and_bumps_once() -> void:
	_owner_rules(_owner_copy("owner.json"))


func test_the_owner_save_with_next_s7_too() -> void:
	_owner_rules(_owner_copy("owner_next.json", "s2_01_tryout"))


func test_the_m42_2_save_plays_s7_from_v0_7_0() -> void:
	SaveGame.use_snapshot(M42_FIXTURE)
	assert_false(CampaignDB.stub_era())
	assert_eq(CampaignDB.current().id, S7)
	assert_true(CampaignDB.stage_card_due(CampaignDB.current()))
	CampaignDB.complete(CampaignDB.current())
	assert_eq(SaveGame.version().label(), "v0.8.0")


func test_a_fresh_chain_save_gets_the_card_once() -> void:
	SaveGame.go_live(TEST_PATH, true)
	assert_true(CampaignDB.jump_to(S7))
	assert_true(CampaignDB.stage_card_due(CampaignDB.current()))
	SaveGame.count_attempt(S7)
	assert_false(CampaignDB.stage_card_due(CampaignDB.current()), "Retry: no card again")


# --- fork_path and the debrief (1.12) -------------------------------------------------------

func test_fork_path_validates_and_s8_resolves_it() -> void:
	var f := ChangeDB.get_fork(&"fork_path")
	assert_not_null(f)
	assert_true(f.campaign)
	assert_eq(f.changes().map(func(c: Change) -> StringName: return c.id), [&"path_arsenal", &"path_auto", &"path_survival"])
	for c in f.changes():
		assert_eq(ChangeDB.problems(c), [] as Array[String])
		assert_eq(c.kind, &"path")
		assert_true(PathDB.has(c.take.id))
	for p: StringName in [&"arsenal", &"auto", &"survival"]:
		SaveGame.go_inert()
		assert_true(CampaignDB.answer_fork(&"fork_path", StringName("path_%s" % p)))
		assert_eq(CampaignDB.get_session(S8).resolve(&"path"), p)
		var shelf := CampaignDB.shelf(2).map(func(c: Change) -> StringName: return c.id)
		assert_eq(shelf.size(), 2, "the two others go in the drawer")
		assert_false(StringName("path_%s" % p) in shelf)


func test_the_s7_debrief_asks_fork_path_then_the_take_and_the_drawer_line() -> void:
	PathRunner.taste_stills["arsenal"] = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGB8))
	var d := DebriefScreen.new()
	add_child_autofree(d)
	d.input_delay = 0.0
	d.open(CampaignDB.get_session(S7), &"stopped", 0)
	d.finish_lines()
	assert_eq(d.phase, DebriefScreen.FORK)
	assert_eq(d.said[-1], "Which shooter do we make?")
	assert_eq(d.fork_options().size(), 3)
	assert_not_null(DebriefScreen._still_for(ChangeDB.get_change(&"path_arsenal")), "the taste's still")
	assert_null(DebriefScreen._still_for(ChangeDB.get_change(&"path_auto")), "no still: text only")
	assert_false(SaveGame.has_shipped(&"path_arsenal"))
	assert_true(d.pick(0))
	d.finish_lines()
	assert_true(d.said.has("Cards it is. I'll start printing."))
	assert_eq(d.said[-1], "The other two go in a drawer. I never throw anything away.")
	assert_false(SaveGame.has_shipped(&"path_arsenal"), "nothing ships before the debrief closes")
	assert_eq(d.choices(), [DebriefScreen.NEXT])
	assert_string_contains(DebriefScreen.notes_text(d.session, d.picked), "The shooter, three ways")
	assert_string_contains(DebriefScreen.notes_text(d.session, d.picked), "Path: Arsenal (cards)")


# --- Telemetry (D18) -------------------------------------------------------------------------

func test_the_path_keys_on_s7_and_stage_1() -> void:
	await _game(S7)
	var r := game.path_runner
	r.swap_now(&"arsenal")
	await wait_physics_frames(2)
	r.swap_now(&"survival")
	await wait_physics_frames(2)
	r.swap_now(&"auto")
	await wait_physics_frames(2)
	r.swap_now(&"off")
	await wait_physics_frames(2)
	var rec := CampaignDB.path_record(RunState.session, r)
	assert_eq(rec.path, "", "a tryout has no answered path")
	assert_null(rec.fp, "fp: null on a tryout")
	assert_eq((rec.fp_tastes as Dictionary).keys().size(), 3, "three tastes")
	assert_eq((rec.swaps as Array).size(), 4)
	assert_false(rec.replay)
	for k in ["weapons", "pickups", "kill_heal", "picks"]:
		assert_true(rec.has(k), k)
	var s1 := CampaignDB.path_record(CampaignDB.get_session(&"s1_04_level"), null)
	assert_eq([s1.path, s1.fp, s1.swaps, s1.fp_tastes], ["", null, [], {}])


# --- Replay as path (D17) ---------------------------------------------------------------------

func test_replay_plays_a_copy_and_restores_the_save_exactly() -> void:
	SaveGame.go_live(TEST_PATH, true)
	CampaignDB.answer_fork(&"fork_path", &"path_arsenal")
	SaveGame.campaign().done = ["s2_01_tryout", "s2_02_day_one"]
	SaveGame.write()
	var bytes := FileAccess.get_file_as_string(TEST_PATH)
	var version := SaveGame.version().label()
	assert_eq(StartScreen.replay_sessions().map(func(s: SessionDef) -> StringName: return s.id), [S8])
	SaveGame.begin_replay(&"fork_path", &"path_survival")
	assert_true(SaveGame.in_replay())
	assert_false(SaveGame.persist, "never written")
	assert_eq(CampaignDB.get_session(S8).resolve(&"path"), &"survival")
	assert_eq(SaveGame.version().label(), version, "no bump")
	SaveGame.set_setting("reduce_flashing", true)
	CampaignDB.jump_to(S8)
	CampaignDB.complete(CampaignDB.get_session(S8))
	SaveGame.end_replay()
	assert_false(SaveGame.in_replay())
	assert_true(SaveGame.persist)
	assert_eq(CampaignDB.get_session(S8).resolve(&"path"), &"arsenal", "the answer is back")
	assert_eq(SaveGame.version().label(), version)
	assert_true(bool(SaveGame.setting("reduce_flashing")), "a settings toggle survives")
	var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
	assert_eq(after.settings.reduce_flashing, true, "and is saved (the restored mode persists)")
	var was: Dictionary = JSON.parse_string(bytes)
	after.settings = was.settings
	assert_eq(after, was, "nothing else changed on disk")


func test_end_replay_under_an_inert_save_stays_inert() -> void:
	SaveGame.go_inert()
	SaveGame.begin_replay(&"fork_path", &"path_auto")
	SaveGame.end_replay()
	assert_eq(SaveGame.last_load, SaveGame.INERT)
	assert_false(SaveGame.persist)


func test_the_replay_row_hides_without_a_done_path_session() -> void:
	SaveGame.go_inert()
	assert_eq(StartScreen.replay_sessions(), [] as Array[SessionDef])
