extends GutTest
## M44 (PLAN v9 1.4): weapons at ranks 1-3. The data (WeaponDef / WeaponDB), the shot
## (Shooter.fire, the projectile's pierce / bounce / blast / size / lifetime), the ten
## rank 2-3 traits, the Loadout, the `give` cue, the two new random streams, F1/F2, the
## binds, and the proof that Stage 1 does not move (every WorldRules field equal to the
## m43.3 fixture, the pistol at rank 1 on today's path).

const CHASER := preload("res://entities/enemy_chaser.tscn")
const PROJECTILE := preload("res://entities/projectile.tscn")
const RulesDump := preload("res://tests/gut/rules_dump.gd")
const BurnLineZone := preload("res://weapons/traits/burn_line_zone.gd")
const BurnLineMod := preload("res://weapons/traits/burn_line_mod.gd")
const StickyMod := preload("res://weapons/traits/sticky_mod.gd")
const RicochetMod := preload("res://weapons/traits/ricochet_mod.gd")
const T := 48.0
const OPEN := Vector2(34, 20)
const TEST_DIR := "user://save_weapons_test/"
## The telemetry log while these tests run: a scratch file, never user://playtest/runs.jsonl.
const TEST_LOG := "user://save_weapons_test/runs.jsonl"
const IDS: Array[StringName] = [&"laser", &"launcher", &"orbit", &"pistol", &"shotgun"]
## OPEN sits one tile above the floor: free 14 T right, 12 T left, 4 T up.
const UP_RIGHT := Vector2(0.9396926, -0.3420201)   ## 20 degrees up

var game: Main
var player: CharacterBody2D
var input: PlayerInput
var _tuning := {}
var _links: Array = []   ## [signal, callable] connected by a test, cut in after_each


func before_each() -> void:
	Telemetry.log_path = TEST_LOG
	for key in ["shoot_cooldown", "projectile_speed", "hard_max_projectiles"]:
		_tuning[key] = Tuning.get(key)


func after_each() -> void:
	for l: Array in _links:
		if (l[0] as Signal).is_connected(l[1]):
			(l[0] as Signal).disconnect(l[1])
	_links.clear()
	for key: String in _tuning:
		Tuning.set(key, _tuning[key])
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.invincible = false
	CampaignDB.active = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(TEST_LOG)


## The legacy arena (no session, no path): spawner and director off, no enemies, the
## player scripted in the open.
func _arena(run_seed := -1) -> void:
	if run_seed >= 0:
		Main.next_seed = run_seed
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


## A campaign session, jumped to (inert save), its stage card skipped.
func _session_game(id: StringName) -> Main:
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var g: Main = load("res://main.tscn").instantiate()
	add_child_autofree(g)
	if g.stage_card != null:
		g.stage_card.skip()   # it pauses the tree
	await wait_physics_frames(2)
	return g


func _frozen_chaser(tile: Vector2, hp := 100.0) -> Node2D:
	var e := RunState.spawn(CHASER, tile * T) as Node2D
	await wait_physics_frames(2)
	e.set_physics_process(false)   # no AI; its Mover still moves it (knockback)
	e.mover.wish = Vector2.ZERO
	e.velocity = Vector2.ZERO
	e.health.base_max_hp = hp
	return e


func _loadout() -> Loadout:
	return Component.find(player, Loadout) as Loadout


func _weapon(id: StringName, rank := 1) -> Weapon:
	return Weapon.new(WeaponDB.get_weapon(id), rank)


## Fires `w` once from the player along `dir`, as the Loadout would (shots counted after).
func _fire(w: Weapon, dir := Vector2.RIGHT) -> Array[Node]:
	var out: Array[Node] = player.shooter.fire(w, dir)
	if not out.is_empty():
		w.shots += 1
	return out


func _wait_until(cond: Callable, max_frames := 300) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await wait_physics_frames(1)
	return cond.call()


## Connects for this test only (after_each cuts it).
func _on(sig: Signal, c: Callable) -> void:
	sig.connect(c)
	_links.append([sig, c])


func _damage_log(source: StringName) -> Array:
	var log: Array = []
	_on(EventBus.entity_damaged, func(target: Node, info: RefCounted) -> void:
		if (info as DamageInfo).source_patch == source:
			log.append([target, (info as DamageInfo).amount, (info as DamageInfo).kind]))
	return log


func _gone(n: Variant) -> bool:
	return not is_instance_valid(n) or (n as Node).is_queued_for_deletion()


# --- 1, 2: the data ---------------------------------------------------------------------

func test_every_weapon_def_is_valid_and_ranks_stop_at_3() -> void:
	assert_eq(WeaponDB.problems(), [] as Array[String])
	assert_eq(WeaponDB.ids(), IDS)
	assert_eq(Loadout.MAX_RANK, 3)
	for w in WeaponDB.all():
		assert_eq(w.max_rank(), 3, "%s: ranks stop at 3 until M50.1" % w.id)
		for t in w.traits_at(2):
			assert_true(t in w.traits_at(3), "%s: rank 3 keeps rank 2's %s" % [w.id, t])
		assert_true(w.traits_at(1).is_empty())
		assert_eq(w.card_text.size(), 3)
	# The checks bite.
	var bad := WeaponDB.get_weapon(&"pistol").duplicate() as WeaponDef
	bad.ranks = [{"traits": [&"seeker"]}, {"traits": [&"heavy_round"], "volume": 3}, {"traits": [&"nope"]}] as Array[Dictionary]
	var text := "\n".join(bad.problems())
	assert_string_contains(text, "rank 4 is not built yet (M50.1)")
	assert_string_contains(text, "rank 3 sets volume, not a rank field")
	assert_string_contains(text, "drops rank 2's trait seeker")
	assert_string_contains(text, "no trait nope")


