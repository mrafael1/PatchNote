extends GutTest
## M47.4 (PLAN 1.16, 3.2, v9.1): the front door, seen. The raw start screen unchanged (a
## snapshot recorded at M47.3), the routing to the title from S7 on, the unveil once, the
## title's menu on a MenuStack, S7's door beat on the stage card (<= 12 s, skippable after
## 0.5 s, <= 3 flashes a second), the polished dev chat from Stage 2 and a neutral UiTheme
## that moves nothing (HUD band and bubble measurements recorded at M47.3).
##
## Never wait_seconds while a debrief, a card or a menu pauses the tree: the beats are driven
## by hand. Scratch saves only (user://m47_4_test/); the fixtures are never written.

const DIR := "user://m47_4_test/"
const TEST_PATH := DIR + "save.json"
const OWNER_COPY := DIR + "owner.json"
const RAW := "res://tests/gut/start_screen_raw_m47_3.json"
const MEASURE := "res://tests/gut/ui_measure_m47_3.json"
const STAGE1_END := "res://tests/gut/save_m42_2_stage1_end.json"
const OWNER := "res://tests/gut/save_m43_owner_shape.json"
const S4 := &"s1_04_level"
const S7 := &"s2_01_tryout"
const S8 := &"s2_02_day_one"
## M47.5b (listed deviation, PLAN v9.3 3.2): line 1 names the door the always-on player never saw.
const DOOR_LINES: Array[String] = ["Before I build three shooters, this game needs a front door.",
		"Options. Real ones. They even save.", "And {key:pause} finally does something."]
const HandWidget := preload("res://paths/arsenal/hand_widget.gd")
const VIEWS: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960), Vector2(1706, 720)]


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_delete_files()
	StartScreen.save_live = false
	StartScreen.legacy_loop = false
	CampaignDB.jumped = false


func after_each() -> void:
	StartScreen.legacy_loop = false
	CampaignDB.jumped = false
	CampaignDB.active = false
	Skins.use_named(&"off")
	RunState.clear_pauses()
	SaveGame.go_inert()
	_delete_files()


func _delete_files() -> void:
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)


func _copy(src: String, dst: String) -> void:
	var f := FileAccess.open(dst, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(src))
	f.close()


func _screen() -> StartScreen:
	var screen: StartScreen = load("res://ui/start_screen.tscn").instantiate()
	add_child_autofree(screen)
	await wait_process_frames(2)
	return screen


## A live scratch save with sessions S0..`upto` done (CampaignDB.complete, no picks).
func _done_upto(upto: StringName) -> void:
	SaveGame.go_live(TEST_PATH, true)
	for i in CampaignDB.index_of(upto) + 1:
		CampaignDB.complete(CampaignDB.session(i))


func _owner_live() -> void:
	_copy(OWNER, OWNER_COPY)
	SaveGame.go_live(OWNER_COPY)


# --- The raw screen, unchanged ----------------------------------------------------------

static func _dump(n: Node, depth: int, rows: Array) -> void:
	var name := String(n.name)
	if name.begins_with("@"):
		name = ""
	var text := ""
	if n is Button or n is Label:
		text = n.text
	elif n is LineEdit:
		text = n.placeholder_text
	if n is OptionButton:
		var items: Array[String] = []
		for i in n.item_count:
			items.append(n.get_item_text(i))
		text = "|".join(items)
	text = text.replace(Main.BUILD, "{BUILD}")
	rows.append([depth, n.get_class(), name, text, n.visible if n is CanvasItem else true])
	for c in n.get_children():
		_dump(c, depth + 1, rows)


func test_the_raw_screen_matches_the_m47_3_snapshot() -> void:
	var recorded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RAW))
	for variant: String in ["fresh", "stage1_end", "legacy"]:
		StartScreen.legacy_loop = variant == "legacy"
		if variant == "stage1_end":
			SaveGame.use_snapshot(STAGE1_END)
		else:
			SaveGame.go_inert()
		var screen := await _screen()
		assert_null(screen.title, "%s: the raw column" % variant)
		var rows: Array = []
		_dump(screen, 0, rows)
		var want: Array = recorded[variant]
		assert_eq(rows.size(), want.size(), "%s: node count" % variant)
		for i in mini(rows.size(), want.size()):
			var w: Array = want[i]
			assert_eq(rows[i], [int(w[0]), w[1], w[2], w[3], w[4]], "%s row %d" % [variant, i])
		screen.free()
	StartScreen.legacy_loop = false


