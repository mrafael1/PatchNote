extends GutTest
## M50.1b (Arsenal depth design, .check/arsenal_depth/design.md, sections 4-8): the fusions
## (WeaponDB.fusions() / recipe(), Prism built, 5 unbuilt rows), FUSE (free: the same pack
## reopens for the new hand, nothing drawn), fused levels from the rank, a parent's card
## feeding the fusion, the link, Prism's centre-beam burn, the misfuse overlay, the cue
## grammar (fuse fail, fused, fuse_ready, the fused / misfused conditions), S9's timeline,
## the recipes in the save and the pause menu, and the bot's fusion rules.

const BotRuns := preload("res://tools/bot_runs.gd")
const BurnLineMod := preload("res://weapons/traits/burn_line_mod.gd")
const HandWidget := preload("res://paths/arsenal/hand_widget.gd")
const T := 48.0
const OPEN := Vector2(34, 20)

var game: Main
var player: CharacterBody2D


func after_each() -> void:
	RunState.invincible = false
	RunState.set_pause(PickPanel.PAUSE, false)
	RunState.session = null
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


## A deep-curve hand with no scene.
func _deep(ids: Array, ranks: Array = []) -> Loadout:
	var lo := Loadout.new()
	lo.apply_path(_arsenal())
	lo.slots.clear()
	for i in ids.size():
		lo.set_weapon(ids[i], ranks[i] if i < ranks.size() else 1)
	autofree(lo)
	return lo


## A runtime patch-note line in the run log.
func _noted(text: String) -> bool:
	for e: Dictionary in RunState.run_log:
		if e.get("event") == &"patch_note" and String(e.get("text")) == text:
			return true
	return false


## A session without the `fusion` basic (Unlocks reads RunState.session).
func _no_fusion_session() -> void:
	var s := SessionDef.new()
	s.basics = [&"movement", &"shooting", &"cards"] as Array[StringName]
	RunState.session = s


# --- Data -------------------------------------------------------------------------------------

func test_the_six_recipes_load_and_the_base_list_is_unchanged() -> void:
	var ids: Array[StringName] = []
	for f in WeaponDB.fusions():
		ids.append(f.id)
	assert_eq(ids, [&"black_moon", &"cluster", &"horizon", &"prism", &"pulse", &"satellite"] as Array[StringName])
	assert_false(&"prism" in WeaponDB.ids(), "ids() stays the base weapons")
	assert_true(WeaponDB.all().all(func(w: WeaponDef) -> bool: return not w.is_fusion()))
	assert_true(WeaponDB.has(&"prism") and WeaponDB.get_weapon(&"prism").is_fusion())
	assert_eq(WeaponDB.recipe(&"laser", &"shotgun"), &"prism", "either order")
	assert_eq(WeaponDB.recipe(&"shotgun", &"launcher"), &"cluster")
	assert_eq(WeaponDB.recipe(&"pistol", &"shotgun"), &"", "the misfuse pair has no recipe")
	assert_true(WeaponDB.fusion_built(&"prism"))
	for id: StringName in [&"cluster", &"satellite", &"pulse", &"horizon", &"black_moon"]:
		assert_false(WeaponDB.fusion_built(id), String(id))


func test_fusion_problems_mark_the_unbuilt_rows_and_check_inherits() -> void:
	var probs := WeaponDB.fusion_problems()
	assert_eq(probs.size(), 5, str(probs))
	for p in probs:
		assert_string_contains(p, "not built yet")
	assert_eq(WeaponDB.problems(), [] as Array[String], "the base weapons stay clean")
	var bad := (WeaponDB.get_weapon(&"prism").duplicate() as WeaponDef)
	bad.mechanics = [&"knockback_cone", &"point_blank", &"ricochet"] as Array[StringName]
	var lines := bad.problems()
	assert_true(lines.any(func(l: String) -> bool: return l.contains("no trait covers the inherited burn_line")), str(lines))


