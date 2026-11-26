extends GutTest
## M47.5a (PLAN v9.3, 0.7): always on, part 1 (part 2, M47.5b: the story flow, at the end). The host (the game in a 1280x720-rect
## SubViewport beside the terminal, PAUSABLE inside ALWAYS), the terminal's rows, the
## debrief's terminal view (same API and labels, one way on per open), the hot-reload swap and
## the ready moment. Hosts here are tool hosts (never live): no window change, no auto way on.

const S0 := &"s1_00_nothing"
const S2 := &"s1_02_enemies"
const S3 := &"s1_03_shooting"
const S4 := &"s1_04_level"
const S7 := &"s2_01_tryout"
const S8 := &"s2_02_day_one"
const TEST_LOG := "user://m47_5a_test/t.jsonl"

var _live_host: GameHost


## Records the mouse motion events that reach the game (inside the SubViewport).
class MotionProbe:
	extends Node
	var seen: Array[Vector2] = []
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			seen.append((event as InputEventMouseMotion).position)

var _prev_scene: Node


func after_each() -> void:
	Input.action_release(&"move_right")
	StartScreen.save_live = true   # M47.5b: _start_screen() turned it off
	StartScreen.test_boot = false
	StartScreen.enter_hook = Callable()
	StartScreen.new_game_pending = false
	GameHost.first_run_prompt = false
	Main.leave_hook = Callable()
	if _live_host != null and is_instance_valid(_live_host):
		get_tree().current_scene = _prev_scene
		_live_host.free()
	_live_host = null
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(TEST_LOG)
	SaveGame.set_setting("reduce_flashing", false)
	RunState.clear_pauses()
	CampaignDB.active = false
	CampaignDB.jumped = false
	GameHost.auto_beats = true
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null


func _hosted(id: StringName, view := Vector2i.ZERO) -> GameHost:
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var g: Main = load("res://main.tscn").instantiate()
	var h := GameHost.host_for_tools(g, view)
	add_child_autofree(h)
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	RunState.invincible = true
	return h


## A host that is the current scene (the live always-on window, minus the window change):
## the game is the live game, its telemetry goes to TEST_LOG, Main.leave_hook stands in for
## the scene change. after_each puts the test scene back.
func _hosted_live(id: StringName) -> GameHost:
	Telemetry.log_path = TEST_LOG
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var g: Main = load("res://main.tscn").instantiate()
	var h := GameHost.host_for_tools(g)
	_live_host = h
	get_tree().root.add_child(h)
	_prev_scene = get_tree().current_scene
	get_tree().current_scene = h
	h.tools = false
	assert_true(h.is_live() and g.is_live_game())
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	RunState.invincible = true
	return h


## A real key press (StageCard reads keys, not actions).
func _press_key(code: Key) -> void:
	for down: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		Input.flush_buffered_events()


func _terminal() -> TerminalPanel:
	var t := TerminalPanel.new()
	t.size = Vector2(480, 720)
	add_child_autofree(t)
	return t


