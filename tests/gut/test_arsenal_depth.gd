extends GutTest
## M50.1a (Arsenal depth design, .check/arsenal_depth/design.md): booster packs every 6 kills
## (PackMeter, BoosterPack on RunState.pack_rng, exactly 6 draws a pack), the hand of 2, rare
## cards, replace / Back, the full-hand give (G4), the deep rank curve (WeaponCurve: damage at
## odd ranks, mechanics at even ranks, no top), trait levels, chain / shrapnel / overcharge,
## the caps, CARD_RARE, the hand's rank badge and dots, and the bot's pack rule.

const CHASER := preload("res://entities/enemy_chaser.tscn")
const PackMeter := preload("res://paths/arsenal/pack_meter.gd")
const HandWidget := preload("res://paths/arsenal/hand_widget.gd")
const BotRuns := preload("res://tools/bot_runs.gd")
const ChainMod := preload("res://weapons/traits/chain_mod.gd")
const Caltrop := preload("res://weapons/traits/caltrop.gd")
const BurnLineZone := preload("res://weapons/traits/burn_line_zone.gd")
const OverchargeBeam := preload("res://weapons/traits/overcharge_beam.gd")
const Grids := preload("res://systems/skins/art/grids.gd")
const T := 48.0
const OPEN := Vector2(34, 20)

var game: Main
var player: CharacterBody2D


func after_each() -> void:
	RunState.invincible = false
	RunState.set_pause(PickPanel.PAUSE, false)
	CampaignDB.active = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null


func _arsenal() -> PathDef:
	return PathDB.get_def(&"arsenal")


## The legacy arena on Arsenal through F2 (outside a session every basic is on).
func _arena() -> PathRunner:
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
	# M50.6: packs stack until asked. These tests play like the bot (a standing ask: each pack
	# opens on the first free tick); the stack's own tests are in test_pack_stack.gd.
	player.input.open_pack_pressed = true
	await wait_physics_frames(1)
	player.global_position = OPEN * T
	player.velocity = Vector2.ZERO
	RunState.invincible = true
	assert_true(game.debug.switch_path(&"arsenal"))
	game.pick_panel.input_delay = 0.0
	await wait_physics_frames(1)
	return game.path_runner


func _loadout() -> Loadout:
	return Component.find(player, Loadout) as Loadout


## A deep-curve loadout with no scene (pure draws).
func _deep(ids: Array, ranks: Array = []) -> Loadout:
	var lo := Loadout.new()
	lo.apply_path(_arsenal())
	for i in ids.size():
		lo.set_weapon(ids[i], ranks[i] if i < ranks.size() else 1)
	autofree(lo)
	return lo


func _frozen_chaser(tile: Vector2, hp := 100.0) -> Node2D:
	var e := RunState.spawn(CHASER, tile * T) as Node2D
	await wait_physics_frames(2)
	e.set_physics_process(false)
	e.mover.wish = Vector2.ZERO
	e.velocity = Vector2.ZERO
	e.health.base_max_hp = hp
	return e


func _kill(runner: PathRunner, n: int, faction := &"player") -> void:
	for i in n:
		runner._on_enemy_killed(null, DamageInfo.make(1.0, &"projectile", faction))


func _rng(s := 7) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


# --- 1. The pack meter -----------------------------------------------------------------------

func test_the_pack_meter_deals_every_six_kills_with_no_cap() -> void:
	var m := PackMeter.new()
	m.def = _arsenal()
	var dealt := [0]
	m.on_card = func() -> void: dealt[0] += 1
	m.add(5)
	assert_eq(m.cards, 0)
	assert_eq(m.kills_left(), 1)
	m.add(1)
	assert_eq(m.cards, 1, "a pack at 6 kills")
	assert_almost_eq(m.progress(), 0.0, 0.0001)
	m.add(3)
	assert_almost_eq(m.progress(), 0.5, 0.0001)
	m.add(600)
	assert_eq(m.cards, 101, "no session cap")
	assert_eq(dealt[0], 101)
	assert_false(m.stopped)


func test_a_tryout_deals_two_packs_then_stops_quietly() -> void:
	var m := PackMeter.new()
	m.def = _arsenal()
	m.tryout = true
	m.add(11)
	assert_eq(m.cards, 1)
	m.add(100)
	assert_eq(m.cards, 2, "pack_taste 2")
	assert_true(m.stopped)
	assert_eq(m.next_need(), -1)
	assert_eq(m.progress(), 1.0)


