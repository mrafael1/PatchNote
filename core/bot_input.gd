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
	wait_pressed = false
	if nearest == null:
		fire = false
		move = Vector2.RIGHT.rotated(_tick * 0.01)
		if RunState.rules.turn_based:
			move = Vector2.ZERO
			wait_pressed = true   # nothing to do: pass the turn
		return
	var to_enemy := nearest.global_position - here
	aim_dir = to_enemy.normalized()
	fire = true
	if RunState.rules.turn_based:
		_turn_policy(to_enemy)
		return
	if to_enemy.length() < keep_distance:
		move = -aim_dir.rotated(0.6)
	else:
		move = aim_dir.rotated(1.2) * 0.6
	jump_pressed = _tick % 90 == 0
	dash_pressed = _tick % 150 == 75
	jump_held = _tick % 90 < 12


## B2 (PLAN v3 section 3): one action per turn. Step away from a close threat (and
## shoot on that turn), otherwise stand and shoot the nearest enemy. A shot on
## cooldown still passes the turn.
func _turn_policy(to_enemy: Vector2) -> void:
	jump_held = false
	if to_enemy.length() < keep_distance:
		var away := -to_enemy.normalized()
		# Switch axis now and then so a wall does not pin the bot.
		move = away if (_tick / 30) % 2 == 0 else away.orthogonal()
	else:
		move = Vector2.ZERO
	wait_pressed = true
