extends GutTest
## M50.4b (Auto depth design, .check/auto_depth rev. 2, sections 2, 4, 7, 9): the passive items
## (Haste, Area, Might wired; Duration, Amount, Speed, Magnet rows), their offers (the pool rule,
## 2 slots, levels to 6), the mods they put on every weapon (node weapons keep their clocks),
## the item gives, the dressed level-up cards and the bot's auto_choice rule.

const LevelMeter := preload("res://paths/auto/level_meter.gd")
const LevelWidget := preload("res://paths/auto/level_widget.gd")
const BotRuns := preload("res://tools/bot_runs.gd")
const T := 48.0
const OPEN := Vector2(34, 20)
const BUILT: Array[StringName] = [&"area", &"haste", &"might"]

var game: Main
var player: CharacterBody2D


func after_each() -> void:
	RunState.invincible = false
	RunState.session_path = &""
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


## The arena on a live Auto path whose level-ups open the real panel (not frozen).
func _auto_runner() -> PathRunner:
	await _arena()
	RunState.session_path = &"auto"
	var r := game.ensure_path_runner()
	r.freeze()
	r.begin()
	r.frozen = false
	await wait_physics_frames(1)
	return r


func _loadout() -> Loadout:
	return Component.find(player, Loadout) as Loadout


func _offer(lo: Loadout, pool: Array[StringName], first := &"", run_seed := 7) -> PickOffer:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	return PickOffer.draw(lo, _auto(), pool, first, rng, Taste.new())


## Opens one level-up on `r` and leaves the panel open (input unlocked).
func _open(r: PathRunner) -> PickOffer:
	r.want_pick()
	r._open_offer()
	game.pick_panel._unlock()
	return game.pick_panel.offer


# --- Data -----------------------------------------------------------------------------------

func test_seven_item_rows_three_built_and_never_weapons() -> void:
	var ids: Array[StringName] = []
	for it in WeaponDB.items():
		ids.append(it.id)
	assert_eq(ids, [&"amount", &"area", &"attract", &"duration", &"haste", &"might", &"speed"] as Array[StringName])
	for id in ids:
		assert_false(WeaponDB.has(id), "%s is not a weapon (get_weapon never resolves it)" % id)
		assert_true(WeaponDB.item(id).icon in WeaponGlyph.ITEM_KEYS, "%s has a glyph key" % id)
		assert_eq(WeaponDB.item_built(id), id in BUILT, id)
	var problems := WeaponDB.item_problems()
	assert_eq(problems.size(), 4, "only the 4 unbuilt rows: %s" % [problems])
	for p in problems:
		assert_true("not built yet" in p, p)
	assert_eq(WeaponDB.ids().size(), 8, "all() / ids() stay the base weapons (M47.6d1 added the revolver)")
	assert_eq([WeaponDB.item(&"haste").pairs, WeaponDB.item(&"area").pairs, WeaponDB.item(&"might").pairs],
			[&"pistol", &"shotgun", &"nova"])


func test_unbuilt_items_are_never_candidates() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	for id: StringName in [&"duration", &"amount", &"speed", &"attract"]:
		assert_eq(PickOffer.candidate(lo, _auto(), id), {}, id)
		assert_false(lo.add_item(id), "%s cannot be held" % id)