func test_packs_need_player_kills_and_stack_until_asked() -> void:
	var r := await _arena()
	player.input.open_pack_pressed = false   # M50.6: the player's hands are off the key
	r.announce(&"shotgun")   # M50.2a: a pool of two, so each pack is a choice (no toast)
	_kill(r, 5, &"enemy")
	assert_eq(r.packs(), 0, "a bomber's own fuse kill does not count")
	_kill(r, 12)
	assert_eq(r.packs(), 2)
	assert_eq(r.pending_picks(), 2, "the packs stack")
	await wait_physics_frames(30)
	assert_false(game.pick_panel.is_open(), "M50.6: a pack never opens by itself")
	assert_true(r.open_pack())
	await wait_physics_frames(2)
	assert_true(game.pick_panel.is_open(), "asked: it opens on the next free tick")
	game.pick_panel.choose(0)
	assert_eq(r.pending_picks(), 1)
	await wait_physics_frames(150)
	assert_false(game.pick_panel.is_open(), "the next one waits to be asked too (no chain, no PACK_GAP timer)")


# --- 2. The pack draw ------------------------------------------------------------------------

func test_a_pack_draws_exactly_six_numbers_whatever_the_hand() -> void:
	var pools := [[&"pistol"], [&"pistol", &"shotgun"], [&"pistol", &"shotgun", &"laser"]]
	var hands := [[&"pistol"], [&"pistol", &"shotgun"], [&"shotgun", &"laser"]]
	for pool: Array in pools:
		for hand: Array in hands:
			var lo := _deep(hand)
			var rng := _rng(11)
			var twin := _rng(11)
			var typed: Array[StringName] = []
			typed.assign(pool)
			BoosterPack.draw(lo, _arsenal(), typed, {}, rng, Taste.new())
			for i in BoosterPack.DRAWS:
				twin.randf()
			assert_eq(rng.state, twin.state, "6 draws (pool %s, hand %s)" % [pool, hand])


func test_same_seed_same_packs() -> void:
	var a: Array[String] = []
	var b: Array[String] = []
	for out: Array[String] in [a, b]:
		var lo := _deep([&"pistol", &"shotgun"])
		var rng := _rng(3)
		var pool: Array[StringName] = [&"pistol", &"shotgun", &"laser"]
		for i in 10:
			var o := BoosterPack.draw(lo, _arsenal(), pool, {}, rng, Taste.new())
			out.append(str(o.cards.map(func(c: Dictionary) -> String: return "%s:%s" % [c.id, c.rarity])))
	assert_eq(a, b)


func test_g1_a_held_card_first_and_g2_never_shows_an_id_twice() -> void:
	var lo := _deep([&"pistol", &"shotgun"])
	lo.held(&"shotgun").shots = 40
	var pool: Array[StringName] = [&"pistol", &"shotgun", &"laser"]
	for s in 20:
		var o := BoosterPack.draw(lo, _arsenal(), pool, {}, _rng(s), Taste.new())
		assert_eq(o.cards[0].id, &"shotgun", "G1: the most-fired held card")
		var keys := {}
		for c: Dictionary in o.cards:
			keys["%s:%s" % [c.id, c.rarity]] = true
		assert_eq(keys.size(), o.cards.size(), "G2: no (id, rarity) twice")
		assert_eq(o.cards.size(), 3)
	var one := _deep([&"pistol"])
	var only: Array[StringName] = [&"pistol"]
	var o := BoosterPack.draw(one, _arsenal(), only, {}, _rng(5), Taste.new())
	assert_eq(o.ids(), [&"pistol"] as Array[StringName], "M50.2a G2': a one-weapon pool shows 1 card")
	var two := _deep([&"pistol", &"shotgun"])
	var both: Array[StringName] = [&"pistol", &"shotgun"]
	assert_eq(BoosterPack.draw(two, _arsenal(), both, {}, _rng(5), Taste.new()).cards.size(), 2,
			"M50.2a G2': a pool of two on a full hand: 2 cards, never a repeat")


## M50.2a (G2'): a card slot with no unshown id left adds no card. M50.6: and nothing else
## happens there (the old rare roll that turned a shown card rare in place is gone: a card's
## rarity is its weapon's and every card is +1).
func test_an_empty_slot_adds_no_card_and_every_card_is_plus_one() -> void:
	var lo := _deep([&"pistol", &"shotgun"], [5, 3])
	var o := PickOffer.new()
	o.pack = true
	o.cards.append(BoosterPack.card(lo, &"pistol"))
	o.cards.append(BoosterPack.card(lo, &"shotgun"))
	var none: Array = []
	var no_epics: Array[StringName] = []
	BoosterPack._take(o, lo, none, none, 0.0, 0.0, 0.99, no_epics, null)
	assert_eq(o.cards.map(func(c: Dictionary) -> String: return "%s:%s:%d" % [c.id, c.rarity, c.rank]),
			["pistol:common:6", "shotgun:common:4"], "no card added, none changed")
	# Through draw(): a 2-weapon pool on a full hand never repeats an id, whatever the seed.
	var pool: Array[StringName] = [&"pistol", &"shotgun"]
	for s in 200:
		var d := BoosterPack.draw(lo, _arsenal(), pool, {}, _rng(s), Taste.new(), true)
		assert_eq(d.cards.size(), 2)
		assert_ne(d.cards[0].id, d.cards[1].id, "never a repeated id (seed %d)" % s)
		for c: Dictionary in d.cards:
			assert_eq([c.rarity, int(c.rank) - int(c.from)], [&"common", 1], "common weapons, +1 (seed %d)" % s)


