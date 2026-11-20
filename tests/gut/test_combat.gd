extends GutTest
## M3: shooting, dash, the three enemies and the spawner, in the real game scene.

const Fx := preload("res://tests/gut/fixtures.gd")
const CHASER := preload("res://entities/enemy_chaser.tscn")
const TANK := preload("res://entities/enemy_tank.tscn")
const SHOOTER := preload("res://entities/enemy_shooter.tscn")
const PROJECTILE := preload("res://entities/projectile.tscn")
const T := 48.0
## Open space with no blocks nearby (row 20 is the lane above the bottom border).
const OPEN := Vector2(34, 20)

var game: Node
var player: CharacterBody2D
var input: Fx.ScriptedInput
var _saved := {}


func before_each() -> void:
	for key: String in ["spawn_interval_start", "spawn_interval_end"]:
		_saved[key] = Tuning.get(key)
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	await wait_physics_frames(2)
	RunState.invincible = true
	player = game.player
	input = Fx.ScriptedInput.new()
	player.set_input(input)


func after_each() -> void:
	for key: String in _saved:
		Tuning.set(key, _saved[key])
	RunState.reset(0)
	RunState.world = null


func _place(tile: Vector2) -> void:
	player.global_position = tile * T
	player.velocity = Vector2.ZERO


func _spawn(scene: PackedScene, tile: Vector2) -> CharacterBody2D:
	var e := RunState.spawn(scene, tile * T) as CharacterBody2D
	await wait_physics_frames(2)
	return e


func _freeze(enemy: Node) -> void:
	enemy.set_physics_process(false)
	(enemy.get_node("Mover") as Node).set_physics_process(false)


func _fire_projectile(from_tile: Vector2, velocity: Vector2) -> Node2D:
	var p := RunState.spawn(PROJECTILE, from_tile * T, {&"velocity": velocity}) as Node2D
	await wait_physics_frames(1)
	return p


func test_holding_fire_shoots_at_the_cooldown_rate() -> void:
	_place(OPEN)
	watch_signals(EventBus)
	input.aim_dir = Vector2.RIGHT
	input.fire = true
	await wait_physics_frames(60)
	input.fire = false
	var shots: int = get_signal_emit_count(EventBus, "projectile_fired")
	assert_between(shots, 5, 7, "about 1 / 0.18 s shots per second")


func test_projectiles_kill_an_enemy_and_are_attributed() -> void:
	_place(OPEN)
	var chaser := await _spawn(CHASER, OPEN + Vector2(6, 0))
	_freeze(chaser)
	watch_signals(EventBus)
	input.aim_dir = Vector2.RIGHT
	input.fire = true
	for i in 120:
		await wait_physics_frames(1)
		if RunState.kills > 0:
			break
	input.fire = false
	assert_eq(RunState.kills, 1)
	assert_eq(RunState.kills_by_source.get(&"base"), 1)
	assert_signal_emit_count(EventBus, "enemy_killed", 1)
	assert_eq(get_signal_emit_count(EventBus, "projectile_hit"), 3, "a chaser takes three hits")
	await wait_physics_frames(2)
	assert_eq(RunState.count(&"enemy"), 0)


func test_projectile_stops_at_a_wall_and_reports_the_normal() -> void:
	watch_signals(EventBus)
	# Fired down at the floor (the bottom border starts at row 21).
	await _fire_projectile(Vector2(34, 20), Vector2(0, 900))
	await wait_physics_frames(10)
	assert_signal_emit_count(EventBus, "projectile_hit_wall", 1)
	var args: Array = get_signal_parameters(EventBus, "projectile_hit_wall")
	assert_almost_eq((args[1] as Vector2).y, 21 * T, 1.0, "contact point is on the floor")
	assert_almost_eq(args[2] as Vector2, Vector2(0, -1), Vector2(0.01, 0.01), "normal points up")
	assert_eq(RunState.count(&"player_projectile"), 0, "removed without a bounce rule")


func test_fast_projectile_does_not_tunnel_through_a_thin_ledge() -> void:
	watch_signals(EventBus)
	# Straight up at the one-tile ledge on row 18 (columns 24-30), far faster than normal.
	await _fire_projectile(Vector2(27, 20), Vector2(0, -6000))
	await wait_physics_frames(5)
	assert_signal_emit_count(EventBus, "projectile_hit_wall", 1)
	var args: Array = get_signal_parameters(EventBus, "projectile_hit_wall")
	assert_almost_eq((args[1] as Vector2).y, 19 * T, 1.0, "stopped at the underside of the ledge")


