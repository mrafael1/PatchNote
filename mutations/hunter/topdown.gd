extends PatchTake
## Top-down take (PLAN v6 3): from hunter_watch.ARRIVE seconds of run time, one slow
## stalker (hunter_body.gd) follows the player for the rest of the run. The watcher is a
## component on the player, so a revert takes it and its hunter away.


func on_entity_spawned(entity: Node) -> void:
	if entity.is_in_group(&"player"):
		Component.attach(entity, preload("res://mutations/hunter/hunter_watch.gd"), id)
