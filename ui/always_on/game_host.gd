class_name GameHost
extends Control
## M47.5a (PLAN v9.3, 0.7): the always-on window. The running game sits in a SubViewport
## whose 2D rect is always 1280x720 (size_2d_override, stretched to the game column), and
## the raw dev terminal (TerminalPanel) is docked to its right. Not "Shell": Main's own docs
## call Main the shell.
##
## Each session is still one fresh main.tscn instance (its _ready resets the run), set to
## PROCESS_MODE_PAUSABLE before it enters the tree, so every RunState.set_pause reason
## freezes it exactly as at root. The host, the container, the viewport and the terminal run
## ALWAYS (paused nodes get no input: the container must keep forwarding keys to the pause
## menu and the debrief). Between sessions next_session() prints the hot-reload, glitches
## the game column for GLITCH_S and swaps the instance on a later frame; the new session
## then holds `&"handoff"` until the player's first move or shot (the ready moment).
##
## M47.6a (PLAN v9.4, 0.8 / 2.5): the ready moment is the play gate. Every live session
## start holds (the first one after a boot or Continue too): the chat types the session's
## before_play lines, then its input waits for `play` (or an armed Enter on the ghost).
## A move or a shot no longer releases it: the keys strain the square instead. A retry
## (again, the pause menu's restart) carries the play already given. --autostart and bot
## chains never gate (auto_play / auto_beats); tool hosts gate only their swaps (run_hash
## calls skip_handoff on frame 1).
##
## Layout, in window pixels while live (the root's content scale off): game scale
## k = min(H / 720, (W - 360) / 1280), the game column 1280k x 720k centred vertically on
## black, the terminal the rest of the width at full height. The windowed base is 1760x720
## (Settings.set_window_base); leaving restores the root and the 1280x720 base.

const SCENE := "res://ui/always_on/game_host.tscn"
const GAME_SCENE := "res://main.tscn"
const GAME_SIZE := Vector2(1280, 720)
const TERMINAL_MIN := 360.0
const BASE := Vector2i(1760, 720)
const PROJECT_BASE := Vector2i(1280, 720)
const GLITCH_S := 0.25
const HANDOFF := &"handoff"
## M47.6a: nothing typed at a gate for this long (from S2 on): a dim "(type play)" row.
const IDLE_HINT_S := 10.0
const IDLE_HINT := "(type play)"
const IDLE_HINT_FROM := 2
const GLITCH_SHADER := preload("res://systems/glitch.gdshader")

## False in bot runs (tools/bot_runs.gd): the debrief never chooses by itself there.
static var auto_beats := true
## M47.5b (PLAN v9.3, 2.7): StartScreen's boot sets it when the first-launch question was never
## asked (and no --autostart): the next host asks it in the terminal before S0's first frame.
static var first_run_prompt := false
## M47.6a (PLAN v9.4 2.5): the play gate releases at once (--autostart, the export's smoke).
static var auto_play := false
const FIRST_RUN_LINE := "patchnotes first run: reduce flashing and screen shake?"
const FIRST_RUN_OPTIONS: Array[String] = ["no", "yes"]

var game: Main
var view: GameView
var viewport: SubViewport
var terminal: TerminalPanel
var tools := false            ## host_for_tools(): never live, no window change
var held := false             ## the handoff is held (the ready moment)
var swaps := 0                ## sessions swapped in (tests)
var layout := {}              ## the last layout_for() result
var _pending: Main            ## host_for_tools' game, attached in _ready
var _back: ColorRect
var _glitch: ColorRect
var _fade: ColorRect
var _window_set := false
var _prev_mode := Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
var _prev_aspect := Window.CONTENT_SCALE_ASPECT_EXPAND
var _prev_size := PROJECT_BASE
var _reload_row := ""         ## the hot-reload / restart command waiting for its "ok"
var _swap_queued := false
var _view_size_override := Vector2i.ZERO
## M47.5b: a stage card is open (chapter mode: the terminal hides, the game fills the window).
var chapter := false
## M47.6a: the play gate is up (held, the chat's input waits for play).
var gate := false
var chat_typed := 0             ## lines typed at gates that were not play (a count, never the text)
var play_wait_s := 0.0          ## real seconds from the last gate's prompt to play
var _carry_play := false        ## a retry: the play already given carries over
var _arming := false            ## the gate's lines still type; the input arms after them
var _gate_usec := 0
var _activity_usec := 0
var _hint_shown := false
var asking_first_run := false   ## the installer's question waits for 1 / 2
var _chapter_rows := false      ## the session's rows wait (for the card to close, or the installer's answer)


