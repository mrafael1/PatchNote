extends CharacterBody2D
## The hunter (PLAN v6 3): a slow stalker that walks at the player, around walls. It
## cannot die: its Health shield never runs out, and every STUN_HITS hits stun it for
## STUN_TIME seconds (it stands still, dimmed, harmless). Its contact costs the player
## CONTACT_DAMAGE as any walker's does. It is not an enemy: no kill, no spawn cap, no
## auto-aim target, explosions pass it by (its own group, "hunter").

const SPEED := 85.0
const HALF := 20.0
const STUN_HITS := 6   # M33 parity: 8 cost the bot 17% of its run (applied from the start)
const STUN_TIME := 4.0
const CONTACT_DAMAGE := 1.0
const COLOR := Color(0.75, 0.1, 0.25)

var kind: StringName = &"hunter"
var half_width := HALF
var stuns := 0                ## tests
var hits_taken := 0           ## hits since the last stun
var _stunned_left := 0.0
var _avoid_side := 1.0
var _best_distance := INF
var _stuck_time := 0.0
var _wander_left := 0.0
var _wander_dir := Vector2.RIGHT

var mover: Mover
var health: Health
var visual: RectVisual


func _init() -> void:
	collision_layer = Tuning.LAYER_ENEMY_BODY
	collision_mask = Tuning.LAYER_WORLD
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(HALF, HALF) * 2.0
	shape.shape = rect
	add_child(shape)
	visual = RectVisual.new()
	visual.name = "Visual"
	visual.size = Vector2(HALF, HALF) * 2.0
	visual.color = COLOR
	add_child(visual)
	mover = Mover.new()
	mover.speed = SPEED
	mover.knockback_scale = 0.1
	add_child(mover)
	health = Health.new()
	health.base_max_hp = 1.0
	health.scales_with_enemy_rule = false
	health.shield_hits = 1 << 30   # never runs out: it cannot be hurt, let alone die
	add_child(health)


func _ready() -> void:
	health.shield_hit.connect(_on_hit)
	add_to_group(&"threat")   # the bot dodges and shoots it, as a player would
	RunState.register_entity(self, kind)


func is_stunned() -> bool:
	return _stunned_left > 0.0


func _on_hit(_info: DamageInfo) -> void:
	visual.flash()
	if is_stunned():
		return
	hits_taken += 1
	if hits_taken >= STUN_HITS:
		hits_taken = 0
		stuns += 1
		_stunned_left = STUN_TIME


func _physics_process(delta: float) -> void:
	if is_stunned():
		_stunned_left -= delta
		mover.wish = Vector2.ZERO
		visual.modulate = Color(1, 1, 1, 0.4)
		return
	visual.modulate = Color.WHITE
	var player := EnemyCommon.find_player(self)
	if player == null:
		mover.wish = Vector2.ZERO
		return
	var to_player := player.global_position - global_position
	var distance := to_player.length()
	var reach := Tuning.contact_range + HALF - 15.0
	visual.rim = EnemyCommon.contact_warning(distance - reach)
	_track_progress(distance, delta)
	mover.wish = _wander_dir if _wander_left > 0.0 else _steer(to_player.normalized(), distance)
	var player_mover := Component.find(player, Mover) as Mover
	if distance <= reach and not (player_mover and player_mover.is_airborne()):
		var target := Component.find(player, Health) as Health
		if target and target.take(DamageInfo.make(CONTACT_DAMAGE, &"contact", &"enemy", global_position)):
			if player_mover:
				player_mover.knockback(to_player.normalized() * Tuning.player_hit_knockback)


## No progress toward the player for Tuning.stuck_time (a wall it cannot steer around):
## wander for Tuning.wander_time in a seeded direction, as the walkers do.
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


## Head for the player; if a wall is in the way, try directions rotated to one side.
func _steer(dir: Vector2, distance: float) -> Vector2:
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
	var across := dir.orthogonal() * HALF
	return EnemyCommon.ray_hits_world(self, global_position + across, global_position + across + dir * length) \
		or EnemyCommon.ray_hits_world(self, global_position - across, global_position - across + dir * length)