# --- Routing ----------------------------------------------------------------------------

func test_before_s7_the_raw_screen_from_s7_the_title() -> void:
	SaveGame.go_live(TEST_PATH, true)
	assert_false(CampaignDB.front_door_open(), "a fresh save")
	SaveGame.use_snapshot(STAGE1_END)
	assert_false(CampaignDB.front_door_open(), "the end of Stage 1: standing at S7, not played")
	var raw := await _screen()
	assert_null(raw.title)
	assert_true(raw.continue_button.get_parent() is VBoxContainer, "Continue in the raw column")
	raw.free()
	Settings.set_value("front_door_seen", true)
	assert_true(CampaignDB.front_door_open(), "quit mid-S7 after the beat: the title")
	SaveGame.use_snapshot(OWNER)
	assert_true(CampaignDB.front_door_open(), "the owner's save (stub-era S7 done)")
	var title := await _screen()
	assert_not_null(title.title)
	assert_eq(title.continue_button, title.title.continue_button, "StartScreen's fields are the title's")
	assert_eq(title.new_button, title.title.new_button)
	assert_true(title.continue_button.visible)
	title.free()
	_done_upto(S8)
	assert_true(CampaignDB.front_door_open(), "S8 done")
	_done_upto(&"s2_03_paint")
	assert_true(CampaignDB.is_done())
	var done := await _screen()
	assert_not_null(done.title, "a finished campaign")
	assert_false(done.continue_button.visible, "nothing to continue")
	done.free()
	SaveGame.use_snapshot(OWNER)
	StartScreen.legacy_loop = true
	var legacy := await _screen()
	assert_null(legacy.title, "the legacy loop always gets the raw column")
	legacy.free()


func test_attempting_s7_opens_the_front_door() -> void:
	SaveGame.use_snapshot(STAGE1_END)
	SaveGame.count_attempt(S7)
	assert_true(CampaignDB.front_door_open())


func test_new_game_keeps_the_settings_but_not_front_door_seen() -> void:
	_owner_live()
	Settings.set_value("vol_sfx", 0.25)
	Settings.set_value("front_door_seen", true)
	Settings.commit()
	var screen := await _screen()
	assert_not_null(screen.title)
	screen.reset_campaign()
	var settings: Dictionary = SaveGame.state().settings
	assert_false(settings.has("front_door_seen"), "story, not a setting")
	assert_eq(float(settings.vol_sfx), 0.25)
	assert_true(bool(settings.asked))
	screen.free()
	var again := await _screen()
	assert_null(again.title, "the raw screen again until S7")
	again.free()


# --- The unveil -------------------------------------------------------------------------

func _drive(title: TitleScreen, seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		title._process(1.0 / 60.0)


func test_the_owner_save_shows_the_unveil_exactly_once() -> void:
	var fixture := FileAccess.get_file_as_string(OWNER)
	_owner_live()
	var first := await _screen()
	assert_true(first.title.unveiling(), "the owner's save: the unveil")
	assert_true(bool(Settings.get_value("front_door_seen")), "set when it starts")
	var written: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OWNER_COPY))
	assert_true(bool(written.settings.get("front_door_seen", false)), "written once")
	var unveil := first.title.unveil
	assert_almost_eq(unveil.end_at() - unveil.start_at(), 6.0, 0.001, "a 6 s cut")
	assert_eq(unveil.said_count(), 0)
	_drive(first.title, 6.1)
	assert_false(first.title.unveiling(), "over within 6 s")
	assert_true(first.title.unveiled)
	assert_eq(unveil.said_count(), 0, "the cut says no beat line")
	assert_eq(first.title.mascot_text(), Line.parse(TitleScreen.UNVEIL_LINE).text)
	first.free()
	var second := await _screen()
	assert_false(second.title.unveiling(), "once")
	assert_eq(second.title.mascot_text(), Line.parse(TitleScreen.launch_line()).text)
	second.free()
	assert_eq(FileAccess.get_file_as_string(OWNER), fixture, "the fixture is never written")


