extends CharacterBody2D
## Chaser: runs at the player and hurts on contact.
## M1: straight-line steering plus a soft push away from other enemies (enemy bodies
## do not collide with each other). Obstacle avoidance and gravity behaviour come later.

var kind: StringName = &"enemy"
var generation := 0

@onready var mover: Mover = $Mover
@onready var health: Health = $Health


func _ready() -> void:
	health.base_max_hp = Tuning.chaser_hp
	health.died.connect(_on_died)
	RunState.register_entity(self, kind)


func _physics_process(_delta: float) -> void:
	mover.speed = Tuning.chaser_speed
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		mover.wish = Vector2.ZERO
		return
	var to_player := player.global_position - global_position
	mover.wish = (to_player.normalized() + _separation()).limit_length(1.0)
	if to_player.length() <= Tuning.contact_range:
		var target := Component.find(player, Health) as Health
		if target:
			target.take(DamageInfo.make(Tuning.chaser_contact_damage, &"contact", &"enemy", global_position))


func _separation() -> Vector2:
	var push := Vector2.ZERO
	var radius := Tuning.enemy_separation_radius
	for other in get_tree().get_nodes_in_group(&"enemy"):
		if other == self:
			continue
		var away: Vector2 = global_position - (other as Node2D).global_position
		var dist := away.length()
		if dist > 0.01 and dist < radius:
			push += away / dist * (1.0 - dist / radius)
	return push


func _on_died(_info: DamageInfo) -> void:
	queue_free()
