extends GutTest
## M45b (PLAN v9 1.4, 1.9, 5): Auto at scale. The split projectile budgets (path sessions only;
## G6, the hard gate: a v6 shooter still fires with Auto saturated, and its control), the
## spatial-hash separation (equal to the legacy loop, path sessions only), the nova and well
## weapons (ranks 1-3), the pool rule for them, the refusal counters in telemetry, and a replay.

const CHASER := preload("res://entities/enemy_chaser.tscn")
const SHOOTER := preload("res://entities/enemy_shooter.tscn")
const BOMBER := preload("res://entities/enemy_bomber.tscn")
const PROJECTILE := preload("res://entities/projectile.tscn")
const PICKUP := preload("res://entities/pickup.tscn")
const WellField := preload("res://mutations/well/well_field.gd")
const WellWeaponField := preload("res://weapons/well_weapon_field.gd")
const NovaPulse := preload("res://weapons/nova_pulse.gd")
const T := 48.0
const OPEN := Vector2(34, 20)
const TEST_DIR := "user://save_auto_scale_test/"
## The telemetry log while these tests run: a scratch file, never user://playtest/runs.jsonl.
const TEST_LOG := "user://save_auto_scale_test/runs.jsonl"
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
	assert_false(FileAccess.file_exists(TEST_LOG), "no telemetry written, not even to the scratch log")
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.invincible = false
	CampaignDB.active = false
	while _draft_in_list() != null:
		CampaignDB.campaign.sessions.erase(_draft_in_list())
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null
	SeparationGrid.clear()
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(TEST_LOG)


func _on(sig: Signal, c: Callable) -> void:
	sig.connect(c)
	_links.append([sig, c])


## The legacy arena (no session): spawner and director off, no enemies, the player in the open.
func _arena(run_seed := -1) -> void:
	if run_seed >= 0:
		Main.next_seed = run_seed
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	game.director.enabled = false
	await wait_physics_frames(2)
	_clear_enemies()
	await wait_physics_frames(1)
	player = game.player
	player.set_input(load("res://tests/gut/fixtures.gd").ScriptedInput.new())
	await wait_physics_frames(1)
	player.global_position = OPEN * T
	player.velocity = Vector2.ZERO
	RunState.invincible = true


## The arena on Auto (as F2 PATH / the bench): session_path auto, the runner frozen (no gems,
## no picks) then begun.
func _auto_arena(run_seed := -1) -> PathRunner:
	await _arena(run_seed)
	RunState.session_path = &"auto"
	var r := game.ensure_path_runner()
	r.freeze()
	r.begin()
	await wait_physics_frames(1)
	return r


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()


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


func _draft() -> SessionDef:
	return load("res://campaign/drafts/s8_draft.tres") as SessionDef


func _draft_game() -> Main:
	CampaignDB.campaign.sessions.insert(CampaignDB.cooking_index(), _draft())
	return await _session_game(&"s8_draft")


func _draft_in_list() -> SessionDef:
	for s in CampaignDB.campaign.sessions:
		if s.id == &"s8_draft":
			return s
	return null


func _loadout() -> Loadout:
	return Component.find(player, Loadout) as Loadout


func _frozen(scene: PackedScene, tile: Vector2, hp := 100.0) -> Node2D:
	var e := RunState.spawn(scene, tile * T) as Node2D
	await wait_physics_frames(2)
	e.set_physics_process(false)   # no AI; its Mover still moves it (knockback)
	e.mover.wish = Vector2.ZERO
	e.velocity = Vector2.ZERO
	e.health.base_max_hp = hp
	e.health.hp_ratio = 1.0
	return e


func _damage_log(source: StringName) -> Array:
	var log: Array = []
	_on(EventBus.entity_damaged, func(target: Node, info: RefCounted) -> void:
		if (info as DamageInfo).source_patch == source:
			log.append([target, (info as DamageInfo).amount, (info as DamageInfo).kind]))
	return log


func _live(kind: StringName) -> int:
	return RunState.count(kind) + RunState.pending_count(kind)


## Frozen shots (no velocity, a long life) at `tile` until `n` of that kind exist.
func _hold_shots(kind: StringName, n: int, tile: Vector2) -> int:
	var made := 0
	while _live(kind) < n:
		if _shot(kind, tile) == null:
			break
		made += 1
	return made


