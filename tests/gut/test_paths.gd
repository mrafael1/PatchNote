extends GutTest
## M45a (PLAN v9 1.2, 1.5): path plumbing and the Auto taste. PathDef / PathDB, the live
## path, the crowd overlay (owner &"path"), Auto's fire, Pickup and the gems, the level
## meter, PickOffer / PickPanel and the pool rule, the PathRunner (pause rule, the `path`
## cue's warning and swap), the data checks (path basics, [tag], unbuilt paths), the S7
## stub's taste and the S8 draft. G6 and G7 live here by name.

const CHASER := preload("res://entities/enemy_chaser.tscn")
const PICKUP := preload("res://entities/pickup.tscn")
const Gems := preload("res://paths/auto/gems.gd")
const LevelMeter := preload("res://paths/auto/level_meter.gd")
const LevelWidget := preload("res://paths/auto/level_widget.gd")
const RulesDump := preload("res://tests/gut/rules_dump.gd")
const T := 48.0
const OPEN := Vector2(34, 20)
const TEST_DIR := "user://save_paths_test/"
## The telemetry log while these tests run: a scratch file, never user://playtest/runs.jsonl.
const TEST_LOG := "user://save_paths_test/runs.jsonl"
const STUB := &"s7_auto_stub"

var game: Main
var player: CharacterBody2D
var _links: Array = []


func before_each() -> void:
	_stub_in()
	Telemetry.log_path = TEST_LOG


func after_each() -> void:
	_stub_out()
	for l: Array in _links:
		if (l[0] as Signal).is_connected(l[1]):
			(l[0] as Signal).disconnect(l[1])
	_links.clear()
	# Review M45a: no test here writes telemetry; the scratch file must never appear.
	assert_false(FileAccess.file_exists(TEST_LOG), "no telemetry written, not even to the scratch log")
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.invincible = false
	CampaignDB.active = false
	while _draft_in_list() != null:
		CampaignDB.campaign.sessions.erase(_draft_in_list())
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(TEST_LOG)


func _on(sig: Signal, c: Callable) -> void:
	sig.connect(c)
	_links.append([sig, c])


func _auto() -> PathDef:
	return PathDB.get_def(&"auto")


## The legacy arena (no session): spawner and director off, no enemies, the player in the open.
func _arena() -> void:
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	game.director.enabled = false
	await wait_physics_frames(2)
	_clear_enemies()
	await wait_physics_frames(1)
	player = game.player
	player.set_input(load("res://tests/gut/fixtures.gd").ScriptedInput.new())
	await wait_physics_frames(1)   # the old input's queue_free lands (no orphan)
	player.global_position = OPEN * T
	player.velocity = Vector2.ZERO
	RunState.invincible = true


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()


## A campaign session, jumped to (inert save), its stage card skipped.
func _session_game(id: StringName) -> Main:
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var g: Main = load("res://main.tscn").instantiate()
	add_child_autofree(g)
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	game = g
	player = g.player
	return g


## The S8 draft as the session (it is not in the campaign list).
func _draft() -> SessionDef:
	return load("res://campaign/drafts/s8_draft.tres") as SessionDef


func _draft_game() -> Main:
	var d := _draft()
	CampaignDB.campaign.sessions.insert(CampaignDB.cooking_index(), d)
	var g := await _session_game(d.id)
	return g


func _loadout() -> Loadout:
	return Component.find(player, Loadout) as Loadout


func _frozen_chaser(tile: Vector2) -> Node2D:
	var e := RunState.spawn(CHASER, tile * T) as Node2D
	await wait_physics_frames(2)
	e.set_physics_process(false)
	e.mover.wish = Vector2.ZERO
	e.velocity = Vector2.ZERO
	e.health.base_max_hp = 100.0
	return e


## Opens a pick now (no waiting on the physics tick) and chooses card i.
func _pick(runner: PathRunner, i := 0) -> PickOffer:
	runner.want_pick()
	runner._open_offer()
	var offer := game.pick_panel.offer
	game.pick_panel._unlock()
	game.pick_panel.choose(mini(i, offer.cards.size() - 1))
	return offer


# --- Data -----------------------------------------------------------------------------------