func test_the_pistol_is_todays_gun() -> void:
	var p := WeaponDB.get_weapon(&"pistol")
	assert_eq(p.cooldown, 0.18)
	assert_eq(p.speed, 900.0)
	assert_eq(p.damage, 1.0)
	assert_eq(Tuning.shoot_cooldown, p.cooldown, "Tuning's default")
	assert_eq(Tuning.projectile_speed, p.speed, "Tuning's default")


# --- 3: no path, the legacy pistol ---------------------------------------------------------

func test_no_path_the_loadout_is_the_pistol_through_try_fire() -> void:
	await _arena()
	var lo := _loadout()
	assert_eq(lo.summary(), "pistol:1")
	assert_true(lo.legacy_pistol())
	Tuning.shoot_cooldown = 0.5
	var frames: Array[int] = []
	var record := func(_p: Node) -> void: frames.append(Engine.get_physics_frames())
	EventBus.projectile_fired.connect(record)
	input.aim_dir = Vector2.RIGHT
	input.fire = true
	await wait_physics_frames(62)
	input.fire = false
	EventBus.projectile_fired.disconnect(record)
	assert_eq(frames.size(), 3, "0.5 s apart over 62 frames")
	assert_between(frames[1] - frames[0], 30, 31, "Shooter's own cooldown, synced from Tuning")
	# D3: a pistol at rank 2 with no path reads Tuning's cooldown and speed too.
	Tuning.projectile_speed = 700.0
	var p2 := _weapon(&"pistol", 2)
	assert_eq(p2.value(&"cooldown"), 0.5)
	assert_eq(p2.value(&"speed"), 700.0)
	assert_eq(_weapon(&"shotgun").value(&"cooldown"), 0.55, "other weapons read their def")


# --- 4, 5: Shooter.fire and the projectile -------------------------------------------------

func _angles(shots: Array[Node]) -> Array:
	return shots.map(func(p: Node) -> float: return snappedf(rad_to_deg((p.velocity as Vector2).angle()), 0.001))


func test_the_shotgun_fans_five_pellets_evenly() -> void:
	await _arena()
	var w := _weapon(&"shotgun")
	var a := _fire(w)
	assert_eq(a.size(), 5)
	assert_eq(_angles(a), [-14.0, -7.0, 0.0, 7.0, 14.0])
	assert_eq(_angles(_fire(w)), [-14.0, -7.0, 0.0, 7.0, 14.0], "the same every call (no RNG)")
	assert_eq(_angles(_fire(_weapon(&"shotgun", 3))), [-9.0, -4.5, 0.0, 4.5, 9.0], "rank 3: 18 degrees")
	for p in a:
		assert_eq(p.source_patch, &"weapon:shotgun")
		assert_eq(p.weapon_id, &"shotgun")
	await wait_physics_frames(1)   # let the pending pellets enter the world before it goes


func test_lifetime_and_size() -> void:
	await _arena()
	var pellets := _fire(_weapon(&"shotgun"), UP_RIGHT)
	assert_true(pellets.all(func(p: Variant) -> bool: return p.lifetime == 0.35))
	await wait_physics_frames(15)
	assert_true(pellets.all(func(p: Variant) -> bool: return not _gone(p)), "alive at 0.25 s")
	await wait_physics_frames(9)   # 0.35 s + a frame (and the deferred entry)
	assert_true(pellets.all(func(p: Variant) -> bool: return _gone(p)), "gone by 0.35 s")
	var laser := _fire(_weapon(&"laser"), Vector2.UP)[0]
	await wait_physics_frames(1)
	assert_eq(laser.get_node(^"Visual").size, Vector2(14, 6) * 1.5, "the laser's visual size")
	var plain := RunState.spawn(PROJECTILE, OPEN * T, {&"velocity": Vector2.UP * 10.0})
	await wait_physics_frames(1)
	assert_eq(plain.get_node(^"Visual").size, Vector2(14, 6), "size 1 = today's visual")


func test_pierce_hits_each_lined_up_enemy_once() -> void:
	await _arena()
	var targets: Array[Node2D] = []
	for i in 5:
		targets.append(await _frozen_chaser(OPEN + Vector2(2 + 0.75 * i, 0)))
	var hits := {}
	_on(EventBus.projectile_hit, func(_p: Node, t: Node, _pos: Vector2) -> void:
		hits[t] = int(hits.get(t, 0)) + 1)
	var shot := _fire(_weapon(&"laser"))[0]
	await wait_physics_frames(20)
	assert_eq(hits.size(), 4, "pierce 3: four enemies")
	for t: Node in hits:
		assert_eq(hits[t], 1, "each once, despite the ray starting inside it")
	assert_false(hits.has(targets[4]), "the fifth is not hit")
	assert_true(not is_instance_valid(shot) or shot.is_queued_for_deletion())


func test_a_weapon_bounce_comes_after_the_rules_bounces() -> void:
	await _arena()
	RunState.rules.projectile_max_bounces = 1
	var p := RunState.spawn(PROJECTILE, OPEN * T, {&"velocity": Vector2.LEFT * 900.0, &"bounces_left": 1,
			&"lifetime": 20.0})
	assert_true(await _wait_until(func() -> bool: return p.bounces_used == 1, 600), "the rules' bounce first")
	assert_eq(p.bounces_left, 1, "the weapon's bounce is still there")
	assert_true(await _wait_until(func() -> bool: return not is_instance_valid(p) or p.bounces_left == 0, 1200))
	assert_true(is_instance_valid(p) and not p.is_queued_for_deletion(), "it bounced, not despawned")
	assert_eq(p.bounces_left, 0)
	var ref: WeakRef = weakref(p)
	assert_true(await _wait_until(func() -> bool: return _gone(ref.get_ref()), 1200), "the third wall ends it")