func _key(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()


# --- Layout ------------------------------------------------------------------------------

func test_layout_at_the_base_and_at_1080p() -> void:
	var a := GameHost.layout_for(Vector2(1760, 720))
	assert_almost_eq(float(a.k), 1.0, 0.0001)
	assert_eq(a.game, Rect2(0, 0, 1280, 720))
	assert_eq(a.terminal, Rect2(1280, 0, 480, 720), "the terminal: 480 px at the base")
	assert_eq(int(a.font), 16)
	var b := GameHost.layout_for(Vector2(1920, 1080))
	assert_almost_eq(float(b.k), 1.21875, 0.0001, "k = (1920 - 360) / 1280")
	assert_eq((b.game as Rect2).size, Vector2(1560, 878))
	assert_eq((b.game as Rect2).position.y, 101.0, "centred vertically")
	assert_eq((b.terminal as Rect2).size, Vector2(360, 1080), "the terminal keeps its 360 px")
	assert_eq(int(b.font), 20, "16 x 1.22")


func test_the_game_rect_is_1280x720_at_any_view_size_and_the_modes_hold() -> void:
	var h := await _hosted(S4, Vector2i(1560, 878))
	var g := h.game
	assert_eq(g.get_viewport(), h.viewport)
	assert_eq(h.viewport.size, Vector2i(1560, 878))
	assert_eq(g.get_viewport().get_visible_rect().size, Vector2(1280, 720), "size_2d_override")
	assert_eq(g.camera.get_viewport_rect().size, Vector2(1280, 720))
	assert_eq(g.process_mode, Node.PROCESS_MODE_PAUSABLE)
	for n: Node in [h, h.view, h.viewport, h.terminal]:
		assert_eq(n.process_mode, Node.PROCESS_MODE_ALWAYS, n.name)
	assert_eq(g.host, h)
	assert_false(h.is_live(), "a tool host is never live")
	assert_false(g.is_live_game(), "no telemetry, no reload")
	assert_eq(g.debrief.view, DebriefScreen.TERMINAL)
	assert_false(g.debrief.auto_way_on)
	assert_true(g.mascot.bubble_enabled, "M47.6a: hosted, the bubble is on during play")


func test_every_pause_reason_freezes_the_hosted_game_not_the_host() -> void:
	var h := await _hosted(S4)
	var g := h.game
	assert_true(g.can_process())
	for reason: StringName in [&"debrief", PickPanel.PAUSE, RunState.MENU, &"stage_card", GameHost.HANDOFF]:
		RunState.set_pause(reason, true)
		assert_false(g.can_process(), "%s freezes the game" % reason)
		assert_false(g.player.can_process(), "%s freezes the player" % reason)
		assert_true(h.terminal.can_process() and h.view.can_process() and h.viewport.can_process(), reason)
		assert_true(g.debrief.can_process() and g.pause_menu.can_process(), "the game's ALWAYS UI runs")
		RunState.set_pause(reason, false)
	assert_true(g.can_process())


func test_typing_while_paused_leaves_game_time_unchanged() -> void:
	var h := await _hosted(S4)
	RunState.set_pause(&"debrief", true)
	var at := RunState.game_time
	h.terminal.live_say(Line.make("A long line that takes a while to type out in full."), 2)
	await wait_process_frames(12)
	assert_eq(RunState.game_time, at, "the terminal never steps game time")
	assert_true(h.terminal.is_busy() or h.terminal.rows().back().contains("A long line"))
	RunState.set_pause(&"debrief", false)


# --- Input through the container -----------------------------------------------------------

func test_pause_reaches_the_pause_menu_through_the_container() -> void:
	var h := await _hosted(S4)
	var g := h.game
	assert_true(g.pause_menu.can_open())
	_key(&"pause")
	await wait_process_frames(2)
	assert_true(g.pause_menu.is_open(), "Esc reaches PauseMenu inside the SubViewport")
	g.pause_menu.close()
	await wait_process_frames(1)
	assert_false(g.pause_menu.is_open())


func test_s3s_three_forks_take_one_key_each_and_land_on_the_corner() -> void:
	var h := await _hosted(S3)
	var g := h.game
	var d := g.debrief
	d.input_delay = 0.0
	g._on_report_ready(&"win")
	assert_true(d.is_open())
	assert_null(d.big_body, "terminal view: no big body")
	assert_true(g.mascot.visible, "the corner body stays for the beat")
	d.finish_lines()
	assert_eq(d.phase, DebriefScreen.FORK)
	assert_eq(g.mascot.body.expression, &"thinking", "thinking lands on the corner body")
	assert_eq(d.box_count(), 3, "three raw preview boxes over the game")
	var opts := d.fork_options()
	assert_eq(opts[0].fork, &"fork_mascot")
	_key(&"choose_2")
	await wait_process_frames(1)
	assert_eq(d.picks.size(), 1, "one key, one pick")
	var body_id: StringName = opts[1].take.id
	assert_true(g.mascot.face, "the pick lands on the corner at once")
	assert_eq(g.mascot.body_id, body_id)
	assert_eq(h.terminal.speaker, GameHost.speaker_for(body_id), "the prompt renames itself")
	assert_true(h.terminal.has_face)
	assert_eq(d.box_count(), 0, "the boxes clear on the pick")
	for i in 2:
		d.finish_lines()
		assert_eq(d.phase, DebriefScreen.FORK, "fork %d" % (i + 2))
		_key(&"choose_1")
		await wait_process_frames(1)
		assert_eq(d.picks.size(), i + 2)
	d.finish_lines()
	assert_eq(d.choices(), [DebriefScreen.NEXT] as Array[String], "the labels stay")
	var rows := h.terminal.rows()
	assert_true(rows.has("you> 2"), "the answer is printed")
	assert_true(rows.any(func(r: String) -> bool: return r.begins_with("[1] ")), "numbered choices")
	d.close()


# --- The terminal --------------------------------------------------------------------------

func test_a_won_s0_end_prints_frozen_lines_thinking_and_the_patch() -> void:
	var h := await _hosted(S0)
	var g := h.game
	var d := g.debrief
	d.input_delay = 0.0
	g._on_report_ready(&"stop")
	d.finish_lines()
	h.terminal.finish()
	var rows := h.terminal.rows()
	assert_true(rows.has("[game frozen]"))
	for line in d.said:
		assert_true(rows.has("  " + line), "said: %s" % line)
	var head := rows.filter(func(r: String) -> bool: return r.contains("ai@patchnotes"))
	assert_false(head.is_empty(), "the header names ai@ before the body pick")
	assert_false(head[0].contains("("), "no expression tag on the caret")
	var v := CampaignDB.version_after(RunState.session).label()
	assert_true(rows.has("ai is thinking . . ."))
	assert_true(rows.has("$ build %s ... ok" % v))
	assert_true(rows.has("$ patch apply %s" % v))
	assert_true(rows.has("  + Added movement"), "the changelog as notes")
	assert_eq(d.choices(), [DebriefScreen.NEXT] as Array[String])
	d.close()


func test_one_way_on_per_open_and_a_death_asks_again_or_move_on() -> void:
	var h := await _hosted(S4)
	var g := h.game
	var d := g.debrief
	d.input_delay = 0.0
	g._on_report_ready(&"lose")
	d.finish_lines()
	assert_eq(d.choices(), [DebriefScreen.RETRY, DebriefScreen.MOVE_ON] as Array[String], "labels unchanged")
	h.terminal.finish()
	var rows := h.terminal.rows()
	assert_true(rows.has("[1] " + DebriefScreen.AGAIN))
	assert_true(rows.has("[2] " + DebriefScreen.MOVE_ON_ROW))
	var retries := []
	d.retry_requested.connect(func() -> void: retries.append(true))
	var before := SaveGame.attempts(S4)
	assert_true(d.choose(DebriefScreen.RETRY))
	assert_false(d.choose(DebriefScreen.RETRY), "the latch: a second choose does nothing")
	_key(&"choose_1")
	await wait_process_frames(1)
	assert_eq(retries.size(), 1, "one _end_session per choose pair")
	assert_eq(SaveGame.attempts(S4), before + 1, "one attempt")
	assert_true(h.terminal.rows().has("you> 1"))
	d.close()


func test_play_mode_completes_a_cut_line_at_once_and_marks_it() -> void:
	var t := _terminal()
	var a := Line.make("First line, long enough to still be typing.", &"happy")
	var b := Line.make("Second.", &"idle")
	t.live_say(a, 2)
	await wait_process_frames(2)
	t.live_cut(a)
	t.live_say(b, 2)
	var rows := t.rows()
	assert_true(rows.has("  " + a.text + TerminalPanel.CUT), "completed now, with the cut mark")
	assert_true(rows.back().ends_with(b.text))
	var chatter := Line.make("chatter that is far too long to fit on one row of the terminal at all, really", &"idle")
	t.live_say(chatter, 1)
	var last: Label = t._list.get_child(t._list.get_child_count() - 1).get_node(^"Text")
	assert_true(last.clip_text, "chatter is clipped to one row")


## M47.6a (PLAN v9.4 2.4; was "with no bubble"): during play the line is in the bubble and the
## terminal logs it whole and dim at once; the beat hides the bubble.
func test_the_mascot_speaks_in_the_bubble_and_the_terminal_logs_it_dim() -> void:
	var h := await _hosted(S4)
	var m := h.game.mascot
	m.say(Line.make("Routed to the terminal.", &"happy"), 3, true)
	m.step(0.016)
	assert_true(m._bubble.visible, "the bubble during play")
	assert_true(m.is_speaking(), "the corner keeps its queue and timing")
	assert_true(h.terminal.rows().back().ends_with("Routed to the terminal."))
	var last: Label = h.terminal._list.get_child(h.terminal._list.get_child_count() - 1).get_node(^"Text")
	assert_eq(last.visible_characters, -1, "logged whole, no typing")
	assert_eq(last.get_meta(&"tone"), &"dim", "dim: history")
	h.game._on_report_ready(&"win")
	assert_false(m.bubble_enabled, "the beat: no bubble")
	m.say(Line.make("In the beat.", &"happy"), 3, true)
	m.step(0.016)
	assert_false(m._bubble.visible)
	h.game.debrief.close()


func test_the_row_cap_the_spinner_and_the_steady_caret() -> void:
	var t := _terminal()
	for i in 350:
		t.sys("row %d" % i)
	t.finish()
	assert_eq(t.row_count(), TerminalPanel.MAX_ROWS)
	assert_eq(t.rows().back(), "row 349")
	var frames := t.spinner_frames()
	assert_eq(frames == TerminalPanel.SPINNER, UiTheme.mono_font().has_char(0x280B), "braille only when the font has it")
	t.gentle = true
	t.prompt()
	t.finish()
	for i in 40:
		await wait_process_frames(1)
		assert_eq(t.rows().back(), "you> _", "reduce flashing: a steady caret")


func test_the_clock_and_the_shared_header() -> void:
	var t := _terminal()
	t.session_index = 4
	assert_eq(t.clock_text(), "[14:12]", "14:00 + 3 min per session")
	t.say_row("one")
	t.say_row("two")
	var heads := t.rows().filter(func(r: String) -> bool: return r.contains("@patchnotes"))
	assert_eq(heads.size(), 1, "the same speaker within 10 s shares one header")
	t.set_speaker("blob", true)
	t.say_row("three", &"happy")
	assert_true(t.rows().any(func(r: String) -> bool: return r.ends_with("blob@patchnotes (happy)")))


# --- The swap and the ready moment ---------------------------------------------------------

func test_the_swap_frees_the_old_game_later_and_the_handoff_waits_for_input() -> void:
	var h := await _hosted(S4)
	var old := h.game
	RunState.set_pause(GameHost.HANDOFF, true)
	h.next_session()
	assert_true(is_instance_valid(old) and h.game == old, "the old game is whole on the swap's frame")
	await wait_process_frames(2)
	assert_false(is_instance_valid(old), "freed by the swap")
	assert_ne(h.game, null)
	assert_eq(h.swaps, 1)
	assert_eq(h.game.process_mode, Node.PROCESS_MODE_PAUSABLE)
	assert_eq(RunState.session.id, S4)
	assert_true(h.held and RunState.is_paused_for(GameHost.HANDOFF), "the ready moment holds")
	assert_false(h.game.can_process())
	assert_true(h.game.pause_menu.can_open(), "M47.6a: Esc at the play gate opens the pause menu")
	var t0 := RunState.game_time
	await wait_process_frames(10)
	assert_true(h.held, "no input: still held")
	assert_eq(RunState.game_time, t0)
	assert_true(h.terminal.rows().has("$ hot-reload game ... ok"))
	# M47.6a (PLAN v9.4 2.5): a move no longer releases it; play does.
	Input.action_press(&"move_right")
	await wait_process_frames(2)
	Input.action_release(&"move_right")
	assert_true(h.held, "a move is not play (M47.6a)")
	assert_eq(RunState.game_time, t0)
	h.give_play()
	await wait_process_frames(2)
	assert_false(h.held, "play releases it")
	assert_true(h.game.can_process())
	assert_true(h.terminal.rows().has("you> play"))


func test_bot_hosts_keep_the_reload_timing_and_skip_handoff_releases() -> void:
	var h := await _hosted(S4)
	GameHost.auto_beats = false
	h.next_session("restart s1_04_level (try 2)")
	await wait_process_frames(2)
	assert_false(h.held, "a bot chain swaps with no hold (the old reload's timing)")
	assert_true(h.terminal.rows().has("$ restart s1_04_level (try 2) ... ok"))
	h.hold()
	assert_true(h.held)
	h.skip_handoff()
	assert_false(h.held)
	assert_false(RunState.is_paused_for(GameHost.HANDOFF))


func test_reduce_flashing_turns_the_glitch_into_a_crossfade() -> void:
	var h := await _hosted(S4)
	SaveGame.set_setting("reduce_flashing", true)
	h._pulse()
	assert_true(h._fade.visible)
	assert_false(h._glitch.visible)
	SaveGame.set_setting("reduce_flashing", false)
	h._pulse()
	assert_true(h._glitch.visible)


# --- Mouse and window ----------------------------------------------------------------------

## The container hands the SubViewport its own pixels; the viewport's stretch maps them back
## to the 1280x720 canvas, so a game pixel is the same world point at any k.
func test_a_click_point_maps_to_the_same_world_point_at_k_1_and_1_22() -> void:
	var h := await _hosted(S4)
	var points: Array[Vector2] = []
	for window: Vector2 in [Vector2(1760, 720), Vector2(1920, 1080)]:
		h.relayout(window)
		await wait_process_frames(1)
		var r := h.game_rect()
		var k := r.size.x / 1280.0
		assert_eq(Vector2(h.viewport.size), r.size, "the viewport fills the game column")
		var pixel := Vector2(640, 200) * k   # where a click lands in the viewport's pixels
		points.append(h.viewport.get_final_transform().affine_inverse() * pixel)
	assert_almost_eq(points[0].x, points[1].x, 0.5, "same canvas x")
	assert_almost_eq(points[0].y, points[1].y, 0.5, "same canvas y")
	assert_almost_eq(points[0].x, 640.0, 0.5)
	assert_almost_eq(points[1].y, 200.0, 0.5)


func test_the_window_base_is_set_and_restored() -> void:
	var h := await _hosted(S4)
	var root := get_tree().root
	var mode := root.content_scale_mode
	h._set_window(true)
	assert_eq(root.content_scale_mode, Window.CONTENT_SCALE_MODE_DISABLED)
	assert_eq(Settings._base_size, GameHost.BASE)
	h._set_window(false)
	assert_eq(root.content_scale_mode, mode, "restored for the title and the cooking screen")
	assert_eq(Settings._base_size, GameHost.PROJECT_BASE)
	assert_eq(Settings.clamped_size(Vector2(3520, 1440), Vector2(1920, 1040)), Vector2i(1920, 785),
			"one uniform factor")


# --- M47.5a review ---------------------------------------------------------------------------

## A hosted session that ends in a scene change (the replay's Next, the campaign's end) set the
## handoff pause and never cleared it: the title came back paused.
func test_a_hosted_replay_next_leaves_nothing_paused_for_the_title() -> void:
	SaveGame.begin_replay(&"fork_path", &"path_auto")
	var h := await _hosted_live(S4)
	var g := h.game
	var left: Array[String] = []
	Main.leave_hook = func(path: String) -> void: left.append(path)
	g.debrief.input_delay = 0.0
	g._on_report_ready(&"win")
	g.debrief.finish_lines()
	assert_true(g.debrief.is_open())
	g._end_session(&"next")
	assert_eq(left, [StartScreen.TITLE_SCENE] as Array[String], "the replay ends on the title")
	assert_false(RunState.is_paused_for(GameHost.HANDOFF), "no handoff pause behind the title")
	assert_false(get_tree().paused, "the title is not paused")
	assert_false(h._swap_queued, "no swap")


func test_the_host_leaving_clears_a_held_handoff() -> void:
	var h := await _hosted(S4)
	h.hold()
	assert_true(get_tree().paused)
	h.get_parent().remove_child(h)
	assert_false(RunState.is_paused_for(GameHost.HANDOFF))
	assert_false(get_tree().paused)
	h.free()


## F5 (DebugOverlay: game.restart(true)) returned early when hosted: the host is the scene.
func test_the_debug_restart_swaps_the_same_seed_in_through_the_host() -> void:
	var h := await _hosted_live(S4)
	var old := h.game
	var seed_was := RunState.run_seed
	old.restart(true)
	assert_true(h._swap_queued, "routed through the host's hot-reload")
	assert_eq(Main.next_seed, seed_was, "the same seed")
	assert_true(RunState.is_paused_for(GameHost.HANDOFF), "frozen until the swap")
	await wait_process_frames(40)
	assert_eq(h.swaps, 1)
	assert_false(is_instance_valid(old))
	assert_eq(RunState.session.id, S4)
	assert_eq(RunState.run_seed, seed_was)
	assert_true(h.held, "the ready moment")
	h.skip_handoff()


## The host and its terminal live for the whole sitting: Options' reduce flashing reaches the
## caret at once.
func test_the_caret_reads_reduce_flashing_live() -> void:
	var t := _terminal()
	var off := t._start_usec + 600000   # the caret's off half-second
	assert_false(t.caret_on(off), "1 Hz blink")
	SaveGame.set_setting("reduce_flashing", true)
	assert_true(t.caret_on(off), "steady at once, no new host")
	t.prompt()
	t.finish()
	t._start_usec = Time.get_ticks_usec() - 600000
	await wait_process_frames(1)
	assert_eq(t.rows().back(), "you> _")
	SaveGame.set_setting("reduce_flashing", false)
	assert_false(t.caret_on(t._start_usec + 600000), "blinks again once it is off")


## A key reaches the StageCard inside the SubViewport (the live host waits on it at S7).
func test_a_key_reaches_the_stage_card_through_the_container() -> void:
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(S7))
	var g: Main = load("res://main.tscn").instantiate()
	var h := GameHost.host_for_tools(g)
	add_child_autofree(h)
	var card := g.stage_card
	assert_not_null(card, "S7 opens a stage")
	await wait_process_frames(1)
	assert_true(card.is_open())
	for i in 10:
		if not card.is_open():
			break
		card.elapsed += StageCard.SKIP_AFTER + 0.05
		_press_key(KEY_SPACE)
		await wait_process_frames(1)
	assert_false(card.is_open(), "keys through the container closed the card")
	assert_false(RunState.is_paused_for(&"stage_card"))