func test_the_path_data_is_valid() -> void:
	assert_eq(PathDB.problems(), [] as Array[String])
	assert_eq(PathDB.ids(), [&"arsenal", &"auto", &"survival"] as Array[StringName], "Auto (M45a), Arsenal (M46), Survival (M47)")
	var a := _auto()
	assert_eq(a.fire_mode, &"auto_all")
	assert_eq(a.growth, &"levelups")
	assert_eq(a.start, [&"pistol"] as Array[StringName])
	assert_eq(a.max_slots, 4)
	assert_eq(a.max_passives, 2)
	assert_eq(a.basics, [&"levelups", &"crowd"] as Array[StringName])
	assert_eq(a.kill_goal_mult, 2.0)
	assert_eq(PathDB.owner_of_basic(&"crowd"), &"auto")
	assert_eq(PathDB.owner_of_basic(&"dash"), &"")
	assert_null(PathDB.get_def(&""))
	assert_true(&"levelups" in Unlocks.CAMPAIGN_BASICS and &"crowd" in Unlocks.CAMPAIGN_BASICS)


func test_thresholds_level_list_then_plus_twenty_and_the_taste_list() -> void:
	var a := _auto()
	assert_eq(a.threshold(1, false), 3)
	assert_eq(a.threshold(8, false), 84)
	assert_eq(a.threshold(9, false), 84 + PathDef.THRESHOLD_STEP)
	assert_eq(a.threshold(1, true), 6, "a tryout: one level-up at 6 gems")
	assert_eq(a.threshold(2, true), -1, "and no more")


func test_live_path_reads_the_session_then_the_override() -> void:
	assert_eq(RunState.live_path(), &"", "no session: no path")
	RunState.session = _draft()
	assert_eq(RunState.live_path(), &"auto")
	assert_eq(RunState.path_def(), _auto())
	RunState.session_path = &"off"
	assert_eq(RunState.live_path(), &"", "off: the legacy pistol")
	RunState.reset(0)
	assert_eq(RunState.session_path, &"", "reset clears the override")


func test_the_s8_draft_and_the_stub_are_valid() -> void:
	assert_eq(_draft().problems(), [] as Array[String])
	assert_eq(CampaignDB.get_session(STUB).problems(), [] as Array[String])
	assert_eq(CampaignDB.problems(CampaignDB.campaign), [] as Array[String])


# --- The overlay ---------------------------------------------------------------------------

func test_the_crowd_overlay_numbers_owner_and_reverse() -> void:
	RunState.reset(1)
	var before := RulesDump.fields(RunState.rules)
	var build := RunState.build_number
	var rate := RunState.rules.spawn_rate_mult
	var cap := RunState.rules.max_enemies
	var hp := RunState.rules.enemy_hp_mult
	var o := PathOverlay.make(_auto())
	assert_eq(o.id, &"path_auto_crowd")
	assert_true(RunState.add_ai(o, &"path"))
	assert_almost_eq(RunState.rules.spawn_rate_mult, rate * 1.6, 0.0001)
	assert_eq(RunState.rules.max_enemies, cap + roundi(cap * 0.5))
	assert_almost_eq(RunState.rules.enemy_hp_mult, hp * 0.7, 0.0001)
	assert_eq(RunState.build_number, build + 1)
	assert_eq(RunState.expire_ai(&"path").size(), 1)
	assert_eq(RulesDump.fields(RunState.rules), before, "reversible")


# --- Auto fire -----------------------------------------------------------------------------

func test_apply_path_gives_the_pistol_at_rank_1_and_auto_mode() -> void:
	await _arena()
	var lo := _loadout()
	lo.give(&"pistol")   # rank 2 on the old path
	lo.apply_path(_auto())
	assert_eq(lo.summary(), "pistol:1")
	assert_eq(lo.fire_mode, &"auto_all")
	assert_eq(lo.max_slots, 4)
	lo.apply_path(null)
	assert_eq(lo.fire_mode, &"manual_one")
	assert_eq(lo.max_slots, 3)


func test_auto_fires_each_slot_at_a_target_in_range_only() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.give(&"shotgun")
	await wait_physics_frames(3)
	assert_eq([lo.slots[0].shots, lo.slots[1].shots], [0, 0], "no enemy: nothing fires")
	var far := await _frozen_chaser(OPEN + Vector2(Tuning.auto_attack_range / T + 3.0, 0))
	await wait_physics_frames(3)
	assert_eq([lo.slots[0].shots, lo.slots[1].shots], [0, 0], "out of range")
	far.queue_free()
	await _frozen_chaser(OPEN + Vector2(4, 0))
	await wait_physics_frames(1)
	assert_eq([lo.slots[0].shots, lo.slots[1].shots], [1, 1], "the player's tick fires both slots")
	assert_eq(lo.auto_tick(), 0, "then their cooldowns")


