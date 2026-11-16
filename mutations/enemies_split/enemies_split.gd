extends Mutation
## A killed enemy breaks into smaller, weaker copies. Copies do not split again
## (Tuning.max_split_generation) and they stay in the world if the patch is reverted.

@export var children := 2
@export var size_factor := 0.65
@export var hp_factor := 0.4
@export var scatter_speed := 220.0


func enable() -> void:
	_listen(EventBus.enemy_killed, _on_enemy_killed)


func _on_enemy_killed(enemy: Node, _info: RefCounted) -> void:
	var parent := enemy as Node2D
	if not is_instance_valid(parent) or parent.scene_file_path == "":
		return
	var generation := _number(parent, &"generation", 0.0)
	if generation >= Tuning.max_split_generation:
		return
	var scene := load(parent.scene_file_path) as PackedScene
	if scene == null:
		return
	var size := _number(parent, &"size_mult", 1.0)
	var hp := _number(parent, &"hp_mult", 1.0)
	for i in children:
		var side := -1.0 if i % 2 == 0 else 1.0
		# Small offset: the smaller copy stays inside the space the parent occupied.
		RunState.spawn(scene, parent.global_position + Vector2(side * 4.0, 0), {
			&"generation": int(generation) + 1,
			&"size_mult": size * size_factor,
			&"hp_mult": hp * hp_factor,
			&"velocity": Vector2(side, 0) * scatter_speed,
		})


func _number(node: Node, field: StringName, fallback: float) -> float:
	var value: Variant = node.get(field)
	return float(value) if value != null else fallback
