extends GutTest
## M5: the scripted Director (PLAN 6), rollbacks (PLAN 7; option D from PLAN v4 1.3:
## AI patches only, earned charges), the M14 scaffold patch (PLAN v4 9.1), and their UI.
## Choices go through Director.on_choice / PromptPanel.choose; no synthetic clicks.

const Fx := preload("res://tests/gut/fixtures.gd")
const TUNING_KEYS: Array[String] = ["first_prompt_min_gap", "prompt_min_gap", "transition_long",
		"transition_short", "prompt_input_delay",
		"big_prompt_after", "ai_scaffold_at_prompt", "rollback_charges_start",
		"rollback_charges_per_stage"]


class Victim extends Node2D:
	var kind: StringName = &"enemy"
	var from_spawner := true
	var generation := 0

	func _ready() -> void:
		RunState.register_entity(self, kind)


var world: Node2D
var director: AiDirector
var offers: Array[Offer] = []
var _saved := {}
var _auto_pick := -1   ## >= 0: answer every prompt at once with this card (clamped)


func before_each() -> void:
	for key in TUNING_KEYS:
		_saved[key] = Tuning.get(key)
	Taste.clear_session()
	Tuning.transition_long = 0.0
	Tuning.transition_short = 0.0
	Tuning.prompt_input_delay = 0.0
	Tuning.big_prompt_after = []   # BIG prompts have their own tests (test_big_prompts)
	Tuning.ai_scaffold_at_prompt = 0   # the scaffold has its own tests below
	RunState.reset(11)
	world = Node2D.new()
	add_child_autofree(world)
	RunState.world = world
	_new_director()


func after_each() -> void:
	for key: String in _saved:
		Tuning.set(key, _saved[key])
	RunState.reset(0)
	RunState.world = null


func _new_director() -> void:
	if director:
		director.free()
	director = AiDirector.new()
	add_child_autofree(director)
	director.set_physics_process(false)   # the tests call poll() themselves
	director.prompt_requested.connect(_on_prompt)
	offers.clear()
	_auto_pick = -1


func _on_prompt(offer: Offer) -> void:
	offers.append(offer)
	if _auto_pick >= 0:
		director.on_choice(offer, offer.cards[mini(_auto_pick, offer.cards.size() - 1)])


func _kill(count: int, from_spawner := true, generation := 0) -> void:
	var v := Victim.new()
	v.from_spawner = from_spawner
	v.generation = generation
	world.add_child(v)
	for i in count:
		EventBus.enemy_killed.emit(v, DamageInfo.make(1, &"projectile", &"player"))
	v.free()


func _ids(cards: Array[Mutation]) -> Array[String]:
	var out: Array[String] = []
	for m in cards:
		out.append(String(m.id))
	return out


func _mut(id: StringName) -> Mutation:
	return MutationDB.get_mutation(id)


# --- Pacing ----------------------------------------------------------------

func test_prompt_needs_kills_and_the_minimum_gap_or_the_maximum_gap() -> void:
	var n := Tuning.first_prompt_kills
	var first := Tuning.first_prompt_min_gap
	assert_false(director.should_prompt({"time": first + 1.0, "kills": n - 1}), "not enough kills")
	assert_false(director.should_prompt({"time": first - 1.0, "kills": n * 3}), "too soon")
	assert_true(director.should_prompt({"time": first, "kills": n}))
	assert_true(director.should_prompt({"time": Tuning.prompt_max_gap, "kills": 0}), "the maximum gap alone is enough")


func test_the_first_prompt_has_its_own_minimum_gap() -> void:
	Tuning.first_prompt_min_gap = 20.0
	Tuning.prompt_min_gap = 60.0
	assert_eq(director.min_gap(), 20.0)
	assert_false(director.should_prompt({"time": 19.0, "kills": 1000}))
	assert_true(director.should_prompt({"time": 20.0, "kills": Tuning.first_prompt_kills}))
	_auto_pick = 0
	RunState.game_time += Tuning.first_prompt_min_gap
	_kill(Tuning.first_prompt_kills)
	director.poll()
	assert_eq(offers.size(), 1)
	assert_eq(director.min_gap(), 60.0)
	var n := Tuning.first_prompt_kills + Tuning.prompt_kills_step
	var t := RunState.game_time
	assert_false(director.should_prompt({"time": t + Tuning.prompt_min_gap - 1.0, "kills": n * 3}), "later gaps are longer")
	assert_true(director.should_prompt({"time": t + Tuning.prompt_min_gap, "kills": n}))


