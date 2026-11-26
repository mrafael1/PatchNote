extends GutTest
## M50.4c1 (Auto depth design, .check/auto_depth rev. 2, sections 2.5-2.6, 5, 6, 7, 9): the
## evolutions (Minigun built, six rows), the EVOLVE choice (only with the basic, rank 6, the
## catalyst and a built row; the choice after the cards, never a card; it spends the level-up),
## the steering, Minigun's numbers on the 60 Hz clock, the live nerf (game time, the pause stops
## it, stop() lands it, a swap drops it, the note from the effective numbers), the grammar, the
## recipes, the HUD hint, the dressed EVOLVE card and the bot's rule 1.

const BotRuns := preload("res://tools/bot_runs.gd")
const Sweep := preload("res://weapons/traits/sweep.gd")
const LevelMeter := preload("res://paths/auto/level_meter.gd")
const LevelWidget := preload("res://paths/auto/level_widget.gd")
const T := 48.0
const OPEN := Vector2(34, 20)
const CHASER := preload("res://entities/enemy_chaser.tscn")

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


## The arena on a live Auto path (outside a session every basic is on, `evolve` too).
func _auto_runner() -> PathRunner:
	await _arena()
	RunState.session_path = &"auto"
	var r := game.ensure_path_runner()
	r.freeze()
	r.begin()
	r.frozen = false
	await wait_physics_frames(1)
	return r


func _ready_to_evolve(r: PathRunner, haste := 1) -> Loadout:
	var lo := r.loadout()
	lo.set_weapon(&"pistol", 6)
	lo.add_item(&"haste")
	for i in haste - 1:
		lo.level_item(&"haste")
	return lo


func _open(r: PathRunner) -> PickOffer:
	r.want_pick()
	r._open_offer()
	game.pick_panel._unlock()
	return game.pick_panel.offer


# --- Data -----------------------------------------------------------------------------------

func test_seven_evolution_rows_three_built() -> void:
	var ids: Array[StringName] = []
	for e in WeaponDB.evolutions():
		ids.append(e.id)
	assert_eq(ids, [&"barrage", &"halo", &"minigun", &"singularity", &"sunbeam", &"supernova", &"thunderclap"] as Array[StringName])
	assert_eq(WeaponDB.ids().size(), 8, "all() / ids() stay the base weapons (M47.6d1 added the revolver)")
	assert_true(WeaponDB.has(&"minigun"))
	assert_true(WeaponDB.get_weapon(&"minigun").is_evolution())
	assert_eq(WeaponDB.evolution_for(&"pistol"), &"minigun")
	assert_eq(WeaponDB.evolution_for(&"nova"), &"supernova")
	assert_true(WeaponDB.evolution_built(&"minigun"))
	assert_true(WeaponDB.evolution_built(&"supernova"), "M50.4c2")
	assert_true(WeaponDB.evolution_built(&"thunderclap"), "M50.4c2")
	assert_false(WeaponDB.evolution_built(&"sunbeam"))
	var problems := WeaponDB.evolution_problems()
	assert_eq(problems.size(), 4, "the four unbuilt rows only (M50.4c2): %s" % [problems])
	for p in problems:
		assert_true("not built yet" in p, p)
	for e in WeaponDB.evolutions():
		assert_eq(WeaponDB.item(e.catalyst).pairs, e.base, "%s: its catalyst pairs its base" % e.id)


func test_a_bad_row_is_reported() -> void:
	var bad := WeaponDef.new()
	bad.id = &"bad"
	bad.title = "Bad"
	bad.base = &"pistol"
	bad.card_text = PackedStringArray(["Bad"])
	bad.launch_values = {&"title": 1}
	var p := bad.problems()
	assert_true(p.any(func(x: String) -> bool: return "catalyst" in x), str(p))
	assert_true(p.any(func(x: String) -> bool: return "launch field" in x), str(p))