func test_fused_levels_come_from_the_rank() -> void:
	var prism := WeaponDB.get_weapon(&"prism")
	assert_eq(WeaponCurve.levels_of(prism, 1), [1, 1, 1, 1] as Array[int], "all 4 from rank 1")
	assert_eq(WeaponCurve.levels_of(prism, 5), [1, 1, 1, 1] as Array[int])
	assert_eq(WeaponCurve.levels_of(prism, 7), [2, 1, 1, 1] as Array[int])
	assert_eq(WeaponCurve.levels_of(prism, 9), [2, 2, 1, 1] as Array[int])
	var w := Weapon.new(prism, 5, WeaponCurve.DEEP)
	assert_eq(w.traits.size(), 4)
	assert_almost_eq(float(w.value(&"damage")), 1.2 * 2.0, 0.0001, "base x the odd-rank multiplier")
	assert_eq(int(w.value(&"pellets")), 5)


# --- FUSE -------------------------------------------------------------------------------------

func test_fuse_needs_a_built_recipe_with_both_at_rank_4() -> void:
	assert_true(BoosterPack.fuse_option(_deep([&"shotgun", &"laser"], [4, 3])).is_empty(), "laser below 4")
	assert_true(BoosterPack.fuse_option(_deep([&"pistol", &"shotgun"], [9, 9])).is_empty(), "no recipe")
	var f := BoosterPack.fuse_option(_deep([&"shotgun", &"laser"], [4, 5]))
	assert_eq(f.id, &"prism")
	assert_eq(int(f.rank), 5, "ceili((4 + 5) / 2.0)")
	assert_eq(f.title, "FUSE: Shotgun 4 + Laser 5 -> Prism 5")
	assert_eq((f.keeps as Array).size(), 4)
	assert_eq(f.loses, [] as Array[String], "no rank-6 mechanic held yet")
	var g := BoosterPack.fuse_option(_deep([&"shotgun", &"laser"], [6, 4]))
	assert_eq(g.loses, ["shrapnel"] as Array[String], "the shotgun's rank-6 mechanic goes")
	assert_string_contains(String(g.text), "loses: shrapnel")


func test_loadout_fuse_takes_the_active_slot_and_frees_one() -> void:
	var lo := _deep([&"shotgun", &"laser"], [4, 5])
	lo.active = 1
	lo.slots[0].shots = 3
	lo.slots[1].shots = 4
	assert_true(lo.fuse(&"shotgun", &"laser", &"prism", 5))
	assert_eq(lo.summary(), "prism:5")
	assert_eq(lo.active, 0)
	assert_eq(lo.current().shots, 7, "the parents' shots")
	assert_eq(lo.holder(&"shotgun"), lo.current(), "a parent's id finds the fusion")
	assert_null(lo.held(&"shotgun"))
	assert_false(lo.fuse(&"shotgun", &"laser", &"prism", 5), "nothing left to fuse")


func test_a_parent_card_feeds_the_fusion_and_never_shows_twice() -> void:
	var lo := _deep([&"shotgun", &"laser"], [4, 5])
	lo.fuse(&"shotgun", &"laser", &"prism", 5)
	var cands := BoosterPack.candidates(lo, [&"pistol", &"shotgun", &"laser"] as Array[StringName])
	assert_eq(cands.map(func(c: Dictionary) -> StringName: return c.id), [&"prism", &"pistol"], "parents fold")
	var c := BoosterPack.card(lo, BoosterPack.fold(lo, &"laser"), false)
	assert_eq(c.kind, &"upgrade")
	assert_eq(c.title, "Prism 5 -> 6")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 20:
		var o := BoosterPack.draw(lo, _arsenal(), [&"pistol", &"shotgun", &"laser"] as Array[StringName], {}, rng, null)
		var seen := {}
		for card: Dictionary in o.cards:
			var key := "%s/%s" % [card.id, card.rarity]
			assert_false(seen.has(key), "no (id, rarity) twice: %s" % key)
			seen[key] = true
			assert_false(card.id in [&"shotgun", &"laser"], "a parent is never its own card")


func test_g1_steers_to_the_lower_recipe_half() -> void:
	var lo := _deep([&"shotgun", &"laser"], [7, 3])
	lo.slots[0].shots = 50
	assert_eq(BoosterPack.recipe_low_half(lo), &"laser")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var o := BoosterPack.draw(lo, _arsenal(), [&"shotgun", &"laser"] as Array[StringName], {}, rng, null)
	assert_eq(o.cards[0].id, &"laser", "card 1: the lower half, not the most-fired")
	assert_eq(BoosterPack.recipe_low_half(_deep([&"shotgun", &"laser"], [4, 4])), &"", "both ready")


