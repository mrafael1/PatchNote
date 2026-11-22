extends PatchTake
## Top-down take (PLAN v6 3): two shards circle the player and hit what they touch.


func on_entity_spawned(entity: Node) -> void:
	if entity.is_in_group(&"player"):
		Component.attach(entity, preload("res://mutations/orbit/orbit_shards.gd"), id)