func test_minigun_holds_all_its_mechanics_at_level_one_and_reads_minigun() -> void:
	var w := Weapon.new(WeaponDB.get_weapon(&"minigun"), 1, WeaponCurve.DEEP)
	assert_eq(w.traits.map(func(t: WeaponTrait) -> String: return "%s:%d" % [t.id, t.level]),
			["heavy_round:1", "seeker:1", "chain:1", "sweep:1"])
	assert_eq(w.label(), "MINIGUN")
	assert_almost_eq(float(w.value(&"cooldown")), 0.066, 0.00001)
	assert_almost_eq(float(w.value(&"damage")), 1.5, 0.00001)


func test_sweep_is_a_fixed_pattern_by_shot_count() -> void:
	assert_eq([Sweep.offset(0), Sweep.offset(1), Sweep.offset(2), Sweep.offset(3), Sweep.offset(4), Sweep.offset(5),
			Sweep.offset(6)], [-6.0, -2.0, 2.0, 6.0, 2.0, -2.0, -6.0])
	var w := Weapon.new(WeaponDB.get_weapon(&"minigun"), 1, WeaponCurve.DEEP)
	var t: WeaponTrait = w.traits[3]
	w.shots = 3
	var params := {&"velocity": Vector2.RIGHT * 100.0}
	t.shot(w, 0, params)
	assert_almost_eq(rad_to_deg((params[&"velocity"] as Vector2).angle()), 6.0, 0.001)


# --- Rates on the 60 Hz clock ---------------------------------------------------------------

## The ticks between two shots of a weapon at cooldown `cd`, as Loadout counts them (ready_in
## down by the physics delta, clamped at 0; a shot when it is 0; the overshoot dropped).
func _ticks_between(cd: float) -> int:
	var ready := 0.0
	var last := -1
	var gaps: Array[int] = []
	for tick in 60:
		ready = maxf(0.0, ready - 1.0 / 60.0)
		if ready <= 0.0:
			if last >= 0:
				gaps.append(tick - last)
			last = tick
			ready = cd
	assert_eq(gaps.min(), gaps.max(), "a steady rate")
	return gaps[0]


func test_minigun_tick_counts() -> void:
	var lo := Loadout.new()
	lo.curve = WeaponCurve.DEEP
	lo.rank_cap = 6
	lo.max_items = 2
	var w := Weapon.new(WeaponDB.get_weapon(&"minigun"), 1, WeaponCurve.DEEP)
	assert_eq(_ticks_between(float(w.value(&"cooldown"))), 4, "steady: 15 shots/s")
	w.launch = {&"cooldown": 0.033, &"damage": 2.0, &"pierce": 1}
	assert_eq(_ticks_between(float(w.value(&"cooldown"))), 2, "launch: 30 shots/s")
	for haste in [1, 4, 5, 6]:
		var it := Item.new(WeaponDB.item(&"haste"), haste)
		w.mods = {&"haste": it.def.mult(haste)}
		w.launch = {}
		assert_eq(_ticks_between(float(w.value(&"cooldown"))), 4 if haste <= 4 else 3, "steady, Haste %d" % haste)
		w.launch = {&"cooldown": 0.033}
		assert_eq(_ticks_between(float(w.value(&"cooldown"))), 2, "launch, Haste %d: 30/s" % haste)
	assert_eq(PathRunner.fire_rate(0.066), 15.0)
	assert_eq(PathRunner.fire_rate(0.033), 30.0)
	assert_eq(PathRunner.fire_rate(0.066 * 0.7), 20.0)
	lo.free()


func test_value_reads_launch_then_mods() -> void:
	var w := Weapon.new(WeaponDB.get_weapon(&"minigun"), 1, WeaponCurve.DEEP)
	w.launch = {&"cooldown": 0.033, &"damage": 2.0}
	w.mods = {&"haste": 0.94, &"might": 1.08}
	assert_almost_eq(float(w.value(&"cooldown")), 0.033 * 0.94, 0.000001)
	assert_almost_eq(float(w.value(&"damage")), 2.0 * 1.08, 0.000001)
	assert_eq(w.value(&"pellets"), 1, "an int field without launch or mods stays an int")


# --- EVOLVE -------------------------------------------------------------------------------------

