extends GutTest
## M50.3b (Arcade through S10 design 4.1, .check/arcade_s10/design.md): Cluster (shotgun +
## launcher) is built. Its shell throws 5 bomblets on every blast (ClusterMod, attached by
## Weapon.attach from the Loadout for player shots only, never by Shooter.fire), at the flight
## angle + k x 72 degrees, each a small player shot that pops at the end of its 0.2 s life
## (Projectile.pop_at_end) for 0.2 x the shell's damage; bomblets go through the player budget
## (140) and never the enemies' 60. Its four mechanics: knockback cone on the blast, sticky (the
## burst comes from the stuck point), point blank on a burst near the player, implode. Fused
## levels from the rank; FUSE Shotgun 4 + Launcher 5 -> Cluster 5; a parent's card feeds it.
## The power bench (Cluster vs Prism at equal rank, one tank and a pack of 8 chasers) is gated
## here: single target 0.7-0.9 x Prism, crowd 1.2-1.5 x Prism (the design's levers applied in
## order: bomblet_mult 0.5 -> 0.2, then the shell's base damage 2 -> 3.9).

const ClusterMod := preload("res://weapons/cluster_mod.gd")
const StickyMod := preload("res://weapons/traits/sticky_mod.gd")
const PointBlankClusterMod := preload("res://weapons/traits/point_blank_cluster_mod.gd")
const CHASER := preload("res://entities/enemy_chaser.tscn")
const SHOOTER := preload("res://entities/enemy_shooter.tscn")
const TANK := preload("res://entities/enemy_tank.tscn")
const PROJECTILE := preload("res://entities/projectile.tscn")
const T := 48.0
const OPEN := Vector2(34, 20)
const TEST_LOG := "user://save_cluster_test/runs.jsonl"
## The power bench's gates (design 4.1).
const SINGLE_BAND := Vector2(0.7, 0.9)
const CROWD_BAND := Vector2(1.2, 1.5)
const BENCH_FACE := 3.3    ## T from the player to the targets' near face
const BENCH_FRAMES := 90   ## waits per shot (the fuse, the bomblets, Prism's burn line)

var game: Main
var player: CharacterBody2D
var _links: Array = []


func before_each() -> void:
	Telemetry.log_path = TEST_LOG


func after_each() -> void:
	for l: Array in _links:
		if (l[0] as Signal).is_connected(l[1]):
			(l[0] as Signal).disconnect(l[1])
	_links.clear()
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.invincible = false
	RunState.set_pause(PickPanel.PAUSE, false)
	RunState.session = null
	CampaignDB.active = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(TEST_LOG)


## The legacy arena on Arsenal through F2 (every basic on; the path's budgets live).
func _arena() -> void:
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
	await wait_physics_frames(1)
	player.global_position = OPEN * T
	player.velocity = Vector2.ZERO
	RunState.invincible = true
	assert_true(game.debug.switch_path(&"arsenal"))
	game.pick_panel.input_delay = 0.0
	await wait_physics_frames(1)


func _loadout() -> Loadout:
	return Component.find(player, Loadout) as Loadout


## The hand is `id` at `rank` (deep curve), active.
func _hold(id: StringName, rank: int) -> Loadout:
	var lo := _loadout()
	lo.slots.clear()
	lo.set_weapon(id, rank)
	lo.active = 0
	return lo


func _frozen(scene: PackedScene, at: Vector2, hp := 1.0e6) -> Node2D:
	var e := RunState.spawn(scene, at) as Node2D
	await wait_physics_frames(2)
	e.set_physics_process(false)
	e.velocity = Vector2.ZERO
	(Component.find(e, Mover) as Mover).wish = Vector2.ZERO
	(Component.find(e, Health) as Health).base_max_hp = hp
	return e


## The player's shots of one Loadout.try_fire.
func _fire(lo: Loadout, dir := Vector2.RIGHT) -> Array[Node]:
	var got: Array[Node] = []
	var grab := func(p: Node) -> void: got.append(p)
	EventBus.projectile_fired.connect(grab)
	lo.try_fire(dir)
	EventBus.projectile_fired.disconnect(grab)
	return got


func _cluster_mod(p: Node) -> ClusterMod:
	for m: Object in p.call(&"mods"):
		if m.get_script() == ClusterMod:
			return m as ClusterMod
	return null


