class_name Main
extends Node2D
## The game scene: the shell (PLAN v5 1.1). It keeps what every genre shares (the run
## reset, feedback, sound, transitions, the Director, the player-facing UI, telemetry)
## and hands the run itself to the genre: arena, world, player, camera, spawner and
## pacing all live in the Genre node it builds. It never branches on a genre id.

const BUILD := "M51b"
## M47.5b: menu_quit's target before the front door: the app itself (no start screen to go to).
const QUIT_GAME := "quit"

## Survive scene reloads: F5 restarts the same seed, "New build" keeps the genre.
static var next_seed := -1
static var next_genre: StringName = &""
## M47.6c2 (PLAN v9.4 0.8, design 2.7): no reload between Stage 1 sessions. The next session
## starts where the player stood (GameHost.capture_start, snapped to 0.01 px) instead of at
## the arena's player_start; NO_START = a cold start. Consumed and reset in _ready as
## next_seed is, and cleared by a retry, Restart / F5, the title and a --session jump.
const NO_START := Vector2.INF
static var next_start := NO_START
## Where the view stood from the player at the capture (lookahead, smoothing and the arena's
## limits included; presentation only), carried with next_start so the room does not move.
static var next_lead := Vector2.ZERO
## Tests: called with the scene path instead of changing scene (M47.5a review).
static var leave_hook := Callable()

var genre: Genre
var feedback: Feedback
var hud: Hud
var transition: Transition
var director: AiDirector
var prompt_panel: PromptPanel
var patch_history: PatchHistory
var report: ReportScreen
var dev_flow: DevSessionFlow   ## report -> dev session -> patch notes (PLAN v5 4)
var session_runner: SessionRunner   ## a campaign session's script (PLAN v8); null in the run loop
var mascot: Mascot                  ## the AI in the corner (PLAN v8 1.3); null in the run loop
var reactions: Reactions            ## the AI's live reactions (PLAN v8 1.7); null in the run loop
var rule_book: RuleBook   ## the AI's rule edits (PLAN v8 1.4); null in the run loop
var event_player: EventPlayer   ## scripted events (PLAN v8 1.5); null in the run loop
var debug: DebugOverlay        ## F1-F9 tools (tests reach F2 through it)
var debrief: DebriefScreen          ## after a campaign session (PLAN v8 1.2)
var stage_card: StageCard   ## before a new stage's first session (PLAN v9 2); null otherwise
## The live path and its pick panel (PLAN v9 1.5, M45a): only in a session with a path or a
## tryout, or once F2's PATH asks (ensure_path_runner). Null in Stage 1 and the v6 loop.
var path_runner: PathRunner
var pick_panel: PickPanel
var sound: Sound
var pause_menu: PauseMenu   ## M47.3 (PLAN 1.16): Esc / Start, when PauseMenu.allowed()
## M47.3: tests set it to log the menu's telemetry line from a game that is not the scene.
var menu_telemetry_always := false
## M47.5a (PLAN v9.3, 0.7): the always-on host this session plays in (set before add_child),
## or null (a direct load, a test, a tool). Its terminal carries the AI's voice.
var host: GameHost

## Read-only forwarders to the genre's nodes, so tests and tools keep working. They
## name shared systems, never a genre; a genre without one of them leaves it null.
var arena: Arena:
	get: return genre.get(&"arena") as Arena if genre else null
var world: Node2D:
	get: return genre.world if genre else null
var player: CharacterBody2D:
	get: return genre.player as CharacterBody2D if genre else null
var camera: CameraRig:
	get: return genre.camera as CameraRig if genre else null
var spawner: Spawner:
	get: return genre.get(&"spawner") as Spawner if genre else null
var turn_clock: TurnClock:
	get: return genre.get(&"turn_clock") as TurnClock if genre else null
var run_loop: RunLoop:
	get: return genre.get(&"run_loop") as RunLoop if genre else null