func test_role_math_at_levels_one_and_six() -> void:
	await _arena()
	RunState.session_path = &"auto"   # a live path (no path: the pistol reads Tuning, M44 D3)
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"launcher", 1)
	var pistol := lo.held(&"pistol")
	var launcher := lo.held(&"launcher")
	var cd := float(pistol.value(&"cooldown"))
	var dmg := float(pistol.value(&"damage"))
	var blast := float(launcher.value(&"blast_radius"))
	assert_true(lo.add_item(&"haste"))
	assert_almost_eq(float(pistol.value(&"cooldown")), cd * 0.94, 0.00001, "Haste 1: -6%")
	assert_true(lo.add_item(&"might"))
	assert_almost_eq(float(pistol.value(&"damage")), dmg * 1.08, 0.00001, "Might 1: +8%")
	for i in 5:
		assert_true(lo.level_item(&"haste"))
		assert_true(lo.level_item(&"might"))
	assert_false(lo.level_item(&"haste"), "items stop at the path's cap, 6")
	assert_eq(lo.item_level(&"haste"), 6)
	assert_almost_eq(float(pistol.value(&"cooldown")), cd * 0.64, 0.00001, "Haste 6: x0.64")
	assert_almost_eq(float(pistol.value(&"damage")), dmg * 1.48, 0.00001, "Might 6: x1.48")
	assert_almost_eq(float(launcher.value(&"blast_radius")), blast, 0.00001, "no Area held")
	assert_false(lo.add_item(&"area"), "two passive slots: a third item never joins")
	lo.clear()
	lo.apply_path(_auto())
	lo.set_weapon(&"launcher", 1)
	launcher = lo.held(&"launcher")
	assert_true(lo.add_item(&"area"))
	assert_almost_eq(float(launcher.value(&"blast_radius")), blast * 1.1, 0.00001, "Area 1: +10%")
	for i in 5:
		lo.level_item(&"area")
	assert_almost_eq(float(launcher.value(&"blast_radius")), blast * 1.6, 0.00001, "Area 6: x1.6")
	lo.add_boost()
	assert_true(lo.add_item(&"might"))
	assert_almost_eq(float(launcher.value(&"damage")), float(WeaponCurve.value(launcher.def, &"damage", 1)) * 1.05 * 1.08,
			0.00001, "the boost and Might multiply")


## M50.4b review: Area was a dead pick in S8 (pistol + shotgun only). It now grows the
## Shotgun's cone reach (its pellets' lifetime) and the laser's burn width, as design 4 says.
func test_area_grows_the_shotgun_reach_and_the_burn_width() -> void:
	await _arena()
	RunState.session_path = &"auto"
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"shotgun", 1)
	lo.set_weapon(&"laser", 2)
	var shotgun := lo.held(&"shotgun")
	var laser := lo.held(&"laser")
	var reach := float(shotgun.value(&"lifetime"))
	var cd := float(shotgun.value(&"cooldown"))
	var dmg := float(shotgun.value(&"damage"))
	assert_true(lo.add_item(&"area"))
	assert_almost_eq(float(shotgun.value(&"lifetime")), reach * 1.1, 0.00001, "Area 1: the cone reaches 10% further")
	assert_true(lo.add_item(&"haste"))
	assert_almost_eq(float(shotgun.value(&"cooldown")), cd * 0.94, 0.00001, "the shotgun still reads Haste")
	lo.level_item(&"haste")
	lo.clear()
	lo.apply_path(_auto())
	lo.set_weapon(&"shotgun", 1)
	shotgun = lo.held(&"shotgun")
	lo.add_item(&"might")
	assert_almost_eq(float(shotgun.value(&"damage")), dmg * 1.08, 0.00001, "and Might")
	lo.clear()
	lo.apply_path(_auto())
	lo.set_weapon(&"laser", 2)
	laser = lo.held(&"laser")
	lo.add_item(&"area")
	var burn: WeaponTrait = null
	for t in laser.traits:
		if t.id == &"burn_line":
			burn = t
	assert_not_null(burn, "laser rank 2 burns")
	var shot := _ModHolder.new()
	autofree(shot)
	burn.spawned(laser, shot)
	assert_almost_eq(float(shot.mods[0].width), 1.1, 0.00001, "Area 1: the burn line is 10% wider")
	shot.mods[0].free()
	lo.clear()
	await wait_physics_frames(1)


class _ModHolder:
	extends Node
	var mods: Array = []
	func add_mod(m: Variant) -> void:
		mods.append(m)


func test_haste_never_touches_the_wells_field_life() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"well", 3)
	var node: Node = lo.passive_node(&"well")
	var life := float(node.get(&"life"))
	var dps := float(node.get(&"dps"))
	lo.add_item(&"haste")
	lo.add_item(&"might")
	assert_eq(lo.passive_node(&"well"), node, "never re-attached")
	assert_almost_eq(float(node.get(&"life")), life, 0.00001, "Haste: the field lives as long")
	assert_almost_eq(float(node.get(&"dps")), dps * 1.08, 0.00001, "Might: the bite is +8%")
	lo.clear()
	await wait_physics_frames(1)


