extends CharacterBody2D
## Chaser: goes for the player and hurts on contact.
##
## Without gravity it steers straight at the player. With gravity it walks along
## surfaces and hops: over low walls, and upward when the player is above and there
## is headroom. Under a ledge it keeps walking the way it was going instead of
## turning back, so it comes out from under and can hop up. Either way, if it makes
## no progress for a while it wanders briefly. Enemy bodies do not collide with each
## other; a soft push keeps them apart.

const HALF_WIDTH := 15.0

var kind: StringName = &"enemy"
var generation := 0

var _walk_dir := Vector2.RIGHT
var _hop_cooldown := 0.0
var _wander_left := 0.0
var _wander_dir := Vector2.RIGHT
var _stuck_time := 0.0
var _best_distance := INF

@onready var mover: Mover = $Mover
@onready var health: Health = $Health


func _ready() -> void:
	health.base_max_hp = Tuning.chaser_hp
	health.died.connect(_on_died)
	mover.jump_held = true
	RunState.register_entity(self, kind)


func _physics_process(delta: float) -> void:
	mover.speed = Tuning.chaser_speed
	_hop_cooldown = maxf(0.0, _hop_cooldown - delta)
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		mover.wish = Vector2.ZERO
		return
	var to_player := player.global_position - global_position
	_track_progress(to_player.length(), delta)

	var rules := RunState.rules
	var steer: Vector2
	if rules.gravity_enabled:
		steer = _steer_with_gravity(to_player, rules.gravity_dir.normalized())
	else:
		steer = _wander_dir if _wander_left > 0.0 else to_player.normalized()
	mover.wish = (steer + _separation()).limit_length(1.0)

	if to_player.length() <= Tuning.contact_range:
		var target := Component.find(player, Health) as Health
		if target:
			target.take(DamageInfo.make(Tuning.chaser_contact_damage, &"contact", &"enemy", global_position))


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
			_hop_cooldown = Tuning.chaser_hop_cooldown
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
		_stuck_time = 0.0
		_best_distance = INF


func _ray_hits_world(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, Tuning.LAYER_WORLD)
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _overhead_clear(g: Vector2) -> bool:
	var across := Vector2(-g.y, g.x) * HALF_WIDTH
	var up := -g * Tuning.chaser_headroom
	return not _ray_hits_world(global_position + across, global_position + across + up) \
		and not _ray_hits_world(global_position - across, global_position - across + up)


func _wall_ahead(side: Vector2) -> bool:
	return _ray_hits_world(global_position, global_position + side * (HALF_WIDTH + 12.0))


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
