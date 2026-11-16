extends GutTest
## M2: the gravity switch in the real game scene.

const Fx := preload("res://tests/gut/fixtures.gd")
const CHASER := preload("res://entities/enemy_chaser.tscn")
const T := 48.0

var game: Node
var player: CharacterBody2D
var input: Fx.ScriptedInput
var gravity: Mutation


func before_each() -> void:
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	await wait_physics_frames(2)
	RunState.invincible = true
	player = game.player
	input = Fx.ScriptedInput.new()
	player.set_input(input)
	gravity = MutationDB.get_mutation(&"gravity_on")


func after_each() -> void:
	RunState.reset(0)
	RunState.world = null


func _place(tile: Vector2) -> void:
	player.global_position = tile * T
	player.velocity = Vector2.ZERO


## Feet position (tile row) of something standing on top of a block whose top is at `row`.
func _standing_y(row: float) -> float:
	return row * T - 17.0


func _wait_until_grounded(max_frames := 180) -> bool:
	for i in max_frames:
		await wait_physics_frames(1)
		if player.is_on_floor():
			return true
	return false


func _assert_all_entities_valid(label: String) -> void:
	for e in RunState.live_entities():
		var pos: Vector2 = (e as Node2D).global_position
		assert_true(is_finite(pos.x) and is_finite(pos.y), "%s: %s finite" % [label, e.name])
		if not e is CharacterBody2D:
			continue   # projectiles legitimately touch walls
		assert_true(game.arena.bounds.has_point(pos), "%s: %s inside arena at %s" % [label, e.name, pos])
		assert_gt(game.arena.distance_to_blocks(pos), 4.0, "%s: %s inside a block at %s" % [label, e.name, pos])


func test_gravity_on_makes_the_player_fall_and_land() -> void:
	assert_not_null(gravity)
	assert_true(gravity.is_mode_switch)
	_place(Vector2(10, 14))
	await wait_physics_frames(20)
	assert_almost_eq(player.global_position.y, 14 * T, 1.0, "no gravity: stays put")
	watch_signals(EventBus)
	RunState.apply(gravity)
	assert_true(await _wait_until_grounded())
	assert_almost_eq(player.global_position.y, _standing_y(18), 3.0, "landed on the ledge below")
	assert_eq(player.motion_mode, CharacterBody2D.MOTION_MODE_GROUNDED)
	assert_signal_emitted(EventBus, "player_landed")


func test_jump_height_and_short_hop() -> void:
	RunState.apply(gravity)
	_place(Vector2(15, 20))
	assert_true(await _wait_until_grounded())
	var ground := player.global_position.y

	input.tap_jump()
	var top := ground
	for i in 70:
		await wait_physics_frames(1)
		top = minf(top, player.global_position.y)
	var full := ground - top
	assert_between(full, 3.2 * T, 4.0 * T, "full jump clears a 3-tile step with margin")
	assert_true(player.is_on_floor(), "back on the ground")

	input.tap_jump()
	await wait_physics_frames(4)
	input.jump_held = false
	top = ground
	for i in 70:
		await wait_physics_frames(1)
		top = minf(top, player.global_position.y)
	assert_lt(ground - top, full * 0.7, "releasing early gives a shorter jump")


func test_space_does_nothing_without_a_jump_rule() -> void:
	assert_eq(RunState.rules.jumps, 0)
	_place(Vector2(15, 20))
	input.tap_jump()
	await wait_physics_frames(20)
	assert_almost_eq(player.global_position.y, 20 * T, 1.0)


func test_extra_jump_rule_gives_an_air_jump() -> void:
	RunState.apply(gravity)
	_place(Vector2(2.5, 20))   # open column: nothing overhead to bump into
	assert_true(await _wait_until_grounded())
	var ground := player.global_position.y
	input.tap_jump()
	await wait_physics_frames(20)
	input.tap_jump()   # no air jump allowed yet
	var top := ground
	for i in 80:
		await wait_physics_frames(1)
		top = minf(top, player.global_position.y)
	var single := ground - top

	RunState.apply(Fx.make(Fx.FxExtraJump, &"fx_extra_jump"))
	assert_eq(RunState.rules.jumps, 2)
	input.tap_jump()
	await wait_physics_frames(20)
	input.tap_jump()
	top = ground
	for i in 100:
		await wait_physics_frames(1)
		top = minf(top, player.global_position.y)
	assert_gt(ground - top, single + T, "second jump in the air goes higher")


func test_player_can_climb_two_tiers() -> void:
	RunState.apply(gravity)
	# Floor, just left of the row-18 ledge that spans columns 24-30.
	_place(Vector2(22.5, 20))
	assert_true(await _wait_until_grounded())
	input.tap_jump()
	input.move = Vector2.RIGHT
	await wait_physics_frames(26)
	input.move = Vector2.ZERO
	assert_true(await _wait_until_grounded())
	assert_almost_eq(player.global_position.y, _standing_y(18), 3.0, "on the first ledge")

	# Walk to its right end and jump to the row-15 ledge (columns 32-36).
	input.move = Vector2.RIGHT
	for i in 120:
		await wait_physics_frames(1)
		if player.global_position.x >= 30.3 * T:
			break
	input.tap_jump()
	await wait_physics_frames(30)
	input.move = Vector2.ZERO
	assert_true(await _wait_until_grounded())
	assert_almost_eq(player.global_position.y, _standing_y(15), 3.0, "on the second ledge")


