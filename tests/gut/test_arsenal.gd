extends GutTest
## M46 (PLAN v9 1.5, 4): Arsenal. Its PathDef, the hand and keys 1-3 (weapon_1..3, AZERTY
## labels), quick-draw, the card meter, offers, the HandWidget, `give` under Arsenal, the
## arsenal bot policy (cards, hysteresis, the flank rule on a stub), the probes, the S8
## Arsenal draft (audit rows, the pool rule) and the play fingerprint. G6 and G7 for Arsenal
## live here by name.

const CHASER := preload("res://entities/enemy_chaser.tscn")
const CardMeter := preload("res://paths/arsenal/card_meter.gd")
const HandWidget := preload("res://paths/arsenal/hand_widget.gd")
const BotRuns := preload("res://tools/bot_runs.gd")
const T := 48.0
const OPEN := Vector2(34, 20)
## The telemetry log while these tests run: a scratch file, never user://playtest/runs.jsonl.
const TEST_LOG := "user://save_arsenal_test/runs.jsonl"
const DRAFT := &"s8_draft_arsenal"
const DRAFT_PATH := "res://campaign/drafts/s8_draft_arsenal.tres"

var game: Main
var player: CharacterBody2D
var _links: Array = []


## A front-shielded enemy as M50's shielder must look to the flank rule.
class ShieldStub extends Node2D:
	var shield_arc_deg := 120.0
	var facing := Vector2.LEFT


## Records the damage every pellet carries as it is spawned.
class SpyTrait extends WeaponTrait:
	var seen: Array = []

	func spawned(_weapon: Weapon, projectile: Node) -> void:
		seen.append(float(projectile.get(&"damage")))


func before_each() -> void:
	Telemetry.log_path = TEST_LOG


func after_each() -> void:
	for l: Array in _links:
		if (l[0] as Signal).is_connected(l[1]):
			(l[0] as Signal).disconnect(l[1])
	_links.clear()
	assert_false(FileAccess.file_exists(TEST_LOG), "no telemetry written, not even to the scratch log")
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.invincible = false
	RunState.set_pause(PickPanel.PAUSE, false)
	CampaignDB.active = false
	while _draft_in_list() != null:
		CampaignDB.campaign.sessions.erase(_draft_in_list())
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null
	for a: StringName in [&"weapon_1", &"weapon_2", &"weapon_3"]:
		Input.action_release(a)
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(TEST_LOG)


func _on(sig: Signal, c: Callable) -> void:
	sig.connect(c)
	_links.append([sig, c])


func _arsenal() -> PathDef:
	return PathDB.get_def(&"arsenal")


## The legacy arena (no session): spawner and director off, no enemies, the player in the open.
func _arena(run_seed := -1) -> void:
	if run_seed >= 0:
		Main.next_seed = run_seed
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	game.director.enabled = false
	await wait_physics_frames(2)
	_clear_enemies()
	await wait_physics_frames(1)
	player = game.player
	player.set_input(load("res://tests/gut/fixtures.gd").ScriptedInput.new())
	await wait_physics_frames(1)
	player.global_position = OPEN * T
	player.velocity = Vector2.ZERO
	RunState.invincible = true


## The arena on Arsenal through F2's PATH (outside a session every basic is on).
func _arsenal_arena() -> PathRunner:
	await _arena()
	assert_true(game.debug.switch_path(&"arsenal"))
	game.pick_panel.input_delay = 0.0
	await wait_physics_frames(1)
	return game.path_runner


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()


func _session_game(id: StringName, run_seed := -1) -> Main:
	if run_seed >= 0:
		Main.next_seed = run_seed
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var g: Main = load("res://main.tscn").instantiate()
	add_child_autofree(g)
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	game = g
	player = g.player
	return g


func _draft() -> SessionDef:
	return load(DRAFT_PATH) as SessionDef


func _draft_game(run_seed := -1) -> Main:
	CampaignDB.campaign.sessions.insert(CampaignDB.cooking_index(), _draft())
	return await _session_game(DRAFT, run_seed)


func _draft_in_list() -> SessionDef:
	for s in CampaignDB.campaign.sessions:
		if s.id == DRAFT:
			return s
	return null


func _loadout() -> Loadout:
	return Component.find(player, Loadout) as Loadout


func _frozen_chaser(tile: Vector2) -> Node2D:
	var e := RunState.spawn(CHASER, tile * T) as Node2D
	await wait_physics_frames(2)
	e.set_physics_process(false)
	e.mover.wish = Vector2.ZERO
	e.velocity = Vector2.ZERO
	e.health.base_max_hp = 100.0
	return e


## Opens a pick now (no waiting on the physics tick) and chooses card i. M50.2a: a 1-card
## pack applies as a toast (no panel): its offer is the runner's last.
func _pick(runner: PathRunner, i := 0) -> PickOffer:
	runner.want_pick()
	runner._open_offer()
	if not game.pick_panel.is_open():
		return runner.offers[-1]
	var offer := game.pick_panel.offer
	game.pick_panel._unlock()
	game.pick_panel.choose(mini(i, offer.cards.size() - 1))
	return offer


func _kill(runner: PathRunner, n: int, faction := &"player") -> void:
	for i in n:
		runner._on_enemy_killed(null, DamageInfo.make(1.0, &"projectile", faction))


## How many EventBus.enemy_killed connections target a PathRunner.
func _runner_kill_links() -> int:
	var n := 0
	for c: Dictionary in EventBus.enemy_killed.get_connections():
		var cb: Callable = c.callable
		if cb.get_method() == &"_on_enemy_killed" and (not is_instance_valid(cb.get_object()) or cb.get_object() is PathRunner):
			n += 1
	return n


# --- 1. Data --------------------------------------------------------------------------------

