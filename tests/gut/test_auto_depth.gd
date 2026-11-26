extends GutTest
## M50.4a (Auto depth design, .check/auto_depth rev. 2, sections 2, 3, 7): Auto on the deep
## curve to rank 6, 3 shared weapon slots (nova / well take one), no level cap, the two
## fillers (+1 max HP, +5% damage), nova's rank-6 shockwave, the raw widget rows and the rail's
## weapon row. Arsenal, Survival and no-path stay as they were.

const CHASER := preload("res://entities/enemy_chaser.tscn")
const LevelMeter := preload("res://paths/auto/level_meter.gd")
const LevelWidget := preload("res://paths/auto/level_widget.gd")
const ShockwaveRing := preload("res://weapons/traits/shockwave_ring.gd")
const T := 48.0
const OPEN := Vector2(34, 20)

var game: Main
var player: CharacterBody2D


func after_each() -> void:
	RunState.invincible = false
	RunState.reset(0)
	RunState.world = null


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


func _loadout() -> Loadout:
	return Component.find(player, Loadout) as Loadout


func _offer(lo: Loadout, pool: Array[StringName], run_seed := 7) -> PickOffer:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	return PickOffer.draw(lo, _auto(), pool, &"", rng, Taste.new())


func _frozen_chaser(tile: Vector2, hp := 100.0) -> Node2D:
	var e := RunState.spawn(CHASER, tile * T) as Node2D
	await wait_physics_frames(2)
	e.set_physics_process(false)
	e.mover.wish = Vector2.ZERO
	e.velocity = Vector2.ZERO
	e.health.base_max_hp = hp
	e.health.hp_ratio = 1.0
	return e


# --- Data -----------------------------------------------------------------------------------

func test_auto_is_deep_to_six_with_three_shared_slots_and_no_cap() -> void:
	var a := _auto()
	assert_eq(a.problems(), [] as Array[String])
	assert_eq([a.rank_curve, a.rank_cap, a.max_slots, a.max_passives, a.max_items, a.shared_slots, a.max_picks],
			[&"deep", 6, 3, 0, 2, true, 0])
	for id: StringName in [&"arsenal", &"survival"]:
		assert_false(PathDB.get_def(id).shared_slots, "%s keeps its own slots" % id)
		assert_eq(PathDB.get_def(id).max_items, 0)


func test_a_shared_slots_path_needs_max_passives_zero() -> void:
	var d := _auto().duplicate() as PathDef
	d.max_passives = 2
	assert_true(d.problems().any(func(p: String) -> bool: return p.contains("max_passives must be 0")))


func test_threshold_mult_scales_and_rounds() -> void:
	var d := _auto().duplicate() as PathDef
	assert_eq(d.threshold(1), 3)
	d.threshold_mult = 1.5
	assert_eq(d.threshold(1), 5, "3 x 1.5 = 4.5 -> 5")
	assert_eq(d.threshold(2), 12)
	assert_eq(d.threshold(9), roundi((84 + PathDef.THRESHOLD_STEP) * 1.5))
	assert_eq(typeof(d.threshold(1)), TYPE_INT)


# --- Ranks ----------------------------------------------------------------------------------

func test_the_pistol_ranks_one_to_six_on_the_deep_curve() -> void:
	var def := WeaponDB.get_weapon(&"pistol")
	var dmg: Array = []
	var mech: Array = []
	for r in range(1, 7):
		var w := Weapon.new(def, r, WeaponCurve.DEEP)
		dmg.append(float(w.value(&"damage")))
		mech.append(w.traits.map(func(t: WeaponTrait) -> String: return String(t.id)))
	assert_eq(dmg, [1.0, 1.0, 1.5, 1.5, 2.0, 2.0])
	assert_eq(mech[0], [])
	assert_eq(mech[1], ["heavy_round"])
	assert_eq(mech[3], ["heavy_round", "seeker"])
	assert_eq(mech[5], ["heavy_round", "seeker", "chain"], "A at 2, B at 4, C at 6, all level 1")
	for t: WeaponTrait in Weapon.new(def, 6, WeaponCurve.DEEP).traits:
		assert_eq(t.level, 1)


func test_nova_has_three_deep_mechanics_and_classic_nova_is_unchanged() -> void:
	var nova := WeaponDB.get_weapon(&"nova")
	assert_eq(nova.mechanics, [&"shove", &"dash_nova", &"shockwave"] as Array[StringName])
	assert_eq(nova.problems(), [] as Array[String])
	assert_eq(Weapon.new(nova, 6, WeaponCurve.DEEP).traits.map(func(t: WeaponTrait) -> StringName: return t.id),
			[&"shove", &"dash_nova", &"shockwave"])
	assert_eq(Weapon.new(nova, 3).traits.map(func(t: WeaponTrait) -> StringName: return t.id),
			[&"shove", &"dash_nova"], "the classic curve never reads mechanics")