func test_the_fire_button_is_dead_on_auto() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	player.input.set(&"fire", true)
	player.input.set(&"aim_dir", Vector2.RIGHT)
	await wait_physics_frames(10)
	assert_eq(get_tree().get_nodes_in_group(&"player_projectile").size(), 0, "no target, no shot, whatever the button")


func test_a_blast_weapon_aims_at_the_densest_spot() -> void:
	await _arena()
	var lone := await _frozen_chaser(OPEN + Vector2(3, 0))
	var pack: Array[Node2D] = []
	for dy in [-1.0, 0.0, 1.0]:
		pack.append(await _frozen_chaser(OPEN + Vector2(-6, dy * 0.6)))
	assert_eq(AutoFire.nearest(player, Tuning.auto_attack_range), lone)
	assert_true(AutoFire.densest(player, Tuning.auto_attack_range, 2.0 * T) in pack)


# --- Pickups and gems ---------------------------------------------------------------------

func _pickup(kind: StringName, tile: Vector2, value := 1) -> Pickup:
	return RunState.spawn(PICKUP, tile * T, {"pickup_kind": kind, "value": value}) as Pickup


func test_a_gem_pulls_flies_and_is_taken() -> void:
	await _arena()
	var taken: Array = []
	_on(EventBus.pickup_taken, func(k: StringName, _id: StringName) -> void: taken.append(k))
	var g := _pickup(&"gem", OPEN + Vector2(2, 0))
	await wait_physics_frames(1)
	assert_true(g.is_in_group(Pickup.GEM_GROUP))
	assert_eq(g.pull_radius(), Tuning.pickup_pull_gem)
	await wait_physics_frames(40)
	assert_eq(taken, [&"gem"])
	assert_false(is_instance_valid(g) and not g.is_queued_for_deletion())


func test_a_far_gem_never_expires_and_other_pickups_blink_then_go() -> void:
	await _arena()
	var g := _pickup(&"gem", OPEN + Vector2(12, 0))
	var other := _pickup(&"heal", OPEN + Vector2(-11, 0))
	g.age = Tuning.pickup_lifetime + 5.0
	other.age = Tuning.pickup_lifetime - 0.5
	await wait_physics_frames(2)
	await wait_physics_frames(40)
	assert_true(is_instance_valid(g) and not g.is_queued_for_deletion(), "gems stay")
	assert_false(is_instance_valid(other) and not other.is_queued_for_deletion(), "a heal expires")


func test_kills_drop_gems_and_big_enemies_drop_three() -> void:
	await _arena()
	var gems := Gems.new()
	add_child_autofree(gems)
	var got: Array = []
	gems.gem_taken.connect(func(v: int) -> void: got.append(v))
	var e := await _frozen_chaser(OPEN + Vector2(10, 0))
	var info := DamageInfo.new()
	info.faction = &"player"
	gems._on_enemy_killed(e, info)
	await wait_physics_frames(1)
	var dropped := get_tree().get_nodes_in_group(Pickup.GEM_GROUP)
	assert_eq(dropped.size(), 1)
	assert_eq((dropped[0] as Pickup).value, 1)
	e.set(&"archetype", &"tank")
	gems._on_enemy_killed(e, info)
	await wait_physics_frames(1)
	var values := get_tree().get_nodes_in_group(Pickup.GEM_GROUP).map(func(p: Pickup) -> int: return p.value)
	assert_true(3 in values, "a tank's gem is worth 3")
	var enemy_shot := DamageInfo.new()
	enemy_shot.faction = &"enemy"
	gems._on_enemy_killed(e, enemy_shot)
	await wait_physics_frames(1)
	assert_eq(get_tree().get_nodes_in_group(Pickup.GEM_GROUP).size(), 2, "only the player's kills drop")