func test_the_arsenal_data_is_valid() -> void:
	assert_eq(PathDB.problems(), [] as Array[String])
	var a := _arsenal()
	assert_eq(a.fire_mode, &"manual_one")
	assert_eq(a.growth, &"cards")
	assert_eq(a.widget, &"hand")
	assert_eq(a.bot_policy, &"arsenal")
	assert_eq(a.start, [&"pistol"] as Array[StringName])
	assert_eq(a.max_slots, 2, "M50.1a: a hand of 2")
	assert_eq(a.max_passives, 1)
	assert_eq(a.max_picks, 6)
	assert_eq(a.basics, [&"cards", &"quick_draw", &"fusion"] as Array[StringName], "M50.1b: + fusion")
	assert_eq(a.quick_draw_mult, 2.0)
	assert_eq(a.pick_line, "Pack. Pick one.")
	assert_eq([a.pack_every, a.pack_taste, a.rank_cap, a.rank_curve], [6, 2, 0, &"deep"], "M50.1a: packs, deep ranks")
	assert_almost_eq(a.epic_chance, 0.05, 0.0001, "M50.6: the epic slot roll (the rare roll is gone)")
	assert_eq(a.taste_thresholds, PackedInt32Array([10]))
	assert_eq(a.level_thresholds.size(), a.max_picks, "one cumulative threshold per pick")
	for i in range(1, a.level_thresholds.size()):
		var step := a.level_thresholds[i] - a.level_thresholds[i - 1]
		var prev := a.level_thresholds[i - 1] - (a.level_thresholds[i - 2] if i >= 2 else 0)
		assert_almost_eq(float(step) / prev, 1.4, 0.03, "x1.4 between cards (%d)" % i)
	for b in a.basics:
		assert_true(b in Unlocks.CAMPAIGN_BASICS, String(b))
		assert_eq(PathDB.owner_of_basic(b), &"arsenal")
	assert_eq(PathDB.get_def(&"auto").full_line, "", "M50.4a: Auto has no level cap, so no stop line")


func test_path_def_problems_bite_on_a_cards_path() -> void:
	var a := _arsenal().duplicate() as PathDef
	a.level_thresholds = PackedInt32Array([15, 36])
	assert_eq(a.problems(), [] as Array[String], "M50.1a: a pack path needs no thresholds")
	a.pack_every = 0
	assert_string_contains("\n".join(a.problems()), "a threshold for each of its 6 picks")
	a = _arsenal().duplicate() as PathDef
	a.epic_chance = 1.0
	assert_string_contains("\n".join(a.problems()), "epic_chance")
	a = _arsenal().duplicate() as PathDef
	a.pack_taste = -1
	assert_string_contains("\n".join(a.problems()), "pack_taste")
	a = _arsenal().duplicate() as PathDef
	a.rank_curve = &"classic"
	assert_string_contains("\n".join(a.problems()), "the classic curve stops at rank 3")
	a = _arsenal().duplicate() as PathDef
	a.quick_draw_mult = 0.5
	assert_string_contains("\n".join(a.problems()), "quick_draw_mult")
	a = _arsenal().duplicate() as PathDef
	a.full_line = "thinking: {key:no_such_action}"
	assert_string_contains("\n".join(a.problems()), "full_line")


# --- 2. Built ----------------------------------------------------------------------------------

func test_path_arsenal_is_built_and_survival_too() -> void:
	assert_eq(Cue.parse("at 3: path arsenal").unbuilt(), "")
	assert_eq(Cue.parse("at 3: path survival").unbuilt(), "", "M47 builds Survival")
	await _arena()
	assert_true(game.debug.switch_path(&"arsenal"))
	assert_eq(game.path_runner.path_id, &"arsenal")
	assert_eq(_loadout().fire_mode, &"manual_one")
	assert_true(game.debug.switch_path(&"survival"), "M47: F2 PATH survival")
	assert_eq(_loadout().fire_mode, &"manual_ammo")
	await wait_physics_frames(2)   # Survival's deferred pieces land before the game is freed (no orphan)


# --- 3. Binds -----------------------------------------------------------------------------------

func _azerty(physical: int) -> int:
	match physical:
		KEY_1:
			return KEY_AMPERSAND
		KEY_2:
			return 0xE9   # é
		KEY_3:
			return KEY_QUOTEDBL
		KEY_Q:
			return KEY_A
	return physical


func test_keys_1_to_3_are_physical_and_named_per_layout() -> void:
	for i in 3:
		var action := StringName("weapon_%d" % (i + 1))
		assert_true(action in InputSetup.ACTIONS)
		var keys := InputMap.action_get_events(action).filter(func(e: InputEvent) -> bool: return e is InputEventKey)
		assert_eq(keys.size(), 1)
		assert_eq((keys[0] as InputEventKey).physical_keycode, [KEY_1, KEY_2, KEY_3][i])
		assert_eq(InputSetup.key_label(action, func(p: int) -> int: return p), str(i + 1), "QWERTY")
		assert_eq(InputSetup.key_label(action, _azerty), str(i + 1), "AZERTY prints the digit")
	assert_eq(InputSetup.key_label(&"weapon_prev", _azerty), "A", "a letter is still the layout's")
	var o := PickOffer.new()
	o.cards.append({"id": &"pistol", "rank": 2, "kind": &"upgrade", "text": "Pistol II"})
	assert_eq(PickPanel.card_text(o, 0, _azerty), "[1]  Pistol II", "never [Ampersand]")


# --- 4. select_slot --------------------------------------------------------------------------

func test_select_slot_selects_and_the_stage_1_pistol_never_moves() -> void:
	await _arena()
	var lo := _loadout()
	assert_false(lo.select_slot(0))
	assert_false(lo.select_slot(1))
	(player.input as PlayerInput).select_slot = 1
	await wait_physics_frames(2)
	assert_eq(lo.active, 0)
	assert_eq(lo.summary(), "pistol:1", "the legacy player is unchanged")
	assert_eq(lo.switches, 0)
	(player.input as PlayerInput).select_slot = -1
	assert_true(game.debug.switch_path(&"arsenal"))
	lo.give(&"shotgun")
	var changed: Array = []
	_on(EventBus.weapon_changed, func(id: StringName, _r: int) -> void: changed.append(id))
	assert_true(lo.select_slot(1))
	assert_eq(lo.active, 1)
	assert_eq(changed, [&"shotgun"])
	assert_false(lo.select_slot(1), "already active")
	assert_false(lo.select_slot(5), "out of range")
	assert_eq(lo.switches, 1)


# --- 5. Keys and panels --------------------------------------------------------------------