func test_bounce_rule_reflects_projectiles() -> void:
	RunState.apply(Fx.make(Fx.FxBounce, &"fx_bounce"))
	watch_signals(EventBus)
	var p := await _fire_projectile(Vector2(34, 20), Vector2(300, 900))
	await wait_physics_frames(6)
	assert_true(is_instance_valid(p) and not p.is_queued_for_deletion(), "still flying after the first wall")
	assert_lt(p.get("velocity").y, 0.0, "reflected off the floor")
	assert_gt(p.get("velocity").x, 0.0, "kept its sideways direction")
	await wait_physics_frames(200)
	assert_eq(get_signal_emit_count(EventBus, "projectile_hit_wall"), 3, "two bounces, then removed on the third wall")
	assert_eq(RunState.count(&"player_projectile"), 0)


func test_projectile_gravity_rule_makes_shots_arc() -> void:
	RunState.add_ai(MutationDB.get_mutation(&"gravity_on"), &"stage")
	var straight := await _fire_projectile(Vector2(10, 10.5), Vector2(600, 0))
	await wait_physics_frames(15)
	assert_almost_eq(straight.global_position.y, 10.5 * T, 0.5, "no arc without the rule")
	RunState.apply(Fx.make(Fx.FxArc, &"fx_arc"))
	var arcing := await _fire_projectile(Vector2(10, 10.5), Vector2(600, 0))
	await wait_physics_frames(15)
	assert_gt(arcing.global_position.y, 10.5 * T + 15.0, "drops with the rule")


func test_dash_covers_its_distance_with_invulnerability_and_cooldown() -> void:
	_place(OPEN)
	watch_signals(EventBus)
	var start := player.global_position
	input.move = Vector2.RIGHT
	await wait_physics_frames(2)
	input.move = Vector2.ZERO
	input.tap_dash()
	await wait_physics_frames(3)
	assert_true(player.health.is_invulnerable(), "immune during the dash")
	await wait_physics_frames(30)
	var travelled := player.global_position.x - start.x
	assert_between(travelled, 3.3 * T, 4.6 * T, "about 3.5 tiles plus a short slide")
	assert_signal_emit_count(EventBus, "player_dashed", 1)
	input.tap_dash()
	await wait_physics_frames(5)
	assert_signal_emit_count(EventBus, "player_dashed", 1, "still on cooldown")
	await wait_physics_frames(50)
	input.tap_dash()
	await wait_physics_frames(5)
	assert_signal_emit_count(EventBus, "player_dashed", 2, "ready again after the cooldown")


func test_dash_works_the_same_with_gravity() -> void:
	RunState.add_ai(MutationDB.get_mutation(&"gravity_on"), &"stage")
	_place(OPEN + Vector2(0, 0.6))
	await wait_physics_frames(30)
	var start := player.global_position
	input.move = Vector2.RIGHT
	await wait_physics_frames(2)
	input.move = Vector2.ZERO
	input.tap_dash()
	await wait_physics_frames(30)
	assert_between(player.global_position.x - start.x, 3.3 * T, 4.6 * T)


func test_tank_resists_knockback_and_takes_more_hits() -> void:
	var chaser := await _spawn(CHASER, Vector2(30, 20))
	var tank := await _spawn(TANK, Vector2(40, 20))
	assert_gt(tank.health.max_hp(), chaser.health.max_hp() * 3.0)
	for e: CharacterBody2D in [chaser, tank]:
		_freeze(e)
		e.velocity = Vector2.ZERO
	chaser.mover.knockback(Vector2(300, 0))
	tank.mover.knockback(Vector2(300, 0))
	assert_almost_eq(chaser.velocity.x, 300.0, 1.0)
	assert_almost_eq(tank.velocity.x, 60.0, 1.0)


func test_shooter_floats_under_gravity_and_hurts_the_player() -> void:
	RunState.add_ai(MutationDB.get_mutation(&"gravity_on"), &"stage")
	_place(OPEN + Vector2(0, 0.6))
	var shooter := await _spawn(SHOOTER, OPEN + Vector2(7, -3))
	var chaser := await _spawn(CHASER, Vector2(3, 3))
	await wait_physics_frames(30)
	assert_true(shooter.mover.ignores_gravity())
	assert_eq(shooter.motion_mode, CharacterBody2D.MOTION_MODE_FLOATING, "shooter is not under gravity")
	assert_eq(chaser.motion_mode, CharacterBody2D.MOTION_MODE_GROUNDED, "a chaser spawned at the same time is")
	assert_lt(shooter.global_position.y, 19.0 * T, "did not drop to the floor")
	chaser.queue_free()

	RunState.invincible = false
	var hit := false
	for i in 400:
		await wait_physics_frames(1)
		if player.health.hp() < 5.0:
			hit = true
			break
	RunState.invincible = true
	assert_true(hit, "its projectile reached the player")
	assert_true(RunState.kills == 0)


