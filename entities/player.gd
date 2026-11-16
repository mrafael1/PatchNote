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
	mover.use_rule_jumps = true
	mover.jumped.connect(func() -> void: EventBus.player_jumped.emit())
	mover.landed.connect(_on_landed)
	set_input(HumanInput.new())
	RunState.register_entity(self, kind)


## Swap who is driving: HumanInput, BotInput, or a scripted provider in tests.
func set_input(provider: PlayerInput) -> void:
	if input:
		remove_child(input)
		input.queue_free()
	input = provider
	input.name = "Input"
	add_child(input)


func set_bot(on: bool) -> void:
	set_input(BotInput.new() if on else HumanInput.new())


func is_bot() -> bool:
	return input is BotInput


func _physics_process(_delta: float) -> void:
	mover.speed = Tuning.player_speed
	mover.accel = Tuning.player_accel
	mover.friction = Tuning.player_friction
	if health.dead:
		mover.wish = Vector2.ZERO
		mover.jump_held = false
		return
	mover.wish = input.move
	mover.jump_held = input.jump_held
	if input.jump_pressed:
		mover.request_jump()


func _process(_delta: float) -> void:
	_aim.rotation = input.aim_dir.angle()
	# Blink while invulnerable after a hit.
	modulate.a = 0.45 if health.is_invulnerable() and not health.dead else 1.0


func _on_landed(impact_speed: float) -> void:
	if impact_speed >= Tuning.landing_min_speed:
		EventBus.player_landed.emit(global_position, impact_speed)
