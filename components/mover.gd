class_name Mover
extends Component
## Moves its CharacterBody2D parent. Whoever controls the entity (player input,
## enemy AI) sets `wish`, `jump_held` and calls request_jump(); the Mover turns that
## into motion according to the current rules. It never stores a "mode": the body
## settings are derived from RunState.rules on every physics tick.

signal jumped
signal landed(impact_speed: float)

var speed := 300.0
var accel := 3200.0
var friction := 3600.0
var jump_speed := 0.0         ## 0 = Tuning.jump_velocity
var use_rule_jumps := false   ## player: jump count comes from rules.jumps
var innate_jumps := 1         ## everyone else
var knockback_scale := 1.0

var wish := Vector2.ZERO      ## desired direction, length 0..1
var jump_held := false
var height := 0.0             ## distance above the ground plane when gravity is off (0 = grounded)

var _buffer := 0.0
var _coyote := 0.0
var _air_jumps_used := 0
var _cut_available := false
var _was_on_floor := false
var _gravity_key := Vector3(-1, 0, 0)   ## (enabled, dir.x, dir.y) seen last tick
var _dash_left := 0.0
var _dash_velocity := Vector2.ZERO
var _hop_t := -1.0             ## seconds into the current hop, -1 = not hopping


## Ask for a jump. It happens as soon as it is allowed, within the buffer window.
func request_jump() -> void:
	_buffer = Tuning.jump_buffer


func is_grounded() -> bool:
	var body := get_parent() as CharacterBody2D
	return body != null and RunState.rules.gravity_enabled and body.is_on_floor()


func max_jumps() -> int:
	return RunState.rules.jumps if use_rule_jumps else innate_jumps


## Does nothing under turn-based (B2): bodies move only by whole tiles.
func knockback(impulse: Vector2) -> void:
	if RunState.rules.turn_based:
		return
	var body := get_parent() as CharacterBody2D
	if body:
		body.velocity += impulse * knockback_scale


## Move at a fixed velocity for a short time, ignoring input and gravity.
func dash(velocity: Vector2, duration: float) -> void:
	_dash_velocity = velocity
	_dash_left = duration


## Ends any dash and drops the speed the body has, except falling under gravity.
## B2 calls it at every turn end so the player stops exactly on its tile.
func stop() -> void:
	_dash_left = 0.0
	var body := get_parent() as CharacterBody2D
	if body == null:
		return
	var rules := RunState.rules
	if rules.gravity_enabled and not ignores_gravity():
		var g := rules.gravity_dir.normalized()
		body.velocity = g * maxf(body.velocity.dot(g), 0.0)
	else:
		body.velocity = Vector2.ZERO


## Off the ground plane (hopping without gravity): passes over ground-level things.
func is_airborne() -> bool:
	return height > 0.0


func is_dashing() -> bool:
	return _dash_left > 0.0


## Entities with a Floating component ignore gravity entirely.
func ignores_gravity() -> bool:
	return Component.find(get_parent(), Floating) != null


func _physics_process(delta: float) -> void:
	var body := get_parent() as CharacterBody2D
	if body == null:
		return
	var rules := RunState.rules
	var falls := rules.gravity_enabled and not ignores_gravity()
	var g_dir := rules.gravity_dir.normalized() if falls else Vector2.ZERO
	var key := Vector3(1.0 if falls else 0.0, g_dir.x, g_dir.y)
	if key != _gravity_key:
		_on_gravity_changed(body, Vector2(_gravity_key.y, _gravity_key.z), g_dir)
		_gravity_key = key
	if _dash_left > 0.0:
		_tick_dash(body, falls, g_dir, delta)
	elif falls:
		_tick_gravity(body, rules, g_dir, delta)
	else:
		_tick_flat(body, delta)


## Gravity turned on, off or changed direction: drop any speed along the old and
## new gravity axes so nobody keeps flying, and forget jump bookkeeping.
func _on_gravity_changed(body: CharacterBody2D, old_dir: Vector2, new_dir: Vector2) -> void:
	for d: Vector2 in [old_dir, new_dir]:
		if d != Vector2.ZERO:
			body.velocity -= d * body.velocity.dot(d)
	_buffer = 0.0
	_coyote = 0.0
	_air_jumps_used = 0
	_cut_available = false
	_was_on_floor = false
	_hop_t = -1.0
	height = 0.0