var _notes_saved := false
var _next_run_seed := -1   ## the seed "Play" starts after a dev session


func _ready() -> void:
	var run_seed := next_seed if next_seed >= 0 else int(randi() % 1000000)
	next_seed = -1
	RunState.reset(run_seed, next_genre)
	next_genre = &""
	var carried := next_start   # M47.6c2: consumed here, whatever this run is
	var carried_lead := next_lead
	clear_start()
	# PLAN v8 1.2: the campaign's session, when the campaign is active (else the v6 loop).
	RunState.session = CampaignDB.session_for_game()
	# PLAN v9 1.2: reset() recomputed with no session; a session's HP floor is base rules.
	# Only then, so Stage 1 (no floor) sees no extra rules_changed.
	if RunState.session != null and RunState.session.hp_floor > 0:
		RunState.recompute()
	print(boot_line())
	Look.use(Unlocks.look())   # the save's look (PLAN v5 1.7); punchy while inert
	Skins.read_args(OS.get_cmdline_user_args())   # `-- --look=pixel`: the Pixel preview (PLAN 1.7)
	Skins.apply_session(RunState.session)   # M48b: the session's skin (S9: revealed by cues)

	var def := GenreDB.get_genre(RunState.genre)
	genre = def.genre_script.new() as Genre
	genre.name = "Genre"
	genre.def = def
	genre.carried_start = carried
	genre.carried_lead = carried_lead
	add_child(genre)
	genre.build(self)

	feedback = Feedback.new()
	feedback.camera = camera
	feedback.effects_parent = world
	add_child(feedback)

	sound = Sound.new()
	sound.name = "Sound"
	add_child(sound)

	transition = Transition.new()
	transition.sound = sound
	add_child(transition)

	director = AiDirector.new()
	director.name = "Director"
	director.transition = transition
	add_child(director)

	prompt_panel = PromptPanel.new()
	add_child(prompt_panel)
	director.prompt_requested.connect(prompt_panel.open)
	prompt_panel.chosen.connect(director.on_choice)
	director.prompt_requested.connect(func(_o: Offer) -> void: sound.play(&"prompt", 0.0))
	prompt_panel.chosen.connect(func(_o: Offer, _m: Mutation) -> void: sound.play(&"click", 0.0))

	patch_history = PatchHistory.new()
	patch_history.director = director
	patch_history.prompt_panel = prompt_panel
	patch_history.transition = transition
	add_child(patch_history)

	genre.run_ended.connect(_on_report_ready)
	genre.stage_ended.connect(func(index: int) -> void: EventBus.stage_ended.emit(index))
	genre.begin_run()

	if RunState.session != null:
		session_runner = SessionRunner.new()
		session_runner.name = "SessionRunner"
		session_runner.session = RunState.session
		session_runner.genre = genre
		add_child(session_runner)
		mascot = Mascot.new()
		mascot.name = "Mascot"
		mascot.setup(RunState.session.face, SaveGame.mascot())
		add_child(mascot)
		if host != null:   # M47.5a: the body stays in the corner, its words go to the terminal
			# M47.6a (PLAN v9.4 2.4): during play the bubble is on again; the chat logs each line.
			mascot.bubble_enabled = true
			mascot.line_started.connect(host.terminal.log_say)
			mascot.line_cut.connect(host.terminal.live_cut)
		reactions = Reactions.new()
		reactions.name = "Reactions"
		reactions.session = RunState.session
		reactions.genre = genre
		reactions.player = player
		reactions.session_id = RunState.session.id
		reactions.muted = session_runner.muted
		add_child(reactions)
		# Reactions hear a script line when it is queued (game time), the mascot when the
		# runner lets it out (read pacing).
		for line in session_runner.queued_lines():
			reactions.note_spoken(line, SessionRunner.PRIORITY)
		session_runner.line_queued.connect(func(line: Line) -> void:
			reactions.note_spoken(line, SessionRunner.PRIORITY))
		session_runner.line_said.connect(func(line: Line) -> void: mascot.say(line, SessionRunner.PRIORITY))
		reactions.line_said.connect(func(line: Line, priority: int) -> void: mascot.say(line, priority))
		rule_book = RuleBook.new()
		rule_book.name = "RuleBook"
		rule_book.game = self
		rule_book.mascot = mascot
		rule_book.reactions = reactions
		rule_book.session_runner = session_runner
		rule_book.sound = sound
		rule_book.muted = session_runner.muted
		add_child(rule_book)
		session_runner.rule_book = rule_book
		event_player = EventPlayer.new()
		event_player.name = "EventPlayer"
		event_player.game = self
		event_player.mascot = mascot
		event_player.reactions = reactions
		event_player.rule_book = rule_book
		event_player.sound = sound
		event_player.transition = transition
		event_player.muted = session_runner.muted
		add_child(event_player)
		session_runner.event_player = event_player
		# M47.6c1 (design 2.6): the endings read the script's cues; a script end window opens
		# with the session's end_line in the bubble.
		if run_loop != null:
			run_loop.session_runner = session_runner
			run_loop.script_window_opened.connect(_on_script_window)
		debrief = DebriefScreen.new()
		debrief.name = "Debrief"
		if host != null:   # M47.5a: the session's end is a terminal beat beside the frozen arena
			debrief.view = DebriefScreen.TERMINAL
			debrief.terminal = host.terminal
			debrief.corner = mascot
			debrief.auto_way_on = host.auto_way_on()
			debrief.host = host
			# M47.5b (PLAN v9.3 2.9, D16): the AI's edits, events and skin cues as `$` rows.
			rule_book.edit_landed.connect(_on_edit_row)
			event_player.event_started.connect(_on_event_row)
			session_runner.skin_cued.connect(_on_skin_row)
		add_child(debrief)
		debrief.next_requested.connect(func() -> void: _end_session(&"next"))
		debrief.move_on_requested.connect(func() -> void: _end_session(&"move_on"))
		debrief.retry_requested.connect(func() -> void: _end_session(&"retry"))
		# PLAN v9 2: a new stage opens with its card; the intro and cues wait on the paused tree.
		if CampaignDB.stage_card_due(RunState.session):
			stage_card = StageCard.new()
			stage_card.name = "StageCard"
			if CampaignDB.door_beat_due(RunState.session):   # M47.4: the front door, built first
				stage_card.setup_door(RunState.session.door_beat_lines())
			if not RunState.session.cook_beat.is_empty():   # M47 (D2): the AI cooking it first
				stage_card.setup_beat(RunState.session.cook_beat, CampaignDB.version_after(RunState.session).label())
			stage_card.setup(RunState.session.stage, CampaignDB.campaign.stage_titles[RunState.session.stage])
			add_child(stage_card)

	report = ReportScreen.new()
	add_child(report)
	report.new_build_requested.connect(_on_report_continue)

	dev_flow = DevSessionFlow.new()
	dev_flow.name = "DevSession"
	add_child(dev_flow)
	dev_flow.session_done.connect(_on_session_done)
	dev_flow.play_requested.connect(func() -> void: start_new_build(_next_run_seed))

	hud = Hud.new()
	hud.player = player
	hud.director = director
	hud.run_loop = run_loop
	hud.turn_clock = turn_clock
	add_child(hud)

	debug = DebugOverlay.new()
	debug.game = self
	add_child(debug)

	# M47.6a (PLAN v9.4 2.2): the movement keys under the square and its strain, while the
	# build cannot move (presentation only: they never write the sim).
	if RunState.session != null and hud != null:
		var keys := MoveKeys.new()
		keys.name = "MoveKeys"
		keys.player = player
		keys.show_for = MoveKeys.show_seconds(RunState.session)
		hud.add_child(keys)
	if player != null and player.get(&"movement_locked") != null and player.get_node_or_null(^"Visual") != null:
		var strain := StrainFX.new()
		strain.name = "StrainFX"
		strain.player = player
		strain.visual = player.get_node(^"Visual") as Node2D
		player.add_child(strain)   # after the body in process order: it leans what the body drew

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	pause_menu.game = self
	add_child(pause_menu)

	if RunState.session != null and (RunState.live_path() != &"" or RunState.session.tryout):
		ensure_path_runner().begin()

	EventBus.player_died.connect(_on_player_died)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.run_started.emit(run_seed)