func _shot(kind: StringName, tile: Vector2) -> Node:
	var params := {&"velocity": Vector2.ZERO, &"lifetime": 9999.0}
	if kind == &"enemy_projectile":
		params[&"kind"] = &"enemy_projectile"
		params[&"faction"] = &"enemy"
	return RunState.spawn(PROJECTILE, tile * T, params)


func _fields(script: Script) -> Array:
	return RunState.world.get_children().filter(func(n: Node) -> bool:
		return n.get_script() == script and not n.is_queued_for_deletion())


func _kill(e: Node2D) -> void:
	e.health.take(DamageInfo.make(10000.0, &"projectile", &"player", e.global_position))


# --- G6 (hard): a v6 shooter still fires with Auto saturated ------------------------------

func _saturated_scene() -> Node2D:
	var lo := _loadout()
	for id: StringName in [&"pistol", &"shotgun", &"laser", &"launcher", &"nova", &"well"]:
		lo.set_weapon(id, 3)
	# ~70 held chasers (no other shooter adds enemy shots), 3-6 T left of the player: the
	# real weapons have targets, nova (1.5 T) reaches none of them.
	for i in 70:
		RunState.spawn(CHASER, (OPEN + Vector2(-3.0 - (i % 10) * 0.4, -2.5 + floori(i / 10.0) * 0.45)) * T)
	await wait_physics_frames(2)
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.set_physics_process(false)
		e.mover.wish = Vector2.ZERO
		e.velocity = Vector2.ZERO
		e.health.base_max_hp = 100000.0
		e.health.hp_ratio = 1.0
	# One v6 shooter 6 T right, in line of sight, out of nova's reach, huge HP.
	var s := RunState.spawn(SHOOTER, (OPEN + Vector2(6, 0)) * T) as Node2D
	await wait_physics_frames(2)
	s.health.base_max_hp = 1000000.0
	s.health.hp_ratio = 1.0
	return s


func test_a_v6_shooter_still_fires_with_auto_saturated() -> void:
	await _auto_arena(3)
	assert_true(RunState.path_live())
	var s := await _saturated_scene()
	var at_fire := []
	_on(EventBus.projectile_fired, func(p: Node) -> void:
		if p.get(&"kind") == &"enemy_projectile" and at_fire.is_empty():
			at_fire.append(_live(&"player_projectile")))
	var fired := false
	for i in 180:   # 3 s; the shooter's interval is 1.8 s
		_hold_shots(&"player_projectile", Tuning.player_projectile_budget, OPEN + Vector2(0, -3))
		await wait_physics_frames(1)
		if RunState.count(&"enemy_projectile") > 0:
			fired = true
			break
	assert_true(is_instance_valid(s), "the shooter lives")
	assert_true(fired, "an enemy shot exists within 3 s")
	assert_eq(RunState.enemy_shots_refused, 0)
	assert_eq(at_fire, [Tuning.player_projectile_budget], "the player sat at 140 when it fired")
	assert_gt(RunState.player_shots_refused, 0, "the real weapons were refused: saturated")


func test_without_a_path_the_combined_cap_starves_the_shooter() -> void:
	await _arena(3)
	assert_false(RunState.path_live())
	var s := await _saturated_scene()
	for i in 180:
		_hold_shots(&"player_projectile", Tuning.hard_max_projectiles, OPEN + Vector2(0, -3))
		await wait_physics_frames(1)
	assert_true(is_instance_valid(s))
	assert_eq(RunState.count(&"enemy_projectile"), 0, "no enemy shot got in")
	assert_gt(RunState.enemy_shots_refused, 0, "the combined cap refused the shooter")


# --- The budgets ----------------------------------------------------------------------------

