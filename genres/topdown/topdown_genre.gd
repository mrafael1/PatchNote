class_name TopdownGenre
extends Genre
## The top-down shooter (PLAN v5 1.1), the first genre: the arena, the player, the
## wave spawner, the camera, the slow-motion tint, and the run pacing of RunLoop (play -> release candidate
## -> over). A run plays a StageSet (PLAN v6 4): between two stages the field is cleared
## and the next stage's arena replaces the last; the player, its components and the
## stack carry over. The parked turn-based code (TurnClock, TurnOverlay) still lives here, as
## it did in M14's single scene, until Phase 5 makes it a genre of its own.

const PLAYER_SCENE := preload("res://entities/player.tscn")
const CHASER_SCENE := preload("res://entities/enemy_chaser.tscn")
const WAVE_SIZE := 8
const WAVE_MIN_DISTANCE_TILES := 6.0

var arena: Arena
var spawner: Spawner
var turn_clock: TurnClock
var run_loop: RunLoop
var stages: StageSet


## World nodes a stage change keeps where they are (the player is always kept).
const KEEP_GROUP := &"keeps_across_stages"
## World nodes a stage change keeps and moves to one of the next arena's spawn markers
## (a stalker that follows you, PLAN v6 4).
const FOLLOW_GROUP := &"follows_across_stages"


## The player's locks from the basics (Unlocks.has_basic): at build, and again when a
## session's cue adds one (PLAN v8 M39.2).
func apply_basics() -> void:
	player.set(&"movement_locked", not Unlocks.has_basic(&"movement"))
	player.set(&"shooting_locked", not Unlocks.has_basic(&"shooting"))
	player.set(&"dash_locked", not Unlocks.has_basic(&"dash"))
	var dasher := Component.find(player, Dasher) as Dasher
	if dasher != null:
		dasher.style = Unlocks.dash_style()
	player.set(&"damage_locked", not Unlocks.has_basic(&"health"))


## The spawner runs with enemies, but not while the gun cannot hit them yet (S3 before
## `hits`): the gag is the AI's two chasers, not a crowd nobody can kill (M39.2 review).
func _spawner_wanted() -> bool:
	if not Unlocks.has_basic(&"enemies"):
		return false
	return Unlocks.has_basic(&"hits") or not Unlocks.has_basic(&"shooting")


func _on_basic_added(id: StringName) -> void:
	if not is_instance_valid(player):
		return
	apply_basics()
	if id == &"health":
		RunState.start_grace(Tuning.health_added_grace)   # the rims light, "run." is said, then the bites
	# Only the basics _spawner_wanted() reads touch the spawner: `add version` must not
	# turn back on a spawner something else turned off (a test, a held clock; M42).
	if id in [&"enemies", &"hits", &"shooting"]:
		_sync_spawner()


## The spawner's state, derived (not saved and restored): wanted by the basics, and
## paused while a scripted event holds the session clock, so the event does not end on
## a crowd that built up while it played (M42 E5). Never back on once the run is over.
func _sync_spawner() -> void:
	if not is_instance_valid(spawner):
		return
	spawner.enabled = _spawner_wanted() and not (run_loop != null and (run_loop.clock_held() or run_loop.is_over()))


func build(p_shell: Node) -> void:
	super(p_shell)
	# A smoke-test build (PLAN v5 4.8) is one short stage, whatever the set. A campaign
	# session (PLAN v8) plays one stage on its own arena.
	if RunState.session != null:
		stages = StageSet.single(RunState.session.arena_def())
		stages.stage(0).spawn_rate = RunState.session.spawn_rate
		stages.stage(0).spawn_cap = RunState.session.spawn_cap
	elif Unlocks.missing_basics().is_empty():
		stages = StageSet.for_run()
	else:
		stages = StageSet.single()
	_build_arena(stages.stage(0).arena)

	world = Node2D.new()
	world.name = "World"
	add_child(world)
	RunState.world = world

	player = PLAYER_SCENE.instantiate()
	player.position = arena.player_start
	apply_basics()
	EventBus.basic_added.connect(_on_basic_added)
	world.add_child(player)

	turn_clock = TurnClock.new()
	turn_clock.name = "TurnClock"
	turn_clock.player = player
	turn_clock.arena = arena
	add_child(turn_clock)

	var overlay := TurnOverlay.new()
	overlay.name = "TurnOverlay"
	overlay.player = player
	overlay.add_to_group(KEEP_GROUP)
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
	spawner.enabled = _spawner_wanted()
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
	run_loop.stages = stages
	run_loop.stage_cleared.connect(_on_stage_cleared)
	run_loop.stage_starting.connect(_on_stage_starting)
	run_loop.exit_opened.connect(_on_exit_opened)
	var session := RunState.session
	if session != null:
		# PLAN v8 1.2: the session's goal; the AI hands things over itself, no prompts.
		run_loop.set_goal(session.goal, session.goal_value, session.time_limit)
		shell.director.enabled = false
	run_loop.begin()
	var missing := Unlocks.missing_basics()
	if session == null and not missing.is_empty():
		# A build that misses a basic (PLAN v5 4.8) plays a short smoke test: no prompts.
		run_loop.smoke_duration = Tuning.smoke_test_duration
		if missing[0] == &"movement":
			run_loop.smoke_stop_at = Tuning.smoke_stop_time
			run_loop.smoke_stop_line = SMOKE_STOP_LINE
		shell.director.enabled = false
		if shell.transition:
			shell.transition.say(smoke_line(missing))
	run_loop.phase_changed.connect(func(phase: StringName) -> void:
		if phase == RunLoop.RELEASE_CANDIDATE and shell.sound:
			shell.sound.play(&"release_candidate", 0.0))


