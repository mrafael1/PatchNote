extends GutTest
## M47.3 (PLAN v9.1 1.16): the pause menu. can_open() is the only rule; the menu holds
## everything that would move under it; Quit and Restart leave nothing paused. The menu
## pauses the tree: nothing here waits while it is open (each frame is driven by hand).

const TEST_PATH := "user://m47_3_test/save.json"
const TEST_LOG := "user://m47_3_test/t.jsonl"
const S4 := &"s1_04_level"
const S8 := &"s2_02_day_one"


class OverGenre:
	extends Genre
	func is_over() -> bool:
		return true


func before_each() -> void:
	_delete_files()
	Telemetry.log_path = TEST_LOG


func after_each() -> void:
	assert_ne(SaveGame.save_path if SaveGame.persist else "", SaveGame.DEFAULT_PATH,
			"no test may leave the real save live")
	RunState.clear_pauses()
	await wait_physics_frames(2)
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	CampaignDB.active = false
	SaveGame.go_inert()
	_delete_files()
	Skins.use(null)
	RunState.invincible = false
	RunState.reset(0)
	RunState.world = null


func _delete_files() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", "user://m47_3_test/save.bad.json", TEST_LOG]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _game(id: StringName, path := &"") -> Main:
	if path != &"":
		assert_true(CampaignDB.answer_fork(&"fork_path", StringName("path_%s" % path)))
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var g: Main = load("res://main.tscn").instantiate()
	add_child_autofree(g)
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	RunState.invincible = true
	return g


func _log_lines() -> Array:
	var out := []
	if not FileAccess.file_exists(TEST_LOG):
		return out
	for line in FileAccess.get_file_as_string(TEST_LOG).strip_edges().split("\n", false):
		out.append(JSON.parse_string(line))
	return out


# --- can_open ---------------------------------------------------------------------

func test_can_open_refuses_each_blocked_case() -> void:
	var g := await _game(S8, &"arsenal")
	var pm := g.pause_menu
	assert_true(pm.can_open(), "plain play")
	assert_false(PauseMenu.allowed(null), "no game")

	var real_genre := g.genre
	var over := OverGenre.new()
	g.genre = over
	assert_false(pm.can_open(), "genre over")
	g.genre = real_genre
	over.free()

	g.transition.busy = true
	assert_false(pm.can_open(), "transition busy")
	g.transition.busy = false

	g.event_player._clock_holds.append(&"test")
	assert_false(pm.can_open(), "a scripted event holds the clock")
	g.event_player._clock_holds.clear()

	RunState.set_pause(&"history", true)
	assert_false(pm.can_open(), "build log open")
	RunState.set_pause(&"history", false)

	g.prompt_panel._root.visible = true
	assert_false(pm.can_open(), "the v6 prompt open")
	g.prompt_panel._root.visible = false

	var card := StageCard.new()
	card.setup(2, "The shooter")
	add_child_autofree(card)
	g.stage_card = card
	assert_false(pm.can_open(), "stage card up")
	card.skip()
	g.stage_card = null
	RunState.set_pause(&"stage_card", false)

	g.debrief._root.visible = true
	assert_false(pm.can_open(), "debrief up")
	g.debrief._root.visible = false

	var clock := TurnClock.new()
	add_child_autofree(clock)
	clock.active = true
	clock._turn_left = 0.5
	assert_false(pm.can_open(), "B2 resolving a turn")
	clock._turn_left = 0.0
	assert_true(pm.can_open(), "B2's turn wait: allowed")
	clock.active = false
	clock.free()

	assert_true(pm.can_open(), "free again")


func test_it_opens_over_a_pick_panel_and_freezes_its_lock() -> void:
	var g := await _game(S8, &"arsenal")
	var panel := g.ensure_path_runner().panel
	var offer := PickOffer.new()
	offer.cards.append({"id": &"shotgun", "rank": 1, "kind": &"new", "text": "Shotgun"})
	panel.input_delay = 0.5
	assert_true(panel.open(offer))
	assert_true(g.pause_menu.can_open(), "over a pick")
	assert_true(g.pause_menu.open())
	var left := panel._locked_for
	panel._process(0.3)
	assert_eq(panel._locked_for, left, "the lock waits under the menu")
	assert_false(panel.can_choose())
	g.pause_menu.close()
	assert_true(RunState.is_paused_for(PickPanel.PAUSE), "the pick still pauses")
	panel._process(0.6)
	assert_true(panel.can_choose())
	panel.choose(0)


# --- Raw / full / style -----------------------------------------------------------