func test_a_key_skips_the_unveil_after_half_a_second() -> void:
	_owner_live()
	var screen := await _screen()
	var title := screen.title
	var at := title.unveil.elapsed
	title._input(_key())
	assert_true(title.unveiling(), "a key in the first 0.5 s is ignored")
	_drive(title, 0.6)
	title._input(_key())
	assert_false(title.unveiling())
	assert_eq(title.mascot_text(), Line.parse(TitleScreen.UNVEIL_LINE).text)
	assert_lt(at, 3.1)
	screen.free()


func _key() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_SPACE
	e.pressed = true
	return e


# --- The title's menu -------------------------------------------------------------------

func _seen_title() -> StartScreen:
	_owner_live()
	Settings.set_value("front_door_seen", true)
	var screen := await _screen()
	await wait_process_frames(2)
	return screen


func test_the_menu_order_wraps_and_every_item_is_reachable() -> void:
	var screen := await _seen_title()
	var title := screen.title
	assert_eq(title.menu_items().map(func(b: Button) -> String: return b.text),
			["Continue", "New game", "Options", "Quit"], "no Replay before S8 is done")
	var items := title.menu_items()
	var last := items[items.size() - 1]
	assert_eq(last.get_node(last.focus_neighbor_bottom), items[0], "down from Quit wraps to Continue")
	assert_eq(items[0].get_node(items[0].focus_neighbor_top), last)
	var seen := {}
	var at: Control = items[0]
	for i in items.size():
		seen[at] = true
		at = at.get_node(at.focus_neighbor_bottom)
	assert_eq(seen.size(), items.size(), "every item by down")
	screen.free()
	_done_upto(S8)
	Settings.set_value("front_door_seen", true)
	var later := await _screen()
	assert_eq(later.title.menu_items().map(func(b: Button) -> String: return b.text),
			["Continue", "New game", "Replay", "Options", "Quit"], "Replay once S8 is done")
	later.title.open_replay()
	assert_eq(later.title.stack.top(), later.title.replay_menu)
	assert_gt(later.replay_session.item_count, 0)
	later.free()


func _cancel() -> InputEventAction:
	var e := InputEventAction.new()
	e.action = &"ui_cancel"
	e.pressed = true
	return e


func test_new_game_asks_first_and_back_returns_to_it() -> void:
	var screen := await _seen_title()
	var title := screen.title
	title.new_button.grab_focus()
	title.confirm_new()
	assert_eq(title.stack.top(), title.confirm_menu, "the confirm")
	assert_false(title.root_menu.visible)
	assert_eq(title.stack.depth(), 2)
	title.stack._input(_cancel())
	assert_eq(title.stack.top(), title.root_menu, "Back pops")
	assert_true(title.new_button.has_focus(), "the focus returns to New game")
	title.stack._input(_cancel())
	assert_eq(title.stack.depth(), 1, "Back at the root does nothing")
	title.confirm_new()
	title.confirm_no.pressed.emit()
	assert_eq(title.stack.top(), title.root_menu, "No pops")
	SaveGame.set_setting("asked", false)   # Yes runs _ask_then: the question first, no scene change
	title.confirm_new()
	title.confirm_yes.pressed.emit()
	assert_eq(title.stack.top(), title.root_menu)
	assert_true(screen.flash_panel.visible, "Yes went through _ask_then")
	assert_true(screen._after_question.is_valid())
	assert_false(title.new_button.visible)
	screen.free()


func test_options_open_from_the_title_and_back_commits() -> void:
	var screen := await _seen_title()
	var title := screen.title
	title.open_options()
	assert_eq(title.stack.top(), title.options)
	assert_true(title.options.visible)
	assert_false(title.mascot.visible, "the mascot steps aside")
	Settings.set_value("vol_ui", 0.4)
	title.options.close()
	assert_eq(title.stack.top(), title.root_menu, "its close pops")
	assert_true(title.mascot.visible)
	var written: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OWNER_COPY))
	assert_almost_eq(float(written.settings.vol_ui), 0.4, 0.001, "committed on Back")
	screen.free()