func test_fuse_reopens_the_same_pack_for_the_new_hand_with_nothing_drawn() -> void:
	var r := await _arena()
	var lo := _loadout()
	lo.slots.clear()
	lo.set_weapon(&"shotgun", 4)
	lo.set_weapon(&"laser", 5)
	lo.active = 0
	r.announce(&"shotgun")
	r.announce(&"laser")
	r.announce(&"pistol")
	var panel := game.pick_panel
	var picked := [0]
	var count := func(_o: PickOffer, _i: int) -> void: picked[0] += 1
	panel.picked.connect(count)
	r.want_pick()
	r._open_offer()
	assert_true(panel.has_fuse(), "FUSE offered")
	var n := panel.offer.cards.size()
	assert_string_contains(PickPanel.fuse_text(panel.offer, Callable(), false), "FUSE: Shotgun 4 + Laser 5 -> Prism 5")
	# M50.1b review: a fixed pack (the pistol NEW, both parents' cards), so the freed slot's
	# NEW card is always there to check.
	panel.offer.cards = [BoosterPack.card(lo, &"pistol", false), BoosterPack.card(lo, &"shotgun", false),
			BoosterPack.card(lo, &"laser", true)] as Array[Dictionary]
	assert_eq(panel.offer.cards.size(), n)
	assert_string_contains(String(panel.offer.cards[0].gain), "replaces a card", "a full hand before FUSE")
	var state := RunState.pack_rng.state
	panel.choose(n)
	assert_eq(lo.summary(), "prism:5", "fused, a slot freed")
	assert_true(panel.fusing(), "the fuse animation")
	assert_false(panel.can_choose())
	assert_true(RunState.is_paused_for(PickPanel.PAUSE), "the game stays paused")
	panel._process(PickPanel.FUSE_TIME + 0.01)   # real time (the tree is paused: no waiting here)
	assert_true(panel.is_open() and not panel.fusing(), "the same pack is back")
	assert_false(panel.has_fuse())
	assert_eq(RunState.pack_rng.state, state, "nothing drawn again")
	assert_eq(picked[0], 0, "FUSE is free: no pick yet")
	assert_eq(int(r.pack_picks.fuse), 1)
	assert_eq(r.fusions.size(), 1)
	assert_eq(r.fusions[0].from, ["shotgun:4", "laser:5"])
	var new_at := -1
	for i in panel.offer.cards.size():
		assert_ne(panel.offer.cards[i].id, &"shotgun")
		assert_ne(panel.offer.cards[i].id, &"laser")
		if panel.offer.cards[i].kind == &"new":
			new_at = i
	assert_eq(panel.offer.cards.map(func(c: Dictionary) -> String: return "%s/%s" % [c.id, c.rarity]),
			["pistol/common", "prism/common", "prism/rare"], "parents fold into the fusion")
	assert_eq(new_at, 0, "the pistol is still NEW")
	assert_string_contains(String(panel.offer.cards[new_at].gain), "joins your hand", "the freed slot")
	panel.choose(new_at)
	assert_eq(lo.slots.size(), 2, "the NEW card fills the freed slot")
	assert_eq(lo.summary(), "prism:5,pistol:1")
	assert_eq(picked[0], 1)
	assert_eq(SaveGame.recipes(), [&"prism"] as Array[StringName], "the recipe is learned")
	assert_true(_noted("New recipe: Prism"))
	panel.picked.disconnect(count)


