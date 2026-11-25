extends ProjectileMod
## Shrapnel (shotgun rank 6, M50.1a): a pellet that touched no entity leaves a caltrop where it
## goes away.

const Caltrop := preload("res://weapons/traits/caltrop.gd")

var life := 3.0
var _hit := false


func hit_entity(_p: Node2D, _target: Node, _pos: Vector2) -> bool:
	_hit = true
	return false


func despawned(p: Node2D) -> void:
	if _hit or not is_instance_valid(RunState.world):
		return
	Caltrop.drop(p.global_position, life, p.source_patch)