func test_stage_1_and_the_legacy_loop_keep_the_combined_cap() -> void:
	await _arena()
	assert_false(RunState.path_live())
	assert_eq(_hold_shots(&"player_projectile", 199, OPEN + Vector2(0, -3)), 199)
	assert_not_null(_shot(&"enemy_projectile", OPEN + Vector2(0, -3.5)), "the 200th shot fits")
	assert_null(_shot(&"enemy_projectile", OPEN + Vector2(0, -3.5)), "201 refused")
	assert_null(_shot(&"player_projectile", OPEN + Vector2(0, -3)), "for either side")
	assert_eq(RunState.enemy_shots_refused, 1)
	assert_eq(RunState.player_shots_refused, 1)
	await wait_physics_frames(1)
	for n in get_tree().get_nodes_in_group(&"enemy_projectile"):
		n.queue_free()
	await wait_physics_frames(1)
	assert_not_null(_shot(&"player_projectile", OPEN + Vector2(0, -3)), "player shots may take all 200")
	assert_null(_shot(&"player_projectile", OPEN + Vector2(0, -3)))
	assert_eq(_live(&"player_projectile"), 200)
	await wait_physics_frames(1)   # the pending shot lands before the scene goes (no leak)


func test_path_budgets_are_140_and_60() -> void:
	await _auto_arena()
	assert_eq(Tuning.player_projectile_budget + Tuning.enemy_projectile_budget, Tuning.hard_max_projectiles)
	assert_eq(_hold_shots(&"player_projectile", 1000, OPEN + Vector2(0, -3)), 140)
	assert_eq(RunState.player_shots_refused, 1, "the 141st player shot")
	assert_eq(_hold_shots(&"enemy_projectile", 1000, OPEN + Vector2(-6, -3)), 60, "enemy shots still spawn")
	assert_eq(RunState.enemy_shots_refused, 1, "the 61st")
	await wait_physics_frames(1)
	assert_eq(RunState.count(&"player_projectile"), 140)
	assert_eq(RunState.count(&"enemy_projectile"), 60)


func test_a_16_shot_burst_in_one_frame_fits_under_auto_saturation() -> void:
	await _auto_arena()
	_hold_shots(&"player_projectile", 1000, OPEN + Vector2(0, -3))
	await wait_physics_frames(1)
	assert_eq(RunState.count(&"player_projectile"), 140)
	var made := 0
	for i in 16:   # one frame: the pending count keeps them honest
		if _shot(&"enemy_projectile", OPEN + Vector2(-6, -3)) != null:
			made += 1
	assert_eq(made, 16)
	await wait_physics_frames(1)
	assert_eq(RunState.count(&"enemy_projectile"), 16)
	assert_eq(RunState.enemy_shots_refused, 0)


func test_the_shotgun_at_rank_3_with_every_slot_full_stays_inside_the_budgets() -> void:
	await _auto_arena(5)
	var lo := _loadout()
	for id: StringName in [&"pistol", &"shotgun", &"laser", &"launcher"]:
		lo.set_weapon(id, 3)
	# M50.4a: 3 shared slots: the launcher took the weakest non-active slot (the laser).
	assert_eq(lo.summary(), "pistol:3,shotgun:3,launcher:3")
	var points: Array = game.arena.spawn_points
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var most := [0, 0]
	for i in 300:
		var n := 0
		while _live(&"enemy") < 64 and n < 8:
			RunState.spawn(CHASER if n % 3 else SHOOTER, points[rng.randi_range(0, points.size() - 1)])
			n += 1
		# Moving filler shots keep the player side near its budget (they expire).
		for k in maxi(0, 125 - _live(&"player_projectile")):
			RunState.spawn(PROJECTILE, (OPEN + Vector2(0, -3)) * T, {&"velocity": Vector2.RIGHT.rotated(rng.randf() * TAU) * 400.0})
			if k > 20:
				break
		await wait_physics_frames(1)
		most[0] = maxi(most[0], RunState.count(&"player_projectile"))
		most[1] = maxi(most[1], RunState.count(&"enemy_projectile"))
		assert_lte(RunState.count(&"player_projectile"), 140)
		assert_lte(RunState.count(&"enemy_projectile"), 60)
	gut.p("most player / enemy shots in one frame: %d / %d, player refused %d" % [most[0], most[1], RunState.player_shots_refused])
	assert_gt(most[0], 100, "the player side ran near its budget")


# --- Separation -----------------------------------------------------------------------------

