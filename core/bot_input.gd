class_name BotInput
extends PlayerInput
## Simple scripted player for automated runs: aim at the nearest enemy, hold fire,
## back away from close threats, jump now and then. Deliberately dumb.

const SHOT_DANGER := 1.0      ## B2: danger of one enemy shot crossing a tile soon
const SHOT_TURNS := 3         ## B2: turns ahead an enemy shot is tracked
const SHOT_CLEARANCE := 34.0  ## B2: a shot passing closer than this to a tile centre hits it
## B2: pull to the arena's middle. Small enough that one tile of it (at most ~2.5e-7 at
## the arena's edge) never outweighs one tile of an enemy's 1/d^2 within keep_distance.
const CENTRE_PULL := 2e-12

var keep_distance := 220.0
var _tick := 0
var _clock_ref: TurnClock    ## B2: found on first use, to test tiles for walls


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


## B2 (PLAN v3 section 3): one action per turn, and a held fire shoots on every turn.
## With a threat close (an enemy, or an enemy shot about to cross this tile), step to
## the free neighbouring tile with the least danger; otherwise stand and shoot the
## nearest enemy. A shot on cooldown still passes the turn.
func _turn_policy(to_enemy: Vector2) -> void:
	jump_held = false
	move = Vector2.ZERO
	wait_pressed = true
	var clock := _clock()
	var here := TurnClock.tile_center(origin())
	var best_danger := _danger(here, clock)
	if to_enemy.length() >= keep_distance and best_danger < SHOT_DANGER:
		return
	var best := Vector2.ZERO
	var rules := RunState.rules
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		# Under gravity the clock only takes sideways steps (TurnClock._step).
		if rules.gravity_enabled and absf(dir.dot(rules.gravity_dir.normalized())) > 0.5:
			continue
		var c := here + dir * Tuning.TILE
		if clock != null and not clock.is_free(c):
			continue
		var d := _danger(c, clock)
		if d < best_danger:
			best_danger = d
			best = dir
	move = best


## How dangerous a tile centre is: SHOT_DANGER for each enemy shot that crosses it in
## the next few turns, inverse square distance to enemies within reach, and a light
## pull to the arena's middle so walls do not corner the bot.
func _danger(p: Vector2, clock: TurnClock) -> float:
	var out := 0.0
	var turn := RunState.rules.turn_duration
	for s in get_tree().get_nodes_in_group(&"enemy_projectile"):
		var shot := s as Node2D
		if shot == null or shot.is_queued_for_deletion():
			continue
		var v: Vector2 = shot.get(&"velocity")
		var horizon := turn * SHOT_TURNS
		# Closest approach of the shot's straight path to p within the horizon.
		var t := 0.0 if v.length_squared() < 1.0 else clampf((p - shot.global_position).dot(v) / v.length_squared(), 0.0, horizon)
		if (shot.global_position + v * t).distance_to(p) < SHOT_CLEARANCE:
			out += SHOT_DANGER
	var reach := keep_distance * 2.0
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var n := e as Node2D
		if n == null or n.is_queued_for_deletion():
			continue
		var d := p.distance_to(n.global_position)
		if d < reach:
			out += 1.0 / maxf(d * d, 1.0)
	if clock != null and clock.arena != null:
		out += CENTRE_PULL * p.distance_squared_to(clock.arena.bounds.get_center())
	return out


func _clock() -> TurnClock:
	if not is_instance_valid(_clock_ref):
		_clock_ref = get_tree().root.find_child("TurnClock", true, false) as TurnClock
	return _clock_ref
