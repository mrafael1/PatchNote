extends GutTest
## M50.4c2 (Auto depth design, .check/auto_depth rev. 2, sections 5 and 9): the Supernova (nova +
## Might, a node weapon: every 2.0 s a 2.5 T blast for 8, the shockwave ring to 6 T at 0.75x, a
## 1.5 T shove; launch 1.2 s / 12) keeps nova's clocks when it evolves and when its numbers
## change; the Thunderclap (shotgun + Area: 7 pellets over 34 degrees every 0.5 s, each volley
## one Explosion.blast 2.5 T ahead, 1.0 T radius, 2 damage, knockback 420; launch 1.5 T / 4)
## pops one blast per volley and its pellets never blast; and the 3-evolution caps bench (all
## three at launch at the enemy cap: player shots <= 140, enemy shots <= 60, a shooter and a
## 16-shot ring still fire, enemy_shots_refused 0).

const T := 48.0
const OPEN := Vector2(34, 20)
const CHASER := preload("res://entities/enemy_chaser.tscn")
const SHOOTER := preload("res://entities/enemy_shooter.tscn")
const PROJECTILE := preload("res://entities/projectile.tscn")
const Clap := preload("res://weapons/traits/clap.gd")

var game: Main
var player: CharacterBody2D


func after_each() -> void:
	RunState.invincible = false
	RunState.session_path = &""
	RunState.set_pause(PickPanel.PAUSE, false)
	RunState.reset(0)
	RunState.world = null
	Skins.use(null)


func _auto() -> PathDef:
	return PathDB.get_def(&"auto")


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


## The arena on a live Auto path, the runner frozen (no gems, no level-ups).
func _auto_runner() -> PathRunner:
	await _arena()
	RunState.session_path = &"auto"
	var r := game.ensure_path_runner()
	r.freeze()
	r.begin()
	r.frozen = false
	await wait_physics_frames(1)
	r.freeze()
	return r


func _evolve(r: PathRunner, from: StringName, item: StringName) -> Weapon:
	var lo := r.loadout()
	lo.set_weapon(from, 6)
	if lo.item(item) == null:
		lo.add_item(item)
	var ev := r.evolve_option()
	assert_eq(ev.get("from"), from, "EVOLVE offered for %s" % from)
	r._take_evolve(lo, ev)
	return lo.held(ev.into)


# --- Data -----------------------------------------------------------------------------------

func test_both_rows_are_built_and_report_nothing() -> void:
	for p in WeaponDB.evolution_problems():
		assert_false("supernova" in p or "thunderclap" in p, p)
	var nova := Weapon.new(WeaponDB.get_weapon(&"supernova"), 1, WeaponCurve.DEEP)
	assert_eq(nova.traits.map(func(t: WeaponTrait) -> String: return "%s:%d" % [t.id, t.level]),
			["shove:1", "dash_nova:1", "shockwave:1", "supernova:1"])
	assert_eq(nova.label(), "SUPERNOVA")
	assert_almost_eq(float(nova.value(&"cooldown")), 2.0, 0.0001)
	assert_almost_eq(float(nova.value(&"damage")), 8.0, 0.0001)
	assert_almost_eq(float(nova.value(&"blast_radius")), 2.5, 0.0001)
	var clap := Weapon.new(WeaponDB.get_weapon(&"thunderclap"), 1, WeaponCurve.DEEP)
	assert_eq(clap.traits.map(func(t: WeaponTrait) -> String: return "%s:%d" % [t.id, t.level]),
			["knockback_cone:1", "point_blank:1", "shrapnel:1", "clap:1"])
	assert_eq(int(clap.value(&"pellets")), 7)
	assert_almost_eq(float(clap.value(&"spread_deg")), 34.0, 0.0001, "point blank's 18 degrees are the shotgun's, not the clap's")
	assert_almost_eq(float(clap.value(&"cooldown")), 0.5, 0.0001)
	assert_almost_eq(float(clap.value(&"damage")), 2.0, 0.0001)
	assert_almost_eq(float(clap.value(&"blast_radius")), 1.0, 0.0001, "2 T across")
	assert_eq(WeaponDB.get_weapon(&"supernova").launch_values, {&"cooldown": 1.2, &"damage": 12.0})
	assert_eq(WeaponDB.get_weapon(&"thunderclap").launch_values, {&"blast_radius": 1.5, &"damage": 4.0})