func test_the_grid_push_equals_the_legacy_push() -> void:
	await _arena()
	var enemies: Array[Node2D] = []
	for i in 60:
		enemies.append(RunState.spawn(CHASER, (OPEN + Vector2(i % 10, -2.0 + floori(i / 10.0) * 0.5)) * T) as Node2D)
	await wait_physics_frames(2)
	for e in enemies:
		e.set_physics_process(false)
		e.mover.set_physics_process(false)
	var r := Tuning.enemy_separation_radius
	var rng := RandomNumberGenerator.new()
	rng.seed = 45
	var layouts: Array = []
	var dense: Array = []
	for i in 60:
		dense.append(Vector2(1000, 600) + Vector2(rng.randf_range(0, 160), rng.randf_range(0, 160)))
	layouts.append(dense)
	var pairs: Array = []
	for i in 30:
		var base := Vector2(r * (3 * i) + (0.0 if i % 2 else 0.0001), r * 2.0 - 0.0001)
		if i < 10:
			pairs.append_array([base, base])                                   # coincident
		elif i < 20:
			pairs.append_array([Vector2(r * (3 * i), 100.0), Vector2(r * (3 * i) - 0.5, 100.0 + 0.2 * i)])   # a cell border between
		else:
			pairs.append_array([base, base + Vector2(r + 0.5, 0)])          # just beyond the radius
	layouts.append(pairs)
	var straddle: Array = []
	for i in 60:
		straddle.append(Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60)))
	layouts.append(straddle)
	var mixed: Array = []
	for i in 60:
		mixed.append(Vector2(-r * 0.5 + (i % 6) * r * 0.5, -r + floori(i / 6.0) * r * 0.31))
	layouts.append(mixed)
	var nonzero := 0
	for li in layouts.size():
		var layout: Array = layouts[li]
		for i in enemies.size():
			enemies[i].global_position = layout[i]
		SeparationGrid.rebuild(get_tree())
		for e in enemies:
			var a := SeparationGrid.push(e)
			var b := EnemyCommon.separation_all(e)
			if b != Vector2.ZERO:
				nonzero += 1
			assert_almost_eq(a.x, b.x, 0.0001, "layout %d x" % li)
			assert_almost_eq(a.y, b.y, 0.0001, "layout %d y" % li)
	assert_gt(nonzero, 60, "the layouts push")


func test_the_spatial_hash_runs_only_in_path_sessions() -> void:
	# The legacy loop.
	await _arena()
	for i in 6:
		RunState.spawn(CHASER, (OPEN + Vector2(4 + i * 0.3, 0)) * T)
	var b0 := SeparationGrid.builds
	await wait_physics_frames(60)
	assert_eq(SeparationGrid.builds, b0, "the legacy loop: no grid")
	remove_child(game)
	game.free()
	RunState.reset(0)
	# Stage 1.
	await _session_game(&"s1_06_playground")
	RunState.invincible = true
	for i in 6:
		RunState.spawn(CHASER, (OPEN + Vector2(4 + i * 0.3, 0)) * T)
	b0 = SeparationGrid.builds
	await wait_physics_frames(60)
	assert_gt(get_tree().get_nodes_in_group(&"enemy").size(), 0)
	assert_eq(SeparationGrid.builds, b0, "Stage 1: no grid")
	remove_child(game)
	game.free()
	RunState.reset(0)
	# The S8 draft: from frame 0.
	await _draft_game()
	RunState.invincible = true
	game.path_runner.freeze()
	for i in 6:
		RunState.spawn(CHASER, (OPEN + Vector2(4 + i * 0.3, 0)) * T)
	b0 = SeparationGrid.builds
	await wait_physics_frames(30)
	assert_gt(SeparationGrid.builds, b0, "the S8 draft: the grid")
	remove_child(game)
	game.free()
	RunState.reset(0)
	CampaignDB.campaign.sessions.erase(_draft_in_list())
	# The S7 stub: no grid until its `path auto` swap lands (13 s cue + 1.5 s warning).
	await _session_game(STUB)
	RunState.invincible = true
	b0 = SeparationGrid.builds
	var frames := 0
	while RunState.session_path != &"auto" and frames < 1200:
		if get_tree().get_nodes_in_group(&"enemy").size() < 3:
			RunState.spawn(CHASER, (OPEN + Vector2(5, 0)) * T)
		await wait_physics_frames(1)
		frames += 1
		if RunState.session_path != &"auto":
			assert_eq(SeparationGrid.builds, b0, "the stub before its swap: no grid (frame %d)" % frames)
	assert_eq(RunState.session_path, &"auto", "the swap landed")
	gut.p("the stub's swap landed after %d frames, game time %.2f s" % [frames, RunState.game_time])
	assert_gte(RunState.game_time, 13.0, "its `at 13: path auto` cue, then the warning")
	for i in 4:
		RunState.spawn(CHASER, (OPEN + Vector2(5, i * 0.3)) * T)
	await wait_physics_frames(30)
	assert_gt(SeparationGrid.builds, b0, "after the swap: the grid")


