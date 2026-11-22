extends Component
## On an enemy shot (PLAN v6 3): once it is clear of the enemies near where it was
## fired, an enemy within RANGE of it bends it toward that enemy (TURN radians a second),
## and touching that enemy hits it for the shot's damage and ends the shot. The hit is
## the magnet patch's (player faction: the player's kill).

const RANGE := Tuning.TILE
const TURN := 14.0
const BODY := 6.0

var _ignored := {}     ## enemies near the muzzle: the shooter and its neighbours
var _started := false
var hits := 0          ## tests


func _physics_process(delta: float) -> void:
	var shot := get_parent() as Node2D
	if shot == null or shot.is_queued_for_deletion() or TurnClock.on_grid(shot):
		return
	if not _started:
		_started = true
		for e in get_tree().get_nodes_in_group(&"enemy"):
			if (e as Node2D).global_position.distance_to(shot.global_position) <= RANGE * 1.5:
				_ignored[e] = true
		return
	var target: Node2D = null
	var best := INF
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := e as Node2D
		if enemy == null or enemy.is_queued_for_deletion() or _ignored.has(enemy):
			continue
		var half: float = enemy.get(&"half_width") if enemy.get(&"half_width") != null else 15.0
		var d := enemy.global_position.distance_to(shot.global_position) - half
		if d < best and d <= RANGE:
			best = d
			target = enemy
	if target == null:
		return
	if best <= BODY:
		var hp := Component.find(target, Health) as Health
		var damage: float = shot.get(&"damage")
		if hp and hp.take(DamageInfo.make(damage, &"projectile", &"player", shot.global_position, source_patch)):
			hits += 1
		shot.queue_free()
		return
	var velocity: Vector2 = shot.get(&"velocity")
	var want := (target.global_position - shot.global_position).angle()
	var turned := Vector2.RIGHT.rotated(rotate_toward(velocity.angle(), want, TURN * delta)) * velocity.length()
	shot.set(&"velocity", turned)
