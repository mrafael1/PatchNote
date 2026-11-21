extends GutTest
## Parking (PLAN v5 1.3): BIG prompts are gone from play, the gravity pair and
## turn-based are parked (never offered), and the big slot stays an internal seam that
## tests, the F2 console and the bot's --big flag still reach. The slot tests kept from
## v3's BIG prompts (transition swap, history, HUD, report, telemetry) live here.

const Fx := preload("res://tests/gut/fixtures.gd")
const TUNING_KEYS: Array[String] = ["transition_long", "transition_short", "prompt_input_delay",
		"report_delay", "prompts_per_run"]

var world: Node2D
var director: AiDirector
var offers: Array[Offer] = []
var fixtures: Array[Mutation] = []   ## registered in MutationDB by _with_fixtures()
var _saved := {}


func before_each() -> void:
	for key in TUNING_KEYS:
		_saved[key] = Tuning.get(key)
	Taste.clear_session()
	Tuning.transition_long = 0.0
	Tuning.transition_short = 0.0
	Tuning.prompt_input_delay = 0.0
	RunState.reset(31)
	world = Node2D.new()
	add_child_autofree(world)
	RunState.world = world
	director = AiDirector.new()
	add_child_autofree(director)
	director.set_physics_process(false)
	director.prompt_requested.connect(func(o: Offer) -> void: offers.append(o))
	offers.clear()


func after_each() -> void:
	RunState.reset(0)
	RunState.world = null
	for m in fixtures:
		MutationDB.unregister(m)
	fixtures.clear()
	for key: String in _saved:
		Tuning.set(key, _saved[key])
	Taste.clear_session()


## Adds the fixtures of Fx.make_bigs() to the pool: fx_big_a, fx_big_b (big), and the
## small fx_under_a, fx_against_b and fx_on_against_b.
func _with_fixtures() -> void:
	fixtures = Fx.make_bigs()
	for m in fixtures:
		MutationDB.register(m)


# --- Parking -----------------------------------------------------------------

func test_the_parked_patches_and_the_offerable_pool() -> void:
	for id: StringName in [&"turn_mode", &"gravity_on", &"gravity_reversed"]:
		var m := MutationDB.get_mutation(id)
		assert_true(m.parked, "%s is parked" % id)
		assert_false(MutationDB.offerable().has(m))
	for m in MutationDB.offerable():
		assert_false(m.parked)
		assert_false(m.is_big, "%s: no big patch is offerable" % m.id)


func test_no_parked_patch_is_offered_over_200_seeded_prompts() -> void:
	Tuning.prompts_per_run = 1000
	var parked := 0
	for i in 200:
		RunState.reset(1000 + i)
		RunState.world = world
		director.prompt_index = 0
		director.pending = null
		director.open_prompt()
		var offer := offers[-1]
		assert_gt(offer.cards.size(), 0)
		for m in offer.cards:
			if m.parked or m.is_big or m.is_ai_tier():
				parked += 1
		director.pending = null
	assert_eq(parked, 0)


func test_the_director_has_no_big_prompt_left() -> void:
	for method in ["open_big_prompt", "get_big_offer", "big_prompt_due", "big_prompts_per_run",
			"scaffold_due", "add_scaffold"]:
		assert_false(director.has_method(method), "AiDirector.%s is gone" % method)
	assert_false("big_index" in director)
	for key in ["big_prompt_after", "big_offer_size", "ai_scaffold_at_prompt"]:
		assert_false(key in Tuning, "Tuning.%s is gone" % key)
	assert_eq(Tuning.rollback_charges_start, 0, "rollbacks are parked: no charge in play")


func test_prompts_done_needs_only_the_small_prompts() -> void:
	assert_false(director.prompts_done())
	director.prompt_index = Tuning.prompts_per_run
	assert_true(director.prompts_done())
	director.pending = Offer.new()
	assert_false(director.prompts_done(), "a pending choice holds the run")


# --- The big slot as a seam (kept from v3) -----------------------------------

func test_a_swap_through_the_transition_drops_small_patches_that_needed_the_old_big() -> void:
	_with_fixtures()
	var transition := Transition.new()
	add_child_autofree(transition)
	director.transition = transition
	RunState.swap_big(fixtures[0])
	RunState.apply(fixtures[2])
	assert_true(transition.request_swap_big(fixtures[1]))
	assert_eq(RunState.big, fixtures[1])
	assert_false(RunState.stack.has(fixtures[2]))
	assert_false(transition.request_swap_big(fixtures[1]), "already in the slot")
	var lines := PatchHistory.build_log_lines()
	assert_string_contains("\n".join(lines), "MAJOR: fx_big_b [locked]")
	assert_string_contains("\n".join(lines), "fx_under_a dropped by fx_big_b")
	assert_false("\n".join(lines).contains("Revert: fx_under_a"), "a dropped patch is not a rollback")


