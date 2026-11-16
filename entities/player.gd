extends CharacterBody2D
## The player entity. Control comes only from its PlayerInput child.

var kind: StringName = &"player"
var input: PlayerInput

@onready var mover: Mover = $Mover
@onready var health: Health = $Health
@onready var _aim: Node2D = $Aim


func _ready() -> void:
	health.base_max_hp = Tuning.player_max_hp
	health.invuln_time = Tuning.player_hit_invuln
	set_bot(false)
	RunState.register_entity(self, kind)


func set_bot(on: bool) -> void:
	if input:
		remove_child(input)
		input.queue_free()
	input = BotInput.new() if on else HumanInput.new()
	input.name = "Input"
	add_child(input)


func is_bot() -> bool:
	return input is BotInput


func _physics_process(_delta: float) -> void:
	mover.speed = Tuning.player_speed
	mover.accel = Tuning.player_accel
	mover.friction = Tuning.player_friction
	mover.wish = Vector2.ZERO if health.dead else input.move


func _process(_delta: float) -> void:
	_aim.rotation = input.aim_dir.angle()
	# Blink while invulnerable after a hit.
	modulate.a = 0.45 if health.is_invulnerable() and not health.dead else 1.0
