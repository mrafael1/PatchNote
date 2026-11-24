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
	["s2_01_tryout", "arsenal", "^at 13: path arsenal ", "Arsenal hand"],
	["s2_01_tryout", "arsenal", "\\{key:weapon_prev\\} and \\{key:weapon_next\\} to switch", "switching"],
	["s2_01_tryout", "arsenal", "^at 15: add cards$", "card meter"],
	["s2_01_tryout", "arsenal", "^at 15: give shotgun$", "weapons (shotgun)"],
	["s2_01_tryout", "survival", "^at 56: path survival ", "Survival"],
	["s2_01_tryout", "survival", "^at 58: add pickups$", "drops"],
	["s2_01_tryout", "survival", "^at 61: drop shotgun$", "swap"],
	["s2_01_tryout", "survival", "Ammo runs out", "sidearm fallback"],
	["s2_01_tryout", "survival", "^at 74: add kill_heal$", "kill-heal"],
	["s2_01_tryout", "auto", "^at 99: path auto ", "Auto auto-fire / fire button off"],
	["s2_01_tryout", "auto", "^at 107: add crowd$", "crowd overlay"],
	["s2_01_tryout", "auto", "^at 112: add levelups$", "gems / LV"],
	["s2_01_tryout", "-", "hp_floor=1", "hp_floor 1"],
	["s2_02_day_one", "arsenal", "^answer:path_arsenal at 10: add cards$", "card meter"],
	["s2_02_day_one", "arsenal", "Rank pips", "weapon ranks (card text)"],
	["s2_02_day_one", "arsenal", "^answer:path_arsenal at 20: add quick_draw$", "quick-draw"],
	["s2_02_day_one", "auto", "Don't touch the trigger", "Auto fire button off"],
	["s2_02_day_one", "auto", "^answer:path_auto at 10: add levelups$", "gems / LV"],
	["s2_02_day_one", "auto", "^answer:path_auto at 14: add crowd$", "crowd overlay"],
	["s2_02_day_one", "survival", "^answer:path_survival at 10: add pickups$", "drops + crates"],
	["s2_02_day_one", "survival", "Walk over another gun to swap", "swap"],
	["s2_02_day_one", "survival", "pistol back", "sidearm fallback"],
	["s2_02_day_one", "survival", "^answer:path_survival kills 5: add kill_heal$", "kill-heal"],
	["s2_02_day_one", "-", "^at 30: give shotgun$", "weapons (shotgun)"],
	["s2_02_day_one", "-", "^at 50: spawn splitter 2$", "splitter"],
]

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
	assert_eq(CampaignDB.index_of(S8), 8, "after S7, the last playable session (D4)")
	assert_eq([s.stage, s.path, s.goal, s.goal_value, s.hp_floor, s.bump, s.fork],
			[2, &"fork:fork_path", SessionDef.SURVIVE, 120.0, 0, &"patch", &""])
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


func test_the_card_line_reads_arsenals_first_card() -> void:
	var first := PathDB.get_def(&"arsenal").threshold(1)
	assert_eq(first, 25, "M46 D1: 25 kills")
	var said := "\n".join(CampaignDB.get_session(S8).cues)
	assert_string_contains(said, "Twenty-five kills, a new card.")


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


# --- Per path ------------------------------------------------------------------------------

func test_the_conditioned_intro_and_cues_load_per_path() -> void:
	var mine := {&"arsenal": "Cards. Today", &"auto": "Auto. Don't touch", &"survival": "Scavenger. You get a pistol"}
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
			assert_true(c.cond == "" or c.cond == "answer:path_%s" % p, "%s: %s" % [p, c.cond])
		await _s8(p)
		assert_eq(RunState.live_path(), p)
		assert_eq(_lo().summary(), "pistol:1", "%s: power stays in its session (pistol:1)" % p)
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


# --- The lines file (0.4) -----------------------------------------------------------------

func test_lines_file_is_up_to_date() -> void:
	var now: String = load("res://campaign/lines_render.gd").call(&"render")
	assert_eq(FileAccess.get_file_as_string("res://campaign/lines_stage2.md"), now,
			"regenerate: godot --headless --path . -s tools/lines_file.gd")
	assert_string_contains(now, "Version one. Your guns are cards.")
	assert_string_contains(now, "Which shooter do we make?")