func test_both_have_their_pictures_and_card_lines() -> void:
	for icon: StringName in [&"supernova", &"thunderclap"]:
		assert_true(CardArt.GUNS.has(icon), "%s has a Pixel picture" % icon)
		var grid: Array = CardArt.GUNS[icon][0]
		for row: String in grid:
			assert_eq(row.length(), String(grid[0]).length(), "%s: rows line up" % icon)
			for ch in row:
				assert_true(ch == "." or (CardArt.GUNS[icon][1] as Dictionary).has(ch), "%s: %s has a colour" % [icon, ch])
		for role: StringName in (CardArt.GUNS[icon][1] as Dictionary).values():
			assert_ne(CardArt.c(role), Color.MAGENTA, "%s: %s is a colour" % [icon, role])
	var nova := LevelCard.data_for_evolve({"from": &"nova", "into": &"supernova", "catalyst": &"might", "rank": 6}, "4")
	assert_eq(String(nova.effect), "A bigger nova, a wider ring.", "no 'sweeping stream' on a nova")
	assert_eq(String(nova.title), "Supernova")
	var clap := LevelCard.data_for_evolve({"from": &"shotgun", "into": &"thunderclap", "catalyst": &"area", "rank": 6}, "4")
	assert_eq(String(clap.effect), "Every volley claps a blast ahead.")
	var mini := LevelCard.data_for_evolve({"from": &"pistol", "into": &"minigun", "catalyst": &"haste", "rank": 6}, "4")
	assert_true(String(mini.effect).ends_with("a sweeping stream"), "the Minigun's line is unchanged")


# --- Supernova ------------------------------------------------------------------------------

func test_the_supernova_node_carries_its_numbers() -> void:
	var r := await _auto_runner()
	var w := _evolve(r, &"nova", &"might")
	var lo := r.loadout()
	assert_eq(lo.summary(), "pistol:1,supernova:1", "in nova's place")
	var node: Node = lo.passive_node(&"supernova")
	assert_not_null(node)
	assert_null(lo.passive_node(&"nova"), "nova's node is gone")
	assert_almost_eq(float(node.cooldown), 2.0, 0.0001)
	assert_almost_eq(float(node.radius), 2.5 * Tuning.TILE, 0.001)
	assert_almost_eq(float(node.damage), 8.0 * 1.08, 0.0001, "Might 1 is held")
	assert_true(node.shove and node.dash_nova and node.shockwave)
	assert_almost_eq(float(node.ring_to), 6.0, 0.0001)
	assert_almost_eq(float(node.ring_mult), 0.75, 0.0001)
	assert_almost_eq(float(node.shove_impulse), node.SHOVE_IMPULSE * 1.5, 0.001)
	node.go_off()
	var rings := get_tree().get_nodes_in_group(&"shockwave_ring")
	assert_eq(rings.size(), 1)
	assert_almost_eq(float(rings[0].to_r), 6.0 * Tuning.TILE, 0.001)
	assert_almost_eq(float(rings[0].damage), 8.0 * 1.08 * 0.75, 0.0001)
	assert_eq(w.def.id, &"supernova")
	await wait_physics_frames(2)   # the blast's ring visual is added deferred: let it land
	lo.clear()


func test_a_plain_nova_keeps_its_numbers() -> void:
	var r := await _auto_runner()
	var lo := r.loadout()
	lo.set_weapon(&"nova", 6)
	var node: Node = lo.passive_node(&"nova")
	assert_almost_eq(float(node.ring_to), 4.0, 0.0001)
	assert_almost_eq(float(node.ring_mult), 0.5, 0.0001)
	assert_almost_eq(float(node.shove_impulse), 610.0, 0.0001)
	lo.clear()


func test_the_supernova_keeps_novas_clock() -> void:
	var r := await _auto_runner()
	var lo := r.loadout()
	lo.set_weapon(&"nova", 6)
	lo.add_item(&"might")
	var nova: Node = lo.passive_node(&"nova")
	await wait_physics_frames(120)   # 2 s of nova's 3 s: about 1 s left
	var left := float(nova.clocks()[0])
	assert_lt(left, 1.2)
	r._take_evolve(lo, r.evolve_option())
	var sn: Node = lo.passive_node(&"supernova")
	assert_almost_eq(float(sn.clocks()[0]), left, 0.0001, "the next blast does not move")
	await wait_physics_frames(10)
	var mid := float(sn.clocks()[0])
	lo.level_item(&"might")
	assert_almost_eq(float(sn.clocks()[0]), mid, 0.0001, "an item pick keeps the clock")
	lo.clear()
	# A fresh nova (3 s left) evolves into a 2 s period: clamped to the new period.
	lo.apply_path(_auto())
	lo.set_weapon(&"nova", 6)
	lo.add_item(&"might")
	r.evolutions.clear()
	r._take_evolve(lo, r.evolve_option())
	assert_lte(float(lo.passive_node(&"supernova").clocks()[0]), 2.0 + 0.0001, "never past the new period")
	lo.clear()


