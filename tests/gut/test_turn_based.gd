extends GutTest
## Big patch B2, "Turn-based" (PLAN v3 section 3), in the real arena: the world waits
## for the player, one action is one turn, the player ends every turn on the grid,
## the bot's turn policy, and swaps between B1 and B2 in the middle of a wave.

const Fx := preload("res://tests/gut/fixtures.gd")
const TICK := 1.0 / 60.0

var game: Main
var input: Fx.ScriptedInput
var clock: TurnClock
var b1: Mutation
var b2: Mutation


func before_each() -> void:
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.director.enabled = false
	game.spawner.enabled = false
	RunState.invincible = true
	input = Fx.ScriptedInput.new()
	game.player.set_input(input)
	clock = game.turn_clock
	b1 = MutationDB.get_mutation(&"motion_time")
	b2 = MutationDB.get_mutation(&"turn_mode")


func after_each() -> void:
	RunState.reset(0)
	RunState.world = null


func _enter_b2() -> void:
	RunState.swap_big(b2)
	await wait_physics_frames(2)


## Waits until the clock is waiting again after the turn now under way.
func _finish_turn(max_frames := 60) -> void:
	for i in max_frames:
		await wait_physics_frames(1)
		if clock.is_waiting():
			return


func _on_grid(p: Vector2) -> bool:
	return p.distance_to(TurnClock.tile_center(p)) < 0.5


func test_b2_only_sets_rules() -> void:
	var r := RunState.preview_rules([] as Array[Mutation], b2)
	assert_true(r.turn_based)
	assert_eq(r.turn_duration, 0.25)
	assert_true(b2.is_big)


func test_entering_b2_snaps_the_player_to_a_free_tile() -> void:
	game.player.global_position += Vector2(13, -9)
	await _enter_b2()
	assert_true(clock.active)
	assert_true(_on_grid(game.player.global_position), "at %s" % game.player.global_position)
	assert_gte(game.arena.distance_to_blocks(game.player.global_position), TurnClock.FREE_CLEARANCE)
	assert_eq(game.player.velocity, Vector2.ZERO)


func test_with_no_input_game_time_does_not_move() -> void:
	await _enter_b2()
	var t0 := RunState.game_time
	await wait_physics_frames(300)   # 5 s of real time
	assert_eq(RunState.game_time, t0)
	assert_true(RunState.is_paused_for(&"turn"))
	assert_true(clock.is_waiting())


func test_twenty_actions_advance_twenty_turns_of_game_time() -> void:
	await _enter_b2()
	var t0 := RunState.game_time
	for i in 20:
		input.tap_wait()
		await wait_physics_frames(1)
		assert_true(clock.in_turn(), "action %d started a turn" % i)
		await _finish_turn()
	assert_eq(clock.turns, 20)
	assert_almost_eq(RunState.game_time - t0, 20.0 * RunState.rules.turn_duration, TICK + 0.0001)


func test_steps_move_one_tile_and_end_every_turn_on_the_grid() -> void:
	await _enter_b2()
	for dir: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2.RIGHT]:
		var from := game.player.global_position
		var target := from + dir * Tuning.TILE
		input.move = dir
		await wait_physics_frames(1)
		input.move = Vector2.ZERO
		await _finish_turn()
		assert_true(_on_grid(game.player.global_position), "on the grid after a step %s" % dir)
		if clock.is_free(target):
			assert_almost_eq(game.player.global_position.distance_to(target), 0.0, 0.5, "one tile %s" % dir)
		else:
			assert_almost_eq(game.player.global_position.distance_to(from), 0.0, 0.5, "blocked %s" % dir)


func test_held_move_repeats_a_step_each_turn() -> void:
	await _enter_b2()
	var turns := clock.turns
	input.move = Vector2.LEFT
	await wait_physics_frames(int(3 * 0.25 * 60) + 1)
	input.move = Vector2.ZERO
	await _finish_turn()
	assert_gte(clock.turns - turns, 3, "held move keeps stepping")
	assert_true(_on_grid(game.player.global_position))


func test_held_fire_shoots_once_per_turn_and_dash_goes_two_tiles() -> void:
	await _enter_b2()
	var shots := [0]
	var count := func(p: Node) -> void:
		if p.get(&"faction") == &"player":
			shots[0] += 1
	EventBus.projectile_fired.connect(count)
	input.aim_dir = Vector2.RIGHT
	input.fire = true
	await wait_physics_frames(int(4 * 0.25 * 60))
	input.fire = false
	await _finish_turn()
	EventBus.projectile_fired.disconnect(count)
	assert_between(shots[0], clock.turns - 1, clock.turns, "one shot per turn")

	var from := game.player.global_position
	var dir := Vector2.UP if clock.is_free(from + Vector2.UP * 2 * Tuning.TILE) else Vector2.DOWN
	input.move = dir
	input.tap_dash()
	await wait_physics_frames(1)
	input.move = Vector2.ZERO
	await _finish_turn()
	assert_true(_on_grid(game.player.global_position))
	assert_gt(game.player.global_position.distance_to(from), 1.5 * Tuning.TILE, "the dash crossed two tiles")


func test_panels_and_the_end_of_the_run_never_wait_for_a_turn() -> void:
	await _enter_b2()
	RunState.set_pause(&"prompt", true)
	input.tap_wait()
	await wait_physics_frames(2)
	assert_true(clock.is_waiting(), "no turn while a panel is open")
	RunState.set_pause(&"prompt", false)
	RunState.invincible = false
	(Component.find(game.player, Health) as Health).take(DamageInfo.make(999, &"contact", &"enemy"))
	await wait_physics_frames(2)
	assert_false(clock.active)
	assert_false(RunState.is_paused_for(&"turn"), "the report is not held by the clock")
	var t0 := RunState.game_time
	await wait_physics_frames(10)
	assert_gt(RunState.game_time, t0)


func test_wait_does_nothing_outside_b2() -> void:
	input.tap_wait()
	await wait_physics_frames(2)
	assert_false(clock.active)
	assert_false(RunState.is_paused_for(&"turn"))
	assert_false(game.get_node("World/TurnOverlay").visible)


func test_bot_turn_policy_plays_turns() -> void:
	game.player.set_bot(true)
	game.spawn_wave(6)
	await _enter_b2()
	var t0 := RunState.game_time
	await wait_physics_frames(240)
	assert_gt(clock.turns, 10)
	assert_gt(RunState.game_time - t0, 2.0)
	assert_true(game.get_node("World/TurnOverlay").visible)


func test_swapping_b1_and_b2_both_ways_mid_wave() -> void:
	game.player.set_bot(true)
	game.spawner.enabled = true
	game.spawn_wave(8)
	await wait_physics_frames(30)
	for big: Mutation in [b1, b2, b1, b2]:
		RunState.swap_big(big)
		await wait_physics_frames(90)
		assert_eq(RunState.big, big)
		assert_eq(clock.active, big == b2)
		assert_eq(RunState.is_paused_except(&"turn"), false)
		if big == b1:
			assert_false(RunState.is_paused_for(&"turn"), "B1 never waits for turns")
			assert_eq(RunState.motion_factor(), RunState.motion_factor(), "B1 runs")
		else:
			assert_eq(Engine.time_scale, 1.0, "B2 does not scale time")
		for e in RunState.live_entities():
			var pos: Vector2 = (e as Node2D).global_position
			assert_true(game.arena.bounds.grow(1.0).has_point(pos), "%s inside the arena" % e.name)
	RunState.reset(0)
	await wait_physics_frames(2)
	assert_false(RunState.is_paused_for(&"turn"))