func test_shipped_pacing_brings_the_first_prompt_early() -> void:
	assert_lte(_saved.first_prompt_min_gap, _saved.prompt_min_gap)
	assert_lt(_saved.prompt_min_gap, Tuning.prompt_max_gap)


func test_only_spawner_generation_zero_kills_count() -> void:
	_kill(5)
	_kill(7, false)      # spawned by a patch
	_kill(9, true, 1)    # a split copy
	assert_eq(director.context().kills, 5)


func test_kill_threshold_grows_and_the_run_has_four_prompts() -> void:
	_auto_pick = 0
	var needed := Tuning.first_prompt_kills
	for i in Tuning.prompts_per_run:
		RunState.game_time += Tuning.prompt_min_gap
		_kill(needed - 1)
		director.poll()
		assert_eq(offers.size(), i, "one kill short of %d" % needed)
		_kill(1)
		director.poll()
		assert_eq(offers.size(), i + 1)
		needed += Tuning.prompt_kills_step
	RunState.game_time += Tuning.prompt_max_gap * 2.0
	_kill(500)
	director.poll()
	assert_eq(offers.size(), Tuning.prompts_per_run, "no prompt after the last one")


## Kills pour in at 5 per second with horde and split applied: the gap between two
## prompts still never drops under the minimum.
func test_prompts_are_never_closer_than_the_minimum_gap() -> void:
	Tuning.first_prompt_min_gap = 30.0
	Tuning.prompt_min_gap = 70.0
	RunState.apply(MutationDB.get_mutation(&"horde_mode"))
	RunState.apply(MutationDB.get_mutation(&"enemies_split"))
	_auto_pick = 0
	var times: Array[float] = [0.0]
	var seen := 0
	for tick in 60 * 600:
		RunState.game_time += 1.0 / 60.0
		if tick % 12 == 0:
			_kill(1)
		director.poll()
		if offers.size() > seen:
			seen = offers.size()
			times.append(RunState.game_time)
	assert_eq(times.size() - 1, Tuning.prompts_per_run)
	for i in range(1, times.size()):
		var minimum := Tuning.first_prompt_min_gap if i == 1 else Tuning.prompt_min_gap
		assert_gte(times[i] - times[i - 1], minimum - 0.001, "gap before prompt %d" % i)


# --- Offers ----------------------------------------------------------------

func test_offer_is_three_different_applicable_cards() -> void:
	director.open_prompt()
	assert_eq(offers.size(), 1)
	var offer := offers[0]
	assert_eq(offer.prompt_index, 1)
	assert_eq(offer.cards.size(), 3)
	assert_false(offer.mandatory)
	assert_ne(offer.line, "")
	var seen := {}
	for m in offer.cards:
		assert_true(RunState.can_apply(m), "%s can be applied" % m.id)
		assert_false(seen.has(m.id), "no duplicates")
		seen[m.id] = true
	assert_eq(director.pending, offer)
	director.open_prompt()
	assert_eq(offers.size(), 1, "no second prompt while one is waiting")


func test_director_never_offers_what_cannot_be_applied() -> void:
	var rng := RandomNumberGenerator.new()
	var cards_seen := 0
	for run_seed in 60:
		RunState.reset(run_seed)
		_new_director()
		rng.seed = run_seed
		for prompt in Tuning.prompts_per_run:
			director.open_prompt()
			if offers.size() <= prompt:
				break
			var offer := offers[prompt]
			for m in offer.cards:
				cards_seen += 1
				if not RunState.can_apply(m) or director.reverted.has(m.id) or m.is_ai_tier():
					fail_test("seed %d prompt %d offered %s" % [run_seed, prompt + 1, m.id])
					return
			director.on_choice(offer, offer.cards[rng.randi_range(0, offer.cards.size() - 1)])
			# Sometimes revert a small one (the F2 path) and mark it, to exercise the
			# "never again" rule.
			if rng.randf() < 0.4 and not RunState.stack.is_empty():
				var x := RunState.stack[rng.randi_range(0, RunState.stack.size() - 1)]
				for d in RunState.revert(x):
					director.on_revert(d)
	pass_test("%d cards checked" % cards_seen)