func test_the_gem_cap_merges_the_oldest() -> void:
	await _arena()
	var gems := Gems.new()
	add_child_autofree(gems)
	var keep := Tuning.hard_max_pickups
	Tuning.hard_max_pickups = 4
	for i in 3:
		gems.drop((OPEN + Vector2(-12, -2 + i)) * T, 1)
	await wait_physics_frames(1)
	gems.drop((OPEN + Vector2(-12, 1)) * T, 1)
	assert_eq(RunState.pending_count(&"pickup"), 1)
	gems.drop((OPEN + Vector2(-12, 3)) * T, 1)
	gems.drop((OPEN + Vector2(-12, 3)) * T, 1)
	await wait_physics_frames(1)
	var total := 0
	for p in get_tree().get_nodes_in_group(Pickup.GEM_GROUP):
		if not p.is_queued_for_deletion():
			total += (p as Pickup).value
	Tuning.hard_max_pickups = keep
	assert_eq(total, 6, "no gem's worth is lost")
	assert_lte(RunState.pending_count(&"pickup"), 4)


# --- The level meter -----------------------------------------------------------------------

func test_the_meter_levels_and_stops_after_ten_picks() -> void:
	var m := LevelMeter.new()
	m.def = _auto()
	var levels: Array = []
	var full := [0]
	m.on_level = func() -> void: levels.append(1)   # never capture m: a cycle leaks
	m.on_full = func() -> void: full[0] += 1
	m.add(2)
	assert_eq(m.level, 1)
	m.add(1)
	assert_eq(m.level, 2)
	m.add(10000)
	assert_eq(m.level, 11, "ten level-ups, then the meter stops")
	assert_eq(levels.size(), 10)
	assert_eq(full[0], 1)
	m.add(500)
	assert_eq(m.level, 11)


func test_a_tryout_meter_levels_once() -> void:
	var m := LevelMeter.new()
	m.def = _auto()
	m.tryout = true
	var full := [0]
	m.on_full = func() -> void: full[0] += 1
	m.add(5)
	assert_eq(m.level, 1)
	m.add(1)
	assert_eq(m.level, 2)
	m.add(100)
	assert_eq(m.level, 2)
	assert_eq(full[0], 0, "no stop line in a tryout")


func test_the_widget_shows_the_level_and_bar() -> void:
	var m := LevelMeter.new()
	m.def = _auto()
	m.add(4)
	var w := LevelWidget.new()
	w.meter = m
	add_child_autofree(w)
	assert_string_starts_with(w.text(), "LV 2")
	assert_almost_eq(w.bar(), m.progress(), 0.0001)


# --- PickOffer -----------------------------------------------------------------------------

func _offer(lo: Loadout, pool: Array[StringName], first := &"", run_seed := 7) -> PickOffer:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	return PickOffer.draw(lo, _auto(), pool, first, rng, Taste.new())


func test_an_offer_is_seeded_and_puts_the_given_weapon_first() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	var pool: Array[StringName] = [&"pistol", &"shotgun", &"laser", &"launcher"]
	assert_eq(_offer(lo, pool).ids(), _offer(lo, pool).ids(), "the same seed, the same cards")
	assert_eq(_offer(lo, pool).cards.size(), 3)
	for s in 6:
		assert_eq(_offer(lo, pool, &"launcher", s).ids()[0], &"launcher")


func test_ranks_stop_at_three_then_the_hp_filler() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.upgrade(&"pistol")
	assert_eq(_offer(lo, [&"pistol"] as Array[StringName]).cards[0].kind, &"upgrade")
	lo.upgrade(&"pistol")
	assert_eq(lo.summary(), "pistol:3")
	var o := _offer(lo, [&"pistol"] as Array[StringName])
	assert_eq(o.ids(), [PickOffer.HP] as Array[StringName])
	assert_eq(o.cards[0].text, "+1 HP (this session)")


func test_the_card_text_names_its_key() -> void:
	var o := PickOffer.new()
	o.cards.append({"id": &"pistol", "rank": 2, "kind": &"upgrade", "text": "Pistol II"})
	# The key as the player's layout prints it (AZERTY and the rest): here every key reads A.
	var text := PickPanel.card_text(o, 0, func(_physical: int) -> int: return KEY_A)
	assert_eq(text, "[A]  Pistol II")
	for i in 3:
		assert_true(InputMap.has_action(StringName("choose_%d" % (i + 1))))


