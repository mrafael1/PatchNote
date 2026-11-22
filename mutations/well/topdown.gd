extends PatchTake
## Top-down take (PLAN v6 3): a killed enemy leaves a pull field (well_field.gd).

const FIELD := preload("res://mutations/well/well_field.gd")


func enable() -> void:
	_listen(EventBus.enemy_killed, _on_killed)


func _on_killed(enemy: Node, _info: RefCounted) -> void:
	if not is_instance_valid(RunState.world) or not enemy is Node2D:
		return
	var field: Node2D = FIELD.new()
	field.position = (enemy as Node2D).global_position
	RunState.world.add_child.call_deferred(field)