func test_reverting_gravity_stops_the_fall() -> void:
	RunState.apply(gravity)
	_place(Vector2(3, 3))
	await wait_physics_frames(15)
	assert_gt(player.velocity.y, 200.0, "falling")
	RunState.revert(gravity)
	await wait_physics_frames(20)
	assert_almost_eq(player.velocity.y, 0.0, 1.0, "no leftover fall speed")
	var y := player.global_position.y
	await wait_physics_frames(20)
	assert_almost_eq(player.global_position.y, y, 0.5, "floating again")
	assert_eq(player.motion_mode, CharacterBody2D.MOTION_MODE_FLOATING)
	assert_eq(RunState.rules.jumps, 0)


func test_flipped_gravity_falls_up_and_keeps_left_right() -> void:
	RunState.apply(gravity)
	RunState.apply(Fx.make(Fx.FxFlipGravity, &"fx_flip", [&"gravity_on"]))
	_place(Vector2(3, 10))
	assert_true(await _wait_until_grounded(240), "lands on the ceiling")
	assert_almost_eq(player.global_position.y, 1 * T + 17.0, 3.0)
	var x := player.global_position.x
	input.move = Vector2.RIGHT
	await wait_physics_frames(20)
	assert_gt(player.global_position.x, x + 40.0, "right is still right")
	input.move = Vector2.ZERO
	var y := player.global_position.y
	input.tap_jump()
	await wait_physics_frames(10)
	assert_gt(player.global_position.y, y + 40.0, "jump pushes away from the ceiling")


func test_fifty_random_toggles_leave_everyone_in_valid_places() -> void:
	player.set_bot(true)
	game.spawn_wave(14)
	await wait_physics_frames(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for i in 50:
		await wait_physics_frames(rng.randi_range(4, 45))
		if RunState.has_patch(&"gravity_on"):
			RunState.revert(gravity)
		else:
			RunState.apply(gravity)
		_assert_all_entities_valid("toggle %d" % i)
	await wait_physics_frames(120)
	_assert_all_entities_valid("settled")
	assert_gt(RunState.live_entities().size(), 0)


func test_chaser_reaches_player_on_the_floor_past_an_obstacle() -> void:
	RunState.apply(gravity)
	_place(Vector2(26, 20))
	# The 2-tile block at columns 20-21 stands between them.
	var chaser := RunState.spawn(CHASER, Vector2(12, 20) * T) as Node2D
	var reached := false
	for i in 600:
		await wait_physics_frames(1)
		if chaser.global_position.distance_to(player.global_position) <= Tuning.contact_range:
			reached = true
			break
	assert_true(reached, "chaser hopped the block and reached the player")


func test_chaser_reaches_player_standing_on_a_ledge() -> void:
	RunState.apply(gravity)
	_place(Vector2(27, 17))   # on the row-18 ledge, columns 24-30
	assert_true(await _wait_until_grounded())
	var chaser := RunState.spawn(CHASER, Vector2(36, 20) * T) as Node2D
	var reached := false
	for i in 900:
		await wait_physics_frames(1)
		if chaser.global_position.distance_to(player.global_position) <= Tuning.contact_range:
			reached = true
			break
	assert_true(reached, "chaser climbed to the player within 15 s")


# --- Reachability of the arena, from its data ---------------------------------

## Surfaces you can stand on for a gravity direction, as [x0, x1, height] where
## height grows upward (against gravity).
func _surfaces(arena: Arena, down: bool) -> Array:
	var out: Array = []
	for rect in arena.blocks:
		var face_y := rect.position.y if down else rect.end.y
		var probe := Vector2(rect.get_center().x, face_y + (-T if down else T))
		if not arena.bounds.grow(-T * 0.5).has_point(probe):
			continue
		if arena.distance_to_blocks(probe) < T * 0.4:
			continue   # no room to stand there
		out.append([rect.position.x, rect.end.x, -face_y if down else face_y])
	return out


func _unreachable(arena: Arena, down: bool) -> Array:
	const MAX_RISE := 3.05 * T    # the jump apex is about 3.6 tiles
	const MAX_GAP := 2.6 * T      # sideways distance covered while above a 3-tile step
	const TAKEOFF := 1.0 * T      # room needed beside a ledge that is directly overhead
	var surfaces := _surfaces(arena, down)
	var floor_index := 0
	for i in surfaces.size():
		if surfaces[i][2] < surfaces[floor_index][2]:
			floor_index = i
	var reached := {floor_index: true}
	var frontier := [floor_index]
	while not frontier.is_empty():
		var a: Array = surfaces[frontier.pop_back()]
		for j in surfaces.size():
			if reached.has(j):
				continue
			var b: Array = surfaces[j]
			var rise: float = b[2] - a[2]
			var gap: float = maxf(0.0, maxf(b[0] - a[1], a[0] - b[1]))
			var ok := false
			if rise <= 0.0:
				ok = gap <= 4.0 * T                      # dropping down
			elif rise <= MAX_RISE and gap <= MAX_GAP:
				ok = gap > 0.0 or a[0] <= b[0] - TAKEOFF or a[1] >= b[1] + TAKEOFF
			if ok:
				reached[j] = true
				frontier.append(j)
	var missing: Array = []
	for j in surfaces.size():
		if not reached.has(j):
			missing.append(surfaces[j])
	return missing


func test_every_ledge_is_reachable_with_gravity_down_and_up() -> void:
	var arena: Arena = game.arena
	assert_gt(_surfaces(arena, true).size(), 20)
	assert_eq(_unreachable(arena, true), [], "gravity down: unreachable surfaces")
	assert_eq(_unreachable(arena, false), [], "gravity up: unreachable surfaces")