func test_pool_of_one_is_one_card() -> void:
	var lo := _deep([&"pistol"], [4])
	var only: Array[StringName] = [&"pistol"]
	for s in 200:
		var o := BoosterPack.draw(lo, _arsenal(), only, {}, _rng(s), Taste.new())
		assert_eq(o.ids(), [&"pistol"] as Array[StringName], "1 card (seed %d)" % s)
		assert_eq([o.cards[0].rarity, int(o.cards[0].rank)], [&"common", 5], "M50.6: the pistol is common, +1")


## M50.6: the old per-card rare roll (rare_chance 0.15, +2 ranks) is gone; the numbers are the
## epic chance on the path and two weights in Tuning.
func test_the_pack_numbers_live_on_the_path_and_in_tuning() -> void:
	assert_almost_eq(_arsenal().epic_chance, 0.05, 0.0001)
	assert_false("rare_chance" in _arsenal(), "no rarity roll per card any more")
	assert_almost_eq(Tuning.pack_rare_weight, 0.5, 0.0001)
	assert_almost_eq(Tuning.pack_held_weight, 2.0, 0.0001)


## M50.2a (D3): a 1-card pack has no choice: it applies at once, with no pick pause and no
## panel, and a short toast shows it. It still counts as a pack (offers, picks, `picked n`).
func test_one_card_pack_is_a_toast_not_a_pause() -> void:
	var r := await _arena()
	var lo := _loadout()
	var offered := [0]
	var on_offer := func(_o: RefCounted) -> void: offered[0] += 1
	EventBus.pick_offered.connect(on_offer)
	var from_rank := lo.rank_of(&"pistol")
	_kill(r, 6)
	assert_eq(r.packs(), 1)
	r._open_offer()
	EventBus.pick_offered.disconnect(on_offer)
	var panel := game.pick_panel
	assert_false(panel.is_open(), "no panel")
	assert_false(RunState.is_paused_for(PickPanel.PAUSE), "no pick pause")
	assert_true(panel.toasting(), "the toast shows")
	assert_eq(offered[0], 1, "pick_offered: it is a pack")
	assert_eq(r.offers.size(), 1)
	assert_eq([r.picks, r.picks_on_path, r.pending_picks()], [1, 1, 0], "a pick (`picked n` counts it)")
	assert_eq([r.packs_toast, r.packs_short], [1, 1])
	var c: Dictionary = r.offers[0].cards[0]
	assert_eq(lo.rank_of(&"pistol"), int(c.rank), "the card applied")
	assert_gt(lo.rank_of(&"pistol"), from_rank)
	assert_string_contains(panel._toast.text, "Pack: Pistol +")
	assert_eq(PickPanel.toast_text({"id": &"laser", "kind": &"upgrade", "rank": 6, "from": 5, "rarity": &"rare"}),
			"Pack: Laser +1  RARE", "M50.6: the tier, no bonus")
	assert_eq(PickPanel.toast_text({"id": &"laser", "kind": &"new", "rank": 1, "rarity": &"common"}),
			"Pack: Laser 1 joins")
	panel._process(PickPanel.TOAST_TIME + 0.05)
	assert_false(panel.toasting(), "it fades out")
	# A pool of two on a hand with room is a choice again: the panel opens.
	r.announce(&"shotgun")
	r.want_pick()
	r._open_offer()
	assert_true(panel.is_open(), "2 cards: the panel")
	assert_true(RunState.is_paused_for(PickPanel.PAUSE))
	assert_eq(r.packs_toast, 1)
	panel.choose(0)


func test_g3_a_new_weapon_with_room_and_g4_a_waiting_give() -> void:
	var lo := _deep([&"pistol"])
	var pool: Array[StringName] = [&"pistol", &"shotgun", &"laser"]
	for s in 10:
		var o := BoosterPack.draw(lo, _arsenal(), pool, {}, _rng(s), Taste.new())
		assert_eq(o.cards[1].kind, &"new", "G3: card 2 is new while the hand has room")
	var full := _deep([&"pistol", &"shotgun"])
	var o := BoosterPack.draw(full, _arsenal(), pool, {"id": &"laser", "rank": 3}, _rng(1), Taste.new())
	assert_eq([o.cards[1].id, o.cards[1].kind, o.cards[1].rarity, o.cards[1].rank], [&"laser", &"new", &"rare", 3])
	assert_false(o.ids().slice(2).has(&"laser"), "not twice")