## M50.1b review (finding 2): S9's 86 s hand is Pistol ~17 + Shotgun ~5 when the laser waits.
## A first play would let the low-rank shotgun go and dead-end the fusion; the replace step
## keeps the laser's partner, and only the other card can go.
func test_the_replace_step_keeps_the_new_cards_recipe_partner() -> void:
	var r := await _arena()
	var lo := _loadout()
	lo.slots.clear()
	lo.set_weapon(&"pistol", 17)
	lo.set_weapon(&"shotgun", 5)
	lo.active = 0
	r.announce(&"pistol")
	r.announce(&"shotgun")
	assert_true(r.give(&"laser", 3), "a full hand: the laser waits (G4)")
	r.want_pick()
	r._open_offer()
	var panel := game.pick_panel
	var offer := panel.offer
	var at := -1
	for i in offer.cards.size():
		if offer.cards[i].id == &"laser" and offer.cards[i].kind == &"new":
			at = i
	assert_gte(at, 0, "the waiting laser is in the pack")
	assert_eq(int(offer.cards[at].get("keep", -1)), 1, "the shotgun is its partner")
	panel.choose(at)
	assert_eq(panel.replacing(), at, "the replace step")
	assert_eq(panel.kept_slot(), 1)
	assert_eq(PickPanel.replace_text(offer, 1, Callable(), false, 1, "Laser"), "Keep Shotgun 5: it links with the Laser")
	assert_eq(PickPanel.replace_text(offer, 0, Callable(), false, 1, "Laser"), "Replace Pistol 17")
	assert_true(panel._buttons[1].disabled, "the partner is not a choice")
	assert_false(panel._buttons[0].disabled)
	assert_eq(BotRuns.pack_choice(panel, lo, "human"), 0, "the human probe: the lowest rank the step allows")
	panel.choose(1)
	assert_eq(panel.replacing(), at, "the partner cannot be replaced")
	assert_eq(lo.summary(), "pistol:17,shotgun:5")
	panel.choose(0)
	assert_eq(lo.summary(), "laser:3,shotgun:5", "the pistol went: a recipe pair")
	assert_eq(r.link_state(), 1, "the dim link")


func test_mark_keeps_only_for_one_built_partner_on_a_full_non_pair_hand() -> void:
	var cards := func(lo: Loadout, ids: Array) -> PickOffer:
		var o := PickOffer.new()
		o.pack = true
		for id: StringName in ids:
			o.cards.append(BoosterPack.card(lo, id, false))
		BoosterPack.mark_keeps(o, lo)
		return o
	var o1: PickOffer = cards.call(_deep([&"pistol", &"shotgun"], [9, 2]), [&"laser", &"launcher", &"pistol"])
	assert_eq(int(o1.cards[0].get("keep", -1)), 1, "laser: keep the shotgun")
	assert_false(o1.cards[1].has("keep"), "launcher: Cluster is unbuilt")
	assert_false(o1.cards[2].has("keep"), "an upgrade is never marked")
	var o2: PickOffer = cards.call(_deep([&"shotgun", &"laser"], [4, 2]), [&"pistol"])
	assert_false(o2.cards[0].has("keep"), "a recipe pair already: the choice stays free")
	var o3: PickOffer = cards.call(_deep([&"shotgun"], [4]), [&"laser"])
	assert_false(o3.cards[0].has("keep"), "room in the hand: no replace step")


## M50.1b review (finding 3): fused before the first-time `fuse_ready` line's gap ended:
## "The link's glowing" would be stale, so it is dropped; `fused 1` still speaks.
func test_a_fuse_ready_line_is_dropped_once_the_pair_was_fused() -> void:
	var r := await _arena()
	var s := SessionDef.new()
	s.id = &"x"
	s.cues = PackedStringArray(["fuse_ready 1: say happy: Lit.", "fused 1: say proud: A Prism!"])
	var runner := SessionRunner.new()
	runner.session = s
	runner.genre = game.genre
	runner.path_runner = r
	add_child_autofree(runner)
	runner.set_physics_process(false)
	runner._last_say = game.genre.session_clock()   # a line was just said: both wait SAY_GAP
	r.fuse_ready_count = 1
	runner._physics_process(0.0)
	assert_eq(runner.queued_lines().size(), 0, "both wait the gap")
	r.fusions.append({"id": "prism", "t": 0.0, "from": ["shotgun:4", "laser:4"], "rank": 4})
	runner._last_say = -1.0   # the gap is over
	runner._physics_process(0.0)
	assert_eq(runner.queued_lines().map(func(l: Line) -> String: return l.text), ["A Prism!"])
	assert_true(Cue.parse("fuse_ready 1: say x").expired({"fused": 1}))
	assert_false(Cue.parse("fuse_ready 2: say x").expired({"fused": 1}))