func test_card_lines_use_digits_on_deep_and_roman_on_classic() -> void:
	var pistol := WeaponDB.get_weapon(&"pistol")
	assert_eq(PickOffer.card_line(pistol, 2, true), "Pistol II: every fifth shot is heavy.  (I -> II)")
	var deep := PickOffer.card_line(pistol, 5, true, true)
	assert_string_starts_with(deep, "Pistol 4 -> 5")
	assert_string_starts_with(PickOffer.card_line(pistol, 4, true, true), "Pistol 3 -> 4: ")
	assert_string_contains(PickOffer.card_line(pistol, 6, true, true), "chain")
	assert_eq(PickOffer.card_line(pistol, 1, false, true), "Pistol: the gun you started with.  (new)")


func test_no_upgrade_card_at_six() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"pistol", 5)
	var c := PickOffer.candidate(lo, _auto(), &"pistol")
	assert_eq([c.kind, c.rank], [&"upgrade", 6])
	lo.set_weapon(&"pistol", 6)
	assert_eq(PickOffer.candidate(lo, _auto(), &"pistol"), {})
	lo.set_weapon(&"pistol", 9)
	assert_eq(lo.rank_of(&"pistol"), 6, "capped at rank_cap")


# --- Shared slots ---------------------------------------------------------------------------

func test_nova_takes_a_weapon_slot_and_a_fourth_is_never_offered() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.give(&"shotgun")
	assert_false(PickOffer.candidate(lo, _auto(), &"nova").is_empty(), "a free slot: nova can join")
	lo.give(&"nova")
	assert_eq(lo.weapon_count(), 3)
	assert_eq(lo.weapons().map(func(w: Weapon) -> StringName: return w.def.id), [&"pistol", &"shotgun", &"nova"])
	for id: StringName in [&"laser", &"launcher", &"well", &"orbit"]:
		assert_eq(PickOffer.candidate(lo, _auto(), id), {}, "%s: no 4th weapon" % id)
	assert_false(PickOffer.candidate(lo, _auto(), &"shotgun").is_empty(), "held ones still rank up")


func test_a_give_with_three_held_replaces_the_weakest_non_active_and_frees_its_node() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"shotgun", 3)
	lo.set_weapon(&"nova", 2)
	assert_not_null(lo.passive_node(&"nova"))
	lo.give(&"laser")   # F2 / a give: nova (rank 2) is the weakest non-active
	assert_eq(lo.summary(), "pistol:1,shotgun:3,laser:1")
	assert_null(lo.passive_node(&"nova"), "the replaced nova's node is freed")
	await wait_physics_frames(1)
	assert_eq(get_tree().get_nodes_in_group(&"player").size(), 1)
	assert_false(player.has_node(^"Weapon_nova"))
	lo.set_weapon(&"well", 1)   # ties at rank 1: the last in weapons() order (laser) goes
	assert_eq(lo.summary(), "pistol:1,shotgun:3,well:1")
	assert_eq(lo.current().def.id, &"pistol", "the active slot never goes")


func test_the_active_slot_survives_when_the_victim_sits_before_it() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"shotgun", 1)
	lo.set_weapon(&"laser", 3)
	lo.select(&"laser")
	lo.set_weapon(&"pistol", 4)
	lo.give(&"launcher")   # shotgun (rank 1, before the active laser) goes
	assert_eq(lo.summary(), "pistol:4,laser:3,launcher:1")
	assert_eq(lo.current().def.id, &"laser")


func test_other_paths_never_share_slots() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(PathDB.get_def(&"arsenal"))
	assert_false(lo.shared_slots)
	lo.apply_path(null)
	assert_false(lo.shared_slots)
	lo.set_weapon(&"shotgun", 1)
	lo.set_weapon(&"laser", 1)
	lo.set_weapon(&"nova", 1)
	assert_eq(lo.summary(), "pistol:1,shotgun:1,laser:1,nova:1", "no path: passives ride beside 3 aimed slots")


# --- The meter ------------------------------------------------------------------------------