func test_the_menus_wear_the_pixel_panel_only_with_the_ui_on() -> void:
	var screen := await _seen_title()
	var title := screen.title
	assert_false(title.dressed(), "neutral")
	assert_eq(title.root_menu.get_theme_stylebox(&"panel"),
			UiTheme.theme().get_stylebox(&"panel", UiTheme.MENU_PANEL), "the UiTheme's MenuPanel")
	Skins.use_named(&"pixel")
	assert_true(title.dressed(), "F10 / a live look: the Pixel panel")
	Skins.use_named(&"off")
	assert_false(title.dressed())
	assert_eq(title.root_menu.get_theme_stylebox(&"panel"),
			UiTheme.theme().get_stylebox(&"panel", UiTheme.MENU_PANEL))
	screen.free()


# --- The door beat ----------------------------------------------------------------------

func test_s7_has_the_three_door_lines_and_bad_data_is_refused() -> void:
	var s := CampaignDB.get_session(S7)
	assert_eq(s.door_beat_lines().map(func(l: Line) -> String: return l.text), DOOR_LINES)
	assert_eq(s.door_beat_lines().map(func(l: Line) -> StringName: return l.expression),
			[&"thinking", &"proud", &"happy"])
	assert_eq(s.problems(), [] as Array[String])
	assert_eq(SessionDef.DOOR_BEAT_MAX, DoorBeat.LINE_AT.size())
	assert_lte(DoorBeat.LENGTH, 12.0)
	var cases := {"an empty line": PackedStringArray(["happy: a", "  "]),
			"a condition": PackedStringArray(["won happy: a"]),
			"4 lines": PackedStringArray(["a", "b", "c", "d"]),
			"an unknown key": PackedStringArray(["happy: press {key:no_such_action}"])}
	for what: String in cases:
		var bad := s.duplicate() as SessionDef
		bad.door_beat = cases[what]
		assert_ne(bad.problems().filter(func(p: String) -> bool: return p.contains("door_beat")), [], what)
	var stage1 := CampaignDB.get_session(S4).duplicate() as SessionDef
	stage1.door_beat = PackedStringArray(["happy: hi"])
	assert_string_contains(str(stage1.problems()), "door_beat needs a stage card")


func _door_card() -> StageCard:
	var s := CampaignDB.get_session(S7)
	var card := StageCard.new()
	card.setup_door(s.door_beat_lines())
	card.setup_beat(s.cook_beat, "v0.8.0")
	card.setup(2, "The shooter")
	add_child_autofree(card)
	return card


func test_the_card_plays_the_door_then_the_cook_beat() -> void:
	SaveGame.go_live(TEST_PATH, true)
	var card := _door_card()
	assert_true(card.in_door())
	assert_true(get_tree().paused)
	assert_true(bool(Settings.get_value("front_door_seen")), "set when the door starts")
	var said: Array[String] = []
	card.door.say.connect(func(l: Line) -> void: said.append(SessionRunner.with_keys(l).text))
	for i in roundi(DoorBeat.LENGTH * 60.0):
		card._process(1.0 / 60.0)
	assert_eq(said, DOOR_LINES.map(func(t: String) -> String: return InputSetup.expand_keys(t)),
			"in order, {key:pause} expanded")
	assert_false(said[2].contains("{key:"))
	assert_false(card.in_door(), "over at 12 s")
	assert_true(card.in_beat(), "then the cook beat")
	assert_eq(card.beat_shown, 0, "re-timed from the door's end")
	for i in 60:
		card._process(1.0 / 60.0)
	assert_eq(card.beat_shown, 1)
	card.skip()
	assert_false(card.is_open())
	assert_false(get_tree().paused)


