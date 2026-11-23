extends Node2D
## A projectile. Not a physics body: each tick it sweeps a ray along its path, which
## gives the exact contact point and wall normal and cannot tunnel through thin walls.
##
## Wall hits bounce while the rules allow (player projectiles only), otherwise the
## projectile is removed. Hit signals fire on every contact, before that decision.
## An enemy shot on B2's grid (TurnClock.on_grid) has no motion, contact or lifetime
## of its own until it leaves the grid.

const COLOR_PLAYER := Color(1.0, 0.95, 0.5)
const COLOR_ENEMY := Color(1.0, 0.55, 0.2)
const MAX_CONTACTS_PER_TICK := 4
const TRAIL_SECONDS := 0.035   ## a trail is as long as this much of the flight
const TRAIL_MAX := 34.0

var kind: StringName = &"player_projectile"
var faction: StringName = &"player"
var velocity := Vector2.ZERO
var damage := 1.0
var source_patch: StringName = &""
## Fired by auto_attack, not by the player's trigger. B1 gives these no time pulse.
var auto_fired := false
var bounces_used := 0

var _age := 0.0
var _dead := false
var _trail := false
var _trail_scale := 1.0


func _ready() -> void:
	($Visual as RectVisual).color = COLOR_PLAYER if faction == &"player" else COLOR_ENEMY
	rotation = velocity.angle()
	_trail = faction == &"player" and Look.preset.trail   # presentation only (PLAN v5 1.7)
	_trail_scale = Look.preset.trail_scale
	RunState.register_entity(self, kind)


func _draw() -> void:
	if not _trail:
		return
	var length := minf(velocity.length() * TRAIL_SECONDS, TRAIL_MAX) * _trail_scale
	draw_polyline_colors(PackedVector2Array([Vector2(-length, 0), Vector2.ZERO]),
			PackedColorArray([Color(COLOR_PLAYER, 0.0), Color(COLOR_PLAYER, 0.6)]), 4.0 * _trail_scale, true)


func _physics_process(delta: float) -> void:
	if _dead or TurnClock.on_grid(self):
		return   # B2 moves an enemy shot tile by tile and resolves its hit
	_age += delta
	if _age >= Tuning.projectile_lifetime:
		_despawn()
		return
	var rules := RunState.rules
	var is_player := faction == &"player"
	if is_player and rules.gravity_enabled and rules.projectile_gravity_scale != 0.0:
		velocity += rules.gravity_dir.normalized() * rules.gravity_strength \
				* rules.projectile_gravity_scale * delta

	# Before the session has `hits` (M39.2) the player's shots pass through enemies.
	var mask := Tuning.LAYER_WORLD
	if not is_player:
		mask |= Tuning.LAYER_PLAYER_BODY
	elif Unlocks.has_basic(&"hits"):
		mask |= Tuning.LAYER_ENEMY_BODY
	var space := get_world_2d().direct_space_state
	var remaining := velocity.length() * delta
	var contacts := 0
	var skipped: Array[RID] = []
	while remaining > 0.01 and contacts < MAX_CONTACTS_PER_TICK:
		var dir := velocity.normalized()
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + dir * remaining, mask)
		query.hit_from_inside = true
		query.exclude = skipped
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			global_position += dir * remaining
			break
		contacts += 1
		var pos: Vector2 = hit.position
		var normal: Vector2 = hit.normal
		var collider := hit.collider as Node
		if collider and collider.is_in_group(&"entities"):
			var target_mover := Component.find(collider, Mover) as Mover
			if target_mover and target_mover.is_airborne():
				skipped.append(hit.rid)   # ground-level shot passes under it
				continue
		remaining -= global_position.distance_to(pos)
		global_position = pos
		if collider and collider.is_in_group(&"entities"):
			_hit_entity(collider, pos, dir)
			return
		EventBus.projectile_hit_wall.emit(self, pos, normal)
		if _dead:
			return
		if is_player and bounces_used < rules.projectile_max_bounces and normal != Vector2.ZERO:
			velocity = velocity.bounce(normal) * Tuning.bounce_restitution
			bounces_used += 1
			global_position = pos + normal * 0.5
		else:
			_despawn()
			return
	rotation = velocity.angle()


func _hit_entity(target: Node, pos: Vector2, dir: Vector2) -> void:
	var health := Component.find(target, Health) as Health
	var applied := false
	if health:
		applied = health.take(DamageInfo.make(damage, &"projectile", faction, pos, source_patch))
	if applied:
		var mover := Component.find(target, Mover) as Mover
		if mover:
			mover.knockback(dir * Tuning.projectile_knockback)
	EventBus.projectile_hit.emit(self, target, pos)
	_despawn()


func _despawn() -> void:
	_dead = true
	queue_free()
