extends GutTest
## M28: the v0.0 run (PLAN v5 2.1-2.3, 1.7). The look (tier 0 and punchy), the
## readability layer every look keeps (telegraphs, hit and kill confirmation, the
## player-hit vignette, camera lookahead), the prompt announcement, and start
## content gating on a new save.

const Fx := preload("res://tests/gut/fixtures.gd")
const CHASER := preload("res://entities/enemy_chaser.tscn")
const SHOOTER := preload("res://entities/enemy_shooter.tscn")
const T := 48.0
const OPEN := Vector2(34, 20)
const TIER_0 := {"tier": 0, "take": ""}
## Files allowed to read the look: the look itself, its presentation readers, and
## the scene and overlay that set or show it (PLAN v5 1.7).
const LOOK_READERS: Array[String] = ["res://systems/look.gd", "res://systems/feedback.gd",
		"res://systems/camera_rig.gd", "res://entities/projectile.gd", "res://main.gd",
		"res://ui/debug_overlay.gd"]

var game: Main
var player: CharacterBody2D
var input: Fx.ScriptedInput


func before_each() -> void:
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	game.director.enabled = false
	await wait_physics_frames(2)
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()   # the opening wave: each test brings its own enemies
	await wait_physics_frames(1)
	RunState.invincible = true
	player = game.player
	input = Fx.ScriptedInput.new()
	player.set_input(input)


func after_each() -> void:
	SaveGame.go_inert()
	Look.use(Unlocks.FULL_LOOK)
	RunState.reset(0)
	RunState.world = null


func _place(tile: Vector2) -> void:
	player.global_position = tile * T
	player.velocity = Vector2.ZERO


func _spawn(scene: PackedScene, tile: Vector2) -> Node2D:
	var e := RunState.spawn(scene, tile * T) as Node2D
	await wait_physics_frames(2)
	return e


func _hold(enemy: Node) -> void:
	(enemy.get_node("Mover") as Node).set_physics_process(false)


# --- The look ------------------------------------------------------------------

func test_inert_games_show_punchy_and_a_new_save_shows_tier_0() -> void:
	assert_eq(Look.preset.tier, 1, "unlock_all: the full look")
	assert_eq(Look.preset.take, &"punchy")
	SaveGame.use_snapshot("", true)
	assert_eq(Look.use(Unlocks.look()).tier, 0)
	assert_eq(Look.preset.resource_path, Look.TIER_0)
	assert_eq(Look.path_for(1, "punchy"), "res://systems/looks/look_1_punchy.tres")


func test_tier_0_has_no_shake_and_no_hit_stop() -> void:
	var t0 := Look.use(TIER_0)
	assert_eq(t0.shake_scale, 0.0)
	assert_eq(t0.hit_stop, 0.0)
	assert_almost_eq(t0.particle_scale, 0.3, 0.001)
	assert_false(t0.muzzle_flash or t0.trail or t0.screen_flash)
	game.camera.shake(9.0)
	assert_eq(game.camera.shake_left(), 0.0, "no shake in tier 0")
	EventBus.player_hit.emit(DamageInfo.make(1, &"contact", &"enemy"))
	assert_false(RunState.has_time_factor(&"hit_stop"), "no hit stop in tier 0")
	assert_gt(game.feedback.screen.vignette_left(), 0.0, "the vignette shows in every look")

	Look.use(Unlocks.FULL_LOOK)
	game.camera.shake(9.0)
	assert_eq(game.camera.shake_left(), 9.0)
	EventBus.player_hit.emit(DamageInfo.make(1, &"contact", &"enemy"))
	assert_true(RunState.has_time_factor(&"hit_stop"), "punchy is M14 plus hit stop")
	for i in 30:
		await get_tree().process_frame
		if not RunState.has_time_factor(&"hit_stop"):
			break
	assert_false(RunState.has_time_factor(&"hit_stop"), "the stop clears after its real seconds")


## main.gd applies the save's look when a game starts: forced the other way first, so
## a leftover value cannot pass the test.
func test_a_game_starts_with_the_save_look() -> void:
	SaveGame.use_snapshot("", true)
	Look.use(Unlocks.FULL_LOOK)
	var fresh: Main = load("res://main.tscn").instantiate()
	add_child_autofree(fresh)
	await wait_physics_frames(1)
	assert_eq(Look.preset.tier, 0, "a new save plays tier 0")
	fresh.camera.shake(9.0)
	assert_eq(fresh.camera.shake_left(), 0.0)
	SaveGame.go_inert()
	Look.use(TIER_0)
	var inert: Main = load("res://main.tscn").instantiate()
	add_child_autofree(inert)
	await wait_physics_frames(1)
	assert_eq(Look.preset.take, &"punchy", "inert games keep today's feel")


