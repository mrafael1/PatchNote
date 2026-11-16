class_name Feedback
extends Node
## Hit feedback. Presentation only: it listens to gameplay events and never changes
## gameplay state. Hit flash, death puff, screen shake when the player is hurt.

const PUFF_COUNT := 12

var camera: CameraRig
var effects_parent: Node


func _ready() -> void:
	EventBus.entity_damaged.connect(_on_entity_damaged)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_hit.connect(_on_player_hit)


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


func puff(pos: Vector2, color: Color) -> void:
	if not is_instance_valid(effects_parent):
		return
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = PUFF_COUNT
	p.lifetime = 0.45
	p.spread = 180.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 240.0
	p.scale_amount_min = 4.0
	p.scale_amount_max = 8.0
	p.color = color
	# Debris falls when the world has gravity.
	var rules := RunState.rules
	p.gravity = rules.gravity_dir.normalized() * rules.gravity_strength * 0.5 if rules.gravity_enabled else Vector2.ZERO
	p.position = pos
	p.finished.connect(p.queue_free)
	effects_parent.add_child(p)
	p.emitting = true