## Presses `action` outside a physics frame, so a manual _physics_process reads it as
## just pressed (inside one, Input stamps the press for the next physics frame).
func _press(action: StringName, release := false) -> void:
	await get_tree().process_frame
	Input.action_press(action)
	if release:
		Input.action_release(action)


func _release_all() -> void:
	Input.action_release(&"weapon_2")
	await wait_physics_frames(1)


func test_keys_never_switch_under_a_pause_or_with_the_key_that_picked() -> void:
	var h := HumanInput.new()
	add_child_autofree(h)
	await wait_physics_frames(1)
	await _press(&"weapon_2")
	assert_true(Input.is_action_just_pressed(&"weapon_2"), "the press reads as fresh")
	h._physics_process(0.0)
	assert_eq(h.select_slot, 1, "control: a fresh digit selects")
	await _release_all()
	RunState.set_pause(PickPanel.PAUSE, true)
	await _press(&"weapon_2")
	h._physics_process(0.0)
	assert_eq(h.select_slot, -1, "never while a panel pauses play")
	RunState.set_pause(PickPanel.PAUSE, false)
	await _release_all()
	# The key that picked card 2 is still down when the panel closes.
	await _press(&"weapon_2")
	h.require_fresh_press()
	h._physics_process(0.0)
	assert_eq(h.select_slot, -1, "the picking key does not also pick slot 2")
	await _release_all()
	h._physics_process(0.0)
	assert_false(h._wait_release, "released: the wait is over")
	# Tapped and released before the tick that ends the wait.
	await _press(&"weapon_2", true)
	var tap_reads := Input.is_action_just_pressed(&"weapon_2")
	h._physics_process(0.0)
	assert_eq(h.select_slot, 1 if tap_reads else -1, "control: a tap selects when Input reports it")
	await wait_physics_frames(1)
	await _press(&"weapon_2", true)
	h.require_fresh_press()
	h._physics_process(0.0)
	assert_eq(h.select_slot, -1, "the tick that ends the wait selects nothing")


func test_a_pick_asks_the_player_input_for_a_fresh_press() -> void:
	var r := await _arsenal_arena()
	var h := HumanInput.new()
	player.set_input(h)
	await wait_physics_frames(1)
	assert_false(h._wait_release)
	r.announce(&"shotgun")   # M50.2a: a pool of two, so the pack is a choice (no toast)
	_pick(r, 0)
	assert_true(h._wait_release, "the runner asks for a fresh press after a pick")


# --- 6. Quick-draw ------------------------------------------------------------------------

func _shot_damages(lo: Loadout) -> Array:
	var seen: Array = []
	var c := func(p: Node) -> void: seen.append(float(p.get(&"damage")))
	EventBus.projectile_fired.connect(c)
	lo.current().ready_in = 0.0
	assert_true(lo.try_fire(Vector2.RIGHT))
	EventBus.projectile_fired.disconnect(c)
	return seen


func test_quick_draw_doubles_the_first_shot_after_a_switch_only() -> void:
	await _arsenal_arena()
	var lo := _loadout()
	assert_eq(lo.quick_draw_mult, 2.0, "outside a session every basic is on")
	lo.give(&"shotgun")
	var shotgun := lo.held(&"shotgun")
	var spy := SpyTrait.new()
	shotgun.traits.append(spy)
	var base := float(shotgun.value(&"damage"))
	assert_true(lo.select_slot(1))
	var first := _shot_damages(lo)
	assert_eq(first.size(), int(shotgun.value(&"pellets")))
	for d: float in first:
		assert_almost_eq(d, base * 2.0, 0.0001, "projectile_fired sees x2")
	for d: float in spy.seen:
		assert_almost_eq(d, base * 2.0, 0.0001, "a trait's spawned sees x2")
	for d: float in _shot_damages(lo):
		assert_almost_eq(d, base, 0.0001, "the next shot is x1")
	assert_false(lo.select_slot(1), "a no-op select of the active card")
	for d: float in _shot_damages(lo):
		assert_almost_eq(d, base, 0.0001, "arms nothing")
	assert_true(RunState.run_log.any(func(e: Dictionary) -> bool: return e.event == &"quick_draw"))
	await wait_physics_frames(1)


func _quick_draw_events() -> int:
	return RunState.run_log.filter(func(e: Dictionary) -> bool: return e.event == &"quick_draw").size()


func test_a_quick_draw_refused_at_the_cap_logs_nothing_and_stays_armed() -> void:
	await _arsenal_arena()
	var lo := _loadout()
	lo.give(&"shotgun")
	assert_true(lo.select_slot(1))
	var base := float(lo.held(&"shotgun").value(&"damage"))
	var q0 := _quick_draw_events()
	var budget := Tuning.player_projectile_budget
	Tuning.player_projectile_budget = 0
	for i in 3:
		lo.current().ready_in = 0.0
		assert_false(lo.try_fire(Vector2.RIGHT), "every pellet refused at the cap")
	Tuning.player_projectile_budget = budget
	assert_eq(_quick_draw_events(), q0, "no quick_draw for shots that never fired")
	assert_true(lo.drawn(), "still armed")
	for d: float in _shot_damages(lo):
		assert_almost_eq(d, base * 2.0, 0.0001, "the first shot that spawns is the boosted one")
	assert_eq(_quick_draw_events(), q0 + 1, "one event for the one boosted shot")
	_shot_damages(lo)
	assert_eq(_quick_draw_events(), q0 + 1, "the next shot logs nothing")
	await wait_physics_frames(1)


