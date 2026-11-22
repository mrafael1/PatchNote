extends GutTest
## M29: the bomber (PLAN v5 3), the enemy the enemy_bomber change ships: it walks in,
## stops near the player, telegraphs, then its blast hurts the player and other enemies,
## and it is gone.

const BOMBER := preload("res://entities/enemy_bomber.tscn")
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


func test_a_bomber_telegraphs_then_blows_up_hurting_the_player_and_enemies() -> void:
	var neighbour := await _spawn(CHASER, OPEN + Vector2(1.6, 1.0))
	(neighbour.get_node("Mover") as Node).set_physics_process(false)
	var near_death := await _spawn(CHASER, OPEN + Vector2(1.2, -0.9))
	(near_death.get_node("Mover") as Node).set_physics_process(false)
	near_death.health.take(DamageInfo.make(near_death.health.hp() - 0.5, &"projectile", &"player"))
	var neighbour_hp: float = neighbour.health.hp()
	var director_kills: int = game.director.get(&"_kills_since_prompt")
	var bomber := await _spawn(BOMBER, OPEN + Vector2(1.2, 0))
	var hp_before := _player_hp()
	var kills_before := RunState.kills
	await wait_physics_frames(3)
	assert_true(bomber.is_fuse_lit(), "in range: the fuse is lit")
	assert_eq(bomber.fuses, 1)
	assert_eq(bomber.mover.wish, Vector2.ZERO, "it stops to telegraph")
	await wait_seconds(Tuning.bomber_windup * 0.5)
	assert_true(is_instance_valid(bomber), "not before the windup ends")
	assert_gt(bomber.visual.telegraph, 0.0, "it grows and flashes")
	await wait_seconds(Tuning.bomber_windup * 0.5 + 0.15)
	assert_false(is_instance_valid(bomber) and not bomber.is_queued_for_deletion(), "gone after its blast")
	assert_eq(_player_hp(), hp_before - Tuning.bomber_blast_damage, "the blast hurts the player")
	assert_lt(neighbour.health.hp(), neighbour_hp, "and enemies in range")
	assert_false(is_instance_valid(near_death) and not near_death.is_queued_for_deletion(), "the blast killed one")
	assert_eq(RunState.kills, kills_before, "neither its own death nor its victims are the player's kills")
	assert_eq(game.director.get(&"_kills_since_prompt"), director_kills, "nor do they pace the prompts")


## The fuse lights inside the blast's reach: a player who stands still is hit.
func test_a_bomber_walking_in_hits_a_player_who_stands_still() -> void:
	assert_lt(Tuning.bomber_trigger_range, Tuning.bomber_blast_radius + Explosion.BODY_MARGIN)
	var bomber := await _spawn(BOMBER, OPEN + Vector2(5, 0))
	var hp_before := _player_hp()
	for i in 240:
		await wait_physics_frames(1)
		if not is_instance_valid(bomber) or bomber.is_queued_for_deletion():
			break
	assert_false(is_instance_valid(bomber) and not bomber.is_queued_for_deletion(), "it walked in and blew up")
	assert_eq(_player_hp(), hp_before - Tuning.bomber_blast_damage)


func test_a_bomber_far_away_walks_in_and_has_no_contact_damage_or_rim() -> void:
	var bomber := await _spawn(BOMBER, OPEN + Vector2(8, 0))
	await wait_physics_frames(10)
	assert_false(bomber.is_fuse_lit())
	assert_gt(bomber.mover.wish.length(), 0.5, "it walks toward the player")
	assert_eq(bomber.get(&"_contact_damage"), 0.0, "it hurts by its blast only")
	# Held inside a chaser's rim range but outside its own trigger range: no rim.
	(bomber.get_node("Mover") as Node).set_physics_process(false)
	bomber.global_position = player.global_position + Vector2(1.7 * T, 0)
	assert_gt(EnemyCommon.contact_warning(1.7 * T - bomber.contact_reach()), 0.0,
			"a chaser here would show its rim")
	await wait_physics_frames(2)
	assert_false(bomber.is_fuse_lit())
	assert_eq(bomber.visual.rim, 0.0, "its telegraph is the fuse, not the contact rim")


func test_a_bomber_shot_first_dies_without_a_blast() -> void:
	var bomber := await _spawn(BOMBER, OPEN + Vector2(6, 0))
	(bomber.get_node("Mover") as Node).set_physics_process(false)
	var neighbour := await _spawn(CHASER, OPEN + Vector2(6.8, 0.8))
	(neighbour.get_node("Mover") as Node).set_physics_process(false)
	var neighbour_hp: float = neighbour.health.hp()
	var hp_before := _player_hp()
	var kills_before := RunState.kills
	bomber.health.take(DamageInfo.make(99, &"projectile", &"player"))
	await wait_physics_frames(2)
	assert_false(is_instance_valid(bomber))
	assert_eq(_player_hp(), hp_before)
	assert_eq(neighbour.health.hp(), neighbour_hp, "no blast")
	assert_eq(RunState.kills, kills_before + 1, "shooting it is a kill")


func test_split_halves_of_a_bomber_are_bombers() -> void:
	RunState.apply(MutationDB.get_mutation(&"enemies_split"), true)
	var bomber := await _spawn(BOMBER, OPEN + Vector2(8, 0))
	bomber.health.take(DamageInfo.make(99, &"projectile", &"player"))
	await wait_physics_frames(3)
	var halves := get_tree().get_nodes_in_group(&"enemy")
	assert_eq(halves.size(), 2)
	for h in halves:
		assert_eq(h.get(&"archetype"), &"bomber")
		assert_eq(h.get(&"generation"), 1)


func test_the_spawner_sends_bombers_only_when_unlocked_and_never_on_the_turn_grid() -> void:
	var spawner: Spawner = game.spawner
	spawner.set(&"_elapsed", Tuning.spawn_bomber_delay + 1.0)
	var counts := {}
	for i in 2000:
		var t := spawner.pick_type()
		counts[t] = int(counts.get(t, 0)) + 1
	assert_gt(int(counts.get(&"bomber", 0)), 100, "inert: everything unlocked")
	SaveGame.use_snapshot("", true)
	counts.clear()
	for i in 2000:
		counts[spawner.pick_type()] = true
	assert_false(counts.has(&"bomber"), "a new save has no bomber")
	assert_false(counts.has(&"tank"), "nor a tank")
	SaveGame.go_inert()
	RunState.rules.turn_based = true
	counts.clear()
	for i in 2000:
		counts[spawner.pick_type()] = true
	RunState.rules.turn_based = false
	assert_false(counts.has(&"bomber"), "B2 has no bomber role")