func test_value_is_byte_identical_with_empty_mods_on_the_deep_curve() -> void:
	for id: StringName in WeaponDB.ids():
		var def := WeaponDB.get_weapon(id)
		for r in range(1, 7):
			var w := Weapon.new(def, r, WeaponCurve.DEEP)
			for f: StringName in [&"damage", &"cooldown", &"pellets", &"speed", &"blast_radius", &"pierce", &"lifetime"]:
				var v: Variant = w.value(f)
				var old: Variant = WeaponCurve.value(def, f, r)
				assert_eq(typeof(v), typeof(old), "%s %d %s type" % [id, r, f])
				assert_eq(v, old)


func test_an_item_pick_keeps_novas_clock() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"nova", 1)
	var node: Node = lo.passive_node(&"nova")
	await wait_physics_frames(30)
	var left := float(node.get(&"_left"))
	lo.add_item(&"haste")
	assert_eq(lo.passive_node(&"nova"), node, "never re-attached")
	assert_almost_eq(float(node.get(&"cooldown")), 3.0 * 0.94, 0.0001)
	assert_almost_eq(float(node.get(&"_left")), minf(left, 3.0 * 0.94), 0.0001, "the next blast never moves past the new period")
	lo.clear()
	await wait_physics_frames(1)


func test_clear_and_apply_path_drop_the_items() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.add_item(&"haste")
	assert_false(lo.current().mods.is_empty())
	lo.clear()
	assert_eq(lo.items.size(), 0)
	assert_true(lo.current().mods.is_empty(), "clear resets the mods")
	lo.apply_path(_auto())
	lo.add_item(&"might")
	lo.apply_path(PathDB.get_def(&"arsenal"))
	assert_eq([lo.items.size(), lo.max_items], [0, 0], "another path holds no items")
	assert_false(lo.add_item(&"haste"))


# --- Offers ---------------------------------------------------------------------------------

func test_items_join_offers_only_by_the_pool_rule_and_stop_at_two_and_six() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	var o := _offer(lo, [&"pistol"] as Array[StringName])
	assert_false(o.cards.any(func(c: Dictionary) -> bool: return c.get("item", false)), "not in the pool: no item")
	o = _offer(lo, [&"pistol", &"haste"] as Array[StringName], &"haste")
	assert_eq(o.cards[0].id, &"haste", "a give: offered first")
	assert_eq([o.cards[0].kind, o.cards[0].item, o.cards[0].rank, o.cards[0].paired], [&"new", true, 1, true])
	assert_eq(o.cards[0].text, "Haste 1: guns fire 6% faster  (new) · your Pistol evolves with this")
	lo.add_item(&"haste")
	o = _offer(lo, [&"haste"] as Array[StringName])
	assert_eq([o.cards[0].kind, o.cards[0].rank], [&"upgrade", 2])
	assert_eq(o.cards[0].text, "Haste 1 -> 2: guns fire 12% faster (was 6%) · your Pistol evolves with this")
	lo.add_item(&"area")
	o = _offer(lo, [&"might"] as Array[StringName])
	assert_false(&"might" in o.ids(), "two items held: no third")
	for i in 5:
		lo.level_item(&"haste")
	o = _offer(lo, [&"haste"] as Array[StringName])
	assert_false(&"haste" in o.ids(), "Haste 6: no upgrade card")