## The PathRunner and its PickPanel, made on first use (a path or tryout session at boot,
## F2's PATH in any scene, the v6 loop included).
func ensure_path_runner() -> PathRunner:
	if path_runner != null:
		return path_runner
	pick_panel = PickPanel.new()
	pick_panel.name = "PickPanel"
	add_child(pick_panel)
	path_runner = PathRunner.new()
	path_runner.name = "PathRunner"
	path_runner.game = self
	path_runner.panel = pick_panel
	pick_panel.runner = path_runner   # M50.4f: the flat slot bar under the dressed cards
	pick_panel.mascot = mascot        # M50.7: its bubble parks under an open panel
	pick_panel.sound = sound          # M50.7: the pack beats' sounds
	pick_panel.hand_target = pick_hand_target   # M50.7 review: the slot-in flies to the real hand
	path_runner.nerf_landed.connect(_on_nerf_row)
	path_runner.muted = session_runner != null and session_runner.muted
	add_child(path_runner)
	if session_runner != null:
		session_runner.path_runner = path_runner
		path_runner.started.connect(session_runner.on_path_started)   # M47: `picked` cues
	if genre != null and genre.is_over():
		path_runner.stop()
	return path_runner


## Debug wave (F-key, screenshots): the genre's own, if it has one.
## "[boot] Patch Notes M30, game v0.1.2, genre <id> (playable: <ids>), Godot 4.7.0":
## the build, the save's version and the run's genre, for the export check and bug
## reports (PLAN v5 M30), then the save's answers (PLAN v6 M36).
static func boot_line() -> String:
	var v: Dictionary = Engine.get_version_info()
	return "[boot] Patch Notes %s, game %s, genre %s%s (playable: %s), Godot %s.%s.%s, %s" % [BUILD,
			SaveGame.version().label(), RunState.genre,
			", session %s" % RunState.session.id if RunState.session else "",
			", ".join(GenreDB.playable_ids().map(func(g: StringName) -> String: return String(g))),
			v.major, v.minor, v.patch, answers_text()]


