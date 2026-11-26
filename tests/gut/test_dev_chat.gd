extends GutTest
## M47.6b (PLAN v9.4 0.8, design 2.1 and 2.8): the dev desktop and the chat upgrade. The host's
## two windows and taskbar (DevDesktop), the chat style derived from the save (a fresh save on
## the terminal, a save past S2 on the chat, by `done` or by an M42.2 index), S2's beat that
## asks the body and ships the chat, the chat's rows (rows() unchanged), its pills (a fork, a
## death, `play` at a gate), and the late body pick for a save that finished S2 before the move.

const S2 := &"s1_02_enemies"
const S3 := &"s1_03_shooting"
const S4 := &"s1_04_level"
const FIXTURE := "res://tests/gut/save_m42_2_stage1_end.json"
const TEST_PATH := "user://m47_6b_test/save.json"
const TEST_LOG := "user://m47_6b_test/t.jsonl"


func before_each() -> void:
	Telemetry.log_path = TEST_LOG
	SaveGame.go_inert()


func after_each() -> void:
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	for path in [TEST_LOG, TEST_PATH, TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	RunState.clear_pauses()
	CampaignDB.active = false
	CampaignDB.jumped = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null


func _hosted(id: StringName, jump := true) -> GameHost:
	CampaignDB.active = true
	if jump:
		assert_true(CampaignDB.jump_to(id))
	var g: Main = load("res://main.tscn").instantiate()
	var h := GameHost.host_for_tools(g)
	add_child_autofree(h)
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	RunState.invincible = true
	return h


## Loads `campaign` through a file (SaveGame.parse(), as an old save would load).
func _load(campaign: Dictionary, shipped: Array = []) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_PATH.get_base_dir())
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema": 2, "version": [0, 3, 0], "shipped": shipped, "campaign": campaign}))
	f.close()
	SaveGame.use_snapshot(TEST_PATH)
	assert_eq(SaveGame.last_load, SaveGame.LOADED)


