class_name Main
extends Node2D
## The game scene: the shell (PLAN v5 1.1). It keeps what every genre shares (the run
## reset, feedback, sound, transitions, the Director, the player-facing UI, telemetry)
## and hands the run itself to the genre: arena, world, player, camera, spawner and
## pacing all live in the Genre node it builds. It never branches on a genre id.

const BUILD := "M50.1a"

## Survive scene reloads: F5 restarts the same seed, "New build" keeps the genre.
static var next_seed := -1
static var next_genre: StringName = &""

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
		debrief = DebriefScreen.new()
		debrief.name = "Debrief"
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
	if get_tree().current_scene != self:
		return
	save_notes()
	next_seed = run_seed
	next_genre = RunState.genre
	get_tree().reload_current_scene()


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
		mascot.silence()
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
		Telemetry.append(CampaignDB.telemetry_record(s, genre.run_record(), debrief.outcome,
				session_runner.hits, choice, BUILD, debrief.picked, reactions.fired_ids(), rule_book.landed,
				event_player.played_ids(), debrief.more_picks(), path_runner))
	if choice == &"retry":
		CampaignDB.retry(s)
	else:
		CampaignDB.complete(s, debrief.picked, debrief.more_picks())
	if get_tree().current_scene != self:
		return   # a test's copy: the save moved on, nothing reloads
	debrief.close()
	if SaveGame.in_replay() and choice != &"retry":
		get_tree().change_scene_to_file(StartScreen.TITLE_SCENE)   # M47: the title ends the replay
	elif CampaignDB.is_done():
		get_tree().change_scene_to_file(CookingScreen.after_campaign_scene())
	else:
		next_seed = debrief.next_seed
		next_genre = RunState.genre
		get_tree().reload_current_scene()


## M47.3 (PLAN 1.16): the pause menu's Restart session: the debrief's Retry from the middle
## of a session (one `menu_retry` telemetry line, one attempt), then a reload.
func menu_restart() -> void:
	var s := RunState.session
	if s != null:
		_menu_telemetry(s, &"menu_retry")
		CampaignDB.retry(s)
	RunState.clear_pauses()
	if get_tree().current_scene != self:
		return   # a test's copy: counted, nothing reloads
	next_seed = -1
	next_genre = RunState.genre
	get_tree().reload_current_scene()


## M47.3: Quit to title (raw: quit to start). A session logs one `abandon` line; the save
## is untouched (Continue replays the session); the v6 loop logs nothing (its telemetry is
## per finished run). StartScreen's campaign build ends a replay as today.
func menu_quit() -> void:
	var s := RunState.session
	if s != null:
		_menu_telemetry(s, &"abandon")
	RunState.clear_pauses()
	if get_tree().current_scene != self:
		return
	get_tree().change_scene_to_file(StartScreen.TITLE_SCENE)


func _menu_telemetry(s: SessionDef, choice: StringName) -> void:
	if not is_live_game() and not menu_telemetry_always:
		return
	Telemetry.append(CampaignDB.telemetry_record(s, genre.run_record(), &"quit",
			session_runner.hits if session_runner != null else 0, choice, BUILD, null,
			reactions.fired_ids() if reactions != null else ([] as Array[String]),
			rule_book.landed if rule_book != null else [],
			event_player.played_ids() if event_player != null else [], [], path_runner))


## True when this scene is the game being played, not a copy instanced by a test.
## Only the live game writes telemetry and teaches the next run.
func is_live_game() -> bool:
	return is_inside_tree() and get_tree().current_scene == self


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
