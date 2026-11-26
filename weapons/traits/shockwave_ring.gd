extends Node2D
## The nova's shockwave ring (M50.4a, Auto depth design 3): from the blast's radius out to
## `to_r` over SECONDS of game time (the physics tick: a pause stops it). An enemy is hit once
## per ring as the edge passes it (from its body edge, as Explosion counts), for `damage`,
## kind `blast`, credited `source`; the hit list holds node references (no instance-id order),
## no random stream. Not a projectile: never counted in the shot budgets.

const SECONDS := 0.4
const MAX_ALIVE := 4
const GROUP := &"shockwave_ring"
const BODY_MARGIN := 12.0

var from_r := 0.0
var to_r := 0.0
var damage := 0.0
var source: StringName = &"weapon:nova"
var hits := 0
var _age := 0.0
var _hit: Array[Node] = []


## The enemies the nova's blast already hit: never hit again by this ring.
func skip(nodes: Array) -> void:
	for n: Node in nodes:
		_hit.append(n)


func radius() -> float:
	return lerpf(from_r, to_r, clampf(_age / SECONDS, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	_age += delta
	var r := radius()
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := e as Node2D
		if enemy == null or enemy.is_queued_for_deletion() or _hit.has(enemy):
			continue
		var d := (enemy.global_position - global_position).length()
		if d <= from_r + BODY_MARGIN or d > r + BODY_MARGIN:
			continue
		_hit.append(enemy)
		var health := Component.find(enemy, Health) as Health
		if health != null and health.take(DamageInfo.make(damage, &"blast", &"player", global_position, source)):
			hits += 1
	queue_redraw()
	if _age >= SECONDS:
		queue_free()


func _draw() -> void:
	var u := clampf(_age / SECONDS, 0.0, 1.0)
	draw_arc(Vector2.ZERO, radius(), 0.0, TAU, 48, Color(Palette.BLAST, 0.8 * (1.0 - u)), 2.0)