func test_stage_1_gets_the_raw_line_and_stage_2_the_full_menu() -> void:
	var g := await _game(S4)
	assert_true(g.pause_menu.open())
	assert_true(g.pause_menu.raw)
	assert_true(g.pause_menu._raw_label.visible)
	assert_false(g.pause_menu._panel.visible)
	# M47.5b (listed deviation): before the front door Q quits the game, and F, -/+, L are here.
	assert_eq(g.pause_menu._raw_label.text,
			"PAUSED   [Escape] resume   [Q] quit game   [F] fullscreen   [-/+] volume   [L] less flashing")
	g.pause_menu.close()
	assert_eq(PauseMenu.raw_line(func(k: int) -> int: return KEY_A if k == KEY_Q else k),
			"PAUSED   [Escape] resume   [A] quit game   [F] fullscreen   [-/+] volume   [L] less flashing",
			"AZERTY prints A for the Q spot")
	assert_true(PauseMenu.raw_for(null), "the v6 loop is raw")


func test_the_full_menu_dresses_in_the_pixel_panel_only_with_the_ui_group() -> void:
	# A menu on its own (a live game would turn the camera's interpolation on with the look).
	var pm := PauseMenu.new()
	add_child_autofree(pm)
	assert_false(pm.dressed(), "no look: neutral")
	Skins.use(Skins.pixel())
	assert_true(Skins.is_on(&"ui_panel"))
	assert_true(pm.dressed(), "the look's ui panel, live on skin_changed")
	Skins.use(null)
	assert_false(pm.dressed())


# --- The freeze -------------------------------------------------------------------

func test_open_freezes_the_bot_hit_stop_fingerprint_speech_and_typing() -> void:
	var g := await _game(S8, &"arsenal")
	g.player.set_bot(true)
	var bot := g.player.get(&"input") as BotInput
	g.feedback.hit_stop(0.2)
	assert_true(RunState.has_time_factor(&"hit_stop"))
	var fp := g.path_runner.fp
	fp.menu_open()
	var line := Line.new()
	line.text = "x".repeat(60)
	g.mascot.say(line, 3, true)
	var chars := g.mascot._chars
	var free_at := g.session_runner._free_at_msec

	assert_true(g.pause_menu.open())
	assert_true(RunState.is_paused_for(&"menu"))
	assert_true(get_tree().paused)
	var tick := bot._tick
	for i in 120:
		bot._physics_process(1.0 / 60.0)
	assert_eq(bot._tick, tick, "the bot policy does not tick")
	assert_null(g.feedback._stop_timer, "the hit stop's timer is held")
	assert_almost_eq(g.feedback._held_left, 0.2, 0.05)
	assert_true(RunState.has_time_factor(&"hit_stop"), "still stopped under the menu")
	assert_eq(fp._menu_from, -1, "the pick clock stops")
	g.mascot._process(1.0)
	assert_eq(g.mascot._chars, chars, "typing frozen")
	OS.delay_msec(60)

	g.pause_menu.close()
	assert_false(RunState.is_paused_for(&"menu"))
	assert_not_null(g.feedback._stop_timer, "re-armed for the time left")
	assert_gte(fp._menu_from, 0, "the pick clock runs again")
	assert_gte(g.session_runner._free_at_msec - free_at, 60, "speech moved on by the held time")
	g.mascot._process(0.1)
	assert_gt(g.mascot._chars, chars, "typing again")
	fp.menu_close()


func test_a_600_frame_menu_leaves_real_time_unchanged() -> void:
	var g := await _game(S8, &"survival")
	var before := RunState.real_time()
	var frames := RunState.real_frames
	assert_true(g.pause_menu.open())
	for i in 600:
		RunState._physics_process(1.0 / 60.0)
	assert_eq(RunState.real_frames, frames + 600, "real_frames stays raw")
	assert_eq(RunState.menu_frames, 600)
	assert_almost_eq(RunState.real_time(), before, 1.0 / 60.0, "within one frame")
	g.pause_menu.close()


func test_hold_speech_and_mascot_hold_directly() -> void:
	var g := await _game(S8, &"auto")
	var free_at := g.session_runner._free_at_msec
	g.session_runner.hold_speech(true)
	OS.delay_msec(40)
	g.session_runner.hold_speech(false)
	assert_gte(g.session_runner._free_at_msec - free_at, 40)
	var line := Line.new()
	line.text = "y".repeat(40)
	g.mascot.say(line, 3, true)
	g.mascot.hold(true)
	var c := g.mascot._chars
	g.mascot._process(1.0)
	assert_eq(g.mascot._chars, c)
	g.mascot.hold(false)


# --- Quit / Restart ---------------------------------------------------------------