## choose_1 reaches an Arsenal PickPanel inside the SubViewport.
func test_choose_1_reaches_a_pick_panel_through_the_container() -> void:
	assert_true(CampaignDB.answer_fork(&"fork_path", &"path_arsenal"))
	var h := await _hosted(S8)
	var panel := h.game.ensure_path_runner().panel
	var offer := PickOffer.new()
	offer.cards.append({"id": &"shotgun", "rank": 1, "kind": &"new", "text": "Shotgun"})
	offer.cards.append({"id": &"smg", "rank": 1, "kind": &"new", "text": "SMG"})
	panel.input_delay = 0.0
	var got: Array[int] = []
	panel.picked.connect(func(_o: PickOffer, i: int) -> void: got.append(i))
	assert_true(panel.open(offer))
	assert_true(get_tree().paused)
	_key(&"choose_1")
	await wait_process_frames(1)
	assert_eq(got, [0] as Array[int], "choose_1 picked the first card")
	assert_false(panel.is_open())
	assert_false(RunState.is_paused_for(PickPanel.PAUSE))


## Real mouse events through the container: the same game pixel is the same world point at
## k = 1 and k = 1.22 (the column's offset included), and motion over the terminal is clamped
## to the column's edge.
func test_real_mouse_events_map_through_the_container_and_clamp_over_the_terminal() -> void:
	var h := await _hosted(S4)
	RunState.set_pause(&"debrief", true)   # the camera holds still; the container still forwards
	var probe := MotionProbe.new()
	probe.process_mode = Node.PROCESS_MODE_ALWAYS
	h.game.add_child(probe)
	var world: Array[Vector2] = []
	for window: Vector2 in [Vector2(1760, 720), Vector2(1920, 1080)]:
		h.relayout(window)
		await wait_process_frames(1)
		var r := h.game_rect()
		var k := r.size.x / 1280.0
		_motion(r.position + Vector2(640, 200) * k)
		await wait_process_frames(1)
		assert_false(probe.seen.is_empty(), "the motion reached the game")
		assert_almost_eq(probe.seen.back().x, 640.0, 1.0, "event x in the game at k %.2f" % k)
		assert_almost_eq(probe.seen.back().y, 200.0, 1.0, "event y in the game at k %.2f" % k)
		var canvas := h.viewport.get_mouse_position()
		assert_almost_eq(canvas.x, 640.0, 1.0, "canvas x at k %.2f" % k)
		assert_almost_eq(canvas.y, 200.0, 1.0, "canvas y at k %.2f (offset %.0f)" % [k, r.position.y])
		world.append(h.game.get_global_mouse_position())
	assert_almost_eq(world[0].x, world[1].x, 1.0, "same world x")
	assert_almost_eq(world[0].y, world[1].y, 1.0, "same world y")
	h.relayout(Vector2(1760, 720))
	await wait_process_frames(1)
	assert_eq(h.game_rect(), Rect2(0, 0, 1280, 720), "back to the base column after 1080p")
	probe.seen.clear()
	_motion(Vector2(1500, 300))   # over the terminal
	await wait_process_frames(1)
	assert_eq(probe.seen.size(), 1, "one motion reaches the game (the host's push, not the container)")
	var at: Vector2 = probe.seen.back() if not probe.seen.is_empty() else Vector2.ZERO
	assert_almost_eq(at.x, 1279.0, 1.0, "clamped to the column's right edge")
	assert_almost_eq(at.y, 300.0, 1.0)
	assert_gt(h.viewport.get_mouse_position().x, 1279.0, "the aim still follows the real mouse")
	RunState.set_pause(&"debrief", false)