func test_evolve_needs_rank_six_and_the_catalyst() -> void:
	var r := await _auto_runner()
	var lo := r.loadout()
	assert_true(r.evolve_live(), "outside a session every basic is on")
	lo.set_weapon(&"pistol", 5)
	lo.add_item(&"haste")
	assert_eq(r.evolve_option(), {}, "rank 5: not yet")
	lo.set_weapon(&"pistol", 6)
	var ev := r.evolve_option()
	assert_eq([ev.from, ev.into, ev.catalyst, ev.rank], [&"pistol", &"minigun", &"haste", 6])
	assert_eq(String(ev.text), "EVOLVE: Pistol 6 + Haste -> MINIGUN: a stream of bullets that sweeps the room.")
	lo.clear()
	lo.apply_path(_auto())
	lo.set_weapon(&"pistol", 6)
	assert_eq(r.evolve_option(), {}, "no catalyst held")
	lo.set_weapon(&"nova", 5)
	lo.add_item(&"might")
	assert_eq(r.evolve_option(), {}, "nova 5: not yet")
	lo.set_weapon(&"nova", 6)   # M50.4c2: Supernova is built
	ev = r.evolve_option()
	assert_eq([ev.from, ev.into, ev.catalyst], [&"nova", &"supernova", &"might"])


func test_evolve_is_not_live_without_the_basic() -> void:
	var r := await _auto_runner()
	_ready_to_evolve(r)
	var no_basic: PathDef = _auto().duplicate()
	no_basic.basics = [&"levelups", &"crowd"] as Array[StringName]
	r.def = no_basic
	assert_false(r.evolve_live())
	assert_eq(r.evolve_option(), {})
	assert_eq(r.evolve_hint(), "")
	r.def = _auto()


func test_evolve_is_the_choice_after_the_cards_and_never_moves_the_draw() -> void:
	var r := await _auto_runner()
	var lo := _ready_to_evolve(r)
	r.announce(&"shotgun")
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 11
	var a := PickOffer.draw(lo, _auto(), r.offer_pool(), &"", rng_a, Taste.new())
	RunState.pick_rng.seed = 11
	var offer := _open(r)
	assert_false(offer.evolve.is_empty())
	assert_eq(offer.ids(), a.ids(), "the same cards as an offer without EVOLVE")
	assert_eq(RunState.pick_rng.state, rng_a.state, "the same draws")
	var panel := game.pick_panel
	assert_true(panel.has_evolve())
	assert_eq(panel._buttons.size(), offer.cards.size() + 1, "one more choice")
	assert_eq(panel._cards_dressed[offer.cards.size()].data.kind, LevelCard.KIND_EVOLVE)
	assert_eq(panel._banner.count, offer.cards.size() + 1,
			"the banner counts EVOLVE as a choice (Auto_Choices mockup: pick 1 of 3 for 2 cards + EVOLVE)")
	var shots := lo.held(&"pistol")
	shots.shots = 41
	var picks := r.picks
	var made := []
	var on_made := func(id: StringName) -> void: made.append(id)
	EventBus.pick_made.connect(on_made)
	panel.choose(offer.cards.size())
	EventBus.pick_made.disconnect(on_made)
	assert_eq(lo.summary(), "minigun:1", "evolved in place")
	assert_eq(lo.slots[0].shots, 41, "shots kept")
	assert_eq(lo.item_level(&"haste"), 1, "the item stays")
	assert_eq(r.picks, picks + 1, "EVOLVE spends the level-up")
	assert_eq(r.level_picks.evolve, 1)
	assert_eq(made, [&"minigun"])
	assert_eq(r.evolutions.size(), 1)
	assert_eq(r.evolve_option(), {}, "one per weapon")
	assert_eq(PickOffer.candidate(lo, _auto(), &"pistol"), {}, "the base never comes back")
	assert_eq(PickOffer.candidate(lo, _auto(), &"minigun"), {}, "no ranks on an evolution")
	lo.clear()


