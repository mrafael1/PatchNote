extends GutTest
## M47.6a (PLAN v9.4 0.8, design 2.2-2.5): the play gate and the voice. The gate holds a live
## session before tick 0 until play (typed, or an armed Enter on the ghost); move keys strain
## the square and never type or release; while the chat has focus no key reaches the game;
## canned replies; the movement keys by layout; the bubble lint; `tried` cues; Esc at the gate.

const S0 := &"s1_00_nothing"
const S1 := &"s1_01_move"
const S2 := &"s1_02_enemies"
const S4 := &"s1_04_level"
const TEST_LOG := "user://m47_6a_test/t.jsonl"

var _live_host: GameHost
var _prev_scene: Node


## Records the keys that reach the game's viewport unhandled (where the debrief reads them).
class KeyProbe:
	extends Node
	var seen: Array[Key] = []
	func _unhandled_input(event: InputEvent) -> void:
		var k := event as InputEventKey
		if k != null and k.pressed:
			seen.append(k.physical_keycode)


func after_each() -> void:
	for code: Key in [KEY_W, KEY_Z, KEY_D, KEY_ENTER, KEY_SPACE, KEY_1]:
		_key_event(code, false)
	Input.action_release(&"move_up")
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
	GameHost.auto_play = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null


## A live host (the current scene) on session `id`, its gate up as a live start opens it.
func _gate(id: StringName) -> GameHost:
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
	assert_true(h.is_live())
	if g.stage_card != null:
		g.stage_card.skip()
	assert_true(h.gate_due(), "a live start gates")
	h.hold()
	await wait_process_frames(2)
	return h


## The gate's lines typed and its arming time passed.
func _armed(h: GameHost) -> void:
	h.terminal.finish()
	await wait_process_frames(2)
	h.terminal.chat_input.arm_at_msec -= 1000
	assert_true(h.terminal.chat_input.armed())


func _key_event(code: Key, down: bool, echo := false, unicode := 0) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	e.echo = echo
	e.unicode = unicode
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _tap(code: Key, unicode := 0) -> void:
	_key_event(code, true, false, unicode)
	_key_event(code, false)


func _type(text: String) -> void:
	for ch in text:
		_tap(OS.find_keycode_from_string(ch.to_upper()), ch.unicode_at(0))


# --- The gate --------------------------------------------------------------------------------

func test_the_gate_holds_at_tick_0_and_types_the_before_play_lines() -> void:
	var h := await _gate(S0)
	assert_true(h.held and h.gate)
	assert_true(RunState.is_paused_for(GameHost.HANDOFF))
	await wait_physics_frames(10)
	assert_eq(RunState.game_time, 0.0, "tick 0 until play")
	assert_eq(h.game.session_runner.said.size(), 0, "the intro waits for play")
	h.terminal.finish()
	var rows := h.terminal.rows()
	for l in GameHost.gate_lines(RunState.session):
		assert_true(rows.has("  " + l.text), "typed in the chat: %s" % l.text)
	assert_true(h.terminal.chat_input.has_focus(), "the input is focused at the gate")
	assert_eq(h.terminal.chat_input.placeholder_text, ChatInput.GHOST, "the ghost play")
	assert_false(h.game.mascot._bubble.visible, "no bubble before play")


func test_typed_play_releases_at_once_and_the_session_starts_at_tick_0() -> void:
	var h := await _gate(S4)
	_type("play")
	assert_eq(h.terminal.chat_input.text, "play")
	_tap(KEY_ENTER)
	assert_false(h.held, "play + Enter releases, even before the lines are typed")
	assert_true(h.terminal.rows().has("you> play"))
	assert_false(h.terminal.chat_input.has_focus(), "unfocused during play")
	assert_false(h.terminal.chat_input.editable)
	assert_eq(RunState.game_time, 0.0)
	await wait_physics_frames(3)
	assert_gt(RunState.game_time, 0.0, "the sim runs")


func test_the_empty_enter_needs_the_arm_and_a_fresh_press() -> void:
	var h := await _gate(S4)
	_tap(KEY_ENTER)
	assert_true(h.held, "Enter while the lines type: nothing")
	_key_event(KEY_ENTER, true)   # held through the arm
	await _armed(h)
	h.terminal.chat_input.arm()
	h.terminal.chat_input.arm_at_msec -= 1000
	_key_event(KEY_ENTER, true, true)   # its echo
	assert_true(h.held, "a held Enter through the arm never releases")
	_key_event(KEY_ENTER, false)
	_tap(KEY_ENTER)
	assert_false(h.held, "a fresh Enter on the ghost after the arm is play")
	assert_true(h.terminal.rows().has("you> play"))


