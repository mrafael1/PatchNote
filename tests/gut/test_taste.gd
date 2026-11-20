extends GutTest
## The adaptive path, first step: the Director leans its offers toward what the player
## picks and keeps, keeps one card for its own agenda, and reads the report's notes in
## the next run of the session.

const TUNING_KEYS: Array[String] = ["transition_long", "transition_short",
		"report_delay", "agenda_cards"]

var director: AiDirector
var _saved := {}


func before_each() -> void:
	for key in TUNING_KEYS:
		_saved[key] = Tuning.get(key)
	Tuning.transition_long = 0.0
	Tuning.transition_short = 0.0
	Taste.clear_session()
	RunState.reset(21)
	_new_director()


func after_each() -> void:
	for key: String in _saved:
		Tuning.set(key, _saved[key])
	Taste.clear_session()
	RunState.reset(0)
	RunState.world = null


func _new_director() -> void:
	if director:
		director.free()
	director = AiDirector.new()
	add_child_autofree(director)
	director.set_physics_process(false)


func _m(id: StringName) -> Mutation:
	return MutationDB.get_mutation(id)


func test_picks_raise_and_passes_reverts_and_cuts_lower_the_score() -> void:
	var t := Taste.new()
	var cards: Array[Mutation] = [_m(&"auto_attack"), _m(&"horde_mode"), _m(&"jump_button")]
	t.on_offer(cards, _m(&"auto_attack"))
	assert_gt(t.score(_m(&"auto_attack")), 0.0)
	assert_lt(t.score(_m(&"horde_mode")), 0.0)
	assert_gt(t.score(_m(&"bouncing_projectiles")), 0.0, "same tag as the pick leans up too")
	t.on_revert(_m(&"auto_attack"))
	assert_lt(t.score(_m(&"auto_attack")), 0.0)
	t.on_rating(_m(&"jump_button"), -1)
	assert_lt(t.score(_m(&"jump_button")), -1.0)
	for i in 20:
		t.on_rating(_m(&"enemies_split"), 1)
	assert_eq(t.weight_mult(_m(&"enemies_split")), Taste.MAX_MULT, "capped")
	assert_eq(t.weight_mult(_m(&"jump_button")), maxf(Taste.MIN_MULT, 1.0 + Taste.LEAN * t.score(_m(&"jump_button"))))


func test_offers_lean_toward_the_favourite_and_keep_one_agenda_card() -> void:
	Tuning.agenda_cards = 1
	var neutral := _count_weapon_cards(Taste.new())
	var fan := Taste.new()
	for i in 4:
		fan.on_rating(_m(&"auto_attack"), 1)
	var leaning := _count_weapon_cards(fan)
	assert_gt(leaning, neutral + 20, "weapon cards: %d neutral, %d with a weapon fan" % [neutral, leaning])


## Over 150 offers, how many of the taste-led cards are weapon patches.
func _count_weapon_cards(t: Taste) -> int:
	var n := 0
	for i in 150:
		director.taste = t
		var offer := director.get_offer({})
		assert_eq(offer.cards.size(), Tuning.offer_size)
		assert_eq(offer.agenda.size(), 1)
		for m in offer.cards:
			if not offer.agenda.has(m) and m.tags.has(&"weapon"):
				n += 1
	return n


func test_the_agenda_card_is_what_the_player_likes_least() -> void:
	var t := director.taste
	for m in MutationDB.all:
		if m.id != &"horde_mode" and RunState.can_apply(m):
			t.on_rating(m, 1)
	var offer := director.get_offer({})
	assert_eq(offer.agenda, [_m(&"horde_mode")] as Array[Mutation])
	assert_eq(offer.cards[-1], _m(&"horde_mode"), "the AI's pick comes last")
	var ids := {}
	for m in offer.cards:
		ids[m.id] = true
	assert_eq(ids.size(), offer.cards.size(), "no card twice")


func test_choice_logs_the_agenda_and_teaches_the_taste() -> void:
	var offer := director.get_offer({})
	var pick := offer.cards[0]
	director.on_choice(offer, pick)
	var entry: Dictionary = RunState.run_log.filter(func(e: Dictionary) -> bool: return e.event == &"prompt")[0]
	assert_eq(entry.agenda, [String(offer.agenda[0].id)] as Array[String])
	assert_gt(director.taste.score(pick), 0.0)


## Option D (PLAN v4 1.3): only a stage patch's rollback teaches the taste.
func test_reverting_teaches_the_taste() -> void:
	var m := _m(&"gravity_on")
	RunState.add_ai(m, &"stage")
	assert_true(director.revert(m))
	assert_lt(director.taste.score(m), 0.0)


func test_notes_carry_into_the_next_run_of_the_session() -> void:
	Taste.carried = {&"horde_mode": -1, &"auto_attack": 1}
	Taste.last_run_rated = 1
	_new_director()
	assert_lt(director.taste.score(_m(&"horde_mode")), 0.0)
	assert_gt(director.taste.score(_m(&"auto_attack")), 0.0)
	var offer := director.get_offer({})
	assert_eq(offer.line, "I read your notes from the last build. Adjusting.")
	assert_eq(offer.agenda.size(), Tuning.agenda_cards)


func test_skipping_the_notes_gives_the_ai_free_rein() -> void:
	Taste.last_run_rated = 0
	_new_director()
	var offer := director.get_offer({})
	assert_eq(offer.agenda.size(), mini(Tuning.agenda_cards_unrated, Tuning.offer_size - 1))
	assert_string_contains(offer.line, "No notes")


func test_report_lists_each_applied_patch_once_and_keep_cut_exclude_each_other() -> void:
	var record := {"events": [
		{"event": "apply", "id": "jump_button"}, {"event": "revert", "id": "jump_button"},
		{"event": "apply", "id": "jump_button"}, {"event": "apply", "id": "horde_mode"},
		{"event": "apply", "id": "not_a_mutation"}]}
	assert_eq(ReportScreen.rateable_ids(record), [&"jump_button", &"horde_mode"] as Array[StringName])
	var report := ReportScreen.new()
	add_child_autofree(report)
	report.open(&"lose", record)
	report.rate(&"jump_button", 1)
	report.rate(&"jump_button", -1)
	assert_eq(report.ratings, {&"jump_button": -1})
	report.rate(&"jump_button", 0)
	assert_true(report.ratings.is_empty())
	report.rate(&"horde_mode", 1)
	assert_string_contains(report.ratings_text(), "keep")


func test_a_game_that_is_not_the_live_scene_teaches_nothing() -> void:
	Tuning.report_delay = 0.0
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.director.enabled = false
	game.run_loop.end(&"lose")
	game.report.rate(&"horde_mode", -1)
	game.save_notes()
	assert_eq(Taste.last_run_rated, -1)
	assert_true(Taste.carried.is_empty())
