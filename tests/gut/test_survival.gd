extends GutTest
## M47 (PLAN v9 1.5 Survival column, 1.6, 4): the Survival path. Data, ammo and the sidearm,
## scavenging (swap, rank up, the untouchable drop), the drops table on loot_rng (never
## gameplay_rng), crates, kill-heal from its arming, the orbit battery, pickup tiles and
## their fallback, the ammo widget, the bot's pickup detour and its BFS field.

const CHASER := preload("res://entities/enemy_chaser.tscn")
const PICKUP := preload("res://entities/pickup.tscn")
const T := 48.0
const OPEN := Vector2(34, 20)
const TEST_LOG := "user://save_survival_test/runs.jsonl"
const AmmoWidget := preload("res://paths/survival/ammo_widget.gd")

var game: Main
var player: CharacterBody2D
var _links: Array = []


func before_each() -> void:
	Telemetry.log_path = TEST_LOG


func after_each() -> void:
	await wait_physics_frames(2)   # deferred spawns land before the game is freed (no orphan)
	for l: Array in _links:
		if (l[0] as Signal).is_connected(l[1]):
			(l[0] as Signal).disconnect(l[1])
	_links.clear()
	assert_false(FileAccess.file_exists(TEST_LOG), "no telemetry written, not even to the scratch log")
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.invincible = false
	CampaignDB.active = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null


func _survival() -> PathDef:
	return PathDB.get_def(&"survival")


## The legacy arena (every basic on outside a session), spawner and director off, Survival live.
func _arena(path := &"survival") -> void:
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	game.director.enabled = false
	await wait_physics_frames(2)
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()
	await wait_physics_frames(1)
	player = game.player
	player.set_input(load("res://tests/gut/fixtures.gd").ScriptedInput.new())
	await wait_physics_frames(1)
	player.global_position = OPEN * T
	player.velocity = Vector2.ZERO
	RunState.invincible = true
	if path != &"":
		assert_true(game.debug.switch_path(path))
		await wait_physics_frames(2)


func _lo() -> Loadout:
	return Component.find(player, Loadout) as Loadout


func _drops() -> Node:
	return game.path_runner.get(&"_drops")


func _clear_pickups() -> void:
	for p in get_tree().get_nodes_in_group(&"pickup"):
		p.free()
	(_drops().get(&"_mine") as Array).clear()


func _weapon_pickup(id: StringName, at: Vector2, extra := {}) -> Pickup:
	var params := {&"pickup_kind": &"weapon", &"weapon_id": id}
	params.merge(extra)
	var p := RunState.spawn(PICKUP, at, params) as Pickup
	_drops().call(&"watch", p)
	return p


func _kill(enemy: Node2D) -> void:
	EventBus.enemy_killed.emit(enemy, DamageInfo.make(1.0, &"shot", &"player"))


# --- Data ------------------------------------------------------------------------------

func test_the_survival_data_is_valid() -> void:
	assert_eq(PathDB.problems(), [] as Array[String])
	assert_eq(PathDB.ids(), [&"arsenal", &"auto", &"survival"] as Array[StringName])
	var s := _survival()
	assert_eq([s.fire_mode, s.growth, s.max_slots, s.max_passives], [&"manual_ammo", &"pickups", 1, 1])
	assert_eq(s.basics, [&"pickups", &"kill_heal"] as Array[StringName])
	assert_true(Unlocks.CAMPAIGN_BASICS.has(&"pickups") and Unlocks.CAMPAIGN_BASICS.has(&"kill_heal"))
	assert_eq(Cue.parse("at 3: path survival").unbuilt(), "")
	for ok: String in ["at 3: drop shotgun", "at 3: drop ammo", "at 3: drop heal", "at 3: drop heal 2"]:
		assert_eq(Cue.parse(ok).problem, "", ok)
	for bad: String in ["at 3: drop", "at 3: drop banana", "at 3: drop ammo x"]:
		assert_ne(Cue.parse(bad).problem, "", bad)
	assert_eq(load("res://levels/arenas/arena_0.tres").problems(), [] as Array[String])


func test_the_path_code_never_names_a_mutation_id() -> void:
	for f in ["drops.gd", "scavenge.gd", "ammo_widget.gd"]:
		var text := FileAccess.get_file_as_string("res://paths/survival/" + f)
		assert_true(text.split("\n").slice(0, 3).has("# path:survival"), f + ": the path tag in its head")
		assert_false(text.contains("\"orbit\""), f + ": reads is_passive() / ammo, never the id")