## "answers look_1=look_1_clean fork_enemy=enemy_tank" (fork id order), "answers -" for
## none: which game this save became, for bug reports and the playtest files (M36).
static func answers_text() -> String:
	var a := DevSession.answers()
	var ids: Array = a.keys()
	ids.sort()
	var parts := ids.map(func(f: String) -> String: return "%s=%s" % [f, a[f]])
	return "answers " + (" ".join(parts) if not parts.is_empty() else "-")


func spawn_wave(count := -1) -> void:
	if genre.has_method(&"spawn_wave"):
		if count < 0:
			genre.call(&"spawn_wave")
		else:
			genre.call(&"spawn_wave", count)


func restart(same_seed := false) -> void:
	start_new_build(RunState.run_seed if same_seed else -1)


## "New build": a fresh run. A negative seed picks a random one. Only works when this
## is the current scene (tests instance it as a child and never reload it).
func start_new_build(run_seed := -1) -> void:
	clear_start()   # M47.6c2: Restart / F5 starts at player_start
	if not is_live_game():   # M47.5a review: hosted, the host is the current scene
		return
	save_notes()
	if host != null:
		RunState.set_pause(GameHost.HANDOFF, true)   # frozen until the swap, as menu_restart
	_reload(run_seed)


## The report's main button: "Dev session" when the save is live, else "New build".
func _on_report_continue(run_seed := -1) -> void:
	if SaveGame.is_live():
		open_dev_session(run_seed)
	else:
		start_new_build(run_seed)


