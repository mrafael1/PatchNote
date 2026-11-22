class_name TurnClock
extends Node
## Big patch B2, "Turn-based" (PLAN v3 sections 3 and 3b). While rules.turn_based is
## on, the world runs only on the player's actions: the clock holds the pause reason
## &"turn" while it waits, and one action (a step, a shot, a dash or a wait; a jump
## only under gravity) releases the world for rules.turn_duration of game time.
##
## The clock runs while the tree is paused (it has to: it is what unpauses it), and it
## never acts while anything else (a panel, a transition, the report) pauses the tree.
## It fixes P (player_tile), the tile the player ends the turn on, before anything else
## plans, then emits EventBus.turn_started; at the turn end the player stands on P and
## EventBus.turn_ended fires. The enemy side listens to those two signals and publishes
## what it plans in `danger` and `intents`. This node is the neutral seam: the overlay,
## the bot and the tests read those fields and never name the patch's own code.

const FREE_CLEARANCE := 20.0   ## a tile centre this far from any block is free for the player
const SNAP_SEARCH := 4         ## tiles searched around the player for a free one
const EPSILON := 0.0001
const DASH_TILES := 2
## Entities in this group are moved on tiles by B2's turn logic; their own scripts
## (steering, contact damage, firing, projectile motion) stand aside. See on_grid().
const GRID_GROUP := &"on_grid"

static var _current: TurnClock

var player: CharacterBody2D
var arena: Arena:
	set(value):
		arena = value
		_free.clear()   # a new stage's arena (PLAN v6 4)

var turns := 0                 ## turns played this run
var active := false            ## B2 is on and the run is going
## The action of the turn under way (or the last one): &"step", &"dash", &"jump",
## &"shot" or &"wait".
var action: StringName = &""
## P (3b.1): the centre of the tile the player ends the current turn on. Between turns,
## the player's tile.
var player_tile := Vector2.ZERO
## The danger map (3b.4), rebuilt at every turn end and when an enemy joins the grid
## between turns; empty outside B2. Tile centre (Vector2) -> Array of sources, each a
## Dictionary {"kind": StringName, "entity": Node2D, "order": int}:
##   &"chaser", &"tank": a melee attack lands on this tile next turn if the player ends there;
##   &"aim": a shooter's locked line: its shot enters this tile next turn;
##   &"shot": a live enemy shot sits on this tile or enters it next turn.
## "entity" is the enemy or the shot (it may be freed later: check is_instance_valid);
## "order" is its attach order. The player is hit at a turn end only on a tile this map
## held when the player chose the action.
var danger := {}
## What the enemies will do next turn, for drawing (3b.7). Dictionaries:
##   {"kind": &"aim", "entity", "dir": Vector2, "tiles": Array[Vector2]} a shooter's locked
##     line, every tile its shot will cross until a wall, nearest first;
##   {"kind": &"shot", "entity", "dir": Vector2, "tiles": Array[Vector2]} the tiles a live
##     shot enters next turn;
##   {"kind": &"rest", "entity", "tile": Vector2} a tank that does not act next turn.
var intents: Array[Dictionary] = []

var _turn_left := 0.0          ## game seconds left in the current turn; 0 = waiting
var _stopped := false          ## the run is over: never hold the world again
var _free := {}                ## Vector2i tile -> is_free at its centre, for the current arena


## The clock of the running game, or null (the turn logic finds it here).
static func current() -> TurnClock:
	return _current


## True while B2's turn logic moves this entity on tiles.
static func on_grid(entity: Node) -> bool:
	return entity.is_in_group(GRID_GROUP)


func _enter_tree() -> void:
	_current = self


func _exit_tree() -> void:
	if _current == self:
		_current = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -5   # after PlayerInput (-10), before entities (0)
	EventBus.run_ended.connect(func(_o: StringName) -> void: _stop())
	EventBus.player_died.connect(_stop)
	# Enter as soon as the rule turns on, so the player snaps before the patch puts the
	# enemies on the grid (3b.2: the player first).
	EventBus.rules_changed.connect(func(_r: Resource) -> void: _sync())


func is_waiting() -> bool:
	return active and _turn_left <= 0.0


func in_turn() -> bool:
	return active and _turn_left > 0.0


func _physics_process(delta: float) -> void:
	_sync()
	if not active:
		return
	if _turn_left > 0.0:
		if get_tree().paused:
			return   # a prompt or the history opened mid-turn: the turn resumes after
		_turn_left -= delta
		if _turn_left > EPSILON:
			return
		_end_turn()
		# Resolution may have ended the run; otherwise hold the world now, and read the
		# next action on the next tick, against the new danger map (3b.1).
		if active and not _stopped:
			RunState.set_pause(&"turn", true)
		return
	_wait_for_action()


func _sync() -> void:
	var want := RunState.rules.turn_based and not _stopped and is_instance_valid(player)
	if want == active:
		return
	if want:
		_enter()
	else:
		_exit()


