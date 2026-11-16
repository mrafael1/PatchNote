class_name CameraRig
extends Camera2D
## Follows a target inside the arena. Zoom is derived from the rules, never stored.
## The camera never rotates.

const ZOOM_LERP := 6.0

var target: Node2D


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
	var wanted := Vector2.ONE * RunState.rules.camera_zoom
	zoom = zoom.lerp(wanted, clampf(ZOOM_LERP * delta, 0.0, 1.0))
