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
var hot_edges: HotEdges


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
		dasher.aims = Unlocks.dash_aims()
	player.set(&"damage_locked", not Unlocks.has_basic(&"health"))
	# M47.7b (PLAN 0.9.1): movement lands on a player whose start carries a tried direction:
	# the handover slide, once. A zero direction touches nothing.
	if carried_tried != Vector2.ZERO and Unlocks.has_basic(&"movement"):
		player.call(&"start_slide", carried_tried)
		carried_tried = Vector2.ZERO


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
	if id == &"level" and arena != null and arena.stripped():
		arena.grow_layout()   # M47.6c1 (design 3, S4): the walls grow in, from the middle out
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
	spawner.enabled = _spawner_wanted() and not (run_loop != null and (run_loop.clock_held() or run_loop.is_over()
			or run_loop.quiet_tail()))   # M47.6c1: a script ending's tail is quiet (budget sessions)


func build(p_shell: Node) -> void:
	super(p_shell)
	# A smoke-test build (PLAN v5 4.8) is one short stage, whatever the set. A campaign
	# session (PLAN v8) plays one stage on its own arena.
	# M50.3c (PLAN v9 1.8): a session with `stages` plays that set (the layout the player
	# picked); the set is shared data, so the session's spawn multipliers go to the run loop.
	if RunState.session != null and RunState.session.stage_set() != null:
		stages = RunState.session.stage_set()
	elif RunState.session != null:
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
	player.position = start_for(carried_start)   # M47.6c2: the carried spot, else player_start
	var tried_in := carried_tried   # M47.7b: apply_basics() consumes it
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
	if player.position != arena.player_start:
		rig.carry_lead(carried_lead)   # M47.6c2: the view the player had (presentation)

	var tint := TimeTint.new()
	tint.name = "TimeTint"
	add_child(tint)

	spawner = Spawner.new()
	spawner.name = "Spawner"
	spawner.arena = arena
	spawner.player = player
	spawner.enabled = _spawner_wanted()
	if RunState.session != null:
		spawner.hold = RunState.session.spawn_after   # M48b (D10): S9's quiet start
		# M47.6c1 (design 2.6): a clear ending's budget, and the session's spawn weights.
		if RunState.session.has_end(SessionDef.CLEAR):
			spawner.budget = enemy_total_now(RunState.session)   # M47.6d2: per path
		spawner.weights = spawn_weights_for(RunState.session)
	add_child(spawner)

	run_loop = RunLoop.new()
	run_loop.name = "RunLoop"
	# M14 ran the loop after the Director and the Transition; the priority keeps that
	# order now that the loop sits in the genre, ahead of the shell's nodes.
	run_loop.process_physics_priority = 1
	run_loop.start_point = player.position   # M47.6c2: the record's and the bot line's start
	run_loop.start_tried = tried_in          # M47.7b: ... and its tried direction (tools)
	add_child(run_loop)

	# M50.3c: edit_hot_edges' band (inert while the rule is 0).
	hot_edges = HotEdges.new()
	hot_edges.name = "HotEdges"
	hot_edges.genre = self
	add_child(hot_edges)


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
		# M45a (PLAN v9 1.2): a kills goal is multiplied by the session's path's
		# kill_goal_mult (Auto x2); survive goals never scale; a tryout swap never rescales.
		# M47.2: goal_by_path (S8 Survival 90 s) picks the value for the live path.
		var path := RunState.path_def()
		var goal_value := session.goal_for(path.id if path != null else &"")
		if session.goal == SessionDef.KILLS and path != null:
			goal_value = roundf(goal_value * path.kill_goal_mult)
		# M47.6c1 (design 2.6): clear / script are endings: the value is the set or the tail.
		if session.goal == SessionDef.CLEAR:
			goal_value = float(enemy_total_now(session))
		elif session.goal == SessionDef.SCRIPT:
			goal_value = session.end_after
		run_loop.set_goal(session.goal, goal_value, session.time_limit)
		run_loop.set_endings(session.end_kinds(), enemy_total_now(session) if session.has_end(SessionDef.CLEAR) else -1,
				session.end_after)
		run_loop.script_window_opened.connect(_sync_spawner)
		if stages.size() > 1:
			run_loop.rate_mult = session.spawn_rate   # M50.3c: on top of each part's preset
			run_loop.cap_mult = session.spawn_cap
			run_loop.part_rate = session.part_rate    # M51: S11's part 3 at x0.8
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


## M47.6d2 (design 3, S8 / S9): the fixed set the session plays on the live path
## (enemy_total_by_path, else enemy_total).
static func enemy_total_now(session: SessionDef) -> int:
	var path := RunState.path_def()
	return session.enemy_total_for(path.id if path != null else &"")