func test_card_lines_name_breakpoints_and_mechanics() -> void:
	var lo := _deep([&"pistol"], [6])
	var c := BoosterPack.card(lo, &"pistol")
	assert_eq(c.title, "Pistol 6 -> 7")
	assert_eq(c.gain, "one-shots chasers and lancers, tank in 4")
	assert_eq(BoosterPack.tags(c), "COMMON", "M50.6: the tier, never a bonus")
	assert_eq(int(c.rank) - int(c.from), 1)
	lo.set_weapon(&"pistol", 5)
	assert_string_contains(BoosterPack.card(lo, &"pistol").gain, "chain: a kill hops to the next enemy (3 hops)")
	var n := BoosterPack.card(lo, &"laser")
	assert_eq([n.kind, n.rank, n.rarity, BoosterPack.tags(n)], [&"new", 1, &"rare", "NEW  RARE"],
			"M50.6: a rare weapon's card is rare, and still joins at rank 1")
	assert_string_contains(n.gain, "goes through things")


# --- 3. Ranks and the curve ------------------------------------------------------------------

func test_the_damage_table_is_exact() -> void:
	var want := {1: 1.0, 2: 1.0, 3: 1.5, 4: 1.5, 5: 2.0, 6: 2.0, 7: 3.0, 8: 3.0, 9: 4.0, 10: 4.0,
			11: 6.0, 12: 6.0, 13: 7.0, 14: 7.0, 15: 8.0}
	var pistol := WeaponDB.get_weapon(&"pistol")
	var laser := WeaponDB.get_weapon(&"laser")
	for r: int in want:
		assert_eq(WeaponCurve.mult(r), float(want[r]), "x at rank %d" % r)
		assert_eq(float(Weapon.new(pistol, r, &"deep").value(&"damage")), float(want[r]), "pistol %d" % r)
		assert_eq(float(Weapon.new(laser, r, &"deep").value(&"damage")), 2.0 * float(want[r]), "laser %d" % r)
	assert_eq(WeaponCurve.breakpoint_text(pistol, 6, 7), "one-shots chasers and lancers, tank in 4")
	assert_eq(WeaponCurve.breakpoint_text(pistol, 4, 5), "one-shots shooters and bombers, tank in 6")
	assert_eq(WeaponCurve.breakpoint_text(pistol, 10, 11), "tank in 2")


func test_levels_unlock_at_2_4_6_then_cycle_and_overflow() -> void:
	assert_eq(WeaponCurve.levels(1, 3), [0, 0, 0] as Array[int])
	assert_eq(WeaponCurve.levels(2, 3), [1, 0, 0] as Array[int])
	assert_eq(WeaponCurve.levels(4, 3), [1, 1, 0] as Array[int])
	assert_eq(WeaponCurve.levels(6, 3), [1, 1, 1] as Array[int])
	assert_eq(WeaponCurve.levels(8, 3), [2, 1, 1] as Array[int])
	assert_eq(WeaponCurve.levels(10, 3), [2, 2, 1] as Array[int])
	assert_eq(WeaponCurve.levels(12, 3), [2, 2, 2] as Array[int])
	assert_eq(WeaponCurve.levels(24, 3), [4, 4, 4] as Array[int], "9 strengthens: ranks 8-24")
	assert_eq(WeaponCurve.levels(26, 3), [5, 4, 4] as Array[int], "overflow is still a strengthen")
	assert_eq(WeaponCurve.levels(30, 3), [5, 5, 5] as Array[int])
	assert_eq(WeaponCurve.levels(5, 4, true), [1, 1, 1, 1] as Array[int], "fused: all from rank 1")
	assert_eq(WeaponCurve.levels(7, 4, true), [2, 1, 1, 1] as Array[int])
	assert_eq(WeaponCurve.levels(9, 4, true), [2, 2, 1, 1] as Array[int])
	for r in range(1, 31):
		var lv := WeaponCurve.levels(r, 3)
		var total := 0
		for l in lv:
			total += l
		assert_eq(total, mini(r / 2, 3) + maxi(0, r / 2 - 3), "one mechanic step per even rank (%d)" % r)


func test_a_skipped_maxed_mechanic_and_a_two_mechanic_weapon() -> void:
	assert_eq(WeaponCurve.levels(6, 2), [1, 1] as Array[int], "no C: rank 6 does nothing")
	assert_eq(WeaponCurve.levels(8, 2), [2, 1] as Array[int])
	assert_eq(WeaponCurve.levels(18, 2), [4, 4] as Array[int])
	assert_eq(WeaponCurve.levels(20, 2), [5, 4] as Array[int])


func test_the_deep_curve_never_reads_ranks() -> void:
	var shotgun := WeaponDB.get_weapon(&"shotgun")
	assert_eq(float(Weapon.new(shotgun, 3, &"deep").value(&"spread_deg")), 28.0, "classic rank 3 is 18, deep 3 is 28")
	assert_eq(float(Weapon.new(shotgun, 4, &"deep").value(&"spread_deg")), 18.0, "point blank's tighter cone at 4")
	assert_eq(float(Weapon.new(shotgun, 20, &"deep").value(&"spread_deg")), 18.0)
	assert_eq(float(Weapon.new(shotgun, 3).value(&"spread_deg")), 18.0, "classic untouched")
	var w := Weapon.new(shotgun, 6, &"deep")
	assert_eq(w.traits.map(func(t: WeaponTrait) -> StringName: return t.id),
			[&"knockback_cone", &"point_blank", &"shrapnel"])
	var big := Weapon.new(WeaponDB.get_weapon(&"laser"), 30, &"deep")
	assert_eq(big.traits.size(), 3, "rank 30 builds")
	assert_eq(big.trait_level(&"burn_line"), 5)
	assert_eq(big.label(), "Laser 30")