func test_the_panel_pauses_for_pick_and_waits_its_delay() -> void:
	var panel := PickPanel.new()
	add_child_autofree(panel)
	await wait_physics_frames(1)
	var o := PickOffer.new()
	o.cards.append({"id": &"pistol", "rank": 2, "kind": &"upgrade", "text": "Pistol II"})
	var got: Array = []
	panel.picked.connect(func(_o: PickOffer, i: int) -> void: got.append(i))
	assert_true(panel.open(o))
	assert_true(RunState.is_paused_for(PickPanel.PAUSE))
	assert_false(panel.can_choose(), "the input delay")
	panel.choose(0)
	assert_eq(got, [])
	panel._unlock()
	panel.choose(0)
	assert_eq(got, [0])
	assert_false(RunState.is_paused_for(PickPanel.PAUSE))
	assert_true(panel.open(o))
	panel.dismiss()
	assert_false(RunState.is_paused_for(PickPanel.PAUSE), "dismiss takes the reason away")
	assert_false(panel.open(o), "never again after the run")


# --- PathRunner in a game -----------------------------------------------------------------

func test_the_stub_boots_without_a_path_then_its_cue_warns_and_swaps() -> void:
	await _session_game(STUB)
	assert_not_null(game.path_runner, "a tryout has a runner")
	assert_eq(RunState.live_path(), &"")
	assert_eq(_loadout().fire_mode, &"manual_one")
	var said := game.path_runner.said.size()
	assert_true(game.path_runner.request_swap(&"auto"))
	assert_eq(game.path_runner.said.size(), said + 1)
	assert_eq(game.path_runner.said[-1], _auto().warn().text)
	assert_true(game.path_runner.swap_pending())
	await wait_physics_frames(roundi(PathRunner.SWAP_WARN_SECONDS * 60) + 2)
	assert_false(game.path_runner.swap_pending())
	assert_eq(RunState.live_path(), &"auto")
	assert_eq(_loadout().fire_mode, &"auto_all")
	assert_eq(_loadout().summary(), "pistol:1")


func test_a_swap_clears_shots_and_pickups_and_keeps_enemies() -> void:
	await _session_game(STUB)
	var e := await _frozen_chaser(Vector2(30, 20))
	var p := _pickup(&"gem", Vector2(4, 4))
	await wait_physics_frames(1)
	game.path_runner.swap_now(&"auto")
	await wait_physics_frames(1)
	assert_true(is_instance_valid(e))
	assert_false(is_instance_valid(p))


func test_path_off_is_the_legacy_pistol() -> void:
	await _session_game(STUB)
	game.path_runner.swap_now(&"auto")
	game.path_runner.swap_now(&"off")
	assert_eq(RunState.live_path(), &"")
	assert_eq(_loadout().fire_mode, &"manual_one")
	assert_eq(_loadout().summary(), "pistol:1")


func test_basics_build_the_meter_and_the_crowd() -> void:
	await _session_game(STUB)
	var r: PathRunner = game.path_runner
	r.swap_now(&"auto")
	assert_null(r.meter(), "no levelups basic yet")
	assert_null(r.overlay())
	RunState.add_basic(&"crowd")
	assert_not_null(r.overlay())
	RunState.add_basic(&"levelups")
	assert_not_null(r.meter())
	assert_true(game.hud.path_widget == r.widget())
	assert_true(r.meter().tryout)


func test_the_pause_rule() -> void:
	await _session_game(STUB)
	var r: PathRunner = game.path_runner
	r.swap_now(&"auto")
	assert_true(r.can_open_now())
	game.rule_book._pending.append({})
	assert_false(r.can_open_now(), "never over a rule edit's warning")
	game.rule_book._pending.clear()
	game.rule_book._live[&"x"] = {"edit": null, "end_tick": 999999}
	assert_true(r.can_open_now(), "a live timed edit does not hold picks")
	game.rule_book._live.clear()
	game.event_player._ctx = EventContext.new()
	assert_false(r.can_open_now(), "never over an event")
	game.event_player._ctx = null
	r.stop()
	assert_false(r.can_open_now(), "never after the run")


func test_level_and_picked_cues_parse() -> void:
	var lv := Cue.parse("level 3: say a")
	var pk := Cue.parse("picked 1: say b")
	assert_false(lv.due({"level": 2}))
	assert_true(lv.due({"level": 3}))
	assert_false(lv.due({"level": -1}))
	assert_false(pk.due({"picks": 0}))
	assert_true(pk.due({"picks": 1}))