## Opens the dev session for the save as it is now (PLAN v5 4.1). After a run its
## opening line reads the run; F9 opens one at any time (an inert game plays it on the
## in-memory save, which is never written). "Play" starts the next run with run_seed.
func open_dev_session(run_seed := -1) -> void:
	if dev_flow.is_open() or RunState.session != null:   # the campaign has its debrief
		return
	save_notes()   # the report's ratings feed the taste the session reads
	_next_run_seed = run_seed
	var context := DevSession.context_from_record(genre.run_record()) if genre.is_over() else {}
	report.close()
	prompt_panel.dismiss()
	RunState.set_pause(&"dev_session", true)
	dev_flow.start(DevSession.plan(RunState.run_seed, context))


## Shift+F9: ships what the next session would (its first card, or the AI's last
## change) without the screens.
func ship_next_change() -> DevSession:
	if dev_flow.is_open() or RunState.session != null:
		return null   # the open session ships; a second one would log twice
	var session := DevSession.plan(RunState.run_seed)
	var ok := session.pick(0) if session.can_pick() else session.finish()
	if ok:
		_on_session_done(session)
		if transition and not session.shipped.is_empty():
			var said := "Shipped %s: %s" % [session.version_after().label(),
					(session.shipped[0].change as Change).title]
			transition.say(said)
			print("[debug] " + said)   # the toast sits under the report
	return session


## F2's rework buttons (PLAN v6 5): swaps fork_id's answer for to_id as a session of
## its own (logged, one patch step), whatever the session would have asked. The next
## run plays it. Null if a session is open or that swap is not on the shelf.
func debug_rework(fork_id: StringName, to_id: StringName) -> DevSession:
	if dev_flow.is_open() or not SaveGame.is_live():
		return null
	var session := DevSession.plan(RunState.run_seed)
	session.shape = DevSession.REWORK   # whatever was due waits for the next session
	session.fork = null
	session.cards.clear()
	if not session.rework(fork_id, to_id):
		return null
	_on_session_done(session)
	var said := "Reworked %s: %s" % [session.version_after().label(), session.rework_id()]
	if transition:
		transition.say(said)
	print("[debug] " + said)
	return session


func _on_session_done(session: DevSession) -> void:
	# Mid-run (Shift+F9): the run carries on and writes its taste at its end, so it
	# starts from the taste the session just wrote.
	if SaveGame.is_live() and not genre.is_over() and director:
		director.taste = Taste.from_save(SaveGame.state().taste)
	if is_live_game():
		Telemetry.append(session.telemetry_record(int(genre.run_record().get("run_index", 0))))


func _on_player_died() -> void:
	player.visible = false


func _on_run_ended(outcome: StringName) -> void:
	if path_runner != null:
		path_runner.stop()   # M45a: the pick panel closes with its pause reason
	if RunState.session != null and RunState.session.look_reveal == &"manual":
		Skins.reveal_all()   # M48b (D4): the debrief and an early death end fully revealed
	if RunState.session != null:
		# A campaign session logs one line when the player picks the way on (_end_session).
		prompt_panel.dismiss()
		patch_history.close()
		patch_history.locked = true
		return
	if is_live_game():
		Telemetry.append(genre.run_record())
		# The save (inert unless the start screen or a bot chain made it live) counts the
		# run, its genre's play time in real seconds, and the taste it ended with.
		SaveGame.record_run(RunState.genre, outcome, RunState.real_time(), director.taste.to_save())
	prompt_panel.dismiss()
	patch_history.close()
	patch_history.locked = true


