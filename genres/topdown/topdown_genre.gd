class_name TopdownGenre
extends Genre
## The top-down shooter (PLAN v5 1.1), the first genre: one arena, the player, the
## wave spawner, the camera, the slow-motion tint, and the run pacing of RunLoop (play -> release candidate
## -> over). The parked turn-based code (TurnClock, TurnOverlay) still lives here, as
## it did in M14's single scene, until Phase 5 makes it a genre of its own.

const PLAYER_SCENE := preload("res://entities/player.tscn")
const CHASER_SCENE := preload("res://entities/enemy_chaser.tscn")
const WAVE_SIZE := 8
const WAVE_MIN_DISTANCE_TILES := 6.0

var arena: Arena
var spawner: Spawner
var turn_clock: TurnClock
var run_loop: RunLoop


func build(p_shell: Node) -> void:
	super(p_shell)
	arena = Arena.new()
	arena.name = "Arena"
	if not Unlocks.has_basic(&"level"):
		arena.strip_layout()   # PLAN v5 4.8: no level yet, an empty box
	add_child(arena)

	world = Node2D.new()
	world.name = "World"
	add_child(world)
	RunState.world = world

	player = PLAYER_SCENE.instantiate()
	player.position = arena.player_start
	player.set(&"movement_locked", not Unlocks.has_basic(&"movement"))
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

	var rig := CameraRig.new()
	rig.target = player
	rig.set_bounds(arena.bounds)
	add_child(rig)
	rig.make_current()
	camera = rig

	var tint := TimeTint.new()
	tint.name = "TimeTint"
	add_child(tint)

	spawner = Spawner.new()
	spawner.name = "Spawner"
	spawner.arena = arena
	spawner.player = player
	spawner.enabled = Unlocks.has_basic(&"enemies")
	add_child(spawner)

	run_loop = RunLoop.new()
	run_loop.name = "RunLoop"
	# M14 ran the loop after the Director and the Transition; the priority keeps that
	# order now that the loop sits in the genre, ahead of the shell's nodes.
	run_loop.process_physics_priority = 1
	add_child(run_loop)


func begin_run() -> void:
	run_loop.build = shell.BUILD
	run_loop.director = shell.director
	run_loop.spawner = spawner
	run_loop.transition = shell.transition
	run_loop.report_ready.connect(func(outcome: StringName) -> void: run_ended.emit(outcome))
	var missing := Unlocks.missing_basics()
	if not missing.is_empty():
		# A build that misses a basic (PLAN v5 4.8) plays a short smoke test: no prompts.
		run_loop.smoke_duration = Tuning.smoke_test_duration
		shell.director.enabled = false
		if shell.transition:
			shell.transition.say(smoke_line(missing))
	run_loop.phase_changed.connect(func(phase: StringName) -> void:
		if phase == RunLoop.RELEASE_CANDIDATE and shell.sound:
			shell.sound.play(&"release_candidate", 0.0))


## The AI's line at the start of a smoke test, about the first basic still missing.
static func smoke_line(missing: Array[StringName]) -> String:
	match missing[0]:
		&"movement":
			return "Smoke test. Movement is not in yet: aim and shoot, that is all."
		&"enemies":
			return "Smoke test. You can move now. There is nothing to shoot yet."
		_:
			return "Smoke test. Something basic is still missing."


func run_record() -> Dictionary:
	return run_loop.record


func is_over() -> bool:
	return run_loop.is_over()


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