## Review M45a: the session runner's ctx carries the runner's level and picks, so the
## stub's own `picked 1` line and an injected `level 2` line are said in a live game.
func test_a_level_cue_and_a_picked_cue_read_the_runner() -> void:
	await _session_game(STUB)
	var sr: SessionRunner = game.session_runner
	var r: PathRunner = game.path_runner
	r.swap_now(&"auto")
	RunState.add_basic(&"levelups")
	var lv := sr.inject("level 2: say happy: Level two now.")
	assert_eq(lv.problem, "")
	var lv_i: int = sr._cues.find(lv)
	var pk_i := -1
	for i in sr._cues.size():
		if sr._cues[i].when == &"picked":
			pk_i = i
	assert_gt(pk_i, -1, "the stub has a picked cue")
	await wait_physics_frames(2)
	assert_false(sr._fired[lv_i], "level 1: not yet")
	assert_false(sr._fired[pk_i], "no pick yet")
	r.meter().add(6)
	assert_eq(r.level(), 2)
	await wait_physics_frames(1)
	assert_true(sr._fired[lv_i], "the level cue fired on the level-up")
	if game.pick_panel.is_open():
		game.pick_panel._unlock()
		game.pick_panel.choose(0)
	else:
		_pick(r, 0)
	assert_eq(r.picks, 1)
	await wait_physics_frames(2)
	assert_true(sr._fired[pk_i], "the picked cue fired after the pick")
	var lines: Array = []
	for c: Cue in [sr._cues[lv_i], sr._cues[pk_i]]:
		lines.append(c.line.text)
	for t: String in lines:
		assert_true(t in sr.said or sr._queue.any(func(l: Line) -> bool: return l.text == t), "said: %s" % t)


func test_the_stub_offer_has_the_shotgun_first() -> void:
	await _session_game(STUB)
	var r: PathRunner = game.path_runner
	r.swap_now(&"auto")
	RunState.add_basic(&"levelups")
	var give := Cue.parse("at 0: give shotgun")
	game.session_runner._fire(give, -1)
	assert_eq(_loadout().summary(), "pistol:1", "no slot is filled")
	r.meter().add(6)
	assert_eq(r.pending_picks(), 1)
	var offer := _pick(r, 0)
	assert_eq(offer.ids()[0], &"shotgun")
	assert_eq(_loadout().summary(), "pistol:1,shotgun:1")
	assert_eq(r.picks, 1)


func test_a_pick_makes_a_mascot_comment_and_hp_filler_heals() -> void:
	await _session_game(STUB)
	var r: PathRunner = game.path_runner
	r.swap_now(&"auto")
	_loadout().upgrade(&"pistol")
	_loadout().upgrade(&"pistol")
	var h := Component.find(player, Health) as Health
	var top := h.max_hp()
	_pick(r, 0)
	assert_eq(r.offers[-1].ids(), [PickOffer.HP] as Array[StringName])
	assert_almost_eq(h.max_hp(), top + 1.0, 0.0001)
	assert_true(r.said[-1] in PathRunner.PICK_LINES.map(func(s: String) -> String: return Line.parse(s).text))


func test_ten_picks_leave_the_stack_build_and_save_alone() -> void:
	await _draft_game()
	var r: PathRunner = game.path_runner
	assert_eq(RunState.live_path(), &"auto")
	RunState.add_basic(&"levelups")
	r.announce(&"shotgun")
	var stack := RunState.stack.duplicate()
	var build := RunState.build_number
	var save := JSON.stringify(SaveGame.data)
	# Review M45a: the real notes sources. The session's patch notes (what the debrief
	# shows) and the run log's patch kinds (apply / revert / ai_apply / ai_remove / edits).
	var notes := RunState.session.notes.duplicate()
	var notes_text := DebriefScreen.notes_text(RunState.session)
	var patch_kinds := [&"apply", &"revert", &"ai_apply", &"ai_remove", &"edit_landed", &"basic_added", &"big_swap"]
	var patch_count := func() -> int:
		return RunState.run_log.filter(func(e: Dictionary) -> bool: return e.event in patch_kinds).size()
	var patches: int = patch_count.call()
	for i in 10:
		assert_true(r.can_open_now(), "pick %d can open" % i)
		_pick(r, i % 2)
	assert_eq(r.picks, 10)
	assert_eq(RunState.stack, stack, "no pick touches the stack")
	assert_eq(RunState.build_number, build, "nor build_number")
	assert_eq(JSON.stringify(SaveGame.data), save, "nor the save")
	assert_eq(RunState.session.notes, notes, "nor the session's patch notes")
	assert_eq(DebriefScreen.notes_text(RunState.session), notes_text, "nor the debrief's notes")
	assert_eq(patch_count.call(), patches, "nor a patch entry in the run log")


