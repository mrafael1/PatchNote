extends PatchTake
## Top-down take (PLAN v6 3): enemy shots curve into other enemies that they pass.


func on_entity_spawned(entity: Node) -> void:
	if entity.is_in_group(&"enemy_projectile"):
		Component.attach(entity, preload("res://mutations/magnet/magnet_pull.gd"), id)