# --- Ammo and the sidearm ----------------------------------------------------------------

func test_ammo_counts_per_shot_and_runs_dry_to_the_sidearm() -> void:
	await _arena()
	var lo := _lo()
	assert_eq(lo.fire_mode, &"manual_ammo")
	assert_true(lo.on_sidearm(), "Survival starts on the pistol")
	assert_eq(lo.sidearm.def.id, Loadout.PISTOL)
	assert_true(lo.give(&"shotgun"))
	assert_eq(lo.slots.size(), 1, "one slot")
	assert_eq(lo.current().def.id, &"shotgun")
	assert_eq(lo.sidearm.def.id, Loadout.PISTOL, "the sidearm stays")
	var w := lo.current()
	assert_eq(w.ammo_left, 24)
	w.ammo_left = 2
	assert_true(lo.try_fire(Vector2.RIGHT))
	assert_eq(w.ammo_left, 1)
	w.ready_in = 0.0
	assert_true(lo.try_fire(Vector2.RIGHT))
	assert_true(lo.on_sidearm(), "0 ammo: the sidearm in the same frame")
	assert_eq(RunState.run_log.filter(func(e: Dictionary) -> bool: return e.event == &"ammo_empty").size(), 1)
	lo.current().ready_in = 0.0
	assert_true(lo.try_fire(Vector2.RIGHT), "the next shot fires the pistol")
	assert_eq(lo.current().def.id, Loadout.PISTOL)


func test_f2_weapons_replace_slot_0_and_keep_the_sidearm() -> void:
	await _arena()
	var lo := _lo()
	assert_true(lo.set_weapon(&"laser", 2))
	assert_eq(lo.slots.size(), 1)
	assert_eq(lo.summary().contains("laser:2"), true, lo.summary())
	assert_true(lo.set_weapon(&"shotgun", 1))
	assert_eq(lo.slots.size(), 1, "replaced, never appended")
	assert_eq(lo.current().def.id, &"shotgun")
	assert_eq(lo.sidearm.def.id, Loadout.PISTOL)


# --- Scavenging ----------------------------------------------------------------------------

func test_the_same_weapon_ranks_up_with_full_ammo() -> void:
	await _arena()
	_clear_pickups()
	var lo := _lo()
	lo.give(&"shotgun")
	lo.current().ammo_left = 3
	_weapon_pickup(&"shotgun", player.global_position)
	await wait_physics_frames(3)
	assert_eq(lo.current().def.id, &"shotgun")
	assert_eq(lo.current().rank, 2)
	assert_eq(lo.current().ammo_left, 24, "full ammo")


func test_another_weapon_swaps_and_the_old_one_drops_untouchable() -> void:
	await _arena()
	_clear_pickups()
	var lo := _lo()
	lo.give(&"shotgun")
	lo.current().ammo_left = 7
	_weapon_pickup(&"laser", player.global_position)
	await wait_physics_frames(3)
	assert_eq(lo.current().def.id, &"laser")
	var dropped: Array = get_tree().get_nodes_in_group(&"pickup").filter(func(p: Node) -> bool:
		return (p as Pickup).weapon_id == &"shotgun")
	assert_eq(dropped.size(), 1, "the shotgun lies at the feet")
	var d := dropped[0] as Pickup
	assert_true(d.untouchable)
	assert_eq(d.ammo_left, 7, "it keeps its ammo")
	# Standing on it: never taken (untouchable until the player has left the take radius).
	for i in 180:
		await wait_physics_frames(1)
	assert_eq(lo.current().def.id, &"laser", "3 s standing still: 0 swaps")
	assert_true(is_instance_valid(d))
	player.global_position += Vector2(6.0 * T, 0)
	await wait_physics_frames(3)
	player.global_position = d.global_position
	await wait_physics_frames(3)
	assert_eq(lo.current().def.id, &"shotgun", "after leaving it, taken back")
	assert_eq(lo.current().ammo_left, 7)