func test_a_bare_p_counts_once_armed() -> void:
	var h := await _gate(S4)
	_type("p")
	_tap(KEY_ENTER)
	assert_true(h.held, "p before the arm: nothing")
	await _armed(h)
	assert_eq(h.terminal.chat_input.text, "p", "kept")
	_tap(KEY_ENTER)
	assert_false(h.held, "p after the arm is play")


func test_move_keys_never_type_or_release_and_other_text_gets_a_canned_reply() -> void:
	var h := await _gate(S4)
	await _armed(h)
	var input := h.terminal.chat_input
	for code: Key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT]:   # the move and dash positions
		_tap(code, OS.get_keycode_string(code).to_lower().unicode_at(0) if code != KEY_SHIFT else 0)
	assert_true(h.held, "move keys are not play")
	assert_eq(input.text, "", "a bound movement key never types at an empty prompt")
	assert_gt(input.pulses, 0, "the keys point at play: the ghost pulsed")
	input.text = ""
	_type("hello")
	_tap(KEY_ENTER)
	assert_true(h.held, "other text is not play")
	assert_eq(h.chat_typed, 1, "counted, never logged")
	h.terminal.finish()
	var rows := h.terminal.rows()
	assert_true(rows.has("you> hello"))
	var reply := Line.parse(CampaignDB.campaign.chat_reply("hello", h.terminal.is_chat()))
	assert_true(rows.has("  " + reply.text), "the canned reply (S4: the chat's, M47.6b)")
	assert_eq(CampaignDB.campaign.chat_reply("what now"), CampaignDB.campaign.chat_replies["*"])
	assert_eq(CampaignDB.campaign.chat_reply("help?"), CampaignDB.campaign.chat_replies["help|?"])


func test_play_typed_on_qwerty_works_once_text_is_in() -> void:
	var h := await _gate(S4)
	_type("p")
	_type("lay")   # l, a, y: "a" is a movement key on QWERTY, but text is already in
	assert_eq(h.terminal.chat_input.text, "play")
	_tap(KEY_ENTER)
	assert_false(h.held)


func test_while_the_chat_has_focus_no_key_reaches_the_game() -> void:
	var h := await _gate(S4)
	var probe := KeyProbe.new()
	h.game.add_child(probe)
	probe.process_mode = Node.PROCESS_MODE_ALWAYS
	assert_true(h.terminal.chat_input.has_focus())
	for code: Key in [KEY_SPACE, KEY_1, KEY_W]:
		_tap(code)
	await wait_process_frames(1)
	assert_eq(probe.seen, [] as Array[Key], "Space, 1 and W stay in the chat")
	h.terminal.chat_input.drop_focus()
	_tap(KEY_1)
	await wait_process_frames(1)
	assert_eq(probe.seen, [KEY_1] as Array[Key], "unfocused, keys flow to the game as before")
	h.skip_handoff()


func test_esc_at_the_gate_opens_the_pause_menu_and_takes_the_focus() -> void:
	var h := await _gate(S4)
	assert_true(h.game.pause_menu.can_open(), "allowed at the gate")
	_tap(KEY_ESCAPE)
	await wait_process_frames(2)
	assert_true(h.game.pause_menu.is_open(), "Esc reaches the menu through the chat's focus")
	assert_false(h.terminal.chat_input.has_focus(), "the menu's keys go to the menu")
	assert_true(h.held, "still at the gate")
	h.game.pause_menu.close()
	await wait_process_frames(2)
	assert_true(h.terminal.chat_input.has_focus(), "back at the gate")
	h.next_session()
	assert_false(h.gate, "the hot-reload closes the gate")
	RunState.set_pause(GameHost.HANDOFF, true)
	assert_false(h.game.pause_menu.can_open(), "no pause menu during the hot-reload")


func test_no_gate_under_autostart_or_in_bot_chains() -> void:
	var h := await _gate(S4)
	GameHost.auto_play = true
	assert_false(h.gate_due())
	GameHost.auto_play = false
	GameHost.auto_beats = false
	assert_false(h.gate_due())
	GameHost.auto_beats = true
	assert_true(h.gate_due())
	h.skip_handoff()


func test_the_idle_hint_from_s2_on() -> void:
	var h := await _gate(S2)
	await _armed(h)
	h._activity_usec -= int((GameHost.IDLE_HINT_S + 1.0) * 1000000.0)
	await wait_process_frames(2)
	h.terminal.finish()
	assert_true(h.terminal.rows().has(GameHost.IDLE_HINT))
	h.skip_handoff()


