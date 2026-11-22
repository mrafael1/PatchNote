extends CharacterBody2D
## Ground enemy that goes for the player and hurts on contact. Used by the chaser
## and the tank; the archetype picks its numbers from Tuning ("chaser_speed", ...).
##
## Without gravity it steers at the player and feels its way around walls. With
## gravity it walks along surfaces and hops: over low walls, and upward when the
## player is above and there is headroom. Under a ledge it keeps walking the way it
## was going instead of turning back, so it comes out from under and can hop up.
## Either way, if it makes no progress for a while it wanders briefly. Close to the
## player it shows a red rim that brightens as it nears contact (PLAN v5 2.2). On
## B2's grid (TurnClock.on_grid) it does none of this.
##
## The bomber (PLAN v5 3) is a walker too: it has no contact damage and no rim. Within
## Tuning.bomber_trigger_range it stops and telegraphs for Tuning.bomber_windup (it grows
## and flashes), then blows up: everyone in Tuning.bomber_blast_radius takes the blast,
## the player and other enemies alike, and the bomber is gone. A lit fuse always ends in
## its blast. Blowing itself up is not a kill; shooting it first is. What its blast kills
## is not the player's kill either (enemy faction: no kill count, no prompt pacing).

@export var archetype: StringName = &"chaser"
@export var half_width := 15.0

var kind: StringName = &"enemy"
var generation := 0
var from_spawner := false
var size_mult := 1.0   ## smaller or bigger copy (set through spawn params)
var hp_mult := 1.0

var _contact_damage := 1.0
var _hop_cooldown_time := 0.5
var _walk_dir := Vector2.RIGHT
var _hop_cooldown := 0.0
var _wander_left := 0.0
var _wander_dir := Vector2.RIGHT
var _stuck_time := 0.0
var _best_distance := INF
var _avoid_side := 1.0
var _fuse_left := -1.0   ## bomber: < 0 while the fuse is not lit
var _blown := false
var fuses := 0           ## bomber: telegraphs started (tests)

@onready var mover: Mover = $Mover
@onready var health: Health = $Health
@onready var visual: RectVisual = $Visual


func _ready() -> void:
	health.base_max_hp = _tuned("hp") * hp_mult
	half_width *= size_mult
	EnemyCommon.apply_size(self, size_mult)
	health.died.connect(_on_died)
	mover.jump_held = true
	mover.accel = Tuning.enemy_accel
	mover.knockback_scale = _tuned("knockback_scale")
	_contact_damage = _tuned("contact_damage")
	_hop_cooldown_time = _tuned("hop_cooldown")
	_avoid_side = 1.0 if RunState.gameplay_rng.randi() % 2 == 0 else -1.0   # seeded: same seed, same run
	RunState.register_entity(self, kind)


func _tuned(suffix: String) -> float:
	return float(Tuning.get("%s_%s" % [archetype, suffix]))


func _physics_process(delta: float) -> void:
	if TurnClock.on_grid(self):
		mover.wish = Vector2.ZERO   # B2: the turn logic moves it and resolves its attacks
		visual.rim = 0.0
		return
	mover.speed = _tuned("speed")
	_hop_cooldown = maxf(0.0, _hop_cooldown - delta)
	var player := EnemyCommon.find_player(self)
	if player == null:
		mover.wish = Vector2.ZERO
		visual.rim = 0.0
		return
	var to_player := player.global_position - global_position
	var distance := to_player.length()
	if is_bomber() and _bomber_step(delta, distance):
		return
	var reach := contact_reach()
	visual.rim = 0.0 if is_bomber() else EnemyCommon.contact_warning(distance - reach)
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

	var player_mover := Component.find(player, Mover) as Mover
	if player_mover and player_mover.is_airborne():
		return   # the player is above the ground plane
	if distance <= reach and _contact_damage > 0.0:
		var target := Component.find(player, Health) as Health
		if target and target.take(DamageInfo.make(_contact_damage, &"contact", &"enemy", global_position)):
			if player_mover:
				player_mover.knockback(to_player.normalized() * Tuning.player_hit_knockback)


## Centre distance at which its contact hurts the player.
func contact_reach() -> float:
	return Tuning.contact_range + half_width - 15.0


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


func is_bomber() -> bool:
	return archetype == &"bomber"


func is_fuse_lit() -> bool:
	return _fuse_left >= 0.0


## Bomber: lights the fuse in range (and with a clear line), then stands still until it
## blows. Returns true while it handles the tick (the walk logic is skipped).
func _bomber_step(delta: float, distance: float) -> bool:
	if _fuse_left < 0.0:
		if distance > Tuning.bomber_trigger_range:
			return false
		var player := EnemyCommon.find_player(self)
		if player and EnemyCommon.ray_hits_world(self, global_position, player.global_position):
			return false
		_fuse_left = Tuning.bomber_windup
		fuses += 1
	mover.wish = Vector2.ZERO
	visual.rim = 0.0
	_fuse_left -= delta
	visual.telegraph = clampf(1.0 - _fuse_left / maxf(Tuning.bomber_windup, 0.001), 0.0, 1.0)
	if _fuse_left <= 0.0:
		blow_up()
	return true


## The bomber's blast: the player and every other enemy in range. It leaves the enemy
## group first, so the blast never counts it and it dies without a kill.
func blow_up() -> void:
	if _blown or is_queued_for_deletion():
		return
	_blown = true
	_fuse_left = -1.0
	remove_from_group(&"enemy")
	var pos := global_position
	var radius := Tuning.bomber_blast_radius
	Explosion.blast(pos, radius, Tuning.bomber_blast_damage, Tuning.bomber_blast_knockback,
			&"explosion", &"", true, &"enemy")
	for p in get_tree().get_nodes_in_group(&"player"):
		var target := p as Node2D
		if target.global_position.distance_to(pos) <= radius + Explosion.BODY_MARGIN:
			var hp := Component.find(target, Health) as Health
			if hp:
				hp.take(DamageInfo.make(Tuning.bomber_blast_damage, &"explosion", &"enemy", pos))
	queue_free()


func _on_died(_info: DamageInfo) -> void:
	queue_free()