func test_same_seed_and_same_choices_give_the_same_offers() -> void:
	var runs: Array = []
	for attempt in 2:
		RunState.reset(4242)
		_new_director()
		var seen: Array = []
		for prompt in Tuning.prompts_per_run:
			director.open_prompt()
			var offer := offers[prompt]
			seen.append(_ids(offer.cards))
			director.on_choice(offer, offer.cards[prompt % offer.cards.size()])
			if prompt == 0:
				RunState.add_ai(_mut(&"gravity_on"), &"stage")
			if prompt == 1:
				assert_true(director.revert(RunState.ai[0]))
		runs.append(seen)
	assert_eq(runs[0], runs[1])
	RunState.reset(4243)
	_new_director()
	director.open_prompt()
	var other := _ids(offers[0].cards)
	RunState.reset(4244)
	_new_director()
	director.open_prompt()
	assert_true(other != runs[0][0] or _ids(offers[0].cards) != runs[0][0], "other seeds differ")


## PLAN v4 9.1: no forced gravity card; mediums never reach a small offer.
func test_no_small_offer_is_forced_or_holds_an_ai_tier_patch() -> void:
	for run_seed in 20:
		RunState.reset(run_seed)
		_new_director()
		_auto_pick = 0
		for prompt in Tuning.prompts_per_run:
			director.open_prompt()
		for offer in offers:
			assert_false(offer.mandatory)
			for m in offer.cards:
				assert_false(m.is_ai_tier(), "seed %d offered %s" % [run_seed, m.id])
	assert_false("force_gravity_at_prompt" in Tuning, "the forced card is gone")
	assert_false("reverts_per_run" in Tuning)


## PLAN v4 11 (DB rules) and 5: fixture mediums and a boss-only patch never reach a
## small offer, and a small that conflicts with a live AI patch is withheld.
func test_fixture_ai_tier_patches_are_never_offered_and_withhold_their_conflicts() -> void:
	var fx := Fx.make_ai_set()
	for m in fx:
		MutationDB.register(m)
	var against := fx[4]
	var seen_against := false
	for run_seed in 20:
		RunState.reset(run_seed)
		_new_director()
		if run_seed % 2 == 1:
			RunState.add_ai(fx[0], &"stage")
		for prompt in Tuning.prompts_per_run:
			director.open_prompt()
			if offers.size() <= prompt:
				break
			for m in offers[prompt].cards:
				if m.is_ai_tier() or (run_seed % 2 == 1 and m == against):
					fail_test("seed %d offered %s" % [run_seed, m.id])
				seen_against = seen_against or m == against
			director.on_choice(offers[prompt], offers[prompt].cards[0])
	for m in fx:
		MutationDB.unregister(m)
	assert_true(seen_against, "the small one is offered when nothing withholds it")


func test_small_pool_gives_fewer_cards_and_an_empty_pool_is_skipped() -> void:
	var smalls := MutationDB.all.filter(func(m: Mutation) -> bool: return not m.is_big and not m.is_ai_tier())
	for m in smalls:
		if RunState.stack.size() < smalls.size() - 2 and RunState.can_apply(m):
			RunState.apply(m)
	director.open_prompt()
	assert_eq(offers[0].cards.size(), 2, "only two left to offer")
	director.on_choice(offers[0], offers[0].cards[0])
	for m in MutationDB.all:
		if RunState.can_apply(m):
			RunState.apply(m)
	director.open_prompt()
	assert_eq(offers.size(), 1, "nothing to offer: no prompt")
	assert_null(director.pending)
	assert_eq(RunState.run_log[-1].event, &"prompt_skipped")


func test_choice_is_logged_with_the_offer() -> void:
	director.open_prompt()
	var offer := offers[0]
	director.on_choice(offer, offer.cards[1])
	assert_true(RunState.has_patch(offer.cards[1].id))
	assert_null(director.pending)
	var entry: Dictionary = {}
	for e: Dictionary in RunState.run_log:
		if e.event == &"prompt":
			entry = e
	assert_eq(entry.get("index"), 1)
	assert_eq(entry.get("offers"), _ids(offer.cards))
	assert_eq(entry.get("pick"), String(offer.cards[1].id))
	assert_true(RunState.in_grace(), "same grace as a transition when the prompt closes")


