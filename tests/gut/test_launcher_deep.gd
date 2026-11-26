extends GutTest
## M50.3a (Arcade through S10 design 3, .check/arcade_s10/design.md): the launcher on the deep
## curve (sticky at 2, implode at 4, mine_layer at 6, then their levels), sticky / implode steps
## whose level 1 is today's constants (the classic curve never moves), the mine (every 3rd
## spawned shell, arms at 0.5 s, blows on the first enemy within 0.5 T, credits the launcher,
## fizzles at 12 s, capped, the oldest goes) and Projectile.explode (blast, contact event,
## blasted(), despawn; its radius argument; blast_knockback 0 by default).

const CHASER := preload("res://entities/enemy_chaser.tscn")
const PROJECTILE := preload("res://entities/projectile.tscn")
const StickyMod := preload("res://weapons/traits/sticky_mod.gd")
const Mine := preload("res://weapons/traits/mine.gd")
const T := 48.0
const OPEN := Vector2(34, 20)
const TEST_LOG := "user://save_launcher_test/runs.jsonl"

var game: Main
var player: CharacterBody2D
var _links: Array = []
var _max_projectiles := 0


## Records the order of a blast shot's hooks.
class Recorder:
	extends ProjectileMod
	var seen: Array = []
	func blasted(_p: Node2D, pos: Vector2) -> void:
		seen.append(["blasted", pos])
	func despawned(_p: Node2D) -> void:
		seen.append(["despawned"])


func before_each() -> void:
	Telemetry.log_path = TEST_LOG
	_max_projectiles = Tuning.hard_max_projectiles


func after_each() -> void:
	for l: Array in _links:
		if (l[0] as Signal).is_connected(l[1]):
			(l[0] as Signal).disconnect(l[1])
	_links.clear()
	Tuning.hard_max_projectiles = _max_projectiles
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.invincible = false
	CampaignDB.active = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(TEST_LOG)


## The legacy arena (no session, no path): spawner and director off, no enemies.
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
	player.global_position = OPEN * T
	player.velocity = Vector2.ZERO
	RunState.invincible = true


func _frozen_chaser(tile: Vector2, hp := 100.0) -> Node2D:
	var e := RunState.spawn(CHASER, tile * T) as Node2D
	await wait_physics_frames(2)
	e.set_physics_process(false)
	e.mover.wish = Vector2.ZERO
	e.velocity = Vector2.ZERO
	e.health.base_max_hp = hp
	return e


func _launcher(rank: int, curve := &"deep") -> Weapon:
	return Weapon.new(WeaponDB.get_weapon(&"launcher"), rank, curve)


## Fires `w` once from the player along `dir`, as the Loadout would (a shot counts only when
## it spawned).
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


func _on(sig: Signal, c: Callable) -> void:
	sig.connect(c)
	_links.append([sig, c])


func _levels(w: Weapon) -> Dictionary:
	var out := {}
	for t in w.traits:
		out[String(t.id)] = t.level
	return out


# --- 1. Data and the deep table ----------------------------------------------------------------

func test_the_deep_table_1_to_12() -> void:
	var def := WeaponDB.get_weapon(&"launcher")
	assert_eq(def.mechanics, [&"sticky", &"implode", &"mine_layer"] as Array[StringName])
	assert_eq(def.mechanic_values.size(), 3)
	assert_eq(def.icon, &"bomb")
	assert_eq(WeaponDB.problems(), [] as Array[String])
	var damage := [2.0, 2.0, 3.0, 3.0, 4.0, 4.0, 6.0, 6.0, 8.0, 8.0, 12.0, 12.0]
	var levels := [{}, {"sticky": 1}, {"sticky": 1}, {"sticky": 1, "implode": 1}, {"sticky": 1, "implode": 1},
			{"sticky": 1, "implode": 1, "mine_layer": 1}, {"sticky": 1, "implode": 1, "mine_layer": 1},
			{"sticky": 2, "implode": 1, "mine_layer": 1}, {"sticky": 2, "implode": 1, "mine_layer": 1},
			{"sticky": 2, "implode": 2, "mine_layer": 1}, {"sticky": 2, "implode": 2, "mine_layer": 1},
			{"sticky": 2, "implode": 2, "mine_layer": 2}]
	for r in range(1, 13):
		var w := _launcher(r)
		assert_almost_eq(float(w.value(&"damage")), damage[r - 1], 0.0001, "rank %d damage" % r)
		assert_eq(_levels(w), levels[r - 1], "rank %d mechanics" % r)
		assert_almost_eq(float(w.value(&"blast_radius")), 1.6, 0.0001, "rank %d blast" % r)
	assert_eq(_launcher(20).traits.size(), 3, "rank 20 builds")