func _on_report_ready(outcome: StringName) -> void:
	transition.clear_toast()
	if RunState.session != null:
		if host != null:
			mascot.bubble_enabled = false   # M47.6a: between sessions the chat talks, not the bubble
			# M47.6c2 (design 2.7): a seamless next session: the room empties during the beat.
			if GameHost.carry_ok(RunState.session, CampaignDB.session(CampaignDB.index_of(RunState.session.id) + 1),
					DebriefScreen.outcome_name(outcome)):
				host.clear_field(self)
		mascot.silence(host == null)   # hosted: the body stays in the corner for the beat
		debrief.open(RunState.session, outcome, session_runner.hits, event_player.played_ids())
		return
	report.open(outcome, genre.run_record())


## The debrief's way on (PLAN v8 1.2): one telemetry line, then the save moves on (next,
## move_on) or counts the attempt (retry), and the next scene plays it. After the last
## session the title screen comes back (M43.2: the cooking screen, while one is cooking).
func _end_session(choice: StringName) -> void:
	var s := RunState.session
	if s == null or not debrief.is_open():
		return
	if is_live_game():
		Telemetry.append(_flow(CampaignDB.telemetry_record(s, genre.run_record(), debrief.outcome,
				session_runner.hits, choice, BUILD, debrief.picked, reactions.fired_ids(), rule_book.landed,
				event_player.played_ids(), debrief.more_picks(), path_runner), debrief.beat_real_s()))
	if choice == &"retry":
		CampaignDB.retry(s)
	else:
		if path_runner != null:
			path_runner.bank_packs()   # M50.6: unopened packs wait for the path's next session
		CampaignDB.complete(s, debrief.picked, debrief.more_picks())
	if not is_live_game():
		return   # a test's copy: the save moved on, nothing reloads
	var leave := ""
	if SaveGame.in_replay() and choice != &"retry":
		leave = StartScreen.TITLE_SCENE   # M47: the title ends the replay
	elif CampaignDB.is_done():
		leave = CookingScreen.after_campaign_scene()
	if host != null and leave == "":
		RunState.set_pause(GameHost.HANDOFF, true)   # M47.5a: the old arena stays frozen until the swap
	# M47.6c2 (design 2.7): Next / Move on into a Stage 1 session carries the player's spot
	# (the tool chain captures through the same GameHost.capture_start); a retry never does.
	clear_start()
	if host != null and leave == "" and choice != &"retry":
		next_start = GameHost.capture_start(self, CampaignDB.current())
		next_lead = camera.get_screen_center_position() - player.global_position 				if next_start.is_finite() and camera != null else Vector2.ZERO
	debrief.close()
	if leave != "":
		_leave_to(leave)
	else:
		_reload(debrief.next_seed, _restart_text(s) if choice == &"retry" else "")


## The session leaves the game for another scene (the title, the cooking screen): nothing
## stays paused behind it (M47.5a review: the handoff pause leaked to the title).
func _leave_to(path: String) -> void:
	RunState.clear_pauses()
	clear_start()   # M47.6c2: the title (or the cooking screen) starts cold
	if leave_hook.is_valid():
		leave_hook.call(path)
		return
	if path == QUIT_GAME:
		get_tree().quit()
		return
	get_tree().change_scene_to_file(path)


## M47.5b (PLAN v9.3 2.9, D16): a landed edit's row: its cmd_text, else "patch <title>".
## Quiet edits (no warning of their own) and an event's edits print nothing (the event's own
## row, if any, said what the AI typed); never a raw id.
func _on_edit_row(edit: RuleEdit) -> void:
	if host == null or rule_book == null or not rule_book.last_warned or rule_book.last_by == &"event":
		return
	host.terminal.cmd(edit_row_text(edit), "ok")


static func edit_row_text(edit: RuleEdit) -> String:
	return edit.cmd_text if edit.cmd_text != "" else "patch %s" % edit.title.to_lower()


