extends GutTest
## Health, spawning, the arena data and a short run of the real game scene.

const Fx := preload("res://tests/gut/fixtures.gd")
const CHASER := preload("res://entities/enemy_chaser.tscn")

var world: Node2D
var _saved_cap := 0


func before_each() -> void:
	RunState.reset(1)
	world = Node2D.new()
	add_child_autofree(world)
	RunState.world = world
	_saved_cap = Tuning.hard_max_enemies


func after_each() -> void:
	Tuning.hard_max_enemies = _saved_cap
	RunState.reset(0)
	RunState.world = null


func _enemy_with_health(base_hp: float) -> Health:
	var e := Fx.make_entity(&"enemy", "E")
	world.add_child(e)
	var h := Component.attach(e, Health) as Health
	h.base_max_hp = base_hp
	return h


func test_damage_kills_and_reports_once() -> void:
	var h := _enemy_with_health(3.0)
	watch_signals(EventBus)
	watch_signals(h)
	for i in 5:
		h.take(DamageInfo.make(1.0, &"projectile", &"player"))
	assert_true(h.dead)
	assert_signal_emit_count(EventBus, "entity_damaged", 3)
	assert_signal_emit_count(EventBus, "enemy_killed", 1)
	assert_signal_emit_count(h, "died", 1)
	assert_eq(RunState.kills, 1)
	assert_eq(RunState.kills_by_source.get(&"base"), 1)


func test_rule_change_keeps_hp_ratio_and_revert_restores_max() -> void:
	var h := _enemy_with_health(10.0)
	h.take(DamageInfo.make(5.0, &"projectile", &"player"))
	assert_almost_eq(h.hp(), 5.0, 0.001)
	var horde := MutationDB.get_mutation(&"horde_mode")
	RunState.apply(horde)
	assert_almost_eq(h.max_hp(), 6.0, 0.001)
	assert_almost_eq(h.hp(), 3.0, 0.001, "still at half")
	assert_false(h.dead, "a rule change never kills")
	RunState.revert(horde)
	assert_almost_eq(h.max_hp(), 10.0, 0.001)
	assert_almost_eq(h.hp(), 5.0, 0.001)


func test_player_invulnerability_and_debug_invincible() -> void:
	var p := Fx.make_entity(&"player", "P")
	world.add_child(p)
	var h := Component.attach(p, Health) as Health
	h.base_max_hp = 5.0
	h.scales_with_enemy_rule = false
	h.invuln_time = 0.8
	h.take(DamageInfo.make(1.0, &"contact", &"enemy"))
	h.take(DamageInfo.make(1.0, &"contact", &"enemy"))
	assert_almost_eq(h.hp(), 4.0, 0.001, "second hit lands during invulnerability")
	RunState.game_time += 1.0
	RunState.invincible = true
	h.take(DamageInfo.make(1.0, &"contact", &"enemy"))
	assert_almost_eq(h.hp(), 4.0, 0.001, "debug invincibility")


func test_spawn_registers_entity_and_applies_stacked_patches() -> void:
	var m := Fx.make(Fx.FxComponent, &"fx_component")
	RunState.apply(m)
	var node := RunState.spawn(CHASER, Vector2(100, 100))
	assert_not_null(node)
	assert_eq(RunState.count(&"enemy"), 0, "enters the tree deferred")
	await wait_physics_frames(2)
	assert_eq(RunState.count(&"enemy"), 1)
	assert_true(node.is_in_group(&"entities"))
	assert_not_null(Component.find(node, Fx.FxComp), "patch component attached on spawn")
	assert_eq((node as Node2D).position, Vector2(100, 100))


func test_spawn_respects_the_hard_cap() -> void:
	Tuning.hard_max_enemies = 3
	var made := 0
	for i in 10:
		if RunState.spawn(CHASER, Vector2(100 + i * 50, 100)) != null:
			made += 1
	assert_eq(made, 3, "pending spawns count toward the cap")
	await wait_physics_frames(2)
	assert_eq(RunState.count(&"enemy"), 3)
	assert_null(RunState.spawn(CHASER, Vector2.ZERO))


func test_arena_spawn_points_are_in_free_space() -> void:
	var arena := Arena.new()
	autofree(arena)
	var inner := arena.bounds.grow(-Tuning.TILE)
	assert_gt(arena.spawn_points.size(), 11)
	for p in arena.spawn_points:
		assert_true(inner.has_point(p), "spawn %s inside the border" % p)
		assert_gte(arena.distance_to_blocks(p), Tuning.TILE * 0.95, "spawn %s clear of blocks" % p)
	assert_gte(arena.distance_to_blocks(arena.player_start), Tuning.TILE * 0.45)


func test_arena_blocks_stay_inside_bounds_and_do_not_overlap() -> void:
	var arena := Arena.new()
	autofree(arena)
	for i in arena.blocks.size():
		assert_true(arena.bounds.encloses(arena.blocks[i]), "block %d inside bounds" % i)
		# Skip the four border pieces, which touch each other by design.
		for j in range(maxi(i + 1, 4), arena.blocks.size()):
			if i >= 4:
				assert_false(arena.blocks[i].intersects(arena.blocks[j]), "blocks %d and %d overlap" % [i, j])


func test_game_scene_runs_with_bot_wave_and_patch_toggle() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	await wait_physics_frames(3)
	RunState.invincible = true
	game.player.set_bot(true)
	game.spawn_wave(12)
	await wait_physics_frames(90)
	# The bot shoots, so one may already be dead: count the kills too.
	assert_eq(RunState.count(&"enemy") + RunState.kills, 12)
	var start: Vector2 = game.arena.player_start
	assert_gt(game.player.global_position.distance_to(start), 10.0, "the bot moved the player")

	var horde := MutationDB.get_mutation(&"horde_mode")
	assert_true(RunState.apply(horde))
	await wait_physics_frames(60)
	assert_almost_eq(game.camera.zoom.x, 0.75, 0.05, "camera follows the zoom rule")
	RunState.revert(horde)
	await wait_physics_frames(60)
	assert_almost_eq(game.camera.zoom.x, 1.0, 0.05)

	var inner: Rect2 = game.arena.bounds
	for e in RunState.live_entities():
		var pos: Vector2 = (e as Node2D).global_position
		assert_true(is_finite(pos.x) and is_finite(pos.y), "%s position is finite" % e.name)
		assert_true(inner.has_point(pos), "%s is inside the arena" % e.name)
		assert_gte(game.arena.distance_to_blocks(pos), 1.0, "%s is not inside a block" % e.name)


func test_chasers_close_in_on_the_player() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	await wait_physics_frames(3)
	RunState.invincible = true
	var chaser := RunState.spawn(CHASER, game.player.global_position + Vector2(300, 0)) as Node2D
	await wait_physics_frames(2)
	var before := chaser.global_position.distance_to(game.player.global_position)
	await wait_physics_frames(60)
	var after := chaser.global_position.distance_to(game.player.global_position)
	assert_lt(after, before - 100.0)