func test_the_evolve_key_follows_the_card_count() -> void:
	var r := await _auto_runner()
	_ready_to_evolve(r)
	var offer := PickOffer.new()
	offer.level = 5
	offer.cap = 6
	offer.cards = [{"id": &"pistol", "rank": 2, "kind": &"upgrade", "text": "a"},
			{"id": &"shotgun", "rank": 1, "kind": &"new", "text": "b"}] as Array[Dictionary]
	offer.evolve = r.evolve_option()
	assert_true(PickPanel.evolve_text(offer).begins_with("[%s]" % InputSetup.expand_keys("{key:choose_3}")),
			"2 cards: choose_3")
	offer.cards.append({"id": &"haste", "rank": 2, "kind": &"upgrade", "item": true, "text": "c"})
	assert_true(PickPanel.evolve_text(offer).begins_with("[%s]" % InputSetup.expand_keys("{key:choose_4}")),
			"3 cards: choose_4")
	r.loadout().clear()


func test_steering_offers_the_paired_weapon_first() -> void:
	var r := await _auto_runner()
	var lo := r.loadout()
	lo.set_weapon(&"pistol", 3)
	lo.add_item(&"haste")
	r.announce(&"shotgun")
	r.announce(&"area")
	assert_eq(r.steer(lo), &"pistol")
	for k in 3:
		RunState.pick_rng.seed = 100 + k
		var offer := _open(r)
		assert_eq(offer.cards[0].id, &"pistol", "seed %d: the pistol's upgrade first" % k)
		game.pick_panel.choose(1)
		lo.set_weapon(&"pistol", 3)
	assert_true(r.evolve_hint().begins_with("pistol lv 3/6 + haste -> MINIGUN"), r.evolve_hint())
	lo.set_weapon(&"pistol", 6)
	assert_ne(r.steer(lo), &"pistol", "at the cap: EVOLVE instead (M50.4c2: a held Shotgun + Area may steer now)")
	assert_eq(r.evolve_hint(), "EVOLVE next level: pistol lv 6 + haste -> MINIGUN")
	lo.clear()


func test_evolve_ready_counts_and_its_cue_drops_after_the_evolution() -> void:
	var r := await _auto_runner()
	assert_eq(r.evolve_ready_count, 0)
	_ready_to_evolve(r)
	await wait_physics_frames(2)
	assert_eq(r.evolve_ready_count, 1)
	assert_gte(r.evolve_ready_t, 0.0)
	var c := Cue.parse("answer:path_auto evolve_ready 1: say happy: Glowing.")
	assert_eq(c.problem, "")
	assert_true(c.due({"evolve_ready": 1}))
	assert_true(c.expired({"evolved": 1}), "taken already: the line is stale")
	r.loadout().clear()


# --- The nerf -----------------------------------------------------------------------------------

func _evolved(r: PathRunner, haste := 1) -> Weapon:
	var lo := _ready_to_evolve(r, haste)
	var ev := r.evolve_option()
	r.want_pick()
	r._take_evolve(lo, ev)
	return lo.held(&"minigun")


func test_the_nerf_lands_after_game_time_and_writes_the_note() -> void:
	var r := await _auto_runner()
	var w := await _evolved(r)
	assert_true(r.arm_nerf(0.5))
	assert_false(r.arm_nerf(0.5), "one nerf")
	assert_eq(PathRunner.fire_rate(float(w.value(&"cooldown"))), 30.0, "too strong: 30/s")
	RunState.set_pause(PickPanel.PAUSE, true)
	await wait_physics_frames(60)
	assert_true(r.nerf_pending(), "the pause stops the clock")
	RunState.set_pause(PickPanel.PAUSE, false)
	await wait_physics_frames(40)
	assert_false(r.nerf_pending())
	assert_eq(w.launch, {})
	assert_eq(PathRunner.fire_rate(float(w.value(&"cooldown"))), 15.0)
	assert_eq(r.nerfs_landed, 1)
	assert_eq(String(r.nerf.text), "Balance: Minigun 30 -> 15 shots/s, damage 2 -> 1.5. It was too strong.")
	var notes := RunState.run_log.filter(func(e: Dictionary) -> bool: return e.get("event") == &"patch_note")
	assert_true(notes.any(func(e: Dictionary) -> bool: return e.text == r.nerf.text), "the note lands in the run log")
	assert_true(r.state_text().contains("evolved=minigun@"), r.state_text())
	r.loadout().clear()


