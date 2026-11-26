extends GutTest
## M42.1 (owner G13): the campaign asks which dash (fork_dash): classic, a grappling hook
## or a teleport (Dasher.style, from Unlocks.dash_style()). Every test plays S4 on the
## in-memory (inert) save with the style shipped, the spawner and the cues off.

const Fx := preload("res://tests/gut/fixtures.gd")
const TANK := preload("res://entities/enemy_tank.tscn")
const T := 48.0
## Block Rect2(20, 19, 2, 2) of arena_0: its left face is at x = 20 tiles, rows 19-20.
const BLOCK_LEFT := 20.0 * T
## In front of that block, on the bottom lane (row 20), 223 px of clear floor away.
const BEFORE_BLOCK := Vector2(15, 20)
## Open space on the bottom lane (as in test_combat).
const OPEN := Vector2(34, 20)

var game: Main
var player: CharacterBody2D
var dasher: Dasher
var input: Fx.ScriptedInput
var _saved := {}


func before_each() -> void:
	for key: String in ["grapple_cone_deg"]:
		_saved[key] = Tuning.get(key)


func after_each() -> void:
	for key: String in _saved:
		Tuning.set(key, _saved[key])
	SaveGame.go_inert()
	CampaignDB.active = false
	RunState.session = null
	RunState.session_added.clear()
	RunState.invincible = false
	RunState.reset(0)
	RunState.world = null


## S4 with `style` shipped (&"" = fork_dash unanswered), nothing moving but the player.
func _game(style: StringName) -> Main:
	SaveGame.go_inert()
	if style != &"":
		SaveGame.ship(StringName("dash_%s" % style), GameVersion.PATCH)
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(&"s1_04_level"))
	Main.next_seed = 7
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	game.arena.grow_layout(0.0)   # M47.6c1: S4's walls grow in from a cue; here, all at once
	await wait_physics_frames(2)
	game.session_runner.set_physics_process(false)
	player = game.player
	dasher = player.dasher
	input = Fx.ScriptedInput.new()
	player.set_input(input)
	return game


func _place(tile: Vector2) -> void:
	player.global_position = tile * T
	player.velocity = Vector2.ZERO


## Faces dir and presses the dash on the same frame, then lets go of the stick.
func _press(dir: Vector2, hold := false) -> void:
	input.move = dir
	input.tap_dash()
	await wait_physics_frames(1)
	if not hold:
		input.move = Vector2.ZERO