func _tick_dash(body: CharacterBody2D, falls: bool, g_dir: Vector2, delta: float) -> void:
	if falls:
		body.motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
		body.up_direction = -g_dir
	else:
		body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		_tick_hop(delta)
	body.velocity = _dash_velocity
	body.move_and_slide()
	_dash_left -= delta
	if _dash_left <= 0.0:
		# Leave the dash at normal speed, with no speed along the gravity axis.
		var exit := _dash_velocity.normalized() * speed
		body.velocity = exit - g_dir * exit.dot(g_dir)
		_was_on_floor = false


func _tick_flat(body: CharacterBody2D, delta: float) -> void:
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	body.wall_min_slide_angle = 0.0
	var target := wish.limit_length(1.0) * speed
	var rate := accel if wish != Vector2.ZERO else friction
	body.velocity = body.velocity.move_toward(target, rate * delta)
	body.move_and_slide()
	_tick_hop(delta)


## Without gravity a jump is a hop on the height axis: a fixed arc, no air jumps.
func _tick_hop(delta: float) -> void:
	_buffer -= delta
	if _hop_t < 0.0:
		if _buffer > 0.0 and max_jumps() >= 1 and not ignores_gravity():
			_buffer = 0.0
			_hop_t = 0.0
			height = 0.01
			jumped.emit()
		return
	_hop_t += delta
	var u := _hop_t / Tuning.hop_time
	if u >= 1.0:
		_hop_t = -1.0
		height = 0.0
		landed.emit(Tuning.hop_impact_speed)
	else:
		height = maxf(0.01, 4.0 * Tuning.hop_height * u * (1.0 - u))


func _tick_gravity(body: CharacterBody2D, rules: WorldRules, g_dir: Vector2, delta: float) -> void:
	body.motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	body.up_direction = -g_dir
	body.floor_snap_length = 6.0

	# Split velocity into "along gravity" (positive = falling) and lateral.
	var v_fall := body.velocity.dot(g_dir)
	var v_lateral := body.velocity - g_dir * v_fall

	# Lateral: the input with its gravity-axis part removed, so left stays left on
	# screen whichever way gravity points.
	var w := wish.limit_length(1.0)
	var lateral_wish := w - g_dir * w.dot(g_dir)
	var rate := accel if lateral_wish.length() > 0.01 else friction
	v_lateral = v_lateral.move_toward(lateral_wish * speed, rate * delta)

	var on_floor := body.is_on_floor()
	var pull := rules.gravity_strength * (Tuning.fall_gravity_mult if v_fall > 0.0 else 1.0)
	v_fall = minf(v_fall + pull * delta, Tuning.terminal_fall_speed)

	if on_floor:
		_coyote = Tuning.coyote_time
		_air_jumps_used = 0
	else:
		_coyote -= delta
	_buffer -= delta

	if _buffer > 0.0:
		var allowed := max_jumps()
		var launch := jump_speed if jump_speed > 0.0 else Tuning.jump_velocity
		if allowed >= 1 and _coyote > 0.0:
			v_fall = -launch
			_start_jump()
		elif _coyote <= 0.0 and _air_jumps_used < allowed - 1:
			v_fall = -launch * Tuning.air_jump_factor
			_air_jumps_used += 1
			_start_jump()

	# Variable jump height: releasing the button early cuts the rise once.
	if _cut_available and not jump_held and v_fall < 0.0:
		v_fall *= Tuning.jump_cut_factor
		_cut_available = false
	if v_fall >= 0.0:
		_cut_available = false

	var impact := v_fall
	body.velocity = v_lateral + g_dir * v_fall
	body.move_and_slide()

	var now_on_floor := body.is_on_floor()
	if now_on_floor and not _was_on_floor:
		landed.emit(maxf(impact, 0.0))
	_was_on_floor = now_on_floor


func _start_jump() -> void:
	_buffer = 0.0
	_coyote = 0.0
	_cut_available = true
	_was_on_floor = false
	jumped.emit()