func test_the_launcher_blasts_on_contact() -> void:
	await _arena()
	var target := await _frozen_chaser(OPEN + Vector2(3, 0))
	var near := await _frozen_chaser(OPEN + Vector2(3, -1))
	var far := await _frozen_chaser(OPEN + Vector2(7, 0))
	var blasts: Array = []
	_on(EventBus.explosion, func(pos: Vector2, r: float) -> void: blasts.append([pos, r]))
	_fire(_weapon(&"launcher"))
	assert_true(await _wait_until(func() -> bool: return not blasts.is_empty(), 60))
	assert_eq(blasts.size(), 1)
	assert_almost_eq(float(blasts[0][1]), 1.6 * T, 0.01)
	assert_almost_eq(target.health.hp(), 98.0, 0.01)
	assert_almost_eq(near.health.hp(), 98.0, 0.01, "in range")
	assert_almost_eq(far.health.hp(), 100.0, 0.01, "out of range")
	assert_lt(player.velocity.length(), 1.0, "the player is not pushed")


# --- 6: the ten traits ------------------------------------------------------------------

func test_heavy_round_every_fifth_shot() -> void:
	await _arena()
	var w := _weapon(&"pistol", 2)
	var shots: Array[Node] = []
	for i in 6:
		shots.append(_fire(w)[0])
	for i in 6:
		var heavy := i == 4
		assert_eq(shots[i].damage, 3.0 if heavy else 1.0, "shot %d" % (i + 1))
		assert_eq(shots[i].size, 2.0 if heavy else 1.0, "shot %d" % (i + 1))
		assert_eq(shots[i].pierce_left, 1 if heavy else 0, "shot %d" % (i + 1))
	await wait_physics_frames(1)


func test_seeker_turns_at_most_60_degrees_a_second_within_4_tiles() -> void:
	await _arena()
	await _frozen_chaser(OPEN + Vector2(3, -2))   # ~3.6 T away, in range
	var shot := _fire(_weapon(&"pistol", 3))[0]
	await wait_physics_frames(12)
	var turned := absf(rad_to_deg((shot.velocity as Vector2).angle()))
	assert_gt(turned, 0.5, "it turns toward the enemy")
	assert_lte(turned, 60.0 * 12.0 / 60.0 + 0.01, "at most 60 degrees a second")
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()
	await wait_physics_frames(1)
	await _frozen_chaser(OPEN + Vector2(4, -3))   # 5 T and more from the shot: out of range
	var straight := _fire(_weapon(&"pistol", 3), Vector2.LEFT)[0]
	await wait_physics_frames(10)
	assert_false(_gone(straight))
	assert_almost_eq(absf(rad_to_deg((straight.velocity as Vector2).angle())), 180.0, 0.001, "nothing within 4 T")


func test_knockback_cone_pushes_about_half_a_tile() -> void:
	await _arena()
	for p in _fire(_weapon(&"shotgun", 2)):
		assert_eq(p.knockback, preload("res://weapons/traits/knockback_cone.gd").KNOCKBACK)
	for p in _fire(_weapon(&"shotgun", 1)):
		assert_eq(p.knockback, -1.0, "rank 1: today's knockback")
	await wait_physics_frames(30)
	var target := await _frozen_chaser(OPEN + Vector2(4, 0))
	var start := target.global_position
	var one := RunState.spawn(PROJECTILE, (OPEN + Vector2(2, 0)) * T, {&"velocity": Vector2.RIGHT * 900.0,
			&"knockback": preload("res://weapons/traits/knockback_cone.gd").KNOCKBACK})
	await wait_physics_frames(60)
	assert_false(is_instance_valid(one) and not one.is_queued_for_deletion(), "it hit")
	assert_almost_eq(target.global_position.x - start.x, 0.5 * T, 0.15 * T, "~0.5 tile")


func test_point_blank_doubles_damage_only_within_2_tiles() -> void:
	await _arena()
	var log := _damage_log(&"weapon:shotgun")
	var close := await _frozen_chaser(OPEN + Vector2(1.5, 0))
	_fire(_weapon(&"shotgun", 3))
	await wait_physics_frames(10)
	var close_hits := log.filter(func(l: Array) -> bool: return l[0] == close)
	assert_gt(close_hits.size(), 0)
	assert_true(close_hits.all(func(l: Array) -> bool: return l[1] == 2.0), "x2 inside 2 T")
	close.queue_free()
	log.clear()
	var far := await _frozen_chaser(OPEN + Vector2(4, 0))
	await wait_physics_frames(30)   # the shotgun's own cooldown does not matter here
	_fire(_weapon(&"shotgun", 3))
	await wait_physics_frames(15)
	var far_hits := log.filter(func(l: Array) -> bool: return l[0] == far)
	assert_gt(far_hits.size(), 0)
	assert_true(far_hits.all(func(l: Array) -> bool: return l[1] == 1.0), "x1 beyond 2 T")