# --- Rollbacks (option D) --------------------------------------------------------

func test_charges_start_at_one_and_each_stage_clear_adds_one() -> void:
	assert_eq(director.charges, 1)
	assert_eq(director.charges_earned, 1)
	director.add_stage_charge()
	assert_eq(director.charges, 2)
	director.add_stage_charge()
	assert_eq(director.charges, 3)
	assert_eq(director.charges_earned, 3)
	assert_eq(RunState.run_log[-1].event, &"charge_earned")


func test_can_revert_is_false_for_every_stack_patch() -> void:
	director.charges = 5
	for m in MutationDB.all:
		if RunState.can_apply(m):
			RunState.apply(m)
	assert_gt(RunState.stack.size(), 0)
	for m in RunState.stack:
		assert_false(director.can_revert(m), String(m.id))
		assert_false(director.revert(m), String(m.id))
	assert_eq(director.charges, 5, "nothing spent")
	assert_false(director.can_revert(null))


func test_an_ai_rollback_costs_one_charge_and_takes_its_dependents() -> void:
	var gravity := _mut(&"gravity_on")
	var reversed := _mut(&"gravity_reversed")
	var horde := _mut(&"horde_mode")
	RunState.apply(horde)
	RunState.add_ai(gravity, &"stage")
	RunState.add_ai(reversed, &"stage")
	director.add_stage_charge()
	assert_eq(director.charges, 2)
	var build := RunState.build_number
	assert_true(director.can_revert(gravity))
	assert_true(director.revert(gravity))
	assert_eq(director.charges, 1, "gravity and its dependent went for one charge")
	assert_true(RunState.ai.is_empty())
	assert_eq(RunState.stack, [horde] as Array[Mutation], "the stack is untouched")
	assert_eq(RunState.build_number, build + 1)
	var entry: Dictionary = RunState.run_log[-1]
	assert_eq(entry.event, &"revert_used")
	assert_eq(entry.id, "gravity_on")
	assert_eq(entry.owner, "stage")
	assert_true(entry.has("hp"))
	assert_eq(entry.removed, 2)
	var removal: Dictionary = RunState.run_log[-2]
	assert_eq(removal.event, &"ai_remove")
	assert_eq(removal.reason, &"rollback")
	assert_false(director.revert(gravity), "not live any more")


func test_no_rollback_without_a_charge() -> void:
	var gravity := _mut(&"gravity_on")
	RunState.add_ai(gravity, &"stage")
	director.charges = 0
	assert_false(director.can_revert(gravity))
	assert_false(director.revert(gravity))
	assert_true(RunState.ai.has(gravity))


func test_expiry_costs_no_charge_and_logs_expired() -> void:
	# Through a transition with the director attached, as a stage end will (M16).
	var transition := Transition.new()
	add_child_autofree(transition)
	director.transition = transition
	var gravity := _mut(&"gravity_on")
	RunState.add_ai(gravity, &"stage")
	assert_true(transition.request_ai_remove(gravity, &"expired"))
	assert_true(RunState.ai.is_empty())
	RunState.add_ai(gravity, &"stage")
	RunState.expire_ai(&"stage")
	assert_eq(director.charges, 1)
	assert_eq(RunState.run_log[-1].event, &"ai_remove")
	assert_eq(RunState.run_log[-1].reason, &"expired")
	for e: Dictionary in RunState.run_log:
		assert_ne(e.event, &"revert_used", "an expiry is not a rollback")
	director.transition = null


func test_an_ai_rollback_never_writes_reverted() -> void:
	var gravity := _mut(&"gravity_on")
	RunState.add_ai(gravity, &"stage")
	assert_true(director.revert(gravity))
	assert_true(director.reverted.is_empty())
	assert_true(RunState.can_add_ai(gravity), "it can come back later")


func test_a_stage_rollback_lowers_taste_and_a_boss_rollback_does_not() -> void:
	var gravity := _mut(&"gravity_on")
	var reversed := _mut(&"gravity_reversed")
	director.charges = 2
	RunState.add_ai(gravity, &"boss")
	var before := director.taste.to_dict()
	assert_true(director.revert(gravity))
	assert_eq(director.taste.to_dict(), before, "a boss rollback is tactics, not taste")
	assert_eq(RunState.run_log[-1].owner, "boss")
	RunState.add_ai(gravity, &"stage")
	RunState.add_ai(reversed, &"stage")
	assert_true(director.revert(gravity))
	assert_lt(director.taste.score(gravity), 0.0)
	var ids: Dictionary = director.taste.to_dict().ids
	assert_lt(float(ids.get("gravity_on", 0.0)), 0.0)
	assert_lt(float(ids.get("gravity_reversed", 0.0)), 0.0, "its dependent went too")