## A hit stop slows the engine but is not slow motion: the B1 tint and the sound
## pitch read the time scale without it.
func test_hit_stop_is_not_read_as_slow_motion() -> void:
	RunState.set_time_factor(RunState.HIT_STOP, 0.0)
	await wait_physics_frames(1)
	assert_almost_eq(Engine.time_scale, RunState.MIN_TIME_SCALE, 0.001)
	assert_eq(RunState.felt_time_scale(), 1.0)
	assert_eq(Sound.pitch_for(RunState.felt_time_scale()), 1.0)
	RunState.set_time_factor(&"fx_slow", 0.5)
	assert_almost_eq(RunState.felt_time_scale(), 0.5, 0.001, "other factors still count")
	RunState.clear_time_factor(&"fx_slow")
	RunState.clear_time_factor(RunState.HIT_STOP)


func test_the_screen_overlay_covers_the_viewport() -> void:
	var screen: ScreenFx = game.feedback.screen
	assert_eq(screen.size, screen.get_viewport_rect().size, "a vignette needs the full screen")
	assert_eq(screen.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_nothing_outside_presentation_reads_the_look() -> void:
	var regex := RegEx.create_from_string("\\bLook\\.")
	var files := _scripts("res://")
	assert_gt(files.size(), 50)
	for path in files:
		if path in LOOK_READERS:
			continue
		if regex.search(FileAccess.get_file_as_string(path)):
			fail_test("%s reads Look" % path)
	pass_test("%d files checked" % files.size())


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for entry in DirAccess.get_files_at(dir):
		if entry.get_extension() == "gd":
			out.append(dir + entry)
	for sub in DirAccess.get_directories_at(dir):
		if sub in ["addons", "tests", ".godot", ".check", "builds"]:
			continue
		out.append_array(_scripts(dir + sub + "/"))
	return out


# --- Readability (every look) --------------------------------------------------

func test_a_shooter_telegraphs_each_shot_and_keeps_its_interval() -> void:
	Look.use(TIER_0)
	# Out of its range while it spawns, so its first telegraph is one the test sees.
	_place(OPEN - Vector2(14, 0))
	var shooter := await _spawn(SHOOTER, OPEN + Vector2(6, 0))
	_hold(shooter)
	assert_eq(shooter.windups, 0)
	_place(OPEN)
	var windup_frames: Array[int] = []
	var shot_frames: Array[int] = []
	var seen_telegraph := false
	var last_windups: int = shooter.windups
	var on_fired := func(p: Node) -> void:
		if p.get(&"faction") == &"enemy":
			shot_frames.append(Engine.get_physics_frames())
	EventBus.projectile_fired.connect(on_fired)
	for i in 300:
		await wait_physics_frames(1)
		if shooter.windups != last_windups:
			last_windups = shooter.windups
			windup_frames.append(Engine.get_physics_frames())
		if shooter.is_winding_up() and shooter.visual.telegraph > 0.3:
			seen_telegraph = true
		if shot_frames.size() >= 2:
			break
	EventBus.projectile_fired.disconnect(on_fired)
	assert_true(seen_telegraph, "it flashes and grows before the shot")
	assert_eq(shot_frames.size(), 2)
	assert_gte(windup_frames.size(), 1)
	if shot_frames.size() < 2 or windup_frames.is_empty():
		return
	var windup := shot_frames[0] - windup_frames[0]
	assert_between(windup, int(Tuning.shooter_windup * 60) - 1, int(Tuning.shooter_windup * 60) + 2,
			"the shot comes shooter_windup after the telegraph starts")
	var interval := shot_frames[1] - shot_frames[0]
	assert_between(interval, int(Tuning.shooter_fire_interval * 60) - 1,
			int(Tuning.shooter_fire_interval * 60) + 3, "the interval is unchanged")


func test_a_chaser_shows_a_red_rim_only_near_contact_and_brighter_closer() -> void:
	assert_eq(EnemyCommon.contact_warning(Tuning.contact_warn_range * T + 1.0), 0.0)
	assert_gt(EnemyCommon.contact_warning(Tuning.contact_warn_range * T - 1.0), 0.0)
	assert_eq(EnemyCommon.contact_warning(0.0), 1.0)
	_place(OPEN)
	var chaser := await _spawn(CHASER, OPEN + Vector2(6, 0))
	_hold(chaser)
	await wait_physics_frames(2)
	assert_eq(chaser.visual.rim, 0.0, "off beyond the range")
	var reach: float = chaser.contact_reach()
	chaser.global_position = player.global_position + Vector2(reach + T, 0)
	await wait_physics_frames(2)
	var far_rim: float = chaser.visual.rim
	assert_gt(far_rim, 0.0, "on inside the range")
	chaser.global_position = player.global_position + Vector2(reach + T * 0.25, 0)
	await wait_physics_frames(2)
	assert_gt(chaser.visual.rim, far_rim, "brighter as it closes in")


func test_a_damaged_enemy_shows_its_hp_lost_until_it_dies() -> void:
	_place(OPEN)
	var shooter := await _spawn(SHOOTER, OPEN + Vector2(8, 0))
	_hold(shooter)
	assert_eq(shooter.visual.hp_shown, 1.0, "no bar at full HP")
	shooter.health.take(DamageInfo.make(1, &"projectile", &"player"))
	assert_almost_eq(shooter.visual.hp_shown, shooter.health.hp_ratio, 0.001)
	assert_lt(shooter.visual.hp_shown, 1.0)
	assert_true(shooter.visual.is_flashing(), "and the white flash")


func test_every_kill_pops_in_every_look() -> void:
	for look: Dictionary in [TIER_0, Unlocks.FULL_LOOK]:
		Look.use(look)
		var before: int = game.feedback.kill_pops
		for i in 3:
			var chaser := await _spawn(CHASER, OPEN + Vector2(4 + i, -3))
			chaser.health.take(DamageInfo.make(999, &"projectile", &"player"))
		await wait_physics_frames(1)
		assert_eq(game.feedback.kill_pops - before, 3, "look %s" % Look.label())
	var pops := game.world.find_children("*", "KillPop", true, false)
	assert_gt(pops.size(), 0, "the ring is in the world")


func test_the_camera_leads_toward_the_aim_inside_the_arena() -> void:
	var cam := game.camera
	_place(OPEN)
	input.aim_dir = Vector2.RIGHT
	await wait_physics_frames(120)
	var view := cam.get_viewport_rect().size / cam.zoom
	assert_almost_eq(cam.lead().x, view.x * Tuning.camera_lookahead, 4.0, "a share of the view")
	assert_almost_eq(cam.lead().y, 0.0, 1.0)
	# Into a corner, aiming out of the arena: the limits still hold the view.
	var bounds: Rect2 = game.genre.arena.bounds
	for corner: int in [-1, 1]:
		var aim := Vector2(corner, corner).normalized()
		player.global_position = (bounds.position if corner < 0 else bounds.end) - aim * 2.0 * T
		input.aim_dir = aim
		await wait_physics_frames(120)
		_assert_view_inside(cam.get_screen_center_position(), view, bounds)


## Per axis: a view that fits stays inside the bounds; one that does not (the headless
## test window is square) is centred on them, as Camera2D's limits do.
func _assert_view_inside(center: Vector2, view: Vector2, bounds: Rect2) -> void:
	for axis in 2:
		if view[axis] <= bounds.size[axis]:
			assert_gte(center[axis] - view[axis] / 2.0, bounds.position[axis] - 1.0, "axis %d" % axis)
			assert_lte(center[axis] + view[axis] / 2.0, bounds.end[axis] + 1.0, "axis %d" % axis)
		else:
			assert_almost_eq(center[axis], bounds.get_center()[axis], 1.0, "axis %d centred" % axis)


# --- The prompt announcement ---------------------------------------------------

func test_the_banner_shows_once_the_kill_gate_is_met_until_the_prompt_opens() -> void:
	var hud := _hud()
	game.director.enabled = true
	await wait_physics_frames(2)
	assert_false(game.director.patch_incoming())
	assert_false(hud.banner_shown(), "not while kills are still needed")
	game.director.set("_kills_since_prompt", Tuning.first_prompt_kills)
	await wait_physics_frames(2)
	assert_true(game.director.patch_incoming())
	assert_true(hud.banner_shown(), "Next patch incoming")
	assert_false(game.prompt_panel.is_open(), "it adds no rule: the time gap still holds")
	game.director.open_prompt()
	await wait_physics_frames(1)
	assert_false(game.director.patch_incoming())
	assert_false(hud.banner_shown())


func _hud() -> Hud:
	for c in game.get_children():
		if c is Hud:
			return c
	return null


# --- Start content (a new save) ------------------------------------------------

func test_a_new_save_never_spawns_a_locked_archetype() -> void:
	SaveGame.use_snapshot("", true)
	assert_eq(Unlocks.enemies(), Tuning.starter_enemies)
	game.spawner.set("_elapsed", Tuning.spawn_tank_delay + 1.0)
	var seen := {}
	for i in 2000:
		var t: StringName = game.spawner.pick_type()
		seen[t] = int(seen.get(t, 0)) + 1
	assert_false(seen.has(&"tank"), "tanks ship later (PLAN v5 2.3)")
	assert_true(seen.has(&"chaser") and seen.has(&"shooter"))
	# The tank's share goes to chasers.
	var chasers := float(seen.get(&"chaser", 0)) / 2000.0
	assert_almost_eq(chasers, 1.0 - Tuning.spawn_shooter_chance, 0.04)


func test_a_new_save_offers_only_the_four_starters() -> void:
	SaveGame.use_snapshot("", true)
	var starters := ["bouncing_projectiles", "enemies_split", "explode_on_hit", "jump_button"]
	var sizes: Array[int] = []
	for i in Tuning.prompts_per_run:
		var offer := game.director.get_offer({})
		sizes.append(offer.cards.size())
		for m in offer.cards:
			assert_has(starters, String(m.id))
		if not offer.cards.is_empty():
			RunState.apply(offer.cards[0])
	assert_eq(sizes, [3, 3, 2] as Array[int], "prompt 3 shows 2 cards (accepted, PLAN v5 9)")


# --- Pacing (PLAN v5 2.1) ------------------------------------------------------

func test_the_v0_run_is_three_prompts_and_a_45_second_wave() -> void:
	assert_eq(Tuning.prompts_per_run, 3)
	assert_eq(Tuning.rc_duration, 45.0)
	assert_lt(Tuning.prompt_min_gap, Tuning.prompt_max_gap)
	# The kill gates are met well before the gaps for the bot, so the gaps set the length.
	var length := Tuning.first_prompt_min_gap + Tuning.prompt_min_gap * (Tuning.prompts_per_run - 1) \
			+ Tuning.rc_duration
	assert_between(length, 170.0, 200.0, "~3 min of game time")


## M30 (PLAN v5 1.7): the 3 tier 1 takes are tuned apart. Each differs from each other
## in at least 3 juice fields and keeps tier 0's palette (palettes are tier 2).
func test_the_tier_1_takes_differ_in_at_least_3_juice_fields() -> void:
	const FIELDS := ["shake_scale", "particle_scale", "hit_stop", "muzzle_flash", "kill_pop_scale",
			"trail", "trail_scale", "screen_flash"]
	var tier_0: LookPreset = load(Look.TIER_0)
	var takes: Array[LookPreset] = []
	for take in ["punchy", "clean", "arcade"]:
		var p: LookPreset = load(Look.path_for(1, take))
		assert_eq(p.palette, tier_0.palette, "%s keeps tier 0's palette" % take)
		takes.append(p)
	for i in takes.size():
		for j in range(i + 1, takes.size()):
			var differ := FIELDS.filter(func(f: String) -> bool: return takes[i].get(f) != takes[j].get(f))
			assert_gte(differ.size(), 3, "%s vs %s: %s" % [takes[i].take, takes[j].take, differ])


## The look mockup's cards show stills captured from the game (tools/mockup_capture.gd),
## not placeholders, one per take, each named after its take.
func test_the_look_mockup_shows_captured_stills() -> void:
	var change: Change = ChangeDB.get_change(&"look_1")
	for take: MockupTake in change.takes:
		assert_eq(take.image.resource_path, "res://devsession/stills/look_1_%s.png" % take.id)
		assert_eq(take.image.get_size(), Vector2(480, 270))
		assert_eq((take.preset as LookPreset).take, take.id)