## Holds the world until the player acts, then starts a turn.
func _wait_for_action() -> void:
	if _stopped:
		return
	RunState.set_pause(&"turn", true)
	if RunState.is_paused_except(&"turn"):
		return
	var input := player.get(&"input") as PlayerInput
	if input == null or not _act(input):
		return
	turns += 1
	_turn_left = RunState.rules.turn_duration
	RunState.set_pause(&"turn", false)
	EventBus.turn_started.emit(turns)


## Plays one action from the input and fixes P. Returns false when the input holds no
## action, or only a refused one (no turn is taken). One action per turn (3b.1), in
## this priority: dash, jump (gravity only), step, shot, wait.
func _act(input: PlayerInput) -> bool:
	var here := tile_center(player.global_position)
	var step := _cardinal(input.move)
	var dasher := Component.find(player, Dasher) as Dasher
	if input.dash_pressed and dasher and dasher.is_ready():
		return _dash(dasher, step if step != Vector2.ZERO else _cardinal(input.aim_dir))
	var mover := Component.find(player, Mover) as Mover
	if input.jump_pressed and RunState.rules.gravity_enabled and mover and mover.max_jumps() >= 1:
		mover.request_jump()
		return _begin(&"jump", here)
	if step != Vector2.ZERO and _step(step):
		return true
	if _fire(input):
		return _begin(&"shot", here)
	if input.wait_pressed:
		# Auto-attack fires on wait turns only, so it never brings back step-and-shoot.
		if RunState.rules.auto_attack and player.has_method(&"auto_fire"):
			player.call(&"auto_fire")
		return _begin(&"wait", here)
	return false


func _begin(kind: StringName, tile: Vector2) -> bool:
	action = kind
	player_tile = tile
	return true


## Moves the player one tile in dir over the turn. Under gravity only sideways.
## Refused into a tile that is not free or that an enemy holds.
func _step(dir: Vector2) -> bool:
	var rules := RunState.rules
	if rules.gravity_enabled:
		var g := rules.gravity_dir.normalized()
		dir -= g * dir.dot(g)
		if dir.length() < 0.5:
			return false
		dir = dir.normalized()
	var target := tile_center(player.global_position) + dir * Tuning.TILE
	if not is_free(target) or enemy_tiles().has(tile_center(target)):
		return false
	var mover := Component.find(player, Mover) as Mover
	if mover == null:
		return false
	mover.dash((target - player.global_position) / rules.turn_duration, rules.turn_duration)
	return _begin(&"step", tile_center(target))


## Up to DASH_TILES along dir, to the farthest tile reached tile by tile that is free
## and not held by an enemy. Refused when that is no tile at all.
func _dash(dasher: Dasher, dir: Vector2) -> bool:
	if dir == Vector2.ZERO:
		return false
	var here := tile_center(player.global_position)
	var held := enemy_tiles()
	var tiles := 0
	for i in range(1, DASH_TILES + 1):
		var c := here + dir * Tuning.TILE * i
		if not is_free(c) or held.has(c):
			break
		tiles = i
	if tiles == 0:
		return false
	if not dasher.try_dash(dir, tiles * Tuning.TILE, RunState.rules.turn_duration):
		return false
	return _begin(&"dash", here + dir * Tuning.TILE * tiles)


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
	if RunState.rules.gravity_enabled:
		snap_player()
		player_tile = tile_center(player.global_position)
	else:
		player.global_position = player_tile
	EventBus.turn_ended.emit(turns)


func _enter() -> void:
	active = true
	_turn_left = 0.0
	_free.clear()
	danger = {}
	intents = []
	var mover := Component.find(player, Mover) as Mover
	if mover:
		mover.stop()
	snap_player()
	player_tile = tile_center(player.global_position)


func _exit() -> void:
	active = false
	_turn_left = 0.0
	danger = {}
	intents = []
	RunState.set_pause(&"turn", false)


func _stop() -> void:
	_stopped = true
	if active:
		_exit()


## The enemy side hands over the next turn's danger map and intents (shapes above).
## Ignored once B2 is off or the run is over.
func publish(map: Dictionary, next_intents: Array[Dictionary]) -> void:
	if not active:
		return
	danger = map
	intents = next_intents


## Tile centres held by enemies on the grid (they stand on tile centres between turns).
func enemy_tiles() -> Dictionary:
	var out := {}
	for e in get_tree().get_nodes_in_group(GRID_GROUP):
		if e.is_in_group(&"enemy") and not e.is_queued_for_deletion():
			out[tile_center((e as Node2D).global_position)] = true
	return out


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


## The tile containing p, as grid coordinates.
static func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / Tuning.TILE), floori(p.y / Tuning.TILE))


static func centre_of(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * Tuning.TILE


func is_free(p: Vector2) -> bool:
	if arena == null:
		return true
	return arena.bounds.has_point(p) and arena.distance_to_blocks(p) >= FREE_CLEARANCE


## is_free at a tile's centre, cached.
func free_tile(tile: Vector2i) -> bool:
	if not _free.has(tile):
		_free[tile] = is_free(centre_of(tile))
	return _free[tile]


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