## A motion at `at` in the root's canvas pixels (the host's coordinates), sent in window pixels
## (headless, the root's content scale maps them).
func _motion(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = get_tree().root.get_final_transform() * at
	e.global_position = e.position
	Input.parse_input_event(e)
	Input.flush_buffered_events()


# --- M47.5b: the story flow (part 2) -----------------------------------------------------------

func _cleanup_5b() -> void:
	StartScreen.save_live = true
	StartScreen.test_boot = false
	StartScreen.enter_hook = Callable()
	GameHost.first_run_prompt = false
	Settings.set_value("vol_master", 1.0)
	Settings.set_value("window_mode", 0)
	SaveGame.set_setting("asked", false)


## A start screen on the inert save: save_live false first (the real save must never go live
## or be read in a test; _cleanup_5b puts it back).
func _start_screen() -> StartScreen:
	StartScreen.save_live = false
	var s: StartScreen = load("res://ui/start_screen.tscn").instantiate()
	add_child_autofree(s)
	return s


func test_boot_routing_host_before_the_door_title_after_raw_for_copies() -> void:
	SaveGame.go_inert()
	var copy := _start_screen()
	assert_false(copy.is_boot_scene(), "an add_child'ed copy (tools, tests) is not the boot")
	assert_not_null(copy.continue_button, "it gets the raw column, as before")
	assert_null(copy.title)
	# The booted screen before the front door builds nothing and enters the host.
	var went: Array[String] = []
	StartScreen.test_boot = true
	StartScreen.enter_hook = func(path: String) -> void: went.append(path)
	var boot := _start_screen()
	assert_eq(boot.get_child_count(), 0, "no screen at all")
	assert_null(boot.continue_button)
	await wait_process_frames(1)
	assert_eq(went, [StartScreen.GAME_SCENE] as Array[String], "straight into the host")
	assert_true(CampaignDB.active)
	assert_eq(Main.next_seed, -1)
	assert_true(GameHost.first_run_prompt, "never asked: the installer asks in the terminal")
	# Asked once: no prompt.
	SaveGame.set_setting("asked", true)
	went.clear()
	var again := _start_screen()
	await wait_process_frames(1)
	assert_eq(went.size(), 1)
	assert_false(GameHost.first_run_prompt, "asked before: no prompt")
	assert_eq(again.get_child_count(), 0)
	# From the door on, the boot opens on the title (M47.4 routing).
	assert_true(CampaignDB.jump_to(S8))
	assert_true(CampaignDB.front_door_open())
	went.clear()
	var titled := _start_screen()
	await wait_process_frames(1)
	assert_not_null(titled.title, "the title")
	assert_eq(went, [] as Array[String], "no shell entry")
	# The legacy loop is never shelled.
	StartScreen.legacy_loop = true
	assert_false(_start_screen().is_boot_scene())
	StartScreen.legacy_loop = false
	_cleanup_5b()


func test_enter_shell_ends_a_replay_and_goes_where_continue_goes() -> void:
	var went: Array[String] = []
	StartScreen.enter_hook = func(path: String) -> void: went.append(path)
	var s := _start_screen()   # its own _ready (the raw column) ends a replay: begin one after it
	SaveGame.begin_replay(&"fork_path", &"path_auto")
	assert_true(SaveGame.in_replay(), "a replay is on before _enter_shell")
	s._enter_shell()
	assert_false(SaveGame.in_replay(), "the replay ended")
	assert_eq(went, [StartScreen.continue_target()] as Array[String])
	_cleanup_5b()


func test_the_installer_asks_once_before_s0_and_its_answer_is_saved() -> void:
	var h := await _hosted(S0)
	SaveGame.set_setting("asked", false)
	h.ask_first_run()
	h.terminal.finish()
	var rows := h.terminal.rows()
	assert_true(rows.has(GameHost.FIRST_RUN_LINE), "the installer's line, not the AI's")
	assert_true(rows.has("[1] no") and rows.has("[2] yes"))
	var asked_rows := rows.slice(rows.find(GameHost.FIRST_RUN_LINE))
	assert_false(asked_rows.any(func(r: String) -> bool: return r.contains("@patchnotes")), "the AI does not speak")
	assert_true(RunState.is_paused_for(GameHost.HANDOFF), "S0 waits before its first frame")
	var t0 := RunState.game_time
	await wait_process_frames(5)
	assert_eq(RunState.game_time, t0)
	_key(&"choose_2")
	await wait_process_frames(2)
	assert_false(h.asking_first_run)
	assert_true(SaveGame.reduce_flashing(), "2 = yes")
	assert_true(bool(SaveGame.setting("asked")))
	assert_true(h.terminal.rows().has("you> 2"))
	assert_false(RunState.is_paused_for(GameHost.HANDOFF), "S0 starts")
	assert_true(h.game.can_process())
	_key(&"choose_1")
	await wait_process_frames(1)
	assert_true(SaveGame.reduce_flashing(), "asked once: a later 1 changes nothing")
	_cleanup_5b()


func test_chapter_mode_hides_the_terminal_around_the_stage_card() -> void:
	var c := GameHost.layout_for(Vector2(1920, 1080), true)
	assert_almost_eq(float(c.k), 1.5, 0.0001)
	assert_eq(c.game, Rect2(0, 0, 1920, 1080))
	var b := GameHost.layout_for(Vector2(1760, 720), true)
	assert_eq(b.game, Rect2(240, 0, 1280, 720), "centred, k from the window")
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(S7))
	var g: Main = load("res://main.tscn").instantiate()
	var h := GameHost.host_for_tools(g)
	add_child_autofree(h)
	assert_true(g.stage_card.is_open())
	assert_true(h.chapter, "chapter mode")
	assert_false(h.terminal.visible, "the terminal hides")
	h.terminal.finish()
	assert_false(h.terminal.rows().has("$ run %s" % S7), "the session rows wait for the card")
	h.hold()
	g.stage_card.skip()
	await wait_process_frames(2)
	assert_false(h.chapter)
	assert_true(h.terminal.visible)
	h.terminal.finish()
	var rows := h.terminal.rows()
	var chapter_row := "--- chapter 2 · %s ---" % CampaignDB.campaign.stage_titles[2]
	assert_true(rows.has(chapter_row), "the chapter's row")
	var at := rows.find(chapter_row)
	assert_gt(rows.find("$ run %s" % S7), at, "then the session's rows")
	# M47.6a: then the play gate: its before_play line typed after the session's rows.
	var bp := "  " + GameHost.gate_lines(RunState.session)[0].text
	assert_gt(rows.find(bp), rows.find("$ run %s" % S7), "then the gate's lines")
	assert_true(h.gate and h.held)
	h.skip_handoff()


