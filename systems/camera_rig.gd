class_name CameraRig
extends Camera2D
## Follows a target inside the arena. Zoom is derived from the rules, never stored.
## The camera never rotates.

const ZOOM_LERP := 6.0

const SHAKE_DECAY := 40.0

var target: Node2D

var _shake := 0.0


## Presentation only: jolt the view by up to `pixels`, fading out quickly.
func shake(pixels: float) -> void:
	_shake = maxf(_shake, pixels)


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	if is_instance_valid(target):
		global_position = target.global_position
		reset_smoothing()
	zoom = Vector2.ONE * RunState.rules.camera_zoom


func set_bounds(rect: Rect2) -> void:
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.end.x)
	limit_bottom = int(rect.end.y)


func _process(delta: float) -> void:
	if is_instance_valid(target):
		global_position = target.global_position
	if _shake > 0.0:
		offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
	else:
		offset = Vector2.ZERO
	var wanted := Vector2.ONE * RunState.rules.camera_zoom
	zoom = zoom.lerp(wanted, clampf(ZOOM_LERP * delta, 0.0, 1.0))
