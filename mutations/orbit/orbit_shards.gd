extends Component
## The orbit patch's shards (PLAN v6 3): SHARDS of them circle the player at RADIUS, a
## full turn every TAU / SPEED seconds of game time (so a same-seed run is the same).
## A shard that touches an enemy deals DAMAGE to it, at most once per COOLDOWN seconds
## per enemy. Not on B2's grid.

const SHARDS := 2
const RADIUS := 1.5 * Tuning.TILE
const SPEED := 4.0                ## radians per second
const SHARD_HALF := 7.0
const DAMAGE := 1.0
const COOLDOWN := 0.4
const KNOCKBACK := 160.0
const COLOR := Color(0.55, 0.95, 1.0)

var _shards: Array[Node2D] = []
var _next_hit := {}               ## enemy -> game time it may be hit again
var hits := 0                     ## tests


func _ready() -> void:
	for i in SHARDS:
		var shard := RectVisual.new()
		shard.size = Vector2(SHARD_HALF, SHARD_HALF) * 2.0
		shard.color = COLOR
		add_child(shard)
		_shards.append(shard)


## Where shard i is now (global).
func shard_position(i: int) -> Vector2:
	var host := get_parent() as Node2D
	var angle := RunState.game_time * SPEED + TAU * i / SHARDS
	return host.global_position + Vector2.RIGHT.rotated(angle) * RADIUS


func _physics_process(_delta: float) -> void:
	var host := get_parent() as Node2D
	if host == null or RunState.rules.turn_based:
		return
	for i in _shards.size():
		var pos := shard_position(i)
		_shards[i].global_position = pos
		_shards[i].rotation = RunState.game_time * SPEED * 2.0
		for e in get_tree().get_nodes_in_group(&"enemy"):
			var enemy := e as Node2D
			if enemy == null or enemy.is_queued_for_deletion():
				continue
			var half: float = enemy.get(&"half_width") if enemy.get(&"half_width") != null else 15.0
			if pos.distance_to(enemy.global_position) > half + SHARD_HALF:
				continue
			if RunState.game_time < float(_next_hit.get(enemy, -1.0)):
				continue
			_next_hit[enemy] = RunState.game_time + COOLDOWN
			var hp := Component.find(enemy, Health) as Health
			if hp and hp.take(DamageInfo.make(DAMAGE, &"orbit", &"player", pos, source_patch)):
				hits += 1
				var mover := Component.find(enemy, Mover) as Mover
				if mover:
					mover.knockback((enemy.global_position - host.global_position).normalized() * KNOCKBACK)