func _died(h: GameHost) -> DebriefScreen:
	var d := h.game.debrief
	d.input_delay = 0.0
	d.auto_way_on = true
	h.game._on_report_ready(&"lose")
	d.finish_lines()
	h.terminal.finish()
	return d


## M47.6a (PLAN v9.4 2.5, D7; rewrites M47.5b's countdown tests): the death ask waits, with no
## countdown; Enter counts only once armed (the lines typed + 0.4 s, a fresh press).
func test_the_death_ask_has_no_countdown_and_enter_is_armed() -> void:
	var h := await _hosted(S4)
	var d := _died(h)
	var retries := []
	d.retry_requested.connect(func() -> void: retries.append(true))
	var before := SaveGame.attempts(S4)
	await wait_process_frames(2)
	assert_false(h.terminal.rows().any(func(r: String) -> bool: return r.begins_with("restarting in")), "no countdown")
	assert_false(d.ask_enter_armed(), "not armed in its first 0.4 s")
	_key(&"ui_accept")
	await wait_process_frames(1)
	assert_eq(retries.size(), 0, "an early Enter does not restart unread")
	d._ask_arm_msec -= 1000
	await wait_process_frames(30)
	assert_eq(retries.size(), 0, "it waits; nothing restarts by itself")
	assert_true(d.ask_enter_armed())
	_key(&"ui_accept")
	await wait_process_frames(1)
	assert_eq(retries.size(), 1, "an armed Enter = again")
	assert_eq(SaveGame.attempts(S4), before + 1, "one attempt")
	assert_true(h.terminal.rows().has("you> 1"))
	_key(&"ui_accept")
	await wait_process_frames(1)
	assert_eq(retries.size(), 1, "never twice")
	d.close()