func _on(sig: Signal, c: Callable) -> void:
	sig.connect(c)
	_links.append([sig, c])


func _wait_until(cond: Callable, max_frames := 300) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await wait_physics_frames(1)
	return cond.call()


func _clear_field() -> void:
	for g: StringName in [&"enemy", &"projectiles", &"burn_line_zone", &"mine"]:
		for n in get_tree().get_nodes_in_group(g):
			n.queue_free()
	for p in RunState.get_tree().get_nodes_in_group(&"entities"):
		if p.get(&"kind") in [&"player_projectile", &"enemy_projectile"]:
			p.queue_free()
	await wait_physics_frames(3)


# --- 1. Data ------------------------------------------------------------------------------------

func test_cluster_is_built_and_covers_its_parents() -> void:
	var c := WeaponDB.get_weapon(&"cluster")
	assert_true(WeaponDB.fusion_built(&"cluster"))
	assert_eq(WeaponDB.recipe(&"launcher", &"shotgun"), &"cluster")
	assert_eq(c.built_in, "")
	assert_eq(c.burst, 5)
	assert_eq(c.icon, &"cluster")
	assert_eq(c.mechanics, [&"knockback_cone_cluster", &"sticky", &"point_blank_cluster", &"implode"] as Array[StringName])
	for name: StringName in c.inherits:
		assert_true(c.covers(name), String(name))
	assert_eq(c.problems(), [] as Array[String])
	for line in WeaponDB.fusion_problems():
		assert_false(line.begins_with("weapon cluster") or line.begins_with("fusion cluster"), line)
	assert_eq(WeaponDB.get_weapon(&"prism").burst, 0, "no other weapon bursts")
	for w in WeaponDB.all():
		assert_eq(w.burst, 0, String(w.id))


func test_fused_levels_come_from_the_rank() -> void:
	var c := WeaponDB.get_weapon(&"cluster")
	assert_eq(WeaponCurve.levels_of(c, 1), [1, 1, 1, 1] as Array[int])
	assert_eq(WeaponCurve.levels_of(c, 5), [1, 1, 1, 1] as Array[int])
	assert_eq(WeaponCurve.levels_of(c, 7), [2, 1, 1, 1] as Array[int])
	var w := Weapon.new(c, 5, WeaponCurve.DEEP)
	assert_eq(w.traits.map(func(t: WeaponTrait) -> StringName: return t.id),
			[&"knockback_cone_cluster", &"sticky", &"point_blank_cluster", &"implode"])
	assert_almost_eq(float(w.value(&"damage")), 3.9 * 2.0, 0.0001, "base 3.9 x the rank-5 multiplier")
	assert_almost_eq(float(w.value(&"blast_radius")), 1.2, 0.0001)
	assert_almost_eq(float(w.value(&"cooldown")), 0.9, 0.0001)


func test_fuse_shotgun_4_and_launcher_5_is_cluster_5() -> void:
	var lo := Loadout.new()
	lo.apply_path(PathDB.get_def(&"arsenal"))
	lo.slots.clear()
	lo.set_weapon(&"shotgun", 4)
	lo.set_weapon(&"launcher", 5)
	autofree(lo)
	var f := BoosterPack.fuse_option(lo)
	assert_eq(f.id, &"cluster")
	assert_eq(int(f.rank), 5)
	assert_eq(f.title, "FUSE: Shotgun 4 + Launcher 5 -> Cluster 5")
	assert_eq((f.keeps as Array).size(), 4)
	assert_eq(f.keeps[0], "knockback: the blast shoves enemies out")
	assert_eq(f.keeps[2], "point blank: a burst within 2 T of you x2")
	assert_eq(f.loses, [] as Array[String])
	lo.slots.clear()
	lo.set_weapon(&"shotgun", 6)
	lo.set_weapon(&"launcher", 6)
	assert_eq(BoosterPack.fuse_option(lo).loses, ["shrapnel", "mine layer"] as Array[String],
			"the parents' rank-6 mechanics go")
	lo.fuse(&"shotgun", &"launcher", &"cluster", 6)
	assert_eq(lo.summary(), "cluster:6")
	# A parent's card feeds it.
	var c := BoosterPack.card(lo, BoosterPack.fold(lo, &"launcher"))
	assert_eq(c.kind, &"upgrade")
	assert_eq(c.title, "Cluster 6 -> 7")
	var cands := BoosterPack.candidates(lo, [&"pistol", &"shotgun", &"launcher"] as Array[StringName])
	assert_eq(cands.map(func(d: Dictionary) -> StringName: return d.id), [&"cluster", &"pistol"], "parents fold")