func test_the_note_reads_the_effective_numbers() -> void:
	var r := await _auto_runner()
	await _evolved(r, 5)
	r.loadout().add_item(&"might")
	r.arm_nerf(0.1)
	await wait_physics_frames(10)
	assert_eq(String(r.nerf.text), "Balance: Minigun 30 -> 20 shots/s, damage 2.16 -> 1.62. It was too strong.")
	r.loadout().clear()


func test_stop_lands_a_pending_nerf_and_a_swap_drops_it() -> void:
	var r := await _auto_runner()
	await _evolved(r)
	r.arm_nerf(8.0)
	r.swap_now(&"auto")
	assert_false(r.nerf_pending(), "a path swap drops it")
	assert_eq(r.nerf, {})
	await _evolved(r)
	r.arm_nerf(8.0)
	r.stop()
	assert_false(r.nerf_pending())
	assert_gte(float(r.nerf.t_landed), 0.0, "the session ended inside the window: it still lands")
	assert_eq(r.nerfs_landed, 1)


# --- Grammar, conditions, recipes ----------------------------------------------------------------

func _cue_problems(cue: String, basics: Array[StringName] = [] as Array[StringName]) -> Array[String]:
	var s := SessionDef.new()
	s.id = &"x"
	s.path = &"fork:fork_path"
	s.weapons = [&"pistol"] as Array[StringName]
	s.basics = basics
	s.cues = PackedStringArray(["answer:path_auto at 0: add evolve", cue])
	return s._cue_problems("x") if s.has_method(&"_cue_problems") else s.problems()


func test_the_grammar_parses_and_checks() -> void:
	assert_eq(Cue.parse("answer:path_auto evolved 1: nerf 8").seconds, 8.0)
	assert_ne(Cue.parse("evolved 1: nerf").problem, "")
	assert_ne(Cue.parse("nerfed: say happy: Hi.").problem, "", "nerfed takes a number")
	var ok := _cue_problems("answer:path_auto evolved 1: nerf 8")
	assert_false(ok.any(func(p: String) -> bool: return "evolve" in p or "nerf" in p), str(ok))
	assert_true(_cue_problems("evolved 1: nerf 8").any(func(p: String) -> bool: return "answer:path_auto" in p))
	assert_true(_cue_problems("answer:path_auto at 9: nerf 8").any(func(p: String) -> bool: return "evolved n" in p))
	var s := SessionDef.new()
	s.id = &"y"
	s.path = &"fork:fork_path"
	s.weapons = [&"pistol"] as Array[StringName]
	s.cues = PackedStringArray(["answer:path_auto nerfed 1: say happy: Hi."])
	assert_true(s.problems().any(func(p: String) -> bool: return "evolve basic" in p))


func test_the_evolved_condition_reads_the_run_log() -> void:
	RunState.reset(0)
	var s := CampaignDB.get_session(&"s2_03_paint")
	assert_false(bool(CampaignDB.line_context(s).evolved))
	RunState.log_event(&"evolved", {"weapon": "minigun"})
	assert_true(bool(CampaignDB.line_context(s).evolved))
	assert_true(Line.condition_holds("evolved", CampaignDB.line_context(s)))


func test_s9_carries_the_evolution_beat() -> void:
	var s := CampaignDB.get_session(&"s2_03_paint")
	var src := Array(s.cues)
	for want: String in ["answer:path_auto at 84: add evolve", "answer:path_auto evolved 1: nerf 8",
			"answer:path_auto evolve_ready 1: say happy: It's glowing. Take EVOLVE.",
			"answer:path_auto nerfed 1: say guilty: Too strong. Patched it down live. Still good, promise."]:
		assert_true(want in src, want)
	assert_true("answer:path_auto&evolved proud: You evolved one. I only nerfed it a little." in Array(s.debrief))
	assert_eq(CampaignDB.problems(), [] as Array[String])
	assert_false(CampaignDB.get_session(&"s2_02_day_one").cues.has("answer:path_auto at 84: add evolve"), "no evolve in S8")