func test_at_the_death_ask_1_is_again_at_once_and_2_moves_on() -> void:
	var h := await _hosted(S4)
	var d := _died(h)
	var retries := []
	d.retry_requested.connect(func() -> void: retries.append(true))
	_key(&"choose_1")
	await wait_process_frames(1)
	assert_eq(retries.size(), 1, "1 is again (no arming for the number key)")
	d.close()
	var d2 := _died(h)
	var moved := []
	d2.move_on_requested.connect(func() -> void: moved.append(true))
	await wait_process_frames(2)
	_key(&"choose_2")
	await wait_process_frames(1)
	d2.finish_lines()
	await wait_process_frames(2)
	assert_eq(retries.size(), 1)
	assert_true(d2.moved_on)
	d2.close()


func test_one_telemetry_line_per_attempt_with_flow_and_beat_seconds() -> void:
	var h := await _hosted_live(S4)
	var g := h.game
	var d := _died(h)
	await wait_process_frames(2)
	_key(&"choose_1")   # M47.6a: again by key (no countdown)
	await wait_process_frames(3)
	var lines := FileAccess.get_file_as_string(TEST_LOG).strip_edges().split("\n")
	assert_eq(lines.size(), 1, "one line for the attempt")
	var rec: Dictionary = JSON.parse_string(lines[0])
	assert_eq(rec.choice, "retry", "the same choice value")
	assert_eq(rec.flow, "always_on")
	assert_true(float(rec.beat_real_s) >= 0.0)
	var plain := CampaignDB.telemetry_record(RunState.session, {}, &"died", 0, &"retry", Main.BUILD)
	var keys: Array = rec.keys().filter(func(k: String) -> bool: return k != "flow" and k != "beat_real_s")
	keys.sort()
	var want: Array = plain.keys()
	want.sort()
	assert_eq(keys, want, "the same keys as an unhosted line, plus flow and beat_real_s")
	await wait_process_frames(30)
	assert_true(h.swaps >= 1, "the restart swapped a new attempt in")
	assert_false(is_instance_valid(g))
	assert_false(h.held, "M47.6a: again carries the play already given (no second gate)")
	h.skip_handoff()