func test_no_pick_carries_a_weapon_before_its_cue() -> void:
	for id: StringName in [STUB, &"s8_draft"]:
		if id == STUB:
			await _session_game(STUB)
		else:
			await _draft_game()
		var r: PathRunner = game.path_runner
		r.swap_now(&"auto")
		RunState.add_basic(&"levelups")
		var gives: Array = RunState.session.cue_list().filter(func(c: Cue) -> bool: return c.action == &"give")
		assert_false(gives.is_empty())
		var give_at: float = gives[0].value
		var seen_before: Array = []
		for second in range(0, int(give_at)):
			for c: Cue in RunState.session.cue_list():
				if c.when == &"at" and int(c.value) == second and c.action in [&"give", &"say"]:
					game.session_runner._fire(c, -1)
			_pick(r, second % 3 if r.offers.is_empty() else 0)
			seen_before.append_array(r.offers[-1].ids())
		assert_false(&"shotgun" in seen_before, "%s: no shotgun before its give at %d s" % [id, give_at])
		game.session_runner._fire(gives[0], -1)
		_pick(r, 0)
		assert_true(&"shotgun" in r.offers[-1].ids(), "%s: offered once given" % id)
		remove_child(game)
		game.free()
		RunState.reset(0)
		CampaignDB.campaign.sessions.erase(_draft_in_list())


func _draft_in_list() -> SessionDef:
	for s in CampaignDB.campaign.sessions:
		if s.id == &"s8_draft":
			return s
	return null


func test_power_stays_in_the_session() -> void:
	await _draft_game()
	var r: PathRunner = game.path_runner
	RunState.add_basic(&"levelups")
	RunState.add_basic(&"crowd")
	r.announce(&"shotgun")
	_pick(r, 0)
	remove_child(game)
	game.free()
	CampaignDB.campaign.sessions.erase(_draft_in_list())
	await _session_game(&"s1_06_playground")
	assert_eq(RunState.session_path, &"")
	assert_null(game.path_runner, "Stage 1 has no runner")
	assert_eq(get_tree().get_nodes_in_group(Pickup.GEM_GROUP).size(), 0)
	assert_eq(_loadout().summary(), "pistol:1")
	assert_eq(RunState.rules.max_enemies, RunState.base_rules.max_enemies, "no crowd overlay")


func test_the_draft_boots_as_auto_with_doubled_kills_only_for_kill_goals() -> void:
	await _draft_game()
	assert_eq(RunState.session.id, &"s8_draft")
	assert_eq(_loadout().fire_mode, &"auto_all")
	var loop: Node = game.genre.get(&"run_loop")
	assert_eq(float(loop.get(&"goal_value")), 120.0, "survive goals never scale")
	CampaignDB.campaign.sessions.erase(_draft_in_list())


func test_a_kills_goal_doubles_on_auto() -> void:
	var d := _draft().duplicate() as SessionDef
	d.goal = SessionDef.KILLS
	d.goal_value = 20
	CampaignDB.campaign.sessions.insert(CampaignDB.cooking_index(), d)
	await _session_game(d.id)
	var loop: Node = game.genre.get(&"run_loop")
	assert_eq(float(loop.get(&"goal_value")), 40.0)
	CampaignDB.campaign.sessions.erase(d)


func test_not_shooting_is_silent_on_auto() -> void:
	await _session_game(STUB)
	var r: PathRunner = game.path_runner
	r.swap_now(&"auto")
	var def: ReactionDef = null
	for d in CampaignDB.reactions:
		if d.id == &"not_shooting":
			def = d
	assert_not_null(def)
	game.reactions._last_shot_at = -1000.0
	assert_false(game.reactions._happened(def, 1000.0, 5), "auto never says not_shooting")
	r.swap_now(&"off")
	assert_true(game.reactions._happened(def, 1001.0, 5), "the manual pistol still does")


# --- Data problems -------------------------------------------------------------------------

func test_a_path_basic_needs_its_path_or_answer() -> void:
	var s := CampaignDB.get_session(&"s1_06_playground").duplicate() as SessionDef
	s.cues = PackedStringArray(["at 5: add crowd"])
	s._parsed = false
	assert_string_contains("\n".join(s.problems()), "crowd is auto's basic; it needs answer:path_auto")
	s.cues = PackedStringArray(["answer:path_auto at 5: add crowd"])
	s._parsed = false
	assert_eq(s.problems(), [] as Array[String])
	s.cues = PackedStringArray([])
	s._parsed = false
	s.basics = s.basics.duplicate()
	s.basics.append(&"levelups")
	assert_string_contains("\n".join(s.problems()), "levelups")
	s.path = &"auto"
	assert_false("levelups" in "\n".join(s.problems()), "its own path")


