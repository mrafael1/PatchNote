extends GutTest
## M47 (PLAN v9 3.2 S8 without the try-on, 1.9, 3.5): S8 "Day one" as data, per path, and
## the splitter (EnemyVariant). G9 (no pick, drop or crate carries the shotgun before its
## give at 30 s) and G10 (the 3.5 audit for S7-S8) live here by name. Every game here is
## jumped to on an inert save, invincible; the clock is moved, never waited on in a panel.

const TEST_LOG := "user://save_s8_day_one_test/runs.jsonl"
const S7 := &"s2_01_tryout"
const S8 := &"s2_02_day_one"
const PATHS: Array[StringName] = [&"arsenal", &"auto", &"survival"]
## PLAN 3.5's audit for S7-S8: [session, path ("-" any), regex, what it covers]. Each row's
## regex must match one of that session's intro or cue strings (or its field, for hp_floor).
const AUDIT := [
	["s2_01_tryout", "arsenal", "^at 4: path arsenal ", "Arsenal hand"],
	["s2_01_tryout", "arsenal", "\\{key:weapon_prev\\} and \\{key:weapon_next\\} to switch", "switching"],
	["s2_01_tryout", "arsenal", "^at 6: add cards$", "card meter"],
	["s2_01_tryout", "arsenal", "^at 6: give shotgun$", "weapons (shotgun)"],
	["s2_01_tryout", "survival", "^at 40: path survival ", "Survival"],
	["s2_01_tryout", "survival", "^at 42: add pickups$", "drops"],
	["s2_01_tryout", "survival", "And a revolver\\. Six shots, then it reloads", "the revolver (M47.6d1)"],
	["s2_01_tryout", "survival", "^at 45: drop shotgun$", "swap"],
	["s2_01_tryout", "survival", "Ammo runs out", "sidearm fallback"],
	["s2_01_tryout", "survival", "^at 58: add kill_heal$", "kill-heal"],
	["s2_01_tryout", "auto", "^at 76: path auto ", "Auto auto-fire / fire button off"],
	["s2_01_tryout", "auto", "^at 84: add crowd$", "crowd overlay"],
	["s2_01_tryout", "auto", "^at 89: add levelups$", "gems / LV"],
	["s2_01_tryout", "-", "hp_floor=1", "hp_floor 1"],
	["s2_02_day_one", "arsenal", "^answer:path_arsenal at 10: add cards$", "card meter"],
	["s2_02_day_one", "arsenal", "ranks it up\\. No top rank\\. Gold cards are rarer", "weapon ranks (card text)"],
	["s2_02_day_one", "arsenal", "^answer:path_arsenal at 20: add quick_draw$", "quick-draw"],
	["s2_02_day_one", "auto", "Don't touch the trigger", "Auto fire button off"],
	["s2_02_day_one", "auto", "^answer:path_auto at 10: add levelups$", "gems / LV"],
	["s2_02_day_one", "auto", "^answer:path_auto at 14: add crowd$", "crowd overlay"],
	["s2_02_day_one", "survival", "^answer:path_survival at 10: add pickups$", "drops + crates"],
	["s2_02_day_one", "survival", "Walk over another gun to swap", "swap"],
	["s2_02_day_one", "survival", "revolver back\\. It just reloads", "sidearm fallback (M47.6d1: the revolver)"],
	["s2_02_day_one", "survival", "^answer:path_survival kills 5: add kill_heal$", "kill-heal"],
	["s2_02_day_one", "-", "^at 30: give shotgun$", "weapons (shotgun)"],
	["s2_02_day_one", "-", "^at 50: spawn splitter 2$", "splitter"],
]

const BotRuns := preload("res://tools/bot_runs.gd")

var game: Main
var _tuning := {}


func before_each() -> void:
	Telemetry.log_path = TEST_LOG
	_tuning["hard_max_enemies"] = Tuning.hard_max_enemies