func test_the_door_is_skippable_after_half_a_second_and_skip_closes_all() -> void:
	var card := _door_card()
	card.elapsed = 0.4
	card._input(_key())
	assert_true(card.in_door(), "a key at 0.4 s is ignored")
	card.elapsed = 0.6
	card._input(_key())
	assert_false(card.in_door(), "at 0.6 s the door ends")
	assert_true(card.in_beat(), "the cook beat starts")
	assert_true(card.is_open())
	var other := _door_card()
	for i in 200:
		other._process(1.0 / 60.0)
	other.skip()
	assert_false(other.is_open(), "skip() closes everything")
	assert_false(RunState.is_paused_for(&"stage_card"))
	card.skip()
	assert_false(get_tree().paused)


func _beat(gentle: bool) -> DoorBeat:
	var beat := DoorBeat.new()
	beat.setup(CampaignDB.get_session(S7).door_beat_lines(), false, gentle)
	add_child_autofree(beat)
	return beat


func test_a_double_tap_after_the_door_keeps_the_cook_beat() -> void:
	var card := _door_card()
	card.elapsed = 0.6
	card._input(_key())
	assert_false(card.in_door(), "the first key ends the door")
	assert_true(card.in_beat())
	card.elapsed = 0.65
	card._input(_key())
	assert_true(card.in_beat(), "a second key 0.05 s later: the cook beat stays (its own 0.5 s)")
	assert_true(card.is_open())
	card.elapsed = 1.15
	card._input(_key())
	assert_false(card.in_beat(), "0.55 s after the door: the key skips the cook beat")
	assert_true(card.is_open(), "the card itself still has its own 0.5 s")
	card.skip()


func test_the_last_door_line_waits_under_the_build_window() -> void:
	var card := _door_card()
	card.elapsed = 0.6
	card._input(_key())
	assert_true(card.in_beat())
	var view := card.get_viewport().get_visible_rect().size
	var frame_bottom := view.y * 0.5 + StageCard.BEAT_FRAME_H * 0.5
	assert_gte(Mascot.TOP + card.mascot.offset.y, frame_bottom, "body and bubble below the frame")
	card.elapsed = 1.2
	card._input(_key())
	assert_false(card.in_beat())
	assert_lt(Mascot.TOP + card.mascot.offset.y, frame_bottom, "back under the title for the card")
	card.skip()


func test_each_door_line_is_readable_before_the_next() -> void:
	var lines := CampaignDB.get_session(S7).door_beat_lines()
	var slowest := 30.0   # Settings text_speed's slowest choice
	for i in lines.size() - 1:
		var text := SessionRunner.with_keys(lines[i]).text
		var complete := DoorBeat.LINE_AT[i] + text.length() / slowest
		assert_lte(complete + SessionRunner.read_seconds(text), DoorBeat.LINE_AT[i + 1],
				"line %d stays complete for its reading time at 30 cps" % (i + 1))
	assert_lt(DoorBeat.LINE_AT[lines.size() - 1], DoorBeat.LENGTH, "every line inside the beat")
	var beat := _beat(false)
	while not beat.is_done():
		beat.step(1.0 / 60.0)
	assert_eq(beat.said_count(), lines.size())


func test_the_ghost_buttons_end_in_the_title_dress() -> void:
	Skins.use_named(&"pixel")
	var beat := _beat(false)
	assert_false(beat._buttons[0].has_theme_stylebox_override(&"normal"), "the raw column: no Pixel panel yet")
	while not beat.is_done():
		beat.step(1.0 / 60.0)
	var ghosts: Array[Button] = beat._buttons.duplicate()
	ghosts.append(beat._options)
	for b in ghosts:
		assert_eq(b.get_theme_stylebox(&"normal"), Skins.current.ui_panel(false), b.text)
		assert_eq(b.get_theme_stylebox(&"focus"), Skins.current.ui_panel(true), b.text)
	Skins.use_named(&"off")
	var neutral := _beat(false)
	while not neutral.is_done():
		neutral.step(1.0 / 60.0)
	assert_false(neutral._buttons[0].has_theme_stylebox_override(&"normal"), "no look: the neutral TitleButton")