func test_classic_stays_todays_launcher() -> void:
	assert_eq(_levels(_launcher(1, &"classic")), {})
	assert_eq(_levels(_launcher(2, &"classic")), {"sticky": 1})
	assert_eq(_levels(_launcher(3, &"classic")), {"sticky": 1, "implode": 1}, "no mines on classic")
	assert_eq(float(_launcher(3, &"classic").value(&"damage")), 2.0)


func test_sticky_and_implode_steps_start_at_todays_constants() -> void:
	var s := WeaponTrait.make(&"sticky")
	var i := WeaponTrait.make(&"implode")
	assert_eq(s.steps().size(), 4)
	assert_eq(i.steps().size(), 4)
	assert_almost_eq(float(s.step_value(&"radius_mult")), StickyMod.RADIUS_MULT, 0.0001, "level 1 = today")
	assert_almost_eq(float(i.step_value(&"pull")), StickyMod.IMPLODE_PULL, 0.0001, "level 1 = today")
	assert_eq([1.2, 1.3, 1.4, 1.5], [1, 2, 3, 4].map(func(l: int) -> float: return float(s.value_at(l, &"radius_mult"))))
	assert_eq([455.0, 606.0, 758.0, 910.0], [1, 2, 3, 4].map(func(l: int) -> float: return float(i.value_at(l, &"pull"))))
	assert_almost_eq(float(s.value_at(5, &"radius_mult")), 1.65, 0.0001, "overflow +10%")
	assert_almost_eq(float(i.value_at(6, &"pull")), 1092.0, 0.0001)
	var m := WeaponTrait.make(&"mine_layer")
	assert_eq([1, 2, 3, 4].map(func(l: int) -> int: return int(m.value_at(l, &"every"))), [3, 3, 2, 2])
	assert_eq([1, 2, 3, 4].map(func(l: int) -> int: return int(m.value_at(l, &"max"))), [4, 5, 5, 6])
	assert_almost_eq(float(m.value_at(5, &"damage_mult")), 1.1, 0.0001, "overflow strengthens the mine")
	assert_eq(int(m.value_at(9, &"max")), 6, "the cap never grows past 6")
	assert_eq(s.describe(1), "sticky: shells stick, then blow bigger (x1.2)")
	assert_eq(i.describe(1), "implode: the blast pulls enemies in")
	assert_eq(m.describe(1), "mine layer: every 3rd shot drops a mine (4 max)")
	assert_eq(m.describe(5), "mine layer: every 2nd shot drops a mine (6 max) (x1.1)")


func test_card_lines_name_the_launcher_mechanics() -> void:
	var def := WeaponDB.get_weapon(&"launcher")
	assert_string_contains(WeaponCurve.gain_text(def, 1, 2), "sticky: shells stick")
	assert_string_contains(WeaponCurve.gain_text(def, 3, 4), "implode")
	assert_string_contains(WeaponCurve.gain_text(def, 5, 6), "mine layer: every 3rd shot")
	assert_string_contains(WeaponCurve.gain_text(def, 7, 8), "+sticky")
	assert_false(WeaponCurve.gain_text(def, 5, 6).contains("not built"))


# --- 2. Sticky / implode levels in play --------------------------------------------------------

func test_sticky_level_2_blows_at_1_3x_and_implode_level_2_pulls_harder() -> void:
	await _arena()
	await _frozen_chaser(OPEN + Vector2(3, 0))
	var blasts: Array = []
	_on(EventBus.explosion, func(_pos: Vector2, r: float) -> void: blasts.append(r))
	var shell := _fire(_launcher(10))[0]
	var mod: Node = shell.mods().filter(func(m: Node) -> bool: return m.get_script() == StickyMod)[0]
	assert_almost_eq(float(mod.radius_mult), 1.3, 0.0001, "sticky level 2")
	assert_true(mod.implode)
	assert_almost_eq(float(mod.pull), 606.0, 0.0001, "implode level 2")
	assert_true(await _wait_until(func() -> bool: return not blasts.is_empty(), 90))
	assert_almost_eq(float(blasts[0]), 1.6 * T * 1.3, 0.01)
	var classic := _fire(_launcher(3, &"classic"))[0]
	var cmod: Node = classic.mods().filter(func(m: Node) -> bool: return m.get_script() == StickyMod)[0]
	assert_eq([cmod.radius_mult, cmod.pull], [StickyMod.RADIUS_MULT, StickyMod.IMPLODE_PULL], "classic = the consts")
	await wait_physics_frames(60)   # its blast lands inside the test (no orphan)