func test_no_link_and_no_fuse_before_the_fusion_basic() -> void:
	var r := await _arena()
	var lo := _loadout()
	lo.slots.clear()
	lo.set_weapon(&"shotgun", 4)
	lo.set_weapon(&"laser", 3)
	var w := r.widget()
	assert_eq(w.link_state(), 1, "dim: a recipe pair with a half below 4")
	lo.upgrade(&"laser")
	assert_eq(w.link_state(), 2, "lit: FUSE available")
	lo.slots[1] = Weapon.new(WeaponDB.get_weapon(&"pistol"), 9, WeaponCurve.DEEP)
	assert_eq(w.link_state(), 0, "never for a non-recipe pair")
	lo.slots[1] = Weapon.new(WeaponDB.get_weapon(&"laser"), 9, WeaponCurve.DEEP)
	_no_fusion_session()
	assert_false(r.fusion_live())
	assert_eq(w.link_state(), 0, "hidden before the basic")
	assert_true(r.fuse_option().is_empty(), "no FUSE before the basic")
	RunState.session = null
	SaveGame.state().settings.reduce_flashing = true
	assert_eq(w.link_glow(), 1.0, "steady under reduce_flashing")
	SaveGame.state().settings.reduce_flashing = false


func test_the_fuse_ready_count_and_the_lit_seconds() -> void:
	var r := await _arena()
	var lo := _loadout()
	lo.slots.clear()
	lo.set_weapon(&"shotgun", 4)
	lo.set_weapon(&"laser", 4)
	await wait_physics_frames(30)
	assert_eq(r.fuse_ready_count, 1)
	assert_gte(r.link_lit_ticks, 25)


# --- Prism ------------------------------------------------------------------------------------

func test_prism_burns_only_on_the_centre_beam() -> void:
	await _arena()
	var lo := _loadout()
	lo.slots.clear()
	lo.set_weapon(&"prism", 1)
	lo.active = 0
	var shots := lo.shooter().fire(lo.current(), Vector2.RIGHT)
	assert_eq(shots.size(), 5)
	var burning: Array[int] = []
	for i in shots.size():
		var p := shots[i] as Node
		if (p.call(&"mods") as Array).any(func(m: Object) -> bool: return m.get_script() == BurnLineMod):
			burning.append(i)
		assert_eq(p.get(&"weapon_id"), &"prism")
		assert_eq(p.get(&"pierce_left"), 2)
	assert_eq(burning, [2] as Array[int], "the centre beam only")
	# M50.1b review: end the shots while the world lives, so the centre beam's burn zone (added
	# deferred on despawn) lands in it and is freed with the game, not leaked at exit.
	for p in shots:
		p.queue_free()
	await wait_physics_frames(2)


# --- The misfuse ------------------------------------------------------------------------------

func test_the_misfuse_is_an_overlay_that_patches_itself() -> void:
	var r := await _arena()
	var lo := _loadout()
	lo.give(&"shotgun")
	var before := lo.summary()
	assert_true(r.fuse_fail())
	assert_true(r.misfusing())
	assert_true(r.widget().misfusing())
	assert_eq(r.widget().misfuse_title(), "Pistgun?")
	assert_false(r.can_open_now(), "no pack while it lasts")
	assert_false(lo.select_slot(1), "switching is locked")
	lo.switch(1)
	assert_eq(lo.active, 0)
	assert_eq(lo.summary(), before, "the Loadout is untouched")
	var dirs: Array[Vector2] = []
	var fired: Array[Node] = []
	var grab := func(p: Node) -> void: fired.append(p)
	EventBus.projectile_fired.connect(grab)
	for i in 4:
		lo.current().ready_in = 0.0
		assert_true(lo.try_fire(Vector2.RIGHT))
		var shot: Node2D = fired.back()
		assert_eq(shot.get(&"weapon_id"), &"pistol", "the active parent's shot")
		assert_eq(shot.get_node(^"Visual").get(&"skin_id"), PathRunner.MISFUSE_SKIN)
		dirs.append((shot.get(&"velocity") as Vector2).normalized().round())
	assert_eq(dirs, [Vector2.RIGHT, Vector2.UP, Vector2.RIGHT, Vector2.DOWN] as Array[Vector2], "straight, left, straight, right")
	EventBus.projectile_fired.disconnect(grab)
	assert_eq(Loadout.misfuse_turn(5), PI, "then backwards")
	# The pause stops it.
	RunState.set_pause(&"test", true)
	assert_false(r.can_process(), "paused: its clock stops")
	RunState.set_pause(&"test", false)
	await wait_physics_frames(roundi(PathRunner.MISFUSE_SECONDS * 60.0) + 2)
	assert_false(r.misfusing())
	assert_false(r.widget().misfusing())
	assert_true(bool(r.misfuse.restored))
	assert_eq(lo.summary(), before)
	assert_true(lo.select_slot(1), "switching again")
	assert_eq(lo.misfuse_skin, &"")
	assert_true(_noted(PathRunner.MISFUSE_NOTE))
	assert_string_contains(DebriefScreen.notes_text(CampaignDB.get_session(&"s2_03_paint")), PathRunner.MISFUSE_NOTE)
	# Merge (M47.5b): the terminal beat prints changelog(), so the fix is there too, under Fixed.
	var log := DebriefScreen.changelog(CampaignDB.get_session(&"s2_03_paint"))
	assert_has(log["Fixed"], "Cards fusing into a gun with guns on it.", "the terminal's changelog")
	assert_eq(TerminalPanel.note_text("Fixed", "Cards fusing into a gun with guns on it."),
			"  - Fixed cards fusing into a gun with guns on it.")