func after_each() -> void:
	await wait_physics_frames(2)   # deferred spawns land before the game is freed (no orphan)
	for k: String in _tuning:
		Tuning.set(k, _tuning[k])
	assert_false(FileAccess.file_exists(TEST_LOG), "no telemetry written, not even to the scratch log")
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.invincible = false
	CampaignDB.active = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null


## S8 on path `p` (fork_path answered first, as the GUT helpers must: C2.9).
func _s8(p: StringName) -> Main:
	SaveGame.go_inert()
	assert_true(CampaignDB.answer_fork(&"fork_path", StringName("path_%s" % p)))
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(S8))
	var g: Main = load("res://main.tscn").instantiate()
	add_child_autofree(g)
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	game = g
	RunState.invincible = true
	return g


func _at(seconds: float) -> void:
	game.run_loop.goal_clock = seconds - 0.01
	await wait_physics_frames(3)


func _lo() -> Loadout:
	return Component.find(game.player, Loadout) as Loadout


func _texts(id: StringName) -> Array[String]:
	var s := CampaignDB.get_session(id)
	var out: Array[String] = []
	out.append_array(s.intro)
	out.append_array(s.cues)
	out.append("hp_floor=%d" % s.hp_floor)
	return out


# --- Data ------------------------------------------------------------------------------

func test_s8_validates_in_the_campaign() -> void:
	var s := CampaignDB.get_session(S8)
	assert_eq(s.problems(), [] as Array[String])
	assert_eq(CampaignDB.problems(), [] as Array[String])
	assert_eq(CampaignDB.index_of(S8), 8, "after S7 (D4); S9 follows since M48b")
	# M47.6d2 (PLAN v9.4 0.8, design 3): a fixed set per path, no survive clock; a hidden cap.
	assert_eq([s.stage, s.path, s.goal, s.end_kinds(), s.time_limit, s.hp_floor, s.bump, s.fork],
			[2, &"fork:fork_path", SessionDef.CLEAR, [SessionDef.CLEAR] as Array[StringName], 180.0, 0, &"patch", &""])
	assert_eq(s.enemy_total_by_path, {&"arsenal": 100, &"auto": 180, &"survival": 55} as Dictionary[StringName, int])
	assert_eq(s.enemy_total, 100, "an unanswered path plays Arcade's set")
	assert_true(s.goal_by_path.is_empty(), "M47.2's 90 s Survival clock is gone")
	assert_false(s.fresh_start, "S8 carries the player from S7")
	assert_eq(s.basics, CampaignDB.get_session(&"s1_06_playground").basics)
	assert_eq(s.notes, PackedStringArray(["Day one", "The shotgun", "New enemy: the splitter"]))
	assert_true(&"fork_path" in CampaignDB.get_session(S7).asked_forks(), "asked earlier, in S7")


func test_quick_draw_comes_before_its_line() -> void:
	var cues := CampaignDB.get_session(S8).cues
	var add := Array(cues).find("answer:path_arsenal at 20: add quick_draw")
	var say := -1
	for i in cues.size():
		if cues[i].begins_with("answer:path_arsenal at 20: say"):
			say = i
	assert_true(add >= 0 and add < say, "the M46 carry-over: the add, then the say")


## M50.1a: the line reads Arsenal's pack cadence (PathDef.pack_every, 6).
func test_the_card_line_reads_arsenals_first_card() -> void:
	assert_eq(PathDB.get_def(&"arsenal").pack_every, 6, "a pack every 6 kills")
	var said := "\n".join(CampaignDB.get_session(S8).cues)
	assert_string_contains(said, "Six kills, one pack. {key:open_pack} opens it.")   # M50.6: packs stack
	assert_string_contains(said, "Two cards max.")



## G10: the 3.5 audit for S7-S8.
func test_every_s7_s8_audit_row_has_its_cue() -> void:
	for row: Array in AUDIT:
		var re := RegEx.create_from_string(row[2])
		var hit := false
		for t in _texts(StringName(row[0])):
			if re.search(t) != null:
				hit = true
				break
		assert_true(hit, "%s / %s: %s (%s)" % row)
	var covered := {}
	for row: Array in AUDIT:
		covered[row[3]] = true
	for need in ["Arsenal hand", "switching", "card meter", "quick-draw", "Auto fire button off", "crowd overlay",
			"gems / LV", "drops + crates", "swap", "sidearm fallback", "kill-heal", "weapons (shotgun)",
			"weapon ranks (card text)", "splitter", "hp_floor 1"]:
		assert_true(covered.has(need), "the audit covers " + need)