func _key(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	e = InputEventAction.new()
	e.action = action
	e.pressed = false
	Input.parse_input_event(e)
	Input.flush_buffered_events()


# --- The chat style, derived from the save -----------------------------------------------------

func test_a_fresh_save_is_on_the_terminal_and_a_save_past_s2_on_the_chat() -> void:
	assert_eq(CampaignDB.chat_style(), TerminalPanel.RAW, "a fresh save")
	assert_eq(CampaignDB.get_session(S2).chat, SessionDef.CHAT_UPGRADE, "S2 ships the chat")
	SaveGame.set_campaign_position(2, S2)
	assert_eq(CampaignDB.chat_style(), TerminalPanel.RAW, "at S2 (its beat ships it)")
	_load({"index": 3, "next": "s1_03_shooting", "done": ["s1_00_nothing", "s1_01_move", "s1_02_enemies"]})
	assert_eq(CampaignDB.chat_style(), TerminalPanel.CHAT, "S2 in done")
	_load({"index": 4, "done": []})
	assert_eq(CampaignDB.current_index(), 4, "an M42.2 save: its index mapped")
	assert_eq(CampaignDB.chat_style(), TerminalPanel.CHAT, "past S2 by its position, with no done")
	SaveGame.use_snapshot(FIXTURE)
	assert_eq(CampaignDB.chat_style(), TerminalPanel.CHAT, "the M42.2 Stage 1 end fixture (check.ps1's door)")


func test_a_host_before_the_upgrade_opens_on_the_terminal() -> void:
	var h := await _hosted(S2)
	assert_false(h.terminal.is_chat(), "S2: the terminal")
	assert_eq(h.desktop.chat_title(), "dev-chat")


func test_a_host_past_s2_opens_on_the_chat() -> void:
	var h4 := await _hosted(S4)
	assert_true(h4.terminal.is_chat(), "S4: the chat")
	assert_eq(h4.desktop.chat_style, TerminalPanel.CHAT)
	h4.terminal.finish()
	var rows := h4.terminal.rows()
	assert_true(rows.has("$ run %s" % S4), "the session rows as before")
	assert_true(h4.terminal.chat.log_rows().has("$ run %s" % S4), "the $ rows go to the build.log strip")


# --- The desktop ---------------------------------------------------------------------------

func test_the_desktop_two_windows_a_taskbar_and_no_product_names() -> void:
	var h := await _hosted(S4)
	h.relayout(Vector2(GameHost.BASE))
	var d := h.desktop
	assert_true(d.visible)
	assert_eq(d.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the windows take their own events")
	assert_eq(d.title_text(), "Patch Notes - %s (debug)" % SaveGame.version().label(), "the version live")
	assert_eq(d.stage_text, GameHost.stage_text(RunState.session))
	assert_string_starts_with(d.stage_text, "S4 ")
	assert_string_ends_with(d.stage_text, ": ON")
	assert_eq(d.chat_title(), "dev-chat - %s" % h.terminal.header_name())
	for text: String in [d.title_text(), d.chat_title(), d.status_text(), d.stage_text] + h.terminal.rows():
		for banned: String in ["cmd.exe", "Microsoft", "Windows [Version"]:
			assert_false(text.contains(banned), "no product name: %s" % text)
	assert_eq(h.game_rect(), Rect2(16, 50, 1280, 720))
	assert_eq(h.viewport.size_2d_override, Vector2i(1280, 720), "the 2D rect stays 1280x720")
	assert_eq(Rect2(h.terminal.position, h.terminal.size), h.layout.terminal)


## Review of the 1080p capture: the chat (tabs, header, pills, input) fits its 360 px window.
func test_the_chat_fits_its_window_at_1080p() -> void:
	var h := await _hosted(S4)
	h.terminal.chat.set_pills(["[1] tank  Something slow that does not die. Your bullets need a reason."] as Array[String])
	for w: Vector2 in [Vector2(GameHost.BASE), Vector2(1920, 1080)]:
		h.relayout(w)
		await wait_process_frames(2)
		var room: float = (h.layout.terminal as Rect2).size.x
		assert_lte(h.terminal.get_combined_minimum_size().x, room, "the chat's minimum width at %s" % w)
		assert_lte(h.terminal.chat.size.x, room, "the chat's width at %s" % w)


func test_the_2d_rect_is_1280x720_at_every_k() -> void:
	var h := await _hosted(S4)
	for w: Vector2 in [Vector2(GameHost.BASE), Vector2(1920, 1080), Vector2(1440, 900), Vector2(2560, 1440)]:
		h.relayout(w)
		await wait_process_frames(1)
		assert_eq(h.viewport.size_2d_override, Vector2i(1280, 720))
		var r := h.game_rect()
		var top_left := h.viewport.get_final_transform().affine_inverse() * Vector2.ZERO
		var bottom_right := h.viewport.get_final_transform().affine_inverse() * r.size
		assert_almost_eq(top_left.x, 0.0, 0.5, "at %s" % w)
		assert_almost_eq(bottom_right.x, 1280.0, 1.0, "at %s" % w)
		assert_almost_eq(bottom_right.y, 720.0, 1.0, "at %s" % w)


# --- S2's beat: the body pick, then the chat ----------------------------------------------------

func test_s2s_beat_asks_the_body_then_ships_the_chat_named_for_it() -> void:
	var h := await _hosted(S2)
	var g := h.game
	var d := g.debrief
	d.input_delay = 0.0
	g._on_report_ready(&"stop")
	d.finish_lines()
	assert_eq(d.fork().id, &"fork_mascot", "the body pick moved to S2 (owner, design 10 Q9)")
	assert_false(h.terminal.is_chat(), "the terminal while it asks")
	var opts := d.fork_options()
	var blob := -1
	for i in opts.size():
		if opts[i].take.id == &"blob":
			blob = i
	assert_gt(blob, -1)
	assert_true(d.pick(blob))
	d.finish_lines()
	h.terminal.finish()
	assert_true(h.terminal.is_chat(), "the chat landed with the patch rows")
	var rows := h.terminal.rows()
	var at_build := rows.find("$ build dev_chat_ui ... ok (it has round corners now)")
	var at_retire := rows.find("$ retire terminal ... collapsed, not deleted")
	var at_patch := rows.find("$ patch apply %s" % CampaignDB.version_after(RunState.session).label())
	assert_gt(at_build, at_patch, "after the patch rows")
	assert_gt(at_retire, at_build)
	assert_true(rows.has("  New window. Round corners. Proud of them."), "its first line, in the chat")
	assert_true(rows.has("  + Added a chat window"), "the note")
	assert_eq(h.terminal.chat.name_text(), "Blob", "the header names the picked body")
	assert_eq(h.terminal.chat.avatar_body().id, &"blob")
	assert_eq(h.terminal.chat_input.placeholder_text, "Talk to Blob...")
	assert_eq(h.desktop.chat_title(), "dev-chat - Blob")
	assert_eq(d.choices(), [DebriefScreen.NEXT] as Array[String])
	d.close()


func test_the_upgrade_lands_on_a_death_too_the_overrun_way_on() -> void:
	var h := await _hosted(S2)
	var d := h.game.debrief
	d.input_delay = 0.0
	h.game._on_report_ready(&"lose")
	d.finish_lines()
	assert_true(d.pick(0))
	d.finish_lines()
	h.terminal.finish()
	assert_true(h.terminal.is_chat(), "S2's death is the way on: the beat still ships the chat")
	d.close()


# --- The chat's asks: pills and keys ---------------------------------------------------------

func test_a_fork_in_the_chat_answers_by_a_pill_or_a_key() -> void:
	var h := await _hosted(S4)
	var d := h.game.debrief
	d.input_delay = 0.0
	h.game._on_report_ready(&"win")
	d.finish_lines()
	assert_eq(d.phase, DebriefScreen.FORK)
	h.terminal.finish()
	await wait_process_frames(1)
	var options := d.fork_options()
	assert_eq(h.terminal.chat.pills.size(), options.size(), "one pill per option")
	assert_string_starts_with(h.terminal.chat.pills[0], "[1] ")
	h.terminal.chat.pill_button(1).pressed.emit()
	assert_eq(d.picks.size(), 1, "the pill picked")
	assert_eq(d.picks[0], options[1])
	var rows := h.terminal.rows()
	assert_true(rows.has("you> 2"), "printed as the terminal would")
	await wait_process_frames(1)
	assert_true(h.terminal.chat.pills.is_empty(), "the pills clear on the answer")
	d.close()


## Review: a fork's descriptions are read in the chat, not cut off in a one-line pill. Every
## option's full "[n] name  description" shows in a wrapped card at 1920x1080, inside the chat's
## width; the pills keep only "[n] name". Fails without the option cards.
func test_a_forks_full_descriptions_show_in_the_chat_at_1080p() -> void:
	var h := await _hosted(S4)
	h.relayout(Vector2(1920, 1080))
	var d := h.game.debrief
	d.input_delay = 0.0
	h.game._on_report_ready(&"win")
	d.finish_lines()
	h.terminal.finish()
	await wait_process_frames(3)
	var choices: Array[String] = []
	for r in h.terminal.rows():
		if r.begins_with("[") and r.contains("  "):
			choices.append(r)
	assert_eq(choices.size(), d.fork_options().size(), "one choice row per option")
	var cards := h.terminal.chat.option_texts()
	assert_eq(cards, choices, "each option's full text is in a card")
	var room: float = (h.layout.terminal as Rect2).size.x
	for c in h.terminal.chat.find_children("Option*", "PanelContainer", true, false):
		var t := c.find_child("Text", true, false) as Label
		assert_true(t.visible and t.visible_characters == -1, "the description shows")
		assert_false(t.clip_text, "it wraps, never cuts")
		assert_lte((c as Control).size.x, room, "the card fits the chat")
	for i in choices.size():
		assert_eq(h.terminal.chat.pills[i], choices[i].get_slice("  ", 0), "the pill is the short name")
	d.close()


func test_a_fork_in_the_chat_still_answers_by_keys_1_to_3() -> void:
	var h2 := await _hosted(S4)
	var d2 := h2.game.debrief
	d2.input_delay = 0.0
	h2.game._on_report_ready(&"win")
	d2.finish_lines()
	var options := d2.fork_options()
	_key(&"choose_3")
	await wait_process_frames(1)
	assert_eq(d2.picks.size(), 1, "keys 1-3 still pick in the chat")
	assert_eq(d2.picks[0], options[2])
	d2.close()


func test_a_death_in_the_chat_asks_again_or_move_on_by_pills() -> void:
	var h := await _hosted(S4)
	var d := h.game.debrief
	d.input_delay = 0.0
	h.game._on_report_ready(&"lose")
	d.finish_lines()
	h.terminal.finish()
	await wait_process_frames(1)
	assert_eq(h.terminal.chat.pills, ["[1] " + DebriefScreen.AGAIN, "[2] " + DebriefScreen.MOVE_ON_ROW] as Array[String])
	var retries := []
	d.retry_requested.connect(func() -> void: retries.append(true))
	h.terminal.chat.pill_button(0).pressed.emit()
	assert_eq(retries.size(), 1, "the again pill")
	assert_true(h.terminal.rows().has("you> 1"))
	d.close()


func test_the_play_pill_at_a_gate() -> void:
	var h := await _hosted(S4)
	h.hold()
	assert_true(h.gate and h.held)
	await wait_process_frames(2)
	assert_eq(h.terminal.chat.pills, ["play"] as Array[String], "play as a quick reply")
	var held_at := RunState.game_time
	await wait_physics_frames(3)
	assert_eq(RunState.game_time, held_at, "the sim waits for play")
	h.terminal.chat.pill_button(0).pressed.emit()
	assert_false(h.held, "the pill is play")
	assert_false(RunState.is_paused_for(GameHost.HANDOFF))
	assert_true(h.terminal.rows().has("you> play"))
	await wait_process_frames(1)
	assert_true(h.terminal.chat.pills.is_empty())


func test_the_chats_gate_lines_and_replies_are_capitalised() -> void:
	var c := CampaignDB.campaign
	assert_eq(GameHost.gate_lines(null, true)[0].text, Line.parse(c.before_play_default_chat[0]).text)
	assert_eq(GameHost.gate_lines(null, false)[0].text, Line.parse(c.before_play_default[0]).text)
	assert_string_starts_with(Line.parse(c.chat_reply("hello", true)).text, "Hi.")
	assert_string_starts_with(Line.parse(c.chat_reply("hello", false)).text, "hi.")


# --- The late body pick ----------------------------------------------------------------------

func test_a_save_that_finished_s2_before_the_move_gets_the_body_at_its_next_beat() -> void:
	_load({"index": 3, "next": "s1_03_shooting", "done": ["s1_00_nothing", "s1_01_move", "s1_02_enemies"], "mascot": ""})
	assert_false(ChangeDB.get_fork(&"fork_mascot").is_answered())
	assert_eq(CampaignDB.late_forks(CampaignDB.get_session(S3)), [&"fork_mascot"] as Array[StringName])
	var h := await _hosted(S3, false)
	var d := h.game.debrief
	d.input_delay = 0.0
	h.game._on_report_ready(&"win")
	d.finish_lines()
	assert_eq(d.fork().id, &"fork_mascot", "first the late body pick")
	assert_true(d.pick(2))
	d.finish_lines()
	assert_eq(d.fork().id, &"fork_dash", "then S3's own")
	d.close()


func test_a_save_with_the_body_has_no_late_fork() -> void:
	_load({"index": 3, "next": "s1_03_shooting", "done": ["s1_00_nothing", "s1_01_move", "s1_02_enemies"], "mascot": "blob"},
			["mascot_blob"])
	assert_true(ChangeDB.get_fork(&"fork_mascot").is_answered())
	assert_true(CampaignDB.late_forks(CampaignDB.get_session(S3)).is_empty())
	assert_true(CampaignDB.late_forks(CampaignDB.get_session(S4)).is_empty(), "a jump (nothing done) has none")


# --- The chat's look ------------------------------------------------------------------------

func test_the_chat_takes_the_pixel_colours_at_the_ui_reveal() -> void:
	var was := Skins.current
	var t := TerminalPanel.new()
	t.size = Vector2(480, 720)
	add_child_autofree(t)
	t.set_style(TerminalPanel.CHAT)
	t.say_row("hello", &"happy")
	t.cmd("build v0.9.0", "ok")
	t.finish()
	assert_eq(t.chat.col(&"bg"), Palette.CHAT_BG)
	Skins.use(Skins.pixel())
	Skins.reset_reveal(true)
	t.dress()
	assert_eq(t.chat.col(&"bg"), Palette.CHAT_BG, "before the ui reveal")
	Skins.reveal(&"ui")
	assert_eq(t.palette_name, &"pixel")
	assert_ne(t.chat.col(&"bg"), Palette.CHAT_BG, "the reveal recolours the chat")
	assert_eq((t.get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color, t.chat.col(&"bg"), "the back too")
	var bubble: Label = t._order.back() if t._order.back() is Label and t._order.back().has_meta(&"row_prefix") else null
	for e: Variant in t._order:
		if e is Label and (e as Label).has_meta(&"row_prefix"):
			bubble = e
	assert_not_null(bubble)
	assert_eq(bubble.get_theme_color(&"font_color"), t.chat.col(&"text"), "a bubble already shown")
	Skins.use(was)
	t.dress()
	assert_eq(t.chat.col(&"bg"), Palette.CHAT_BG)


func test_the_chat_lists_rows_as_the_terminal_and_keeps_the_raw_rows() -> void:
	var t := TerminalPanel.new()
	t.size = Vector2(480, 720)
	add_child_autofree(t)
	t.sys("before")
	t.finish()
	t.set_style(TerminalPanel.CHAT)
	t.set_style(TerminalPanel.RAW)
	assert_true(t.is_chat(), "one way")
	t.say_row("one")
	t.think(0.0)
	t.cmd("build v0.3.0", "ok")
	t.cmd("patch apply v0.3.0")
	t.notes({"Added": ["Shooting"] as Array[String], "Changed": [] as Array[String], "Fixed": [] as Array[String]})
	t.ask(["a", "b"] as Array[String])
	t.finish()
	t.answer("2")
	t.you_said("play")
	var rows := t.rows()
	assert_eq(rows[0], "before", "the raw rows stay (collapsed, not deleted)")
	for want: String in ["  one", "ai is thinking . . .", "$ build v0.3.0 ... ok", "$ patch apply v0.3.0",
			"  + Added shooting", "[1] a", "[2] b", "you> 2", "you> play"]:
		assert_true(rows.has(want), "row %s" % want)
	assert_eq(t.chat.log_rows().back(), "$ patch apply v0.3.0")