func test_enemy_projectiles_never_bounce_or_arc() -> void:
	RunState.add_ai(MutationDB.get_mutation(&"gravity_on"), &"stage")
	RunState.apply(Fx.make(Fx.FxBounce, &"fx_bounce"))
	RunState.apply(Fx.make(Fx.FxArc, &"fx_arc"))
	_place(Vector2(3, 3))
	var p := RunState.spawn(PROJECTILE, Vector2(34, 19.5) * T, {
		&"kind": &"enemy_projectile", &"faction": &"enemy", &"velocity": Vector2(320, 0)}) as Node2D
	await wait_physics_frames(20)
	assert_almost_eq(p.global_position.y, 19.5 * T, 0.5, "flies straight")
	p.set("velocity", Vector2(0, 900))
	await wait_physics_frames(10)
	assert_eq(RunState.count(&"enemy_projectile"), 0, "removed at the first wall")


func test_chaser_gets_around_a_ledge_without_gravity() -> void:
	# The player is directly above the row-18 ledge (columns 24-30), the chaser below it.
	_place(Vector2(27, 16))
	var chaser := await _spawn(CHASER, Vector2(27, 20))
	var reached := false
	for i in 600:
		await wait_physics_frames(1)
		if chaser.global_position.distance_to(player.global_position) <= Tuning.contact_range:
			reached = true
			break
	assert_true(reached, "went around the ledge within 10 s")


func test_contact_damage_knocks_the_player_back() -> void:
	_place(OPEN)
	RunState.invincible = false
	var chaser := await _spawn(CHASER, OPEN + Vector2(2, 0))
	var hit := false
	for i in 120:
		await wait_physics_frames(1)
		if player.health.hp() < 5.0:
			hit = true
			break
	RunState.invincible = true
	assert_true(hit)
	assert_lt(player.velocity.x, -50.0, "pushed away from the chaser")
	assert_true(is_instance_valid(chaser))


func test_spawner_fills_to_the_rule_cap_and_follows_horde_mode() -> void:
	_place(OPEN)
	Tuning.spawn_interval_start = 0.02
	Tuning.spawn_interval_end = 0.02
	game.spawner.enabled = true
	await wait_physics_frames(120)
	game.spawner.enabled = false
	await wait_physics_frames(2)
	assert_between(RunState.count(&"enemy"), 25, 26, "stops at max_enemies")
	for e in get_tree().get_nodes_in_group(&"enemy"):
		assert_true(e.get("from_spawner"), "marked as spawner-spawned")
		_freeze(e)
	RunState.apply(MutationDB.get_mutation(&"horde_mode"))
	assert_eq(game.spawner.current_cap(), 75)
	RunState.revert(MutationDB.get_mutation(&"horde_mode"))
	assert_eq(RunState.count(&"enemy"), 25 if RunState.count(&"enemy") == 25 else 26, "revert never culls")


func test_spawner_picks_points_away_from_the_player() -> void:
	_place(OPEN)
	for i in 60:
		var p: Vector2 = game.spawner.pick_point()
		assert_gte(p.distance_to(player.global_position), Tuning.spawn_min_distance)
		var offset := (p - player.global_position).abs()
		assert_true(offset.x > 640 or offset.y > 360, "outside the view at %s" % p)


func test_spawner_brings_in_all_three_types() -> void:
	game.spawner.set("_elapsed", Tuning.spawn_tank_delay + 1.0)
	var seen := {}
	for i in 300:
		seen[game.spawner.pick_type()] = true
	assert_eq(seen.size(), 3)


func test_bot_plays_twenty_seconds_and_gets_kills() -> void:
	_place(OPEN)
	player.set_bot(true)
	game.spawner.enabled = true
	await wait_physics_frames(1200)
	assert_gt(RunState.kills, 3, "the bot killed something")
	assert_gt(float(RunState.damage_by_source.get(&"base", 0.0)), 0.0)
	for e in RunState.live_entities():
		var pos: Vector2 = (e as Node2D).global_position
		assert_true(is_finite(pos.x) and is_finite(pos.y), "%s finite" % e.name)
		assert_true(game.arena.bounds.has_point(pos), "%s inside the arena at %s" % [e.name, pos])