func test_the_title_grid_carries_on_from_the_unveil() -> void:
	_owner_live()
	var screen := await _screen()
	var title := screen.title
	assert_true(title.unveiling())
	_drive(title, 6.1)
	assert_false(title.unveiling())
	assert_eq(title.backdrop.scroll, TitleBackdrop.SPEED * DoorBeat.CUT_TO, "no jump at the hand-over")
	screen.free()


func test_at_most_three_flashes_a_second_and_none_with_reduce_flashing() -> void:
	var beat := _beat(false)
	var strength: Array[float] = []
	while not beat.is_done():
		beat.step(1.0 / 60.0)
		strength.append(beat.glitch_strength())
	assert_almost_eq(beat.elapsed, DoorBeat.LENGTH, 0.001)
	var rises: Array[int] = []
	for i in range(1, strength.size()):
		if strength[i - 1] <= 0.5 and strength[i] > 0.5:
			rises.append(i)
	assert_gt(rises.size(), 0, "there is a wipe")
	for i in strength.size():
		var in_window := rises.filter(func(r: int) -> bool: return r >= i and r < i + 60).size()
		assert_lte(in_window, 3, "frame %d" % i)
	var calm := _beat(true)
	var last := 0.0
	while not calm.is_done():
		calm.step(1.0 / 60.0)
		assert_eq(calm.glitch_strength(), 0.0)
		assert_gte(calm.crossfade(), last, "the crossfade only goes one way")
		last = calm.crossfade()
	assert_eq(last, 1.0)


func test_the_replica_shows_only_raw_screen_texts() -> void:
	var recorded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RAW))
	var texts := {}
	for row: Array in recorded.fresh:
		texts[String(row[3])] = true
	var beat := _beat(false)
	for t in beat.replica_texts():
		assert_true(texts.has(t.replace(Main.BUILD, "{BUILD}")), t)


func test_the_beat_is_due_once_per_save_or_on_a_jump() -> void:
	SaveGame.use_snapshot(STAGE1_END)
	var s := CampaignDB.get_session(S7)
	assert_true(CampaignDB.door_beat_due(s), "the end of Stage 1: the full beat")
	assert_false(CampaignDB.door_beat_due(CampaignDB.get_session(S8)), "only S7 has one")
	Settings.set_value("front_door_seen", true)
	assert_false(CampaignDB.door_beat_due(s), "seen (the owner's unveil)")
	CampaignDB.jumped = true
	assert_true(CampaignDB.door_beat_due(s), "a dev replay plays it in full")


func test_a_session_jump_boots_into_the_door() -> void:
	SaveGame.go_inert()
	assert_true(CampaignDB.read_jump_args(PackedStringArray(["--session=s2_01_tryout"])))
	assert_true(CampaignDB.jumped)
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	assert_not_null(game.stage_card)
	assert_true(game.stage_card.in_door())
	game.stage_card.skip()
	await wait_physics_frames(2)
	assert_false(get_tree().paused)
	game.free()


# --- The polished dev chat --------------------------------------------------------------

func _debrief(id: StringName) -> DebriefScreen:
	SaveGame.use_snapshot(STAGE1_END)
	var d := DebriefScreen.new()
	d.input_delay = 0.0
	add_child_autofree(d)
	d.open(CampaignDB.get_session(id), &"win", 0)
	return d


func test_s7_opens_the_polished_chat() -> void:
	var d := _debrief(S7)
	assert_eq(d.style, DebriefScreen.POLISHED)
	assert_ne(d._window.get_theme_stylebox(&"panel").get_class(), "StyleBoxEmpty", "framed")
	assert_eq(d.bar_text(), "patchnotes · dev chat · v0.8.0")
	assert_eq(d.said[0], "So. Three versions of the same game.", "M47.5b: the redecorated line is cut (listed deviation)")
	assert_not_null(d._body.find_child("Avatar", true, false), "the avatar on the first bubble")
	assert_eq((d._body.find_child("Speaker", true, false) as Label).text, DebriefScreen.speaker_name(DebriefScreen.body_for(d.session)))
	assert_ne(d._dots.text, "", "typing dots while it types")
	d.finish_lines()
	assert_eq(d.phase, DebriefScreen.FORK)
	var chip := d._cards.get_child(0).find_child("KeyChip", true, false) as Label
	assert_eq(chip.text, InputSetup.key_label(&"choose_1"))
	assert_true(d.pick(0))
	d.finish_lines()
	assert_eq(d.phase, DebriefScreen.DONE)
	assert_eq(d.choices(), [DebriefScreen.NEXT] as Array[String], "button texts unchanged")
	assert_eq(d._notes.text, DebriefScreen.notes_text(d.session, d.picked, d.more_picks()))
	assert_false(d._notes.visible)
	assert_true(d._changelog.visible)
	var log := DebriefScreen.changelog(d.session, d.picked)
	assert_eq(log["Added"], ["The shooter, three ways", "A title screen.",
			"Options (audio, video, controls, accessibility).", "A pause menu.", d.picked.title])
	assert_eq(log["Changed"], [])
	assert_eq(log["Fixed"], [])
	d.close()