func test_the_misfuse_is_skipped_with_one_card() -> void:
	var r := await _arena()
	assert_false(r.fuse_fail())
	assert_true(RunState.run_log.any(func(e: Dictionary) -> bool: return e.get("event") == &"fuse_fail_skipped"))
	assert_false(CampaignDB.line_context(CampaignDB.get_session(&"s2_03_paint")).misfused)


# --- Grammar and data -------------------------------------------------------------------------

func test_the_fusion_cue_grammar_and_conditions() -> void:
	for src in ["answer:path_arsenal at 79: fuse fail", "fuse_ready 1: say happy: Lit.", "fused 1: say proud: Yes.",
			"answer:path_arsenal at 82: say misfused surprised: Sideways."]:
		var c := Cue.parse(src)
		assert_eq(c.problem, "", src)
	assert_ne(Cue.parse("at 3: fuse now").problem, "")
	for bad in ["at 3: fuse", "at 3: fuse fail x", "fused 0: say x", "fuse_ready: say x", "fused: say x",
			"fuse_ready 1.5: say x"]:
		assert_ne(Cue.parse(bad).problem, "", bad)
	var c2 := Cue.parse("fused 2: say proud: Two.")
	assert_false(c2.due({"fused": 1}))
	assert_true(c2.due({"fused": 2}))
	assert_true(Cue.parse("fuse_ready 1: say x").due({"fuse_ready": 1}))
	assert_true(Line.condition_holds("answer:path_arsenal&fused", {"shipped": [&"path_arsenal"], "fused": true}))
	assert_false(Line.condition_holds("answer:path_arsenal&fused", {"shipped": [&"path_arsenal"], "fused": false}))
	assert_eq(Line.parse("misfused guilty: Undoing.").when, &"misfused")


## M50.1b review (finding 5): a fusion cue that can never fire does not validate.
func test_session_problems_gate_the_fusion_cues_and_lines() -> void:
	# The parse is cached per SessionDef: a fresh one per case.
	var probs := func(cues: Array, fork := false, intro: Array = [], debrief: Array = []) -> String:
		var s := SessionDef.new()
		s.id = &"x"
		s.goal = SessionDef.SURVIVE
		s.goal_value = 100.0
		if fork:
			s.path = &"fork:fork_path"
		s.cues = PackedStringArray(cues)
		s.intro = PackedStringArray(intro)
		s.debrief = PackedStringArray(debrief)
		return str(s.problems())
	assert_string_contains(probs.call(["fused 1: say proud: x"]), "fused needs the fusion basic")
	assert_string_contains(probs.call(["fuse_ready 1: say happy: x"]), "fuse_ready needs the fusion basic")
	assert_string_contains(probs.call(["at 3: fuse fail"]), "fuse needs the cards basic")
	var adds := ["answer:path_arsenal at 0: add cards", "answer:path_arsenal at 0: add fusion"]
	var p: String = probs.call(adds + ["at 3: fuse fail", "fused 1: say proud: x"], true)
	assert_eq(p.count("a fusion cue needs answer:path_arsenal"), 2, p)
	assert_true("at 3: fuse fail" in p and "fused 1: say proud: x" in p, p)
	var ok: String = probs.call(adds + ["answer:path_arsenal at 3: fuse fail", "answer:path_arsenal fused 1: say proud: x",
			"answer:path_arsenal fuse_ready 1: say happy: x"], true)
	assert_false("fusion" in ok or "fuse" in ok, ok)
	assert_string_contains(probs.call(adds, true, ["fused proud: x"]), "an intro line cannot depend on a fusion")
	assert_string_contains(probs.call(adds, true, ["!misfused happy: x"]), "an intro line cannot depend on a fusion")
	var deb: String = probs.call(adds, true, [], ["answer:path_arsenal&fused proud: x"])
	assert_false("fusion" in deb, "a debrief may read it: " + deb)


