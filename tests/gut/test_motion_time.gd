extends GutTest
## Big patch B1, "Time moves when you move" (PLAN v3 section 2), in the real arena:
## the acceptance numbers, the shot/dash pulse, pauses and death, and its presentation.

const Fx := preload("res://tests/gut/fixtures.gd")
const CHASER := preload("res://entities/enemy_chaser.tscn")

var game: Main
var input: Fx.ScriptedInput
var b1: Mutation


func before_each() -> void:
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.director.enabled = false
	game.spawner.enabled = false
	RunState.invincible = true
	input = Fx.ScriptedInput.new()
	game.player.set_input(input)
	b1 = MutationDB.get_mutation(&"motion_time")


func after_each() -> void:
	RunState.reset(0)
	RunState.world = null


func _settle() -> void:
	RunState.swap_big(b1)
	await wait_physics_frames(30)


func test_b1_is_a_big_patch_that_only_sets_rules() -> void:
	assert_true(b1.is_big)
	assert_true(b1.is_mode_switch)
	var r := RunState.preview_rules([] as Array[Mutation], b1)
	assert_true(r.time_follows_motion)
	assert_almost_eq(r.idle_time_scale, 0.08, 0.0001)
	assert_eq(RunState.motion_factor(), 1.0, "no effect before the swap")


func test_standing_still_for_three_seconds_moves_game_time_by_at_most_0_4() -> void:
	await _settle()
	var t0 := RunState.game_time
	await wait_physics_frames(180)   # 3 s of real time at 60 fps
	var passed := RunState.game_time - t0
	assert_lte(passed, 0.4, "game time while idle: %.3f s" % passed)
	assert_gt(passed, 0.0, "time slows, it never stops")
	assert_almost_eq(Engine.time_scale, 0.08, 0.01)


func test_moving_at_full_speed_runs_time_at_full_speed() -> void:
	await _settle()
	input.move = Vector2.RIGHT
	await wait_physics_frames(20)
	assert_gte(Engine.time_scale, 0.95)
	input.move = Vector2.ZERO
	await wait_physics_frames(60)
	assert_lt(Engine.time_scale, 0.2, "stopping slows time again")


func test_a_shot_or_a_dash_runs_time_for_a_short_pulse() -> void:
	await _settle()
	EventBus.projectile_fired.emit(_faction_node(&"player"))
	await wait_physics_frames(2)
	assert_eq(Engine.time_scale, 1.0, "the muzzle leaves at full speed")
	await wait_physics_frames(60)
	assert_lt(Engine.time_scale, 0.2, "and time slows again after the pulse")
	EventBus.projectile_fired.emit(_faction_node(&"enemy"))
	await wait_physics_frames(2)
	assert_lt(Engine.time_scale, 0.2, "enemy shots do not move time")
	EventBus.player_dashed.emit()
	await wait_physics_frames(2)
	assert_eq(Engine.time_scale, 1.0, "a dash pulses too")


func test_auto_attack_keeps_the_slow_motion() -> void:
	# Owner, 2026-11-20: auto-fire is a bonus under B1, not a way to cancel it.
	RunState.apply(MutationDB.get_mutation(&"auto_attack"))
	await _settle()
	var at := game.player.global_position + Vector2(5 * 48.0, 0)
	var enemy := RunState.spawn(CHASER, at) as CharacterBody2D
	await wait_physics_frames(2)
	enemy.set_physics_process(false)
	(enemy.get_node("Mover") as Node).set_physics_process(false)
	(Component.find(enemy, Health) as Health).base_max_hp = 1000.0   # it must outlive the test
	var shots := [0]
	var count := func(p: Node) -> void:
		if p.get(&"faction") == &"player":
			shots[0] += 1
	EventBus.projectile_fired.connect(count)
	var peak := 0.0
	var t0 := RunState.game_time
	var f0 := Engine.get_physics_frames()
	for i in 180:   # standing still
		await wait_physics_frames(1)
		peak = maxf(peak, Engine.time_scale)
	EventBus.projectile_fired.disconnect(count)
	assert_gt(shots[0], 0, "the weapon kept firing by itself")
	assert_lt(peak, 0.2, "and no auto shot sped time up (peak %.2f)" % peak)
	var real := (Engine.get_physics_frames() - f0) / 60.0
	assert_lte(RunState.game_time - t0, 0.1 * real, "idle time stays slow with auto-fire")
	input.aim_dir = Vector2.RIGHT
	input.fire = true
	peak = 0.0
	for i in 30:
		await wait_physics_frames(1)
		peak = maxf(peak, Engine.time_scale)
	input.fire = false
	assert_eq(peak, 1.0, "a manual shot still pulses")


class FactionNode extends Node:
	var faction: StringName = &"player"


func _faction_node(faction: StringName) -> Node:
	var n := FactionNode.new()
	n.faction = faction
	autofree(n)
	return n


func test_pauses_and_a_dead_player_run_at_full_speed() -> void:
	await _settle()
	RunState.set_pause(&"prompt", true)
	await wait_physics_frames(2)
	assert_eq(Engine.time_scale, 1.0, "panels are never slowed")
	RunState.set_pause(&"prompt", false)
	await wait_physics_frames(60)
	assert_lt(Engine.time_scale, 0.2)
	RunState.invincible = false
	(Component.find(game.player, Health) as Health).take(DamageInfo.make(999, &"contact", &"enemy"))
	await wait_physics_frames(2)
	assert_eq(Engine.time_scale, 1.0, "the report is not slowed by a dead player")


func test_the_world_tint_and_the_sound_pitch_follow_the_time_scale() -> void:
	var tint := game.get_node("TimeTint") as TimeTint
	await wait_physics_frames(2)
	assert_eq(tint.amount(), 0.0, "no tint at normal speed")
	await _settle()
	await wait_physics_frames(2)
	assert_gt(tint.amount(), 0.9)
	assert_eq(TimeTint.amount_for(1.0), 0.0)
	assert_eq(Sound.pitch_for(1.0), 1.0)
	assert_lt(Sound.pitch_for(0.08), 0.6)
	RunState.reset(0)
	await wait_physics_frames(2)
	assert_eq(Engine.time_scale, 1.0, "reset empties the slot and time is normal again")


func test_gravity_under_b1_needs_no_special_code() -> void:
	await _settle()
	RunState.add_ai(MutationDB.get_mutation(&"gravity_on"), &"stage")
	# Lifted into the air and let go: the fall speeds time up as it gathers speed.
	game.player.global_position = game.arena.player_start + Vector2(0, -200)
	game.player.velocity = Vector2.ZERO
	var peak := 0.0
	for i in 90:
		await wait_physics_frames(1)
		if not game.player.is_on_floor():
			peak = maxf(peak, Engine.time_scale)
	assert_gt(peak, 0.9, "falling moves time")
	assert_lt(Engine.time_scale, 0.2, "standing on the floor again: slow")
