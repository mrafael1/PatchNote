class_name Spawner
extends Node
## Wave spawner. Rate and cap follow the rules (spawn_rate_mult, max_enemies), times
## a phase multiplier the run loop will use for the final wave. Enemies appear at
## arena markers that are off-screen and away from the player.

## Base scenes by id (EnemyDB.BASES). Spawner.SCENES stays the name the genre and tests read.
static var SCENES: Dictionary = EnemyDB.base_scenes()
const VIEW_HALF := Vector2(640, 360)

var arena: Arena
var player: Node2D
var enabled := true
var phase_rate := 1.0
var phase_cap := 1.0

var _timer := 1.0
var _elapsed := 0.0
## M48b (D10): seconds of enabled spawner time before the first tick counts (a session's
## spawn_after); 0 = today.
var hold := 0.0
var _held := 0.0


func _physics_process(delta: float) -> void:
	if not enabled or not is_instance_valid(player) or arena == null:
		return
	if _held < hold:
		_held += delta
		return
	_elapsed += delta
	_timer -= delta * RunState.rules.spawn_rate_mult * phase_rate
	if _timer > 0.0:
		return
	var ramp := clampf(_elapsed / Tuning.spawn_ramp_time, 0.0, 1.0)
	_timer = lerpf(Tuning.spawn_interval_start, Tuning.spawn_interval_end, ramp)
	if RunState.count(&"enemy") >= current_cap():
		return
	spawn_one()


func current_cap() -> int:
	return int(RunState.rules.max_enemies * phase_cap)


func spawn_one() -> Node:
	var rng := RunState.gameplay_rng
	var jitter := Vector2(rng.randf_range(-16, 16), rng.randf_range(-16, 16))
	return RunState.spawn(SCENES[pick_type()], pick_point() + jitter, {&"from_spawner": true})


## One roll per pick. Archetypes the save has not unlocked (Unlocks.enemies, PLAN v5
## 2.3) never come: a locked type's chance goes to chasers. Bombers never come on the
## parked turn grid (PLAN v5 3: B2 has no bomber role).
func pick_type() -> StringName:
	var allowed := Unlocks.enemies()
	var roll := RunState.gameplay_rng.randf()
	var tank_ok := _elapsed >= Tuning.spawn_tank_delay and allowed.has(&"tank")
	var tank_chance := Tuning.spawn_tank_chance if tank_ok else 0.0
	var shooter_chance := Tuning.spawn_shooter_chance if allowed.has(&"shooter") else 0.0
	var bomber_ok := _elapsed >= Tuning.spawn_bomber_delay and allowed.has(&"bomber") and not RunState.rules.turn_based
	var bomber_chance := Tuning.spawn_bomber_chance if bomber_ok else 0.0
	var lancer_ok := _elapsed >= Tuning.spawn_lancer_delay and allowed.has(&"lancer") and not RunState.rules.turn_based
	var lancer_chance := Tuning.spawn_lancer_chance if lancer_ok else 0.0
	if roll < tank_chance:
		return &"tank"
	if roll < tank_chance + shooter_chance:
		return &"shooter"
	if roll < tank_chance + shooter_chance + bomber_chance:
		return &"bomber"
	if roll < tank_chance + shooter_chance + bomber_chance + lancer_chance:
		return &"lancer"
	if allowed.has(&"chaser") or allowed.is_empty():
		return &"chaser"
	return allowed[0]


## A marker outside what the player can see and not too close. Falls back to the
## farthest marker if none qualifies.
func pick_point() -> Vector2:
	var here := player.global_position
	# The camera leads toward the aim by up to camera_lookahead of the view (PLAN v5 2.2):
	# widen the hidden margin by that much, so no lead shows a fresh spawn. A fixed margin
	# keeps spawning independent of presentation state.
	var view := VIEW_HALF / RunState.rules.camera_zoom * (1.0 + 2.0 * Tuning.camera_lookahead)
	view += Vector2.ONE * Tuning.TILE
	var good: Array[Vector2] = []
	var farthest := arena.spawn_points[0]
	for p in arena.spawn_points:
		var offset := (p - here).abs()
		if p.distance_to(here) > farthest.distance_to(here):
			farthest = p
		if (offset.x > view.x or offset.y > view.y) and p.distance_to(here) >= Tuning.spawn_min_distance:
			good.append(p)
	if good.is_empty():
		return farthest
	return good[RunState.gameplay_rng.randi_range(0, good.size() - 1)]