func test_burn_line_burns_1_per_half_second_for_1_second() -> void:
	await _arena()
	var target := await _frozen_chaser(OPEN + Vector2(3, 0))
	var log := _damage_log(&"weapon:laser")
	_fire(_weapon(&"laser", 2))
	assert_true(await _wait_until(func() -> bool: return get_tree().get_nodes_in_group(&"enemy").size() > 0 \
			and _zones().size() == 1, 240), "the line appears when the shot ends")
	var zone: Node = _zones()[0]
	var born := RunState.game_time
	var ref: WeakRef = weakref(zone)
	await _wait_until(func() -> bool: return ref.get_ref() == null, 120)
	assert_null(ref.get_ref(), "gone after 1 s")
	assert_almost_eq(RunState.game_time - born, 1.0, 0.05)
	var burns := log.filter(func(l: Array) -> bool: return l[0] == target and l[2] == &"burn")
	assert_eq(burns.size(), 2, "1 per 0.5 s for 1 s")
	assert_true(burns.all(func(l: Array) -> bool: return l[1] == 1.0))


## M44 review: the line is the path the shot flew (muzzle, the bounce, the end), never the
## straight chord muzzle -> end, which after a bounce crosses ground (or walls) it never
## touched.
func test_the_burn_line_follows_the_bounce_not_the_chord() -> void:
	await _arena()
	var shot := _fire(_weapon(&"laser", 3), UP_RIGHT)[0]   # rank 3: ricochet + burn line
	assert_eq(shot.mods().filter(func(m: Node) -> bool: return m.get_script() == BurnLineMod).size(), 1)
	assert_true(await _wait_until(func() -> bool: return _zones().size() == 1, 240), "the line appears when the shot ends")
	var zone: Node = _zones()[0]
	var pts: PackedVector2Array = zone.points
	assert_gte(pts.size(), 3, "the muzzle, the bounce, the end: %s" % pts)
	assert_eq(pts[0], shot.origin if is_instance_valid(shot) else pts[0], "it starts at the muzzle")
	var space := player.get_world_2d().direct_space_state
	for i in range(1, pts.size()):
		if pts[i - 1].distance_to(pts[i]) < 5.0:
			continue   # the half-pixel step off the wall after a bounce
		var q := PhysicsRayQueryParameters2D.create(pts[i - 1].move_toward(pts[i], 2.0),
				pts[i].move_toward(pts[i - 1], 2.0), Tuning.LAYER_WORLD)
		assert_true(space.intersect_ray(q).is_empty(), "segment %d crosses no wall" % i)
	var chord_mid := (pts[0] + pts[pts.size() - 1]) / 2.0
	var path_mid := (pts[pts.size() - 2] + pts[pts.size() - 1]) / 2.0   # after the bounce
	assert_gt(chord_mid.distance_to(zone.closest_point(chord_mid)), T, "the chord's middle is off the path")
	var log := _damage_log(&"weapon:laser")
	var off := await _frozen_chaser(chord_mid / T)
	var on := await _frozen_chaser(path_mid / T)
	var ref: WeakRef = weakref(zone)
	await _wait_until(func() -> bool: return ref.get_ref() == null, 120)
	var burned := func(e: Node) -> int:
		return log.filter(func(l: Array) -> bool: return l[0] == e and l[2] == &"burn").size()
	assert_eq(burned.call(off), 0, "nothing burns where the shot never went")
	assert_gt(burned.call(on), 0, "the path after the bounce burns")


func _zones() -> Array:
	return RunState.world.get_children().filter(func(n: Node) -> bool: return n.get_script() == BurnLineZone)


func test_ricochet_bounces_once_and_restores_pierce() -> void:
	await _arena()
	var shot := _fire(_weapon(&"laser", 3), Vector2.LEFT)[0]
	assert_eq(shot.bounces_left, 1)
	await wait_physics_frames(1)
	shot.pierce_left = 0   # as if it had pierced three already
	var mod: Node = shot.mods().filter(func(m: Node) -> bool: return m.get_script() == RicochetMod)[0]
	assert_true(await _wait_until(func() -> bool: return not is_instance_valid(shot) or mod.bounced == 1, 180))
	assert_true(is_instance_valid(shot) and not shot.is_queued_for_deletion(), "it bounced")
	assert_eq(shot.pierce_left, 3, "pierce back to full")
	assert_eq(shot.bounces_left, 0, "one bounce")


func test_sticky_stops_follows_and_blasts_after_0_6_s_at_1_2x() -> void:
	await _arena()
	var target := await _frozen_chaser(OPEN + Vector2(3, 0))
	var blasts: Array = []
	_on(EventBus.explosion, func(_pos: Vector2, r: float) -> void: blasts.append([RunState.game_time, r]))
	var shell := _fire(_weapon(&"launcher", 2))[0]
	var mod: Node = shell.mods().filter(func(m: Node) -> bool: return m.get_script() == StickyMod)[0]
	assert_true(await _wait_until(func() -> bool: return mod.stuck, 60))
	var stuck_at := RunState.game_time
	assert_true(blasts.is_empty(), "no blast on contact")
	var offset: Vector2 = shell.global_position - target.global_position
	target.global_position += Vector2(0, 20)
	await wait_physics_frames(2)
	assert_almost_eq((shell.global_position - target.global_position).distance_to(offset), 0.0, 0.01, "it follows")
	assert_true(await _wait_until(func() -> bool: return not blasts.is_empty(), 60))
	assert_almost_eq(float(blasts[0][0]) - stuck_at, 0.6, 1.5 / 60.0)
	assert_almost_eq(float(blasts[0][1]), 1.6 * T * 1.2, 0.01)
	assert_eq(target.health.hp(), 98.0)


