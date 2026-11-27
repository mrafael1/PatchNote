class_name EnemyWalker
extends CharacterBody2D
## Ground enemy that goes for the player and hurts on contact. The chaser and the tank
## use this script as is; the bomber and the lancer extend it (enemy_bomber.gd,
## enemy_lancer.gd) through the hooks below. The archetype picks its numbers from
## Tuning ("chaser_speed", ...).
##
## Without gravity it steers at the player and feels its way around walls. With
## gravity it walks along surfaces and hops: over low walls, and upward when the
## player is above and there is headroom. Under a ledge it keeps walking the way it
## was going instead of turning back, so it comes out from under and can hop up.
## Either way, if it makes no progress for a while it wanders briefly. Close to the
## player it shows a red rim that brightens as it nears contact (PLAN v5 2.2). On
## B2's grid (TurnClock.on_grid) it does none of this.

@export var archetype: StringName = &"chaser"
@export var half_width := 15.0
var _rule_scale := 1.0   ## the live size a rule edit gave it (EnemyCommon.follow_scale)

var kind: StringName = &"enemy"
var generation := 0
var from_spawner := false
var size_mult := 1.0   ## smaller or bigger copy (set through spawn params)
var hp_mult := 1.0
## M47 (PLAN v9 1.9): the EnemyVariant this walker plays (&"" = the plain base), and a floor
## on its max HP after every overlay (a splitter's minis: 1).
var variant: StringName = &""
var min_hp := 0.0
## M50.3c (PLAN v9 1.9): what the variant's data sets, read once in _ready (the plain base:
## 1.0 and no shield). The shielder's shield covers `_shield_arc` degrees around `facing`,
## which turns toward the player at Tuning.shielder_turn_deg a second.
var _speed_mult := 1.0
var _shield_arc := 0.0
## The flank-rule contract (BotInput.flank_step, M46): the shield's arc in degrees (0: none).
var shield_arc_deg: float:
	get:
		return _shield_arc
var facing := Vector2.RIGHT
var blocked := 0   ## shots its shield stopped (tests)
var _faced := false
var _arc: ShieldArc
## M48b (PLAN 1.7.1, D9): a `spawn ... specimen` cue's enemy: it stands still, shows no rim,
## takes no damage (Health.take) and deals none until a `release` cue clears it.
var specimen := false:
	set(value):
		specimen = value
		if is_inside_tree():
			if value:
				add_to_group(&"specimen")
			elif is_in_group(&"specimen"):
				remove_from_group(&"specimen")

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
@onready var visual: RectVisual = $Visual


func _ready() -> void:
	health.base_max_hp = _tuned("hp") * hp_mult
	if min_hp > 0.0:
		health.min_max_hp = min_hp
	half_width *= size_mult
	EnemyCommon.apply_size(self, size_mult)
	health.died.connect(_on_died)
	if variant != &"":
		_apply_variant()
	mover.jump_held = true
	mover.accel = Tuning.enemy_accel
	mover.knockback_scale = _tuned("knockback_scale")
	_contact_damage = _tuned("contact_damage")
	_hop_cooldown_time = _tuned("hop_cooldown")
	_avoid_side = 1.0 if RunState.gameplay_rng.randi() % 2 == 0 else -1.0   # seeded: same seed, same run
	if specimen:
		add_to_group(&"specimen")
	RunState.register_entity(self, kind)


func _tuned(suffix: String) -> float:
	return float(Tuning.get("%s_%s" % [archetype, suffix]))


## M50.3c: the variant's speed and shield (a splitter has neither: 1.0 and none).
func _apply_variant() -> void:
	var v := EnemyDB.variant(variant)
	if v == null:
		return
	_speed_mult = v.speed_mult
	if v.shield_arc_deg > 0.0:
		_shield_arc = v.shield_arc_deg
		health.guard = shield_blocks
		_arc = ShieldArc.new()
		_arc.name = "ShieldArc"
		_arc.arc_deg = _shield_arc
		_arc.radius = half_width + 14.0
		add_child(_arc)


## The shield turns toward the player (at once on its first tick, then at the turn rate).
func _turn_shield(to_player: Vector2, delta: float) -> void:
	if to_player == Vector2.ZERO:
		return
	var want := to_player.angle()
	var a := want if not _faced else rotate_toward(facing.angle(), want, deg_to_rad(Tuning.shielder_turn_deg) * delta)
	_faced = true
	facing = Vector2.from_angle(a)
	if _arc != null:
		_arc.facing = facing


