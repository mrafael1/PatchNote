class_name Main
extends Node2D
## The game scene: the shell (PLAN v5 1.1). It keeps what every genre shares (the run
## reset, feedback, sound, transitions, the Director, the player-facing UI, telemetry)
## and hands the run itself to the genre: arena, world, player, camera, spawner and
## pacing all live in the Genre node it builds. It never branches on a genre id.

const BUILD := "M31"

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
var sound: Sound

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
	print(boot_line())
	Look.use(Unlocks.look())   # the save's look (PLAN v5 1.7); punchy while inert

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
	genre.begin_run()

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

	var debug := DebugOverlay.new()
	debug.game = self
	add_child(debug)

	EventBus.player_died.connect(_on_player_died)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.run_started.emit(run_seed)


## Debug wave (F-key, screenshots): the genre's own, if it has one.
## "[boot] Patch Notes M30, game v0.1.2, genre <id> (playable: <ids>), Godot 4.7.0":
## the build, the save's version and the run's genre, for the export check and bug
## reports (PLAN v5 M30).
static func boot_line() -> String:
	var v: Dictionary = Engine.get_version_info()
	return "[boot] Patch Notes %s, game %s, genre %s (playable: %s), Godot %s.%s.%s" % [BUILD,
			SaveGame.version().label(), RunState.genre,
			", ".join(GenreDB.playable_ids().map(func(g: StringName) -> String: return String(g))),
			v.major, v.minor, v.patch]


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
	if dev_flow.is_open():
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
	if dev_flow.is_open():
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
	report.open(outcome, genre.run_record())


## True when this scene is the game being played, not a copy instanced by a test.
## Only the live game writes telemetry and teaches the next run.
func is_live_game() -> bool:
	return is_inside_tree() and get_tree().current_scene == self


## The report's notes become what the AI knows at the start of the next run of this
## session, and one "notes" telemetry line. Skipping them is a signal too.
func save_notes() -> void:
	if _notes_saved or not genre.is_over() or not is_live_game():
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
