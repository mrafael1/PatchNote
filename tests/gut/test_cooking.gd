extends GutTest
## M43.2 (G13b): the cooking screen. S7's playable stub is gone from the campaign flow:
## between Stage 1 and Stage 2 the stage card shows the AI building the next version (its
## progress lines one by one, a working indicator, a bar that stalls), then "To be
## continued". The card pauses the tree: these tests drive _process by hand and never
## wait while it is open.

const TEST_PATH := "user://save_cooking_test/save.json"
## The telemetry log while these tests run: a scratch file, never the owner's
## user://playtest/runs.jsonl (G13b review).
const TEST_LOG := "user://save_cooking_test/runs.jsonl"
const LINES := ["one...", "two...", "three."]


func before_each() -> void:
	_delete_files()
	Telemetry.log_path = TEST_LOG


func after_each() -> void:
	_cook_out()
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.set_pause(&"stage_card", false)
	SaveGame.go_inert()
	_delete_files()


func _delete_files() -> void:
	for path in [TEST_LOG, TEST_PATH, TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _card(lines: Array = LINES) -> StageCard:
	var card := StageCard.new()
	card.setup(2, "The shooter", PackedStringArray(lines), "v0.8.0")
	add_child_autofree(card)
	return card


func _key() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_SPACE
	e.pressed = true
	return e


func _run(card: StageCard, seconds: float) -> void:
	for i in roundi(seconds * 10.0):
		card._process(0.1)


func test_the_cooking_card_types_its_lines_then_to_be_continued() -> void:
	var card := _card()
	assert_true(card.is_cooking())
	assert_true(get_tree().paused, "it pauses the tree like any card")
	assert_eq(card._stage_label.text, "Stage 2")
	assert_eq(card._title_label.text, "The shooter")
	assert_eq(card._building_label.text, "Building v0.8.0")
	assert_eq(card.lines_shown(), PackedStringArray())
	var seen: Array = []
	for i in 80:   # the end at 1.5 + 3 x 1.6 = 6.3 s
		card._process(0.1)
		var now := card.lines_shown()
		if now.size() > seen.size():
			seen.append(now[now.size() - 1])
			assert_lt(card._bar.value, StageCard.BAR_MAX + 0.001, "the bar never fills")
	assert_eq(seen, LINES, "each line, in order")
	assert_true(card.ended)
	assert_true(card._end_label.visible)
	assert_eq(card._end_label.text, "To be continued")
	assert_eq(card.ending_text(), "to_be_continued")
	assert_almost_eq(card._bar.value, StageCard.BAR_MAX, 0.001, "stalled short of full")
	assert_true(card.is_open(), "it never closes itself")
	_run(card, 10.0)
	assert_true(card.is_open())
	card.skip()
	assert_false(card.is_open())
	assert_false(get_tree().paused)


func test_a_key_jumps_to_the_end_then_closes() -> void:
	var card := _card()
	card._input(_key())
	assert_false(card.ended, "a key before 0.5 s is ignored")
	_run(card, 0.6)
	card._input(_key())
	assert_true(card.ended, "the first key: the end")
	assert_eq(card.lines_shown(), PackedStringArray(LINES), "every line up")
	assert_true(card.is_open())
	card._input(_key())
	assert_false(card.is_open(), "the next key closes")


func test_skip_ends_and_closes_at_any_time() -> void:
	var card := _card()
	var closed := []
	card.closed.connect(func() -> void: closed.append(true))
	card.skip()
	assert_true(card.ended)
	assert_eq(card.ending_text(), "to_be_continued")
	assert_false(card.is_open())
	assert_eq(closed.size(), 1)


func test_the_indicator_spins_or_is_dots_with_reduce_flashing() -> void:
	var card := _card()
	var spins := {}
	for i in 10:
		card._process(0.05)
		spins[card.spinner_text()] = true
	assert_true(spins.size() >= 3, "a spinner (%s)" % [spins.keys()])
	card.skip()
	SaveGame.set_setting("reduce_flashing", true)
	var gentle := _card()
	assert_true(gentle.gentle)
	var seen: Array[String] = []
	for i in 30:
		gentle._process(0.1)
		var t := gentle.spinner_text()
		if seen.is_empty() or seen.back() != t:
			seen.append(t)
	assert_eq(seen.slice(0, 3), [".", "..", "..."] as Array[String], "slow dots, no spinner")
	gentle.skip()
	assert_eq(gentle.spinner_text(), "", "nothing once ended")


func test_the_mascot_says_it_is_cooking_then_promises() -> void:
	var card := _card()
	assert_eq(card.mascot.current_text(), StageCard.LINE)
	assert_eq(card.mascot.queued(), 1, "then the cooking line")
	card._end()
	assert_eq(card.mascot.current_text(), StageCard.END_LINE)
	assert_eq(card.mascot.queued(), 0, "a key jumped to the end: the cooking line is dropped")
	for i in 40:
		card.mascot.step(0.25)
	assert_false(card.mascot.shown.has(StageCard.COOK_LINE), "never said after the promise")
	card.skip()


func test_a_card_without_lines_is_the_plain_card() -> void:
	var card := StageCard.new()
	card.setup(2, "The shooter")
	add_child_autofree(card)
	assert_false(card.is_cooking())
	assert_null(card._bar)
	card._process(1.5)
	card._process(1.5)
	assert_false(card.is_open(), "it still closes itself at 3 s")


## M47: nothing cooks in the campaign (S7 is real); a test-only cooking session appended
## after S8 keeps the screen covered (removed in after_each, never left for problems()).
const COOK_ID := &"s2_99_test_cook"


func _cook_in() -> SessionDef:
	var s := SessionDef.new()
	s.id = COOK_ID
	s.stage = 2
	s.title = "Cooking (test)"
	s.bump = &"minor"
	s.cooking = PackedStringArray(LINES)
	CampaignDB.campaign.sessions.append(s)
	return s


func _cook_out() -> void:
	while CampaignDB.get_session(COOK_ID) != null:
		CampaignDB.campaign.sessions.erase(CampaignDB.get_session(COOK_ID))


func test_the_cooking_screen_shows_a_cooking_session_and_writes_nothing() -> void:
	SaveGame.go_live(TEST_PATH, true)
	for i in CampaignDB.size():
		CampaignDB.complete(CampaignDB.session(i))
	assert_eq(CookingScreen.after_campaign_scene(), StartScreen.TITLE_SCENE, "M47: nothing cooks")
	_cook_in()
	assert_eq(CookingScreen.after_campaign_scene(), CookingScreen.SCENE)
	SaveGame.write()
	var save_text := FileAccess.get_file_as_string(TEST_PATH)
	assert_eq(Telemetry.log_path, TEST_LOG, "the scratch log")
	var screen: CookingScreen = load(CookingScreen.SCENE).instantiate()
	add_child_autofree(screen)
	assert_not_null(screen.card)
	assert_eq(screen.session.id, COOK_ID)
	assert_true(screen.card.is_open())
	assert_eq(screen.card.title, "The shooter")
	assert_eq(screen.card.cooking_lines, screen.session.cooking)
	assert_eq(screen.card.building, "v0.9.0")
	screen.card.skip()
	assert_false(get_tree().paused)
	assert_eq(SaveGame.version().label(), "v0.8.1", "no bump")
	assert_eq(FileAccess.get_file_as_string(TEST_PATH), save_text, "no save write")
	assert_false(FileAccess.file_exists(TEST_LOG), "no telemetry")


## The review's lint: a test that reads the telemetry log first points it at a scratch
## file, so no suite run ever opens the owner's user://playtest/runs.jsonl.
func test_no_test_reads_the_real_telemetry_log() -> void:
	var dir := "res://tests/gut/"
	var checked := 0
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string(dir + f)
		if text.contains("get_file_as_string(Telemetry.log_path)") or text.contains("file_exists(Telemetry.log_path)"):
			checked += 1
			assert_true(text.contains("Telemetry.log_path = "), f + " reads the log without a scratch path")
	assert_gt(checked, 0)
