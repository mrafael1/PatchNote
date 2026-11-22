extends GutTest
## M33: the shooter's new patches (PLAN v6 3), one section each: orbit (contact
## cooldown), echo (delay), magnet (curve), well (pull), hunter (stun), elite (shield).

const CHASER := preload("res://entities/enemy_chaser.tscn")
const PROJECTILE := preload("res://entities/projectile.tscn")
const T := 48.0
const OPEN := Vector2(34, 20)

var game: Main
var player: CharacterBody2D
var input


func before_each() -> void:
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	game.director.enabled = false
	await wait_physics_frames(2)
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()
	await wait_physics_frames(1)
	player = game.player
	input = load("res://tests/gut/fixtures.gd").ScriptedInput.new()
	player.set_input(input)
	player.global_position = OPEN * T
	player.velocity = Vector2.ZERO
	RunState.invincible = true


func after_each() -> void:
	RunState.invincible = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null


func _mut(id: StringName) -> Mutation:
	return MutationDB.get_mutation(id)


func _frozen_chaser(tile: Vector2) -> Node2D:
	var e := RunState.spawn(CHASER, tile * T) as Node2D
	await wait_physics_frames(2)
	e.set_physics_process(false)
	e.mover.wish = Vector2.ZERO   # the mover keeps the last wish otherwise
	e.velocity = Vector2.ZERO
	return e


func test_every_new_patch_is_a_small_with_a_take_and_ships_through_one_change() -> void:
	for id: StringName in [&"orbit", &"echo", &"magnet", &"well", &"hunter", &"elite"]:
		var m := _mut(id)
		assert_not_null(m, String(id))
		assert_false(m.starter or m.parked or m.is_big or m.is_ai_tier(), String(id))
		assert_eq(MutationDB.problems(m), [] as Array[String], String(id))
		var by := ChangeDB.all.filter(func(c: Change) -> bool: return id in c.unlocks)
		assert_eq(by.size(), 1, "%s ships through one change" % id)


# --- orbit -------------------------------------------------------------------------

func test_orbit_shards_circle_the_player_and_hit_each_enemy_once_per_cooldown() -> void:
	assert_true(RunState.apply(_mut(&"orbit")))
	var shards: Node = null
	for c in player.get_children():
		if c is Component and c.source_patch == &"orbit":
			shards = c
	assert_not_null(shards, "the shards ride on the player")
	assert_almost_eq(shards.shard_position(0).distance_to(player.global_position), 1.5 * T, 0.5)
	# A big frozen target right on the shards' circle: every pass would touch it.
	var target := await _frozen_chaser(OPEN + Vector2(1.5, 0))
	target.health.base_max_hp = 100.0
	var seconds := 2.0
	await wait_seconds(seconds)
	assert_gt(shards.hits, 0, "a shard hit it")
	assert_lte(shards.hits, int(seconds / 0.4) + 1, "at most once per 0.4 s")
	assert_gt(float(RunState.damage_by_source.get(&"orbit", 0.0)), 0.0, "the patch's damage")
	RunState.revert(_mut(&"orbit"))
	await wait_physics_frames(1)
	for c in player.get_children():
		assert_false(c is Component and c.source_patch == &"orbit", "gone on revert")


# --- echo --------------------------------------------------------------------------

func test_echo_fires_each_shot_again_from_where_it_was_fired() -> void:
	assert_true(RunState.apply(_mut(&"echo")))
	var shots: Array[Node2D] = []
	var born: Array[Vector2] = []
	EventBus.entity_spawned.connect(func(e: Node) -> void:
		if e.is_in_group(&"player_projectile"):
			shots.append(e)
			born.append((e as Node2D).position))
	input.aim_dir = Vector2.RIGHT
	input.fire = true
	await wait_physics_frames(1)
	input.fire = false
	await wait_physics_frames(2)
	assert_eq(shots.size(), 1, "the shot")
	var fired_at := born[0]
	player.global_position += Vector2(0, 3 * T)   # walk away: the echo still comes from there
	await wait_seconds(0.4)
	assert_eq(shots.size(), 1, "not yet: 0.6 s")
	await wait_seconds(0.35)
	assert_eq(shots.size(), 2, "the echo")
	assert_eq(shots[1].get(&"source_patch"), &"echo")
	assert_almost_eq(born[1].distance_to(fired_at), 0.0, 1.0, "from where it was fired")
	assert_almost_eq(shots[1].get(&"velocity"), Vector2.RIGHT * player.shooter.projectile_speed, Vector2.ONE)
	await wait_seconds(0.8)
	assert_eq(shots.size(), 2, "an echo does not echo")


# --- magnet ------------------------------------------------------------------------

func _enemy_shot(from: Vector2, velocity: Vector2) -> Node2D:
	return RunState.spawn(PROJECTILE, from, {&"kind": &"enemy_projectile", &"faction": &"enemy",
			&"velocity": velocity}) as Node2D


func test_magnet_bends_an_enemy_shot_into_an_enemy_it_passes() -> void:
	player.global_position = (OPEN + Vector2(0, 6)) * T   # well out of the shot's way
	var target := await _frozen_chaser(OPEN + Vector2(4, 0.8))
	var hp: float = target.health.hp()
	_enemy_shot(OPEN * T, Vector2.RIGHT * 500.0)   # passes 0.8 tiles from it
	await wait_seconds(1.2)
	assert_eq(target.health.hp(), hp, "without the magnet it flies by")
	assert_true(RunState.apply(_mut(&"magnet")))
	_enemy_shot(OPEN * T, Vector2.RIGHT * 500.0)
	await wait_seconds(1.2)
	assert_lt(target.health.hp(), hp, "with it, the shot curves into the enemy")
	assert_gt(float(RunState.damage_by_source.get(&"magnet", 0.0)), 0.0)


