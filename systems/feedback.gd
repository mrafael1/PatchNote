class_name Feedback
extends Node
## Hit feedback. Presentation only: it listens to gameplay events and never changes
## gameplay state. Hit flash, particles (death puff, wall sparks, landing dust, dash
## trail, explosion sparks, player hit burst), screen shake.

const PUFF_COUNT := 12
const MAX_LIVE_EFFECTS := 80   ## beyond this, new bursts are skipped (a horde of bounces)
const DUST := Color(0.75, 0.78, 0.85)
const HIT := Color(1.0, 0.35, 0.35)

var camera: CameraRig
var effects_parent: Node

var _live := 0


func _ready() -> void:
	EventBus.entity_damaged.connect(_on_entity_damaged)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_hit.connect(_on_player_hit)
	EventBus.projectile_hit_wall.connect(_on_hit_wall)
	EventBus.player_landed.connect(_on_player_landed)
	EventBus.player_dashed.connect(_on_player_dashed)
	EventBus.explosion.connect(_on_explosion)


func _on_entity_damaged(target: Node, _info: RefCounted) -> void:
	var visual := target.get_node_or_null("Visual") as RectVisual
	if visual:
		visual.flash()


func _on_enemy_killed(enemy: Node, _info: RefCounted) -> void:
	var visual := enemy.get_node_or_null("Visual") as RectVisual
	var color := visual.color if visual else Color.WHITE
	puff((enemy as Node2D).global_position, color)


func _on_player_hit(_info: RefCounted) -> void:
	if camera:
		camera.shake(9.0)
	var player := _player()
	if player:
		burst(player.global_position, HIT, 10, 120.0, 260.0, 0.35, 5.0)


func _on_hit_wall(projectile: Node, pos: Vector2, normal: Vector2) -> void:
	var visual := projectile.get_node_or_null("Visual") as RectVisual if is_instance_valid(projectile) else null
	var color := visual.color if visual else Color.WHITE
	burst(pos, color, 5, 60.0, 180.0, 0.18, 3.0, normal, 70.0)


func _on_player_landed(pos: Vector2, impact_speed: float) -> void:
	var rules := RunState.rules
	var up := -rules.gravity_dir.normalized() if rules.gravity_enabled else Vector2.UP
	var amount := int(clampf(impact_speed / 60.0, 6.0, 16.0))
	burst(pos - up * 16.0, DUST, amount, 50.0, 160.0, 0.35, 4.0, up, 80.0, 0.3)
	if camera and impact_speed > 700.0:
		camera.shake(4.0)


func _on_player_dashed() -> void:
	var player := _player()
	if player:
		burst(player.global_position, Color(0.4, 0.9, 1.0, 0.8), 10, 20.0, 90.0, 0.3, 6.0)


func _on_explosion(pos: Vector2, radius: float) -> void:
	burst(pos, Color(1.0, 0.75, 0.3), int(clampf(radius / 6.0, 8.0, 20.0)), radius * 1.5, radius * 3.5, 0.3, 4.0)
	if camera:
		camera.shake(3.0)


func puff(pos: Vector2, color: Color) -> void:
	burst(pos, color, PUFF_COUNT, 90.0, 240.0, 0.45, 6.0, Vector2.ZERO, 180.0, 0.5)


## One-shot CPUParticles2D. dir == ZERO means all directions. gravity_scale scales
## the world gravity (debris falls only when the world has gravity).
func burst(pos: Vector2, color: Color, amount: int, speed_min: float, speed_max: float,
		lifetime: float, size: float, dir := Vector2.ZERO, spread := 180.0, gravity_scale := 0.0) -> void:
	if not is_instance_valid(effects_parent) or _live >= MAX_LIVE_EFFECTS:
		return
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.direction = dir if dir != Vector2.ZERO else Vector2.RIGHT
	p.spread = spread if dir != Vector2.ZERO else 180.0
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.damping_min = speed_min * 0.5
	p.damping_max = speed_max
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.3
	p.color = color
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	var rules := RunState.rules
	p.gravity = rules.gravity_dir.normalized() * rules.gravity_strength * gravity_scale \
			if rules.gravity_enabled and gravity_scale > 0.0 else Vector2.ZERO
	p.position = pos
	_live += 1
	p.finished.connect(_on_effect_finished.bind(p))
	effects_parent.add_child(p)
	p.emitting = true


func live_effects() -> int:
	return _live


func _on_effect_finished(p: CPUParticles2D) -> void:
	_live -= 1
	p.queue_free()


func _player() -> Node2D:
	return get_tree().get_first_node_in_group(&"player") as Node2D