# --- 2. The burst ---------------------------------------------------------------------------------

func test_a_blast_throws_five_bomblets_at_fixed_angles() -> void:
	await _arena()
	var lo := _hold(&"cluster", 1)
	var dir := Vector2.RIGHT.rotated(0.3)
	var shots := _fire(lo, dir)
	assert_eq(shots.size(), 1, "one shell")
	var shell := shots[0] as Node2D
	var mod := _cluster_mod(shell)
	assert_not_null(mod, "the Loadout attached the burst")
	assert_eq(mod.count, 5)
	assert_eq(shell.get(&"blast_radius"), 1.2 * T)
	assert_eq(shell.get(&"blast_knockback"), 420.0, "knockback cone level 1 on the blast")
	await wait_physics_frames(2)
	var pos := player.global_position + Vector2(5 * T, 0)   # out of point blank's reach
	var shell_damage := float(shell.get(&"damage"))
	shell.call(&"explode", pos)
	assert_almost_eq(shell_damage, float(shell.get(&"damage")), 0.0001, "no point blank at 5 T")
	assert_eq(mod.bomblets.size(), 5)
	for k in 5:
		var b := mod.bomblets[k]
		var v: Vector2 = b.get(&"velocity")
		assert_almost_eq(v.length(), 1.5 * T / 0.2, 0.01, "speed 1.5 T in 0.2 s")
		assert_almost_eq(angle_difference(v.angle(), dir.angle() + TAU * k / 5.0), 0.0, 0.0001, "angle %d" % k)
		assert_eq(b.get(&"pop_at_end"), true)
		assert_almost_eq(float(b.get(&"lifetime")), 0.2, 0.0001)
		assert_almost_eq(float(b.get(&"blast_radius")), 0.6 * T, 0.0001)
		assert_almost_eq(float(b.get(&"damage")), shell_damage * ClusterMod.BOMBLET_MULT, 0.0001)
		assert_eq(b.get(&"weapon_id"), &"cluster")
		assert_eq(b.get(&"source_patch"), &"weapon:cluster")
		assert_eq(b.get(&"kind"), &"player_projectile")
		assert_eq((b.call(&"mods") as Array).size(), 0, "bomblets carry no mods")
		assert_eq(b.get_node(^"Visual").get(&"skin_id"), &"shot_ball_player")
	var burst := RunState.run_log.filter(func(e: Dictionary) -> bool: return e.get("event") == &"cluster_burst")
	assert_eq(burst.size(), 1)
	assert_eq(int(burst[0].bomblets), 5)
	assert_eq(int(burst[0].refused), 0)
	await wait_physics_frames(2)


func test_bomblets_pop_at_the_end_of_their_life() -> void:
	await _arena()
	var blasts: Array = []
	_on(EventBus.explosion, func(at: Vector2, r: float) -> void: blasts.append([at, r]))
	var start := OPEN * T + Vector2(T, 0)
	var b: WeakRef = weakref(RunState.spawn(PROJECTILE, start, {&"kind": &"player_projectile", &"velocity": Vector2.RIGHT * 360.0,
			&"lifetime": 0.2, &"blast_radius": 0.6 * T, &"pop_at_end": true, &"damage": 1.0,
			&"source_patch": &"weapon:cluster"}))
	var plain: WeakRef = weakref(RunState.spawn(PROJECTILE, start + Vector2(0, -T), {&"kind": &"player_projectile",
			&"velocity": Vector2.RIGHT * 360.0, &"lifetime": 0.2, &"blast_radius": 0.6 * T, &"damage": 1.0}))
	assert_true(await _wait_until(func() -> bool: return b.get_ref() == null and plain.get_ref() == null, 40))
	assert_eq(blasts.size(), 1, "only the pop_at_end shot blows when its life ends")
	assert_almost_eq((blasts[0][0] as Vector2).x, start.x + 72.0, 7.0, "about 1.5 T out")
	assert_almost_eq(float(blasts[0][1]), 0.6 * T, 0.001)
	var fresh := PROJECTILE.instantiate()
	assert_false(fresh.get(&"pop_at_end"), "default: today's quiet end")
	fresh.free()