func test_the_untouchable_drop_waits_half_a_second() -> void:
	await _arena()
	_clear_pickups()
	var d := RunState.spawn(PICKUP, player.global_position + Vector2(8.0 * T, 0), {&"pickup_kind": &"weapon",
			&"weapon_id": &"shotgun", &"untouchable": true}) as Pickup
	_drops().call(&"watch", d)
	await wait_physics_frames(2)
	d.age = 0.49
	player.global_position = d.global_position
	await wait_physics_frames(1)
	assert_true(is_instance_valid(d) and not d.is_queued_for_deletion(), "0.49 s: not yet")
	player.global_position = d.global_position + Vector2(6.0 * T, 0)
	d.age = 0.51
	await wait_physics_frames(2)
	player.global_position = d.global_position
	await wait_physics_frames(2)
	assert_eq(_lo().current().def.id, &"shotgun", "0.51 s and the player arrived from outside: taken")


func test_a_pistol_pickup_ranks_up_the_sidearm_and_keeps_the_gun() -> void:
	await _arena()
	_clear_pickups()
	var lo := _lo()
	lo.give(&"shotgun")
	_weapon_pickup(Loadout.PISTOL, player.global_position)
	await wait_physics_frames(3)
	assert_eq(lo.current().def.id, &"shotgun", "never a swap")
	assert_eq(lo.sidearm.rank, 2)


func test_ammo_is_half_the_gun_capped_and_never_the_sidearm() -> void:
	await _arena()
	var lo := _lo()
	lo.give(&"shotgun")
	lo.current().ammo_left = 1
	var p := PICKUP.instantiate() as Pickup
	p.pickup_kind = &"ammo"
	Scavenge.take(lo, p, Vector2.ZERO)
	assert_eq(lo.current().ammo_left, 13, "+12 (50% of 24)")
	Scavenge.take(lo, p, Vector2.ZERO)
	assert_eq(lo.current().ammo_left, 24, "capped")
	lo.to_sidearm()
	Scavenge.take(lo, p, Vector2.ZERO)
	assert_true(lo.on_sidearm())
	p.free()


# --- The drop cue -----------------------------------------------------------------------------

func test_drop_heal_ammo_and_a_weapon() -> void:
	await _arena()
	_clear_pickups()
	var r := game.path_runner
	assert_true(r.drop(&"shotgun", 1))
	assert_true(r.drop(&"ammo", 1))
	assert_true(r.drop(&"heal", 1))
	await wait_physics_frames(1)
	var kinds: Array = get_tree().get_nodes_in_group(&"pickup").map(func(p: Node) -> String:
		return "%s:%s" % [(p as Pickup).pickup_kind, (p as Pickup).weapon_id])
	kinds.sort()
	assert_eq(kinds, ["ammo:", "heal:", "weapon:shotgun"])
	assert_true(game.debug.switch_path(&"auto"))
	await wait_physics_frames(2)
	assert_false(game.path_runner.drop(&"ammo", 1), "only with Survival live")


# --- Drops ------------------------------------------------------------------------------------

func test_the_drop_table_reads_loot_rng_only() -> void:
	await _arena()
	_clear_pickups()
	var lo := _lo()
	lo.give(&"shotgun")
	var drops := _drops()
	drops.set(&"crates", false)
	var chaser := CHASER.instantiate() as Node2D
	add_child_autofree(chaser)
	chaser.set_physics_process(false)
	chaser.global_position = OPEN * T + Vector2(10 * T, 0)
	RunState.loot_rng.seed = 7
	var gameplay := RunState.gameplay_rng.state
	var spawned := 0
	var counted := func() -> int: return get_tree().get_nodes_in_group(&"pickup").size()
	var before := 0
	for i in 200:
		before = counted.call()
		_kill(chaser)
		await wait_physics_frames(1)
		if counted.call() > before:
			spawned += 1
		_clear_pickups()
	assert_eq(RunState.gameplay_rng.state, gameplay, "drops never touch gameplay_rng")
	assert_between(spawned, 8, 35, "about 10 pct of 200 kills (%d)" % spawned)
	# Big enemies (tank, bomber): 35 pct.
	chaser.set(&"archetype", &"tank")
	var big := 0
	for i in 200:
		before = counted.call()
		_kill(chaser)
		await wait_physics_frames(1)
		if counted.call() > before:
			big += 1
		_clear_pickups()
	assert_eq(RunState.gameplay_rng.state, gameplay, "still never gameplay_rng")
	# A drop is a weapon or ammo 50/50 and a weapon needs a weapon to draw, so the absolute
	# rate is not 35 pct here; the ratio to the small-enemy rate is 3.5.
	assert_between(float(big) / maxf(1.0, float(spawned)), 2.0, 5.5, "35 vs 10 pct (%d vs %d)" % [big, spawned])