func test_max_picks_zero_never_stops_and_the_taste_still_stops_after_one() -> void:
	var m := LevelMeter.new()
	m.def = _auto()
	var full := [0]
	m.on_full = func() -> void: full[0] += 1
	m.add(100000)
	assert_gt(m.level, 50, "no level cap")
	assert_false(m.stopped)
	assert_eq(full[0], 0, "no stop line")
	var t := LevelMeter.new()
	t.def = _auto()
	t.tryout = true
	t.add(100)
	assert_eq(t.level, 2, "S7's taste: one level")
	assert_true(t.stopped)


# --- Fillers --------------------------------------------------------------------------------

func test_fillers_only_when_nothing_else_and_boost_stacks_into_damage() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"pistol", 5)
	var o := _offer(lo, [&"pistol", &"shotgun"] as Array[StringName])
	assert_false(PickOffer.HP in o.ids() or PickOffer.BOOST in o.ids(), "no filler pads an offer with cards")
	assert_eq(o.cards.size(), 2)
	lo.set_weapon(&"pistol", 6)
	o = _offer(lo, [&"pistol"] as Array[StringName])
	assert_eq(o.ids(), [PickOffer.HP, PickOffer.BOOST] as Array[StringName])
	var before := float(lo.current().value(&"damage"))
	assert_true(lo.current().mods.is_empty())
	lo.add_boost()
	lo.add_boost()
	assert_almost_eq(float(lo.current().value(&"damage")), before * 1.10, 0.0001, "two stacks: +10%")
	lo.set_weapon(&"nova", 1)
	assert_almost_eq(float(lo.held(&"nova").value(&"damage")), 3.0 * 1.10, 0.0001, "a new weapon gets the boost")
	assert_almost_eq(float(lo.passive_node(&"nova").damage), 3.0 * 1.10, 0.0001)
	lo.clear()
	assert_eq(lo.boost, 0)
	assert_true(lo.current().mods.is_empty(), "clear resets the boost")
	lo.add_boost()
	lo.apply_path(_auto())
	assert_eq(lo.boost, 0, "apply_path resets it too")
	assert_true(lo.current().mods.is_empty())
	await wait_physics_frames(1)   # the cleared nova's node goes (no orphan)


## M50.4a review: the well keeps its teeth in `dps`, not `damage`: the boost must reach it
## without a rank-up.
func test_boost_reaches_the_well_without_a_rank_up() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"well", 3)
	var node: Node = lo.passive_node(&"well")
	var base := float(node.get(&"dps"))
	assert_almost_eq(base, float(lo.held(&"well").value(&"damage")), 0.0001)
	assert_gt(base, 0.0)
	lo.add_boost()
	assert_eq(lo.passive_node(&"well"), node, "never re-attached")
	assert_almost_eq(float(node.get(&"dps")), base * 1.05, 0.0001, "one stack: +5% bite")
	lo.clear()
	await wait_physics_frames(1)


func test_the_boost_filler_is_auto_only() -> void:
	await _arena()
	var lo := _loadout()
	var d := PathDB.get_def(&"arsenal")
	lo.apply_path(d)
	var rng := RandomNumberGenerator.new()
	var o := PickOffer.draw(lo, d, [] as Array[StringName], &"", rng, Taste.new())
	assert_eq(o.ids(), [PickOffer.HP] as Array[StringName], "other paths keep the one +1 HP filler")


func test_value_is_byte_identical_with_empty_mods() -> void:
	for id: StringName in WeaponDB.ids():
		var def := WeaponDB.get_weapon(id)
		for r in range(1, 4):
			var w := Weapon.new(def, r)
			for f: StringName in [&"damage", &"cooldown", &"pellets", &"speed", &"blast_radius", &"pierce"]:
				var v: Variant = w.value(f)
				var old: Variant = def.value(f, r)
				assert_eq(typeof(v), typeof(old), "%s %d %s type" % [id, r, f])
				assert_eq(v, old)


func test_nova_reconfigure_keeps_its_clock() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"nova", 1)
	var node: Node = lo.passive_node(&"nova")
	await wait_physics_frames(30)
	var left := float(node.get(&"_left"))
	assert_lt(left, 3.0)
	lo.add_boost()
	assert_eq(lo.passive_node(&"nova"), node, "never re-attached")
	assert_almost_eq(float(node.get(&"_left")), left, 0.0001, "the next blast does not move")


# --- Shockwave ------------------------------------------------------------------------------