# --- 3. Mines --------------------------------------------------------------------------------

func test_a_mine_every_third_spawned_shell_and_none_from_a_refused_one() -> void:
	await _arena()
	var w := _launcher(6)
	for k in 6:
		_fire(w, Vector2.UP)
		await wait_physics_frames(1)
	assert_eq(Mine.alive(), 2, "shots 3 and 6")
	# The 9th shot is refused at the cap: no mine, and it is not counted.
	for k in 2:
		_fire(w, Vector2.UP)
	await wait_physics_frames(1)
	assert_eq(w.shots, 8)
	Tuning.hard_max_projectiles = 0
	assert_true(_fire(w, Vector2.UP).is_empty(), "refused")
	await wait_physics_frames(1)
	assert_eq([w.shots, Mine.alive()], [8, 2], "a refused shell drops none and is not counted")
	Tuning.hard_max_projectiles = _max_projectiles
	assert_false(_fire(w, Vector2.UP).is_empty())
	await wait_physics_frames(1)
	assert_eq(Mine.alive(), 3, "the next spawned shell is the 9th")
	var laid := RunState.run_log.filter(func(e: Dictionary) -> bool: return e.get("event") == &"mine_laid").size()
	assert_eq(laid, 3, "telemetry: laid")


func test_no_mine_on_the_classic_curve_or_below_rank_6() -> void:
	await _arena()
	for w: Weapon in [_launcher(3, &"classic"), _launcher(5)]:
		for k in 6:
			_fire(w, Vector2.UP)
			await wait_physics_frames(1)
	assert_eq(Mine.alive(), 0)


func test_a_mine_arms_blows_on_an_enemy_and_credits_the_launcher() -> void:
	await _arena()
	var e := await _frozen_chaser(OPEN + Vector2(6, 0))
	var at := e.global_position + Vector2(0.3 * T, 0)
	var t0 := RunState.game_time
	var blasts: Array = []
	_on(EventBus.explosion, func(_pos: Vector2, r: float) -> void: blasts.append([RunState.game_time - t0, r]))
	var m: Node2D = Mine.drop(at, 4.0, 4, &"weapon:launcher")
	await wait_physics_frames(10)
	assert_false(m.is_armed(), "not armed before 0.5 s")
	assert_true(blasts.is_empty())
	assert_true(await _wait_until(func() -> bool: return not blasts.is_empty(), 60))
	assert_almost_eq(float(blasts[0][0]), Mine.ARM, 3.0 / 60.0, "blows once armed")
	assert_almost_eq(float(blasts[0][1]), 1.6 * T, 0.01)
	assert_almost_eq(e.health.hp(), 96.0, 0.01, "the mine's damage")
	assert_gt(float(RunState.damage_by_source.get(&"weapon:launcher", 0.0)), 0.0, "credited to the launcher")
	await wait_physics_frames(1)
	assert_eq(Mine.alive(), 0, "one blast, then gone")
	assert_lt(player.velocity.length(), 1.0, "the player is not pushed")


func test_a_mine_ignores_an_enemy_out_of_reach_and_fizzles_at_12_s() -> void:
	await _arena()
	var e := await _frozen_chaser(OPEN + Vector2(6, 0))
	var m: Node2D = Mine.drop(e.global_position + Vector2(0, 2.0 * T), 4.0, 4, &"weapon:launcher")
	await wait_physics_frames(45)
	assert_true(m.is_armed())
	assert_eq(e.health.hp(), 100.0, "out of reach")
	await wait_physics_frames(int(Mine.LIFE * 60) - 50)
	assert_true(is_instance_valid(m) and not m.is_queued_for_deletion(), "still there just before 12 s")
	await wait_physics_frames(10)
	assert_true(not is_instance_valid(m) or m.is_queued_for_deletion(), "fizzled")
	assert_eq(e.health.hp(), 100.0, "a fizzle deals nothing")