func test_patch_history_shows_the_big_patch_locked_and_not_selectable() -> void:
	_with_fixtures()
	var history := PatchHistory.new()
	history.director = director
	add_child_autofree(history)
	RunState.swap_big(fixtures[0])
	RunState.apply(MutationDB.get_mutation(&"auto_attack"))
	assert_true(history.open())
	await wait_physics_frames(1)
	var big_rows := 0
	var buttons := 0
	for child in history._list.get_children():
		if child.is_queued_for_deletion():
			continue
		if child.name == "BigEntry":
			big_rows += 1
		elif child is Button:
			buttons += 1
	assert_eq(big_rows, 1)
	assert_eq(buttons, 0, "neither the big nor a small patch can be rolled back (option D)")
	history.close()
	assert_false(director.can_revert(fixtures[0]))
	assert_eq(RunState.revert(fixtures[0]), [] as Array[Mutation])


## PLAN v4 11: a swap that drops a live AI gravity patch plays the gravity safety.
func test_a_swap_preview_with_ai_gravity_live_plays_the_gravity_safety() -> void:
	Tuning.transition_long = 0.1
	var transition := Transition.new()
	add_child_autofree(transition)
	var gravity := MutationDB.get_mutation(&"gravity_on")
	var turns := MutationDB.get_mutation(&"turn_mode")
	var real_time := Fx.make_big(Fx.FxRealTime, &"fx_real_time")
	fixtures = [real_time]
	MutationDB.register(real_time)
	RunState.add_ai(gravity, &"stage")
	# A swap that keeps the AI gravity changes no gravity (the long sequence still plays).
	assert_true(transition.request_swap_big(real_time))
	assert_false(transition.gravity_changed, "the AI gravity stays")
	await wait_for_signal(transition.finished, 2.0)
	assert_eq(RunState.ai, [gravity] as Array[Mutation])
	RunState._grace_until = -1.0   # end the first swap's grace, so the next one shows
	assert_eq(RunState.ai_swap_drops(turns), [gravity] as Array[Mutation], "the preview drops it")
	assert_false(RunState.preview_rules(RunState.stack, turns, [] as Array[Mutation]).gravity_enabled)
	assert_false(RunState.in_grace())
	assert_true(transition.request_swap_big(turns))
	assert_true(transition.gravity_changed, "the swap's preview drops the AI gravity")
	assert_true(transition.busy)
	assert_true(RunState.is_paused_for(&"transition"), "the world freezes before the change")
	assert_true(RunState.rules.gravity_enabled, "not yet")
	await wait_for_signal(transition.finished, 2.0)
	assert_true(RunState.in_grace(), "then the grace")
	assert_true(RunState.ai.is_empty())
	assert_false(RunState.rules.gravity_enabled)
	assert_eq(RunState.big, turns)


func test_hud_names_the_parked_genre_next_to_the_version() -> void:
	var base := "v0.0.0 · build %d" % RunState.build_number
	assert_eq(Hud.version_text(), base)
	RunState.swap_big(MutationDB.get_mutation(&"turn_mode"))
	assert_eq(Hud.version_text(), "v0.0.0 · build %d · Turn-based" % RunState.build_number)


func test_report_and_telemetry_show_genres_and_swaps() -> void:
	_with_fixtures()
	RunState.game_time = 10.0
	RunState.swap_big(fixtures[0])
	RunState.game_time = 70.0
	RunState.swap_big(fixtures[1])
	RunState.game_time = 100.0
	var rec := Telemetry.build_record(&"lose")
	assert_eq((rec.big_offers as Array).size(), 0, "no BIG prompt in v5")
	assert_eq((rec.big_swaps as Array).size(), 2)
	assert_eq(rec.big_swaps[0].from, "")
	assert_eq(rec.big_swaps[1].from, "fx_big_a")
	var seconds: Dictionary = rec.genre_seconds
	assert_almost_eq(float(seconds.base), 10.0, 0.01)
	assert_almost_eq(float(seconds["fx_big_a"]), 60.0, 0.01)
	assert_almost_eq(float(seconds[rec.final_big]), 30.0, 0.01)
	var text := ReportScreen.report_text(&"lose", rec)
	assert_string_contains(text, "Genres      Base 0:10, fx_big_a 1:00")
	assert_eq(ReportScreen.genres_text({"base": 12.0}), "", "no line for a run that stayed in base")