func test_the_pick_takes_and_levels_an_item() -> void:
	var r := await _auto_runner()
	var lo := _loadout()
	r.announce(&"haste")
	r.give(&"haste")
	var offer := _open(r)
	assert_eq(offer.cards[0].id, &"haste", "give haste: offered first at the next level-up")
	assert_gt(offer.level, 0, "a level-up offer carries its level")
	assert_eq(offer.cap, 6)
	var seen := []
	EventBus.item_changed.connect(func(id: StringName, level: int) -> void: seen.append([id, level]))
	game.pick_panel.choose(0)
	assert_eq(lo.item_level(&"haste"), 1)
	assert_eq(r.level_picks.item_new, 1)
	offer = _open(r)
	var i := offer.ids().find(&"haste")
	assert_gt(i, -1, "the held item's upgrade can be offered")
	game.pick_panel.choose(i)
	assert_eq(lo.item_level(&"haste"), 2)
	assert_eq(r.level_picks.item_up, 1)
	assert_eq(seen, [[&"haste", 1], [&"haste", 2]])
	assert_true(r.state_text().ends_with(" items=haste:2"), r.state_text())


func test_path_def_accepts_item_ids_in_its_pool() -> void:
	assert_eq(_auto().problems(), [] as Array[String])
	assert_true(&"haste" in _auto().offer_pool_extra)
	var d := _auto().duplicate() as PathDef
	d.offer_pool_extra = d.offer_pool_extra.duplicate()   # a shallow duplicate shares the cached def's array
	d.offer_pool_extra.append(&"not_a_thing")
	assert_false(&"not_a_thing" in _auto().offer_pool_extra, "the shared auto def is untouched")
	assert_true(d.problems().any(func(p: String) -> bool: return "not_a_thing" in p))


# --- Gives and the session grammar -------------------------------------------------------------

## A session with one cue (cue_list() parses once per SessionDef).
func _problems_of(cue: String) -> Array[String]:
	var s := SessionDef.new()
	s.id = &"x"
	s.weapons = [&"pistol"] as Array[StringName]
	s.cues = PackedStringArray([cue])
	return s._weapon_problems("x")


func test_item_gives_need_answer_path_auto_and_a_built_item() -> void:
	assert_eq(_problems_of("answer:path_auto at 9: give haste"), [] as Array[String], "Auto's give is fine")
	assert_true(_problems_of("at 9: give haste").any(func(p: String) -> bool: return "answer:path_auto" in p))
	assert_true(_problems_of("answer:path_auto at 9: give speed").any(func(p: String) -> bool: return "not built yet" in p))
	assert_true(_problems_of("answer:path_auto at 9 [attract]: say happy: Hi.").any(
			func(p: String) -> bool: return "not built yet" in p))
	assert_eq(_problems_of("answer:path_auto at 9 [might]: say happy: Hi."), [] as Array[String],
			"a built item's tag is fine (Auto's pool)")


func test_an_item_give_without_a_levelups_path_is_skipped_and_logged() -> void:
	RunState.reset(0)
	var runner := SessionRunner.new()   # never in the tree: no session, no path runner
	runner._fire(Cue.parse("at 9: give haste"), 0)
	runner.free()
	var skipped := RunState.run_log.filter(func(e: Dictionary) -> bool: return e.get("event") == &"give_skipped")
	assert_eq(skipped.size(), 1)
	assert_eq(skipped[0].get("item"), "haste")


func test_the_shipped_sessions_carry_the_item_lines() -> void:
	var s8 := CampaignDB.get_session(&"s2_02_day_one")
	var s9 := CampaignDB.get_session(&"s2_03_paint")
	assert_true("answer:path_auto at 38 [haste]: say happy: New pick: passives. Haste makes every gun fire faster." in s8.cues)
	assert_true("answer:path_auto at 42 [area]: say thinking: And area: bigger blasts, longer shotgun reach. Two passive slots. Choose." in s8.cues)
	assert_true(s8.debrief.has("answer:path_auto thinking: A maxed gun and its passive... I have an idea for next time."))
	assert_true("answer:path_auto at 9: give haste" in s9.cues)
	assert_true("answer:path_auto at 94 [might]: say thinking: Might makes everything hit harder. Nova evolves with it." in s9.cues)
	# M50.4b review: a give only puts Haste first in the next offer, so its line waits for the pick.
	assert_true("answer:path_auto holds haste: say happy: Haste came back with you. Guns fire faster." in s9.cues)
	assert_false(s9.cues.has("answer:path_auto at 18: say happy: Haste came back with you. Guns fire faster."))
	assert_eq(s8.problems(), [] as Array[String])
	assert_eq(s9.problems(), [] as Array[String])