func test_magnet_spares_the_enemy_that_fired() -> void:
	assert_true(RunState.apply(_mut(&"magnet")))
	player.global_position = (OPEN + Vector2(0, 6)) * T
	var shooter := await _frozen_chaser(OPEN)
	var hp: float = shooter.health.hp()
	_enemy_shot(OPEN * T + Vector2(26, 0), Vector2.RIGHT * 500.0)
	await wait_seconds(0.6)
	assert_eq(shooter.health.hp(), hp)


# --- well --------------------------------------------------------------------------

func test_a_kill_leaves_a_well_that_drags_nearby_enemies_to_it() -> void:
	assert_true(RunState.apply(_mut(&"well")))
	player.global_position = (OPEN + Vector2(0, 8)) * T
	var victim := await _frozen_chaser(OPEN)
	var near := await _frozen_chaser(OPEN + Vector2(2, 0))
	var far := await _frozen_chaser(OPEN + Vector2(6, 0))
	var near_at: Vector2 = near.global_position
	var far_at: Vector2 = far.global_position
	victim.health.take(DamageInfo.make(99.0, &"projectile", &"player"))
	await wait_seconds(0.5)
	assert_lt(near.global_position.distance_to(OPEN * T), near_at.distance_to(OPEN * T) - 0.5 * T,
			"dragged toward the centre")
	assert_eq(far.global_position, far_at, "out of reach")
	assert_lt(player.global_position.distance_to(OPEN * T + Vector2(0, 8 * T)), 1.0, "never the player")


# --- hunter ------------------------------------------------------------------------

func _hunter() -> Node2D:
	return get_tree().get_first_node_in_group(&"hunter") as Node2D


func test_the_hunter_comes_after_a_minute_cannot_die_and_hits_stun_it() -> void:
	assert_true(RunState.apply(_mut(&"hunter")))
	await wait_physics_frames(3)
	assert_null(_hunter(), "not before a minute")
	RunState.game_time = 61.0
	await wait_physics_frames(3)
	var hunter := _hunter()
	assert_not_null(hunter, "after a minute")
	assert_false(hunter.is_in_group(&"enemy"), "not an enemy: no kill, no cap, no auto-aim")
	var kills := RunState.kills
	for i in hunter.STUN_HITS - 1:
		hunter.health.take(DamageInfo.make(5.0, &"projectile", &"player"))
	assert_false(hunter.is_stunned())
	hunter.health.take(DamageInfo.make(5.0, &"projectile", &"player"))
	assert_true(hunter.is_stunned(), "STUN_HITS hits stun it")
	assert_eq(hunter.stuns, 1)
	assert_false(hunter.health.dead, "it cannot die")
	assert_eq(RunState.kills, kills)
	var at: Vector2 = hunter.global_position
	await wait_seconds(1.0)
	assert_almost_eq(hunter.global_position, at, Vector2(3, 3), "a stunned hunter stands still")
	assert_eq(get_tree().get_nodes_in_group(&"hunter").size(), 1, "one per run")
	RunState.revert(_mut(&"hunter"))
	await wait_physics_frames(3)
	assert_null(_hunter(), "gone with the patch")


func test_the_hunter_follows_the_player() -> void:
	assert_true(RunState.apply(_mut(&"hunter")))
	RunState.game_time = 61.0
	await wait_physics_frames(3)
	var hunter := _hunter()
	hunter.global_position = (OPEN + Vector2(6, 0)) * T   # in the open: the spawn point is random
	await wait_physics_frames(1)
	var d0 := hunter.global_position.distance_to(player.global_position)
	await wait_seconds(1.5)
	assert_lt(hunter.global_position.distance_to(player.global_position), d0 - 50.0)


# --- elite -------------------------------------------------------------------------

func test_every_eighth_spawn_is_an_elite_whose_shield_takes_three_hits() -> void:
	assert_true(RunState.apply(_mut(&"elite")))
	var spawned: Array[Node2D] = []
	for i in 8:
		spawned.append(RunState.spawn(CHASER, (OPEN + Vector2(4 + i, 4)) * T, {&"from_spawner": true}) as Node2D)
	await wait_physics_frames(2)
	var elites := spawned.filter(func(e: Node2D) -> bool: return e.health.shield_hits > 0)
	assert_eq(elites, [spawned[7]], "the eighth")
	var elite: Node2D = spawned[7]
	elite.set_physics_process(false)
	for i in 3:
		assert_false(elite.health.take(DamageInfo.make(1.0, &"projectile", &"player")), "shield hit %d" % i)
	assert_eq(elite.health.hp(), elite.health.max_hp(), "the shield takes hits whole")
	assert_true(elite.health.take(DamageInfo.make(1.0, &"projectile", &"player")), "then it is down")
	# Killing it wipes the enemy shots around it.
	var near := _enemy_shot(elite.global_position + Vector2(2 * T, 0), Vector2.ZERO)
	var far := _enemy_shot(elite.global_position + Vector2(9 * T, 0), Vector2.ZERO)
	await wait_physics_frames(1)
	elite.health.take(DamageInfo.make(99.0, &"projectile", &"player"))
	await wait_physics_frames(1)
	assert_false(is_instance_valid(near), "a shot near it is gone")
	assert_true(is_instance_valid(far), "a far one stays")