func _overlaps_world_or_enemy(at: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = (player.get_node("CollisionShape2D") as CollisionShape2D).shape
	q.transform = Transform2D(0.0, at)
	q.collision_mask = Tuning.LAYER_WORLD | Tuning.LAYER_ENEMY_BODY
	q.exclude = [player.get_rid()]
	return not player.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func _edit(id: StringName) -> void:
	RunState.add_ai(RuleDB.get_edit(id), &"edit")


# --- Which dash ----------------------------------------------------------------------

func test_the_style_is_the_saves_answer_in_a_session_and_classic_outside() -> void:
	SaveGame.go_inert()
	RunState.session = null
	assert_eq(Unlocks.dash_answer(), &"classic", "unanswered")
	RunState.session = CampaignDB.get_session(&"s1_04_level")
	assert_eq(Unlocks.dash_style(), &"classic", "unanswered, in a session")
	SaveGame.ship(&"dash_grapple", GameVersion.PATCH)
	assert_eq(Unlocks.dash_style(), &"grapple")
	RunState.session = null
	assert_eq(Unlocks.dash_answer(), &"grapple", "the answer reads the save")
	assert_eq(Unlocks.dash_style(), &"classic", "outside a session: always classic (v6, B2, run_hash)")


func test_the_fork_and_its_changes_load() -> void:
	var f := ChangeDB.get_fork(&"fork_dash")
	assert_not_null(f)
	assert_true(f.campaign)
	assert_eq(f.question, "I think a dash would feel good. What do you want?")
	assert_eq(f.changes().map(func(c: Change) -> StringName: return c.take.id), Change.DASHES)
	for c in f.changes():
		assert_eq(c.kind, &"dash")
		assert_eq(ChangeDB.problems(c), [] as Array[String])
		assert_false("later" in c.pitch.to_lower() or "change" in c.pitch.to_lower(), "no promise of a change")
	var bad := Change.new()
	bad.id = &"dash_bad"
	bad.kind = &"dash"
	assert_eq(ChangeDB.problems(bad).size(), 1, "a dash change needs a take naming a style")


func test_classic_in_a_session_is_the_built_dash() -> void:
	await _game(&"")
	assert_eq(dasher.style, &"classic")
	await wait_physics_frames(1)
	assert_eq(game.hud._label.text, "HP %d\ndash ready" % int(Tuning.player_max_hp))
	_place(OPEN)
	watch_signals(EventBus)
	var start := player.global_position
	input.move = Vector2.RIGHT
	await wait_physics_frames(2)
	input.move = Vector2.ZERO
	input.tap_dash()
	await wait_physics_frames(3)
	assert_true(player.health.is_invulnerable())
	await wait_physics_frames(30)
	assert_between(player.global_position.x - start.x, 3.3 * T, 4.6 * T)
	assert_signal_emit_count(EventBus, "player_dashed", 1)


func test_the_corner_names_the_dash() -> void:
	for style: StringName in [&"grapple", &"teleport"]:
		await _game(style)
		await wait_physics_frames(1)
		var word := "hook" if style == &"grapple" else "teleport"
		assert_eq(dasher.label(), word)
		assert_eq(game.hud._label.text, "HP %d\n%s ready" % [int(Tuning.player_max_hp), word])
		_place(BEFORE_BLOCK if style == &"grapple" else OPEN)
		await _press(Vector2.RIGHT)
		await wait_physics_frames(2)
		assert_eq(game.hud._label.text, "HP %d\n%s ..." % [int(Tuning.player_max_hp), word])
		game.queue_free()
		await wait_physics_frames(2)


# --- The grappling hook ---------------------------------------------------------------

## The hook lands 19 px off the wall (17 half box + 2), at rest, with no bounce under
## bouncy walls (the stick let go), at full speed and in slow-mo.
func test_a_hook_lands_just_off_the_wall_at_rest() -> void:
	for slow: bool in [false, true]:
		await _game(&"grapple")
		_edit(&"edit_bouncy_walls")
		if slow:
			_edit(&"edit_slowmo")
			assert_lt(Engine.time_scale, 1.0)
		_place(BEFORE_BLOCK)
		await wait_physics_frames(1)
		var counts := {"dashed": 0, "hooked": 0, "bounced": 0}
		var on_dashed := func() -> void: counts.dashed = int(counts.dashed) + 1
		var on_hooked := func(_a: Vector2) -> void: counts.hooked = int(counts.hooked) + 1
		EventBus.player_dashed.connect(on_dashed)
		EventBus.player_hooked.connect(on_hooked)
		player.mover.bounced.connect(func(_n: Vector2) -> void: counts.bounced = int(counts.bounced) + 1)
		await _press(Vector2.RIGHT)
		assert_true(player.mover.is_dashing(), "the pull counts as a dash (the lancer reads it)")
		assert_true(player.health.is_invulnerable(), "i-frames for the pull")
		await wait_physics_frames(40)
		assert_almost_eq(BLOCK_LEFT - player.global_position.x, 19.0, 0.5, "slow %s" % slow)
		assert_almost_eq(player.global_position.y, BEFORE_BLOCK.y * T, 0.5, "straight")
		assert_lt(player.velocity.length(), 1.0, "at rest")
		assert_eq(counts, {"dashed": 1, "hooked": 1, "bounced": 0}, "one use, no bounce (slow %s)" % slow)
		EventBus.player_dashed.disconnect(on_dashed)
		EventBus.player_hooked.disconnect(on_hooked)
		game.queue_free()
		await wait_physics_frames(2)


## A gravity change mid-pull cuts the pull where it is: its speed does not fling the
## player on past the hook (M42.1 review).
func test_a_gravity_change_mid_pull_stops_the_pull() -> void:
	await _game(&"grapple")
	_place(BEFORE_BLOCK)
	await wait_physics_frames(1)
	await _press(Vector2.RIGHT)
	assert_true(player.mover.is_pulling())
	_edit(&"edit_gravity_down")
	await wait_physics_frames(1)
	assert_false(player.mover.is_pulling())
	var at := player.global_position.x
	await wait_physics_frames(30)
	assert_lt(absf(player.global_position.x - at), 24.0, "no slide on at pull speed")


## Holding toward the wall after the hook lands walks into it, and bounces like walking
## into a wall does (accepted, PLAN 6.8: as often as walking into it would); never
## during the pull.
func test_holding_into_the_wall_after_a_hook_may_bounce_once_after_arrival() -> void:
	await _game(&"grapple")
	_edit(&"edit_bouncy_walls")
	_place(BEFORE_BLOCK)
	await wait_physics_frames(1)
	var bounces := []
	player.mover.bounced.connect(func(_n: Vector2) -> void: bounces.append(player.mover.is_pulling()))
	await _press(Vector2.RIGHT, true)
	await wait_physics_frames(30)
	input.move = Vector2.ZERO
	gut.p("bounces after arrival while holding into the wall: %d" % bounces.size())
	assert_false(true in bounces, "no bounce while pulling")
	assert_false(_overlaps_world_or_enemy(player.global_position))


## A box, not a ray: a block corner 10 px off the centre line stops the pull.
func test_the_hook_s_box_cast_catches_a_corner_a_ray_would_miss() -> void:
	await _game(&"grapple")
	var y := 19.0 * T - 10.0   # the block's top is row 19; the centre line passes 10 px above it
	player.global_position = Vector2(BEFORE_BLOCK.x * T, y)
	player.velocity = Vector2.ZERO
	var hit := Dasher.grapple_target(player, Vector2.RIGHT)
	assert_false(hit.is_empty())
	assert_almost_eq(BLOCK_LEFT - (hit.stop as Vector2).x, 19.0, 0.5)
	await _press(Vector2.RIGHT)
	await wait_physics_frames(30)
	assert_false(_overlaps_world_or_enemy(player.global_position), "never clips the corner")
	assert_almost_eq(BLOCK_LEFT - player.global_position.x, 19.0, 0.5)


func test_a_hook_s_cooldown_is_longer_than_the_dash_s() -> void:
	await _game(&"grapple")
	_place(BEFORE_BLOCK)
	await _press(Vector2.RIGHT)
	await wait_physics_frames(60)   # 1.0 s
	assert_false(dasher.is_ready(), "1.1 s cooldown")
	await wait_physics_frames(10)
	assert_true(dasher.is_ready())


## A spot where the hook's five casts all fly clear along dir, the whole way (arena_0
## has some): every box along each cast is free, so nothing is merely too close.
func _miss_spot(dir: Vector2) -> Vector2:
	var cone := deg_to_rad(Tuning.grapple_cone_deg)
	for row in range(2, 20):
		for col in range(2, 64):
			var p := Vector2(col + 0.5, row + 0.5) * T
			var clear := true
			for a: float in [0.0, cone, -cone, 2.0 * cone, -2.0 * cone]:
				for k in int(Tuning.grapple_range / 8.0) + 1:
					if _overlaps_world_or_enemy(p + dir.rotated(a) * k * 8.0):
						clear = false
						break
				if not clear:
					break
			if not clear:
				continue
			player.global_position = p
			if Dasher.grapple_target(player, dir).is_empty():
				return p
	return Vector2.INF


func test_a_miss_does_not_move_is_shown_and_costs_a_short_cooldown() -> void:
	await _game(&"grapple")
	var spot := _miss_spot(Vector2.RIGHT)
	assert_ne(spot, Vector2.INF, "arena_0 has open air somewhere")
	player.global_position = spot
	player.velocity = Vector2.ZERO
	await wait_physics_frames(1)
	watch_signals(EventBus)
	await _press(Vector2.RIGHT)
	await wait_physics_frames(2)
	assert_lt(player.global_position.distance_to(spot), 4.0, "no move")
	assert_signal_emit_count(EventBus, "player_hook_missed", 1)
	assert_signal_not_emitted(EventBus, "player_dashed")
	assert_false(dasher.is_ready())
	await wait_physics_frames(24)   # 0.4 s with the press frames
	assert_true(dasher.is_ready(), "0.4 s on a miss")


func test_the_cone_finds_a_wall_off_the_move_line() -> void:
	await _game(&"grapple")
	var spot := _miss_spot(Vector2.RIGHT)
	assert_ne(spot, Vector2.INF)
	var wall := StaticBody2D.new()
	wall.collision_layer = Tuning.LAYER_WORLD
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(40, 40)
	cs.shape = shape
	wall.add_child(cs)
	wall.position = spot + Vector2.RIGHT.rotated(deg_to_rad(20.0)) * 200.0
	RunState.world.add_child(wall)
	player.global_position = spot
	await wait_physics_frames(2)
	player.global_position = spot
	var hit := Dasher.grapple_target(player, Vector2.RIGHT)
	assert_false(hit.is_empty(), "the cone catches it")
	Tuning.grapple_cone_deg = 0.0
	assert_true(Dasher.grapple_target(player, Vector2.RIGHT).is_empty(), "a straight cast alone misses")


func test_under_gravity_a_side_wall_latches_and_a_ceiling_does_not() -> void:
	await _game(&"grapple")
	_edit(&"edit_gravity_down")
	_place(BEFORE_BLOCK)
	await wait_physics_frames(20)   # settle on the floor
	await _press(Vector2.RIGHT)
	await wait_physics_frames(12)   # the pull (223 px at 1400 px/s) is over
	assert_true(player.mover.is_holding(), "a side wall latches")
	var held_at := player.global_position
	await wait_physics_frames(6)
	assert_almost_eq(player.global_position.y, held_at.y, 0.5, "hangs there")
	await wait_physics_frames(20)
	assert_false(player.mover.is_holding(), "for 0.3 s only")
	# A ceiling (pressing up under down gravity): no latch, and no air jump given back.
	game.queue_free()
	await wait_physics_frames(2)
	await _game(&"grapple")
	_edit(&"edit_gravity_down")
	await wait_physics_frames(1)
	player.global_position = Vector2(OPEN.x, 18.5) * T   # under the row-15 ledge, in the air
	player.velocity = Vector2.ZERO
	player.mover._air_jumps_used = 1
	await _press(Vector2.UP)
	assert_true(player.mover.is_pulling())
	for i in 20:
		if not player.mover.is_pulling():
			break
		await wait_physics_frames(1)
	assert_false(player.mover.is_holding(), "no latch on a ceiling")
	assert_eq(player.mover._air_jumps_used, 1, "air jumps are not reset by a hook")
	assert_almost_eq(player.global_position.y, 16.0 * T + 19.0, 1.0, "under the ledge")


func test_under_inverted_controls_the_hook_follows_the_turned_movement() -> void:
	await _game(&"grapple")
	_edit(&"edit_inverted")
	_place(BEFORE_BLOCK)
	await wait_physics_frames(1)
	await _press(Vector2.LEFT)   # turned: right, toward the block
	await wait_physics_frames(30)
	assert_almost_eq(BLOCK_LEFT - player.global_position.x, 19.0, 0.5)


# --- The teleport ---------------------------------------------------------------------

func test_a_teleport_crosses_a_ledge() -> void:
	await _game(&"teleport")
	watch_signals(EventBus)
	player.global_position = Vector2(OPEN.x * T, 16.5 * T)   # under the row-15 ledge
	player.velocity = Vector2.ZERO
	await wait_physics_frames(1)
	var from := player.global_position
	await _press(Vector2.UP)
	assert_almost_eq(player.global_position.y, from.y - Tuning.teleport_distance, 4.0, "through the ledge (plus a frame of walking)")
	assert_signal_emit_count(EventBus, "player_teleported", 1)
	assert_signal_emit_count(EventBus, "player_dashed", 1)
	assert_true(player.health.is_invulnerable())
	await wait_physics_frames(10)
	assert_true(player.health.is_invulnerable(), "0.25 s from the blink")
	await wait_physics_frames(8)
	assert_false(player.health.is_invulnerable())


func test_a_teleport_steps_back_out_of_a_block() -> void:
	await _game(&"teleport")
	_place(OPEN)   # 192 px up is inside the row-15 ledge (720-768)
	await wait_physics_frames(1)
	var from := player.global_position
	await _press(Vector2.UP)
	assert_almost_eq(player.global_position.y, from.y - 168.0, 4.0, "the first free spot back")
	assert_false(_overlaps_world_or_enemy(player.global_position))


func test_a_teleport_never_leaves_the_arena() -> void:
	await _game(&"teleport")
	var inner := game.arena.bounds.grow(-Tuning.TILE)
	for n in [1, 2, 3]:
		for dir: Vector2 in [Vector2.LEFT, Vector2.UP]:
			player.global_position = Vector2(Tuning.TILE + 17.0 + n * T, 20.0 * T) if dir == Vector2.LEFT \
					else Vector2(OPEN.x * T, Tuning.TILE + 17.0 + n * T)
			player.velocity = Vector2.ZERO
			var to := Dasher.teleport_target(player, dir)
			var box := Rect2(to - Vector2(17, 17), Vector2(34, 34))
			assert_true(inner.encloses(box), "%d T from the border, %s: %s" % [n, dir, to])


func test_a_teleport_never_lands_in_a_body_or_a_pocket() -> void:
	await _game(&"teleport")
	var arena := game.arena
	var tank := RunState.spawn(TANK, OPEN * T + Vector2(Tuning.teleport_distance, 0)) as Node2D
	tank.set_physics_process(false)
	await wait_physics_frames(2)
	_place(OPEN)
	var to := Dasher.teleport_target(player, Vector2.RIGHT)
	assert_ne(to, player.global_position)
	assert_false(_overlaps_world_or_enemy(to), "steps back out of the tank")
	var rng := RandomNumberGenerator.new()
	rng.seed = 421
	var landed := 0
	var tries := 0
	while tries < 200:
		var p := Vector2(rng.randf_range(2.0, 64.0), rng.randf_range(2.0, 20.0)) * T
		if _overlaps_world_or_enemy(p):
			continue
		tries += 1
		player.global_position = p
		var dir := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		var t := Dasher.teleport_target(player, dir)
		if t == p:
			continue
		landed += 1
		assert_false(_overlaps_world_or_enemy(t), "from %s along %s" % [p, dir])
		assert_true(arena.is_reachable(t))
		assert_true(arena.bounds.grow(-Tuning.TILE).encloses(Rect2(t - Vector2(17, 17), Vector2(34, 34))))
	assert_gt(landed, 150, "most blinks find a spot")
	gut.p("teleports landed %d/200" % landed)


func test_sealed_pockets_are_not_reachable() -> void:
	# Every arena on disk: list its pockets (S4-S6 play arena_0, which must have none).
	for f in ResourceLoader.list_directory("res://levels/arenas/"):
		if not f.ends_with(".tres"):
			continue
		var a := Arena.new(load("res://levels/arenas/" + f) as ArenaDef)
		gut.p("%s: sealed tiles %s" % [f, a.sealed_tiles()])
		for t in a.sealed_tiles():
			assert_false(a.is_reachable((Vector2(t) + Vector2(0.5, 0.5)) * T))
		if f == "arena_0.tres":
			assert_eq(a.sealed_tiles().size(), 0, "S4-S6's arena has no pocket")
		a.free()
	# A ring of blocks: its inside is sealed.
	var def := ArenaDef.new()
	def.blocks = [Rect2(8, 8, 5, 1), Rect2(8, 12, 5, 1), Rect2(8, 9, 1, 3), Rect2(12, 9, 1, 3)] as Array[Rect2]
	def.player_start = Vector2(30, 15)
	var ring := Arena.new(def)
	assert_false(ring.is_reachable(Vector2(10.5, 10.5) * T), "inside the ring")
	assert_true(ring.is_reachable(Vector2(20.5, 10.5) * T))
	assert_false(ring.is_reachable(Vector2(-10, 10)), "outside the arena")
	assert_eq(ring.sealed_tiles().size(), 9)
	ring.free()


func test_a_boxed_in_teleport_fizzles_and_costs_nothing() -> void:
	await _game(&"teleport")
	player.global_position = Vector2(Tuning.TILE + 24.0, 20.0 * T)   # against the left border
	player.velocity = Vector2.ZERO
	await wait_physics_frames(1)
	watch_signals(EventBus)
	var from := player.global_position
	await _press(Vector2.LEFT)
	assert_signal_emit_count(EventBus, "player_dash_fizzled", 1)
	assert_signal_not_emitted(EventBus, "player_dashed")
	assert_signal_not_emitted(EventBus, "player_teleported")
	assert_true(dasher.is_ready(), "no cooldown")
	assert_lt(player.global_position.distance_to(from), 8.0)


func test_a_teleport_drops_the_fall_speed() -> void:
	await _game(&"teleport")
	_edit(&"edit_gravity_down")
	player.global_position = Vector2(OPEN.x, 17.0) * T
	await wait_physics_frames(1)
	player.velocity = Vector2(0, 600)
	await _press(Vector2.RIGHT)
	assert_lt(player.velocity.y, 100.0, "the fall speed is gone (one frame of gravity left)")


func test_each_style_says_its_own_first_dash_and_s4_line() -> void:
	for style: StringName in Change.DASHES:
		SaveGame.go_inert()
		SaveGame.ship(StringName("dash_%s" % style), GameVersion.PATCH)
		var ctx := CampaignDB.line_context(CampaignDB.get_session(&"s1_04_level"))
		assert_eq(ctx.dash, style)
		# M47.6c1: the dash line is S4's 5 s cue (after the walls), one per style and direction.
		var intro: Array = CampaignDB.get_session(&"s1_04_level").cue_list().filter(func(c: Cue) -> bool:
			return c.action == &"say" and Line.condition_holds(c.cond, ctx)).map(func(c: Cue) -> Line: return c.line)
		var word: String = {&"classic": "dash", &"grapple": "hook", &"teleport": "teleport"}[style]
		assert_true(intro.any(func(l: Line) -> bool: return word in l.text.to_lower()), String(style))