## M50.4b review: "holds <item>:" is due only once the item is held (not when a give offers it).
func test_a_holds_cue_waits_for_the_item() -> void:
	var c := Cue.parse("holds haste: say happy: Haste came back with you.")
	assert_eq(c.problem, "")
	assert_eq([c.when, c.held], [&"holds", &"haste"])
	assert_false(c.due({"clock": 99.0, "items": []}), "given, not picked: silent")
	assert_false(c.due({"clock": 99.0, "items": [&"might"]}))
	assert_true(c.due({"clock": 0.0, "items": [&"might", &"haste"]}), "picked: says it")
	assert_ne(Cue.parse("holds: say happy: x").problem, "", "holds needs an item")
	assert_ne(Cue.parse("holds 3: say happy: x").problem, "", "an item id, not a number")
	var s9 := CampaignDB.get_session(&"s2_03_paint").duplicate() as SessionDef
	s9.cues = PackedStringArray(s9.cues) + PackedStringArray(["answer:path_auto holds nope: say happy: x"])
	assert_true(s9.problems().any(func(p: String) -> bool: return "holds nope: no built item" in p))


func test_the_runner_says_the_haste_line_only_after_the_pick() -> void:
	var r := await _auto_runner()
	var runner := SessionRunner.new()
	runner.path_runner = r
	autofree(runner)
	assert_eq(runner._held_items(), [], "nothing held yet")
	r.loadout().add_item(&"haste")
	assert_eq(runner._held_items(), [&"haste"])
	r.loadout().clear()


# --- HUD --------------------------------------------------------------------------------------

func test_the_raw_widget_shows_the_held_items() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.add_item(&"haste")
	lo.level_item(&"haste")
	var m := LevelMeter.new()
	m.def = _auto()
	var w := LevelWidget.new()
	w.meter = m
	w.loadout = lo
	add_child_autofree(w)
	await wait_process_frames(1)
	assert_eq(w.text(), "LV 1\nPistol 1\nHaste 2  +")
	lo.add_item(&"area")
	await wait_process_frames(1)
	assert_eq(w.text(), "LV 1\nPistol 1\nHaste 2  Area 1")
	assert_lte(w.custom_minimum_size.x, LevelWidget.MAX_W)
	assert_lte(w.custom_minimum_size.y, 60.0)


func test_the_rail_reads_the_items_as_passives() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.add_item(&"might")
	lo.level_item(&"might")
	var fake := _FakeRunner.new()
	var d: Dictionary = RailState._items(fake, lo, _auto())
	fake.free()
	assert_eq(d.passives, [{"title": "Might", "rank": 2, "icon": &"might"}])
	assert_eq(d.passive_slots, 2)


class _FakeRunner:
	extends Node

	func meter() -> RefCounted:
		return null


# --- The dressed cards (the M50.4m sheet) ------------------------------------------------------

func test_level_card_data_for_each_kind() -> void:
	var weapon := LevelCard.data_for({"id": &"pistol", "rank": 4, "kind": &"upgrade", "text": "x"}, 6, "1")
	assert_eq([weapon.kind, weapon.kind_label, weapon.title, weapon.from, weapon.to, weapon.cap, weapon.new],
			[LevelCard.KIND_WEAPON, "WEAPON", "Pistol", 3, 4, 6, false])
	assert_eq(weapon.effect, WeaponCurve.gain_text(WeaponDB.get_weapon(&"pistol"), 3, 4))
	var fresh := LevelCard.data_for({"id": &"shotgun", "rank": 1, "kind": &"new", "text": "x"}, 6, "2")
	assert_eq([fresh.new, fresh.to, fresh.effect], [true, 1, WeaponDB.get_weapon(&"shotgun").card_text[0]])
	var item := LevelCard.data_for({"id": &"haste", "rank": 3, "kind": &"upgrade", "item": true, "paired": true}, 6, "3")
	assert_eq([item.kind, item.kind_label, item.title, item.icon, item.pair, item.paired],
			[LevelCard.KIND_ITEM, "PASSIVE", "Haste", &"haste", "pairs with Pistol", true])
	assert_eq(item.effect, "guns fire 18% faster (was 12%)")
	var hp := LevelCard.data_for({"id": PickOffer.HP, "rank": 0, "kind": PickOffer.HP}, 6, "1")
	var boost := LevelCard.data_for({"id": PickOffer.BOOST, "rank": 0, "kind": PickOffer.BOOST}, 6, "2")
	assert_eq([hp.kind, hp.title, hp.icon, hp.cap], [LevelCard.KIND_FILLER, "+1 MAX HP", &"hp", 0])
	assert_eq([boost.title, boost.icon], ["+5% DAMAGE", &"boost"])