func test_no_quick_draw_on_auto_without_a_path_or_before_its_basic() -> void:
	await _arena()
	var lo := _loadout()
	# Without a path: the shotgun fires through Shooter.fire, never boosted.
	lo.give(&"shotgun")
	assert_true(lo.select_slot(1))
	var base := float(lo.held(&"shotgun").value(&"damage"))
	for d: float in _shot_damages(lo):
		assert_almost_eq(d, base, 0.0001, "no path: x1")
	assert_true(game.debug.switch_path(&"auto"))
	assert_eq(lo.quick_draw_mult, 1.0, "Auto has no quick-draw")
	lo.give(&"shotgun")
	lo.switch(1)
	for d: float in _shot_damages(lo):
		assert_almost_eq(d, base, 0.0001, "Auto: x1")
	# The legacy pistol never goes through the multiplier.
	assert_true(game.debug.switch_path(&"off"))
	assert_true(lo.legacy_pistol())
	lo.quick_draw_mult = 2.0
	lo._drawn = true
	var legacy: Array = []
	var c := func(p: Node) -> void: legacy.append(float(p.get(&"damage")))
	EventBus.projectile_fired.connect(c)
	lo.shooter()._ready_in = 0.0
	assert_true(lo.try_fire(Vector2.RIGHT))
	EventBus.projectile_fired.disconnect(c)
	assert_eq(legacy, [lo.shooter().damage], "the legacy pistol is today's shot")
	lo.quick_draw_mult = 1.0
	await wait_physics_frames(1)


func test_quick_draw_waits_for_its_basic_in_the_draft() -> void:
	await _draft_game()
	var lo := _loadout()
	assert_eq(RunState.live_path(), &"arsenal")
	assert_eq(lo.quick_draw_mult, 1.0, "not before `add quick_draw`")
	RunState.add_basic(&"quick_draw")
	assert_eq(lo.quick_draw_mult, 2.0)


func test_shooter_fire_with_the_default_mult_is_todays_damage() -> void:
	await _arena()
	var lo := _loadout()
	lo.give(&"shotgun")
	var w := lo.held(&"shotgun")
	var got: Array = []
	var c := func(p: Node) -> void: got.append(float(p.get(&"damage")))
	EventBus.projectile_fired.connect(c)
	lo.shooter().fire(w, Vector2.RIGHT)
	EventBus.projectile_fired.disconnect(c)
	assert_false(got.is_empty())
	for d: float in got:
		assert_eq(d, float(w.value(&"damage")), "exactly today's damage")
	await wait_physics_frames(1)


# --- 7. The card meter ----------------------------------------------------------------------

func test_the_card_meter_deals_on_cumulative_kills_and_stops_after_six() -> void:
	var a := _arsenal()
	var m := CardMeter.new()
	m.def = a
	var dealt := [0]
	var full := [0]
	m.on_card = func() -> void: dealt[0] += 1   # never capture m: a cycle leaks
	m.on_full = func() -> void: full[0] += 1
	m.add(a.threshold(1) - 1)
	assert_eq(m.cards, 0)
	m.add(1)
	assert_eq(m.cards, 1, "the first card at %d kills" % a.threshold(1))
	m.add(a.threshold(2) - m.kills)
	assert_eq(m.cards, 2, "cumulative: the second at %d" % a.threshold(2))
	m.add(100000)
	assert_eq(m.cards, 6)
	assert_eq(dealt[0], 6)
	assert_eq(full[0], 1, "the full line once")
	m.add(1000)
	assert_eq(m.cards, 6)
	assert_eq(m.next_need(), -1)
	assert_eq(m.progress(), 1.0)


func test_a_tryout_card_meter_stops_quietly_after_ten_kills() -> void:
	var m := CardMeter.new()
	m.def = _arsenal()
	m.tryout = true
	var full := [0]
	m.on_full = func() -> void: full[0] += 1
	m.add(9)
	assert_eq(m.cards, 0)
	m.add(1)
	assert_eq(m.cards, 1)
	assert_true(m.stopped)
	m.add(500)
	assert_eq(m.cards, 1)
	assert_eq(full[0], 0, "no stop line in a tryout")


func test_player_kills_fill_the_meter_in_a_game() -> void:
	var r := await _arsenal_arena()
	assert_not_null(r.meter())
	assert_true(r.pack_path(), "M50.1a: Arsenal deals packs")
	_kill(r, 3)
	_kill(r, 5, &"enemy")
	assert_eq(int(r.meter().get(&"kills")), 3, "a bomber's own fuse kill does not count")
	assert_eq(r.level(), 1, "no level on Arsenal")
	assert_eq(r.gems(), 0)
	assert_eq(r.cards(), 0)
	assert_eq(r.kills_to_next(), 3, "6 kills a pack")
	r.force_level()
	assert_eq(r.cards(), 1, "F2's +1 deals one pack")
	assert_eq(r.pending_picks(), 1)
	assert_string_contains(r.state_text(), "path=arsenal packs=1 stack=1 kills=0/6 hand=pistol:1")
	var meter := r.meter()
	EventBus.basic_added.emit(&"cards")
	EventBus.basic_added.emit(&"quick_draw")
	assert_true(r.meter() == meter, "a second basic_added builds no second meter")
	assert_eq(_runner_kill_links(), 1, "one kill feed")
	for i in 9:
		r.force_level()
	assert_eq(r.cards(), 10, "no session cap on a pack path")
	assert_false(Line.parse(_arsenal().full_line).text in r.said, "no full line")


func test_a_real_kill_reaches_the_meter_and_swaps_leave_no_feed() -> void:
	var before := _runner_kill_links()
	var r := await _arsenal_arena()
	assert_eq(_runner_kill_links(), before + 1)
	var e := await _frozen_chaser(OPEN + Vector2(4, 0))
	e.health.take(DamageInfo.make(1000.0, &"projectile", &"player", e.global_position))
	await wait_physics_frames(1)
	assert_eq(int(r.meter().get(&"kills")), 1, "through EventBus.enemy_killed")
	r.swap_now(&"auto")
	assert_eq(_runner_kill_links(), before, "a swap drops the feed")
	r.swap_now(&"arsenal")
	assert_eq(_runner_kill_links(), before + 1, "a live feed going into the tree exit")
	remove_child(game)
	assert_eq(_runner_kill_links(), before, "leaving the tree drops it (PathRunner._exit_tree)")
	game.free()
	assert_eq(_runner_kill_links(), before, "and freeing the scene")


func test_freeze_drops_the_card_feed() -> void:
	var before := _runner_kill_links()
	var r := await _arsenal_arena()
	assert_eq(_runner_kill_links(), before + 1)
	r.freeze()
	assert_eq(_runner_kill_links(), before, "freeze drops it")
	r.swap_now(&"arsenal")
	assert_eq(_runner_kill_links(), before, "and a frozen runner builds no new feed")