## M50.7 (plan item 8): the live nerf's row, like a rule edit's: `$ hotfix minigun ... ok` in the
## terminal (the rail draws it as a hotfix slip carrying the patch note), and on the flat HUD
## (no rail) the note as a toast. Presentation only: no cue, no say, no RunState write.
func _on_nerf_row(text: String, weapon: StringName) -> void:
	var rail: Node = host.get(&"rail") if host != null else null
	if host != null:
		var row := nerf_row_text(weapon)
		if rail != null and is_instance_valid(rail) and bool(rail.get(&"on")):
			rail.call(&"mark_nerf", "$ " + row, text)
		host.terminal.cmd(row, "ok")
	if rail == null or not is_instance_valid(rail) or not bool(rail.get(&"on")):
		pick_panel.note(text)


## M50.7 review: where a pack's chosen card flies, in the game view's coordinates: the rail's HAND
## module when the rail shows (below the game column, so the card leaves the view toward it),
## else the flat hand widget's first card. null: the panel's default. Presentation only.
func pick_hand_target() -> Variant:
	var view := get_viewport().get_visible_rect().size
	var rail: Node = host.get(&"rail") if host != null else null
	if rail != null and is_instance_valid(rail) and bool(rail.get(&"on")):
		var mods: Node = rail.get(&"modules")
		var g: Rect2 = host.game_rect()
		if mods != null and mods.has_method(&"cell_rect") and g.size.x > 0.0 and g.size.y > 0.0:
			var cell: Rect2 = mods.call(&"cell_rect", &"path")
			if cell.size.x > 0.0:
				return (cell.get_center() - g.position) * view / g.size
	var w: Control = path_runner.widget() if path_runner != null else null
	if w != null and is_instance_valid(w) and w.is_visible_in_tree() and w.has_method(&"card_rect"):
		var r: Rect2 = w.call(&"card_rect", 0, view)
		return r.get_center()
	return null


static func nerf_row_text(weapon: StringName) -> String:
	return "hotfix %s" % String(weapon)


func _on_event_row(id: StringName) -> void:
	var ev := EventDB.get_event(id)
	if host != null and ev != null and ev.cmd_text != "":
		host.terminal.cmd(ev.cmd_text, "ok")


func _on_skin_row(target: StringName) -> void:
	if host != null and target != &"bug":
		host.terminal.cmd("skin reveal %s" % target, "ok")


## M47.5b (PLAN v9.3 2.8): a hosted live line says so and how long its beat took (real
## seconds from the debrief opening; 0 for the pause menu's lines). Same line, same moment.
## M47.6c1 (design 2.10, additive): and the play gate's wait, the lines typed at it that were
## not play (a count, never the text) and which chat the player had.
func _flow(rec: Dictionary, beat_s: float) -> Dictionary:
	if host != null:
		rec["flow"] = "always_on"
		rec["beat_real_s"] = beat_s
		rec["play_wait_s"] = host.play_wait_s
		rec["chat_typed"] = host.gate_typed
		rec["chat_style"] = String(CampaignDB.chat_style())
	return rec


## M47.6c1 (design 2.3): the script is done: the AI says the test is over (end_line, if any).
func _on_script_window() -> void:
	if session_runner == null or RunState.session == null:
		return
	var line := RunState.session.end_line_parsed()
	if line != null and line.passes(CampaignDB.line_context(RunState.session)):
		session_runner.say(line)


## M47.3 (PLAN 1.16): the pause menu's Restart session: the debrief's Retry from the middle
## of a session (one `menu_retry` telemetry line, one attempt), then a reload.
func menu_restart() -> void:
	clear_start()   # M47.6c2: a retry starts at player_start
	var s := RunState.session
	# M47.6a review: at a play gate nothing was played yet: no attempt, no telemetry line
	# (the new attempt gates again: GameHost.next_session carries only a play given).
	var at_gate := host != null and is_instance_valid(host) and host.held
	if s != null and not at_gate:
		_menu_telemetry(s, &"menu_retry")
		CampaignDB.retry(s)
	RunState.clear_pauses()
	if not is_live_game():
		return   # a test's copy: counted, nothing reloads
	if host != null:
		RunState.set_pause(GameHost.HANDOFF, true)
	_reload(-1, _restart_text(s) if s != null else "")