# --- M47.6d2 (PLAN v9.4 0.8: no survive timer; a fixed set per path) ---------------------

## Was M47.2's "Survival 90 s, the others 120 s": now each path plays its own fixed set, the
## spawner's budget, and the session goes on past the old clocks until the set is dead.
func test_s8_clears_a_fixed_set_per_path() -> void:
	var s := CampaignDB.get_session(S8)
	assert_eq([s.enemy_total_for(&"arsenal"), s.enemy_total_for(&"auto"), s.enemy_total_for(&"survival"),
			s.enemy_total_for(&"")], [100, 180, 55, 100])
	for p in PATHS:
		await _s8(p)
		var want := s.enemy_total_for(p)
		assert_eq([game.spawner.budget, game.run_loop.enemy_total, int(game.run_loop.goal_value)], [want, want, want],
				"%s: the run plays its %d" % [p, want])
		assert_eq(game.run_loop.goal_text(), "", "%s: no goal text" % p)
		assert_eq(game.hud.goal_shown(), "", "M47.6c1: no campaign HUD shows it")
		await _at(125.0)
		assert_eq(game.run_loop.phase, RunLoop.PLAY, "%s: still playing past the old 120 s clock" % p)
		game.run_loop.end(&"win")   # the record is written at the end
		var rec := CampaignDB.telemetry_record(s, game.genre.run_record(), &"won", 0, &"next")
		assert_eq(String(Dictionary(rec.get("goal", {})).get("kind", "")), "clear", "telemetry: a clear goal")
		assert_eq(int(rec.get("enemy_total", -1)), want, "telemetry: the path's set")
		game.free()


## The hidden cap (180 s, never shown) ends a set the player never finishes (stopped, limit).
func test_s8_stops_at_its_hidden_cap() -> void:
	await _s8(&"arsenal")
	await _at(179.0)
	assert_eq(game.run_loop.phase, RunLoop.PLAY)
	await _at(180.5)
	assert_true(game.run_loop.is_over(), "stopped at the cap")
	assert_eq(game.run_loop.end_reason, &"limit")


## The intro no longer names a clock ("Two minutes" / "Ninety seconds"): one wave on every path.
func test_the_intro_says_one_wave_on_every_path() -> void:
	var s := CampaignDB.get_session(S8)
	for p in PATHS:
		SaveGame.go_inert()
		CampaignDB.answer_fork(&"fork_path", StringName("path_%s" % p))
		var intro := "\n".join(Line.passing(s.intro_lines(), CampaignDB.line_context(s)).map(
				func(l: Line) -> String: return l.text))
		assert_string_contains(intro, "One wave. I'll build it properly this time.")
		assert_false(intro.contains("Ninety seconds") or intro.contains("Two minutes"), "%s: %s" % [p, intro])


## "Almost there" (last_seconds) is survive-only: S8 has no clock left to count down.
func test_last_seconds_stays_silent_in_s8() -> void:
	for p in PATHS:
		await _s8(p)
		await _at(86.0)
		assert_eq(game.reactions._survive_left(), -1.0, "%s: no survive clock" % p)
		game.free()


