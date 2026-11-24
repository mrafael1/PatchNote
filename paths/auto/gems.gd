extends Node
# path:auto
## Auto's gems (PLAN v9 1.5, 1.6): every enemy the player kills drops a gem (tank and bomber
## 3, the rest 1; shielders join at M50). A bomber's blast killing an enemy drops nothing
## (the faction filter RunState.kills uses). At the pickup cap the oldest gem merges into its
## nearest gem first, so a gem is never refused. The merge draws nothing: the oldest (lowest
## serial) and the nearest are deterministic (PLAN 1.4 lists gem merges under loot_rng; there
## is nothing to draw). PathRunner makes this node while Auto and `levelups` are live.

signal gem_taken(value: int)

const PICKUP := preload("res://entities/pickup.tscn")
const BIG_GEMS: Array[StringName] = [&"tank", &"bomber"]

var _serial := 0
var _mine: Array[Pickup] = []   ## every gem dropped (pruned when merging)


func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)


func _exit_tree() -> void:
	if EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.disconnect(_on_enemy_killed)


func _on_enemy_killed(enemy: Node, info: RefCounted) -> void:
	if (info as DamageInfo).faction != &"player" or not enemy is Node2D:
		return
	var archetype: Variant = enemy.get(&"archetype")   # null on a shooter (its own script)
	var big := archetype != null and StringName(archetype) in BIG_GEMS
	drop((enemy as Node2D).global_position, 3 if big else 1)


## A gem worth `value` at `pos` (merging the oldest first at the cap). The new node; at the
## cap with nothing to merge yet (every gem still entering the tree this frame) the newest
## gem takes the value instead, so no worth is lost.
func drop(pos: Vector2, value: int) -> Node:
	if RunState.count(&"pickup") + RunState.pending_count(&"pickup") >= Tuning.hard_max_pickups:
		if not merge_oldest():
			var newest := _newest()
			if newest != null:
				newest.value += value
			return newest
	_serial += 1
	var g := RunState.spawn(PICKUP, pos, {&"pickup_kind": &"gem", &"value": value, &"serial": _serial})
	if g != null:
		g.taken.connect(func(p: Pickup) -> void: gem_taken.emit(p.value))
		_mine.append(g)
	return g


## The last gem this node spawned that is still there (in the tree or entering it).
func _newest() -> Pickup:
	for i in range(_mine.size() - 1, -1, -1):
		var g := _mine[i]
		if is_instance_valid(g) and not g.is_queued_for_deletion():
			return g
	return null


## The oldest gem on the floor goes into its nearest gem (value kept). False: fewer than two.
func merge_oldest() -> bool:
	_mine = _mine.filter(func(g: Pickup) -> bool: return is_instance_valid(g) and not g.is_queued_for_deletion())
	var gems: Array[Pickup] = []
	for n in get_tree().get_nodes_in_group(Pickup.GEM_GROUP):
		if n is Pickup and not n.is_queued_for_deletion():
			gems.append(n)
	if gems.size() < 2:
		return false
	var oldest := gems[0]
	for g in gems:
		if g.serial < oldest.serial:
			oldest = g
	var into: Pickup = null
	for g in gems:
		if g != oldest and (into == null or g.global_position.distance_squared_to(oldest.global_position)
				< into.global_position.distance_squared_to(oldest.global_position)):
			into = g
	into.value += oldest.value
	oldest.queue_free()
	return true
