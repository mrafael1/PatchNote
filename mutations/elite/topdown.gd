extends PatchTake
## Top-down take (PLAN v6 3): every EVERY-th enemy the spawner sends is an elite
## (elite_mark.gd): a shield that takes SHIELD hits whole. Killing an elite removes every
## enemy shot within CLEAR_RADIUS of it. Whether an enemy is an elite is decided once,
## the first time this patch sees it, and kept on the enemy: a revert and re-apply
## marks the same enemies (the smoke matrix rebuilds the stack that way).

const MARK := preload("res://mutations/elite/elite_mark.gd")
@export var every := 8
@export var shield := 3
@export var clear_radius := 5.0 * Tuning.TILE


func on_entity_spawned(entity: Node) -> void:
	if not entity.is_in_group(&"enemy") or not entity.get(&"from_spawner"):
		return
	if not entity.has_meta(MARK.IS_ELITE):
		var seen := int(state().get("spawned", 0)) + 1
		state()["spawned"] = seen
		entity.set_meta(MARK.IS_ELITE, seen % every == 0)
	if entity.get_meta(MARK.IS_ELITE):
		var mark: Component = Component.attach(entity, MARK, id)
		mark.set(&"shield_max", shield)


func enable() -> void:
	_listen(EventBus.enemy_killed, _on_killed)


func _on_killed(enemy: Node, _info: RefCounted) -> void:
	if Component.find(enemy, MARK) == null or not enemy is Node2D:
		return
	var at := (enemy as Node2D).global_position
	var cleared := 0
	for p in RunState.get_tree().get_nodes_in_group(&"enemy_projectile"):
		if (p as Node2D).global_position.distance_to(at) <= clear_radius:
			p.queue_free()
			cleared += 1
	state()["cleared"] = int(state().get("cleared", 0)) + cleared
	EventBus.explosion.emit(at, clear_radius)   # presentation only: the wipe's ring