func test_a_mixed_owner_rollback_lowers_only_the_stage_patch_taste() -> void:
	var gravity := _mut(&"gravity_on")
	var reversed := _mut(&"gravity_reversed")
	RunState.add_ai(gravity, &"stage")
	RunState.add_ai(reversed, &"boss")
	assert_true(director.revert(gravity))
	assert_true(RunState.ai.is_empty(), "the boss-owned dependent went too")
	var ids: Dictionary = director.taste.to_dict().ids
	assert_lt(float(ids.get("gravity_on", 0.0)), 0.0)
	assert_false(ids.has("gravity_reversed"), "a boss patch teaches no taste")


func test_reverted_patches_are_not_offered_again() -> void:
	var horde := _mut(&"horde_mode")
	RunState.apply(horde)
	RunState.revert(horde)
	director.on_revert(horde)
	for seed_value in 30:
		RunState.director_rng.seed = seed_value
		director.pending = null
		director.prompt_index = 0
		director.open_prompt()
		assert_false(offers[-1].cards.has(horde))


# --- M14 scaffold (PLAN v4 9.1) --------------------------------------------------

func test_the_scaffold_patch_is_chosen_by_data() -> void:
	var m := AiDirector.scaffold_patch()
	assert_not_null(m)
	assert_true(m.is_medium and m.is_mode_switch)
	for x in MutationDB.all:
		if x == m:
			break
		assert_false(x.is_medium and x.is_mode_switch, "the first one in MutationDB order")


func test_the_scaffold_lands_after_the_last_small_prompt_as_a_stage_patch() -> void:
	Tuning.ai_scaffold_at_prompt = Tuning.prompts_per_run
	_auto_pick = 0
	for i in Tuning.prompts_per_run:
		assert_false(director.scaffold_due())
		director.open_prompt()
	assert_true(RunState.ai.is_empty(), "not before the prompt is answered and polled")
	assert_true(director.scaffold_due())
	assert_false(director.prompts_done(), "the run loop waits for it")
	director.poll()
	var m := AiDirector.scaffold_patch()
	assert_eq(RunState.ai, [m] as Array[Mutation])
	assert_eq(RunState.ai_owner[m.id], &"stage")
	assert_true(director.prompts_done())
	assert_eq(offers.size(), Tuning.prompts_per_run, "no extra prompt")
	director.poll()
	assert_eq(RunState.ai.size(), 1, "added once")
	assert_true(director.revert(m), "a rollback target")


func test_the_scaffold_is_skipped_when_it_conflicts_with_the_live_state() -> void:
	Tuning.ai_scaffold_at_prompt = 1
	RunState.swap_big(_mut(&"turn_mode"))
	_auto_pick = 0
	director.open_prompt()
	director.poll()
	assert_true(RunState.ai.is_empty(), "gravity conflicts with Turn-based")
	assert_eq(RunState.run_log[-1].event, &"ai_scaffold_skipped")
	assert_false(director.scaffold_due())


# --- In the game -----------------------------------------------------------

func _start_game() -> Node:
	var game: Node = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	await wait_physics_frames(2)
	return game


func test_prompt_panel_pauses_and_a_choice_applies_the_patch_and_heals() -> void:
	var game: Node = await _start_game()
	var health := Component.find(game.player, Health) as Health
	health.take(DamageInfo.make(2.0, &"contact", &"enemy"))
	assert_almost_eq(health.hp(), 3.0, 0.01)
	game.director.open_prompt()
	await wait_process_frames(2)
	assert_true(game.prompt_panel.is_open())
	assert_true(RunState.is_paused_for(&"prompt"))
	assert_false(game.patch_history.open(), "the build log is unavailable during a prompt")
	var offer: Offer = game.prompt_panel.offer
	game.prompt_panel.choose(0)
	assert_false(game.prompt_panel.is_open())
	assert_false(get_tree().paused)
	assert_true(RunState.has_patch(offer.cards[0].id))
	assert_almost_eq(health.hp(), 4.0, 0.01, "hotfix: every patch heals one HP")
	game.prompt_panel.choose(0)
	assert_eq(RunState.stack.size(), 1, "a closed panel ignores input")