## The layout for a window of `window` pixels: {k, game: Rect2, terminal: Rect2, font: int}.
## M47.5b, chapter mode: the game alone, 16:9, centred (k from the whole window), no terminal.
static func layout_for(window: Vector2, p_chapter := false) -> Dictionary:
	if p_chapter:
		var kc := maxf(0.05, minf(window.y / GAME_SIZE.y, window.x / GAME_SIZE.x))
		var gc := (GAME_SIZE * kc).round()
		return {"k": kc, "game": Rect2(((window - gc) * 0.5).round(), gc), "terminal": Rect2(Vector2(window.x, 0), Vector2.ZERO),
				"font": roundi(TerminalPanel.BASE_FONT * clampf(kc, 1.0, 2.0))}
	var k := maxf(0.05, minf(window.y / GAME_SIZE.y, (window.x - TERMINAL_MIN) / GAME_SIZE.x))
	var gs := (GAME_SIZE * k).round()
	var game_rect := Rect2(Vector2(0, roundf((window.y - gs.y) * 0.5)), gs)
	var term := Rect2(Vector2(gs.x, 0), Vector2(maxf(0.0, window.x - gs.x), window.y))
	return {"k": k, "game": game_rect, "terminal": term, "font": roundi(TerminalPanel.BASE_FONT * clampf(k, 1.0, 2.0))}


