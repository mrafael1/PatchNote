class_name Explosion
extends Node2D
## One-shot area effect plus its ring visual (PLAN 5). Not an entity: nothing can
## hit it and it emits no projectile signals, so explosions cannot chain off each other.
##
## Use Explosion.blast(). Damage goes to enemies only, through Health.take like all
## damage. Knockback goes to every enemy in range and, if push_player, to the player.

const LIFE := 0.25
const COLOR := Color(1.0, 0.7, 0.25)
const BODY_MARGIN := 12.0   # enemies are counted from their edge, not their centre

var radius := 60.0
var _age := 0.0


## Returns how many enemies took damage.
static func blast(pos: Vector2, p_radius: float, damage: float, knockback: float,
		kind: StringName, source_patch: StringName, push_player := true) -> int:
	var tree := RunState.get_tree()
	var hits := 0
	for e in tree.get_nodes_in_group(&"enemy"):
		var enemy := e as Node2D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		var away := enemy.global_position - pos
		if away.length() > p_radius + BODY_MARGIN:
			continue
		var health := Component.find(enemy, Health) as Health
		if health and health.take(DamageInfo.make(damage, kind, &"player", pos, source_patch)):
			hits += 1
		_push(enemy, away, p_radius, knockback)
	if push_player:
		for p in tree.get_nodes_in_group(&"player"):
			var player := p as Node2D
			var away := player.global_position - pos
			if away.length() <= p_radius + BODY_MARGIN:
				_push(player, away, p_radius, knockback)
	if is_instance_valid(RunState.world):
		var ring := Explosion.new()
		ring.radius = p_radius
		ring.position = pos
		RunState.world.add_child.call_deferred(ring)
	return hits


static func _push(target: Node2D, away: Vector2, p_radius: float, knockback: float) -> void:
	var mover := Component.find(target, Mover) as Mover
	if mover == null:
		return
	var dir := away.normalized() if away.length() > 1.0 else Vector2.UP
	var falloff := clampf(1.0 - away.length() / (p_radius + BODY_MARGIN), 0.3, 1.0)
	mover.knockback(dir * knockback * falloff)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var u := clampf(_age / LIFE, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius * (0.4 + 0.6 * u), Color(COLOR, 0.35 * (1.0 - u)))
	draw_arc(Vector2.ZERO, radius * (0.4 + 0.6 * u), 0.0, TAU, 32, Color(COLOR, 1.0 - u), 3.0)