func test_prompt_ignores_input_right_after_opening() -> void:
	Tuning.prompt_input_delay = 30.0   # far longer than the frames this test lets pass
	var game: Node = await _start_game()
	game.director.open_prompt()
	await wait_process_frames(2)
	game.prompt_panel.choose(0)
	assert_true(game.prompt_panel.is_open(), "too early")
	assert_eq(RunState.stack.size(), 0)
	# The tree is paused, so step the panel's own clock instead of waiting on a timer.
	game.prompt_panel._process(31.0)
	game.prompt_panel.choose(0)
	assert_false(game.prompt_panel.is_open())
	assert_eq(RunState.stack.size(), 1)


func test_hotfix_never_heals_above_the_maximum() -> void:
	var game: Node = await _start_game()
	var health := Component.find(game.player, Health) as Health
	game.director.open_prompt()
	await wait_process_frames(2)
	game.prompt_panel.choose(0)
	assert_almost_eq(health.hp(), 5.0, 0.01)


func test_patch_history_shows_the_build_log_and_rolls_back_on_confirm() -> void:
	var game: Node = await _start_game()
	var gravity := _mut(&"gravity_on")
	var reversed := _mut(&"gravity_reversed")
	var horde := _mut(&"horde_mode")
	game.transition.request_apply(horde)
	game.transition.request_ai_add(gravity, &"stage")
	game.transition.request_ai_add(reversed, &"stage")
	assert_eq(RunState.ai, [gravity, reversed] as Array[Mutation])
	var history: PatchHistory = game.patch_history
	assert_true(history.open())
	assert_true(RunState.is_paused_for(&"history"))
	assert_eq(PatchHistory.build_log_lines(), ["v0.1  Initial build", "v0.2  " + horde.title,
			"v0.3  AI patch (undocumented)", "v0.4  AI patch (undocumented)"] as Array[String])
	await wait_process_frames(1)
	var ai_buttons: Array[String] = []
	for child in history._ai_list.get_children():
		if child is Button and not child.is_queued_for_deletion():
			ai_buttons.append((child as Button).text)
	assert_eq(ai_buttons, ["Roll back: " + PatchHistory.UNDOCUMENTED,
			"Roll back: " + PatchHistory.UNDOCUMENTED] as Array[String])
	var yours: Array[String] = []
	for child in history._list.get_children():
		assert_false(child is Button, "the player's own patches have no rollback")
		if child is Label and not child.is_queued_for_deletion():
			yours.append((child as Label).text)
	assert_eq(yours, [horde.title] as Array[String])
	_assert_no_title_shown(history, gravity)
	_assert_no_title_shown(history, reversed)
	history.press_revert(horde.id)
	history.press_revert(horde.id)
	assert_true(history.is_open(), "a stack patch is no target")
	history.press_revert(gravity.id)
	assert_eq(RunState.ai.size(), 2, "the first press only asks for confirmation")
	assert_true(history.is_open())
	await wait_process_frames(1)
	_assert_no_title_shown(history, gravity)
	history.press_revert(gravity.id)
	assert_false(history.is_open())
	assert_false(get_tree().paused)
	assert_true(RunState.ai.is_empty(), "gravity and its dependent are gone")
	assert_eq(RunState.stack, [horde] as Array[Mutation])
	assert_eq(game.director.charges, 0)
	await wait_process_frames(1)
	assert_string_contains(_hud(game)._label.text, "Rollbacks: 0 [Tab]", "the HUD reads the charges left")
	assert_eq(PatchHistory.build_log_lines(), ["v0.1  Initial build", "v0.2  " + horde.title,
			"v0.3  AI patch: " + gravity.title, "v0.4  AI patch: " + reversed.title,
			"v0.5  Rollback: " + reversed.title, "v0.5  Rollback: " + gravity.title] as Array[String],
			"a rollback names what it removed")
	var opens := 0
	for e: Dictionary in RunState.run_log:
		if e.event == &"history_open":
			opens += 1
	assert_eq(opens, 1, "opening the log is recorded")
	history.open()
	history.close()
	assert_false(get_tree().paused)


