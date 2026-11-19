extends GutTest
## BIG prompts (PLAN v3 sections 4-6): schedule, offers, Keep, taste, the choice
## routed to the big slot, and what the panel, history, HUD, report and telemetry show.

const Fx := preload("res://tests/gut/fixtures.gd")
const TUNING_KEYS: Array[String] = ["transition_long", "transition_short", "prompt_input_delay",
		"force_gravity_at_prompt", "big_prompt_after", "big_offer_size", "report_delay"]

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
	Tuning.force_gravity_at_prompt = 0
	Tuning.big_prompt_after = [1, 3]
	Tuning.big_offer_size = 2
	RunState.reset(31)
	world = Node2D.new()
	add_child_autofree(world)
	RunState.world = world
	_new_director()


func after_each() -> void:
	RunState.reset(0)
	RunState.world = null
	for m in fixtures:
		MutationDB.unregister(m)
	fixtures.clear()
	for key: String in _saved:
		Tuning.set(key, _saved[key])
	Taste.clear_session()


func _new_director() -> void:
	if director:
		director.free()
	director = AiDirector.new()
	add_child_autofree(director)
	director.set_physics_process(false)
	director.prompt_requested.connect(func(o: Offer) -> void: offers.append(o))
	offers.clear()


## Adds fx_big_a, fx_big_b (big) and fx_under_a (small, requires fx_big_a) to the pool.
func _with_fixtures() -> void:
	fixtures = Fx.make_bigs()
	for m in fixtures:
		MutationDB.register(m)


func _ids(cards: Array[Mutation]) -> Array[String]:
	var out: Array[String] = []
	for m in cards:
		out.append(String(m.id))
	return out


## Opens the next small prompt and answers it with its first card.
func _small_prompt() -> void:
	director.open_prompt()
	director.on_choice(offers[-1], offers[-1].cards[0])


# --- Schedule ----------------------------------------------------------------

func test_big_prompts_open_right_after_the_listed_small_prompts() -> void:
	_with_fixtures()
	var kinds: Array[String] = []
	for i in Tuning.prompts_per_run:
		_small_prompt()
		director.poll()   # no kills, no time: only a due BIG prompt can open
		kinds.append("big" if offers[-1].big else "small")
		if offers[-1].big:
			director.on_choice(offers[-1], offers[-1].cards[0])
	assert_eq(kinds, ["big", "small", "big", "small"] as Array[String])
	assert_eq(director.big_index, 2)
	assert_true(director.prompts_done())
	director.poll()
	assert_eq(offers.filter(func(o: Offer) -> bool: return o.big).size(), 2, "never a third")


func test_the_run_loop_waits_for_a_due_big_prompt() -> void:
	for i in Tuning.prompts_per_run:
		director.prompt_index += 1
	assert_false(director.prompts_done(), "two BIG prompts still to come")
	director.big_index = director.big_prompts_per_run()
	assert_true(director.prompts_done())
	Tuning.big_prompt_after = [1, 3, 9]
	assert_eq(director.big_prompts_per_run(), 2, "a BIG prompt after a prompt that never comes does not count")


func test_with_only_b1_the_first_big_prompt_offers_it_and_the_second_is_skipped() -> void:
	_small_prompt()
	director.poll()
	var first := offers[-1]
	assert_true(first.big)
	assert_eq(_ids(first.cards), ["motion_time"] as Array[String])
	assert_eq(first.agenda.size(), 0, "one candidate: no agenda card")
	assert_null(first.keep, "no Keep card on the first BIG prompt")
	assert_eq(first.line, MutationDB.get_mutation(&"motion_time").line_proposal)
	director.on_choice(first, first.cards[0])
	assert_eq(RunState.big, MutationDB.get_mutation(&"motion_time"))
	_small_prompt()
	_small_prompt()
	var before := offers.size()
	director.poll()
	assert_eq(offers.size(), before, "nothing to swap to: no BIG prompt")
	assert_eq(RunState.run_log[-1].event, &"big_prompt_skipped")
	assert_eq(director.big_index, 2)


# --- Offers ------------------------------------------------------------------

func test_big_offers_never_hold_the_slotted_patch_and_later_ones_add_keep() -> void:
	_with_fixtures()
	_small_prompt()
	director.poll()
	var first := offers[-1]
	assert_eq(first.cards.size(), 2)
	assert_eq(first.agenda.size(), 1, "three candidates: one agenda card")
	assert_eq(first.cards[-1], first.agenda[0], "the AI's pick comes last")
	for m in first.cards:
		assert_true(m.is_big)
	director.on_choice(first, first.cards[0])
	var slotted := RunState.big
	_small_prompt()
	_small_prompt()
	director.poll()
	var second := offers[-1]
	assert_true(second.big)
	assert_eq(second.keep, slotted)
	assert_eq(second.cards[-1], slotted, "Keep comes last")
	assert_eq(second.cards.size(), 3, "two big patches and Keep")
	for i in second.cards.size() - 1:
		assert_ne(second.cards[i], slotted, "the slotted patch is only offered as Keep")


func test_same_seed_and_same_choices_give_the_same_big_offers() -> void:
	_with_fixtures()
	var runs: Array = []
	for run in 2:
		RunState.reset(77)
		_new_director()
		for i in Tuning.prompts_per_run:
			_small_prompt()
			director.poll()
			if offers[-1].big:
				director.on_choice(offers[-1], offers[-1].cards[0])
		runs.append(offers.filter(func(o: Offer) -> bool: return o.big).map(
				func(o: Offer) -> Array[String]: return _ids(o.cards)))
	assert_eq(runs[0], runs[1])
	assert_eq((runs[0] as Array).size(), 2)