## M47.6c2: no carried start (the next run starts at the arena's player_start).
static func clear_start() -> void:
	next_start = NO_START
	next_lead = Vector2.ZERO


## M47.5a: the next scene plays `run_seed` (-1 = random): the host swaps the session in
## (hot-reload), or, unhosted, the scene reloads as before.
func _reload(run_seed: int, restart := "") -> void:
	next_seed = run_seed
	next_genre = RunState.genre
	if host != null:
		host.next_session(restart)
	else:
		get_tree().reload_current_scene()


## "restart s1_04_level (try 2)": the terminal's line for a new attempt.
static func _restart_text(s: SessionDef) -> String:
	return "restart %s (try %d)" % [s.id, CampaignDB.attempt(s.id)]


## M47.3: Quit to title (raw: quit to start). A session logs one `abandon` line; the save
## is untouched (Continue replays the session); the v6 loop logs nothing (its telemetry is
## per finished run). StartScreen's campaign build ends a replay as today.
func menu_quit() -> void:
	var s := RunState.session
	if s != null:
		_menu_telemetry(s, &"abandon")
	RunState.clear_pauses()
	if not is_live_game():
		return
	_leave_to(quit_target(s))


## M47.5b (PLAN v9.3 2.7, D11): before the front door a campaign session's Q quits the game
## (the boot goes straight back into the host, there is no start screen); from the door on,
## and in the v6 loop, Quit goes to the title / start screen as before.
static func quit_target(s: SessionDef) -> String:
	if s != null and not CampaignDB.front_door_open():
		return QUIT_GAME
	return StartScreen.TITLE_SCENE


func _menu_telemetry(s: SessionDef, choice: StringName) -> void:
	if not is_live_game() and not menu_telemetry_always:
		return
	Telemetry.append(_flow(CampaignDB.telemetry_record(s, genre.run_record(), &"quit",
			session_runner.hits if session_runner != null else 0, choice, BUILD, null,
			reactions.fired_ids() if reactions != null else ([] as Array[String]),
			rule_book.landed if rule_book != null else [],
			event_player.played_ids() if event_player != null else [], [], path_runner), 0.0))


## True when this scene is the game being played, not a copy instanced by a test.
## Only the live game writes telemetry and teaches the next run. M47.5a: or the session of
## the live always-on host (never a tool's or a test's host).
func is_live_game() -> bool:
	return is_inside_tree() and (get_tree().current_scene == self or (host != null and host.is_live()))


## The report's notes become what the AI knows at the start of the next run of this
## session, and one "notes" telemetry line. Skipping them is a signal too.
func save_notes() -> void:
	if _notes_saved or not genre.is_over() or not is_live_game() or RunState.session != null:
		return
	_notes_saved = true
	if SaveGame.is_live():
		# A live save keeps taste on disk: fold the ratings into it.
		var taste := Taste.from_save(SaveGame.state().taste)
		for id: StringName in report.ratings:
			var m := MutationDB.get_mutation(id)
			if m:
				taste.on_rating(m, report.ratings[id])
		SaveGame.set_taste(taste.to_save())
	else:
		Taste.carried = report.ratings.duplicate()
	Taste.last_run_rated = 1 if not report.ratings.is_empty() else 0
	var notes := {}
	for id: StringName in report.ratings:
		notes[String(id)] = report.ratings[id]
	Telemetry.append({"type": "notes", "session_id": Telemetry.session(),
			"run_index": genre.run_record().get("run_index", 0), "seed": RunState.run_seed,
			"rated": not notes.is_empty(), "notes": notes})


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_notes()
