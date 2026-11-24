extends "res://mutations/well/well_field.gd"
## The well weapon's field (PLAN v9 1.4, M45b): the v6 patch's pull field (same radius 2.6 T
## and pull 230; the weapon sets `life` 1.5 s). Rank 2 (`gem_pull`): gems within the radius
## are dragged to the centre at the pull speed. Rank 3 (`teeth`): every BITE_EVERY seconds of
## game time each enemy within the radius takes `bite` damage (kind `burn`, faction player,
## credited `source`). A bitten enemy flashes white (its hit flash): the field already draws.

const BITE_EVERY := 0.5

var gem_pull := false
var teeth := false
var bite := 0.5
var source: StringName = &"weapon:well"
var bites := 0           ## tests: damage applied
var _next_bite := 0.0


func _after_pull(delta: float) -> void:
	if gem_pull:
		for g in get_tree().get_nodes_in_group(Pickup.GEM_GROUP):
			var gem := g as Node2D
			if gem == null or gem.is_queued_for_deletion():
				continue
			var d := gem.global_position.distance_to(global_position)
			if d <= radius:
				gem.global_position = gem.global_position.move_toward(global_position, pull * delta)
	if not teeth or _age < _next_bite:
		return
	_next_bite += BITE_EVERY
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := e as Node2D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		if enemy.global_position.distance_to(global_position) > radius:
			continue
		var hp := Component.find(enemy, Health) as Health
		if hp and hp.take(DamageInfo.make(bite, &"burn", &"player", global_position, source)):
			bites += 1