## Health.guard: a player's shot that hits the front and does not pierce stops on the shield.
## Blasts, beams, burns, orbit shards and piercing shots (other kinds, or `pierces`) pass.
func shield_blocks(info: DamageInfo) -> bool:
	if _shield_arc <= 0.0 or info.kind != &"projectile" or info.faction != &"player" or info.pierces:
		return false
	var from := info.pos - global_position
	if from == Vector2.ZERO or absf(facing.angle_to(from)) > deg_to_rad(_shield_arc) * 0.5:
		return false
	blocked += 1
	RunState.shield_blocks += 1
	if _arc != null:
		_arc.blocked()
	return true


func _physics_process(delta: float) -> void:
	if specimen:
		mover.wish = Vector2.ZERO   # M48b: held still and harmless until `release`
		visual.rim = 0.0
		return
	if _before_tick(delta):
		return
	EnemyCommon.follow_scale(self)
	if TurnClock.on_grid(self):
		mover.wish = Vector2.ZERO   # B2: the turn logic moves it and resolves its attacks
		visual.rim = 0.0
		return
	mover.speed = _tuned("speed") * RunState.rules.enemy_speed_mult * _speed_mult
	_hop_cooldown = maxf(0.0, _hop_cooldown - delta)
	var player := EnemyCommon.find_player(self)
	if player == null:
		mover.wish = Vector2.ZERO
		visual.rim = 0.0
		return
	var to_player := player.global_position - global_position
	var distance := to_player.length()
	if _shield_arc > 0.0:
		_turn_shield(to_player, delta)
	if _attack_step(delta, to_player, distance):
		return
	var reach := contact_reach()
	var harmless: bool = player.get(&"damage_locked") == true   # no `health` yet (M39.2)
	visual.rim = 0.0 if not _shows_rim() or harmless else EnemyCommon.contact_warning(distance - reach)
	var rules := RunState.rules
	if rules.enemies_flee > 0 and not rules.gravity_enabled:
		# M51 review: fleeing never gets closer, so the stuck detector would start wanders (a
		# gameplay_rng draw each) that outlive the edit. Off while fleeing; it starts fresh after.
		_wander_left = 0.0
		_stuck_time = 0.0
		_best_distance = INF
	else:
		_track_progress(distance, delta)

	var steer: Vector2
	if rules.gravity_enabled:
		steer = _steer_with_gravity(to_player, rules.gravity_dir.normalized())
	elif rules.enemies_flee > 0:
		# M51 (edit_enemies_flee): away from the player, feeling around walls the same way.
		steer = _steer_around_walls(-to_player.normalized(), Tuning.avoid_probe)
	elif _wander_left > 0.0:
		steer = _wander_dir
	else:
		steer = _steer_around_walls(to_player.normalized(), distance)
	if harmless and distance <= reach:
		steer = Vector2.ZERO   # arrived, and nothing happens: they ring the player, not bury it
	mover.wish = (steer + EnemyCommon.separation(self)).limit_length(1.0)

	var player_mover := Component.find(player, Mover) as Mover
	if player_mover and player_mover.is_airborne():
		return   # the player is above the ground plane
	if distance <= reach and _contact_damage > 0.0:
		var target := Component.find(player, Health) as Health
		if target and target.take(DamageInfo.make(_contact_damage, &"contact", &"enemy", global_position)):
			if player_mover:
				player_mover.knockback(to_player.normalized() * Tuning.player_hit_knockback)


## A subclass's pre-walk tick (a death fuse); true skips the frame.
func _before_tick(_delta: float) -> bool:
	return false


## A subclass's attack, run before the walk; true ends the frame after it.
func _attack_step(_delta: float, _to_player: Vector2, _distance: float) -> bool:
	return false


## False hides the contact rim.
func _shows_rim() -> bool:
	return true


## Health ran out: freed here; a subclass may delay it.
func _on_died(_info: DamageInfo) -> void:
	if variant != &"":
		VariantDeath.on_died(self, variant)
	queue_free()


## Centre distance at which its contact hurts the player.
func contact_reach() -> float:
	return Tuning.contact_range + body_half() - 15.0


## Half its width as it is now: half_width under a rule edit's live size (PLAN v8 1.4).
func body_half() -> float:
	return half_width * RunState.rules.enemy_scale_mult


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
	var across := dir.orthogonal() * body_half()
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
	var across := Vector2(-g.y, g.x) * body_half()
	var up := -g * Tuning.chaser_headroom
	return not EnemyCommon.ray_hits_world(self, global_position + across, global_position + across + up) \
		and not EnemyCommon.ray_hits_world(self, global_position - across, global_position - across + up)


func _wall_ahead(side: Vector2) -> bool:
	return EnemyCommon.ray_hits_world(self, global_position, global_position + side * (body_half() + 12.0))