## The AI gives up on the build that cannot move (owner, 2026-11-22).
const SMOKE_STOP_LINE := "Okay. We're not going anywhere. Stopping the test."


## The AI's line at the start of a smoke test, about the first basic still missing.
static func smoke_line(missing: Array[StringName]) -> String:
	match missing[0]:
		&"movement":
			return "Smoke test. Movement is not in yet: aim and shoot, that is all."
		&"enemies":
			return "Smoke test. You can move now. There is nothing to shoot yet."
		_:
			return "Smoke test. Something basic is still missing."


func _build_arena(def: ArenaDef) -> void:
	arena = Arena.new(def)
	arena.name = "Arena"
	if not Unlocks.has_basic(&"level"):
		arena.strip_layout()   # PLAN v5 4.8: no level yet, an empty box
	add_child(arena)
	move_child(arena, 0)   # drawn under the world, as when it was built first


## The stage is over: its enemies, shots and patch leftovers go; the player stays.
func _on_stage_cleared(index: int) -> void:
	_clear_field()
	stage_ended.emit(index)


## The next stage: a fresh field, its arena, the player at its start.
func _on_stage_starting(_index: int, stage: StageDef) -> void:
	_clear_field()
	var old := arena
	remove_child(old)
	old.queue_free()
	_build_arena(stage.arena)
	spawner.arena = arena
	turn_clock.arena = arena
	if not (stages.keep_position and _clear_spot(player.global_position)):
		player.global_position = arena.player_start
	player.velocity = Vector2.ZERO
	var rig := camera as CameraRig
	rig.set_bounds(arena.bounds)
	rig.global_position = player.global_position
	rig.reset_smoothing()
	for node in get_tree().get_nodes_in_group(FOLLOW_GROUP):
		if node is Node2D and world.is_ancestor_of(node) and not node.is_queued_for_deletion():
			(node as Node2D).global_position = spawner.pick_point()


## Shifting keeps the player in place when the new layout leaves the spot free.
func _clear_spot(p: Vector2) -> bool:
	return arena.distance_to_blocks(p) >= Tuning.TILE * 0.5


## Breakout: the exit gate opens on the far side; reaching it ends the stage.
func _on_exit_opened(_index: int) -> void:
	var gate := ExitGate.new()
	gate.name = "ExitGate"
	world.add_child(gate)
	gate.setup(arena, player)
	gate.reached.connect(run_loop.reach_exit)


## Twice: now, and once the spawns queued this tick have entered the tree (RunState.spawn
## adds them deferred), so nothing spawned on the clearing tick survives it.
func _clear_field() -> void:
	_sweep()
	_sweep.call_deferred()


func _sweep() -> void:
	if not is_instance_valid(world):
		return
	for child in world.get_children():
		if child == player or child.is_in_group(KEEP_GROUP) or child.is_in_group(FOLLOW_GROUP) 				or child.is_queued_for_deletion():
			continue
		child.queue_free()


func run_record() -> Dictionary:
	return run_loop.record


func session_clock() -> float:
	return run_loop.goal_clock


func session_progress() -> float:
	return run_loop.goal_pct()


func hold_session_clock(owner_id: StringName, on: bool) -> void:
	run_loop.hold_clock(owner_id, on)
	_sync_spawner()


## Places `count` enemies of `archetype` at the spawner's off-screen points (a cue).
func spawn_archetype(archetype: StringName, count: int) -> bool:
	if not Spawner.SCENES.has(archetype):
		return false
	for i in count:
		var rng := RunState.gameplay_rng
		var jitter := Vector2(rng.randf_range(-16, 16), rng.randf_range(-16, 16))
		RunState.spawn(Spawner.SCENES[archetype], spawner.pick_point() + jitter, {&"from_spawner": true})
	return true


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
