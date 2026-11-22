extends GutTest
## M33: the lancer (PLAN v6 3), the enemy the enemy_lancer change ships: it stops in
## range, telegraphs its line, then charges along it, hitting the player and any enemy
## on the way once each.

const LANCER := preload("res://entities/enemy_lancer.tscn")
const CHASER := preload("res://entities/enemy_chaser.tscn")
const T := 48.0
const OPEN := Vector2(34, 20)

var game: Main
var player: CharacterBody2D


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
	player.set_input(load("res://tests/gut/fixtures.gd").ScriptedInput.new())
	player.global_position = OPEN * T
	player.velocity = Vector2.ZERO
	RunState.game_time = 100.0   # past the start grace


func after_each() -> void:
	RunState.invincible = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null


func _spawn(scene: PackedScene, tile: Vector2) -> Node2D:
	var e := RunState.spawn(scene, tile * T) as Node2D
	await wait_physics_frames(2)
	return e


func _player_hp() -> float:
	return (Component.find(player, Health) as Health).hp()


func test_a_lancer_telegraphs_its_line_then_charges_through_everyone_on_it() -> void:
	var lancer := await _spawn(LANCER, OPEN + Vector2(4, 0))
	var bystander := await _spawn(CHASER, OPEN + Vector2(2, 0))
	bystander.set_physics_process(false)   # it stands on the line
	var bystander_hp: float = bystander.health.hp()
	var hp_before := _player_hp()
	var kills := RunState.kills
	await wait_physics_frames(2)
	assert_eq(lancer.lance, lancer.Lance.WINDUP, "in range with a clear line: it telegraphs")
	assert_almost_eq(lancer.lance_dir(), Vector2.LEFT, Vector2(0.01, 0.01), "the line points at the player")
	var at: Vector2 = lancer.global_position
	await wait_seconds(Tuning.lancer_windup * 0.5)
	assert_almost_eq(lancer.global_position, at, Vector2(2, 2), "it stands still while it telegraphs")
	assert_gt(lancer.visual.telegraph, 0.0)
	await wait_seconds(Tuning.lancer_windup * 0.5 + 0.4)
	assert_eq(lancer.charges, 1)
	assert_lt(lancer.global_position.x, at.x - 2.5 * T, "it charged along the line")
	assert_eq(_player_hp(), hp_before - Tuning.lancer_charge_damage, "the player on the line is hit, once")
	assert_eq(bystander.health.hp(), bystander_hp - Tuning.lancer_charge_damage, "so is the enemy on it")
	assert_eq(RunState.kills, kills, "its hits are not the player's kills")
	await wait_seconds(Tuning.lancer_recover + 0.2)
	assert_eq(_player_hp(), hp_before - Tuning.lancer_charge_damage, "one hit per charge")


func test_a_lancer_out_of_range_walks_in() -> void:
	var lancer := await _spawn(LANCER, OPEN + Vector2(9, 0))
	await wait_physics_frames(5)
	assert_eq(lancer.lance, lancer.Lance.WALK)
	assert_lt(lancer.mover.wish.x, 0.0, "it walks toward the player")


func test_a_lancer_ships_through_its_change_and_spawns() -> void:
	assert_has(Unlocks.ARCHETYPES, &"lancer")
	assert_has(ChangeDB.get_change(&"enemy_lancer").unlocks, &"lancer")
	SaveGame.use_snapshot("", true)
	assert_false(Unlocks.enemies().has(&"lancer"), "a fresh save has none")
	SaveGame.ship(&"enemy_lancer", GameVersion.PATCH)
	assert_true(Unlocks.enemies().has(&"lancer"))
	game.spawner.set(&"_elapsed", Tuning.spawn_lancer_delay + 1.0)
	var seen := {}
	for i in 400:
		seen[game.spawner.pick_type()] = true
	assert_true(seen.has(&"lancer"), "the spawner sends lancers once shipped")
	assert_false(seen.has(&"tank"), "and nothing it has not unlocked")