func test_after_freeze_add_cards_builds_nothing() -> void:
	await _draft_game()
	var r: PathRunner = game.path_runner
	assert_null(r.meter(), "no cards basic yet")
	r.freeze()
	RunState.add_basic(&"cards")
	assert_null(r.meter(), "the bot's --loadout= freeze holds")


# --- 8. Offers ---------------------------------------------------------------------------------

func test_offers_lead_with_the_most_fired_card_and_respect_the_hand() -> void:
	var r := await _arsenal_arena()
	var lo := _loadout()
	lo.give(&"shotgun")
	r.announce(&"shotgun")
	r.announce(&"laser")
	lo.held(&"pistol").shots = 10
	lo.held(&"shotgun").shots = 50
	r.want_pick()
	r._open_offer()
	var offer := game.pick_panel.offer
	assert_true(offer.pack)
	assert_eq(offer.line, "Pack. Pick one.")
	assert_eq(offer.ids()[0], &"shotgun", "the most-fired card's upgrade first (G1)")
	assert_eq(offer.cards[0].kind, &"upgrade", "a held card is an upgrade")
	assert_eq(PathRunner.most_fired(lo), &"shotgun")
	var by := 2 if offer.cards[0].rarity == &"rare" else 1
	game.pick_panel.choose(0)
	assert_eq(lo.rank_of(&"shotgun"), 1 + by, "a common card +1, a rare +2")
	# M50.1a: no top rank on the deep curve, so no filler card.
	for id: StringName in [&"pistol", &"shotgun"]:
		lo.set_weapon(id, 30)
	assert_eq(lo.rank_of(&"pistol"), 30)
	assert_ne(PathRunner.most_fired(lo), &"", "always something to rank up")
	var o := _pick(r, 0)
	assert_false(PickOffer.HP in o.ids(), "no +1 HP filler on a pack path")


# --- 9. give ---------------------------------------------------------------------------------

func test_give_under_arsenal_is_a_free_card() -> void:
	await _draft_game()
	var r: PathRunner = game.path_runner
	game.session_runner._fire(Cue.parse("at 0: give shotgun"), -1)
	assert_eq(_loadout().summary(), "pistol:1,shotgun:1", "a free card")
	assert_eq(r.pending_picks(), 0, "no pick owed")
	assert_true(&"shotgun" in r.live_pool)
	# A full hand before the `cards` basic: the weakest card that is not the active one goes,
	# logged give_replaced (M50.1a).
	var lo := _loadout()
	lo.apply_path(_arsenal())
	lo.set_weapon(&"pistol", 2)
	lo.set_weapon(&"laser", 1)
	lo.active = 0
	assert_false(r.give(&"shotgun"))
	assert_true(RunState.run_log.any(func(e: Dictionary) -> bool: return e.event == &"give_replaced"))
	assert_true(lo.give(&"shotgun"))
	assert_eq(lo.summary(), "pistol:2,shotgun:1")
	# Once the packs are live a full hand never loses a card silently: M50.2b's give step
	# (G4 retired).
	RunState.add_basic(&"cards")
	assert_true(r.give(&"laser", 3))
	assert_eq(lo.summary(), "pistol:2,shotgun:1", "nothing replaced")
	assert_eq(r.give_pending(), &"laser", "the give step waits for a free tick")
	assert_true(RunState.run_log.any(func(e: Dictionary) -> bool: return e.event == &"give_offered"))


# --- 10. HandWidget --------------------------------------------------------------------------

func test_the_hand_widget_rows_pips_keys_and_bar() -> void:
	var r := await _arsenal_arena()
	var w := r.widget()
	assert_not_null(w)
	assert_true(game.hud.path_widget == w, "set through hud.set_path_widget")
	await wait_physics_frames(1)
	assert_string_contains(w.text(), "[1] Pistol 1 ○○○", "M50.1a: the rank digit and 3 mechanic dots")
	assert_string_contains(w.text(), "pack in 6")
	assert_eq(w.active_row(), 0)
	var lo := _loadout()
	lo.give(&"shotgun")
	lo.upgrade(&"shotgun")
	assert_true(lo.select_slot(1))
	assert_string_contains(w.text(), "[2] Shotgun 2 ●○○")
	lo.set_weapon(&"shotgun", 9)
	assert_string_contains(w.text(), "[2] Shotgun 9 ●'●●", "rank 6 unlocks C, rank 8 strengthens A")
	assert_eq(w.active_row(), 1, "the active card is raised")
	_kill(r, 5)
	w.step(0.0)
	assert_almost_eq(w.bar(), float(r.meter().progress()), 0.0001)
	assert_gt(w.bar(), 0.0)
	assert_eq(HandWidget.pips(3), "●●●")


## M47.2 (owner G14a: "a card hand ... you see current weapons and which is equipped (real
## cards)"): one card per held weapon, its title, rank and switch key on the layout.
func test_the_hand_shows_one_card_per_weapon_with_its_key_and_pips() -> void:
	var r := await _arsenal_arena()
	var w := r.widget()
	w.manual = true
	assert_eq(w.card_count(), 1)
	assert_eq(w.card_title(0), "Pistol")
	assert_eq(w.card_rank(0), 1)
	var lo := _loadout()
	lo.give(&"shotgun")
	lo.upgrade(&"shotgun")
	w.step(0.0)
	assert_eq(w.card_count(), 2, "M50.1a: a hand of 2")
	assert_eq([w.card_title(1), w.card_rank(1)], ["Shotgun", 2])
	for i in 2:
		assert_eq(w.key_label(i), InputSetup.expand_keys("{key:weapon_%d}" % (i + 1)))
		assert_eq(w.key_label(i, _azerty), InputSetup.expand_keys("{key:weapon_%d}" % (i + 1), _azerty))
	assert_eq([w.key_label(0, _azerty), w.key_label(1, _azerty)], ["1", "2"], "AZERTY prints the digit (M46)")
	assert_eq(w.key_label(1, func(k: int) -> int: return k), "2", "QWERTY")