func test_enemy_total_by_path_problems() -> void:
	var s := CampaignDB.get_session(S8).duplicate() as SessionDef
	assert_eq(s.problems(), [] as Array[String])
	s.enemy_total_by_path = {&"nowhere": 10}
	assert_string_contains(" ".join(s.problems()), "enemy_total_by_path: unknown path nowhere")
	s.enemy_total_by_path = {&"auto": -1}
	assert_string_contains(" ".join(s.problems()), "enemy_total_by_path: auto must be >= 0")
	s.enemy_total_by_path = {&"auto": 50}
	s.goal = SessionDef.SURVIVE
	s.goal_value = 120.0
	s.time_limit = 0.0
	s.enemy_total = -1
	assert_string_contains(" ".join(s.problems()), "enemy_total_by_path is for clear endings only")
	var pathless := CampaignDB.get_session(&"s1_04_level").duplicate() as SessionDef
	pathless.enemy_total_by_path = {&"auto": 20}
	assert_string_contains(" ".join(pathless.problems()), "enemy_total_by_path needs a path")
	var tryout := CampaignDB.get_session(S7).duplicate() as SessionDef
	tryout.enemy_total_by_path = {&"auto": 100}
	assert_string_contains(" ".join(tryout.problems()), "enemy_total_by_path is not for a tryout")
	# A kills-N spawn cue must be able to fire on the smallest set (Survival's 55 + the 2 splitters).
	var k := CampaignDB.get_session(S8).duplicate() as SessionDef
	k.cues.append("kills 60: spawn chaser 1")
	k._parsed = false
	assert_string_contains(" ".join(k.problems()), "can never fire (at most 57 enemies before it)")


## M47.2's goal_by_path rules still hold on a survive session (S8 as it was, by hand).
func _survive_s8() -> SessionDef:
	var s := CampaignDB.get_session(S8).duplicate() as SessionDef
	s.goal = SessionDef.SURVIVE
	s.goal_value = 120.0
	s.time_limit = 0.0
	s.enemy_total = -1
	s.enemy_total_by_path = {}
	return s


func test_goal_by_path_problems() -> void:
	var s := _survive_s8()
	s.goal_by_path = {&"survival": 90.0}
	assert_eq(s.problems(), [] as Array[String])
	s.goal_by_path = {&"nowhere": 90.0}
	assert_string_contains(" ".join(s.problems()), "goal_by_path: unknown path nowhere")
	s.goal_by_path = {&"auto": 0.0}
	assert_string_contains(" ".join(s.problems()), "goal_by_path: auto must be > 0")
	s.goal_by_path = {&"survival": 40.0}
	assert_string_contains(" ".join(s.problems()), "cue 'at 50: spawn splitter 2' is after the goal's end (40.0 s on survival)")
	assert_false(" ".join(s.problems()).contains("answer:path_arsenal at 20"), "a cue of another path is not checked")
	s.goal_by_path = {&"survival": 90.0}
	s.cues.append("answer:path_survival at 95: say happy: Late.")
	s._parsed = false
	assert_string_contains(" ".join(s.problems()), "after the goal's end (90.0 s on survival)")
	var pathless := CampaignDB.get_session(&"s1_04_level").duplicate() as SessionDef
	pathless.goal_by_path = {&"auto": 20.0}
	assert_string_contains(" ".join(pathless.problems()), "goal_by_path needs a path")
	var tryout := CampaignDB.get_session(S7).duplicate() as SessionDef
	tryout.goal_by_path = {&"auto": 100.0}
	assert_string_contains(" ".join(tryout.problems()), "goal_by_path is not for a tryout")
	for id: StringName in [&"s1_00_nothing", &"s1_01_move"]:
		assert_eq(CampaignDB.get_session(id).problems(), [] as Array[String], "%s: fine" % id)
	# M47.6c1: S0 and S1 end on their script now (a late cue only moves it); a stop goal by hand.
	var late := CampaignDB.get_session(&"s1_01_move").duplicate() as SessionDef
	late.goal = SessionDef.STOP
	late.end_after = 5.0
	late.cues.append("at %d: say happy: Too late." % int(late.goal_value + Tuning.smoke_stop_read + 1.0))
	late._parsed = false
	assert_string_contains(" ".join(late.problems()), "after the goal's end")


## bot_runs' --session-set goal_value replaces goal_by_path (it would shadow it on Survival).
func test_a_session_set_goal_value_replaces_goal_by_path() -> void:
	var copy := _survive_s8()
	copy.goal_by_path = {&"survival": 90.0}
	BotRuns.set_session_field(copy, "goal_value", 60.0)
	assert_eq(copy.goal_for(&"survival"), 60.0)
	assert_eq(copy.goal_for(&"arsenal"), 60.0)