func test_a_bomber_self_kill_drops_nothing() -> void:
	await _arena()
	_clear_pickups()
	var e := CHASER.instantiate() as Node2D
	add_child_autofree(e)
	e.set_physics_process(false)
	RunState.loot_rng.seed = 1
	for i in 100:
		EventBus.enemy_killed.emit(e, DamageInfo.make(1.0, &"explosion", &"enemy"))
	await wait_physics_frames(1)
	assert_eq(get_tree().get_nodes_in_group(&"pickup").size(), 0)


func test_crates_two_at_once_one_per_20_s_max_three_and_never_in_a_tryout() -> void:
	await _arena()
	var crates := func() -> int:
		return get_tree().get_nodes_in_group(&"pickup").filter(func(p: Node) -> bool: return (p as Pickup).crate).size()
	assert_eq(crates.call(), 2, "2 at the arming")
	var spots: Array = get_tree().get_nodes_in_group(&"pickup").map(func(p: Node) -> Vector2: return (p as Node2D).global_position)
	assert_ne(spots[0], spots[1], "on two different tiles")
	var drops := _drops()
	drops.set(&"_tick", int(drops.get(&"_next_crate")) - 1)
	await wait_physics_frames(2)
	assert_eq(crates.call(), 3, "one more after 20 s")
	drops.set(&"_tick", int(drops.get(&"_next_crate")) - 1)
	await wait_physics_frames(2)
	assert_eq(crates.call(), 3, "at most 3")
	for p in get_tree().get_nodes_in_group(&"pickup"):
		(p as Pickup).age = 999.0
	await wait_physics_frames(2)
	assert_eq(crates.call(), 3, "crates never expire")
	var tryout := Node.new()
	tryout.set_script(load("res://paths/survival/drops.gd"))
	tryout.set(&"runner", game.path_runner)
	tryout.set(&"crates", false)
	add_child_autofree(tryout)
	tryout.call(&"arm_pickups")
	await wait_physics_frames(1)
	assert_eq(crates.call(), 3, "no crate in a tryout")


func test_kill_heal_counts_from_its_arming_and_never_on_auto() -> void:
	await _arena()
	var drops := _drops()
	drops.set(&"pickups_on", false)
	var e := CHASER.instantiate() as Node2D
	add_child_autofree(e)
	e.set_physics_process(false)
	drops.set(&"heal_on", false)
	for i in 4:
		_kill(e)
	drops.call(&"arm_kill_heal")
	var h := Component.find(player, Health) as Health
	var heal_logs := func() -> int:
		return RunState.run_log.filter(func(ev: Dictionary) -> bool: return ev.event == &"kill_heal").size()
	for i in 5:
		_kill(e)
	assert_eq(game.path_runner.heals(), 0, "the 5th since the arming at full HP restores nothing: not counted")
	assert_eq(heal_logs.call(), 0, "nor logged (telemetry kill_heal = HP restored)")
	h.hp_ratio = (h.max_hp() - 1.5) / h.max_hp()
	for i in 4:
		_kill(e)
	assert_eq(game.path_runner.heals(), 0, "4 kills since the last heal tick: no heal")
	_kill(e)
	assert_eq(game.path_runner.heals(), 1, "the 10th since the arming heals")
	assert_almost_eq(h.hp(), h.max_hp() - 0.5, 0.001, "1 HP back")
	assert_eq(heal_logs.call(), 1)
	for i in 5:
		_kill(e)
	assert_almost_eq(h.hp(), h.max_hp(), 0.001, "capped at max")
	assert_eq(game.path_runner.heals(), 2, "half an HP restored still counts")
	assert_true(game.debug.switch_path(&"auto"))
	await wait_physics_frames(2)
	h.hp_ratio = (h.max_hp() - 2.0) / h.max_hp()
	for i in 10:
		_kill(e)
	assert_almost_eq(h.hp(), h.max_hp() - 2.0, 0.001, "not armed on Auto after the swap: no HP back")
	assert_eq(heal_logs.call(), 2)