func test_loadout_ranks_rare_and_no_cap_while_classic_clamps_at_3() -> void:
	var lo := _deep([&"pistol"])
	assert_eq(lo.rank_cap, 0)
	assert_true(lo.upgrade(&"pistol", 2))
	assert_eq(lo.rank_of(&"pistol"), 3, "upgrade(by) adds what it is asked (M50.6: a pack card asks 1)")
	lo.set_weapon(&"pistol", 30)
	assert_true(lo.upgrade(&"pistol"))
	assert_eq(lo.rank_of(&"pistol"), 31, "no top")
	lo.give(&"laser", 3)
	assert_eq(lo.rank_of(&"laser"), 3, "a give at rank 3 joins at 3")
	assert_true(lo.hand_full())
	var classic := Loadout.new()
	autofree(classic)
	classic.apply_path(null)   # M50.4a: Auto is deep now; no path keeps the classic curve
	assert_eq(classic.rank_cap, Loadout.MAX_RANK)
	classic.set_weapon(&"pistol", 30)
	assert_eq(classic.rank_of(&"pistol"), 3, "classic stops at 3")
	assert_false(classic.upgrade(&"pistol", 2))
	assert_eq(classic.current().curve, &"classic")


func test_replace_keeps_the_slot_and_the_active_card() -> void:
	var lo := _deep([&"pistol", &"shotgun"], [7, 5])
	lo.active = 1
	assert_true(lo.replace_slot(1, &"laser", 3))
	assert_eq(lo.summary(), "pistol:7,laser:3")
	assert_eq(lo.active, 1, "the new card is active where the old one was")
	assert_false(lo.drawn(), "a replace is not a switch")
	assert_eq(lo.current().curve, &"deep")


func test_each_trait_steps_start_at_todays_constant() -> void:
	var pairs := [[&"heavy_round", &"every", 5], [&"heavy_round", &"mult", 3.0],
			[&"seeker", &"turn", preload("res://weapons/traits/seeker_mod.gd").TURN_DEG],
			[&"seeker", &"range", preload("res://weapons/traits/seeker_mod.gd").RANGE / Tuning.TILE],
			[&"knockback_cone", &"knockback", preload("res://weapons/traits/knockback_cone.gd").KNOCKBACK],
			[&"point_blank", &"range", preload("res://weapons/traits/point_blank_mod.gd").RANGE / Tuning.TILE],
			[&"point_blank", &"mult", 2.0], [&"burn_line", &"life", BurnLineZone.LIFE],
			[&"ricochet", &"bounces", 1]]
	for p: Array in pairs:
		var t := WeaponTrait.make(p[0])
		assert_eq(t.level, 1)
		assert_almost_eq(float(t.step_value(p[1])), float(p[2]), 0.0001, "%s.%s level 1 = today" % [p[0], p[1]])
		assert_eq(t.steps().size(), 4, "%s has 4 levels" % p[0])
	var h := WeaponTrait.make(&"heavy_round", 4)
	assert_eq(int(h.step_value(&"every")), 2)
	h.level = 6
	assert_almost_eq(float(h.step_value(&"mult")), 3.6, 0.0001, "overflow +10% of the last step a level")
	assert_eq(WeaponTrait.make(&"seeker", 4).step_value(&"turn"), 180.0)
	assert_eq(WeaponTrait.make(&"ricochet", 4).step_value(&"bounces"), 3)
	assert_eq(WeaponTrait.make(&"chain", 4).step_value(&"hops"), 6)
	assert_eq(WeaponTrait.make(&"shrapnel", 4).step_value(&"life"), 5.0)
	assert_eq(WeaponTrait.make(&"overcharge", 4).step_value(&"every"), 2)


func test_the_roster_reads_enemy_db_and_the_tuning() -> void:
	var reading: Array[StringName] = EnemyDB.READING.duplicate()
	var bases: Array[StringName] = EnemyDB.BASES.duplicate()
	reading.sort()
	bases.sort()
	assert_eq(reading, bases, "READING holds the same ids as BASES")
	for id: StringName in EnemyDB.READING:
		assert_eq(WeaponCurve.roster_hp(id), float(Tuning.get("%s_hp" % id)), String(id))
		assert_gt(WeaponCurve.roster_hp(id), 0.0, String(id))


func test_weapon_data_is_valid() -> void:
	assert_eq(WeaponDB.problems(), [] as Array[String])
	assert_eq(PathDB.problems(), [] as Array[String])


