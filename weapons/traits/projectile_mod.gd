class_name ProjectileMod
extends Node
## A per-shot behaviour a weapon trait adds to one projectile (child node). The
## projectile calls the hooks; with no mods nothing runs (its default path is today's).


## Each tick, before the gravity step: turn or hold the projectile.
func steer(_p: Node2D, _delta: float) -> void:
	pass


## The projectile touched an entity. True = handled (the projectile does nothing else).
func hit_entity(_p: Node2D, _target: Node, _pos: Vector2) -> bool:
	return false


## M50.1a: after the projectile's damage landed on `target` (`killed`: it died of it). True =
## keep flying (the projectile skips its despawn and this target from now on). Never called
## for a blast shot (its blast is not a hit).
func after_hit(_p: Node2D, _target: Node, _killed: bool) -> bool:
	return false


## The projectile touched a wall. True = handled.
func hit_wall(_p: Node2D, _pos: Vector2, _normal: Vector2) -> bool:
	return false


## The projectile is going away (contact, wall, lifetime).
func despawned(_p: Node2D) -> void:
	pass