func test_implode_pulls_in_before_the_pop() -> void:
	await _arena()
	await _frozen_chaser(OPEN + Vector2(3, 0))
	var side := await _frozen_chaser(OPEN + Vector2(4, -1.4))
	var blasts: Array = []
	var shell := _fire(_weapon(&"launcher", 3))[0]
	var mod: Node = shell.mods().filter(func(m: Node) -> bool: return m.get_script() == StickyMod)[0]
	assert_true(mod.implode)
	_on(EventBus.explosion, func(pos: Vector2, _r: float) -> void: blasts.append([pos, mod.pulled]))
	assert_true(await _wait_until(func() -> bool: return mod.stuck, 60))
	var centre: Vector2 = shell.global_position
	var before := side.global_position.distance_to(centre)
	assert_true(await _wait_until(func() -> bool: return not blasts.is_empty(), 60))
	assert_gt(int(blasts[0][1]), 0, "pulled before the blast")
	assert_lt(side.global_position.distance_to(centre), before - 10.0, "pulled in")


func test_orbit_rank_1_two_shards_at_2_tiles() -> void:
	await _arena()
	var lo := _loadout()
	assert_true(lo.set_weapon(&"orbit", 1))
	assert_eq(lo.summary(), "pistol:1,orbit:1")
	assert_true(lo.legacy_pistol(), "a passive rides along with the pistol")
	var node: Node = lo.passive_node(&"orbit")
	assert_not_null(node)
	assert_eq(node.source_patch, &"", "never in the patch snapshot")
	assert_eq(node.shard_count, 2)
	assert_almost_eq(node.shard_position(0).distance_to(player.global_position), 2.0 * T, 0.5)
	await _frozen_chaser(OPEN + Vector2(2, 0))
	await wait_seconds(2.0)
	assert_gt(node.hits, 0)
	assert_lte(node.hits, int(2.0 / 0.4) + 1, "at most once per 0.4 s")
	assert_gt(float(RunState.damage_by_source.get(&"weapon:orbit", 0.0)), 0.0)


func test_flare_doubles_the_radius_for_0_6_s_after_a_dash() -> void:
	await _arena()
	var lo := _loadout()
	lo.set_weapon(&"orbit", 2)
	var node: Node = lo.passive_node(&"orbit")
	assert_true(node.flare)
	await wait_physics_frames(1)
	EventBus.player_dashed.emit()
	await wait_physics_frames(1)
	assert_almost_eq(node.shard_position(0).distance_to(player.global_position), 4.0 * T, 0.5)
	await wait_physics_frames(40)
	assert_almost_eq(node.shard_position(1).distance_to(player.global_position), 2.0 * T, 0.5, "back after 0.6 s")


func test_guard_eats_an_enemy_shot_and_the_shard_is_back_after_1_s() -> void:
	await _arena()
	var lo := _loadout()
	lo.set_weapon(&"orbit", 3)
	var node: Node = lo.passive_node(&"orbit")
	assert_true(node.guard)
	await wait_physics_frames(1)
	var ahead := RunState.game_time + 3.0 / 60.0
	var at: Vector2 = player.global_position + Vector2.RIGHT.rotated(ahead * node.SPEED) * node.radius
	var shot := RunState.spawn(PROJECTILE, at, {&"kind": &"enemy_projectile", &"faction": &"enemy"})
	assert_true(await _wait_until(func() -> bool: return node.eaten == 1, 30))
	assert_true(not is_instance_valid(shot) or shot.is_queued_for_deletion())
	assert_false(node.shard_active(0), "that shard is gone")
	await wait_seconds(1.05)
	assert_true(node.shard_active(0), "back after 1 s")


# --- 7: each rank changes what it says ---------------------------------------------------

func test_each_rank_changes_exactly_its_keys() -> void:
	for def in WeaponDB.all():
		var fields: Array[String] = []
		for p: Dictionary in def.get_property_list():
			if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not p.name in ["ranks", "card_text"]:
				fields.append(p.name)
		for r in [2, 3]:
			var keys: Array = def.ranks[r - 2].keys().map(func(k: Variant) -> String: return String(k))
			for f in fields:
				var moved: bool = def.value(StringName(f), r) != def.value(StringName(f), r - 1)
				var listed: bool = f in keys and def.ranks[r - 2][f] != def.value(StringName(f), r - 1)
				assert_eq(moved, listed, "%s rank %d: %s" % [def.id, r, f])
			assert_ne(def.traits_at(r), def.traits_at(r - 1), "%s rank %d adds a behaviour" % [def.id, r])


# --- 8: the Loadout ------------------------------------------------------------------------

func test_loadout_give_upgrade_switch_clear() -> void:
	await _arena()
	var lo := _loadout()
	watch_signals(EventBus)
	assert_true(lo.give(&"shotgun"))
	assert_eq(lo.summary(), "pistol:1,shotgun:1")
	assert_signal_emitted_with_parameters(EventBus, "weapon_changed", [&"shotgun", 1])
	assert_eq(lo.current().def.id, &"pistol", "no auto-switch")
	assert_true(lo.give(&"shotgun"))
	assert_eq(lo.rank_of(&"shotgun"), 2, "held: one rank up")
	assert_true(lo.give(&"shotgun", 3))
	assert_false(lo.give(&"shotgun"), "capped at 3")
	assert_false(lo.upgrade(&"shotgun"), "capped at 3")
	lo.switch(1)
	assert_eq(lo.current().def.id, &"shotgun")
	assert_signal_emitted_with_parameters(EventBus, "weapon_changed", [&"shotgun", 3])
	lo.switch(1)
	assert_eq(lo.current().def.id, &"pistol", "cycles")
	assert_true(lo.give(&"laser"))
	assert_true(lo.give(&"orbit"))
	assert_eq(lo.slots.size(), 3)
	lo.switch(-1)
	assert_eq(lo.current().def.id, &"laser", "the passive is not in the cycle")
	lo.switch(1)
	assert_true(lo.give(&"launcher"), "a full hand")
	assert_eq(lo.summary(), "pistol:1,shotgun:3,launcher:1,orbit:1", "the weakest non-active (laser r1) goes")
	assert_true(lo.upgrade(&"launcher"))
	assert_eq(lo.rank_of(&"launcher"), 2)
	lo.clear()
	assert_eq(lo.summary(), "pistol:1")
	assert_null(lo.passive_node(&"orbit"))
	lo.switch(1)
	assert_eq(lo.active, 0, "one slot: a no-op")
	assert_true(lo.give(&"pistol", 3))
	assert_eq(lo.summary(), "pistol:3")
	assert_false(lo.legacy_pistol())
	assert_true(lo.set_weapon(&"pistol", 1))
	assert_eq(lo.summary(), "pistol:1")
	assert_true(lo.legacy_pistol(), "legacy again")


