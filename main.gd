class_name Main
extends Node2D
## The game scene. Builds the arena, the player, the camera and the UI, and starts a run.

const BUILD := "M14"
const PLAYER_SCENE := preload("res://entities/player.tscn")
const CHASER_SCENE := preload("res://entities/enemy_chaser.tscn")
const WAVE_SIZE := 8
const WAVE_MIN_DISTANCE_TILES := 6.0

## Survives scene reloads so F5 can restart the same seed.
static var next_seed := -1

var arena: Arena
var world: Node2D
var player: CharacterBody2D
var camera: CameraRig
var spawner: Spawner
var feedback: Feedback
var transition: Transition
var director: AiDirector
var prompt_panel: PromptPanel
var patch_history: PatchHistory
var run_loop: RunLoop
var report: ReportScreen
var sound: Sound
var turn_clock: TurnClock

var _notes_saved := false


func _ready() -> void:
	var v: Dictionary = Engine.get_version_info()
	print("[boot] Patch Notes %s, Godot %s.%s.%s" % [BUILD, v.major, v.minor, v.patch])

	var run_seed := next_seed if next_seed >= 0 else int(randi() % 1000000)
	next_seed = -1
	RunState.reset(run_seed)

	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)

	world = Node2D.new()
	world.name = "World"
	add_child(world)
	RunState.world = world

	player = PLAYER_SCENE.instantiate()
	player.position = arena.player_start
	world.add_child(player)

	turn_clock = TurnClock.new()
	turn_clock.name = "TurnClock"
	turn_clock.player = player
	turn_clock.arena = arena
	add_child(turn_clock)

	var overlay := TurnOverlay.new()
	overlay.name = "TurnOverlay"
	overlay.player = player
	world.add_child(overlay)

	camera = CameraRig.new()
	camera.target = player
	camera.set_bounds(arena.bounds)
	add_child(camera)
	camera.make_current()

	spawner = Spawner.new()
	spawner.name = "Spawner"
	spawner.arena = arena
	spawner.player = player
	add_child(spawner)

	feedback = Feedback.new()
	feedback.camera = camera
	feedback.effects_parent = world
	add_child(feedback)

	var tint := TimeTint.new()
	tint.name = "TimeTint"
	add_child(tint)

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

	run_loop = RunLoop.new()
	run_loop.name = "RunLoop"
	run_loop.build = BUILD
	run_loop.director = director
	run_loop.spawner = spawner
	run_loop.transition = transition
	add_child(run_loop)
	run_loop.report_ready.connect(_on_report_ready)
	run_loop.phase_changed.connect(func(phase: StringName) -> void:
		if phase == RunLoop.RELEASE_CANDIDATE:
			sound.play(&"release_candidate", 0.0))

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


## Debug wave: chasers at spawn points away from the player.
func spawn_wave(count := WAVE_SIZE) -> void:
	var far: Array[Vector2] = []
	for p in arena.spawn_points:
		if p.distance_to(player.global_position) >= WAVE_MIN_DISTANCE_TILES * Tuning.TILE:
			far.append(p)
	if far.is_empty():
		far = arena.spawn_points
	for i in count:
		var p := far[RunState.gameplay_rng.randi_range(0, far.size() - 1)]
		var jitter := Vector2(RunState.gameplay_rng.randf_range(-20, 20), RunState.gameplay_rng.randf_range(-20, 20))
		RunState.spawn(CHASER_SCENE, p + jitter)


func restart(same_seed := false) -> void:
	start_new_build(RunState.run_seed if same_seed else -1)


## "New build": a fresh run. A negative seed picks a random one. Only works when this
## is the current scene (tests instance it as a child and never reload it).
func start_new_build(run_seed := -1) -> void:
	if get_tree().current_scene != self:
		return
	save_notes()
	next_seed = run_seed
	get_tree().reload_current_scene()


func _on_player_died() -> void:
	player.visible = false


func _on_run_ended(_outcome: StringName) -> void:
	if is_live_game():
		Telemetry.append(run_loop.record)
	prompt_panel.dismiss()
	patch_history.close()
	patch_history.locked = true


func _on_report_ready(outcome: StringName) -> void:
	transition.clear_toast()
	report.open(outcome, run_loop.record)


## True when this scene is the game being played, not a copy instanced by a test.
## Only the live game writes telemetry and teaches the next run.
func is_live_game() -> bool:
	return is_inside_tree() and get_tree().current_scene == self


## The report's notes become what the AI knows at the start of the next run of this
## session, and one "notes" telemetry line. Skipping them is a signal too.
func save_notes() -> void:
	if _notes_saved or not run_loop.is_over() or not is_live_game():
		return
	_notes_saved = true
	Taste.carried = report.ratings.duplicate()
	Taste.last_run_rated = 1 if not report.ratings.is_empty() else 0
	var notes := {}
	for id: StringName in report.ratings:
		notes[String(id)] = report.ratings[id]
	Telemetry.append({"type": "notes", "session_id": Telemetry.session(),
			"run_index": run_loop.record.get("run_index", 0), "seed": RunState.run_seed,
			"rated": not notes.is_empty(), "notes": notes})


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_notes()
