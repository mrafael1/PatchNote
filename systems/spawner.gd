class_name Spawner
extends Node
## Wave spawner. Rate and cap follow the rules (spawn_rate_mult, max_enemies), times
## a phase multiplier the run loop will use for the final wave. Enemies appear at
## arena markers that are off-screen and away from the player.

const SCENES := {
	&"chaser": preload("res://entities/enemy_chaser.tscn"),
	&"shooter": preload("res://entities/enemy_shooter.tscn"),
	&"tank": preload("res://entities/enemy_tank.tscn"),
}
const VIEW_HALF := Vector2(640, 360)

var arena: Arena
var player: Node2D
var enabled := true
var phase_rate := 1.0
var phase_cap := 1.0

var _timer := 1.0
var _elapsed := 0.0


func _physics_process(delta: float) -> void:
	if not enabled or not is_instance_valid(player) or arena == null:
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


func pick_type() -> StringName:
	var roll := RunState.gameplay_rng.randf()
	var tank_chance := Tuning.spawn_tank_chance if _elapsed >= Tuning.spawn_tank_delay else 0.0
	if roll < tank_chance:
		return &"tank"
	if roll < tank_chance + Tuning.spawn_shooter_chance:
		return &"shooter"
	return &"chaser"


## A marker outside what the player can see and not too close. Falls back to the
## farthest marker if none qualifies.
func pick_point() -> Vector2:
	var here := player.global_position
	var view := VIEW_HALF / RunState.rules.camera_zoom + Vector2.ONE * Tuning.TILE
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