func test_a_level_up_opens_the_dressed_cards_flat_then_pixel() -> void:
	var r := await _auto_runner()
	r.announce(&"haste")
	r.announce(&"shotgun")
	var offer := _open(r)
	var panel := game.pick_panel
	assert_true(panel.dressed())
	assert_eq(panel._cards_dressed.size(), offer.cards.size())
	assert_true(panel._banner.visible, "the LEVEL n banner")
	assert_eq(panel._banner.level, offer.level)
	assert_eq(panel._banner.count, offer.cards.size(), "no EVOLVE: the banner counts the cards")
	assert_false(panel._line.visible)
	assert_false(panel._cards_dressed[0].pixel, "no look: the flat cards")
	for b in panel._buttons:
		assert_eq(b.text, "", "the card draws itself")
	await wait_process_frames(2)   # both looks draw without an error
	panel.choose(0)
	Skins.use(Skins.pixel())
	for e in get_errors():   # the look's known engine note (test_rail_ui)
		if e.contains_text("Camera2D overridden to physics process mode"):
			e.handled = true
	_open(r)
	assert_true(panel._cards_dressed[0].pixel, "the UI look: the Pixel cards")
	await wait_process_frames(2)
	panel.choose(0)


func test_a_pack_and_a_plain_offer_stay_plain() -> void:
	var o := PickOffer.new()
	o.cards.append({"id": &"pistol", "rank": 2, "kind": &"upgrade", "text": "x"})
	var p := PickPanel.new()
	add_child_autofree(p)
	p.input_delay = 0.0
	assert_true(p.open(o))
	assert_false(p.dressed(), "level 0: the plain buttons")
	assert_eq(p._buttons[0].text.ends_with("x"), true)
	p.dismiss()


func test_every_glyph_key_draws_on_the_card_art() -> void:
	for key in WeaponGlyph.ITEM_KEYS:
		assert_true(CardArt.has(key), "%s has a Pixel grid" % key)
		for row: String in CardArt.GLYPHS[key][0]:
			for ch in row:
				assert_true(ch == "." or (CardArt.GLYPHS[key][1] as Dictionary).has(ch), "%s: %s has a colour" % [key, ch])


## M50.4b review: with a look on, the weapon cards and Auto's rail slots draw one gun per
## weapon from the sheet (the Pistol's and the Shotgun's shot sprites are the same pellet).
func test_each_card_weapon_has_its_own_gun() -> void:
	var grids := []
	for id: StringName in [&"pistol", &"shotgun", &"laser", &"launcher"]:
		var icon := WeaponDB.get_weapon(id).icon
		assert_true(CardArt.GUNS.has(icon), "%s (%s) has a gun" % [id, icon])
		var grid: Array = CardArt.GUNS[icon][0]
		assert_false(grid in grids, "%s is its own picture" % id)
		grids.append(grid)
		for row: String in grid:
			assert_eq(row.length(), String(grid[0]).length(), "%s: rows are one width" % id)
			for ch in row:
				assert_true(ch == "." or (CardArt.GUNS[icon][1] as Dictionary).has(ch), "%s: %s has a colour" % [id, ch])
		for role: StringName in (CardArt.GUNS[icon][1] as Dictionary).values():
			assert_ne(CardArt.c(role), Color.MAGENTA, "%s: %s is a card colour" % [id, role])