func test_shockwave_hits_each_enemy_once_outside_the_blast() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.fire_mode = &"manual_one"   # the pistol holds its fire: only the nova hits
	lo.set_weapon(&"nova", 6)
	var node: Node = lo.passive_node(&"nova")
	assert_true(bool(node.get(&"shockwave")))
	var near := await _frozen_chaser(OPEN + Vector2(1, 0))
	var mid := await _frozen_chaser(OPEN + Vector2(0, 3))
	var far := await _frozen_chaser(OPEN + Vector2(-6, 0))
	var hp := [near.health.hp(), mid.health.hp(), far.health.hp()]
	node.call(&"go_off")
	assert_eq(get_tree().get_nodes_in_group(ShockwaveRing.GROUP).size(), 1)
	await wait_physics_frames(40)
	var dmg := float(node.get(&"damage"))
	assert_almost_eq(near.health.hp(), hp[0] - dmg, 0.001, "inside the blast: the blast only")
	assert_almost_eq(mid.health.hp(), hp[1] - dmg * 0.5, 0.001, "the ring: once, half damage")
	assert_almost_eq(far.health.hp(), hp[2], 0.001, "past 4 T: untouched")
	assert_eq(get_tree().get_nodes_in_group(ShockwaveRing.GROUP).size(), 0, "the ring is gone after 0.4 s")


func test_shockwave_rings_cap_at_four() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"nova", 6)
	var node: Node = lo.passive_node(&"nova")
	for i in 6:
		node.call(&"go_off")
	assert_eq(get_tree().get_nodes_in_group(ShockwaveRing.GROUP).size(), ShockwaveRing.MAX_ALIVE)
	assert_eq(int(node.get(&"rings")), 4)
	await wait_physics_frames(40)


func test_nova_below_six_sends_no_ring() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"nova", 5)
	lo.passive_node(&"nova").call(&"go_off")
	assert_eq(get_tree().get_nodes_in_group(ShockwaveRing.GROUP).size(), 0)
	await wait_physics_frames(20)


# --- HUD and rail ---------------------------------------------------------------------------

func test_the_raw_widget_rows_star_the_top_rank_and_show_the_item_slots() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"pistol", 6)
	lo.set_weapon(&"nova", 2)
	var m := LevelMeter.new()
	m.def = _auto()
	var w := LevelWidget.new()
	w.meter = m
	w.loadout = lo
	add_child_autofree(w)
	await wait_process_frames(1)
	assert_eq(w.text(), "LV 1\nPistol 6*  Nova 2\nPassives  + +")
	assert_lte(w.custom_minimum_size.y, 60.0, "the band's height (Hud's path band)")
	assert_lte(w.custom_minimum_size.x, LevelWidget.MAX_W)


func test_the_rail_reads_every_weapon_in_the_shared_slots() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"nova", 3)
	var fake := _FakeRunner.new(lo)
	var d: Dictionary = RailState._items(fake, lo, _auto())
	fake.free()
	assert_eq((d.weapons as Array).map(func(x: Dictionary) -> String: return "%s:%d" % [x.title, x.rank]),
			["Pistol:1", "Nova:3"])
	assert_eq([d.slots, d.passive_slots, d.cap, (d.passives as Array).size()], [3, 2, 6, 0])


class _FakeRunner:
	extends Node
	var lo: Loadout

	func _init(p_lo: Loadout) -> void:
		lo = p_lo

	func meter() -> RefCounted:
		return null



# --- Gems (a bug the uncapped meter reached) --------------------------------------------------

func test_the_gem_cap_merges_after_a_gem_was_taken() -> void:
	await _arena()
	var gems: Node = load("res://paths/auto/gems.gd").new()
	add_child_autofree(gems)
	var keep := Tuning.hard_max_pickups
	Tuning.hard_max_pickups = 4
	for i in 4:
		gems.call(&"drop", (OPEN + Vector2(-12, -2 + i)) * T, 1)
	await wait_physics_frames(1)
	var first: Node = (gems.get(&"_mine") as Array)[0]
	first.queue_free()   # taken: freed, still in the gem list
	await wait_physics_frames(1)
	for i in 2:
		gems.call(&"drop", (OPEN + Vector2(-12, 3)) * T, 1)
	await wait_physics_frames(1)
	var total := 0
	for p in get_tree().get_nodes_in_group(Pickup.GEM_GROUP):
		if not p.is_queued_for_deletion():
			total += (p as Pickup).value
	Tuning.hard_max_pickups = keep
	assert_eq(total, 5, "3 left + 2 new: no worth lost (and no script error: GUT fails on one)")
	assert_eq(get_tree().get_nodes_in_group(Pickup.GEM_GROUP).filter(func(p: Node) -> bool:
			return not p.is_queued_for_deletion()).size(), 4, "the oldest merged, the new gem spawned")