func test_the_equipped_card_is_raised_and_the_others_lowered() -> void:
	var r := await _arsenal_arena()
	var w := r.widget()
	w.manual = true
	var lo := _loadout()
	lo.give(&"shotgun")
	w.step(1.0)
	var view := Vector2(1280, 720)
	assert_eq(w.equipped(), 0)
	assert_lt(w.card_rect(0, view).position.y, w.card_rect(1, view).position.y, "the pistol is up")
	assert_true(lo.select_slot(1))
	w.step(0.05)
	assert_eq(w.equipped(), 1)
	assert_between(w.lift(1), 0.1, 0.9, "the switch tweens (partway after 0.05 s)")
	w.step(0.2)
	assert_eq(w.lift(1), 1.0)
	assert_eq(w.lift(0), 0.0)
	assert_lt(w.card_rect(1, view).position.y, w.card_rect(0, view).position.y, "the shotgun is raised")
	assert_eq(w.card_rect(0, view).end.y, view.y - HandWidget.MARGIN, "the others sit on the margin")


func test_a_new_card_slides_in() -> void:
	var r := await _arsenal_arena()
	var w := r.widget()
	w.manual = true
	w.step(1.0)
	assert_eq(w.joining(0), 0.0)
	_loadout().give(&"laser")
	w.step(0.0)
	assert_eq(w.joining(1), 1.0, "a new card starts below, faded")
	w.step(0.1)
	assert_between(w.joining(1), 0.1, 0.9)
	w.step(0.3)
	assert_eq(w.joining(1), 0.0, "in after 0.25 s")


## reduce_flashing: the lit card never pulses and a joining card has no brightness flash.
func test_reduce_flashing_never_pulses_the_hand() -> void:
	var r := await _arsenal_arena()
	SaveGame.state().settings["reduce_flashing"] = true
	var w := r.widget()
	w.manual = true
	w.step(1.0)
	var still := true
	for i in 60:
		w.step(1.0 / 30.0)
		still = still and w.lift(0) == 1.0 and w.joining(0) == 0.0 and w.join_flash(0) == 0.0
	assert_true(still, "the lit card holds still over 2 s")
	_loadout().give(&"laser")
	w.step(0.0)
	assert_true(SaveGame.reduce_flashing())
	assert_eq(w.joining(1), 1.0)
	var last := 0.0
	for i in 20:
		assert_eq(w.join_flash(1), 0.0, "no brightness flash with reduce_flashing")
		w.step(1.0 / 60.0)
		assert_gte(1.0 - w.joining(1), last, "the join's alpha only rises")
		last = 1.0 - w.joining(1)
	SaveGame.state().settings["reduce_flashing"] = false
	_loadout().replace_slot(1, &"shotgun", 1)
	w.step(0.0)
	assert_gt(w.join_flash(1), 0.0, "the flash is there without it")


# --- 11. G6 for Arsenal ----------------------------------------------------------------------

func test_six_arsenal_picks_leave_the_stack_build_and_save_alone() -> void:
	await _draft_game()
	var r: PathRunner = game.path_runner
	assert_eq(RunState.live_path(), &"arsenal")
	RunState.add_basic(&"cards")
	r.announce(&"shotgun")
	var stack := RunState.stack.duplicate()
	var build := RunState.build_number
	var save := JSON.stringify(SaveGame.data)
	var notes := RunState.session.notes.duplicate()
	var notes_text := DebriefScreen.notes_text(RunState.session)
	var patch_kinds := [&"apply", &"revert", &"ai_apply", &"ai_remove", &"edit_landed", &"basic_added", &"big_swap"]
	var patch_count := func() -> int:
		return RunState.run_log.filter(func(e: Dictionary) -> bool: return e.event in patch_kinds).size()
	var patches: int = patch_count.call()
	for i in 6:
		assert_true(r.can_open_now(), "pick %d can open" % i)
		_pick(r, i % 2)
	assert_eq(r.picks, 6)
	assert_eq(RunState.stack, stack, "no pick touches the stack")
	assert_eq(RunState.build_number, build, "nor build_number")
	assert_eq(JSON.stringify(SaveGame.data), save, "nor the save")
	assert_eq(RunState.session.notes, notes, "nor the session's patch notes")
	assert_eq(DebriefScreen.notes_text(RunState.session), notes_text, "nor the debrief's notes")
	assert_eq(patch_count.call(), patches, "nor a patch entry in the run log")


# --- 12. G7 for Arsenal: the pool rule -----------------------------------------------------

func test_no_arsenal_offer_carries_the_shotgun_before_its_give() -> void:
	await _draft_game()
	var r: PathRunner = game.path_runner
	RunState.add_basic(&"cards")
	var gives: Array = RunState.session.cue_list().filter(func(c: Cue) -> bool: return c.action == &"give")
	assert_eq(gives.size(), 1)
	var give_at: float = gives[0].value
	var seen_before: Array = []
	for second in range(0, int(give_at)):
		for c: Cue in RunState.session.cue_list():
			if c.when == &"at" and int(c.value) == second and c.action == &"say":
				game.session_runner._fire(c, -1)
		seen_before.append_array(_pick(r, second % 3).ids())
	assert_false(seen_before.is_empty())
	assert_false(&"shotgun" in seen_before, "no shotgun before its give at %d s" % give_at)
	game.session_runner._fire(gives[0], -1)
	assert_eq(_loadout().rank_of(&"shotgun"), 1, "the give is a free card")
	var after := _pick(r, 0)
	assert_true(&"shotgun" in after.ids(), "offered (as an upgrade) once given")


# --- 13. The arsenal bot ----------------------------------------------------------------------

## A bot driven by hand only (_tick): its own physics tick never runs.
func _bot(probe := &"") -> BotInput:
	var bot := BotInput.new()
	bot.probe = probe
	player.set_input(bot)
	bot.set_physics_process(false)
	await wait_physics_frames(1)
	return bot


func _tick(bot: BotInput) -> void:
	player.global_position = OPEN * T
	bot._physics_process(1.0 / 60.0)


