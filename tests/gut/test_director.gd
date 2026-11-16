extends GutTest
## M5: the scripted Director (PLAN 6), reverts (PLAN 7), and their UI.
## Choices go through Director.on_choice / PromptPanel.choose; no synthetic clicks.

const Fx := preload("res://tests/gut/fixtures.gd")
const TUNING_KEYS: Array[String] = ["transition_long", "transition_short", "prompt_input_delay",
		"force_gravity_at_prompt"]


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
	Tuning.transition_long = 0.0
	Tuning.transition_short = 0.0
	Tuning.prompt_input_delay = 0.0
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


func _mode_switch() -> Mutation:
	for m in MutationDB.all:
		if m.is_mode_switch:
			return m
	return null


# --- Pacing ----------------------------------------------------------------

func test_prompt_needs_kills_and_the_minimum_gap_or_the_maximum_gap() -> void:
	var n := Tuning.first_prompt_kills
	assert_false(director.should_prompt({"time": Tuning.prompt_min_gap + 1.0, "kills": n - 1}), "not enough kills")
	assert_false(director.should_prompt({"time": Tuning.prompt_min_gap - 1.0, "kills": n * 3}), "too soon")
	assert_true(director.should_prompt({"time": Tuning.prompt_min_gap, "kills": n}))
	assert_true(director.should_prompt({"time": Tuning.prompt_max_gap, "kills": 0}), "the maximum gap alone is enough")


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
		assert_gte(times[i] - times[i - 1], Tuning.prompt_min_gap - 0.001, "gap before prompt %d" % i)


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
	Tuning.force_gravity_at_prompt = 0
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
				if not RunState.can_apply(m) or director.reverted.has(m.id):
					fail_test("seed %d prompt %d offered %s" % [run_seed, prompt + 1, m.id])
					return
			director.on_choice(offer, offer.cards[rng.randi_range(0, offer.cards.size() - 1)])
			# Sometimes roll something back, to exercise the "never again" rule.
			if rng.randf() < 0.4 and not RunState.stack.is_empty():
				director.revert(RunState.stack[rng.randi_range(0, RunState.stack.size() - 1)])
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
			if prompt == 1:
				director.revert(RunState.stack[0])
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


func test_second_prompt_forces_the_mode_switch_if_it_is_missing() -> void:
	var switch := _mode_switch()
	director.open_prompt()
	var first := offers[0]
	var pick: Mutation = null
	for m in first.cards:
		if m != switch:
			pick = m
	director.on_choice(first, pick)
	director.open_prompt()
	var second := offers[1]
	assert_true(second.mandatory)
	assert_eq(second.cards.size(), 1)
	assert_eq(second.cards[0], switch)
	assert_eq(second.line, Dialogue.MANDATORY)


func test_no_forced_card_when_the_mode_switch_is_already_applied_or_disabled() -> void:
	RunState.apply(_mode_switch())
	director.open_prompt()
	director.on_choice(offers[0], offers[0].cards[0])
	director.open_prompt()
	assert_false(offers[1].mandatory, "already applied")

	RunState.reset(11)
	_new_director()
	Tuning.force_gravity_at_prompt = 0
	director.open_prompt()
	director.on_choice(offers[0], offers[0].cards[0])
	director.open_prompt()
	assert_false(offers[1].mandatory, "disabled by the tuning flag")


func test_small_pool_gives_fewer_cards_and_an_empty_pool_is_skipped() -> void:
	Tuning.force_gravity_at_prompt = 0
	for m in MutationDB.all:
		if RunState.stack.size() < MutationDB.all.size() - 2 and RunState.can_apply(m):
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


# --- Reverts ---------------------------------------------------------------

func test_two_reverts_per_run_and_a_cascade_costs_one() -> void:
	var gravity := MutationDB.get_mutation(&"gravity_on")
	var reversed := MutationDB.get_mutation(&"gravity_reversed")
	var horde := MutationDB.get_mutation(&"horde_mode")
	var split := MutationDB.get_mutation(&"enemies_split")
	for m: Mutation in [gravity, reversed, horde, split]:
		RunState.apply(m)
	assert_eq(director.reverts_left, 2)
	var build := RunState.build_number
	assert_true(director.revert(gravity))
	assert_eq(director.reverts_left, 1, "gravity and its dependent went for one charge")
	assert_eq(RunState.stack.size(), 2)
	assert_eq(RunState.build_number, build + 1)
	assert_true(director.reverted.has(gravity.id) and director.reverted.has(reversed.id))
	var entry: Dictionary = RunState.run_log[-1]
	assert_eq(entry.event, &"revert_used")
	assert_eq(entry.removed, 2)
	assert_false(director.revert(gravity), "not in the stack any more")
	assert_true(director.revert(horde))
	assert_eq(director.reverts_left, 0)
	assert_false(director.can_revert(split))
	assert_false(director.revert(split), "out of charges")
	assert_true(RunState.has_patch(split.id))


func test_reverted_patches_are_not_offered_again() -> void:
	Tuning.force_gravity_at_prompt = 0
	var horde := MutationDB.get_mutation(&"horde_mode")
	RunState.apply(horde)
	director.revert(horde)
	for seed_value in 30:
		RunState.director_rng.seed = seed_value
		director.pending = null
		director.prompt_index = 0
		director.open_prompt()
		assert_false(offers[-1].cards.has(horde))


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
	var gravity := MutationDB.get_mutation(&"gravity_on")
	game.transition.request_apply(gravity)
	game.transition.request_apply(MutationDB.get_mutation(&"gravity_reversed"))
	var history: PatchHistory = game.patch_history
	assert_true(history.open())
	assert_true(RunState.is_paused_for(&"history"))
	assert_eq(history.build_log_lines(), ["v0.1  Initial build", "v0.2  Implement gravity",
			"v0.3  Reverse gravity"] as Array[String])
	history.press_revert(gravity.id)
	assert_eq(RunState.stack.size(), 2, "the first press only asks for confirmation")
	assert_true(history.is_open())
	history.press_revert(gravity.id)
	assert_false(history.is_open())
	assert_false(get_tree().paused)
	assert_eq(RunState.stack.size(), 0, "gravity and its dependent are gone")
	assert_eq(game.director.reverts_left, 1)
	assert_eq(history.build_log_lines().slice(3), ["v0.4  Revert: Reverse gravity",
			"v0.4  Revert: Implement gravity"] as Array[String])
	var opens := 0
	for e: Dictionary in RunState.run_log:
		if e.event == &"history_open":
			opens += 1
	assert_eq(opens, 1, "opening the log is recorded")
	history.open()
	history.close()
	assert_false(get_tree().paused)
