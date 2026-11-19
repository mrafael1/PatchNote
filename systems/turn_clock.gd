class_name TurnClock
extends Node
## Big patch B2, "Turn-based" (PLAN v3 section 3). While rules.turn_based is on, the
## world runs only on the player's actions: the clock holds the pause reason &"turn"
## while it waits, and one action (step, shot, dash, jump or wait) releases the world
## for rules.turn_duration of game time. The player half only: enemies keep moving
## in real time inside each turn.
##
## The clock runs while the tree is paused (it has to: it is what unpauses it), and it
## never acts while anything else (a panel, a transition, the report) pauses the tree.
## At every turn end the player stops on a tile centre (columns only under gravity,
## where falling happens during turns).

signal turn_started(number: int)
signal turn_ended(number: int)

const FREE_CLEARANCE := 20.0   ## a tile centre this far from any block is free for the player
const SNAP_SEARCH := 4         ## tiles searched around the player for a free one
const EPSILON := 0.0001

var player: CharacterBody2D
var arena: Arena

var turns := 0                 ## turns played this run
var active := false            ## B2 is on and the run is going
var _turn_left := 0.0          ## game seconds left in the current turn; 0 = waiting
var _stopped := false          ## the run is over: never hold the world again


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -5   # after PlayerInput (-10), before entities (0)
	EventBus.run_ended.connect(func(_o: StringName) -> void: _stop())
	EventBus.player_died.connect(_stop)


func is_waiting() -> bool:
	return active and _turn_left <= 0.0


func in_turn() -> bool:
	return active and _turn_left > 0.0


func _physics_process(delta: float) -> void:
	var want := RunState.rules.turn_based and not _stopped and is_instance_valid(player)
	if want != active:
		if want:
			_enter()
		else:
			_exit()
	if not active:
		return
	if _turn_left > 0.0:
		if get_tree().paused:
			return   # a prompt or the history opened mid-turn: the turn resumes after
		_turn_left -= delta
		if _turn_left > EPSILON:
			return
		_end_turn()
	_wait_for_action()


## Holds the world until the player acts, then starts a turn.
func _wait_for_action() -> void:
	RunState.set_pause(&"turn", true)
	if RunState.is_paused_except(&"turn"):
		return
	var input := player.get(&"input") as PlayerInput
	if input == null or not _act(input):
		return
	turns += 1
	_turn_left = RunState.rules.turn_duration
	RunState.set_pause(&"turn", false)
	turn_started.emit(turns)


## Plays one action from the input. Returns false when the input holds no action.
## Priority: dash, jump, step (a held fire also shoots on that turn), shot, wait.
func _act(input: PlayerInput) -> bool:
	var step := _cardinal(input.move)
	var dasher := Component.find(player, Dasher) as Dasher
	if input.dash_pressed and dasher and dasher.is_ready():
		var dir := step if step != Vector2.ZERO else _cardinal(input.aim_dir)
		dasher.try_dash(dir, 2.0 * Tuning.TILE, RunState.rules.turn_duration)
		return true
	var mover := Component.find(player, Mover) as Mover
	if input.jump_pressed and mover and mover.max_jumps() >= 1:
		mover.request_jump()
		_fire(input)
		return true
	var stepped := step != Vector2.ZERO and _step(step)
	var fired := _fire(input)
	return stepped or fired or input.wait_pressed


## Moves the player one tile in dir over the turn. Under gravity only sideways.
func _step(dir: Vector2) -> bool:
	var rules := RunState.rules
	if rules.gravity_enabled:
		var g := rules.gravity_dir.normalized()
		dir -= g * dir.dot(g)
		if dir.length() < 0.5:
			return false
		dir = dir.normalized()
	var target := tile_center(player.global_position) + dir * Tuning.TILE
	if not is_free(target):
		return false
	var mover := Component.find(player, Mover) as Mover
	if mover == null:
		return false
	mover.dash((target - player.global_position) / rules.turn_duration, rules.turn_duration)
	return true


func _fire(input: PlayerInput) -> bool:
	if not input.fire:
		return false
	var shooter := Component.find(player, Shooter) as Shooter
	return shooter != null and shooter.try_fire(input.aim_dir) != null


func _end_turn() -> void:
	_turn_left = 0.0
	var mover := Component.find(player, Mover) as Mover
	if mover:
		mover.stop()
	snap_player()
	turn_ended.emit(turns)


func _enter() -> void:
	active = true
	_turn_left = 0.0
	var mover := Component.find(player, Mover) as Mover
	if mover:
		mover.stop()
	snap_player()


func _exit() -> void:
	active = false
	_turn_left = 0.0
	RunState.set_pause(&"turn", false)


func _stop() -> void:
	_stopped = true
	if active:
		_exit()


## Puts the player on the nearest free tile centre. Under gravity only the column
## snaps, so a falling or standing body keeps its height.
func snap_player() -> void:
	if not is_instance_valid(player):
		return
	var p := player.global_position
	if RunState.rules.gravity_enabled:
		var g := RunState.rules.gravity_dir.normalized()
		var c := tile_center(p)
		var snapped_p := p + (c - p) - g * (c - p).dot(g)   # move across gravity only
		if is_free(snapped_p):
			player.global_position = snapped_p
		return
	player.global_position = nearest_free_tile(p)


## The centre of the tile containing p.
static func tile_center(p: Vector2) -> Vector2:
	var t := Tuning.TILE
	return Vector2((floorf(p.x / t) + 0.5) * t, (floorf(p.y / t) + 0.5) * t)


func is_free(p: Vector2) -> bool:
	if arena == null:
		return true
	return arena.bounds.has_point(p) and arena.distance_to_blocks(p) >= FREE_CLEARANCE


## The free tile centre closest to p (p's own tile if it is free).
func nearest_free_tile(p: Vector2) -> Vector2:
	var home := tile_center(p)
	var best := home
	var best_d := INF
	for dy in range(-SNAP_SEARCH, SNAP_SEARCH + 1):
		for dx in range(-SNAP_SEARCH, SNAP_SEARCH + 1):
			var c := home + Vector2(dx, dy) * Tuning.TILE
			var d := c.distance_squared_to(p)
			if d < best_d and is_free(c):
				best_d = d
				best = c
	return best


## The strongest axis of v as a unit step (4 directions); zero under a small stick tilt.
static func _cardinal(v: Vector2) -> Vector2:
	if v.length() < 0.5:
		return Vector2.ZERO
	if absf(v.x) >= absf(v.y):
		return Vector2(signf(v.x), 0.0)
	return Vector2(0.0, signf(v.y))