## M50.4f (the sheet's VARIANTS panel): a card to the path's last rank is MAX (gold tag, gold
## ring), a rank-up that brings a mechanic names it (the icon and the bold name), the tall pips
## are the mechanic ranks, and an item reads READY when its EVOLVE is on offer.
func test_m50_4f_max_mechanic_and_ready_card_data() -> void:
	var top := LevelCard.data_for({"id": &"pistol", "rank": 6, "kind": &"upgrade", "text": "x"}, 6, "1")
	assert_true(top.max, "5 > 6 on a cap-6 path is MAX")
	var mid := LevelCard.data_for({"id": &"pistol", "rank": 5, "kind": &"upgrade", "text": "x"}, 6, "1")
	assert_false(mid.max)
	var fresh := LevelCard.data_for({"id": &"pistol", "rank": 1, "kind": &"new", "text": "x"}, 6, "1")
	assert_false(fresh.max, "a NEW card is never MAX")
	var four := LevelCard.data_for({"id": &"pistol", "rank": 4, "kind": &"upgrade", "text": "x"}, 6, "1")
	var wd := WeaponDB.get_weapon(&"pistol")
	assert_ne(four.mech, &"", "an even rank brings a mechanic")
	assert_true(four.mech in WeaponCurve.mechanics(wd), String(four.mech))
	assert_eq(four.mech_name, String(four.mech).replace("_", " ").capitalize())
	assert_eq(mid.mech, &"", "an odd rank brings damage, not a mechanic")
	var card := LevelCard.new()
	autofree(card)
	card.data = four
	assert_eq([card.mechanic_rank(2), card.mechanic_rank(3), card.mechanic_rank(4), card.mechanic_rank(6)],
			[true, false, true, true], "tall pips: the mechanic ranks")
	card.data = LevelCard.data_for({"id": &"haste", "rank": 3, "kind": &"upgrade", "item": true, "paired": true}, 6, "2")
	assert_false(card.mechanic_rank(2), "a passive has no tall pips")
	assert_false(card.data.ready, "no EVOLVE on offer: no READY")
	var ready := LevelCard.data_for({"id": &"haste", "rank": 3, "kind": &"upgrade", "item": true, "paired": true}, 6, "2",
			{"from": &"pistol", "into": &"minigun", "catalyst": &"haste", "rank": 6})
	assert_true(ready.ready, "its EVOLVE is on offer: READY")
	assert_eq(ready.pair_icon, wd.icon, "the pair row shows the paired gun")
	for key: StringName in CardArt.MECHS:
		var grid: Array = CardArt.MECHS[key][0]
		for row: String in grid:
			for ch in row:
				assert_true(ch == "." or (CardArt.MECHS[key][1] as Dictionary).has(ch), "%s: %s has a colour" % [key, ch])
	for icon in WeaponGlyph.FLAT_GUNS:
		assert_true(WeaponDB.ids().any(func(id: StringName) -> bool: return WeaponDB.get_weapon(id).icon == icon) or icon == &"minigun",
				"%s is a weapon's icon" % icon)


## M50.4f (the sheet's FOCUS and XP strip): the focused card reads "focused", and the rail's ITEMS
## reading lifts the slot the focused choice changes (a free well for a NEW card), fills the bar
## and carries the per-key legend while the level-up is open; the flat look adds its slot bar.
func test_m50_4f_focus_lifts_the_slot_and_the_rail_reads_the_pick() -> void:
	var r := await _auto_runner()
	r.announce(&"haste")
	r.announce(&"shotgun")
	var offer := _open(r)
	var panel := game.pick_panel
	assert_not_null(panel._slot_bar, "the flat look: the slot bar under the cards")
	var lo := r.loadout()
	for i in panel._buttons.size():
		panel._buttons[i].grab_focus()
		assert_eq(panel.focused_choice(), i)
		for j in panel._cards_dressed.size():
			assert_eq(panel._cards_dressed[j].key_word(), "focused" if j == i else "choose", "card %d with %d focused" % [j, i])
		var d := RailState._items(r, lo, _auto())
		assert_true(bool(d.get("picking", false)), "the level-up is open")
		assert_eq(String(d.legend).count("["), panel._buttons.size(), "one legend entry per choice: %s" % d.legend)
		var c: Dictionary = offer.cards[i]
		var lifted := 0
		for s: Dictionary in (d.weapons as Array) + (d.passives as Array):
			if s.get("lift", false):
				lifted += 1
				assert_true(s.get("next", false), "its next pip glows")
		if c.get("kind") == &"new":
			assert_eq(lifted, 0)
			if c.get("item", false):
				assert_eq(int(d.new_passive), (d.passives as Array).size(), "the free passive well lifts")
			else:
				assert_eq(int(d.new_slot), (d.weapons as Array).size(), "the free weapon well lifts")
		elif c.get("kind") == &"upgrade":
			assert_eq(lifted, 1, "the slot card %d changes lifts" % i)
	panel.choose(0)
	var after := RailState._items(r, lo, _auto())
	assert_false(after.has("picking"), "closed: the rail's own XP strip")
	r.loadout().clear()