# --- Nova -----------------------------------------------------------------------------------

func test_nova_rank_1_blasts_every_3_seconds() -> void:
	await _arena()
	var lo := _loadout()
	var near := await _frozen(CHASER, OPEN + Vector2(1, 0))
	var far := await _frozen(CHASER, OPEN + Vector2(2.5, 0))
	var log := _damage_log(&"weapon:nova")
	var frames: Array[int] = []
	_on(EventBus.explosion, func(_pos: Vector2, radius: float) -> void:
		if is_equal_approx(radius, 1.5 * T):
			frames.append(Engine.get_physics_frames()))
	lo.set_weapon(&"nova", 1)
	var node := lo.passive_node(&"nova")
	assert_eq(node.get_script(), NovaPulse)
	var start := player.global_position
	await wait_physics_frames(365)
	assert_eq(frames.size(), 2)
	assert_eq(node.novas, 2)
	if frames.size() == 2:
		assert_between(frames[1] - frames[0], 179, 181, "3 s apart")
	assert_true(log.all(func(l: Array) -> bool: return l[0] == near and l[1] == 3.0 and l[2] == &"blast"))
	assert_eq(log.size(), 2, "the near one, twice; never the far one (2.5 T)")
	assert_true(is_instance_valid(far))
	assert_eq(player.global_position, start, "the player is never pushed")


func test_nova_rank_2_shoves_survivors_one_tile() -> void:
	await _arena()
	var lo := _loadout()
	var e := await _frozen(CHASER, OPEN + Vector2(1, 0))
	lo.set_weapon(&"nova", 1)
	var start := e.global_position
	lo.passive_node(&"nova").go_off()
	await wait_physics_frames(60)
	assert_almost_eq(e.global_position.x, start.x, 1.0, "rank 1: no knockback")
	lo.set_weapon(&"nova", 2)
	start = e.global_position
	lo.passive_node(&"nova").go_off()
	await wait_physics_frames(60)
	gut.p("shove: %.1f px" % (e.global_position.x - start.x))
	assert_almost_eq(e.global_position.x - start.x, 1.0 * T, 0.3 * T, "~1 tile")


func test_nova_rank_3_a_dash_sets_it_off_then_waits() -> void:
	await _arena()
	var lo := _loadout()
	lo.set_weapon(&"nova", 3)
	var node := lo.passive_node(&"nova")
	var frames: Array[int] = []
	_on(EventBus.explosion, func(_pos: Vector2, radius: float) -> void:
		if is_equal_approx(radius, 1.5 * T):
			frames.append(Engine.get_physics_frames()))
	await wait_physics_frames(30)
	EventBus.player_dashed.emit()
	assert_eq(node.novas, 1, "a dash sets it off now")
	assert_eq(node.dash_novas, 1)
	await wait_physics_frames(1)
	EventBus.player_dashed.emit()
	assert_eq(node.novas, 1, "the dash trigger waits 3 s")
	await wait_physics_frames(170)
	assert_eq(node.novas, 1, "the regular timer restarted at the dash")
	await wait_physics_frames(12)
	assert_eq(node.novas, 2, "3 s after the dash nova")
	if frames.size() == 2:
		assert_between(frames[1] - frames[0], 179, 181)
	EventBus.player_dashed.emit()
	assert_eq(node.dash_novas, 2, "3 s later a dash works again")
	assert_eq(node.novas, 3)
	await wait_physics_frames(1)   # the blast's deferred ring lands before the scene goes (no leak)