# --- 4. Chain, shrapnel, overcharge, caps ----------------------------------------------------

func test_chain_keeps_the_shot_on_a_kill_and_hops_to_the_nearest() -> void:
	await _arena()
	var lo := _loadout()
	lo.set_weapon(&"pistol", 6)
	assert_true(lo.current().has_trait(&"chain"))
	var first := await _frozen_chaser(OPEN + Vector2(3, 0), 1.0)
	var near := await _frozen_chaser(OPEN + Vector2(5, -2), 100.0)   # (a wall row lies just below OPEN)
	var far := await _frozen_chaser(OPEN + Vector2(3, -4.5), 100.0)
	await wait_seconds(1.0)   # past any spawn grace
	var shots := get_tree().get_nodes_in_group(&"player_projectile").size()
	var fired := lo.shooter().fire(lo.current(), Vector2.RIGHT)
	assert_eq(fired.size(), 1)
	var mod: Node = null
	for m in (fired[0] as Node).call(&"mods"):
		if m.get_script() == ChainMod:
			mod = m
	assert_not_null(mod)
	var hops := 0
	for i in 30:
		if is_instance_valid(mod):
			hops = int(mod.get(&"hops"))
		if near.health.hp() < 100.0:
			break
		await wait_physics_frames(1)
	assert_eq(hops, 1, "one hop after the kill")
	assert_lt(near.health.hp(), 100.0, "the nearest one is hit next")
	assert_eq(far.health.hp(), 100.0)
	assert_lte(get_tree().get_nodes_in_group(&"player_projectile").size(), shots + 1, "no spawn")
	assert_false(is_instance_valid(first) and not first.is_queued_for_deletion(), "the first one died")


func test_chain_never_hops_off_a_corpse() -> void:
	# Review: an enemy killed by something else this frame still sits in the space; a shot
	# reaching it lands no damage, so it is not this shot's kill and must not hop.
	await _arena()
	var lo := _loadout()
	lo.set_weapon(&"pistol", 6)
	var corpse := await _frozen_chaser(OPEN + Vector2(3, 0), 1.0)
	var near := await _frozen_chaser(OPEN + Vector2(4, -1), 100.0)
	await wait_seconds(1.0)
	var fired := lo.shooter().fire(lo.current(), Vector2.RIGHT)
	assert_eq(fired.size(), 1)
	var shot := fired[0] as Node2D
	var mod: Node = null
	for m in shot.call(&"mods"):
		if m.get_script() == ChainMod:
			mod = m
	assert_not_null(mod)
	corpse.health.take(DamageInfo.make(1000.0, &"projectile", &"player"))
	assert_true(corpse.health.dead, "killed by something else")
	var keep: bool = shot.call(&"_hit_entity", corpse, corpse.global_position, Vector2.RIGHT, RID())
	assert_false(keep, "the shot is spent on the corpse")
	assert_eq(int(mod.get(&"hops")), 0, "no free hop")
	assert_eq(near.health.hp(), 100.0)


func test_chain_never_rides_a_blast_shot() -> void:
	var t := WeaponTrait.make(&"chain", 1, true)
	var p := Node2D.new()
	p.set_script(load("res://entities/projectile.gd"))
	autofree(p)
	p.set(&"blast_radius", 50.0)
	t.spawned(null, p)
	assert_eq((p.call(&"mods") as Array).size(), 0)


func test_caltrops_burn_lines_and_beams_are_capped() -> void:
	await _arena()
	for i in 40:
		Caltrop.drop(OPEN * T + Vector2(i * 3, 200), 10.0, &"weapon:shotgun")
		await wait_physics_frames(1)
	var alive := get_tree().get_nodes_in_group(Caltrop.GROUP).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	assert_lte(alive.size(), Caltrop.CAP, "caltrops <= 30")
	assert_gte(alive.size(), Caltrop.CAP - 1)
	for i in 20:
		var z := BurnLineZone.new()
		z.points = PackedVector2Array([OPEN * T, OPEN * T + Vector2(100, 0)])
		z.life = 10.0
		BurnLineZone.make_room(BurnLineZone.DEEP_CAP)
		RunState.world.add_child(z)
	var zones := get_tree().get_nodes_in_group(BurnLineZone.GROUP).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	assert_lte(zones.size(), BurnLineZone.DEEP_CAP, "burn lines <= 12 on the deep curve")
	assert_not_null(OverchargeBeam.fire(OPEN * T, Vector2.RIGHT, 1.0, 1.0, &""))
	await wait_physics_frames(1)
	assert_null(OverchargeBeam.fire(OPEN * T, Vector2.RIGHT, 1.0, 1.0, &""), "one beam at a time")


func test_shrapnel_drops_a_caltrop_for_a_pellet_that_hits_nothing() -> void:
	await _arena()
	var lo := _loadout()
	lo.set_weapon(&"shotgun", 6)
	lo.select(&"shotgun")
	var before := get_tree().get_nodes_in_group(Caltrop.GROUP).size()
	lo.shooter().fire(lo.current(), Vector2.RIGHT)
	await wait_physics_frames(40)
	assert_eq(get_tree().get_nodes_in_group(Caltrop.GROUP).size() - before, 5, "5 missed pellets, 5 caltrops")