func test_the_report_names_stage_patches() -> void:
	var gravity := _mut(&"gravity_on")
	RunState.add_ai(gravity, &"stage")
	assert_false(PatchHistory.build_log_lines().has("v0.2  AI patch: " + gravity.title))
	assert_true(PatchHistory.build_log_lines(true).has("v0.2  AI patch: " + gravity.title))


func test_a_boss_patch_is_named_in_the_history() -> void:
	var gravity := _mut(&"gravity_on")
	RunState.add_ai(gravity, &"boss")
	assert_eq(PatchHistory.ai_label(gravity), "Boss patch: " + gravity.title)
	assert_true(PatchHistory.build_log_lines().has("v0.2  AI patch: " + gravity.title))


## In the game, the scaffold goes through the transition: an AI gravity change gets
## the pause, the undocumented terminal text, the grace and the AI line.
func test_the_scaffold_lands_through_the_transition() -> void:
	Tuning.transition_long = 0.12
	Tuning.ai_scaffold_at_prompt = 1
	var game: Node = await _start_game()
	var transition: Transition = game.transition
	var m := AiDirector.scaffold_patch()
	game.director.prompt_index = 1   # as if small prompt 1 had been answered
	await wait_physics_frames(2)
	assert_true(transition.busy, "the long sequence runs")
	assert_true(RunState.is_paused_for(&"transition"))
	assert_true(RunState.ai.is_empty(), "added after the terminal text")
	assert_string_contains(transition._terminal.text, "(undocumented)")
	assert_false(transition._terminal.text.contains(m.title), "a stage patch is not named")
	assert_false(transition._terminal.text.contains(String(m.id)))
	await wait_for_signal(transition.finished, 2.0)
	assert_eq(RunState.ai, [m] as Array[Mutation])
	assert_eq(RunState.ai_owner[m.id], &"stage")
	assert_false(RunState.is_paused_for(&"transition"))
	assert_true(RunState.in_grace())
	assert_eq(transition._toast.text, "AI: " + Dialogue.AI_SCAFFOLD)


## F2 (PLAN v4 9.2 Debug): an AI-tier patch is added as a stage patch and removed again,
## with no charge spent and no rollback logged.
func test_the_console_adds_and_removes_ai_patches() -> void:
	var game: Node = await _start_game()
	var overlay: DebugOverlay = null
	for child in game.get_children():
		if child is DebugOverlay:
			overlay = child
	assert_not_null(overlay)
	var gravity := _mut(&"gravity_on")
	var button: Button = overlay._buttons[gravity.id]
	assert_string_contains(button.text, " MED gravity_on")
	overlay.toggle_mutation(gravity.id)
	assert_eq(RunState.ai, [gravity] as Array[Mutation])
	assert_eq(RunState.ai_owner[gravity.id], &"stage")
	assert_true(button.text.begins_with("[x]"))
	overlay.toggle_mutation(gravity.id)
	assert_true(RunState.ai.is_empty())
	assert_eq(game.director.charges, 1, "no charge spent")
	assert_eq(RunState.run_log[-1].event, &"ai_remove")
	assert_eq(RunState.run_log[-1].reason, &"console", "not a rollback")
	for e: Dictionary in RunState.run_log:
		assert_ne(e.event, &"revert_used")
	overlay.toggle_mutation(&"gravity_reversed")
	assert_eq(RunState.ai, [_mut(&"gravity_reversed")] as Array[Mutation], "forced, like a console")


func test_hud_shows_the_rollback_charges() -> void:
	var game: Node = await _start_game()
	await wait_process_frames(2)
	var hud := _hud(game)
	assert_not_null(hud)
	assert_string_contains(hud._label.text, "Rollbacks: 1 [Tab]")


func _hud(game: Node) -> Hud:
	for child in game.get_children():
		if child is Hud:
			return child
	return null


## No Label or Button text under the history names m (title or id).
func _assert_no_title_shown(history: PatchHistory, m: Mutation) -> void:
	var stack: Array[Node] = [history]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n.is_queued_for_deletion():
			continue
		var text := ""
		if n is Label:
			text = (n as Label).text
		elif n is Button:
			text = (n as Button).text
		if text.contains(m.title) or text.contains(String(m.id)):
			fail_test("history shows %s: %s" % [m.id, text])
			return