## M47.6c1: a session's spawn_weights with each "fork:<id>" key read as that fork's enemy
## (SessionRunner's reading); an unanswered fork is left out.
static func spawn_weights_for(session: SessionDef) -> Dictionary:
	var out := {}
	for k: Variant in session.spawn_weights:
		var arch := SessionRunner._resolve_archetype(StringName(String(k)))
		# M51 (PLAN v9 1.9): a variant (S11's shielder / sniper / swarm) keeps its weight too.
		if arch != &"" and (Spawner.SCENES.has(arch) or EnemyDB.variant(arch) != null):
			out[arch] = float(out.get(arch, 0.0)) + float(session.spawn_weights[k])
	return out


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
## M47.6c2 (design 2.7): where the player starts: a carried spot (Main.next_start) when it
## is inside the arena, clear of every block (half a tile) and reachable from player_start.
## A spot hugging a wall (the player stood against it) moves to the nearest free tile centre
## (the walls' own push-out, Arena.free_tile_near) when that one is reachable, so the room does
## not visibly jump; else the arena's player_start. A cold start (INF) reads nothing.
func start_for(carried: Vector2) -> Vector2:
	if RunState.session != null and RunState.session.fresh_start:
		return arena.player_start   # M47.6d2: S9's specimen is placed from player_start
	if not carried.is_finite() or not arena.bounds.has_point(carried):
		return arena.player_start
	if _clear_spot(carried) and arena.is_reachable(carried):
		return carried
	var near := arena.free_tile_near(carried)
	if near != carried and _clear_spot(near) and arena.is_reachable(near):
		return near
	return arena.player_start


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


func hold_session_goal(owner_id: StringName, on: bool) -> void:
	run_loop.hold_goal(owner_id, on)


## Places `count` enemies of `archetype` at the spawner's off-screen points (a cue).
func spawn_archetype(archetype: StringName, count: int) -> bool:
	# M47 (PLAN v9 1.9): a variant spawns its base scene carrying its data.
	var v := EnemyDB.variant(archetype)
	var base := v.base if v != null else archetype
	if not Spawner.SCENES.has(base):
		return false
	for i in count:
		var rng := RunState.gameplay_rng
		var jitter := Vector2(rng.randf_range(-16, 16), rng.randf_range(-16, 16))
		var at := spawner.pick_point()
		if v == null:
			RunState.spawn(Spawner.SCENES[base], at + jitter, {&"from_spawner": true})
		else:
			# M50.3c: a pack variant (the swarm) brings the rest of its pack around the same
			# marker. M51: through the spawner's helper (the same draws in the same order).
			Spawner.spawn_variant(v, at, jitter)
	return true


## M48b (PLAN 1.7.1, D9): `count` specimens of a walker `archetype`, in view: 4 tiles right
## of the arena's start (1.5 tiles apart in y), each snapped to the nearest reachable tile
## centre, no jitter, no RNG. They stand still, take and deal no damage until
## release_specimens(). False for a non-walker.
const SPECIMEN_OFFSET := Vector2(4.0, 0.0)   ## tiles from player_start
const SPECIMEN_GAP := 1.5                    ## tiles between two specimens (y)


func spawn_specimens(archetype: StringName, count: int) -> bool:
	var v := EnemyDB.variant(archetype)
	var base := v.base if v != null else archetype
	if not base in SessionDef.SPECIMEN_BASES or not Spawner.SCENES.has(base):
		return false
	var t := Tuning.TILE
	for i in count:
		var want := arena.player_start + (SPECIMEN_OFFSET + Vector2(0.0, SPECIMEN_GAP * i)) * t
		var params := {&"from_spawner": true, &"specimen": true}
		if v != null:
			params.merge({&"variant": v.id, &"size_mult": v.scale, &"hp_mult": v.hp_mult})
		RunState.spawn(Spawner.SCENES[base], _nearest_open_tile(want), params)
	return true


## The centre of the reachable tile nearest `p` (rings of growing radius, row-major).
func _nearest_open_tile(p: Vector2) -> Vector2:
	var t := Tuning.TILE
	var c := Vector2i(int(floorf(p.x / t)), int(floorf(p.y / t)))
	for radius in 8:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var centre := (Vector2(c + Vector2i(dx, dy)) + Vector2(0.5, 0.5)) * t
				if arena.is_reachable(centre):
					return centre
	return p


## M48b: every specimen fights from now on (tree order).
func release_specimens() -> void:
	for node in get_tree().get_nodes_in_group(&"specimen"):
		if is_instance_valid(node):
			node.set(&"specimen", false)


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