## M47.6d2: likewise enemy_total replaces enemy_total_by_path.
func test_a_session_set_enemy_total_replaces_enemy_total_by_path() -> void:
	var copy := CampaignDB.get_session(S8).duplicate() as SessionDef
	BotRuns.set_session_field(copy, "enemy_total", 30.0)
	assert_eq([copy.enemy_total_for(&"survival"), copy.enemy_total_for(&"auto")], [30, 30])
	assert_eq(CampaignDB.get_session(S8).enemy_total_for(&"survival"), 55, "the shipped session is untouched")


# --- Per path ------------------------------------------------------------------------------

func test_the_conditioned_intro_and_cues_load_per_path() -> void:
	var mine := {&"arsenal": "Cards. Today", &"auto": "Auto. Don't touch", &"survival": "Scavenger. You get a revolver"}
	var s := CampaignDB.get_session(S8)
	for p in PATHS:
		SaveGame.go_inert()
		CampaignDB.answer_fork(&"fork_path", StringName("path_%s" % p))
		var ctx := CampaignDB.line_context(s)
		var intro := Line.passing(s.intro_lines(), ctx).map(func(l: Line) -> String: return l.text)
		assert_eq(intro.size(), 2, "%s: its line and the common one" % p)
		for q: StringName in mine:
			assert_eq(intro.any(func(t: String) -> bool: return t.begins_with(mine[q])), q == p, "%s intro, %s line" % [p, q])
		var cues := s.cue_list().filter(func(c: Cue) -> bool: return Line.condition_holds(c.cond, ctx))
		for c: Cue in cues:
			assert_true(c.cond == "" or c.cond == "answer:path_%s" % p
					or (c.cond.begins_with("!answer:path_") and c.cond != "!answer:path_%s" % p), "%s: %s" % [p, c.cond])
		await _s8(p)
		assert_eq(RunState.live_path(), p)
		var start := "revolver:1" if p == &"survival" else "pistol:1"   # M47.6d1: Survival's revolver
		assert_eq(_lo().summary(), start, "%s: power stays in its session (%s)" % [p, start])
		game.free()


func test_arsenal_cards_at_10_and_quick_draw_at_20() -> void:
	await _s8(&"arsenal")
	assert_null(game.path_runner.meter())
	await _at(10.0)
	assert_not_null(game.path_runner.meter(), "the card meter at 10 s")
	assert_eq(_lo().quick_draw_mult, 1.0)
	await _at(20.0)
	assert_gt(_lo().quick_draw_mult, 1.0, "quick-draw at 20 s")


func test_auto_levelups_at_10_and_the_crowd_at_14() -> void:
	await _s8(&"auto")
	await _at(10.0)
	assert_not_null(game.path_runner.meter(), "levels at 10 s")
	assert_null(game.path_runner.overlay())
	await _at(14.0)
	assert_not_null(game.path_runner.overlay(), "the crowd at 14 s")


func test_survival_crates_at_10_and_kill_heal_at_5_kills() -> void:
	await _s8(&"survival")
	var crates := func() -> int:
		return get_tree().get_nodes_in_group(&"pickup").filter(func(p: Node) -> bool: return (p as Pickup).crate).size()
	assert_eq(crates.call(), 0)
	await _at(10.0)
	assert_eq(crates.call(), 2, "two crates at 10 s")
	var drops: Node = game.path_runner.get(&"_drops")
	assert_false(drops.get(&"heal_on"))
	game.spawner.enabled = false
	var e := (load("res://entities/enemy_chaser.tscn") as PackedScene).instantiate() as Node2D
	add_child_autofree(e)
	e.set_physics_process(false)
	e.global_position = Vector2(-4000, -4000)
	var kill := func() -> void: EventBus.enemy_killed.emit(e, DamageInfo.make(1.0, &"shot", &"player"))
	var h := Component.find(game.player, Health) as Health
	h.hp_ratio = (h.max_hp() - 2.0) / h.max_hp()
	for i in 5:
		kill.call()
	assert_eq(RunState.kills, 5, "real kills")
	await wait_physics_frames(3)
	assert_true(drops.get(&"heal_on"), "kill-heal armed at 5 kills")
	assert_eq(game.path_runner.heals(), 0, "no heal on the add tick")
	for i in 4:
		kill.call()
	assert_eq(game.path_runner.heals(), 0, "kill 9: none yet (counted from the arming)")
	kill.call()
	assert_eq(game.path_runner.heals(), 1, "kill 10: the first heal")
	assert_almost_eq(h.hp(), h.max_hp() - 1.0, 0.001)