func test_only_the_players_loadout_attaches_a_burst() -> void:
	await _arena()
	var lo := _hold(&"cluster", 1)
	var w := lo.current()
	var raw := lo.shooter().fire(w, Vector2.RIGHT)
	assert_eq(raw.size(), 1)
	assert_null(_cluster_mod(raw[0]), "Shooter.fire (shared with enemies) attaches none")
	w.attach(raw, &"enemy")
	assert_null(_cluster_mod(raw[0]), "an enemy shot never bursts")
	w.attach(raw, &"player")
	assert_not_null(_cluster_mod(raw[0]))
	lo.misfuse_skin = &"shot_misfuse_player"
	w.ready_in = 0.0
	var mis := _fire(lo)
	assert_eq(mis.size(), 1)
	assert_null(_cluster_mod(mis[0]), "the misfuse never bursts")
	lo.misfuse_skin = &""
	var pistol := Weapon.new(WeaponDB.get_weapon(&"pistol"), 3, WeaponCurve.DEEP)
	var ps := lo.shooter().fire(pistol, Vector2.RIGHT)
	pistol.attach(ps, &"player")
	assert_null(_cluster_mod(ps[0]), "no burst on a weapon without one")
	for p in raw + mis + ps:
		p.queue_free()
	await wait_physics_frames(2)


func test_bomblets_are_refused_at_the_player_budget_never_the_enemies() -> void:
	await _arena()
	assert_true(RunState.path_live(), "the split budgets")
	var lo := _hold(&"cluster", 1)
	var shell := _fire(lo)[0] as Node2D
	var mod := _cluster_mod(shell)
	await wait_physics_frames(1)
	var filler := Tuning.player_projectile_budget - RunState.count(&"player_projectile") - 2
	for i in filler:
		RunState.spawn(PROJECTILE, OPEN * T + Vector2(-10 * T, 0), {&"kind": &"player_projectile",
				&"velocity": Vector2.ZERO, &"lifetime": 60.0})
	await wait_physics_frames(1)
	var enemy_refused := RunState.enemy_shots_refused
	var player_refused := RunState.player_shots_refused
	shell.call(&"explode", shell.global_position)
	assert_eq(mod.bomblets.size(), 2, "two places left under 140")
	assert_eq(mod.refused, 3)
	assert_eq(RunState.player_shots_refused - player_refused, 3)
	assert_eq(RunState.enemy_shots_refused, enemy_refused, "the enemies' 60 is never touched")
	var e := RunState.spawn(PROJECTILE, OPEN * T, {&"kind": &"enemy_projectile", &"faction": &"enemy",
			&"velocity": Vector2.ZERO, &"lifetime": 0.1})
	assert_not_null(e, "an enemy shot still spawns")
	var burst: Array = RunState.run_log.filter(func(x: Dictionary) -> bool: return x.get("event") == &"cluster_burst")
	assert_eq(int(burst[0].refused), 3)
	await _clear_field()


# --- 3. The mechanics ------------------------------------------------------------------------------

func test_sticky_then_the_burst_from_the_stuck_point() -> void:
	await _arena()
	var lo := _hold(&"cluster", 1)
	var e := await _frozen(CHASER, OPEN * T + Vector2(4 * T, 0))
	var shell := _fire(lo)[0] as Node2D
	var mod := _cluster_mod(shell)
	var sticky: StickyMod = null
	for m: Object in shell.call(&"mods"):
		if m.get_script() == StickyMod:
			sticky = m
	assert_not_null(sticky)
	assert_true(sticky.implode, "implode rides the sticky shell")
	var bomblets: Array[Node] = mod.bomblets   # outlives the shell and its mods
	var ws: WeakRef = weakref(sticky)
	var wp: WeakRef = weakref(shell)
	var seen := {"stuck": false, "at": Vector2.ZERO, "pulled": 0, "early": false}
	var watch := func() -> bool:
		var st: StickyMod = ws.get_ref()
		var sh: Node2D = wp.get_ref()
		if st != null and st.stuck and not seen.stuck:
			seen.stuck = true
			seen.early = not bomblets.is_empty()
		if st != null:
			seen.pulled = st.pulled
		if sh != null and not sh.is_queued_for_deletion():
			seen.at = sh.global_position   # the stuck shell rides its target until it blows
		return not bomblets.is_empty()
	assert_true(await _wait_until(watch, 90), "the burst after the fuse")
	assert_true(seen.stuck, "it stuck first")
	assert_false(seen.early, "no burst on contact")
	assert_eq(bomblets.size(), 5)
	assert_almost_eq((bomblets[0] as Node2D).position.distance_to(seen.at), 0.0, 1.0, "from the stuck shell")
	assert_almost_eq(angle_difference((bomblets[0].get(&"velocity") as Vector2).angle(), 0.0), 0.0, 0.0001,
			"the flight angle survives the stop")
	assert_true(int(seen.pulled) >= 1, "implode pulled before the burst")
	e.queue_free()
	await _clear_field()


