class_name BotInput
extends PlayerInput
## Simple scripted player for automated runs: aim at the nearest enemy, hold fire,
## back away from close threats, jump now and then. Deliberately dumb.

var keep_distance := 220.0
var _tick := 0


func _physics_process(_delta: float) -> void:
	_tick += 1
	dash_pressed = false
	jump_pressed = false
	var here := origin()
	var nearest: Node2D = null
	var best := INF
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var n := e as Node2D
		if n == null or n.is_queued_for_deletion():
			continue
		var d := here.distance_squared_to(n.global_position)
		if d < best:
			best = d
			nearest = n
	if nearest == null:
		fire = false
		move = Vector2.RIGHT.rotated(_tick * 0.01)
		return
	var to_enemy := nearest.global_position - here
	aim_dir = to_enemy.normalized()
	fire = true
	if to_enemy.length() < keep_distance:
		move = -aim_dir.rotated(0.6)
	else:
		move = aim_dir.rotated(1.2) * 0.6
	jump_pressed = _tick % 90 == 0
	dash_pressed = _tick % 150 == 75
	jump_held = _tick % 90 < 12