func test_the_arsenal_bot_picks_the_card_for_the_moment() -> void:
	await _arsenal_arena()
	var lo := _loadout()
	lo.max_slots = 3   # M50.1a: the hand is 2; the fight rule still knows 3 kinds
	lo.set_weapon(&"pistol", 3)
	lo.set_weapon(&"shotgun", 1)
	lo.set_weapon(&"laser", 1)
	lo.active = 0
	var bot := await _bot()
	var e := await _frozen_chaser(OPEN + Vector2(3, 0))
	_tick(bot)
	assert_eq(bot.policy, &"arsenal")
	assert_eq(bot._card, &"shotgun", "an enemy within 4 T")
	assert_eq(bot.select_slot, 1, "through select_slot, as keys 1-3")
	assert_true(bot.fire)
	# The hysteresis: the trigger flips, the choice holds HOLD_TICKS.
	e.global_position = (OPEN + Vector2(6, 0)) * T
	var held := 0
	while bot._card == &"shotgun" and held < 100:
		_tick(bot)
		held += 1
	assert_eq(held, BotInput.HOLD_TICKS, "held for 30 ticks")
	assert_eq(bot._card, &"pistol", "then the highest rank")
	assert_eq(bot.select_slot, -1, "the pistol is already active")
	e.queue_free()
	await wait_physics_frames(1)
	# The laser: three lined up in the corridor.
	bot = await _bot()
	for x in [5, 7, 9]:
		await _frozen_chaser(OPEN + Vector2(x, 0))
	_tick(bot)
	assert_eq(bot._card, &"laser", "3 enemies in the 0.5 T corridor")
	assert_eq(bot.select_slot, 2)
	_clear_enemies()
	await wait_physics_frames(1)


func test_the_arsenal_bot_launches_into_groups_of_three_only() -> void:
	await _arsenal_arena()
	var lo := _loadout()
	lo.max_slots = 3   # M50.1a: the hand is 2; the fight rule still knows 3 kinds
	lo.set_weapon(&"pistol", 3)

	lo.set_weapon(&"shotgun", 1)
	lo.set_weapon(&"launcher", 1)
	lo.active = 0
	var bot := await _bot()
	var a := await _frozen_chaser(OPEN + Vector2(8, 0))
	await _frozen_chaser(OPEN + Vector2(8, -1))
	_tick(bot)
	assert_eq(bot._card, &"pistol", "two are not a group")
	var c := await _frozen_chaser(OPEN + Vector2(8.5, 1))
	bot = await _bot()
	_tick(bot)
	assert_eq(bot._card, &"launcher", "three within the blast radius")
	assert_eq(bot.select_slot, 2)
	var to_group := (a.global_position - player.global_position).normalized()
	assert_gt(bot.aim_dir.dot(to_group), 0.95, "aimed at the group")
	assert_not_null(c)
	_clear_enemies()
	await wait_physics_frames(1)


func test_no_switch_never_changes_the_card() -> void:
	await _arsenal_arena()
	var lo := _loadout()
	lo.give(&"shotgun")
	lo.active = 0
	var bot := await _bot(&"no_switch")
	await _frozen_chaser(OPEN + Vector2(3, 0))
	for i in 40:
		_tick(bot)
		assert_eq(bot.select_slot, -1)
	assert_true(bot.fire, "otherwise the same policy")
	bot.set_physics_process(true)
	await wait_physics_frames(3)
	assert_eq(lo.active, 0)
	_clear_enemies()
	await wait_physics_frames(1)


func test_first_pick_consumes_its_draw_and_takes_card_0() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 42
	b.seed = 42
	for i in 5:
		var probe_pick: int = BotRuns.pick_card(a, 3, "first_pick")
		var default_pick: int = BotRuns.pick_card(b, 3, "")
		assert_eq(probe_pick, 0)
		assert_between(default_pick, 0, 2)
		assert_eq(a.state, b.state, "the pick_rng stream stays paired")


func test_the_flank_rule_steps_around_a_shield_and_holds_fire() -> void:
	await _arsenal_arena()
	var bot := await _bot()
	var stub := ShieldStub.new()
	stub.add_to_group(&"enemy")
	game.add_child(stub)
	stub.global_position = (OPEN + Vector2(3, 0)) * T
	stub.facing = Vector2.LEFT   # toward the bot
	_tick(bot)
	assert_false(bot.fire, "hold fire in front of the shield")
	var away := (player.global_position - stub.global_position).normalized()
	assert_almost_eq(bot.move.dot(away), 0.0, 0.0001, "perpendicular: 90 degrees around it")
	assert_almost_eq(bot.move.length(), 1.0, 0.0001)
	assert_true(bot.move.is_equal_approx(BotInput.flank_step(player.global_position, stub)))
	stub.facing = Vector2.RIGHT   # its back to the bot
	_tick(bot)
	assert_true(bot.fire, "outside the arc: fire")
	assert_eq(BotInput.flank_step(player.global_position, stub), Vector2.ZERO)
	stub.facing = Vector2.LEFT.rotated(0.3)
	var side := BotInput.flank_step(player.global_position, stub)
	stub.facing = Vector2.LEFT.rotated(-0.3)
	assert_true(side.is_equal_approx(-BotInput.flank_step(player.global_position, stub)), "the shorter way out")
	var plain := Node2D.new()
	assert_eq(BotInput.flank_step(Vector2.ZERO, plain), Vector2.ZERO, "no shield, no flank")
	plain.free()
	game.remove_child(stub)
	stub.free()


# --- 14. Determinism ------------------------------------------------------------------------

var _replay: Dictionary = {}


## One replay of the draft (seed 3, the bot from the scene's first tick, invincible), keyed
## on the runner's own physics ticks (GUT's frame waits can start a frame apart): a hash
## every 10 ticks for 15 s, one card forced at tick 700 (after `add cards` at 10 s), its
## panel chosen from pick_rng on the first frame it can be.
func _replay_hashes() -> Array:
	SaveGame.go_inert()   # each replay from the same fresh save, as bot_runs
	CampaignDB.campaign.sessions.insert(CampaignDB.cooking_index(), _draft())
	Main.next_seed = 3
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(DRAFT))
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	if game.stage_card != null:
		game.stage_card.skip()
	player = game.player
	player.set_bot(true)
	RunState.invincible = true
	game.pick_panel.input_delay = 0.0
	_replay = {"out": [], "last": -1, "forced": false}
	get_tree().physics_frame.connect(_on_replay_frame)
	while game.path_runner._tick < 905:
		await wait_physics_frames(1)
	get_tree().physics_frame.disconnect(_on_replay_frame)
	var out: Array = [_replay.out, game.path_runner.picks, _replay.forced]
	remove_child(game)
	game.free()
	RunState.reset(0)
	CampaignDB.campaign.sessions.erase(_draft_in_list())
	return out