func test_a_rank_up_fires_through_the_loadout_with_its_own_cooldown() -> void:
	await _arena()
	var lo := _loadout()
	lo.set_weapon(&"shotgun", 1)
	lo.select(&"shotgun")
	var fired: Array[int] = []
	var record := func(_p: Node) -> void: fired.append(Engine.get_physics_frames())
	EventBus.projectile_fired.connect(record)
	input.aim_dir = Vector2.RIGHT
	input.fire = true
	await wait_physics_frames(40)
	input.fire = false
	EventBus.projectile_fired.disconnect(record)
	assert_eq(fired.size(), 10, "two shots of five pellets in 40 frames (0.55 s cooldown)")
	assert_eq(lo.current().shots, 2)


# --- 9: randomness -------------------------------------------------------------------------

func _states() -> Array:
	return [RunState.gameplay_rng.state, RunState.director_rng.state, RunState.loot_rng.state,
			RunState.pick_rng.state]


func _stream_run(fire: bool) -> Array:
	await _arena(77)
	for i in 3:
		await _frozen_chaser(OPEN + Vector2(3, i - 1), 100000.0)
	var lo := _loadout()
	lo.set_weapon(&"orbit", 3)
	var aimed: Array[StringName] = [&"pistol", &"shotgun", &"laser", &"launcher"]
	input.aim_dir = Vector2.RIGHT
	for id in aimed:
		for r in [1, 2, 3]:
			if fire:
				lo.set_weapon(id, r)
				lo.select(id)
			input.fire = fire
			await wait_physics_frames(50)
	input.fire = false
	var out := _states()
	game.free()
	await wait_physics_frames(1)
	return out


func test_weapons_never_draw_from_any_stream() -> void:
	var with_fire := await _stream_run(true)
	var without := await _stream_run(false)
	assert_eq(with_fire, without, "10 s of every weapon at every rank: all four streams untouched")
	RunState.reset(5)
	var a := _states()
	RunState.reset(5)
	assert_eq(_states(), a)
	var seeds := [RunState.gameplay_rng.seed, RunState.director_rng.seed, RunState.loot_rng.seed,
			RunState.pick_rng.seed]
	for i in seeds.size():
		for j in range(i + 1, seeds.size()):
			assert_ne(seeds[i], seeds[j], "four distinct streams")


# --- 10, 11: kill credit, the cap ----------------------------------------------------------

func test_kill_credit_per_weapon_and_base_for_the_legacy_pistol() -> void:
	await _arena()
	await _frozen_chaser(OPEN + Vector2(2, 0), 1.0)
	_fire(_weapon(&"shotgun"))
	await wait_physics_frames(10)
	assert_eq(int(RunState.kills_by_source.get(&"weapon:shotgun", 0)), 1)
	assert_eq(ReportScreen._source_title("weapon:shotgun"), "Shotgun", "the report's title")
	await _frozen_chaser(OPEN + Vector2(2, 0), 1.0)
	input.aim_dir = Vector2.RIGHT
	input.fire = true
	await wait_physics_frames(10)
	input.fire = false
	assert_eq(int(RunState.kills_by_source.get(&"base", 0)), 1, "the legacy pistol: base, as before")


func test_the_shotgun_never_passes_the_projectile_cap() -> void:
	await _arena()
	var w := _weapon(&"shotgun", 3)
	w.def = w.def.duplicate() as WeaponDef
	w.def.lifetime = 5.0
	var most := 0
	for i in 90:
		for k in 2:
			player.shooter.fire(w, Vector2.RIGHT.rotated(-0.2 - 0.01 * (i % 10)))
		await wait_physics_frames(1)
		most = maxi(most, RunState.count(&"player_projectile") + RunState.count(&"enemy_projectile"))
		assert_lte(most, Tuning.hard_max_projectiles)
	assert_gt(most, 150, "it reached the cap")


# --- 12: the give cue ----------------------------------------------------------------------

func test_the_give_cue_hands_the_weapon() -> void:
	var g := await _session_game(&"s2_01_tryout")
	var lo := Component.find(g.player, Loadout) as Loadout
	assert_eq(lo.summary(), "pistol:1")
	g.session_runner.inject("at 0.5: give shotgun")
	await wait_physics_frames(45)
	assert_eq(lo.summary(), "pistol:1,shotgun:1")


