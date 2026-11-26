extends GutTest
## M50.6 (stacked packs and weapon rarity, owner asks of 2026-11-26): a booster pack no longer
## opens by itself. It joins a stack; the `open_pack` action opens the top one (the same panel,
## the same pause), one at a time. The HUD shows the count and the key, the AI says the key at
## the first pack and nudges once at Tuning.pack_nudge_at. Unopened packs wait in the save
## (the sparse campaign key `packs`). Every card is +1; a card's tier is its weapon's `rarity`
## (common / rare / epic); held weapons weigh more; an epic card is a ready-made fusion (rank
## 4 at least, never card 1, one a pack, both parents available) that melts a held parent.
## The bot asks every tick, so a seed replays.

const PackMeter := preload("res://paths/arsenal/pack_meter.gd")
const HandWidget := preload("res://paths/arsenal/hand_widget.gd")
const RailState := preload("res://ui/rail/rail_state.gd")
const BotRuns := preload("res://tools/bot_runs.gd")
const Fixtures := preload("res://tests/gut/fixtures.gd")
const T := 48.0
const OPEN := Vector2(34, 20)
const TEST_LOG := "user://save_pack_stack_test/runs.jsonl"

var game: Main
var player: CharacterBody2D


func before_each() -> void:
	Telemetry.log_path = TEST_LOG


func after_each() -> void:
	Input.action_release(&"open_pack")
	await wait_physics_frames(2)
	assert_false(FileAccess.file_exists(TEST_LOG), "no telemetry written")
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.invincible = false
	RunState.set_pause(PickPanel.PAUSE, false)
	RunState.session = null
	CampaignDB.active = false
	SaveGame.go_inert()
	Main.next_seed = -1
	RunState.reset(0)
	RunState.world = null


func _arsenal() -> PathDef:
	return PathDB.get_def(&"arsenal")


## The legacy arena on Arsenal through F2 (outside a session every basic is on). The input is
## a ScriptedInput that never asks for a pack, unless `input` is given.
func _arena(run_seed := -1, input: PlayerInput = null) -> PathRunner:
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
	player.set_input(input if input != null else Fixtures.ScriptedInput.new())
	await wait_physics_frames(1)
	player.global_position = OPEN * T
	player.velocity = Vector2.ZERO
	RunState.invincible = true
	assert_true(game.debug.switch_path(&"arsenal"))
	game.pick_panel.input_delay = 0.0
	await wait_physics_frames(1)
	# Three weapons in the pool: a pack is a real choice (a 1-card pack is M50.2a's toast).
	game.path_runner.announce(&"shotgun")
	game.path_runner.announce(&"laser")
	return game.path_runner


func _loadout() -> Loadout:
	return Component.find(player, Loadout) as Loadout


## A deep-curve loadout with no scene (pure draws).
func _deep(ids: Array, ranks: Array = []) -> Loadout:
	var lo := Loadout.new()
	lo.apply_path(_arsenal())
	lo.slots.clear()
	for i in ids.size():
		lo.set_weapon(ids[i], ranks[i] if i < ranks.size() else 1)
	autofree(lo)
	return lo


func _kill(runner: PathRunner, n: int) -> void:
	for i in n:
		runner._on_enemy_killed(null, DamageInfo.make(1.0, &"projectile", &"player"))