func test_mines_are_capped_and_the_oldest_goes() -> void:
	await _arena()
	var first: Node2D = null
	for k in 8:
		var m: Node2D = Mine.drop(OPEN * T + Vector2(k * 10, -100), 1.0, 4, &"weapon:launcher")
		if k == 0:
			first = m
		await wait_physics_frames(1)
	assert_eq(Mine.alive(), 4, "cap 4")
	assert_true(not is_instance_valid(first) or first.is_queued_for_deletion(), "the oldest went first")
	for k in 4:
		Mine.drop(OPEN * T + Vector2(k * 10, -60), 1.0, 6, &"weapon:launcher")
		await wait_physics_frames(1)
	assert_eq(Mine.alive(), 6, "cap 6")


## The M50.3a hard gate: mines stay under the cap at rank 20 (every 2nd shot, 6 max).
func test_rank_20_keeps_mines_under_the_cap() -> void:
	await _arena()
	var w := _launcher(20)
	var lv := w.trait_level(&"mine_layer")
	assert_eq(lv, 3, "rank 20: sticky 4, implode 3, mine layer 3")
	var cap := int(WeaponTrait.make(&"mine_layer", lv, true).step_value(&"max"))
	assert_eq(cap, 5)
	var most := 0
	for k in 40:
		_fire(w, Vector2.UP)
		await wait_physics_frames(1)
		most = maxi(most, Mine.alive())
	assert_eq(most, cap, "full but never over")


# --- 4. Projectile.explode -------------------------------------------------------------------

func test_explode_order_on_an_enemy_and_on_a_wall() -> void:
	await _arena()
	var e := await _frozen_chaser(OPEN + Vector2(3, 0))
	var order: Array = []
	_on(EventBus.explosion, func(_pos: Vector2, _r: float) -> void: order.append("blast"))
	_on(EventBus.projectile_hit, func(_p: Node, _t: Node, _pos: Vector2) -> void: order.append("hit"))
	_on(EventBus.projectile_hit_wall, func(_p: Node, _pos: Vector2, _n: Vector2) -> void: order.append("wall"))
	var shell := _fire(_launcher(1))[0]
	assert_eq(float(shell.blast_knockback), 0.0, "no knockback by default")
	var rec := Recorder.new()
	shell.add_mod(rec)
	var log1: Array = rec.seen
	assert_true(await _wait_until(func() -> bool: return not order.is_empty(), 60))
	assert_eq(order, ["blast", "hit"])
	assert_eq(log1.map(func(x: Array) -> String: return x[0]), ["blasted", "despawned"], "blasted, then the despawn")
	assert_almost_eq(e.health.hp(), 98.0, 0.01)
	order.clear()
	var down := _fire(_launcher(1), Vector2.DOWN)[0]
	var rec2 := Recorder.new()
	down.add_mod(rec2)
	var log2: Array = rec2.seen
	assert_true(await _wait_until(func() -> bool: return not order.is_empty(), 60))
	assert_eq(order, ["blast", "wall"])
	assert_eq(log2.map(func(x: Array) -> String: return x[0]), ["blasted", "despawned"])


func test_explode_takes_a_radius_and_a_knockback() -> void:
	await _arena()
	var e := await _frozen_chaser(OPEN + Vector2(6, 0))
	var radii: Array = []
	_on(EventBus.explosion, func(_pos: Vector2, r: float) -> void: radii.append(r))
	var p := RunState.spawn(PROJECTILE, OPEN * T, {&"kind": &"player_projectile", &"blast_radius": 40.0,
			&"velocity": Vector2.ZERO, &"lifetime": 5.0}) as Node2D
	await wait_physics_frames(1)
	p.explode(OPEN * T, 25.0)
	assert_eq(radii, [25.0], "the radius argument")
	var q := RunState.spawn(PROJECTILE, OPEN * T, {&"kind": &"player_projectile", &"blast_radius": 40.0,
			&"velocity": Vector2.ZERO, &"lifetime": 5.0, &"blast_knockback": 600.0}) as Node2D
	await wait_physics_frames(1)
	var before := e.global_position
	q.explode(e.global_position + Vector2(-20, 0))
	assert_eq(radii, [25.0, 40.0], "-1: its own blast_radius")
	await wait_physics_frames(10)
	assert_gt(e.global_position.x, before.x + 2.0, "blast_knockback pushes")