func test_a_tag_must_be_a_session_weapon() -> void:
	var s := CampaignDB.get_session(STUB).duplicate() as SessionDef
	s.cues = PackedStringArray(["at 20 [laser]: say happy: A laser."])
	s._parsed = false
	assert_string_contains("\n".join(s.problems()), "[laser] is not in the session's weapons")
	s.cues = PackedStringArray(["at 20 [shotgun]: say happy: A shotgun."])
	s._parsed = false
	assert_eq(s.problems(), [] as Array[String])


func test_the_carry_rule_skips_path_basics() -> void:
	# The draft adds crowd; a session after it lists neither: the carry rule must not ask.
	CampaignDB.campaign.sessions.insert(CampaignDB.cooking_index(), _draft())
	var problems := CampaignDB.problems(CampaignDB.campaign)
	CampaignDB.campaign.sessions.erase(_draft_in_list())
	assert_eq(problems, [] as Array[String])


# --- The auto bot -------------------------------------------------------------------------

## Review M45a: with no enemy left, an open exit gate wins over a gem (as the default bot).
func test_the_auto_bot_goes_to_the_gate_before_a_gem() -> void:
	await _arena()
	assert_true(game.debug.switch_path(&"auto"))
	var bot := BotInput.new()
	player.set_input(bot)
	await wait_physics_frames(1)
	var gate := ExitGate.new()
	game.add_child(gate)
	gate.setup(game.arena, player)
	var here := bot.origin()
	var to_gate := gate.direction_from(here)
	var g := _pickup(&"gem", OPEN + (-to_gate * 12.0).rotated(0.4))
	await wait_physics_frames(1)
	assert_true(g.is_in_group(Pickup.GEM_GROUP))
	bot._physics_process(1.0 / 60.0)
	assert_eq(bot.policy, &"auto")
	here = bot.origin()
	assert_true(bot.move.is_equal_approx(gate.direction_from(here)), "to the gate, not the gem")
	game.remove_child(gate)
	gate.free()
	bot._physics_process(1.0 / 60.0)
	assert_true(bot.move.is_equal_approx((g.global_position - bot.origin()).normalized()), "then the gem")


# --- F1 / F2 -------------------------------------------------------------------------------

func test_f2_path_and_f1_line() -> void:
	await _arena()
	assert_null(game.path_runner)
	assert_true(game.debug.switch_path(&"auto"))
	assert_not_null(game.path_runner)
	assert_eq(_loadout().fire_mode, &"auto_all")
	assert_string_contains(game.path_runner.state_text(), "path=auto level=")
	game.debug.add_level()
	assert_eq(game.path_runner.level(), 2)
	assert_true(game.debug.switch_path(&"survival"), "M47: F2 PATH survival")
	assert_eq(_loadout().fire_mode, &"manual_ammo")
	await wait_physics_frames(2)   # Survival's deferred pieces land before the game is freed (no orphan)
	assert_true(game.debug.switch_path(&"off"))
	assert_eq(_loadout().fire_mode, &"manual_one")


func test_the_stub_before_its_path_cue_matches_s6_rules_but_hp_floor() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RulesDump.FIXTURE))
	var d: Dictionary = await RulesDump.dump(get_tree(), self, STUB)
	var want: Dictionary = fixture["s1_06_playground"]
	for part in ["rules", "base_rules"]:
		for k: String in want[part]:
			if k == "hp_floor":
				continue
			assert_eq(d[part].get(k), want[part][k], "%s.%s" % [part, k])


## M47 (D5): the old Auto-taste stub is a draft now; these tests insert it (after S8) and
## after_each removes it.
const STUB_DRAFT := "res://campaign/drafts/s7_auto_stub.tres"


func _stub_in() -> void:
	if CampaignDB.get_session(STUB) == null:
		CampaignDB.campaign.sessions.insert(CampaignDB.cooking_index(), load(STUB_DRAFT) as SessionDef)


func _stub_out() -> void:
	var s := CampaignDB.get_session(STUB)
	while s != null:
		CampaignDB.campaign.sessions.erase(s)
		s = CampaignDB.get_session(STUB)