func _rng(s := 7) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _pool(ids: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(ids)
	return out


# --- 1. The stack ----------------------------------------------------------------------------

func test_a_pack_joins_the_stack_and_never_opens_by_itself() -> void:
	var r := await _arena()
	var panel := game.pick_panel
	var state := RunState.pack_rng.state
	_kill(r, _arsenal().pack_every)
	assert_eq(r.pack_stack(), 1, "six kills: one pack on the stack")
	_kill(r, _arsenal().pack_every * 2)
	assert_eq(r.pack_stack(), 3, "eighteen kills: three")
	assert_eq(r.stack_peak, 3)
	await wait_physics_frames(roundi(PathRunner.PACK_GAP * 60.0) + 60)
	assert_false(panel.is_open(), "no pack opened by itself")
	assert_false(RunState.is_paused_for(PickPanel.PAUSE), "the game never paused")
	assert_eq(r.packs_opened, 0)
	assert_eq(r.offers.size(), 0)
	assert_eq(RunState.pack_rng.state, state, "nothing drawn until a pack opens")
	assert_eq(r.pack_stack(), 3, "all three still wait")


func test_the_open_action_opens_one_pack_and_pauses_and_no_other_follows() -> void:
	var r := await _arena()
	var panel := game.pick_panel
	_kill(r, _arsenal().pack_every * 2)
	assert_eq(r.pack_stack(), 2)
	player.input.open_pack_pressed = true   # the key
	await wait_physics_frames(2)
	player.input.open_pack_pressed = false
	await wait_physics_frames(2)
	assert_true(panel.is_open(), "the top pack opened")
	assert_true(panel.offer.pack and not panel.offer.give_step, "the usual pack panel")
	assert_true(RunState.is_paused_for(PickPanel.PAUSE), "with the usual pause")
	assert_eq(r.packs_opened, 1)
	assert_eq(r.pack_stack(), 2, "the open pack is still on the stack until a card is taken")
	panel.choose(0)
	await wait_physics_frames(2)
	assert_false(panel.is_open())
	assert_eq(r.pack_stack(), 1, "one pack left")
	await wait_physics_frames(roundi(PathRunner.PACK_GAP * 60.0) + 60)
	assert_false(panel.is_open(), "the next pack does not chain-open")
	assert_eq(r.packs_opened, 1)
	assert_true(r.open_pack(), "asked again (the API the key uses)")
	await wait_physics_frames(2)
	assert_true(panel.is_open(), "the second pack")
	panel.choose(0)
	await wait_physics_frames(2)
	assert_eq(r.pack_stack(), 0)
	assert_false(r.open_pack(), "nothing stacked: nothing to open")


func test_the_open_pack_action_exists_and_the_human_input_reads_it() -> void:
	assert_true(InputMap.has_action(&"open_pack"), "a real input action")
	assert_true(InputSetup.ACTIONS.has(&"open_pack"), "listed for the options screen")
	assert_ne(PathRunner.open_key(), "", "it has a key")
	assert_false(PathRunner.open_key().contains("{"), "expanded: %s" % PathRunner.open_key())
	var r := await _arena(-1, HumanInput.new())
	var panel := game.pick_panel
	_kill(r, _arsenal().pack_every)
	await wait_physics_frames(30)
	assert_false(panel.is_open(), "not pressed: closed")
	# Pressed at the start of a physics tick, so that tick reads it as just pressed.
	get_tree().physics_frame.connect(func() -> void: Input.action_press(&"open_pack"), CONNECT_ONE_SHOT)
	await wait_physics_frames(4)
	Input.action_release(&"open_pack")
	assert_true(panel.is_open(), "the key opens the pack")
	panel.choose(0)


func test_a_held_key_opens_no_second_pack_and_a_closed_gate_opens_none() -> void:
	var r := await _arena()
	_kill(r, _arsenal().pack_every)
	RunState.set_pause(&"test_gate", true)
	assert_false(r.open_pack(), "another pause holds the pack")
	RunState.set_pause(&"test_gate", false)
	assert_true(r.open_pack())
	await wait_physics_frames(2)
	assert_true(game.pick_panel.is_open())
	assert_false(r.open_pack(), "never a second panel over the first")
	game.pick_panel.choose(0)


func test_the_stack_has_a_cap_and_non_pack_paths_keep_opening_by_themselves() -> void:
	var r := await _arena()
	r._want = Tuning.pack_stack_max
	r.want_pick()
	assert_eq(r.pack_stack(), Tuning.pack_stack_max, "capped")
	r._want = 0
	assert_true(game.debug.switch_path(&"auto"))
	await wait_physics_frames(2)
	assert_false(r.pack_path())
	assert_eq(r.pack_stack(), 0, "no stack off a pack path")
	r.want_pick()
	await wait_physics_frames(3)
	assert_true(game.pick_panel.is_open(), "a level-up still opens by itself")
	game.pick_panel.choose(0)


# --- 2. The HUD and the AI's lines ------------------------------------------------------------

func test_the_hud_shows_the_count_and_the_key() -> void:
	var r := await _arena()
	var w := r.widget() as HandWidget
	assert_eq([w.stack_count(), w.stack_text(), w.stack_hint()], [0, "", ""], "nothing stacked: nothing shown")
	var d0 := RailState._pack(r, _arsenal())
	assert_eq([int(d0.stack), String(d0.key)], [0, PathRunner.open_key()])
	_kill(r, _arsenal().pack_every)
	assert_eq(w.stack_text(), "1 pack")
	_kill(r, _arsenal().pack_every)
	assert_eq(w.stack_text(), "2 packs")
	assert_eq(w.stack_hint(), "[%s] open" % PathRunner.open_key())
	assert_string_contains(w.text(), "2 packs [%s] open" % PathRunner.open_key())
	var d := RailState._pack(r, _arsenal())
	assert_eq(int(d.stack), 2, "the rail's pack module reads the stack")
	assert_true(d.on)


func test_the_ai_teaches_the_key_at_the_first_pack_and_nudges_once_at_three() -> void:
	var r := await _arena()
	var def := _arsenal()
	var key := PathRunner.open_key()
	assert_eq(Tuning.pack_nudge_at, 3)
	_kill(r, def.pack_every)
	assert_eq(r.said, ["A pack! %s opens it. No rush." % key] as Array[String], "the first pack: the key")
	_kill(r, def.pack_every)
	assert_eq(r.said.size(), 1, "two stacked: quiet")
	_kill(r, def.pack_every)
	assert_eq(r.said[1], "Three packs waiting. %s opens one." % key, "three stacked: the nudge")
	_kill(r, def.pack_every * 3)
	assert_eq(r.said.size(), 2, "only once")
	r.open_pack()
	await wait_physics_frames(2)
	game.pick_panel.choose(0)
	await wait_physics_frames(2)
	r._want = 2
	_kill(r, def.pack_every)
	assert_eq(r.said.size(), 2, "back at three: still once a session")
	assert_true(def.problems().is_empty(), str(def.problems()))


# --- 3. The save ------------------------------------------------------------------------------

func _session(id: StringName) -> PathRunner:
	assert_true(CampaignDB.answer_fork(&"fork_path", &"path_arsenal"))
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	if game.stage_card != null:
		game.stage_card.skip()
	await wait_physics_frames(3)
	player = game.player
	RunState.invincible = true
	return game.path_runner


func test_unopened_packs_wait_in_the_save_for_the_next_session() -> void:
	SaveGame.go_inert()
	assert_eq(SaveGame.packs_banked(), 0)
	assert_false(SaveGame.campaign().has("packs"), "a new save has no key")
	var r := await _session(&"s2_02_day_one")
	game.run_loop.goal_clock = 11.0   # S8 adds the cards at 10 s
	await wait_physics_frames(3)
	assert_true(r.pack_path(), "S8 on Arsenal")
	assert_eq(r.packs_carried, 0)
	_kill(r, _arsenal().pack_every * 2)
	assert_eq(r.pack_stack(), 2)
	r.stop()
	assert_eq(r.pack_stack(), 2, "the session's end keeps the stack")
	r.bank_packs()
	assert_eq(SaveGame.packs_banked(), 2, "banked when the player moves on")
	game.free()
	RunState.session = null
	var r2 := await _session(&"s2_03_paint")
	assert_eq(r2.packs_carried, 2)
	assert_eq(r2.pack_stack(), 2, "S9 starts with the two packs")
	assert_eq((r2.widget() as HandWidget).stack_text(), "2 packs")
	assert_true(r2.open_pack())
	await wait_physics_frames(2)
	if game.pick_panel.is_open():   # (a 1-card pack is a toast: no panel)
		game.pick_panel.choose(0)
	await wait_physics_frames(2)
	assert_eq(r2.packs_opened, 1, "a carried pack opens like any other")
	assert_eq(r2.pack_stack(), 1)
	r2.bank_packs()
	assert_eq(SaveGame.packs_banked(), 1, "the bank follows what is left")
	assert_eq(SaveGame.write(), ERR_UNAVAILABLE, "inert: nothing written")


func test_the_tryout_banks_nothing_and_an_old_save_loads() -> void:
	SaveGame.go_inert()
	SaveGame.bank_packs(4)
	assert_eq(SaveGame.packs_banked(), 4)
	SaveGame.bank_packs(1000)
	assert_eq(SaveGame.packs_banked(), SaveGame.PACKS_MAX, "capped")
	assert_eq(SaveGame.PACKS_MAX, Tuning.pack_stack_max)
	# The parser: an old file (no key) loads with none; a good value is kept; a bad one fails.
	var old: Variant = SaveGame.parse({"campaign": {"index": 3}})
	assert_not_null(old, "a save from before M50.6 loads")
	assert_false((old as Dictionary).campaign.has("packs"), "and holds no packs")
	var with: Variant = SaveGame.parse({"campaign": {"index": 3, "packs": 5}})
	assert_eq(int((with as Dictionary).campaign.packs), 5)
	var big: Variant = SaveGame.parse({"campaign": {"packs": 5000}})
	assert_eq(int((big as Dictionary).campaign.packs), SaveGame.PACKS_MAX)
	assert_null(SaveGame.parse({"campaign": {"packs": "3"}}), "a wrong type")
	assert_null(SaveGame.parse({"campaign": {"packs": -1}}), "a negative count")
	# Outside a session nothing is banked or carried.
	SaveGame.go_inert()
	SaveGame.bank_packs(3)
	var r := await _arena()
	assert_eq(r.packs_carried, 0, "the arena carries none")
	assert_eq(r.pack_stack(), 0)
	_kill(r, _arsenal().pack_every)
	r.bank_packs()
	assert_eq(SaveGame.packs_banked(), 3, "and banks none")


# --- 4. Every card is +1; the tier is the weapon's --------------------------------------------

func test_rarity_is_weapon_data() -> void:
	var tiers := {}
	for id: StringName in [&"pistol", &"shotgun", &"launcher", &"laser", &"nova", &"well", &"orbit"]:
		tiers[id] = WeaponDB.get_weapon(id).rarity
	assert_eq(tiers, {&"pistol": &"common", &"shotgun": &"common", &"launcher": &"common",
			&"laser": &"rare", &"nova": &"rare", &"well": &"rare", &"orbit": &"rare"})
	assert_gt(WeaponDB.fusions().size(), 0)
	for f in WeaponDB.fusions():
		assert_eq(f.rarity, &"epic", "%s: a fusion is epic" % f.id)
	for d in WeaponDB.all():
		assert_true(d.rarity in WeaponDef.RARITIES, String(d.id))
		assert_eq(d.rarity == &"epic", d.is_fusion(), "%s: epic means fusion" % d.id)
	var bad := WeaponDB.get_weapon(&"pistol").duplicate() as WeaponDef
	bad.rarity = &"mythic"
	assert_string_contains(str(bad.problems()), "rarity")
	bad.rarity = &"epic"
	assert_string_contains(str(bad.problems()), "epic")


func test_every_card_is_plus_one_and_carries_its_weapons_tier() -> void:
	var lo := _deep([&"pistol", &"laser"], [3, 5])
	var p := BoosterPack.card(lo, &"pistol")
	var l := BoosterPack.card(lo, &"laser")
	assert_eq([int(p.from), int(p.rank), p.rarity, p.kind], [3, 4, &"common", &"upgrade"])
	assert_eq([int(l.from), int(l.rank), l.rarity, l.kind], [5, 6, &"rare", &"upgrade"], "a rare card: +1, never +2")
	var n := BoosterPack.card(_deep([&"pistol"]), &"laser")
	assert_eq([int(n.from), int(n.rank), n.rarity, n.kind], [0, 1, &"rare", &"new"], "a new rare card joins at rank 1")
	assert_eq([BoosterPack.tags(p), BoosterPack.tags(l), BoosterPack.tags(n)], ["COMMON", "RARE", "NEW  RARE"])
	# Many packs: no card ever gives more than +1 and its tier is always the weapon's.
	var pool := _pool([&"pistol", &"shotgun", &"launcher", &"laser"])
	var rng := _rng(11)
	var seen := {}
	for i in 300:
		var hand := _deep([&"pistol", &"laser"], [1 + i % 7, 1 + i % 5])
		var o := BoosterPack.draw(hand, _arsenal(), pool, {}, rng, null)
		for c: Dictionary in o.cards:
			assert_eq(int(c.rank), int(c.from) + 1, "%s: +1" % c.title)
			assert_eq(c.rarity, WeaponDB.get_weapon(c.id).rarity, "%s: the weapon's tier" % c.id)
			seen[c.rarity] = true
	assert_true(seen.has(&"common") and seen.has(&"rare"), "both tiers seen")
	# Taking a rare upgrade in the arena: one rank.
	var r := await _arena()
	var real := _loadout()
	real.slots.clear()
	real.set_weapon(&"pistol", 2)
	real.set_weapon(&"laser", 2)
	r._want = 1
	r._take_pack_card(real, BoosterPack.card(real, &"laser"))
	assert_eq(real.summary(), "pistol:2,laser:3")
	assert_eq(int(r.pack_picks.rare), 1, "counted as a rare card taken")


func test_the_ribbon_is_the_tier_and_never_rare_plus_two() -> void:
	var lo := _deep([&"pistol", &"laser"], [3, 5])
	var common := CardFace.face_of(BoosterPack.card(lo, &"pistol"), "[1]")
	var rare := CardFace.face_of(BoosterPack.card(lo, &"laser"), "[2]")
	var fresh := CardFace.face_of(BoosterPack.card(_deep([&"pistol"]), &"laser"), "[2]")
	var epic := CardFace.face_of(BoosterPack.epic_card(_deep([&"pistol", &"shotgun"]), &"prism"), "[3]")
	assert_eq([common.ribbon, rare.ribbon, fresh.ribbon, epic.ribbon], ["COMMON", "RARE", "RARE", "EPIC"])
	assert_eq([common.style, rare.style, fresh.style, epic.style],
			[&"card_common", &"card_rare", &"card_rare", &"card_epic"], "the frame follows the tier")
	assert_eq(fresh.tag, "NEW", "a new card says so next to its tier")
	for f: Dictionary in [common, rare, fresh, epic]:
		assert_false(String(f.ribbon).contains("+2"))
	assert_ne(Palette.CARD_EPIC, Palette.CARD_RARE, "a third frame colour")


# --- 5. The weights ---------------------------------------------------------------------------

func test_held_weapons_weigh_double_and_rare_ones_half() -> void:
	assert_eq(Tuning.pack_held_weight, 2.0)
	assert_eq(Tuning.pack_rare_weight, 0.5)
	var lo := _deep([&"pistol"])
	var cands := BoosterPack.candidates(lo, _pool([&"pistol", &"launcher", &"laser"]))
	assert_eq(cands.map(func(c: Dictionary) -> Array: return [c.id, c.kind, c.rarity]),
			[[&"pistol", &"upgrade", &"common"], [&"launcher", &"new", &"common"], [&"laser", &"new", &"rare"]])
	# Weights 2 : 1 : 0.5 of 3.5.
	assert_eq(BoosterPack.weighted(cands, 0.0, null), 0)
	assert_eq(BoosterPack.weighted(cands, 1.99 / 3.5, null), 0, "the held card's share is 2 of 3.5")
	assert_eq(BoosterPack.weighted(cands, 2.01 / 3.5, null), 1)
	assert_eq(BoosterPack.weighted(cands, 2.99 / 3.5, null), 1)
	assert_eq(BoosterPack.weighted(cands, 3.01 / 3.5, null), 2, "the rare card's share is 0.5 of 3.5")
	# A held rare card: 2 x 0.5 = 1, the same as a new common one.
	var both := BoosterPack.candidates(_deep([&"laser"]), _pool([&"laser", &"launcher"]))
	assert_eq(BoosterPack.weighted(both, 0.49, null), 0)
	assert_eq(BoosterPack.weighted(both, 0.51, null), 1)
	# In whole packs: card 1 is always held, and card 3 is the held shotgun more often than a
	# given new common card.
	var hand := _deep([&"pistol", &"shotgun"], [1, 1])
	hand.max_slots = 4   # room: the new cards are plain NEW cards
	var pool := _pool([&"pistol", &"shotgun", &"launcher", &"laser", &"nova"])
	var rng := _rng(5)
	var third := {}
	for i in 2000:
		hand.slots[0].shots = 5   # the pistol is card 1
		var o := BoosterPack.draw(hand, _arsenal(), pool, {}, rng, null)
		assert_eq(o.cards[0].kind, &"upgrade", "card 1 is always a held weapon")
		assert_eq(o.cards[0].id, &"pistol")
		third[o.cards[2].id] = int(third.get(o.cards[2].id, 0)) + 1
	assert_gt(int(third.get(&"shotgun", 0)), 1000, "card 3 favours the held weapon: %s" % str(third))


# --- 6. Epic cards ----------------------------------------------------------------------------

func test_an_epic_needs_both_parents_available_and_no_fusion_held() -> void:
	var lo := _deep([&"pistol", &"shotgun"])
	assert_eq(BoosterPack.epic_ids(lo, _pool([&"pistol", &"shotgun", &"laser"])), [&"prism"] as Array[StringName],
			"shotgun held, laser in the pool")
	assert_eq(BoosterPack.epic_ids(lo, _pool([&"pistol", &"shotgun"])), [] as Array[StringName], "no laser anywhere: no Prism")
	assert_eq(BoosterPack.epic_ids(lo, _pool([&"pistol", &"shotgun", &"laser", &"launcher"])),
			[&"cluster", &"prism"] as Array[StringName], "sorted by id")
	assert_eq(BoosterPack.epic_ids(_deep([&"pistol"]), _pool([&"pistol", &"laser"])), [] as Array[StringName],
			"the shotgun is neither held nor in the pool")
	assert_eq(BoosterPack.epic_ids(_deep([&"shotgun", &"laser"]), _pool([])), [&"prism"] as Array[StringName], "both held")
	var holds := _deep([&"prism", &"pistol"], [4, 1])
	assert_false(&"prism" in BoosterPack.epic_ids(holds, _pool([&"pistol", &"shotgun", &"laser", &"launcher"])),
			"never a fusion the hand already holds")
	for id in BoosterPack.epic_ids(lo, _pool([&"pistol", &"shotgun", &"laser", &"launcher", &"nova", &"well", &"orbit"])):
		assert_true(WeaponDB.fusion_built(id), "%s: only built fusions" % id)


func test_a_pack_shows_one_epic_at_most_never_first_and_at_about_five_percent() -> void:
	var def := _arsenal()
	assert_almost_eq(def.epic_chance, 0.05, 0.0001)
	var pool := _pool([&"pistol", &"shotgun", &"laser", &"launcher"])
	# The real chance.
	var rng := _rng(3)
	var with_epic := 0
	for i in 4000:
		var o := BoosterPack.draw(_deep([&"pistol", &"shotgun"], [2, 2]), def, pool, {}, rng, null, true)
		var n := o.cards.filter(BoosterPack.is_epic).size()
		assert_lt(n, 2, "one epic a pack at most")
		assert_false(BoosterPack.is_epic(o.cards[0]), "card 1 is never epic")
		with_epic += n
	# Two slots at 5 %, the second only when the first showed none: 9.75 % of packs.
	assert_between(with_epic, 300, 480, "about 5 %% a slot: %d of 4000 packs" % with_epic)
	# A forced chance: still one a pack, never first, rank 4 at least, and none without `epics`.
	var loud := def.duplicate() as PathDef
	loud.epic_chance = 0.95
	var state := 0
	for i in 200:
		var lo := _deep([&"pistol", &"shotgun"], [1 + i % 9, 1 + i % 6])
		var o := BoosterPack.draw(lo, loud, pool, {}, rng, null, true)
		var epics := o.cards.filter(BoosterPack.is_epic)
		assert_lt(epics.size(), 2)
		assert_false(BoosterPack.is_epic(o.cards[0]))
		state += epics.size()
		for c: Dictionary in epics:
			assert_gte(int(c.rank), BoosterPack.FUSE_RANK, c.title)
			assert_true(c.id in [&"prism", &"cluster"])
		var before := rng.state
		var plain := BoosterPack.draw(lo, loud, pool, {}, rng, null)
		assert_eq(plain.cards.filter(BoosterPack.is_epic).size(), 0, "before the fusion basic: no epic")
		assert_ne(rng.state, before)
	assert_gt(state, 150, "the forced chance shows them")
	# The draws never change with the epic roll: six a pack.
	var a := _rng(9)
	var b := _rng(9)
	BoosterPack.draw(_deep([&"pistol", &"shotgun"]), loud, pool, {}, a, null, true)
	for i in BoosterPack.DRAWS:
		b.randf()
	assert_eq(a.state, b.state, "exactly DRAWS draws")
	# No parents, no epic, whatever the roll.
	for i in 50:
		var o := BoosterPack.draw(_deep([&"pistol", &"shotgun"]), loud, _pool([&"pistol", &"shotgun"]), {}, rng, null, true)
		assert_eq(o.cards.filter(BoosterPack.is_epic).size(), 0)


func test_the_epic_card_arrives_at_rank_four_or_the_held_parents_rank() -> void:
	var fresh := BoosterPack.epic_card(_deep([&"pistol"]), &"prism")
	assert_eq([fresh.kind, int(fresh.rank), fresh.rarity, fresh.title], [&"new", 4, &"epic", "Prism 4"], "no parent held: rank 4")
	assert_false(fresh.has("absorbs"))
	var low := BoosterPack.epic_card(_deep([&"pistol", &"shotgun"], [9, 2]), &"prism")
	assert_eq([low.kind, int(low.rank), low.absorbs], [&"absorb", 4, [&"shotgun"] as Array[StringName]], "a low parent: rank 4")
	var high := BoosterPack.epic_card(_deep([&"pistol", &"shotgun"], [1, 7]), &"prism")
	assert_eq([high.kind, int(high.rank)], [&"absorb", 7], "a higher parent keeps its rank")
	assert_string_contains(high.gain, "Shotgun 7")
	var pair := BoosterPack.epic_card(_deep([&"shotgun", &"laser"], [5, 6]), &"prism")
	assert_eq([pair.kind, int(pair.rank), pair.absorbs.size()], [&"absorb", 6, 2], "both held: the hand-made rule (average, up)")
	var weak := BoosterPack.epic_card(_deep([&"shotgun", &"laser"], [1, 2]), &"prism")
	assert_eq(int(weak.rank), 4, "both held but low: never below rank 4")
	assert_true(BoosterPack.is_epic(fresh) and BoosterPack.is_epic(pair))
	assert_false(BoosterPack.is_epic(BoosterPack.card(_deep([&"prism"], [4]), &"prism")), "a held fusion's +1 is an upgrade")


func _open_with(r: PathRunner, card: Dictionary) -> int:
	r._want = 1
	r._open_offer()
	assert_true(game.pick_panel.is_open())
	game.pick_panel.offer.cards.append(card)
	return game.pick_panel.offer.cards.size() - 1


func test_taking_an_epic_melts_one_held_parent_in_its_slot() -> void:
	var r := await _arena()
	var lo := _loadout()
	lo.slots.clear()
	lo.set_weapon(&"pistol", 2)
	lo.set_weapon(&"shotgun", 6)
	lo.active = 1
	lo.slots[1].shots = 40
	var at := _open_with(r, BoosterPack.epic_card(lo, &"prism"))
	game.pick_panel.choose(at)
	await wait_physics_frames(2)
	assert_false(game.pick_panel.is_open(), "no replace step: the parent's slot is the card's")
	assert_eq(lo.summary(), "pistol:2,prism:6", "the shotgun became Prism, in place, at its own higher rank")
	assert_eq(lo.active, 1, "still the active card")
	assert_eq(lo.slots[1].shots, 40, "its shots stay")
	assert_eq(int(r.pack_picks.epic), 1)
	assert_eq(r.fusions.size(), 1, "recorded like a fusion made")
	assert_eq([r.fusions[0].id, r.fusions[0].rank, r.fusions[0].epic], ["prism", 6, true])
	assert_true(&"prism" in SaveGame.recipes(), "the recipe is learned")
	assert_eq(r.pack_stack(), 0)


func test_taking_an_epic_with_both_parents_fuses_them_and_frees_a_slot() -> void:
	var r := await _arena()
	var lo := _loadout()
	lo.slots.clear()
	lo.set_weapon(&"shotgun", 1)
	lo.set_weapon(&"laser", 2)
	var at := _open_with(r, BoosterPack.epic_card(lo, &"prism"))
	game.pick_panel.choose(at)
	await wait_physics_frames(2)
	assert_eq(lo.summary(), "prism:4", "both melted into one card, never below rank 4")
	assert_false(lo.hand_full(), "a slot is free again")


func test_an_epic_on_a_full_hand_with_no_parent_asks_which_card_goes() -> void:
	var r := await _arena()
	var lo := _loadout()
	lo.slots.clear()
	lo.set_weapon(&"pistol", 3)
	lo.set_weapon(&"launcher", 3)
	r.announce(&"shotgun")
	r.announce(&"laser")
	assert_true(&"prism" in BoosterPack.epic_ids(lo, r.offer_pool()), "both parents in the pool")
	var card := BoosterPack.epic_card(lo, &"prism")
	assert_eq([card.kind, int(card.rank)], [&"new", 4])
	assert_string_contains(card.gain, "replaces a card")
	var at := _open_with(r, card)
	var panel := game.pick_panel
	panel.choose(at)
	assert_eq(panel.replacing(), at, "the replace step")
	panel.choose(1)
	await wait_physics_frames(2)
	assert_eq(lo.summary(), "pistol:3,prism:4", "the launcher went; Prism arrives at rank 4")
	assert_eq(int(r.pack_picks.replace), 1)
	assert_eq(int(r.pack_picks.epic), 1)
	# With room it simply joins.
	lo.slots.clear()
	lo.set_weapon(&"pistol", 1)
	var joins := BoosterPack.epic_card(lo, &"cluster")
	assert_string_contains(joins.gain, "joins your hand")
	r._want = 1
	r._take_pack_card(lo, joins)
	assert_eq(lo.summary(), "pistol:1,cluster:4")


func test_absorb_is_a_loadout_step_that_keeps_the_slot() -> void:
	var lo := _deep([&"shotgun", &"pistol"], [5, 2])
	lo.active = 0
	assert_false(lo.absorb(&"laser", &"prism", 4), "not held: nothing")
	assert_false(lo.absorb(&"shotgun", &"bogus", 4), "no such weapon")
	assert_true(lo.absorb(&"shotgun", &"prism", 5))
	assert_eq(lo.summary(), "prism:5,pistol:2")
	assert_eq(lo.active, 0)
	assert_eq(lo.holder(&"shotgun").def.id, &"prism", "the parent now feeds the fusion")


# --- 7. The bot -------------------------------------------------------------------------------

func test_the_bot_takes_an_epic_that_melts_a_card_and_never_one_that_costs_a_card() -> void:
	var r := await _arena()
	var lo := _loadout()
	lo.slots.clear()
	lo.set_weapon(&"pistol", 2)
	lo.set_weapon(&"shotgun", 2)
	lo.slots[0].shots = 50
	var at := _open_with(r, BoosterPack.epic_card(lo, &"prism"))
	var panel := game.pick_panel
	assert_eq(BotRuns.pack_choice(panel, lo, ""), at, "an absorb epic is taken")
	assert_ne(BotRuns.pack_choice(panel, lo, "no_fuse"), at, "never with no_fuse")
	panel.offer.cards[at] = BoosterPack.epic_card(_deep([&"pistol", &"launcher"]), &"prism")
	assert_eq(panel.offer.cards[at].kind, &"new")
	assert_ne(BotRuns.pack_choice(panel, lo, ""), at, "a full hand: an epic NEW card is never taken")
	panel.choose(0)


## The bot's run of `packs` packs on one seed: what each pack showed, what it took, the hand
## and the pack stream at the end.
func _bot_run(run_seed: int, probe: StringName, packs := 5) -> String:
	var bot := BotInput.new()
	bot.probe = probe
	var r := await _arena(run_seed, bot)
	r.announce(&"shotgun")
	r.announce(&"laser")
	var panel := game.pick_panel
	var trace: Array[String] = []
	for i in packs:
		_kill(r, _arsenal().pack_every)
		for f in 6:
			await wait_physics_frames(1)
			if panel.is_open() and panel.can_choose():
				trace.append("%d:%s" % [RunState.tick if &"tick" in RunState else 0, ",".join(panel.offer.ids().map(func(x: StringName) -> String: return String(x)))])
				BotRuns.choose_pack(panel, game, String(probe))
	await wait_physics_frames(2)
	var out := "%s|%s|%d|opened=%d|left=%d" % [";".join(trace), _loadout().summary(), RunState.pack_rng.state,
			r.packs_opened, r.pack_stack()]
	if panel.is_open():
		panel.dismiss()
	game.free()
	RunState.set_pause(PickPanel.PAUSE, false)
	await wait_physics_frames(1)
	return out


func test_the_bot_opens_each_pack_at_once_and_a_seed_replays() -> void:
	var a := await _bot_run(4242, &"")
	var b := await _bot_run(4242, &"")
	assert_eq(a, b, "the same seed twice: the same packs, picks, hand and stream")
	assert_string_contains(a, "opened=5|left=0", "every pack opened as soon as it was stacked")
	var c := await _bot_run(77, &"")
	assert_ne(a, c, "another seed plays differently")
	var h := await _bot_run(4242, &"hoard")
	assert_string_contains(h, "opened=0|left=5", "the hoard probe never opens one")