func test_give_problems() -> void:
	var s := SessionDef.new()
	s.id = &"x"
	s.goal = SessionDef.SURVIVE
	s.goal_value = 10.0
	s.weapons = [&"pistol"] as Array[StringName]
	s.cues = PackedStringArray(["at 3: give railgun", "at 4: give shotgun"])
	var text := "\n".join(s.problems())
	assert_string_contains(text, "unknown weapon railgun")
	assert_string_contains(text, "give shotgun: not in the session's weapons")
	s.weapons = [&"shotgun", &"shotgun"] as Array[StringName]
	s.cues = PackedStringArray()
	s._parsed = false
	text = str(s.problems())
	assert_string_contains(text, "weapons must list pistol")
	assert_string_contains(text, "weapon shotgun is listed twice")
	s.weapons = [&"pistol", &"shotgun"] as Array[StringName]
	s.cues = PackedStringArray(["at 5: give shotgun 4"])
	s._parsed = false
	assert_eq(s.problems().filter(func(p: String) -> bool: return "weapon" in p or "give" in p), [])
	assert_string_contains(str(CampaignDB._unbuilt_problems(s)), "rank 4 is not built yet (M50.1)")
	assert_eq(CampaignDB.problems(), [] as Array[String], "the campaign is clean")


func test_the_stub_gives_after_its_intro() -> void:
	var s := CampaignDB.get_session(&"s2_01_tryout")
	assert_eq(s.weapons, [&"pistol", &"shotgun"] as Array[StringName])
	var intro := 0.0
	for l in s.intro_lines():
		intro += SessionRunner.read_seconds(l.text)
	var gives := s.cue_list().filter(func(c: Cue) -> bool: return c.action == &"give")
	assert_eq(gives.size(), 1)
	assert_eq(gives[0].target, &"shotgun")
	assert_gte(gives[0].value, intro, "the give and its line come after the intro (%.2f s)" % intro)
	var says := s.cue_list().filter(func(c: Cue) -> bool: return c.action == &"say" and c.value == gives[0].value)
	assert_eq(says.size(), 1, "announced together")


# --- 13: binds -----------------------------------------------------------------------------

func _has_event(action: StringName, check: Callable) -> bool:
	return InputMap.action_get_events(action).any(check)


func test_switch_binds_and_the_mouse_wheel() -> void:
	var key := func(code: Key) -> Callable:
		return func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == code
	var mouse := func(b: MouseButton) -> Callable:
		return func(e: InputEvent) -> bool: return e is InputEventMouseButton and e.button_index == b
	var pad := func(b: JoyButton) -> Callable:
		return func(e: InputEvent) -> bool: return e is InputEventJoypadButton and e.button_index == b
	assert_true(_has_event(&"weapon_prev", key.call(KEY_Q)))
	assert_true(_has_event(&"weapon_prev", mouse.call(MOUSE_BUTTON_WHEEL_UP)))
	assert_true(_has_event(&"weapon_prev", pad.call(JOY_BUTTON_LEFT_SHOULDER)))
	assert_true(_has_event(&"weapon_next", key.call(KEY_E)))
	assert_true(_has_event(&"weapon_next", mouse.call(MOUSE_BUTTON_WHEEL_DOWN)))
	assert_true(_has_event(&"weapon_next", pad.call(JOY_BUTTON_RIGHT_SHOULDER)))
	assert_true(_has_event(&"wait", key.call(KEY_E)), "E still passes a turn (B2)")
	var human := HumanInput.new()
	add_child_autofree(human)
	await wait_physics_frames(1)
	assert_eq(human.switch_step, 0)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = pressed
		human._input(ev)
	human._physics_process(1.0 / 60.0)
	assert_eq(human.switch_step, 1, "the wheel notch lands on the next tick")
	human._physics_process(1.0 / 60.0)
	assert_eq(human.switch_step, 0, "for one tick")


## M44 review: the binds are physical positions, so the switch line names the keys printed
## on the player's keyboard (AZERTY prints A where weapon_prev's Q sits; the key printed Q
## is move_left), never a hard-coded letter.
func test_the_switch_line_names_the_keys_on_the_players_layout() -> void:
	var azerty := func(physical: Key) -> Key:
		return {KEY_W: KEY_Z, KEY_A: KEY_Q, KEY_Q: KEY_A, KEY_Z: KEY_W}.get(physical, physical)
	var qwerty := func(physical: Key) -> Key: return physical
	# M45a: the stub is an Auto taste now (no switch line); M44's line, as data.
	var line := Line.parse("happy: I built you a shotgun. {key:weapon_prev} and {key:weapon_next} to switch.")
	assert_eq(line.problem, "")
	assert_eq(SessionRunner.with_keys(line, azerty).text, "I built you a shotgun. A and E to switch.")
	assert_eq(SessionRunner.with_keys(line, qwerty).text, "I built you a shotgun. Q and E to switch.")
	assert_eq(SessionRunner.with_keys(line, azerty).expression, &"happy")
	assert_true(line.text.contains("{key:weapon_prev}"), "the cached parse is never changed")
	assert_eq(InputSetup.key_label(&"move_left", azerty), "Q", "the key printed Q moves left on AZERTY")
	assert_string_contains(Line.parse("happy: press {key:fly}").problem, "unknown action")
	assert_string_contains(Line.parse("happy: press {key:dash").problem, "unclosed")
	var g := await _session_game(&"s2_01_tryout")
	g.session_runner.inject("at 0.5: say happy: {key:weapon_prev} and {key:weapon_next}.")
	await wait_physics_frames(45)
	var texts: Array[String] = g.session_runner.said.duplicate()
	for l in g.session_runner.queued_lines():
		texts.append(l.text)
	assert_has(texts, "%s and E." % InputSetup.key_label(&"weapon_prev"), "the runner names the keys when it says the line")


func test_nothing_in_the_weapon_code_reads_wait() -> void:
	var files: Array[String] = ["res://components/loadout.gd"]
	files.append_array(_scripts("res://campaign/"))
	files.append_array(_scripts("res://weapons/"))
	for path in files:
		assert_false(FileAccess.get_file_as_string(path).contains("&\"wait\""), path)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for entry in DirAccess.get_files_at(dir):
		if entry.get_extension() in ["gd", "tres"]:
			out.append(dir + entry)
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + sub + "/"))
	return out