func test_f1_shows_survivals_weapon_ammo_and_heals() -> void:
	await _arena()
	var r := game.path_runner
	assert_eq(r.state_text(), "path=survival weapon=pistol:1 ammo=- picks=0 pickups=0 heals=0")
	_lo().give(&"shotgun")
	_lo().upgrade(&"shotgun")
	_lo().current().ammo_left = 18
	assert_string_contains(r.state_text(), "path=survival weapon=shotgun:2 ammo=18/24 ")
	assert_string_contains(r.state_text(), " heals=0")


func test_a_cue_swap_to_survival_keeps_its_two_first_crates() -> void:
	await _arena(&"")
	var r := game.ensure_path_runner()
	# The swap lands inside PathRunner's own tick (a cue), so the crates' deferred spawns
	# enter before the second sweep a frame later: it must keep them.
	# A shot fired on the swap tick too: the second sweep meets a shot and the kept crates.
	var lo := _lo()
	lo.current().ready_in = 0.0
	r.started.connect(func(_id: StringName) -> void: assert_true(lo.try_fire(Vector2.RIGHT)), CONNECT_ONE_SHOT)
	r.set(&"_swap_target", &"survival")
	r.set(&"_swap_tick", int(r.get(&"_tick")) + 1)
	await wait_physics_frames(5)
	assert_eq(RunState.live_path(), &"survival")
	var crates := get_tree().get_nodes_in_group(&"pickup").filter(func(p: Node) -> bool:
		return (p as Pickup).crate and not p.is_queued_for_deletion())
	assert_eq(crates.size(), 2, "2 at once, never swept by the swap")
	assert_gt(int((RunState.run_log.filter(func(e: Dictionary) -> bool: return e.event == &"path_leftovers")[-1] as Dictionary).get("late", 0)), 0,
			"the swap-tick shot went in the second sweep")
	assert_eq(r.leftover_checks[-1], [] as Array[String])


# --- The orbit battery ----------------------------------------------------------------------

func test_the_orbit_battery_runs_20_s_and_a_battery_restores_it() -> void:
	await _arena()
	var lo := _lo()
	assert_true(lo.give(&"orbit"))
	assert_not_null(lo.passive_node(&"orbit"))
	assert_almost_eq(lo.battery(&"orbit"), 20.0, 0.001)
	lo._drain(19.9)
	assert_not_null(lo.passive_node(&"orbit"))
	lo._drain(0.2)
	assert_null(lo.passive_node(&"orbit"), "20 s: the orbit is gone")
	var p := PICKUP.instantiate() as Pickup
	p.pickup_kind = &"battery"
	Scavenge.take(lo, p, Vector2.ZERO)
	p.free()
	assert_not_null(lo.passive_node(&"orbit"), "a battery pickup restores it")
	assert_almost_eq(lo.battery(&"orbit"), 20.0, 0.001)


# --- Pickup tiles, the widget -------------------------------------------------------------------

func test_pickup_tiles_problems_and_the_fallback() -> void:
	var def := (load("res://levels/arenas/arena_0.tres") as ArenaDef).duplicate() as ArenaDef
	assert_eq(def.problems(), [] as Array[String])
	def.pickup_tiles = PackedVector2Array([Vector2(18, 13.5)])
	assert_string_contains("\n".join(def.problems()), "1 pickup tiles")
	var ok := [Vector2(18, 13.5), Vector2(48, 13.5), Vector2(10, 16.5)]
	def.pickup_tiles = PackedVector2Array(ok + [Vector2(8, 18.5)])
	assert_string_contains("\n".join(def.problems()), "pickup tile (8.0, 18.5) is inside or against a block")
	# A sealed box: free of blocks inside, but no walk to it from the start.
	def.blocks = def.blocks.duplicate()
	def.blocks.append_array([Rect2(26, 13, 5, 1), Rect2(26, 17, 5, 1), Rect2(26, 14, 1, 3), Rect2(30, 14, 1, 3)])
	def.pickup_tiles = PackedVector2Array(ok + [Vector2(28.5, 15.5)])
	assert_eq(def.problems(), ["%s: pickup tile (28.5, 15.5) cannot be walked to from the start" % def.id] as Array[String])
	def.pickup_tiles = PackedVector2Array()
	assert_eq(def.problems(), [] as Array[String], "none: the spawn points are the fallback")