func test_give_shotgun_per_path() -> void:
	await _s8(&"arsenal")
	await _at(30.0)
	assert_ne(_lo().held(&"shotgun"), null, "Arsenal: a free card")
	game.free()
	await _s8(&"auto")
	await _at(30.0)
	assert_eq(game.path_runner.get(&"_first"), &"shotgun", "Auto: first in the next level-up")
	game.free()
	await _s8(&"survival")
	await _at(30.0)
	var sg := get_tree().get_nodes_in_group(&"pickup").filter(func(p: Node) -> bool:
		return (p as Pickup).weapon_id == &"shotgun" and (p as Pickup).crate)
	assert_gt(sg.size(), 0, "Survival: a crate near the player")


## G9: nothing carries the shotgun before its give (S8 x 3 paths), and S7's live pool.
func test_no_pick_drop_or_crate_carries_the_shotgun_before_its_give() -> void:
	for p in PATHS:
		await _s8(p)
		game.player.set_bot(true)
		var seen := false
		while game.run_loop.goal_clock < 29.5:
			await wait_physics_frames(1)
			if RunState.is_paused_for(PickPanel.PAUSE) and game.pick_panel != null:
				for c in game.pick_panel.offer.cards:
					if str(c).contains("shotgun"):
						seen = true
				if game.pick_panel.can_choose():
					game.pick_panel.choose(0)
			for pk in get_tree().get_nodes_in_group(&"pickup"):
				if (pk as Pickup).weapon_id == &"shotgun":
					seen = true
			if _lo().held(&"shotgun") != null:
				seen = true
		assert_false(seen, "%s: no shotgun before 30 s" % p)
		var pooled: bool = game.path_runner.offer_pool().has(&"shotgun")
		assert_false(pooled, str(p) + ": not in the pool before its give")
		if p == &"survival":
			var drops: Node = game.path_runner.get(&"_drops")
			for i in 200:
				assert_ne(drops.call(&"_draw_weapon"), &"shotgun")
		game.free()
	SaveGame.go_inert()
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(S7))
	var g7: Main = load("res://main.tscn").instantiate()
	add_child_autofree(g7)
	g7.stage_card.skip()
	await wait_physics_frames(2)
	g7.path_runner.swap_now(&"survival")
	var pooled7: bool = g7.path_runner.offer_pool().has(&"shotgun")
	assert_false(pooled7, "S7: outside the live pool before its give")


# --- The splitter (1.9) --------------------------------------------------------------------

func _splitters() -> Array:
	return get_tree().get_nodes_in_group(&"enemy").filter(func(e: Node) -> bool: return e.get(&"variant") == &"splitter")


func _minis() -> Array:
	return get_tree().get_nodes_in_group(&"enemy").filter(func(e: Node) -> bool: return int(e.get(&"generation")) == 1)


func _kill(e: Node) -> void:
	var h := Component.find(e, Health) as Health
	h.take(DamageInfo.make(999.0, &"shot", &"player"))