# --- Well -----------------------------------------------------------------------------------

func test_a_player_kill_leaves_a_1_5_s_field_that_pulls_enemies_not_the_player() -> void:
	await _arena()
	var lo := _loadout()
	lo.set_weapon(&"well", 1)
	var victim := await _frozen(CHASER, OPEN + Vector2(3, 0), 1.0)
	var other := await _frozen(CHASER, OPEN + Vector2(4.5, 0))
	player.global_position = (OPEN + Vector2(3, -1.5)) * T
	var p_start := player.global_position
	var o_start := other.global_position
	var at := victim.global_position
	var born := RunState.game_time
	_kill(victim)
	await wait_physics_frames(1)
	var fields := _fields(WellWeaponField)
	assert_eq(fields.size(), 1, "a field")
	assert_eq(lo.passive_node(&"well").fields, 1)
	if fields.is_empty():
		return
	var f: Node2D = fields[0]
	assert_eq(f.position, at)
	assert_almost_eq(f.life, 1.5, 0.0001)
	assert_almost_eq(f.radius, 2.6 * T, 0.0001)
	assert_almost_eq(f.pull, 230.0, 0.0001)
	await wait_physics_frames(30)
	assert_lt(other.global_position.x, o_start.x - 10.0, "an enemy is pulled in")
	assert_eq(player.global_position, p_start, "never the player")
	var waited := 0
	while is_instance_valid(f) and not f.is_queued_for_deletion() and waited < 200:
		await wait_physics_frames(1)
		waited += 1
	assert_almost_eq(RunState.game_time - born, 1.5, 0.05, "1.5 s of game time")


func test_a_bomber_fuse_blast_kill_leaves_no_field() -> void:
	await _arena()
	var lo := _loadout()
	lo.set_weapon(&"well", 1)
	var bomber := await _frozen(BOMBER, OPEN + Vector2(8, 0))
	var victim := await _frozen(CHASER, OPEN + Vector2(8.5, 0), 0.5)
	var killed := []
	_on(EventBus.enemy_killed, func(e: Node, info: RefCounted) -> void: killed.append([e, (info as DamageInfo).faction]))
	bomber.blow_up()   # the fuse: faction enemy
	await wait_physics_frames(2)
	assert_eq(killed.size(), 1, "the blast killed the chaser")
	if killed.size() == 1:
		assert_eq(killed[0][0], victim)
		assert_eq(killed[0][1], &"enemy")
	assert_eq(_fields(WellWeaponField).size(), 0, "an enemy's kill leaves no field")
	assert_eq(lo.passive_node(&"well").fields, 0)


func test_well_fields_stop_at_12_live() -> void:
	await _arena()
	var lo := _loadout()
	lo.set_weapon(&"well", 1)
	var victims: Array[Node2D] = []
	for i in 13:
		victims.append(await _frozen(CHASER, OPEN + Vector2(-8 + i * 0.5, -2), 1.0))
	for v in victims:
		_kill(v)
	await wait_physics_frames(1)
	var node := lo.passive_node(&"well")
	assert_eq(node.MAX_FIELDS, 12, "PLAN v9 R6's fallback (D8)")
	assert_eq(_fields(WellWeaponField).size(), 12)
	assert_eq(node.fields, 12)
	assert_eq(node.capped, 1, "the 13th kill leaves none")
	await wait_physics_frames(100)
	assert_eq(_fields(WellWeaponField).size(), 0, "all gone after 1.5 s")
	_kill(await _frozen(CHASER, OPEN + Vector2(-8, -2), 1.0))
	await wait_physics_frames(1)
	assert_eq(_fields(WellWeaponField).size(), 1, "room again")