func test_quit_before_the_door_quits_the_game_and_the_raw_keys_save() -> void:
	var h := await _hosted(S4)
	var g := h.game
	assert_eq(Main.quit_target(RunState.session), Main.QUIT_GAME)
	assert_eq(PauseMenu.quit_label(RunState.session), PauseMenu.QUIT_GAME)
	assert_eq(Main.quit_target(null), StartScreen.TITLE_SCENE, "the v6 loop: quit to start")
	assert_true(g.pause_menu.open())
	assert_true(g.pause_menu._raw_label.text.contains("[Q] quit game"))
	assert_eq(g.pause_menu._raw_status.text, "fullscreen off · volume 100% · less flashing off")
	for code: Key in [KEY_L, KEY_MINUS, KEY_MINUS]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = true
		assert_true(g.pause_menu.raw_option(e))
	assert_true(SaveGame.reduce_flashing(), "L: less flashing")
	assert_almost_eq(float(Settings.get_value("vol_master")), 0.8, 0.001, "- twice")
	assert_eq(g.pause_menu._raw_status.text, "fullscreen off · volume 80% · less flashing on")
	var f := InputEventKey.new()
	f.physical_keycode = KEY_F
	f.pressed = true
	assert_true(g.pause_menu.raw_option(f))
	assert_eq(int(Settings.get_value("window_mode")), 1, "F: fullscreen (stored)")
	g.pause_menu.close()
	assert_true(CampaignDB.jump_to(S8))
	assert_eq(Main.quit_target(CampaignDB.get_session(S8)), StartScreen.TITLE_SCENE, "from the door on: the title")
	_cleanup_5b()


func test_edit_event_and_skin_rows_are_player_facing_and_quiet_edits_silent() -> void:
	var h := await _hosted(S4)
	var g := h.game
	assert_true(g.rule_book.edit_landed.is_connected(g._on_edit_row))
	assert_true(g.event_player.event_started.is_connected(g._on_event_row))
	assert_true(g.session_runner.skin_cued.is_connected(g._on_skin_row))
	var walls := RuleDB.get_edit(&"edit_bouncy_walls")
	assert_true(g.rule_book.request(walls.id, &"cue", 2.0))
	for i in 200:
		if g.rule_book.is_live(walls.id):
			break
		await wait_physics_frames(1)
	assert_true(g.rule_book.is_live(walls.id))
	h.terminal.finish()
	assert_true(h.terminal.rows().has("$ %s ... ok" % walls.cmd_text), "the edit's own command")
	var n := h.terminal.row_count()
	g.rule_book.last_warned = false
	g._on_edit_row(walls)
	g.rule_book.last_warned = true
	g.rule_book.last_by = &"event"
	g._on_edit_row(walls)
	h.terminal.finish()
	assert_eq(h.terminal.row_count(), n, "a quiet edit and an event's edit print nothing")
	var plain := walls.duplicate() as RuleEdit
	plain.cmd_text = ""
	assert_eq(Main.edit_row_text(plain), "patch bouncy walls", "no cmd_text: the title")
	g._on_event_row(&"wrong_variable")
	g._on_skin_row(&"ui")
	g._on_skin_row(&"bug")
	h.terminal.finish()
	var rows := h.terminal.rows()
	assert_true(rows.has("$ set gravity_scale 0.9 ... ok"), "the slider the AI thinks it moves")
	assert_true(rows.has("$ skin reveal ui ... ok"))
	assert_false(rows.any(func(r: String) -> bool: return r.contains("bug")), "a bug cue prints nothing")
	for r: String in rows:
		assert_false(r.contains("edit_") or r.contains("wrong_variable"), "no raw id: %s" % r)


