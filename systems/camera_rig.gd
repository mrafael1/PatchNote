class_name CameraRig
extends Camera2D
## Follows a target inside the arena. Zoom is derived from the rules, never stored.
## The camera never rotates. It leads toward the target's aim by
## Tuning.camera_lookahead of the view, smoothed (PLAN v5 2.2); the arena limits
## still clamp the view. Shake is scaled by the look (Look.preset.shake_scale, 1.7).

const ZOOM_LERP := 6.0

const SHAKE_DECAY := 40.0

var target: Node2D

var _shake := 0.0
var _lead := Vector2.ZERO


## Presentation only: jolt the view by up to `pixels`, fading out quickly.
## Halved with the "reduce flashing" setting (PLAN v8 1.9).
func shake(pixels: float) -> void:
	var scale := Look.preset.shake_scale * (0.5 if SaveGame.reduce_flashing() else 1.0)
	_shake = maxf(_shake, pixels * scale)


func shake_left() -> float:
	return _shake


func _init() -> void:
	# M48b: a look's physics interpolation (Skins.apply_motion) is on before the camera is
	# built in S9: say physics mode up front, as the engine would force it on entering the
	# tree anyway (no warning then). The project's own setting (tier 0): untouched.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.physics_interpolation:
		process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


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
		var weight := clampf(Tuning.camera_lookahead_lerp * delta, 0.0, 1.0)
		_lead = _lead.lerp(lead_for(_aim_dir()), weight)
		global_position = target.global_position + _lead
	if _shake > 0.0:
		offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
	else:
		offset = Vector2.ZERO
	var wanted := Vector2.ONE * RunState.rules.camera_zoom
	zoom = zoom.lerp(wanted, clampf(ZOOM_LERP * delta, 0.0, 1.0))


## Where the camera leads for an aim direction: a share of the view, in world units.
func lead_for(aim: Vector2) -> Vector2:
	if aim == Vector2.ZERO:
		return Vector2.ZERO
	var view := get_viewport_rect().size / zoom
	return aim.normalized() * view * Tuning.camera_lookahead


func lead() -> Vector2:
	return _lead


func _aim_dir() -> Vector2:
	var input: Variant = target.get(&"input")
	if input is Object and is_instance_valid(input):
		var aim: Variant = (input as Object).get(&"aim_dir")
		if aim is Vector2:
			return aim
	return Vector2.ZERO