func test_stage_1_keeps_the_plain_debrief() -> void:
	var d := _debrief(S4)
	assert_eq(d.style, DebriefScreen.PLAIN)
	assert_eq(d._window.get_theme_stylebox(&"panel").get_class(), "StyleBoxEmpty")
	assert_false(d._bar.visible)
	assert_null(d._body.find_child("Avatar", true, false))
	d.finish_lines()
	if d.phase == DebriefScreen.FORK:
		d.pick(0)
		d.finish_lines()
	assert_eq(d._notes.text, DebriefScreen.notes_text(d.session, d.picked, d.more_picks()))
	assert_true(d._notes.visible)
	assert_false(d._changelog.visible)
	assert_null(d._buttons.find_child("KeyChip", true, false))
	d.close()


func test_changelog_sections() -> void:
	var s := SessionDef.new()
	s.notes = PackedStringArray(["Fixed the door", "Changed some colours", "Added a thing", "A plain note"])
	var log := DebriefScreen.changelog(s)
	assert_eq(log["Added"], ["A thing", "A plain note"])
	assert_eq(log["Changed"], ["Some colours"])
	assert_eq(log["Fixed"], ["The door"])


# --- UiTheme is neutral -----------------------------------------------------------------

func _r(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func test_the_neutral_theme_moves_nothing() -> void:
	assert_eq(UiTheme.font(), ThemeDB.fallback_font)
	assert_eq(UiTheme.theme().default_font, ThemeDB.fallback_font)
	assert_eq(UiTheme.theme().default_font_size, ThemeDB.fallback_font_size)
	var project := ThemeDB.get_project_theme()
	assert_true(project == null or project != UiTheme.theme(), "never the project theme")
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MEASURE))
	for v in VIEWS:
		var want: Dictionary = m.rects["%dx%d" % [v.x, v.y]]
		assert_eq(_r(Hud.band_rect(v)), want.band)
		assert_eq(_r(Hud.corner_rect(v)), want.corner)
		assert_eq(_r(Hud.goal_rect(v)), want.goal)
		assert_eq(_r(HandWidget.hand_rect(v)), want.hand)
	for t: String in m.bubbles:
		assert_eq([Mascot.bubble_width(t), Mascot.bubble_width(t, 24, 620.0)], m.bubbles[t], t)
	var plain := Control.new()
	var themed := Control.new()
	UiTheme.apply(themed)
	add_child_autofree(plain)
	add_child_autofree(themed)
	for t: String in m.labels:
		for parent in [plain, themed]:
			var l := Label.new()
			l.text = t
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = Mascot.bubble_width(t, 24, 620.0)
			l.add_theme_font_size_override(&"font_size", 24)
			parent.add_child(l)
			var size := l.get_combined_minimum_size()
			assert_eq([size.x, size.y], m.labels[t], "%s under %s" % [t, "UiTheme" if parent == themed else "no theme"])
			l.free()
	var b1 := Button.new()
	b1.text = "Continue"
	var b2 := Button.new()
	b2.text = "Continue"
	plain.add_child(b1)
	themed.add_child(b2)
	assert_eq(b2.get_combined_minimum_size(), b1.get_combined_minimum_size(), "a plain button")