func test_well_cap_holds_across_a_rank_up() -> void:
	# M45b review: a rank-up rebuilds the well node; the old node's 12 fields still count.
	await _arena()
	var lo := _loadout()
	lo.set_weapon(&"well", 1)
	var victims: Array[Node2D] = []
	for i in 12:
		victims.append(await _frozen(CHASER, OPEN + Vector2(-8 + i * 0.5, -2), 1.0))
	for v in victims:
		_kill(v)
	await wait_physics_frames(1)
	assert_eq(_fields(WellWeaponField).size(), 12)
	var old_node := lo.passive_node(&"well")
	lo.set_weapon(&"well", 2)
	await wait_physics_frames(1)
	var node := lo.passive_node(&"well")
	assert_ne(node, old_node, "the rank-up rebuilt the node")
	_kill(await _frozen(CHASER, OPEN + Vector2(-8, -3), 1.0))
	await wait_physics_frames(1)
	assert_eq(_fields(WellWeaponField).size(), 12, "still 12 live after the rank-up")
	assert_eq(node.fields, 0)
	assert_eq(node.capped, 1, "the new node counts the old fields")


func test_well_rank_2_pulls_gems() -> void:
	await _arena()
	var lo := _loadout()
	lo.set_weapon(&"well", 1)
	var gem := RunState.spawn(PICKUP, (OPEN + Vector2(8.5, 0)) * T, {&"pickup_kind": &"gem"}) as Node2D
	var victim := await _frozen(CHASER, OPEN + Vector2(7, 0), 1.0)
	var g_start := gem.global_position
	_kill(victim)
	await wait_physics_frames(30)
	assert_eq(gem.global_position, g_start, "rank 1: gems stay")
	await wait_physics_frames(70)
	lo.set_weapon(&"well", 2)
	victim = await _frozen(CHASER, OPEN + Vector2(7, 0), 1.0)
	_kill(victim)
	await wait_physics_frames(30)
	assert_lt(gem.global_position.x, g_start.x - 20.0, "rank 2: pulled toward the centre")


func test_well_rank_3_bites_1_per_second() -> void:
	await _arena()
	var lo := _loadout()
	lo.set_weapon(&"well", 3)
	var log := _damage_log(&"weapon:well")
	var inside := await _frozen(CHASER, OPEN + Vector2(6, 1))
	var victim := await _frozen(CHASER, OPEN + Vector2(6, 0), 1.0)
	_kill(victim)
	await wait_physics_frames(100)
	var bites := log.filter(func(l: Array) -> bool: return l[0] == inside)
	assert_eq(bites.size(), 3, "at 0, 0.5 and 1.0 s of a 1.5 s field")
	assert_true(bites.all(func(l: Array) -> bool: return l[1] == 0.5 and l[2] == &"burn"))
	var total := 0.0
	for l: Array in bites:
		total += float(l[1])
	assert_almost_eq(total, 1.5, 0.0001, "1 damage a second for 1.5 s")


func test_the_v6_well_patch_field_is_unchanged() -> void:
	await _arena()
	var f: Node2D = WellField.new()
	assert_eq(f.life, 1.0)
	assert_eq(f.radius, 2.6 * T)
	assert_eq(f.pull, 230.0)
	assert_eq(f.life, WellField.LIFE)
	assert_false(&"gem_pull" in f)
	assert_false(&"teeth" in f)
	var gem := RunState.spawn(PICKUP, (OPEN + Vector2(8.5, 0)) * T, {&"pickup_kind": &"gem"}) as Node2D
	var e := await _frozen(CHASER, OPEN + Vector2(6, 1))
	var hp: float = e.health.hp()
	var g_start := gem.global_position
	var e_start := e.global_position
	f.position = (OPEN + Vector2(7, 0)) * T
	RunState.world.add_child(f)
	await wait_physics_frames(30)
	assert_eq(gem.global_position, g_start, "no gem pull")
	assert_eq(e.health.hp(), hp, "no damage")
	assert_ne(e.global_position, e_start, "it still pulls enemies")
	await wait_physics_frames(35)
	assert_false(is_instance_valid(f) and not f.is_queued_for_deletion(), "gone after 1 s")


# --- The pool -------------------------------------------------------------------------------

func _pick(runner: PathRunner, i := 0) -> PickOffer:
	runner.want_pick()
	runner._open_offer()
	var offer := game.pick_panel.offer
	game.pick_panel._unlock()
	game.pick_panel.choose(mini(i, offer.cards.size() - 1))
	return offer