func test_point_blank_only_on_a_burst_near_the_player() -> void:
	await _arena()
	var lo := _hold(&"cluster", 1)
	for case: Array in [[1.5, true], [3.0, false]]:
		lo.current().ready_in = 0.0
		var shell := _fire(lo)[0] as Node2D
		var mod := _cluster_mod(shell)
		var pb: PointBlankClusterMod = null
		for m: Object in shell.call(&"mods"):
			if m.get_script() == PointBlankClusterMod:
				pb = m
		assert_not_null(pb)
		await wait_physics_frames(1)
		var base := float(shell.get(&"damage"))
		shell.call(&"explode", player.global_position + Vector2(float(case[0]) * T, 0))
		assert_eq(pb.applied, case[1], "burst at %s T" % case[0])
		var want := base * (2.0 if case[1] else 1.0)
		assert_almost_eq(float(shell.get(&"damage")), want, 0.0001)
		assert_almost_eq(float(mod.bomblets[0].get(&"damage")), want * ClusterMod.BOMBLET_MULT, 0.0001, "the bomblets carry it")
		await _clear_field()


func test_the_blast_knocks_back_by_the_cone_level() -> void:
	await _arena()
	assert_eq(_fire(_hold(&"cluster", 1))[0].get(&"blast_knockback"), 420.0)
	assert_almost_eq(float(_fire(_hold(&"cluster", 7))[0].get(&"blast_knockback")), 420.0 * 1.3, 0.001, "rank 7: level 2")
	assert_eq(_fire(_hold(&"launcher", 7))[0].get(&"blast_knockback"), 0.0, "the launcher's blast stays still")
	await _clear_field()
	var e := await _frozen(CHASER, OPEN * T + Vector2(4 * T, 0)) as CharacterBody2D
	var lo := _hold(&"cluster", 1)
	var shell := _fire(lo)[0] as Node2D
	await wait_physics_frames(1)
	e.velocity = Vector2.ZERO
	shell.call(&"explode", e.global_position + Vector2(-0.5 * T, 0))
	assert_gt(e.velocity.x, 100.0, "pushed away from the blast")
	await _clear_field()


# --- 4. The cap and the power bench ----------------------------------------------------------------

## Cluster 20 against a crowd at 60 enemies (half shooters) for 30 s: player shots never over
## 140, the enemies keep firing, none of their shots refused, no mines.
func test_cluster_20_in_a_crowd_stays_under_the_budgets() -> void:
	await _arena()
	var lo := _hold(&"cluster", 20)
	for i in 60:
		var at := OPEN * T + Vector2(6 * T, 0).rotated(TAU * i / 60.0) * (1.0 + 0.25 * (i % 3))
		var e := RunState.spawn(SHOOTER if i % 2 == 0 else CHASER, at) as Node2D
		assert_not_null(e)
	await wait_physics_frames(2)
	for e in get_tree().get_nodes_in_group(&"enemy"):
		(Component.find(e, Health) as Health).base_max_hp = 1.0e6
	var enemy_fired := [0]
	_on(EventBus.projectile_fired, func(p: Node) -> void:
		if p.get(&"faction") == &"enemy":
			enemy_fired[0] += 1)
	var refused := RunState.enemy_shots_refused
	var most := 0
	for f in 30 * 60:
		var nearest: Node2D = null
		for e in get_tree().get_nodes_in_group(&"enemy"):
			if nearest == null or player.global_position.distance_squared_to(e.global_position) \
					< player.global_position.distance_squared_to(nearest.global_position):
				nearest = e
		if nearest != null:
			lo.try_fire(nearest.global_position - player.global_position)
		most = maxi(most, RunState.count(&"player_projectile"))
		await wait_physics_frames(1)
	var thrown := 0
	for x: Dictionary in RunState.run_log:
		if x.get("event") == &"cluster_burst":
			thrown += int(x.get("bomblets", 0))
	gut.p("cluster 20 crowd: max player shots %d, bomblets %d, enemy shots %d" % [most, thrown, enemy_fired[0]])
	assert_lte(most, Tuning.player_projectile_budget)
	assert_gt(thrown, 100, "it kept bursting")
	assert_gt(enemy_fired[0], 0, "the enemies still fire")
	assert_eq(RunState.enemy_shots_refused, refused)
	assert_eq(get_tree().get_nodes_in_group(&"mine").size(), 0, "Cluster lays no mines")
	await _clear_field()


