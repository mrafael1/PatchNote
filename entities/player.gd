extends CharacterBody2D
## The player entity. Control comes only from its PlayerInput child.

var kind: StringName = &"player"
var input: PlayerInput

var _facing := Vector2.RIGHT
## The first build has no movement yet (PLAN v5 4.8): it can aim and shoot, nothing
## else. The genre sets this from Unlocks when it builds the run.
var movement_locked := false
## The campaign's first sessions have no gun and no dash yet either (owner, 2026-11-23):
## the genre sets these from the session's basics (Unlocks.has_basic).
var shooting_locked := false
var dash_locked := false
## Before the session has `health` (owner, M39.2) nothing hurts the player: enemies
## reach it and nothing happens.
var damage_locked := false

@onready var mover: Mover = $Mover
@onready var health: Health = $Health
@onready var shooter: Shooter = $Shooter
@onready var dasher: Dasher = $Dasher
@onready var loadout: Loadout = $Loadout   ## M44: every shot goes through it (the pistol at rank 1 is today's)
@onready var _aim: Node2D = $Aim
@onready var _visual: RectVisual = $Visual

var _shadow: RectVisual


func _ready() -> void:
	health.base_max_hp = Tuning.player_max_hp
	health.invuln_time = Tuning.player_hit_invuln
	mover.use_rule_jumps = true
	mover.jumped.connect(func() -> void: EventBus.player_jumped.emit())
	mover.landed.connect(_on_landed)
	dasher.dashed.connect(func() -> void: EventBus.player_dashed.emit())
	dasher.hooked.connect(func(a: Vector2) -> void: EventBus.player_hooked.emit(a))
	dasher.hook_missed.connect(func(f: Vector2, t: Vector2) -> void: EventBus.player_hook_missed.emit(f, t))
	dasher.teleported.connect(func(f: Vector2, t: Vector2) -> void: EventBus.player_teleported.emit(f, t))
	dasher.fizzled.connect(func() -> void: EventBus.player_dash_fizzled.emit())
	shooter.faction = &"player"
	set_input(HumanInput.new())
	# Shadow left on the ground while the body is up on the height axis.
	_shadow = RectVisual.new()
	_shadow.size = _visual.size
	_shadow.color = Color(0, 0, 0, 0.4)
	_shadow.visible = false
	_shadow.show_behind_parent = true
	add_child(_shadow)
	move_child(_shadow, 0)
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
	mover.speed = Tuning.player_speed * RunState.rules.player_speed_mult
	mover.accel = Tuning.player_accel
	mover.friction = Tuning.player_friction
	shooter.cooldown = Tuning.shoot_cooldown
	shooter.projectile_speed = Tuning.projectile_speed
	if health.dead:
		mover.wish = Vector2.ZERO
		mover.jump_held = false
		return
	if RunState.rules.turn_based:
		# B2: the TurnClock turns input into actions; the body only plays them out.
		mover.wish = Vector2.ZERO
		mover.jump_held = true   # a turn's jump is always a full jump
		return   # auto-attack fires only on wait turns: the TurnClock calls auto_fire()
	if movement_locked:
		mover.wish = Vector2.ZERO
		mover.jump_held = false
	else:
		var move := input.move
		var turn := fposmod(RunState.rules.input_rotation_deg, 360.0)
		if turn != 0.0:
			move = move.rotated(deg_to_rad(turn))   # edit_inverted: the controls turn, aim does not
		mover.wish = move
		if move.length() > 0.2:
			_facing = move.normalized()
		mover.jump_held = input.jump_held
		if input.jump_pressed:
			mover.request_jump()
		if input.dash_pressed and not dash_locked:
			# Both directions: the dasher picks (M42.2). The aim is not turned, like the gun.
			dasher.use(_facing, input.aim_dir)
	if shooting_locked:
		return
	if input.switch_step != 0:
		loadout.switch(input.switch_step)
	if input.fire:
		loadout.try_fire(input.aim_dir)
	elif RunState.rules.auto_attack and loadout.can_fire():
		auto_fire()


## auto_attack: one shot at the nearest visible enemy. Returns true if it fired.
func auto_fire() -> bool:
	var target := _auto_target()
	return target != null and loadout.try_fire(target.global_position - global_position, true)


## Nearest enemy in range with a clear line. Same Shooter, same cooldown as manual fire.
func _auto_target() -> Node2D:
	var best: Node2D = null
	var best_d := Tuning.auto_attack_range * Tuning.auto_attack_range
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var n := e as Node2D
		if n == null or n.is_queued_for_deletion():
			continue
		var d := global_position.distance_squared_to(n.global_position)
		if d < best_d and not EnemyCommon.ray_hits_world(self, global_position, n.global_position):
			best_d = d
			best = n
	return best


func _process(_delta: float) -> void:
	_aim.rotation = input.aim_dir.angle()
	_aim.visible = not shooting_locked   # no gun yet: no barrel
	# Height axis: the body lifts and grows, the shadow stays on the ground.
	var lift := mover.height
	_visual.position = Vector2(0, -lift)
	_aim.position = Vector2(0, -lift)
	_visual.scale = Vector2.ONE * (1.0 + 0.35 * lift / Tuning.hop_height)
	_shadow.visible = lift > 0.0
	# Under reversed gravity the sprite is drawn upside down.
	var rules := RunState.rules
	_visual.scale.y *= -1.0 if rules.gravity_enabled and rules.gravity_dir.y < 0.0 else 1.0
	# Blink while invulnerable (after a hit, during a dash).
	modulate.a = 0.45 if health.is_invulnerable() and not health.dead else 1.0


func _on_landed(impact_speed: float) -> void:
	if impact_speed >= Tuning.landing_min_speed:
		EventBus.player_landed.emit(global_position, impact_speed)