func test_quit_leaves_nothing_paused_writes_abandon_and_not_the_save() -> void:
	SaveGame.go_live(TEST_PATH, true)
	var g := await _game(S8, &"arsenal")
	SaveGame.write()
	var bytes := FileAccess.get_file_as_string(TEST_PATH)
	g.menu_telemetry_always = true
	g.feedback.hit_stop(0.2)
	assert_true(g.pause_menu.open())
	g.pause_menu.quit()
	assert_false(get_tree().paused)
	assert_true(RunState._pause_reasons.is_empty(), "no pause reason left")
	assert_true(RunState._time_factors.is_empty(), "no held hit stop left")
	assert_eq(FileAccess.get_file_as_string(TEST_PATH), bytes, "the save is untouched")
	var lines := _log_lines()
	assert_eq(lines.size(), 1)
	assert_eq(lines[0].choice, "abandon")
	assert_eq(lines[0].outcome, "quit")
	assert_eq(lines[0].build, Main.BUILD)   # M47.4: the build, not a pinned name


func test_restart_counts_one_attempt_and_one_line() -> void:
	var g := await _game(S8, &"auto")
	g.menu_telemetry_always = true
	var before := CampaignDB.attempt(S8)
	assert_true(g.pause_menu.open())
	g.pause_menu.ask_restart()
	assert_true(g.pause_menu._confirm.visible, "asks first")
	g.pause_menu.cancel_restart()
	assert_true(g.pause_menu._menu.visible)
	assert_eq(CampaignDB.attempt(S8), before, "No: nothing counted")
	g.pause_menu.restart()
	assert_eq(CampaignDB.attempt(S8), before + 1, "exactly one attempt")
	var lines := _log_lines()
	assert_eq(lines.size(), 1)
	assert_eq(lines[0].choice, "menu_retry")
	assert_false(get_tree().paused)


func test_the_raw_quit_key_is_q_by_position() -> void:
	var g := await _game(S4)
	assert_true(g.pause_menu.open())
	var e := InputEventKey.new()
	e.physical_keycode = KEY_Q
	e.keycode = KEY_A   # AZERTY
	e.pressed = true
	assert_true(PauseMenu._raw_quit(e))
	var y := InputEventJoypadButton.new()
	y.button_index = JOY_BUTTON_Y
	y.pressed = true
	assert_true(PauseMenu._raw_quit(y))
	g.pause_menu.close()


# --- Options ----------------------------------------------------------------------

func test_options_open_from_pause_with_four_tabs_and_close_back() -> void:
	var g := await _game(S8, &"arsenal")
	assert_true(g.pause_menu.open())
	g.pause_menu.open_options()
	var o := g.pause_menu.options
	assert_true(o.visible)
	assert_eq(o._pages.size(), 4)
	o.show_tab(o.tab + 1)
	assert_eq(o.tab, 1)
	o.show_tab(o.tab - 2)
	assert_eq(o.tab, 3, "wraps")
	assert_true((o.control_for("window_mode") as BaseButton).disabled, "video ignored here")
	(o.control_for("shake") as HSlider).value = 0.4
	assert_almost_eq(float(Settings.get_value("shake")), 0.4, 0.001)
	o.close()
	assert_false(o.visible)
	assert_true(g.pause_menu._panel.visible)
	g.pause_menu.close()


func test_controls_tab_shows_layout_keys_and_pad_names() -> void:
	var azerty := func(k: int) -> int:
		match k:
			KEY_W: return KEY_Z
			KEY_A: return KEY_Q
			KEY_Q: return KEY_A
		return k
	assert_eq(OptionsScreen.keyboard_text([&"move_up", &"move_left", &"move_down", &"move_right"], "", azerty),
			"Z Q S D")
	assert_eq(OptionsScreen.pad_text([&"pause"]), "Menu")
	assert_eq(OptionsScreen.pad_text([&"jump"]), "A")
	assert_eq(OptionsScreen.pad_text([&"dash"]), "LT")


# --- The debrief on actions -------------------------------------------------------

func test_the_debrief_takes_the_physical_1_and_enter() -> void:
	var g := await _game(&"s1_03_shooting")
	g.run_loop.goal_clock = 120.0
	await wait_physics_frames(int(Tuning.report_delay * 60) + 5)
	var d := g.debrief
	assert_true(d.is_open())
	d.input_delay = 0.0
	d.finish_lines()
	assert_eq(d.phase, DebriefScreen.FORK)
	var one := InputEventKey.new()
	one.physical_keycode = KEY_1
	one.keycode = KEY_AMPERSAND   # AZERTY's 1 key
	one.pressed = true
	d._cards_msec -= 1000
	d._unhandled_input(one)
	assert_eq(d.picks.size(), 1, "the physical 1 picks on AZERTY")
	while d.phase != DebriefScreen.DONE and d.is_open():
		if d.phase == DebriefScreen.FORK:
			d._cards_msec -= 1000
			d._unhandled_input(one)
		else:
			d.finish_lines()
	assert_eq(d.phase, DebriefScreen.DONE)
	d._buttons_msec -= 1000
	watch_signals(d)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	d._unhandled_input(enter)
	assert_true(get_signal_emit_count(d, "next_requested") + get_signal_emit_count(d, "move_on_requested") > 0,
			"Enter takes the way on")
	d.close()
