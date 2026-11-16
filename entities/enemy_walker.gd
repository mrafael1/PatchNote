extends CharacterBody2D
## Ground enemy that goes for the player and hurts on contact. Used by the chaser
## and the tank; the archetype picks its numbers from Tuning ("chaser_speed", ...).
##
## Without gravity it steers at the player and feels its way around walls. With
## gravity it walks along surfaces and hops: over low walls, and upward when the
## player is above and there is headroom. Under a ledge it keeps walking the way it
## was going instead of turning back, so it comes out from under and can hop up.
## Either way, if it makes no progress for a while it wanders briefly.

@export var archetype: StringName = &"chaser"
@export var half_width := 15.0

var kind: StringName = &"enemy"
var generation := 0
var from_spawner := false

var _contact_damage := 1.0
var _hop_cooldown_time := 0.5
var _walk_dir := Vector2.RIGHT
var _hop_cooldown := 0.0
var _wander_left := 0.0
var _wander_dir := Vector2.RIGHT
var _stuck_time := 0.0
var _best_distance := INF
var _avoid_side := 1.0

@onready var mover: Mover = $Mover
@onready var health: Health = $Health


func _ready() -> void:
	health.base_max_hp = _tuned("hp")
	health.died.connect(_on_died)
	mover.jump_held = true
	mover.accel = Tuning.enemy_accel
	mover.knockback_scale = _tuned("knockback_scale")
	_contact_damage = _tuned("contact_damage")
	_hop_cooldown_time = _tuned("hop_cooldown")
	_avoid_side = 1.0 if get_instance_id() % 2 == 0 else -1.0
	RunState.register_entity(self, kind)


func _tuned(suffix: String) -> float:
	return float(Tuning.get("%s_%s" % [archetype, suffix]))


func _physics_process(delta: float) -> void:
	mover.speed = _tuned("speed")
	_hop_cooldown = maxf(0.0, _hop_cooldown - delta)
	var player := EnemyCommon.find_player(self)
	if player == null:
		mover.wish = Vector2.ZERO
		return
	var to_player := player.global_position - global_position
	var distance := to_player.length()
	_track_progress(distance, delta)

	var rules := RunState.rules
	var steer: Vector2
	if rules.gravity_enabled:
		steer = _steer_with_gravity(to_player, rules.gravity_dir.normalized())
	elif _wander_left > 0.0:
		steer = _wander_dir
	else:
		steer = _steer_around_walls(to_player.normalized(), distance)
	mover.wish = (steer + EnemyCommon.separation(self)).limit_length(1.0)

	if distance <= Tuning.contact_range + half_width - 15.0:
		var target := Component.find(player, Health) as Health
		if target and target.take(DamageInfo.make(_contact_damage, &"contact", &"enemy", global_position)):
			var player_mover := Component.find(player, Mover) as Mover
			if player_mover:
				player_mover.knockback(to_player.normalized() * Tuning.player_hit_knockback)


## No gravity: head for the player, and if a wall is in the way try directions
## rotated to one side, keeping the same side so it does not dither.
func _steer_around_walls(dir: Vector2, distance: float) -> Vector2:
	var probe := minf(Tuning.avoid_probe, distance)
	if not _blocked(dir, probe):
		return dir
	for angle: float in [0.6, 1.2, 1.8]:
		for side: float in [_avoid_side, -_avoid_side]:
			var candidate := dir.rotated(side * angle)
			if not _blocked(candidate, probe):
				_avoid_side = side
				return candidate
	return dir


func _blocked(dir: Vector2, length: float) -> bool:
	var across := dir.orthogonal() * half_width
	return EnemyCommon.ray_hits_world(self, global_position + across, global_position + across + dir * length) \
		or EnemyCommon.ray_hits_world(self, global_position - across, global_position - across + dir * length)


func _steer_with_gravity(to_player: Vector2, g: Vector2) -> Vector2:
	var lateral := to_player - g * to_player.dot(g)
	var above := -to_player.dot(g)   # how far the player is above us
	var side := lateral.normalized() if lateral.length() > 8.0 else Vector2.ZERO
	if _wander_left > 0.0:
		var across := Vector2(-g.y, g.x)
		side = across * (1.0 if _wander_dir.dot(across) >= 0.0 else -1.0)
	elif side == Vector2.ZERO and absf(above) > Tuning.TILE:
		side = _walk_dir   # straight above or below us: keep going to find an edge
	if is_on_floor():
		var hop := false
		if above > Tuning.TILE and _wander_left <= 0.0:
			if _overhead_clear(g):
				hop = true
			else:
				side = _walk_dir   # under a ledge: walk out from under it
		if side != Vector2.ZERO and _wall_ahead(side):
			hop = true
		if hop and _hop_cooldown <= 0.0:
			mover.request_jump()
			_hop_cooldown = _hop_cooldown_time
		if side != Vector2.ZERO:
			_walk_dir = side
	return side


func _track_progress(distance: float, delta: float) -> void:
	if _wander_left > 0.0:
		_wander_left -= delta
		return
	if distance < _best_distance - Tuning.TILE * 0.5:
		_best_distance = distance
		_stuck_time = 0.0
		return
	_stuck_time += delta
	if _stuck_time >= Tuning.stuck_time and distance > Tuning.contact_range * 1.5:
		_wander_left = Tuning.wander_time
		_wander_dir = Vector2.RIGHT.rotated(RunState.gameplay_rng.randf_range(0.0, TAU))
		_avoid_side = -_avoid_side
		_stuck_time = 0.0
		_best_distance = INF


func _overhead_clear(g: Vector2) -> bool:
	var across := Vector2(-g.y, g.x) * half_width
	var up := -g * Tuning.chaser_headroom
	return not EnemyCommon.ray_hits_world(self, global_position + across, global_position + across + up) \
		and not EnemyCommon.ray_hits_world(self, global_position - across, global_position - across + up)


func _wall_ahead(side: Vector2) -> bool:
	return EnemyCommon.ray_hits_world(self, global_position, global_position + side * (half_width + 12.0))


func _on_died(_info: DamageInfo) -> void:
	queue_free()