func test_a_session_without_before_play_types_the_default() -> void:
	var s := SessionDef.new()
	s.id = &"x"
	var lines := GameHost.gate_lines(s)
	assert_eq(lines.size(), CampaignDB.campaign.before_play_default.size())
	assert_eq(lines[0].text, Line.parse(CampaignDB.campaign.before_play_default[0]).text)
	for sd: SessionDef in CampaignDB.campaign.sessions:
		assert_false(sd.before_play.is_empty(), "%s has its own before_play" % sd.id)


# --- The square and the keys -----------------------------------------------------------------

func test_z_at_the_s0_gate_types_nothing_and_strains_the_visual_not_the_body() -> void:
	var h := await _gate(S0)
	var p := h.game.player
	var strain := p.get_node(^"StrainFX") as StrainFX
	assert_not_null(strain)
	var body := p.global_position
	var visual := p.get_node(^"Visual") as Node2D
	_key_event(KEY_W, true, false, "w".unicode_at(0))   # move_up by position (Z on AZERTY)
	await wait_process_frames(20)
	assert_eq(h.terminal.chat_input.text, "", "it types nothing")
	assert_lt(strain.offset().y, -1.0, "the square leans up")
	assert_gt(visual.scale.y, 1.0, "stretched along the push")
	assert_eq(p.global_position, body, "the body never moves")
	assert_eq(RunState.game_time, 0.0, "nor does the sim")
	assert_true(h.held)
	_key_event(KEY_W, false)
	await wait_process_frames(40)
	assert_lt(strain.offset().length(), 0.1, "it springs back")
	h.skip_handoff()


func test_the_strain_is_off_once_the_build_can_move() -> void:
	var h := await _gate(S1)
	var p := h.game.player
	var strain := p.get_node(^"StrainFX") as StrainFX
	_key_event(KEY_W, true)
	await wait_process_frames(10)
	assert_eq(strain.offset(), Vector2.ZERO, "S1 can move: no strain")
	_key_event(KEY_W, false)
	h.skip_handoff()


func test_the_move_keys_show_by_layout_and_light_with_the_input() -> void:
	assert_eq(MoveKeys.show_seconds(CampaignDB.get_session(S0)), -1.0, "S0: while it cannot move")
	assert_eq(MoveKeys.show_seconds(CampaignDB.get_session(S1)), MoveKeys.SHOW_S, "S1: the first seconds")
	assert_eq(MoveKeys.show_seconds(CampaignDB.get_session(S2)), 0.0, "then never")
	var keys := MoveKeys.new()
	add_child_autofree(keys)
	keys.to_label = func(_k: Key) -> Key: return KEY_NONE
	assert_eq(keys.labels(), ["W", "A", "S", "D"] as Array[String], "QWERTY positions")
	var azerty := {KEY_W: KEY_Z, KEY_A: KEY_Q, KEY_S: KEY_S, KEY_D: KEY_D}
	keys.to_label = func(k: Key) -> Key: return azerty.get(k, k)
	assert_eq(keys.labels(), ["Z", "Q", "S", "D"] as Array[String], "AZERTY: Z Q S D")
	Input.action_press(&"move_up")
	await wait_process_frames(2)
	assert_eq(keys.lit, [true, false, false, false] as Array[bool])
	Input.action_release(&"move_up")
	await wait_process_frames(2)
	assert_eq(keys.lit, [false, false, false, false] as Array[bool])


func test_the_move_keys_are_in_s0s_hud_and_fade_after_s1s_first_seconds() -> void:
	var h := await _gate(S1)
	var keys := h.game.hud.get_node(^"MoveKeys") as MoveKeys
	assert_true(keys.visible)
	h.skip_handoff()
	SaveGame.set_setting("reduce_flashing", true)
	RunState.game_time = MoveKeys.SHOW_S + 0.1
	await wait_process_frames(2)
	assert_false(keys.visible, "gone after the first seconds (reduce flashing: a plain hide)")


# --- The voice ---------------------------------------------------------------------------------

func test_a_tried_cue_counts_direction_presses_while_locked() -> void:
	var c := Cue.parse("tried 2: say surprised: oh.")
	assert_eq(c.problem, "")
	assert_false(c.due({"tried": 1}))
	assert_true(c.due({"tried": 2}))
	var s := SessionDef.new()
	s.id = &"t"
	s.basics = [&"movement"] as Array[StringName]
	s.cues = PackedStringArray(["tried 1: say happy: x."])
	assert_true(s.problems().any(func(p: String) -> bool: return p.contains("tried needs")))
	var h := await _gate(S0)
	h.skip_handoff()
	var runner := h.game.session_runner
	var bot := BotInput.new()
	h.game.player.set_input(bot)
	await wait_physics_frames(2)
	var before := runner.tried
	h.game.player.input.set_physics_process(false)
	h.game.player.input.move = Vector2.UP
	await wait_physics_frames(3)
	h.game.player.input.move = Vector2.ZERO
	await wait_physics_frames(2)
	h.game.player.input.move = Vector2.LEFT
	await wait_physics_frames(2)
	assert_eq(runner.tried - before, 2, "two presses, each counted once")