func test_s9_plays_the_fusion_beats_on_arsenal_only() -> void:
	var s := CampaignDB.get_session(&"s2_03_paint")
	var src := Array(s.cues)
	for want in ["answer:path_arsenal at 79: fuse fail", "answer:path_arsenal at 86: give laser 3", "answer:path_arsenal at 11: give shotgun 3",
			"answer:path_arsenal at 94: add fusion", "!answer:path_arsenal at 80: give laser"]:
		assert_true(want in src, want)
	assert_eq(CampaignDB.problems(), [] as Array[String])
	var ctx := {"shipped": [&"path_survival"]}
	var kept := s.cue_list().filter(func(c: Cue) -> bool: return Line.condition_holds(c.cond, ctx))
	assert_true(kept.any(func(c: Cue) -> bool: return c.action == &"give" and c.target == &"laser" and c.rank == 1),
			"Survival keeps the shared laser at 80")
	assert_false(kept.any(func(c: Cue) -> bool: return c.action in [&"fuse"] or c.target == &"fusion"))


# --- The save and the pause menu --------------------------------------------------------------

func test_recipes_are_saved_as_knowledge_with_a_migration() -> void:
	SaveGame.go_inert()
	assert_eq(SaveGame.recipes(), [] as Array[StringName], "a save without the key knows none")
	assert_false(SaveGame.campaign().has("recipes"), "a new save is unchanged")
	assert_eq(PauseMenu.recipes_text(), "")
	assert_true(SaveGame.learn_recipe(&"prism"))
	assert_false(SaveGame.learn_recipe(&"prism"), "once")
	assert_eq(PauseMenu.recipes_text(), "Recipes: Prism (shotgun + laser)")
	assert_eq(SaveGame.write(), ERR_UNAVAILABLE, "inert: nothing written")
	var parsed: Variant = SaveGame.parse({"campaign": {"recipes": ["prism", "bogus", "prism", "pistol"]}})
	assert_eq((parsed as Dictionary).campaign.recipes, ["prism"], "fusion ids only, once")
	var old: Variant = SaveGame.parse({"campaign": {"index": 3}})
	assert_false((old as Dictionary).campaign.has("recipes"), "an older file: none known")
	assert_null(SaveGame.parse({"campaign": {"recipes": "prism"}}), "a wrong type")


# --- The bot ----------------------------------------------------------------------------------

func test_the_bot_fuses_then_chooses_again() -> void:
	var r := await _arena()
	var lo := _loadout()
	lo.slots.clear()
	lo.set_weapon(&"shotgun", 4)
	lo.set_weapon(&"laser", 4)
	r.announce(&"shotgun")
	r.announce(&"laser")
	r.want_pick()
	r._open_offer()
	var panel := game.pick_panel
	assert_eq(BotRuns.pack_choice(panel, lo, ""), panel.offer.cards.size(), "(1) FUSE first")
	assert_ne(BotRuns.pack_choice(panel, lo, "no_fuse"), panel.offer.cards.size(), "no_fuse")
	lo.slots[1] = Weapon.new(WeaponDB.get_weapon(&"laser"), 3, WeaponCurve.DEEP)
	panel.offer.cards = [BoosterPack.card(lo, &"shotgun", true), BoosterPack.card(lo, &"laser", false)] as Array[Dictionary]
	panel.offer.fuse = {}
	assert_eq(BotRuns.pack_choice(panel, lo, ""), 1, "(2) the lower recipe half before a rare card")
	panel.dismiss()