func _on_replay_frame() -> void:
	# GUT's frame waits resume inside this same signal: a scene freed there may still be called.
	if not is_instance_valid(game) or game.is_queued_for_deletion():
		return
	var r: PathRunner = game.path_runner
	if game.pick_panel.can_choose():
		game.pick_panel.choose(BotRuns.pick_card(RunState.pick_rng, game.pick_panel.offer.cards.size(), ""))
	if r._tick >= 700 and not _replay.forced and r.meter() != null:
		_replay.forced = true
		r.force_level()
	if r._tick % 10 != 0 or r._tick == int(_replay.last) or r._tick > 900 or r._tick == 0:
		return
	_replay.last = r._tick
	var parts: Array[String] = []
	for group: StringName in [&"enemy", &"player_projectile", &"enemy_projectile"]:
		for n in get_tree().get_nodes_in_group(group):
			parts.append("%s %.2f %.2f" % [group, (n as Node2D).global_position.x, (n as Node2D).global_position.y])
	parts.sort()
	parts.append("p %.2f %.2f k %d %s a%d" % [player.global_position.x, player.global_position.y,
			RunState.kills, _loadout().summary(), _loadout().active])
	(_replay.out as Array).append(hash("|".join(parts)))


func test_the_arsenal_draft_replays_to_the_same_hash() -> void:
	var a: Array = await _replay_hashes()
	var b: Array = await _replay_hashes()
	assert_true(bool(a[2]), "a card was forced")
	assert_eq(int(a[1]), 1, "a pick is in the replay")
	assert_eq((a[0] as Array).size(), 90, "15 s, a hash every 10 ticks")
	assert_eq(a[0], b[0], "the same seed, the same 90 hashes")


# --- 15. Power stays in the session ----------------------------------------------------------

func test_arsenal_power_stays_in_the_session() -> void:
	await _draft_game()
	var r: PathRunner = game.path_runner
	RunState.add_basic(&"cards")
	r.announce(&"shotgun")
	_pick(r, 0)
	_loadout().give(&"shotgun")
	remove_child(game)
	game.free()
	CampaignDB.campaign.sessions.erase(_draft_in_list())
	await _session_game(&"s1_06_playground")
	assert_eq(RunState.session_path, &"")
	assert_null(game.path_runner, "Stage 1 has no runner")
	assert_null(game.hud.path_widget, "no hand widget")
	assert_eq(_loadout().summary(), "pistol:1")
	assert_eq(_loadout().quick_draw_mult, 1.0)


# --- 16. The S8 Arsenal draft (3.5 audit rows) ----------------------------------------------

const NUMBER_WORDS := {10: "Ten", 15: "Fifteen", 20: "Twenty", 25: "Twenty-five", 30: "Thirty"}


func test_the_arsenal_draft_is_valid_and_its_audit_rows_hold() -> void:
	var d := _draft()
	assert_eq(d.problems(), [] as Array[String])
	assert_eq(d.path, &"arsenal")
	var cues := d.cue_list()
	var at := func(t: float, action: StringName) -> Array:
		return cues.filter(func(c: Cue) -> bool: return c.when == &"at" and c.value == t and c.action == action)
	assert_eq((at.call(10.0, &"add") as Array).map(func(c: Cue) -> StringName: return c.target), [&"cards"])
	var first: int = _arsenal().threshold(1)
	assert_true(NUMBER_WORDS.has(first), "the first need has a word: %d" % first)
	var say10: Array = at.call(10.0, &"say")
	assert_eq(say10.size(), 1)
	assert_string_contains((say10[0] as Cue).line.text, "%s kills, a new card" % NUMBER_WORDS[first],
			"the line names the .tres's first need")
	assert_eq((at.call(20.0, &"add") as Array).map(func(c: Cue) -> StringName: return c.target), [&"quick_draw"])
	assert_eq((at.call(20.0, &"say") as Array).size(), 1)
	assert_eq((at.call(30.0, &"give") as Array).map(func(c: Cue) -> StringName: return c.target), [&"shotgun"])
	assert_false(&"cards" in d.basics or &"quick_draw" in d.basics, "nothing by default: both are added by cue")
	CampaignDB.campaign.sessions.insert(CampaignDB.cooking_index(), d)
	assert_eq(CampaignDB.problems(CampaignDB.campaign), [] as Array[String], "the carry rule skips path basics")


# --- 17. The fingerprint ---------------------------------------------------------------------

func test_the_fingerprint_values() -> void:
	var r := await _arsenal_arena()
	var lo := _loadout()
	lo.give(&"shotgun")
	var fp := Fingerprint.new()
	var input := player.input as PlayerInput
	player.set_physics_process(false)
	for i in 300:   # 5 s
		input.fire = i < 150
		if i == 100:
			lo.switch(1)
		fp.sample(player)
	player.set_physics_process(true)
	input.fire = false
	var v := fp.values(0, lo.switches, 0)
	assert_almost_eq(float(v.fire_share), 0.5, 1.0 / 300.0)
	assert_almost_eq(float(v.switches_per_min), 12.0, 0.001, "one switch in 5 s")
	assert_eq(float(v.ammo_dry_share), 0.0)
	assert_eq(v.keys().size(), 8)
	# menu_s: wall time from the offer to the pick (the tree is paused meanwhile).
	var clock := [1000]
	r.fp.clock = func() -> int: return clock[0]
	r.want_pick()
	r._open_offer()
	clock[0] = 1250
	game.pick_panel._unlock()
	game.pick_panel.choose(0)
	assert_almost_eq(float(r.fingerprint().menu_s), 0.25, 0.0001)
	assert_gt(float(r.fingerprint().picks_per_min), 0.0)
