class_name Shooter
extends Component
## Fires projectiles on a cooldown. One Shooter per entity: anything that wants to
## fire (manual input, later auto-attack) goes through try_fire, so the fire rate
## never stacks.

const PROJECTILE := preload("res://entities/projectile.tscn")

var cooldown := 0.18
var projectile_speed := 900.0
var damage := 1.0
var faction: StringName = &"player"
var muzzle_offset := 26.0

var _ready_in := 0.0


func _physics_process(delta: float) -> void:
	_ready_in = maxf(0.0, _ready_in - delta)


func can_fire() -> bool:
	return _ready_in <= 0.0


## Returns the projectile, or null if on cooldown or at the projectile cap. auto marks
## a shot the weapon fired by itself (auto_attack).
func try_fire(dir: Vector2, auto := false) -> Node:
	if _ready_in > 0.0 or dir == Vector2.ZERO:
		return null
	var shooter := get_parent() as Node2D
	var from := shooter.global_position
	var aim := dir.normalized()
	var muzzle := from + aim * muzzle_offset
	# Never start a projectile inside or behind a wall.
	var query := PhysicsRayQueryParameters2D.create(from, muzzle, Tuning.LAYER_WORLD)
	if not shooter.get_world_2d().direct_space_state.intersect_ray(query).is_empty():
		muzzle = from
	var projectile := RunState.spawn(PROJECTILE, muzzle, {
		&"kind": &"player_projectile" if faction == &"player" else &"enemy_projectile",
		&"faction": faction,
		&"velocity": aim * projectile_speed,
		&"damage": damage,
		&"auto_fired": auto,
	})
	if projectile == null:
		return null
	_ready_in = cooldown
	EventBus.projectile_fired.emit(projectile)
	return projectile