# --- 14: Stage 1 does not move (the hard gate) ----------------------------------------------

func test_stage_1_rules_equal_the_m43_3_fixture_field_by_field() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RulesDump.FIXTURE))
	assert_not_null(fixture)
	for id in RulesDump.STAGE1:
		var seen := {}
		var d: Dictionary = await RulesDump.dump(get_tree(), self, id, func(g: Node) -> void:
			var lo := Component.find(g.player, Loadout) as Loadout
			seen["loadout"] = lo.summary()
			seen["legacy"] = lo.legacy_pistol())
		assert_eq(d.session, String(id))
		assert_eq(d.path, "", "%s has no path" % id)
		assert_eq(seen.get("loadout"), "pistol:1", String(id))
		assert_eq(seen.get("legacy"), true, String(id))
		_same_fields(d, fixture[String(id)], String(id))
	_same_fields(RulesDump.legacy(get_tree()), fixture["legacy"], "legacy")


func _same_fields(now: Dictionary, want: Dictionary, where: String) -> void:
	for part in ["rules", "base_rules"]:
		var a: Dictionary = now[part]
		var b: Dictionary = want[part]
		var ak := a.keys()
		var bk := b.keys()
		ak.sort()
		bk.sort()
		assert_eq(ak, bk, "%s %s: the same fields (a new field joins the fixture on purpose)" % [where, part])
		for k: String in b:
			assert_eq(a.get(k), b[k], "%s %s.%s" % [where, part, k])


# --- 15: power stays in the session --------------------------------------------------------

## Through the real way on (M44 review): the session ends, the debrief's Retry and Next go
## through main._end_session (CampaignDB writes the in-memory save), and only then is the
## save scanned. The retry's fresh scene (no jump) starts bare.
func test_a_weapon_never_outlives_its_session_or_reaches_the_save() -> void:
	var g := await _session_game(&"s2_01_tryout")
	var lo := Component.find(g.player, Loadout) as Loadout
	assert_true(lo.give(&"shotgun", 3))
	assert_eq(lo.summary(), "pistol:1,shotgun:3")
	g.run_loop.end(&"lose")
	await _to_debrief(g)
	var before := str(SaveGame.state())
	g._end_session(&"retry")
	assert_ne(str(SaveGame.state()), before, "Retry wrote the save")
	assert_eq(SaveGame.attempts(&"s2_01_tryout"), 1)
	_no_weapon_keys("after Retry")
	g.free()
	await wait_physics_frames(1)
	var again: Main = load("res://main.tscn").instantiate()   # the retry's reload: no jump
	add_child_autofree(again)
	if again.stage_card != null:
		again.stage_card.skip()
	await wait_physics_frames(2)
	assert_eq(RunState.session.id, &"s2_01_tryout", "the same session again")
	var lo2 := Component.find(again.player, Loadout) as Loadout
	assert_eq(lo2.summary(), "pistol:1", "the retry starts bare")
	assert_true(lo2.give(&"laser", 2))
	again.run_loop.goal_clock = again.run_loop.goal_value
	await _to_debrief(again)
	assert_eq(again.debrief.outcome, &"won")
	before = str(SaveGame.state())
	again._end_session(&"next")
	assert_ne(str(SaveGame.state()), before, "Next wrote the save")
	assert_true(&"s2_01_tryout" in SaveGame.campaign().done or "s2_01_tryout" in SaveGame.campaign().done, "the session is done")
	_no_weapon_keys("after Next")


## The session's end opened the debrief (wait_physics_frames only until it opens: it
## pauses the tree), its lines skipped.
func _to_debrief(g: Main) -> void:
	assert_true(await _wait_until(func() -> bool: return g.debrief.is_open(), int(Tuning.report_delay * 60) + 30),
			"the debrief opened")
	g.debrief.input_delay = 0.0
	g.debrief.finish_lines()


func _no_weapon_keys(where: String) -> void:
	var bad: Array[String] = []
	_keys_with(SaveGame.state(), ["loadout", "rank", "weapon"], bad)
	assert_eq(bad, [] as Array[String], where)
	var values := str(SaveGame.state())
	for word in ["pistol:", "shotgun", "laser"]:
		assert_false(values.contains(word), "%s: the save mentions %s" % [where, word])


func _keys_with(v: Variant, words: Array, out: Array[String]) -> void:
	if v is Dictionary:
		for k: Variant in v:
			for w: String in words:
				if String(k).to_lower().contains(w):
					out.append(String(k))
			_keys_with(v[k], words, out)
	elif v is Array:
		for x: Variant in v:
			_keys_with(x, words, out)


# --- 16: F1 / F2 ---------------------------------------------------------------------------

func test_f2_gives_and_ranks_up_and_f1_shows_the_loadout() -> void:
	await _arena()
	assert_true(game.debug.give_weapon(&"laser"))
	assert_true(game.debug.give_weapon(&"laser"))
	assert_eq(_loadout().rank_of(&"laser"), 2)
	assert_string_contains(game.debug._build_text(), "weapon=pistol:1 loadout=pistol:1,laser:2")
	game.debug.clear_weapons()
	assert_eq(_loadout().summary(), "pistol:1")


# --- 17: weapons never apply patches -------------------------------------------------------

func test_weapons_never_apply_patches() -> void:
	for path in _scripts("res://weapons/"):
		var text := FileAccess.get_file_as_string(path)
		for word in ["RunState.apply", "add_ai", "MutationDB", "swap_big"]:
			assert_false(text.contains(word), "%s uses %s" % [path, word])