func test_the_nerf_rereads_the_supernova_node() -> void:
	var r := await _auto_runner()
	var w := _evolve(r, &"nova", &"might")
	var lo := r.loadout()
	var node: Node = lo.passive_node(&"supernova")
	await wait_physics_frames(30)
	var left := float(node.clocks()[0])
	assert_true(r.arm_nerf(8.0))
	assert_almost_eq(float(node.cooldown), 1.2, 0.0001, "launch: every 1.2 s")
	assert_almost_eq(float(node.damage), 12.0 * 1.08, 0.0001, "launch damage, Might on top")
	assert_lte(float(node.clocks()[0]), 1.2 + 0.0001, "the clock fits the launch period")
	assert_lte(float(node.clocks()[0]), left)
	r._land_nerf()
	assert_almost_eq(float(node.cooldown), 2.0, 0.0001, "patched to the steady period")
	assert_almost_eq(float(node.damage), 8.0 * 1.08, 0.0001)
	assert_eq(String(r.nerf.text), "Balance: Supernova every 1.2 s -> every 2 s, damage 12.96 -> 8.64. It was too strong.")
	assert_true(w.launch.is_empty())
	lo.clear()


## Review fix: the Thunderclap has no cooldown launch key, so its note names no fire rate
## ("2 -> 2 shots/s" before) and does name the blast cut.
func test_the_thunderclap_nerf_note_names_the_blast_not_the_rate() -> void:
	var r := await _auto_runner()
	var w := _evolve(r, &"shotgun", &"area")
	assert_true(r.arm_nerf(8.0))
	assert_almost_eq(float(w.value(&"blast_radius")), 1.5 * 1.1, 0.0001)
	r._land_nerf()
	assert_almost_eq(float(w.value(&"blast_radius")), 1.1, 0.0001)
	assert_eq(String(r.nerf.text), "Balance: Thunderclap damage 4 -> 2, blast 1.65 T -> 1.1 T. It was too strong.")
	assert_false("shots/s" in String(r.nerf.text))
	assert_true(w.launch.is_empty())
	r.loadout().clear()


# --- Thunderclap ----------------------------------------------------------------------------

func test_each_volley_claps_one_blast_ahead_and_the_pellets_never_blast() -> void:
	var r := await _auto_runner()
	var w := _evolve(r, &"shotgun", &"area")
	assert_eq(w.def.id, &"thunderclap")
	var lo := r.loadout()
	var blasts := []
	var on_blast := func(pos: Vector2, radius: float) -> void: blasts.append([pos, radius])
	EventBus.explosion.connect(on_blast)
	var shots := lo.shooter().fire(w, Vector2.RIGHT, true)
	EventBus.explosion.disconnect(on_blast)
	assert_eq(shots.size(), 7, "7 pellets")
	for s in shots:
		assert_eq(float(s.get(&"blast_radius")), 0.0, "a pellet never blasts")
	assert_eq(blasts.size(), 1, "one clap per volley")
	var muzzle := player.global_position + Vector2.RIGHT * lo.shooter().muzzle_offset
	assert_almost_eq((blasts[0][0] as Vector2).x, muzzle.x + 2.5 * T, 0.5, "2.5 T ahead")
	assert_almost_eq((blasts[0][0] as Vector2).y, muzzle.y, 0.5, "along the aim (the cone's middle)")
	assert_almost_eq(float(blasts[0][1]), 1.0 * 1.1 * T, 0.01, "1 T, Area 1 grows it 10%")
	var clap: WeaponTrait = w.traits.filter(func(t: WeaponTrait) -> bool: return t.id == &"clap")[0]
	assert_eq(clap.claps, 1)
	await wait_physics_frames(2)   # the blast's ring visual is added deferred: let it land
	lo.clear()


func test_the_clap_hits_and_pushes_what_is_ahead() -> void:
	var r := await _auto_runner()
	var w := _evolve(r, &"shotgun", &"area")
	var lo := r.loadout()
	var dir := Vector2.UP
	var muzzle := player.global_position + dir * lo.shooter().muzzle_offset
	var e := RunState.spawn(CHASER, muzzle + dir * 2.5 * T + Vector2(0.6 * T, 0)) as Node2D
	await wait_physics_frames(1)
	var hp := float(e.health.hp())
	var hits := []
	var on_hit := func(target: Node, info: RefCounted) -> void:
		if target == e and info.kind == &"blast":
			hits.append(info.amount)
	EventBus.entity_damaged.connect(on_hit)
	lo.shooter().fire(w, dir, true)   # the clap is immediate; the pellets land on later ticks
	EventBus.entity_damaged.disconnect(on_hit)
	assert_eq(hits.size(), 1, "the clap hit the chaser once")
	assert_almost_eq(float(hits[0]) if not hits.is_empty() else 0.0, 2.0, 0.001, "2 damage (no Might)")
	assert_lt(float(e.health.hp()), hp)
	await wait_physics_frames(2)
	if is_instance_valid(e):
		assert_gt(e.velocity.dot(Vector2(0.6, -1.0).normalized()), 0.0, "knocked away from the clap's centre")
	lo.clear()