func test_evolutions_are_learned_and_listed_apart() -> void:
	SaveGame.go_inert()
	assert_true(SaveGame.learn_recipe(&"minigun"))
	assert_eq(PauseMenu.recipes_text(), "Evolutions: Minigun (pistol + haste)")
	SaveGame.learn_recipe(&"prism")
	assert_eq(PauseMenu.recipes_text(), "Recipes: Prism (shotgun + laser)\nEvolutions: Minigun (pistol + haste)")
	assert_false(PauseMenu.recipes_text().contains("Minigun ()"))
	var parsed: Variant = SaveGame.parse({"campaign": {"recipes": ["minigun", "bogus", "prism", "supernova"]}})
	assert_eq((parsed as Dictionary).campaign.recipes, ["minigun", "prism", "supernova"], "fusion and evolution ids")
	assert_eq(SaveGame.write(), ERR_UNAVAILABLE, "inert: nothing written")


func test_the_first_evolution_writes_a_recipe_note() -> void:
	SaveGame.go_inert()
	var r := await _auto_runner()
	await _evolved(r)
	var notes := RunState.run_log.filter(func(e: Dictionary) -> bool:
		return e.get("event") == &"patch_note" and String(e.text).begins_with("New recipe"))
	assert_eq(notes.size(), 1)
	assert_eq(String(notes[0].text), "New recipe: Minigun (pistol + haste)")
	r.loadout().clear()


# --- HUD and the card -----------------------------------------------------------------------------

func test_the_hud_and_the_rail_show_the_evolution() -> void:
	var r := await _auto_runner()
	_ready_to_evolve(r)
	await wait_process_frames(1)
	var widget := LevelWidget.new()
	var m := LevelMeter.new()
	m.def = _auto()
	widget.meter = m
	widget.loadout = r.loadout()
	widget.runner = r
	add_child_autofree(widget)
	await wait_process_frames(1)
	assert_lte(widget.custom_minimum_size.y, 60.0, "the hint row stays in the band")
	assert_true(widget.text().contains("EVOLVE next level: pistol lv 6 + haste -> MINIGUN"), widget.text())
	var items := RailState._items(r, r.loadout(), _auto())
	assert_eq(String(items.hint), "EVOLVE next level: pistol lv 6 + haste -> MINIGUN")
	await _evolved_from_ready(r)
	await wait_process_frames(1)
	assert_true(widget.text().contains("MINIGUN"), widget.text())
	items = RailState._items(r, r.loadout(), _auto())
	assert_true(bool(items.weapons[0].evo), "the rail's slot is an evolution")
	r.loadout().clear()


func _evolved_from_ready(r: PathRunner) -> void:
	r.want_pick()
	r._take_evolve(r.loadout(), r.evolve_option())


func test_the_evolve_card_data_and_both_looks_draw() -> void:
	var r := await _auto_runner()
	_ready_to_evolve(r)
	var d := LevelCard.data_for_evolve(r.evolve_option(), "4")
	assert_eq([d.kind, d.title, d.from_title, d.item_title, d.rank, d.icon], [LevelCard.KIND_EVOLVE, "Minigun", "Pistol", "Haste", 6, &"minigun"])
	assert_eq(String(d.effect), "fire rate x2.5, a sweeping stream", "pistol 6 (6/s) -> Minigun steady (15/s)")
	assert_true(Palette.has(&"card_evolve"))
	assert_ne(Palette.tier_0(&"card_evolve"), Color.MAGENTA)
	r.announce(&"shotgun")
	_open(r)
	await wait_process_frames(2)
	game.pick_panel.choose(0)
	Skins.use(Skins.pixel())
	for e in get_errors():
		if e.contains_text("Camera2D overridden to physics process mode"):
			e.handled = true
	_open(r)
	assert_true(game.pick_panel._cards_dressed[game.pick_panel._cards_dressed.size() - 1].pixel)
	await wait_process_frames(2)
	game.pick_panel.choose(0)
	r.loadout().clear()