func test_the_bubble_lint_flags_a_three_row_line() -> void:
	var s := SessionDef.new()
	s.id = &"lint"
	s.intro = PackedStringArray(["happy: Short."])
	assert_false(s.problems().any(func(p: String) -> bool: return p.contains("bubble rows")))
	var s2 := SessionDef.new()
	s2.id = &"lint2"
	s2.cues = PackedStringArray(["at 1: say happy: This line is far too long for the little bubble: it goes on and on and on, and then it says more."])
	assert_true(s2.problems().any(func(p: String) -> bool: return p.contains("bubble rows")))
	assert_eq(Mascot.bubble_rows("Hi."), 1)
	var long := "word ".repeat(60)
	assert_lte(Mascot.bubble_rows(Mascot.clamp_text(long)), 2, "the runtime clamp")
	assert_true(Mascot.clamp_text(long).ends_with("..."))
	assert_eq(CampaignDB.problems(), [] as Array[String], "every authored line fits")


func test_the_s0_voice_is_lowercase_and_talks_from_the_start() -> void:
	var s := CampaignDB.get_session(S0)
	assert_false(s.before_play.is_empty())
	for l in s.before_play_lines() + s.intro_lines():
		assert_eq(l.text, l.text.to_lower(), "lowercase before the chat upgrade")
		assert_false(l.text.contains("<-"), "the mute phase is gone")
	var s3 := CampaignDB.get_session(&"s1_03_shooting")
	assert_false(s3.debrief.has("happy: I can talk now. Weird."), "cut")


# --- Review fixes (M47.6a) ---------------------------------------------------------------------

func test_again_typed_on_qwerty_gets_the_again_reply() -> void:
	var h := await _gate(S4)
	_type("again")   # the `a` is move_left by position on QWERTY: swallowed at the empty prompt
	assert_eq(h.terminal.chat_input.text, "gain", "the swallowed letter never types")
	_tap(KEY_ENTER)
	h.terminal.finish()
	var rows := h.terminal.rows()
	assert_true(rows.has("you> again"), "said as typed")
	var reply := Line.parse(CampaignDB.campaign.chat_reply("again", h.terminal.is_chat()))
	assert_true(rows.has("  " + reply.text), "the again reply, not the fallback")
	assert_true(h.held)
	h.skip_handoff()


func test_one_you_prompt_while_an_ask_waits() -> void:
	var t := TerminalPanel.new()
	add_child_autofree(t)
	await wait_process_frames(1)
	assert_true(t.input_row_shown(), "no ask: the input row shows")
	t.ask(["again", "move on"] as Array[String])
	t.finish()
	await wait_process_frames(1)
	assert_false(t.input_row_shown(), "the ask's own you> row is the only prompt")
	assert_eq(t._input_row.modulate.a, 0.0, "hidden, its space kept")
	t.answer("1")
	assert_true(t.input_row_shown())
	assert_eq(t._input_row.modulate.a, 1.0)


func test_restart_from_the_gate_gates_again_and_counts_no_attempt() -> void:
	var h := await _gate(S4)
	var tries := CampaignDB.attempt(S4)
	assert_true(h.held and h.gate)
	h.game.menu_restart()
	await wait_process_frames(40)   # the glitch's real-time timer (the tree is paused)
	assert_true(h.held, "no play was given: the new attempt holds")
	assert_true(h.gate, "and its gate is up")
	assert_eq(RunState.game_time, 0.0)
	assert_eq(CampaignDB.attempt(S4), tries, "a restart before play is not an attempt")
	var log_text := FileAccess.get_file_as_string(TEST_LOG) if FileAccess.file_exists(TEST_LOG) else ""
	assert_false(log_text.contains("menu_retry"), "no telemetry for an attempt never played")
	# A play given does carry over.
	h.give_play()
	await wait_process_frames(2)
	assert_false(h.held)
	h.next_session("restart s1_04_level (try 2)")
	await wait_process_frames(40)   # the glitch's real-time timer (the tree is paused)
	assert_false(h.held, "a retry after play carries the play")