func test_overcharge_throws_a_beam_on_its_shot() -> void:
	await _arena()
	var lo := _loadout()
	lo.set_weapon(&"laser", 6)
	lo.select(&"laser")
	var e := await _frozen_chaser(OPEN + Vector2(-6, 0), 100.0)
	var w := lo.current()
	w.shots = 3   # the 4th shot
	lo.shooter().fire(w, Vector2.LEFT)
	await wait_physics_frames(2)
	assert_eq(get_tree().get_nodes_in_group(OverchargeBeam.GROUP).size(), 1)
	await wait_physics_frames(30)
	assert_lt(e.health.hp(), 100.0)


# --- 5. The panel: replace, Back, keys --------------------------------------------------------

func test_a_full_hand_new_card_replaces_or_goes_back_to_the_same_pack() -> void:
	var r := await _arena()
	var lo := _loadout()
	lo.give(&"shotgun")
	r.announce(&"shotgun")
	r.announce(&"laser")
	var panel := game.pick_panel
	var picked := [0]
	var count := func(_o: PickOffer, _i: int) -> void: picked[0] += 1
	panel.picked.connect(count)
	r.want_pick()
	r._open_offer()
	var offer := panel.offer
	var at := -1
	for i in offer.cards.size():
		if offer.cards[i].kind == &"new":
			at = i
	if at < 0:
		offer.cards.append(BoosterPack.card(lo, &"laser"))
		at = offer.cards.size() - 1
	var state := RunState.pack_rng.state
	panel.choose(at)
	assert_eq(panel.replacing(), at, "the replace step")
	assert_eq(PickPanel.replace_text(offer, 2, Callable(), false), "Back to the pack")
	assert_eq(PickPanel.replace_text(offer, 0, Callable(), false), "Replace Pistol 1")
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	panel._unhandled_input(esc)
	assert_eq(panel.replacing(), at, "Esc is the pause menu's, never Back")
	panel.choose(2)
	assert_eq(panel.replacing(), -1, "Back: the same pack again")
	assert_true(panel.is_open())
	assert_true(panel.offer == offer, "the same pack")
	assert_eq(RunState.pack_rng.state, state, "nothing drawn again")
	assert_eq(picked[0], 0, "no picked")
	assert_eq(r.pending_picks(), 1)
	assert_eq(int(r.pack_picks.back), 1)
	panel.choose(at)
	panel.choose(0)
	assert_eq(picked[0], 1)
	assert_eq(lo.slots[0].def.id, offer.cards[at].id, "slot 1 replaced in place")
	assert_eq(lo.slots.size(), 2)
	assert_eq(int(r.pack_picks.replace), 1)
	panel.picked.disconnect(count)


func test_the_replace_step_has_its_own_input_lock() -> void:
	var r := await _arena()
	var lo := _loadout()
	lo.give(&"shotgun")
	game.pick_panel.input_delay = 0.4
	r.want_pick()
	r._open_offer()
	var panel := game.pick_panel
	panel.offer.cards.append(BoosterPack.card(lo, &"laser"))
	panel._unlock()
	panel.choose(panel.offer.cards.size() - 1)
	assert_false(panel.can_choose(), "locked again for 0.4 s")
	panel._unlock()
	assert_true(panel.can_choose())
	panel.back()


func test_pack_panel_text_and_the_rare_frame() -> void:
	var r := await _arena()
	var lo := _loadout()
	r.announce(&"laser")   # M50.6: a rare weapon (a pool of two: no toast)
	r.want_pick()
	r._open_offer()
	var panel := game.pick_panel
	var o := panel.offer
	assert_eq(o.cards.map(func(c: Dictionary) -> String: return "%s:%s" % [c.id, c.rarity]),
			["pistol:common", "laser:rare"], "the pistol and a NEW laser: each its weapon's tier")
	assert_eq(panel._buttons.size(), 2)
	assert_string_contains(PickPanel.pack_card_text(o, 0, Callable(), false), "Pistol 1 -> 2   COMMON")
	assert_string_contains(PickPanel.pack_card_text(o, 1, Callable(), false), "Laser 1   NEW  RARE")
	var face: CardFace = panel._faces[1]   # M50.2c: a card face, not a framed button
	assert_eq([face.face.style, face.face.ribbon, face.face.tag], [&"card_rare", "RARE", "NEW"], "a rare card's gold frame")
	assert_eq([panel._faces[0].face.style, panel._faces[0].face.ribbon], [&"card_common", "COMMON"])
	panel.choose(1)
	assert_eq(lo.rank_of(&"laser"), 1, "M50.6: no rare bonus")