func test_the_thunderclap_launch_numbers() -> void:
	var r := await _auto_runner()
	var w := _evolve(r, &"shotgun", &"area")
	w.launch = WeaponDB.get_weapon(&"thunderclap").launch_values.duplicate()
	assert_almost_eq(float(w.value(&"blast_radius")), 1.5 * 1.1, 0.0001, "3 T across, Area on top")
	assert_almost_eq(float(w.value(&"damage")), 4.0, 0.0001)
	w.launch = {}
	assert_almost_eq(float(w.value(&"blast_radius")), 1.1, 0.0001)
	r.loadout().clear()


func test_a_full_hand_never_drops_an_evolution_first() -> void:
	var r := await _auto_runner()
	var lo := r.loadout()
	_evolve(r, &"nova", &"might")
	lo.set_weapon(&"laser", 2)
	assert_eq(lo.summary(), "pistol:1,laser:2,supernova:1")
	lo.give(&"shotgun")   # full: the weakest non-active goes; the Supernova (rank 1) counts past the cap
	assert_eq(lo.summary(), "pistol:1,shotgun:1,supernova:1", "the laser went, not the Supernova")
	lo.clear()


# --- Caps -----------------------------------------------------------------------------------

func test_three_evolutions_at_launch_stay_in_the_budgets() -> void:
	var r := await _auto_runner()
	var lo := r.loadout()
	lo.set_weapon(&"shotgun", 6)
	lo.set_weapon(&"nova", 6)
	lo.set_weapon(&"pistol", 6)
	lo.add_item(&"haste")
	lo.add_item(&"might")
	for i in 5:
		lo.level_item(&"haste")
		lo.level_item(&"might")
	assert_true(lo.evolve(&"pistol", &"minigun"))
	assert_true(lo.evolve(&"shotgun", &"thunderclap"))
	assert_true(lo.evolve(&"nova", &"supernova"))
	assert_eq(lo.weapon_count(), 3)
	for id: StringName in [&"minigun", &"thunderclap", &"supernova"]:
		var w := lo.held(id)
		w.launch = WeaponDB.get_weapon(id).launch_values.duplicate()
		lo.reread(w)
	var points: Array = game.arena.spawn_points
	var shooters: Array[Node2D] = []
	for k in 2:
		shooters.append(RunState.spawn(SHOOTER, (OPEN + Vector2(-8 + 16 * k, 0)) * T) as Node2D)
	await wait_physics_frames(2)
	for s in shooters:   # 8 T out, in line of sight, huge HP: they live to show they still fire
		s.health.base_max_hp = 1000000.0
		s.health.hp_ratio = 1.0
	var enemy_fired := 0   # the most live enemy shots on a tick
	var most := 0
	for i in 600:   # 10 s at the cap
		var n := 0
		while RunState.count(&"enemy") + RunState.pending_count(&"enemy") < 57 and n < 8:
			RunState.spawn(CHASER, points[(i + n) % points.size()])
			n += 1
		await wait_physics_frames(1)
		most = maxi(most, RunState.count(&"player_projectile"))
		enemy_fired = maxi(enemy_fired, RunState.count(&"enemy_projectile"))
		assert_lte(RunState.count(&"player_projectile"), 140)
		assert_lte(RunState.count(&"enemy_projectile"), 60)
	var made := 0
	for k in 16:   # a 16-shot ring in one frame
		var shot := RunState.spawn(PROJECTILE, player.global_position + Vector2(-6, -3) * T,
				{&"velocity": Vector2.RIGHT.rotated(TAU * k / 16.0) * 200.0, &"kind": &"enemy_projectile", &"faction": &"enemy"})
		if shot != null:
			made += 1
	gut.p("most live player shots %d, refused %d; most live enemy shots %d (shooters alive %d, windups %d); novas %d; claps %d" % [most,
			RunState.player_shots_refused, enemy_fired, shooters.filter(func(x: Node2D) -> bool: return is_instance_valid(x)).size(),
			shooters.reduce(func(a: int, x: Node2D) -> int: return a + (int(x.windups) if is_instance_valid(x) else 0), 0), int(lo.passive_node(&"supernova").novas),
			int(lo.held(&"thunderclap").traits.filter(func(t: WeaponTrait) -> bool: return t.id == &"clap")[0].claps)])
	assert_eq(made, 16, "the ring fits")
	assert_gt(enemy_fired, 0, "a shooter fired under the three evolutions")
	assert_eq(RunState.enemy_shots_refused, 0)
	assert_gt(int(lo.passive_node(&"supernova").novas), 6, "every 1.2 s for 10 s")
	await wait_physics_frames(1)
	lo.clear()