# --- The bot's rule ---------------------------------------------------------------------------

class _Panel:
	extends Node
	var offer: PickOffer


func _panel_with(cards: Array) -> _Panel:
	var p := _Panel.new()
	p.offer = PickOffer.new()
	for c: Dictionary in cards:
		p.offer.cards.append(c)
	autofree(p)
	return p


func test_auto_choice_keeps_the_draw_without_an_item_card() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	var p := _panel_with([{"id": &"pistol", "rank": 2, "kind": &"upgrade"}, {"id": &"shotgun", "rank": 1, "kind": &"new"}])
	for drawn in 2:
		assert_eq(BotRuns.auto_choice(p, lo, "", drawn), drawn, "S7's taste and the stub: the draw")


func test_auto_choice_rules_in_order() -> void:
	await _arena()
	var lo := _loadout()
	lo.apply_path(_auto())
	lo.set_weapon(&"pistol", 3)
	var up := {"id": &"pistol", "rank": 4, "kind": &"upgrade"}
	var shot := {"id": &"shotgun", "rank": 1, "kind": &"new"}
	var haste := {"id": &"haste", "rank": 1, "kind": &"new", "item": true}
	var area := {"id": &"area", "rank": 1, "kind": &"new", "item": true}
	# (3) a catalyst of a held weapon beats a new weapon and an upgrade.
	assert_eq(BotRuns.auto_choice(_panel_with([up, shot, haste]), lo, "", 0), 2)
	# (4) a new weapon while a slot is free, before (5) the upgrade; Area pairs nothing held.
	assert_eq(BotRuns.auto_choice(_panel_with([up, area, shot]), lo, "", 1), 2)
	lo.add_item(&"haste")
	# (2) the paired weapon's upgrade first.
	var haste_up := {"id": &"haste", "rank": 2, "kind": &"upgrade", "item": true}
	assert_eq(BotRuns.auto_choice(_panel_with([shot, haste_up, up]), lo, "", 0), 2)
	lo.set_weapon(&"shotgun", 2)
	lo.set_weapon(&"nova", 1)
	# (3) again: Area now pairs the held shotgun.
	var shot_up := {"id": &"shotgun", "rank": 3, "kind": &"upgrade"}
	var nova_up := {"id": &"nova", "rank": 2, "kind": &"upgrade"}
	assert_eq(BotRuns.auto_choice(_panel_with([nova_up, area, shot_up]), lo, "", 0), 1)
	# full slots: (5) the highest-ranked upgrade, then (6) an item upgrade, then (7) the draw.
	assert_eq(BotRuns.auto_choice(_panel_with([nova_up, haste_up, shot_up]), lo, "", 0), 2)
	var well := {"id": &"well", "rank": 1, "kind": &"new"}
	assert_eq(BotRuns.auto_choice(_panel_with([well, haste_up]), lo, "", 0), 1)
	assert_eq(BotRuns.auto_choice(_panel_with([up, haste]), lo, "random_picks", 1), 1, "random_picks: the draw")
	lo.clear()
	await wait_physics_frames(1)