## A host for tools and tests around `p_game` (run_hash --shell): never live, no window
## change, no typing waits. The caller adds it to the tree; the game enters with it.
static func host_for_tools(p_game: Main, view_size := Vector2i.ZERO) -> GameHost:
	var h := GameHost.new()
	h.name = "GameHost"
	h.tools = true
	h._pending = p_game
	h._view_size_override = view_size
	return h


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back = ColorRect.new()
	_back.name = "Back"
	_back.color = Palette.CURTAIN
	_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back)
	view = GameView.new()
	view.name = "GameView"
	view.stretch = false
	view.process_mode = Node.PROCESS_MODE_ALWAYS
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(view)
	viewport = SubViewport.new()
	viewport.name = "GameViewport"
	viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	viewport.handle_input_locally = true
	viewport.size_2d_override = Vector2i(GAME_SIZE)
	viewport.size_2d_override_stretch = true
	viewport.size = Vector2i(GAME_SIZE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.add_child(viewport)
	_glitch = ColorRect.new()
	_glitch.name = "Glitch"
	_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = GLITCH_SHADER
	_glitch.material = mat
	_glitch.visible = false
	add_child(_glitch)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(Palette.CURTAIN, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	add_child(_fade)
	terminal = TerminalPanel.new()
	terminal.name = "Terminal"
	add_child(terminal)
	view.chat = terminal.chat_input
	terminal.chat_input.play_given.connect(give_play)
	terminal.chat_input.typed.connect(_on_typed)
	terminal.chat_input.move_pressed.connect(_on_activity)
	terminal.chat_input.pause_pressed.connect(_on_chat_pause)
	if "--autostart" in OS.get_cmdline_user_args():
		auto_play = true
	if is_live():
		_set_window(true)
	get_viewport().size_changed.connect(relayout.bind(Vector2.ZERO))
	relayout()
	if _pending != null:
		var g := _pending
		_pending = null
		_attach(g)
	elif not tools:
		if first_run_prompt:   # the installer first: the session's rows wait for the answer
			first_run_prompt = false
			asking_first_run = true
		_attach(load(GAME_SCENE).instantiate() as Main)
	if asking_first_run:
		ask_first_run()
	if gate_due():   # M47.6a: the first session of a boot waits for play too
		hold()


func _exit_tree() -> void:
	if _window_set:
		_set_window(false)
	if held or RunState.is_paused_for(HANDOFF):   # M47.5a review: never leak to the next scene
		held = false
		RunState.set_pause(HANDOFF, false)


## True when this host is the scene being played (not a tool's or a test's copy).
func is_live() -> bool:
	return not tools and is_inside_tree() and get_tree().current_scene == self


## The debrief takes its own way on (Next after the patch) only in a live, non-bot host.
func auto_way_on() -> bool:
	return is_live() and auto_beats


## M47.6a: a live start gates (not under --autostart, not in a bot chain).
func gate_due() -> bool:
	return is_live() and auto_beats and not auto_play


# --- Window and layout ---------------------------------------------------------------------

func _set_window(on: bool) -> void:
	var root := get_tree().root
	if on:
		_prev_mode = root.content_scale_mode
		_prev_aspect = root.content_scale_aspect
		_prev_size = root.content_scale_size
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		Settings.set_window_base(BASE)
		_window_set = true
	else:
		root.content_scale_mode = _prev_mode
		root.content_scale_aspect = _prev_aspect
		root.content_scale_size = _prev_size
		Settings.set_window_base(PROJECT_BASE)
		_window_set = false
	Settings.apply()


## Lays the game column and the terminal out for the current window (tests: `window`).
func relayout(window := Vector2.ZERO) -> void:
	if not is_inside_tree():
		return
	if window == Vector2.ZERO:
		window = get_viewport().get_visible_rect().size
	layout = layout_for(window, chapter)
	var g: Rect2 = layout.game
	# The viewport first: with stretch off, the container's minimum size is the viewport's, so
	# shrinking the window (1080p back to the base) would keep the old, larger column.
	viewport.size = Vector2i(g.size) if _view_size_override == Vector2i.ZERO else _view_size_override
	view.position = g.position
	view.size = g.size
	for r: Control in [_glitch, _fade]:
		r.position = g.position
		r.size = g.size
	var t: Rect2 = layout.terminal
	terminal.position = t.position
	terminal.size = t.size
	terminal.visible = t.size.x >= 1.0 and not chapter
	if terminal.font_size() != int(layout.font):
		terminal.set_font_size(int(layout.font))


## The game column's rect in this host's coordinates.
func game_rect() -> Rect2:
	return Rect2(view.position, view.size)


# --- Sessions ------------------------------------------------------------------------------

func _attach(g: Main) -> void:
	g.host = self
	g.process_mode = Node.PROCESS_MODE_PAUSABLE   # before add_child: never inherit ALWAYS
	viewport.add_child(g)
	game = g
	terminal.dress()   # M47.5b: the look's ui group (S9's reveal on) recolours the terminal
	if g.stage_card != null and g.stage_card.is_open():
		_enter_chapter(g.stage_card)
		return
	if asking_first_run:
		_chapter_rows = true
		return
	_session_rows()


# --- Chapters (M47.5b, PLAN v9.3 2.6): the only full-screen pauses ----------------------------

## A new stage's card is up: the terminal hides and the game fills the window, centred on
## black; the card itself is unchanged (door -> cook beat -> card). The hot-reload's "ok"
## prints now, the session's rows once the card closes.
func _enter_chapter(card: StageCard) -> void:
	chapter = true
	_chapter_rows = true
	if _reload_row != "":
		terminal.close_cmd("ok")
		_reload_row = ""
	card.closed.connect(_exit_chapter.bind(card), CONNECT_ONE_SHOT)
	relayout()


func _exit_chapter(_card: StageCard) -> void:
	if not chapter:
		return
	chapter = false
	relayout()
	var s := RunState.session
	if s != null:
		terminal.sys("--- chapter %d · %s ---" % [s.stage, CampaignDB.campaign.stage_titles[s.stage]])
	if _chapter_rows:
		_chapter_rows = false
		_session_rows()
	if held:
		_open_gate()


## The terminal's rows for a session that just started: the speaker, the version, then
## "--- session 4 · Level · v0.4.0 ---" and "$ run <id>".
func _session_rows() -> void:
	var s := RunState.session
	terminal.session_index = CampaignDB.current_index() if s != null else 0
	terminal.set_version(SaveGame.version().label())
	if s == null:
		return
	var body := DebriefScreen.body_for(s)
	terminal.set_speaker(speaker_for(body), s.face)
	if _reload_row != "":
		terminal.close_cmd("ok")
		_reload_row = ""
	terminal.sys("--- session %d · %s · %s ---" % [CampaignDB.index_of(s.id), s.title, SaveGame.version().label()])
	terminal.cmd("run %s" % s.id)


## The prompt's name for a body: "ai" for the caret, else the body's short name, lower case.
static func speaker_for(body_id: StringName) -> String:
	if body_id == MascotBody.CARET:
		return "ai"
	return DebriefScreen.speaker_name(body_id).to_lower()


## Main._reload: the next session (or the same one again: `restart` names it). Live, the
## game column glitches GLITCH_S first; the swap always happens on a later frame, so a
## caller still reading the old game this frame sees it whole.
func next_session(restart := "") -> void:
	if _swap_queued:
		return
	_swap_queued = true
	# M47.6a: again / restart: the play already given carries over. Review: only a play that
	# was given (released); a restart from the gate (still held) gates again.
	_carry_play = restart != "" and not held
	_close_gate()
	_reload_row = restart if restart != "" else "hot-reload game"
	terminal.cmd_open(_reload_row)
	if is_live() and auto_beats:
		_pulse()
		get_tree().create_timer(GLITCH_S, true, false, true).timeout.connect(_swap)
	else:
		_swap.call_deferred()


func _pulse() -> void:
	var gentle := SaveGame.reduce_flashing()
	var tw := create_tween().set_ignore_time_scale(true)
	if gentle:   # reduce flashing: a short crossfade, no glitch
		_fade.visible = true
		_fade.color.a = 0.0
		tw.tween_property(_fade, ^"color:a", 0.75, GLITCH_S * 0.5)
		tw.tween_property(_fade, ^"color:a", 0.0, GLITCH_S * 0.5)
		tw.tween_callback(func() -> void: _fade.visible = false)
		return
	var mat := _glitch.material as ShaderMaterial
	_glitch.visible = true
	mat.set_shader_parameter(&"seed", float(swaps % 7))
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter(&"strength", v), 1.0, 0.0, GLITCH_S)
	tw.tween_callback(func() -> void: _glitch.visible = false)


## The swap: the old instance leaves the tree and is freed (as the old reload did, before the
## new one's _ready, so nothing of it hears the new run's signals), a new one enters, and the
## handoff holds it until the ready moment.
func _swap() -> void:
	_swap_queued = false
	if not is_inside_tree():
		return
	var old := game
	game = null
	if old != null and is_instance_valid(old):
		if old.get_parent() == viewport:
			viewport.remove_child(old)
		old.free()
	swaps += 1
	_attach(load(GAME_SCENE).instantiate() as Main)
	# The ready moment is the live player's. A bot chain (auto_beats off) keeps the old
	# reload's timing exactly: the new session runs from the next physics frame, as a
	# reloaded scene did, so its [botrun] lines stay byte-identical. M47.6a: so does a retry
	# (the play carries over: held for its _ready, released on its first frame, tick 0).
	var carry := _carry_play
	_carry_play = false
	if auto_beats and not carry and not (auto_play and is_live()):
		hold()


## Holds the new session before its first tick until play (tools call skip_handoff on
## frame 1). The gate opens now, or after the stage card / the installer's answer.
func hold() -> void:
	held = true
	RunState.set_pause(HANDOFF, true)
	if not chapter and not asking_first_run:   # a chapter's gate comes after its card
		_open_gate()


func skip_handoff() -> void:
	if asking_first_run:
		answer_first_run(false)
	if held:
		_release()


## M47.6a: play (the chat's input, a quick reply, tests). Only while a gate holds.
func give_play() -> void:
	if held and not asking_first_run:
		_release()


func _release() -> void:
	held = false
	if gate:
		play_wait_s = snappedf((Time.get_ticks_usec() - _gate_usec) / 1000000.0, 0.01)
	_close_gate()
	RunState.set_pause(HANDOFF, false)
	terminal.you_said("play")


# --- The play gate (M47.6a, PLAN v9.4 2.5) ----------------------------------------------------

## The chat types the session's before_play (or the campaign's default), then its input
## takes focus; the empty Enter arms once the lines are typed.
func _open_gate() -> void:
	if gate:
		return
	gate = true
	_arming = true
	_hint_shown = false
	_gate_usec = Time.get_ticks_usec()
	_activity_usec = _gate_usec
	for line in gate_lines(RunState.session):
		terminal.type_line(line)
	terminal.chat_input.open_gate()


func _close_gate() -> void:
	gate = false
	_arming = false
	terminal.chat_input.close_gate()


## The lines a gate types for session `s`: its before_play (conditions passing), else the
## campaign's before_play_default; {key:...} named for this keyboard.
static func gate_lines(s: SessionDef) -> Array[Line]:
	var out: Array[Line] = []
	var lines: Array[Line] = []
	if s != null:
		lines = Line.passing(s.before_play_lines(), CampaignDB.line_context(s))
	if lines.is_empty() and CampaignDB.campaign != null:
		lines = Line.parse_all(CampaignDB.campaign.before_play_default)
	for l in lines:
		out.append(SessionRunner.with_keys(l))
	return out


## Anything typed at a gate that is not play: the row, then a canned reply (counted, never logged).
func _on_typed(text: String) -> void:
	_on_activity()
	if not gate:
		return
	chat_typed += 1
	var reply := CampaignDB.campaign.chat_reply(text) if CampaignDB.campaign != null else ""
	# Review: a word that starts on a movement key lost that letter at the empty prompt
	# ("again" -> "gain" on QWERTY). If the text alone gets the fallback, try it with the letter.
	var lead := terminal.chat_input.typed_lead
	if lead != "" and CampaignDB.campaign != null and reply == CampaignDB.campaign.chat_replies.get("*", ""):
		var with_lead := CampaignDB.campaign.chat_reply(lead + text)
		if with_lead != reply:
			reply = with_lead
			text = lead + text
	terminal.you_said(text)
	if reply != "":
		terminal.type_line(Line.parse(reply))


## Esc in the focused chat at a gate: the game's pause menu (PauseMenu.allowed says when).
func _on_chat_pause() -> void:
	if game != null and is_instance_valid(game) and game.pause_menu != null and game.pause_menu.can_open():
		terminal.chat_input.drop_focus()
		game.pause_menu.open()


func _on_activity() -> void:
	_activity_usec = Time.get_ticks_usec()


## The gate's input wants focus unless the pause menu is up (its keys go to the game).
func _gate_step() -> void:
	var input := terminal.chat_input
	if _arming and not terminal.is_busy():
		_arming = false
		input.arm()
	var menu_up := game != null and is_instance_valid(game) and game.pause_menu != null and game.pause_menu.is_open()
	if menu_up:
		input.drop_focus()
	elif not input.has_focus() and terminal.visible:
		input.take_focus()
	if input.text != "":
		_activity_usec = Time.get_ticks_usec()
	var s := RunState.session
	if not _hint_shown and not _arming and s != null and CampaignDB.index_of(s.id) >= IDLE_HINT_FROM \
			and (Time.get_ticks_usec() - _activity_usec) / 1000000.0 >= IDLE_HINT_S:
		_hint_shown = true
		terminal.sys(IDLE_HINT)


# --- The installer's first-run question (M47.5b, PLAN v9.3 2.7, D13) -------------------------

## Before S0's first frame, under the handoff: the installer (not the AI) asks once. The host
## reads 1 / 2 (no debrief is open); a click on a choice row answers too.
func ask_first_run() -> void:
	asking_first_run = true
	RunState.set_pause(HANDOFF, true)
	terminal.sys(FIRST_RUN_LINE)
	terminal.ask(FIRST_RUN_OPTIONS)
	if not terminal.chosen.is_connected(_on_first_run_row):
		terminal.chosen.connect(_on_first_run_row)


func _on_first_run_row(index: int) -> void:
	if asking_first_run:
		answer_first_run(index == 1)


## "reduce flashing off ([Esc] then [L] to change)": M47.5b review, the raw pause's own keys
## (by layout), since no Options screen exists before the front door.
static func first_run_answer_line(reduce: bool, to_label := Callable()) -> String:
	return "reduce flashing %s ([%s] then [%s] to change)" % ["on" if reduce else "off",
			InputSetup.expand_keys("{key:pause}", to_label), PauseMenu._key_name(KEY_L, to_label)]


## The answer goes to the save (reduce_flashing, asked), then S0 starts.
func answer_first_run(reduce: bool) -> void:
	if not asking_first_run:
		return
	asking_first_run = false
	SaveGame.set_setting("reduce_flashing", reduce)
	SaveGame.set_setting("asked", true)
	terminal.answer("2" if reduce else "1")
	terminal.sys(first_run_answer_line(reduce))
	if terminal.chosen.is_connected(_on_first_run_row):
		terminal.chosen.disconnect(_on_first_run_row)
	if _chapter_rows and not chapter:
		_chapter_rows = false
		_session_rows()
	if not held:
		RunState.set_pause(HANDOFF, false)
	elif not chapter:
		_open_gate()   # M47.6a: the AI's first lines, then the input


func _process(_delta: float) -> void:
	if asking_first_run:
		if Input.is_action_just_pressed(&"choose_1"):
			answer_first_run(false)
		elif Input.is_action_just_pressed(&"choose_2"):
			answer_first_run(true)
		return
	if gate:
		_gate_step()


## The mouse over the terminal still aims: motion outside the game column reaches the game
## clamped to its edge (the shooter's aim does not freeze).
func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion == null or game == null:
		return
	var r := game_rect()
	if r.has_point(motion.position):
		return
	var e := motion.duplicate() as InputEventMouseMotion
	e.position = (motion.position - r.position).clamp(Vector2.ZERO, r.size - Vector2.ONE)
	e.global_position = e.position
	viewport.push_input(e)