func test_the_terminal_takes_the_pixel_colours_at_the_ui_reveal() -> void:
	var was := Skins.current
	var t := _terminal()
	t.say_row("hello", &"happy")
	t.cmd("build v0.9.0", "ok")
	t.finish()
	assert_eq(t.palette_name, &"raw")
	Skins.use(Skins.pixel())
	Skins.reset_reveal(true)   # S9: manual reveal, nothing on yet
	t.dress()
	assert_eq(t.palette_name, &"raw", "before the ui reveal the terminal is raw")
	Skins.reveal(&"ui")
	assert_eq(t.palette_name, &"pixel", "the reveal recolours it at once")
	var cmd_row: Label = t._list.get_child(t._list.get_child_count() - 1)
	assert_eq(cmd_row.get_theme_color(&"font_color"), t.col(&"cmd"))
	assert_ne(t.col(&"bg"), Palette.TERM_BG)
	assert_eq((t.get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color, t.col(&"bg"), "the back too")
	assert_eq(t.font_size(), TerminalPanel.BASE_FONT, "colours only")
	Skins.use(was)
	t.dress()
	assert_eq(t.palette_name, &"raw")


# --- M47.5b review ---------------------------------------------------------------------------

func test_new_game_resets_once_per_process_not_on_every_return_to_the_title() -> void:
	SaveGame.go_inert()
	StartScreen.test_boot = true
	StartScreen.enter_hook = func(_path: String) -> void: pass
	StartScreen.new_game_pending = true   # as `-- --new-game` sets it
	SaveGame.set_campaign_position(3, S3)
	_start_screen()
	await wait_process_frames(1)
	assert_eq(int(SaveGame.campaign().index), 0, "the first boot starts over")
	assert_false(StartScreen.new_game_pending, "the flag is used up")
	# Progress made in this process, then a session quits / a replay ends back to the title.
	SaveGame.set_campaign_position(3, S3)
	_start_screen()
	await wait_process_frames(1)
	assert_eq(int(SaveGame.campaign().index), 3, "a second boot-scene screen keeps the progress")
	assert_eq(String(SaveGame.campaign().next), String(S3))
	_cleanup_5b()


func test_the_installer_is_for_a_first_run_only_not_a_save_with_progress() -> void:
	SaveGame.go_inert()
	SaveGame.set_setting("asked", false)
	assert_true(StartScreen.first_run_due(), "a fresh save, never asked")
	(SaveGame.campaign().done as Array).append(String(S0))
	assert_false(StartScreen.first_run_due(), "a campaign under way (asked lost or never stored): no prompt mid-campaign")
	var went: Array[String] = []
	StartScreen.test_boot = true
	StartScreen.enter_hook = func(path: String) -> void: went.append(path)
	_start_screen()
	await wait_process_frames(1)
	assert_eq(went.size(), 1)
	assert_false(GameHost.first_run_prompt)
	_cleanup_5b()


func test_the_installer_answer_points_at_the_raw_pause_keys_not_options() -> void:
	var line := GameHost.first_run_answer_line(false)
	assert_eq(line, "reduce flashing off ([Escape] then [L] to change)")
	assert_false(line.contains("Options"), "no Options screen before the front door")
	assert_eq(GameHost.first_run_answer_line(true), "reduce flashing on ([Escape] then [L] to change)")
	var h := await _hosted(S0)
	SaveGame.set_setting("asked", false)
	h.ask_first_run()
	h.answer_first_run(false)
	h.terminal.finish()
	assert_true(h.terminal.rows().has(GameHost.first_run_answer_line(false)))
	_cleanup_5b()


func _vol_key(physical: Key, keycode: Key, unicode: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = physical
	e.keycode = keycode
	e.unicode = unicode
	e.pressed = true
	return e


func test_the_raw_volume_keys_read_the_typed_character_on_azerty() -> void:
	# AZERTY: "-" is on the 6 key; the US "-" position types ")"; "=" / "+" share a key.
	assert_eq(PauseMenu.volume_step(_vol_key(KEY_6, KEY_MINUS, 45)), -1, "AZERTY's -")
	assert_eq(PauseMenu.volume_step(_vol_key(KEY_EQUAL, KEY_EQUAL, 61)), 1, "AZERTY's =")
	assert_eq(PauseMenu.volume_step(_vol_key(KEY_EQUAL, KEY_PLUS, 43)), 1, "+ (shifted)")
	assert_eq(PauseMenu.volume_step(_vol_key(KEY_MINUS, KEY_MINUS, 45)), -1, "US -")
	assert_eq(PauseMenu.volume_step(_vol_key(KEY_KP_ADD, KEY_KP_ADD, 43)), 1, "keypad +")
	assert_eq(PauseMenu.volume_step(_vol_key(KEY_6, KEY_6, 54)), 0, "US 6 is not a volume key")
	var h := await _hosted(S4)
	var g := h.game
	assert_true(g.pause_menu.open())
	assert_true(g.pause_menu.raw_option(_vol_key(KEY_6, KEY_MINUS, 45)))
	assert_almost_eq(float(Settings.get_value("vol_master")), 0.9, 0.001, "AZERTY - lowers the volume")
	assert_true(g.pause_menu.raw_option(_vol_key(KEY_EQUAL, KEY_EQUAL, 61)))
	assert_almost_eq(float(Settings.get_value("vol_master")), 1.0, 0.001)
	g.pause_menu.close()
	_cleanup_5b()


func test_q_in_a_live_hosted_session_before_the_door_quits_the_game_with_one_abandon_line() -> void:
	var h := await _hosted_live(S4)
	var g := h.game
	var went: Array[String] = []
	Main.leave_hook = func(path: String) -> void: went.append(path)
	assert_true(g.pause_menu.open())
	await wait_process_frames(1)
	_press_key(KEY_Q)
	await wait_process_frames(2)
	assert_eq(went, [Main.QUIT_GAME] as Array[String], "Q quits the app (not change_scene to 'quit')")
	assert_false(g.pause_menu.is_open())
	var lines := FileAccess.get_file_as_string(TEST_LOG).strip_edges().split("\n")
	assert_eq(lines.size(), 1, "one abandon line")
	var rec: Dictionary = JSON.parse_string(lines[0])
	assert_eq(rec.choice, "abandon")
	assert_eq(rec.flow, "always_on")
	assert_false(RunState.is_paused_for(GameHost.HANDOFF))
	_cleanup_5b()