func test_the_big_agenda_card_is_the_least_liked_big_patch() -> void:
	_with_fixtures()
	for m in MutationDB.all:
		if m.is_big and m.id != &"fx_big_b":
			director.taste.on_rating(m, 1)
	_small_prompt()
	director.poll()
	assert_eq(_ids(offers[-1].agenda), ["fx_big_b"] as Array[String])


# --- Choices -----------------------------------------------------------------

func test_picking_a_big_card_swaps_heals_logs_and_teaches_the_taste() -> void:
	_with_fixtures()
	_small_prompt()
	director.poll()
	var offer := offers[-1]
	var pick := offer.cards[0]
	var build := RunState.build_number
	director.on_choice(offer, pick)
	assert_eq(RunState.big, pick)
	assert_eq(RunState.build_number, build + 1, "one build")
	assert_null(director.pending)
	assert_true(RunState.in_grace())
	var entry: Dictionary = RunState.run_log.filter(func(e: Dictionary) -> bool: return e.event == &"big_prompt")[0]
	assert_eq(entry.pick, String(pick.id))
	assert_eq(entry.offers, _ids(offer.cards))
	assert_false(entry.kept)
	assert_gt(director.taste.score(pick), 0.0)
	assert_eq(RunState.run_log.filter(func(e: Dictionary) -> bool: return e.event == &"prompt").size(), 1,
			"a BIG choice is not logged as a small prompt")


func test_keep_changes_nothing_but_counts_as_a_pick() -> void:
	_with_fixtures()
	RunState.swap_big(fixtures[0])
	director.big_index = 1
	director.prompt_index = 3
	director.poll()
	var offer := offers[-1]
	assert_eq(offer.keep, fixtures[0])
	var build := RunState.build_number
	director.on_choice(offer, offer.keep)
	assert_eq(RunState.big, fixtures[0])
	assert_eq(RunState.build_number, build, "no new build")
	assert_true(RunState.run_log[-1].kept)
	assert_gt(director.taste.score(fixtures[0]), 0.0)
	for m in offer.cards:
		if m != offer.keep:
			assert_lt(director.taste.score(m), 0.0, "passed over")


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


# --- Presentation ------------------------------------------------------------

func test_the_prompt_panel_frames_a_big_prompt_and_its_keep_card() -> void:
	_with_fixtures()
	var panel := PromptPanel.new()
	add_child_autofree(panel)
	panel.chosen.connect(director.on_choice)
	RunState.swap_big(fixtures[0])
	director.big_index = 1
	director.prompt_index = 3
	director.poll()
	var offer := offers[-1]
	panel.open(offer)
	await wait_physics_frames(1)
	assert_true(panel.is_open())
	assert_true(panel._major.visible, "MAJOR UPDATE header")
	assert_true(panel._footer.visible)
	assert_eq(panel._footer.text, Dialogue.BIG_FOOTER)
	var keep_text := PromptPanel.card_text(offer, offer.cards.size() - 1)
	assert_true(keep_text.contains("KEEP: fx_big_a"), keep_text)
	assert_true(PromptPanel.card_text(offer, 0).contains("(%s)" % offer.cards[0].genre_label))
	panel.choose(0)
	assert_eq(RunState.big, offer.cards[0])
	assert_false(RunState.is_paused_for(&"prompt"))
	# A small prompt afterwards has no MAJOR frame.
	var small := Offer.new()
	small.cards = [MutationDB.get_mutation(&"auto_attack")]
	panel.open(small)
	await wait_physics_frames(1)
	assert_false(panel._major.visible)
	assert_false(panel._footer.visible)
	panel.choose(0)


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
	assert_eq(buttons, 1, "only the small patch can be rolled back")
	history.close()
	assert_false(director.can_revert(fixtures[0]))
	assert_eq(RunState.revert(fixtures[0]), [] as Array[Mutation])


func test_hud_names_the_genre_next_to_the_version() -> void:
	assert_eq(Hud.version_text(), RunState.version_label())
	RunState.swap_big(MutationDB.get_mutation(&"motion_time"))
	assert_eq(Hud.version_text(), "%s · Motion time" % RunState.version_label())


func test_report_and_telemetry_show_genres_big_offers_and_swaps() -> void:
	_with_fixtures()
	RunState.game_time = 10.0
	_small_prompt()
	director.poll()
	director.on_choice(offers[-1], offers[-1].cards[0])
	var first_big := RunState.big
	RunState.game_time = 70.0
	RunState.swap_big(fixtures[1] if first_big != fixtures[1] else fixtures[0])
	RunState.game_time = 100.0
	var rec := Telemetry.build_record(&"lose")
	assert_eq((rec.big_offers as Array).size(), 1)
	assert_eq(rec.big_offers[0].pick, String(first_big.id))
	assert_eq((rec.big_swaps as Array).size(), 2)
	assert_eq(rec.big_swaps[0].from, "")
	assert_eq(rec.big_swaps[1].from, String(first_big.id))
	var seconds: Dictionary = rec.genre_seconds
	assert_almost_eq(float(seconds.base), 10.0, 0.01)
	assert_almost_eq(float(seconds[String(first_big.id)]), 60.0, 0.01)
	assert_almost_eq(float(seconds[rec.final_big]), 30.0, 0.01)
	var text := ReportScreen.report_text(&"lose", rec)
	assert_string_contains(text, "Genres      Base 0:10, %s 1:00" % first_big.genre_label)
	var ids := ReportScreen.rateable_ids(rec)
	assert_true(ids.has(first_big.id), "big patches can be kept or cut")
	assert_true(ids.has(StringName(rec.final_big)))
	assert_eq(ReportScreen.genres_text({"base": 12.0}), "", "no line for a run that stayed in base")