func test_the_ammo_widget_text() -> void:
	await _arena()
	var lo := _lo()
	assert_eq(AmmoWidget.line_for(lo), "Pistol I ●○○ ∞")
	lo.give(&"shotgun")
	lo.upgrade(&"shotgun")
	lo.current().ammo_left = 18
	assert_eq(AmmoWidget.line_for(lo).get_slice("\n", 0).begins_with("Shotgun II ●●○ 18/24"), true, AmmoWidget.line_for(lo))
	assert_string_contains(AmmoWidget.line_for(lo), "+ Pistol I ∞")


# --- The bot -----------------------------------------------------------------------------------

func test_the_bot_walks_to_a_pickup_with_no_enemy_near_and_the_probe_does_not() -> void:
	await _arena()
	_clear_pickups()
	_drops().set(&"crates", false)
	var p := _weapon_pickup(&"shotgun", player.global_position + Vector2(-5.0 * T, 0))
	await wait_physics_frames(1)
	var bot := BotInput.new()
	player.set_input(bot)
	await wait_physics_frames(1)
	bot._physics_process(1.0 / 60.0)
	assert_eq(bot.policy, &"survival")
	assert_gt(bot.move.dot((p.global_position - bot.origin()).normalized()), 0.9, "to the pickup")
	bot.probe = &"no_pickup"
	bot._physics_process(1.0 / 60.0)
	assert_lt(bot.move.dot((p.global_position - bot.origin()).normalized()), 0.9, "no_pickup: no detour")


func test_the_bot_never_bounces_between_two_aimed_guns() -> void:
	await _arena()
	_clear_pickups()
	_drops().set(&"crates", false)
	var lo := _lo()
	assert_true(lo.set_weapon(&"laser", 1))
	var bot := BotInput.new()
	player.add_child(bot)   # asked directly; the scripted input still drives the player
	await wait_physics_frames(1)
	var p := _weapon_pickup(&"shotgun", player.global_position + Vector2(-5.0 * T, 0))
	await wait_physics_frames(1)
	assert_eq(bot._pickup_dir(bot.origin()), Vector2.ZERO, "a laser with its ammo: never walks to swap it")
	lo.current().ammo_left = 1
	assert_ne(bot._pickup_dir(bot.origin()), Vector2.ZERO, "under half ammo: the shotgun is worth it")
	# The swap: the laser drops; once it is touchable again the bot never walks back to it.
	player.global_position = p.global_position
	await wait_physics_frames(3)
	assert_eq(lo.current().def.id, &"shotgun")
	bot._pickup_dir(bot.origin())
	var laser: Array = get_tree().get_nodes_in_group(&"pickup").filter(func(n: Node) -> bool:
		return (n as Pickup).weapon_id == &"laser")
	assert_eq(laser.size(), 1)
	(laser[0] as Pickup).untouchable = false
	player.global_position += Vector2(8.0 * T, 0)
	lo.current().ammo_left = 2
	assert_eq(bot._pickup_dir(bot.origin()), Vector2.ZERO, "the gun it just dropped: never again (no loop)")
	var same := _weapon_pickup(&"shotgun", player.global_position + Vector2(0, 4.0 * T))
	await wait_physics_frames(1)
	assert_ne(bot._pickup_dir(bot.origin()), Vector2.ZERO, "the same gun still ranks up")
	same.queue_free()


func test_the_bfs_field_takes_the_nearer_pickup_by_path() -> void:
	var f := PickupField.new()
	var a := Vector2(10, 16.5) * T
	var b := Vector2(57, 16.5) * T
	f.build([a, b] as Array[Vector2])
	assert_lt(f.steps_from(a + Vector2(2 * T, 0)), f.steps_from(b - Vector2(30 * T, 0)))
	assert_eq(f.steps_from(a), 0)
	assert_eq(f.direction_from((Vector2(10, 16) + Vector2(0.5, 0.5)) * T), Vector2.ZERO, "at a source tile's centre")
	var d := f.direction_from(a + Vector2(3 * T, 0))
	assert_gt(d.dot(Vector2.LEFT), 0.5, "towards the nearer one")


# --- Power stays in the session ------------------------------------------------------------------

func test_power_stays_in_the_session() -> void:
	await _arena()
	_lo().give(&"shotgun")
	assert_eq(SaveGame.state().shipped, [], "nothing weapon-related reaches the save")
	game.free()
	await _arena()
	assert_eq(_lo().summary(), "pistol:1", "the next session starts on the pistol")
	assert_eq(get_tree().get_nodes_in_group(&"pickup").filter(func(p: Node) -> bool: return not (p as Pickup).crate).size(), 0)
