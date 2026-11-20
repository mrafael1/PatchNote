extends CharacterBody2D
## Shooter: keeps its distance, strafes, and fires slow projectiles when it has a
## clear line to the player. It has a Floating component, so gravity never applies.
## On B2's grid (TurnClock.on_grid) it does none of this.

const STRAFE_FLIP_TIME := 2.5

var kind: StringName = &"enemy"
var generation := 0
var from_spawner := false
var size_mult := 1.0   ## smaller or bigger copy (set through spawn params)
var hp_mult := 1.0

var _strafe_sign := 1.0
var _strafe_left := STRAFE_FLIP_TIME

@onready var mover: Mover = $Mover
@onready var health: Health = $Health
@onready var shooter: Shooter = $Shooter


func _ready() -> void:
	health.base_max_hp = Tuning.shooter_hp * hp_mult
	EnemyCommon.apply_size(self, size_mult)
	health.died.connect(func(_info: DamageInfo) -> void: queue_free())
	mover.accel = Tuning.enemy_accel
	shooter.faction = &"enemy"
	shooter.cooldown = Tuning.shooter_fire_interval
	shooter.projectile_speed = Tuning.shooter_projectile_speed
	_strafe_sign = 1.0 if RunState.gameplay_rng.randi() % 2 == 0 else -1.0   # seeded: same seed, same run
	RunState.register_entity(self, kind)


func _physics_process(delta: float) -> void:
	if TurnClock.on_grid(self):
		mover.wish = Vector2.ZERO   # B2: the turn logic moves it and fires its shots
		return
	mover.speed = Tuning.shooter_speed
	var player := EnemyCommon.find_player(self)
	if player == null:
		mover.wish = Vector2.ZERO
		return
	var to_player := player.global_position - global_position
	var distance := to_player.length()
	var dir := to_player / maxf(distance, 0.001)

	_strafe_left -= delta
	if _strafe_left <= 0.0 or get_slide_collision_count() > 0:
		_strafe_sign = -_strafe_sign
		_strafe_left = STRAFE_FLIP_TIME

	var steer := dir.orthogonal() * _strafe_sign
	if distance > Tuning.shooter_far:
		steer = dir
	elif distance < Tuning.shooter_near:
		steer = -dir
	mover.wish = (steer + EnemyCommon.separation(self)).limit_length(1.0)

	if distance <= Tuning.shooter_range and shooter.can_fire() \
			and not EnemyCommon.ray_hits_world(self, global_position, player.global_position):
		shooter.try_fire(dir)