## The targets, placed after they spawned (no step toward the player): one tank, or a pack of
## 8 chasers 0.75 T apart (rows of 3, 3, 2; the middle row on the aim line). AI off, bodies
## still movable (knockback and implode act), HP that never runs out. The near face is
## BENCH_FACE T from the player: all 5 of Prism's beams land on the tank there, and neither
## weapon's point blank reaches it at ranks 5-13.
func _place(crowd: bool) -> void:
	var face := OPEN * T + Vector2(BENCH_FACE * T, 0)
	var centre := face + Vector2(15.0 + 0.75 * T, 0) if crowd else face + Vector2(22.0, 0)
	var spots: Array[Vector2] = [Vector2.ZERO]
	if crowd:
		spots = [Vector2(-0.75, -0.75), Vector2(0, -0.75), Vector2(0.75, -0.75), Vector2(-0.75, 0),
				Vector2(0, 0), Vector2(0.75, 0), Vector2(-0.375, 0.75), Vector2(0.375, 0.75)]
	var made: Array[Node2D] = []
	for at in spots:
		made.append(RunState.spawn(CHASER if crowd else TANK, centre + at * T) as Node2D)
	await wait_physics_frames(1)
	for i in made.size():
		var e := made[i] as CharacterBody2D
		e.set_physics_process(false)
		(Component.find(e, Mover) as Mover).wish = Vector2.ZERO
		(Component.find(e, Health) as Health).base_max_hp = 1.0e6
		e.velocity = Vector2.ZERO
		e.global_position = centre + spots[i] * T
	await wait_physics_frames(1)


## `id` at `rank`: the damage of one shot (all of it: blasts, bomblets, burns) over its cooldown.
## Deterministic, so one shot per case.
func _dps(id: StringName, rank: int, crowd: bool) -> float:
	await _clear_field()
	player.global_position = OPEN * T
	await _place(crowd)
	var lo := _hold(id, rank)
	var dmg := [0.0]
	var add := func(entity: Node, info: DamageInfo) -> void:
		if entity.is_in_group(&"enemy"):
			dmg[0] += info.amount
	_on(EventBus.entity_damaged, add)
	lo.try_fire(Vector2.RIGHT)
	for f in BENCH_FRAMES:
		player.global_position = OPEN * T
		await wait_physics_frames(1)
	EventBus.entity_damaged.disconnect(add)
	return dmg[0] / float(lo.current().value(&"cooldown"))


func test_cluster_vs_prism_power_bench() -> void:
	await _arena()
	var lines: Array[String] = []
	for rank: int in [5, 9, 13]:
		var cs := await _dps(&"cluster", rank, false)
		var ps := await _dps(&"prism", rank, false)
		var cc := await _dps(&"cluster", rank, true)
		var pc := await _dps(&"prism", rank, true)
		lines.append("rank %d: tank %.1f/%.1f = %.2f, pack %.1f/%.1f = %.2f" % [rank, cs, ps, cs / ps, cc, pc, cc / pc])
		assert_between(cs / ps, SINGLE_BAND.x, SINGLE_BAND.y, "rank %d single target" % rank)
		assert_between(cc / pc, CROWD_BAND.x, CROWD_BAND.y, "rank %d crowd" % rank)
	gut.p("[bench] cluster_vs_prism (dps cluster/prism) " + " | ".join(lines))
	await _clear_field()