func test_nova_and_well_are_never_offered_before_a_tagged_say() -> void:
	await _draft_game()
	var r: PathRunner = game.path_runner
	assert_eq(r.def.offer_pool_extra, [&"nova", &"well", &"haste", &"area", &"might"] as Array[StringName])
	RunState.add_basic(&"levelups")
	r.announce(&"shotgun")
	var seen: Array = []
	for i in 10:
		seen.append_array(_pick(r, i % 3).ids())
	assert_false(&"nova" in seen or &"well" in seen, "no [nova] / [well] cue: never offered")
	assert_false(&"nova" in r.offer_pool())
	r.announce(&"nova")   # what a `say [nova]` cue does
	assert_true(&"nova" in r.offer_pool(), "after its tagged say it can be offered")
	assert_false(&"well" in r.offer_pool())
	r.announce(&"well")
	var lo := _loadout()
	lo.clear()
	lo.set_weapon(&"nova", 1)
	lo.set_weapon(&"orbit", 1)   # F2's route: three weapons held (M50.4a: the shared slots)
	assert_eq(lo.weapon_count(), 3)
	seen.clear()
	for i in 10:
		var offer := _pick(r, i % 3)
		seen.append_array(offer.ids())
		assert_lte(lo.weapon_count(), 3, "M50.4a: never a 4th weapon held")
	assert_false(&"well" in seen, "a 4th weapon is never offered")


# --- Telemetry ------------------------------------------------------------------------------

func test_refusals_reach_the_campaign_line() -> void:
	await _auto_arena()
	_hold_shots(&"player_projectile", 1000, OPEN + Vector2(0, -3))
	_hold_shots(&"enemy_projectile", 1000, OPEN + Vector2(-6, -3))
	_shot(&"enemy_projectile", OPEN + Vector2(-6, -3))
	assert_eq(RunState.player_shots_refused, 1)
	assert_eq(RunState.enemy_shots_refused, 2)
	var rec := CampaignDB.telemetry_record(_draft(), {}, &"won", 0, &"")
	assert_eq(rec["enemy_shots_refused"], 2)
	assert_eq(rec["player_shots_refused"], 1)
	assert_eq(rec["schema"], 4, "additive keys: the schema stays 4")
	var run := Telemetry.build_record(&"won")
	assert_eq(run["enemy_shots_refused"], 2)
	assert_eq(run["player_shots_refused"], 1)
	await wait_physics_frames(1)   # the pending shots land before the scene goes (no leak)
	RunState.reset(1)
	assert_eq(RunState.enemy_shots_refused, 0)
	assert_eq(RunState.player_shots_refused, 0)


# --- Replay ---------------------------------------------------------------------------------

func _replay_hashes() -> Array:
	await _auto_arena(11)
	game.spawner.enabled = true
	var lo := _loadout()
	for id: StringName in [&"pistol", &"nova", &"well"]:   # M50.4a: 3 shared slots
		lo.set_weapon(id, 3)
	var out: Array = []
	for i in 90:   # 15 s
		await wait_physics_frames(10)
		var parts: Array[String] = []
		for group: StringName in [&"enemy", &"player_projectile", &"enemy_projectile", &"pickup"]:
			for n in get_tree().get_nodes_in_group(group):
				parts.append("%s %.2f %.2f" % [group, (n as Node2D).global_position.x, (n as Node2D).global_position.y])
		parts.sort()
		parts.append("p %.2f %.2f k %d" % [player.global_position.x, player.global_position.y, RunState.kills])
		out.append(hash("|".join(parts)))
	var nodes := [lo.passive_node(&"nova").novas, lo.passive_node(&"well").fields]
	await wait_physics_frames(1)   # a blast's deferred ring lands before the scene goes (no leak)
	remove_child(game)
	game.free()
	RunState.reset(0)
	return [out, nodes]


func test_auto_with_nova_and_well_replays_to_the_same_hash() -> void:
	var a: Array = await _replay_hashes()
	var b: Array = await _replay_hashes()
	gut.p("novas / well fields: %s" % [a[1]])
	assert_gt(int(a[1][0]), 3, "nova went off")
	assert_gt(int(a[1][1]), 0, "kills left fields")
	assert_eq(a[1], b[1])
	assert_eq(a[0], b[0], "the same seed, the same run")


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
