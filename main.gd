class_name Main
extends Node2D
## The game scene. Builds the arena, the player, the camera and the UI, and starts a run.

const BUILD := "M6"
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


func _ready() -> void:
	var v: Dictionary = Engine.get_version_info()
	print("[boot] Alone Alone Lab %s, Godot %s.%s.%s" % [BUILD, v.major, v.minor, v.patch])

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

	transition = Transition.new()
	add_child(transition)

	director = AiDirector.new()
	director.name = "Director"
	director.transition = transition
	add_child(director)

	prompt_panel = PromptPanel.new()
	add_child(prompt_panel)
	director.prompt_requested.connect(prompt_panel.open)
	prompt_panel.chosen.connect(director.on_choice)

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

	report = ReportScreen.new()
	add_child(report)
	report.new_build_requested.connect(start_new_build)

	var hud := Hud.new()
	hud.player = player
	hud.director = director
	hud.run_loop = run_loop
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
	next_seed = run_seed
	get_tree().reload_current_scene()


func _on_player_died() -> void:
	player.visible = false


func _on_run_ended(_outcome: StringName) -> void:
	if get_tree().current_scene == self:
		Telemetry.append(run_loop.record)
	prompt_panel.dismiss()
	patch_history.close()
	patch_history.locked = true


func _on_report_ready(outcome: StringName) -> void:
	report.open(outcome, run_loop.record)