func test_the_minigun_has_its_pictures() -> void:
	assert_true(&"minigun" in WeaponGlyph.KEYS)
	assert_true(CardArt.GUNS.has(&"minigun"))
	var grid: Array = CardArt.GUNS[&"minigun"][0]
	for row: String in grid:
		assert_eq(row.length(), String(grid[0]).length())
		for ch in row:
			assert_true(ch == "." or (CardArt.GUNS[&"minigun"][1] as Dictionary).has(ch), ch)
	for role: StringName in (CardArt.GUNS[&"minigun"][1] as Dictionary).values():
		assert_ne(CardArt.c(role), Color.MAGENTA, String(role))
	assert_true(Skins.pixel().has(&"shot_minigun_player"))
	assert_eq(Skins.shot_id(&"minigun", &"player"), &"shot_minigun_player")


# --- The bot ----------------------------------------------------------------------------------------

class _Panel:
	extends Node
	var offer: PickOffer


func test_auto_choice_takes_evolve_first_unless_probed() -> void:
	await _arena()
	var lo := Component.find(player, Loadout) as Loadout
	lo.apply_path(_auto())
	var p := _Panel.new()
	autofree(p)
	p.offer = PickOffer.new()
	p.offer.cards = [{"id": &"pistol", "rank": 2, "kind": &"upgrade"}, {"id": &"shotgun", "rank": 1, "kind": &"new"}] as Array[Dictionary]
	p.offer.evolve = {"from": &"pistol", "into": &"minigun", "catalyst": &"haste", "rank": 6, "text": ""}
	assert_eq(BotRuns.auto_choice(p, lo, "", 0), 2, "rule 1: EVOLVE")
	assert_eq(BotRuns.auto_choice(p, lo, "no_evolve", 1), 1, "no_evolve: the draw")
	assert_eq(BotRuns.auto_choice(p, lo, "random_picks", 0), 0)


# --- Caps -------------------------------------------------------------------------------------------

func test_minigun_at_launch_with_laser_and_nova_stays_in_the_budgets() -> void:
	var r := await _auto_runner()
	r.freeze()
	var lo := r.loadout()
	lo.set_weapon(&"laser", 6)
	lo.set_weapon(&"nova", 6)
	lo.add_item(&"haste")
	lo.evolve(&"pistol", &"minigun")
	var w := lo.held(&"minigun")
	w.launch = {&"cooldown": 0.033, &"damage": 2.0, &"pierce": 1}
	var points: Array = game.arena.spawn_points
	var most := 0
	for i in 600:   # 10 s at the cap
		var n := 0
		while RunState.count(&"enemy") + RunState.pending_count(&"enemy") < 57 and n < 8:
			var e := RunState.spawn(CHASER, points[(i + n) % points.size()]) as Node2D
			n += 1
		await wait_physics_frames(1)
		var mini := get_tree().get_nodes_in_group(&"player_projectile").filter(func(x: Node) -> bool:
			return x.get(&"weapon_id") == &"minigun").size()
		most = maxi(most, mini)
		assert_lte(RunState.count(&"player_projectile"), 140)
		assert_lte(RunState.count(&"enemy_projectile"), 60)
	gut.p("most live Minigun shots: %d, player refused %d" % [most, RunState.player_shots_refused])
	assert_lte(most, 25, "30/s x 0.8 s: about 24 live")
	assert_gt(most, 10, "the stream fired")
	assert_eq(RunState.enemy_shots_refused, 0)
	lo.clear()


func test_the_nerf_note_is_a_change_in_the_changelog() -> void:
	RunState.reset(0)
	RunState.log_event(&"patch_note", {"text": "Balance: Minigun 30 -> 15 shots/s, damage 2 -> 1.5. It was too strong."})
	var notes := DebriefScreen.changelog(CampaignDB.get_session(&"s2_03_paint"))
	assert_true("Minigun 30 -> 15 shots/s, damage 2 -> 1.5. It was too strong." in notes["Changed"], str(notes))
	assert_eq(TerminalPanel.note_text("Changed", "Minigun 30 -> 15 shots/s, damage 2 -> 1.5. It was too strong."),
			"  ~ Changed minigun 30 -> 15 shots/s, damage 2 -> 1.5. It was too strong.")
