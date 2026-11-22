class_name Main
extends Node2D
## The game scene: the shell (PLAN v5 1.1). It keeps what every genre shares (the run
## reset, feedback, sound, transitions, the Director, the player-facing UI, telemetry)
## and hands the run itself to the genre: arena, world, player, camera, spawner and
## pacing all live in the Genre node it builds. It never branches on a genre id.

const BUILD := "M28"

## Survive scene reloads: F5 restarts the same seed, "New build" keeps the genre.
static var next_seed := -1
static var next_genre: StringName = &""

var genre: Genre
var feedback: Feedback
var transition: Transition
var director: AiDirector
var prompt_panel: PromptPanel
var patch_history: PatchHistory
var report: ReportScreen
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


func _ready() -> void:
	var v: Dictionary = Engine.get_version_info()
	print("[boot] Patch Notes %s, Godot %s.%s.%s" % [BUILD, v.major, v.minor, v.patch])

	var run_seed := next_seed if next_seed >= 0 else int(randi() % 1000000)
	next_seed = -1
	RunState.reset(run_seed, next_genre)
	next_genre = &""
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
	report.new_build_requested.connect(start_new_build)

	var hud := Hud.new()
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