func test_the_splitter_at_50_s_splits_into_two_minis() -> void:
	await _s8(&"arsenal")
	game.spawner.enabled = false
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()
	await wait_physics_frames(2)
	await _at(50.0)
	var sp := _splitters()
	assert_eq(sp.size(), 2, "spawn splitter 2: two chasers marked splitter")
	assert_eq((sp[0] as Node).get(&"archetype"), &"chaser")
	_kill(sp[0])
	await wait_physics_frames(3)
	var minis := _minis()
	assert_eq(minis.size(), 2)
	for m: Node in minis:
		assert_almost_eq(float(m.get(&"size_mult")), 0.5, 0.001)
		assert_almost_eq((Component.find(m, Health) as Health).max_hp(), 1.0, 0.001)
	_kill(minis[0])
	await wait_physics_frames(3)
	assert_eq(_minis().size(), 1, "a mini's death spawns nothing")


func test_the_split_is_refused_at_the_cap_and_logged() -> void:
	await _s8(&"arsenal")
	game.spawner.enabled = false
	await wait_physics_frames(1)
	assert_true(game.genre.spawn_archetype(&"splitter", 1))
	await wait_physics_frames(2)
	Tuning.hard_max_enemies = RunState.count(&"enemy")
	_kill(_splitters()[0])
	await wait_physics_frames(3)
	assert_eq(_minis().size(), 0)
	assert_eq(RunState.run_log.filter(func(e: Dictionary) -> bool: return e.event == &"split_refused").size(), 2)


func test_minis_keep_1_hp_under_autos_hp_overlay() -> void:
	await _s8(&"auto")
	game.spawner.enabled = false
	RunState.rules.enemy_hp_mult = 0.7
	assert_true(game.genre.spawn_archetype(&"splitter", 1))
	await wait_physics_frames(2)
	_kill(_splitters()[0])
	await wait_physics_frames(3)
	assert_eq(_minis().size(), 2, "the split happened (never green on no minis)")
	for m: Node in _minis():
		assert_almost_eq((Component.find(m, Health) as Health).max_hp(), 1.0, 0.001, "1 HP, not 0")


func test_a_variant_is_never_a_fork_unlock() -> void:
	assert_false(&"splitter" in Unlocks.ARCHETYPES)
	assert_eq(load("res://enemies/variants/splitter.tres").problems(), [] as Array[String])


# --- M48b (v9.2 0.6): the two prototype lines, no try-on, no fork -------------------------

## S8 says the game still looks like a prototype (80 s, Survival 74 s), then promises a
## drawing (86 s, Survival 80 s); the debrief ends on the drawing. M47.6d2: a set has no clock,
## so the bots' median clear (>= 90 s on every path, the gate) is what keeps these in.
func test_s8_promises_a_drawing_per_path_before_the_goal() -> void:
	var s := CampaignDB.get_session(S8)
	var want := {&"arsenal": [80.0, 86.0], &"auto": [80.0, 86.0], &"survival": [74.0, 80.0]}
	for p: StringName in want:
		SaveGame.go_inert()
		CampaignDB.answer_fork(&"fork_path", StringName("path_%s" % p))
		var ctx := CampaignDB.line_context(s)
		var times: Array = []
		for c in s.cue_list():
			if c.action == &"say" and Line.condition_holds(c.cond, ctx) and (c.line.text.contains("prototype")
					or c.line.text.contains("learn to draw")):
				times.append(c.value)
		assert_eq(times, want[p], String(p))
		assert_lt(float(times[1]), 90.0, "%s: before the gate's 90 s median clear" % p)
	assert_eq(s.debrief[s.debrief.size() - 1], "thinking: Next time, I'll have something to show you. A drawing. My first.")
	assert_eq([s.look, s.skin, s.fork, s.more_forks], ["", &"", &"", [] as Array[StringName]], "no look, no try-on, no fork")
	assert_false(s.cue_list().any(func(c: Cue) -> bool: return c.action in [&"look", &"skin"]))


# --- The lines file (0.4) -----------------------------------------------------------------

func test_lines_file_is_up_to_date() -> void:
	var now: String = load("res://campaign/lines_render.gd").call(&"render")
	assert_eq(FileAccess.get_file_as_string("res://campaign/lines_stage2.md"), now,
			"regenerate: godot --headless --path . -s tools/lines_file.gd")
	assert_string_contains(now, "Version one. Your guns are cards.")
	assert_string_contains(now, "Which shooter do we make?")