## CARD_RARE is a tier-0 role, so it resolves in every look, never to the unknown magenta.
## M50.3a: Pixel names it (the elite gold already in the atlas), in the one atlas digest move.
func test_card_rare_is_a_role_in_every_look() -> void:
	assert_true(Palette.has(&"card_rare"))
	assert_ne(Palette.tier_0(&"card_rare"), Color.MAGENTA)
	assert_eq(Grids.ROLES.get("card_rare"), "#ffd84a", "Pixel names it: the elite gold")
	assert_eq(Skins.pixel().role(&"card_rare"), Color.html("#ffd84a"))


# --- 6. Hand widget, telemetry, bot -----------------------------------------------------------

func test_the_hand_has_two_rows_a_rank_badge_and_mechanic_dots() -> void:
	var r := await _arena()
	var w := r.widget()
	w.manual = true
	assert_eq(HandWidget.ROWS, 2)
	var lo := _loadout()
	lo.set_weapon(&"pistol", 12)
	w.step(0.0)
	assert_eq(w.card_levels(0), [2, 2, 2] as Array[int])
	assert_eq(HandWidget.dots_text([5, 0, 1] as Array[int]), "●'''+○●")
	assert_string_contains(w.text(), "Pistol 12 ●'●'●'")
	assert_true(w.rank_badge_rect(0, Vector2(1280, 720)).end.x <= w.card_rect(0, Vector2(1280, 720)).end.x)


func test_the_bot_pack_rule() -> void:
	var r := await _arena()
	var lo := _loadout()
	r.announce(&"shotgun")
	r.want_pick()
	r._open_offer()
	var panel := game.pick_panel
	var o := panel.offer
	o.cards = [BoosterPack.card(lo, &"pistol"), BoosterPack.card(lo, &"shotgun")] as Array[Dictionary]
	assert_eq(BotRuns.pack_choice(panel, lo, ""), 1, "(5) a NEW card while the hand has room")
	assert_eq(BotRuns.pack_choice(panel, lo, "skip_new"), 0, "skip_new")
	# M50.6 (2): an EPIC card that melts a held parent is taken; one that needs a full hand's
	# slot is not (6). Rarity alone decides nothing any more.
	lo.give(&"shotgun")
	o.hand = [{"id": &"pistol", "title": "Pistol", "rank": 1}, {"id": &"shotgun", "title": "Shotgun", "rank": 1}] as Array[Dictionary]
	o.cards = [BoosterPack.card(lo, &"pistol"), BoosterPack.epic_card(lo, &"prism")] as Array[Dictionary]
	assert_eq(o.cards[1].kind, &"absorb")
	assert_eq(BotRuns.pack_choice(panel, lo, ""), 1, "(2) an epic that melts a held parent")
	assert_eq(BotRuns.pack_choice(panel, lo, "no_fuse"), 0, "no_fuse: never an epic")
	lo.slots.remove_at(1)
	lo.give(&"launcher")
	o.cards = [BoosterPack.card(lo, &"pistol"), BoosterPack.epic_card(lo, &"prism")] as Array[Dictionary]
	assert_eq(o.cards[1].kind, &"new")
	assert_eq(BotRuns.pack_choice(panel, lo, ""), 0, "(6) an epic NEW card on a full hand is never taken")
	lo.slots.remove_at(1)
	assert_eq(BotRuns.pack_choice(panel, lo, "first_pick"), 0)
	panel.dismiss()
	panel._dismissed = false
	r._want = 0
	lo.give(&"launcher")
	lo.held(&"launcher").shots = 9
	r.want_pick()
	r._open_offer()
	# M50.1b: a NEW card that is not a built recipe with a held card is never taken on a full
	# hand. M50.3b (Cluster built): on Pistol + Launcher the laser makes no recipe; the shotgun
	# (Cluster with the launcher) does.
	panel.offer.cards = [BoosterPack.card(lo, &"pistol"), BoosterPack.card(lo, &"laser"),
			BoosterPack.card(lo, &"launcher")] as Array[Dictionary]
	assert_eq(BotRuns.pack_choice(panel, lo, ""), 2, "(7) the most-fired held card; (6) no NEW on a full hand")
	panel._replacing = 1
	assert_eq(BotRuns.pack_choice(panel, lo, ""), -1, "Back on the replace step")
	panel._replacing = -1
	panel.offer.cards[1] = BoosterPack.card(lo, &"shotgun")
	assert_eq(BotRuns.pack_choice(panel, lo, ""), 1, "(4) a NEW card that makes a recipe with a held card")
	panel._replacing = 1
	assert_eq(BotRuns.pack_choice(panel, lo, ""), 0, "(4) its replace step lets the non-partner (pistol) go")
	panel._replacing = -1
	panel.choose(2)


func test_telemetry_counts_the_packs() -> void:
	var r := await _arena()
	_kill(r, 6)
	r._open_offer()
	game.pick_panel.choose(0)
	assert_eq(r.packs(), 1)
	assert_eq(int(r.pack_picks.upgrade), 1)
	assert_eq(r.picks, 1)
