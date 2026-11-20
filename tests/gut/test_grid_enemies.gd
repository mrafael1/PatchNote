extends GutTest
## B2's enemy half (PLAN v3 3b.8) in the real arena: the grid at every turn end,
## refused steps and dashes, one action per turn, each enemy's plan, shots on tiles,
## kills during a turn, deaths at a turn end, the danger promise over thousands of
## random turns, same seed same run, and swaps in the middle of a wave.
##
## Like the overlay and the bot, this reads B2's enemy side only through the TurnClock
## (player_tile, danger, intents), the entities and the run log, never through
## turn_mode's own scripts. Every turn end of every test goes through _between(), which
## checks the grid, the shots and the danger promise.

const CHASER := preload("res://entities/enemy_chaser.tscn")
const TANK := preload("res://entities/enemy_tank.tscn")
const SHOOTER := preload("res://entities/enemy_shooter.tscn")
const PROJECTILE := preload("res://entities/projectile.tscn")
const FAST_TURN := 4.0 / 60.0   ## long runs play 4 ticks a turn instead of 15
const NO_TILE := Vector2i(-1, -1)
const DIRS: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]
const EIGHT: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP,
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]
## Results of a source on P that land no logged hit (3b.4), besides no_shot (the
## projectile cap): hits blocked by Health, and the source gone during the turn.
const BLOCKED := ["iframes", "grace", "dead"]
const GONE := ["died", "removed"]
const TUNING_KEYS: Array[String] = [
	"spawn_interval_start", "spawn_interval_end", "spawn_tank_delay", "hard_max_projectiles",
]


## Acts only while the clock waits for an action, and for exactly one tick: the next
## queued action, otherwise the policy's. When a turn has ended since it last acted it
## first calls `between`, which sees the world as the next action will (resolved, with
## the new danger map), then it notes the map and the log as they stand before acting.
class TurnInput extends PlayerInput:
	var clock: TurnClock
	var actions: Array[Dictionary] = []
	var policy: Callable           ## () -> Dictionary, used when nothing is queued
	var between: Callable          ## () -> void, once per turn end
	var seen_turns := 0
	var map_seen := {}             ## the danger map when the last action was chosen
	var log_seen := 0              ## the run log's size then

	func _physics_process(_delta: float) -> void:
		move = Vector2.ZERO
		fire = false
		dash_pressed = false
		jump_pressed = false
		wait_pressed = false
		if clock == null or not clock.is_waiting() or RunState.is_paused_except(&"turn"):
			return
		if clock.turns != seen_turns:
			seen_turns = clock.turns
			if between.is_valid():
				between.call()
		map_seen = clock.danger
		log_seen = RunState.run_log.size()
		var a: Dictionary = {}
		if not actions.is_empty():
			a = actions.pop_front()
		elif policy.is_valid():
			a = policy.call()
		match a.get("kind", &""):
			&"step":
				move = a.dir
				fire = a.get("fire", false)
			&"dash":
				move = a.dir
				dash_pressed = true
			&"shot":
				aim_dir = a.dir
				fire = true
			&"wait":
				wait_pressed = true


var game: Main
var clock: TurnClock
var input: TurnInput
var b1: Mutation
var b2: Mutation
var rng := RandomNumberGenerator.new()   ## the random policy's own generator
var problems: Array[String] = []
var stats := {}
var trace: Array[String] = []
var recording := false

var _saved := {}
var _turn_duration := 0.0
var _last_turn := 0
var _turn_hits := 0
var _next_id := 0
var _known_shots := {}   ## test id -> true: the shots seen at the last turn end
var _shot_next := {}     ## test id -> tile it must stand on at the next turn end, or NO_TILE: gone
var _shot_age := {}      ## test id -> turn ends seen
var _aimed: Array[Dictionary] = []   ## last turn end's aims: the tiles each new shot enters


func before_each() -> void:
	b1 = MutationDB.get_mutation(&"motion_time")
	b2 = MutationDB.get_mutation(&"turn_mode")
	_turn_duration = b2.get(&"turn_duration")
	for key in TUNING_KEYS:
		_saved[key] = Tuning.get(key)
	problems.clear()
	stats = {"turns": 0, "marked": 0, "hits": 0, "results": {}}
	trace.clear()
	recording = false


func after_each() -> void:
	b2.set(&"turn_duration", _turn_duration)
	for key: String in _saved:
		Tuning.set(key, _saved[key])
	await _drop_game()


# --- Setup and driving ------------------------------------------------------------

## A fresh game on run_seed, director and spawner off, the player invincible and driven
## by a TurnInput, standing on player_at if given. `fast` shortens B2's turn.
func _start(run_seed: int, player_at := NO_TILE, fast := false) -> void:
	if fast:
		b2.set(&"turn_duration", FAST_TURN)
	# Start on a physics frame boundary, so the same seed sees the same frames before
	# B2 whether this is the test's first game or a later one.
	await wait_physics_frames(1)
	Main.next_seed = run_seed
	game = load("res://main.tscn").instantiate() as Main
	add_child(game)
	await wait_physics_frames(2)
	game.director.enabled = false
	game.spawner.enabled = false
	RunState.invincible = true
	clock = game.turn_clock
	input = TurnInput.new()
	input.clock = clock
	input.between = _between
	game.player.set_input(input)
	if player_at != NO_TILE:
		game.player.global_position = TurnClock.centre_of(player_at)


func _drop_game() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await wait_physics_frames(1)
	game = null
	RunState.reset(0)
	RunState.world = null


func _enter_b2() -> void:
	RunState.swap_big(b2)
	_track()
	await wait_physics_frames(1)


## Starts the turn checks afresh (on B2 entry: nothing before it is a turn).
func _track() -> void:
	input.seen_turns = clock.turns
	_last_turn = clock.turns
	_known_shots.clear()
	for s in _live(&"enemy_projectile"):
		_known_shots[_id_of(s)] = true
	_shot_next.clear()
	_shot_age.clear()
	_aimed.clear()


## Queues actions and returns once each has been played (or refused), the world waits
## again and the last turn end has been checked.
func _play(actions: Array[Dictionary]) -> void:
	input.actions.append_array(actions)
	for i in 2000:
		await wait_physics_frames(1)
		if not clock.active:
			return
		if input.actions.is_empty() and clock.is_waiting() and input.seen_turns == clock.turns:
			return
	fail_test("the queued actions never finished")


## The random policy plays `count` more turns.
func _run_policy(count: int) -> void:
	input.policy = _random_action
	var goal := clock.turns + count
	for i in count * 40 + 100:
		if clock.turns >= goal or not clock.active:
			break
		await wait_physics_frames(5)
	input.policy = Callable()
	await _play([])


## Seeded, and blind to danger (3b.8: not the avoiding bot). Refused picks cost no turn,
## so the next tick simply picks again.
func _random_action() -> Dictionary:
	var roll := rng.randf()
	var dir := DIRS[rng.randi_range(0, 3)]
	if roll < 0.45:
		return _step(dir)
	if roll < 0.55:
		return _dash(dir)
	if roll < 0.8:
		return _shot(Vector2(EIGHT[rng.randi_range(0, 7)]).normalized())
	return _wait()


static func _step(dir: Vector2, fire := false) -> Dictionary:
	return {"kind": &"step", "dir": dir, "fire": fire}


static func _dash(dir: Vector2) -> Dictionary:
	return {"kind": &"dash", "dir": dir}


static func _shot(dir: Vector2) -> Dictionary:
	return {"kind": &"shot", "dir": dir}


static func _wait() -> Dictionary:
	return {"kind": &"wait"}


func _waits(n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in n:
		out.append(_wait())
	return out


## Spawns an enemy on a tile centre; it joins the grid when it enters the tree.
func _spawn(scene: PackedScene, tile: Vector2i, params := {}) -> Node2D:
	var e := RunState.spawn(scene, TurnClock.centre_of(tile), params) as Node2D
	await wait_physics_frames(1)
	return e


## A mixed wave at the arena's spawn points: chasers, two shooters and a tank.
func _spawn_mix() -> void:
	var points := game.arena.spawn_points
	var scenes: Array[PackedScene] = [CHASER, CHASER, SHOOTER, CHASER, TANK, SHOOTER, CHASER]
	for i in scenes.size():
		RunState.spawn(scenes[i], points[(i * 5) % points.size()])


func _health() -> Health:
	return Component.find(game.player, Health) as Health


# --- Reading the world ------------------------------------------------------------

func _live(group: StringName) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for n in get_tree().get_nodes_in_group(group):
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			out.append(n as Node2D)
	return out


static func _tile(n: Node2D) -> Vector2i:
	return TurnClock.tile_of(n.global_position)


func _p() -> Vector2i:
	return TurnClock.tile_of(clock.player_tile)


func _id_of(n: Node) -> int:
	if not n.has_meta(&"grid_test_id"):
		_next_id += 1
		n.set_meta(&"grid_test_id", _next_id)
	return n.get_meta(&"grid_test_id")


static func _alive(entity: Variant) -> bool:
	if not is_instance_valid(entity):
		return false
	var node := entity as Node
	var health := Component.find(node, Health) as Health
	return not node.is_queued_for_deletion() and (health == null or not health.dead)


static func _role(e: Node) -> String:
	return "shooter" if Component.find(e, Shooter) != null else String(e.get(&"archetype"))


func _intents(kind: StringName, entity: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for intent in clock.intents:
		if intent.kind == kind and is_instance_valid(intent.entity) and intent.entity == entity:
			out.append(intent)
	return out


## The danger map's sources on a tile.
func _sources(tile: Vector2i) -> Array:
	return clock.danger.get(TurnClock.centre_of(tile), [])


func _marked_by(tile: Vector2i, entity: Node) -> bool:
	for s: Dictionary in _sources(tile):
		if is_instance_valid(s.entity) and s.entity == entity:
			return true
	return false


func _hits(from: int, kind := &"") -> int:
	var n := 0
	for i in range(from, RunState.run_log.size()):
		var e := RunState.run_log[i]
		if e.event == &"player_hit" and (kind == &"" or e.kind == kind):
			n += 1
	return n


func _events(from: int, event: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(from, RunState.run_log.size()):
		if RunState.run_log[i].event == event:
			out.append(RunState.run_log[i])
	return out


## The one wall rule (3b.3): a step is blocked if its tile is not free, and a diagonal
## step also if either orthogonal neighbour is not free.
func _blocked(from: Vector2i, d: Vector2i) -> bool:
	if not clock.free_tile(from + d):
		return true
	if d.x != 0 and d.y != 0:
		return not clock.free_tile(from + Vector2i(d.x, 0)) or not clock.free_tile(from + Vector2i(0, d.y))
	return false


## Up to `steps` tiles from `from` along d, stopping before the first blocked step.
func _line(from: Vector2i, d: Vector2i, steps: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var t := from
	for i in steps:
		if _blocked(t, d):
			break
		t += d
		out.append(t)
	return out


static func _centres(tiles: Array[Vector2i]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for t in tiles:
		out.append(TurnClock.centre_of(t))
	return out


## Breadth-first distances from `from` over free tiles, 4-way.
func _field(from: Vector2i) -> Dictionary:
	var field := {from: 0}
	var queue: Array[Vector2i] = [from]
	var i := 0
	while i < queue.size():
		var t := queue[i]
		i += 1
		for d in EIGHT.slice(0, 4):
			var n: Vector2i = t + d
			if not field.has(n) and clock.free_tile(n):
				field[n] = int(field[t]) + 1
				queue.append(n)
	return field


static func _misalignment(v: Vector2i) -> int:
	var x := absi(v.x)
	var y := absi(v.y)
	return mini(mini(x, y), absi(x - y))


# --- The checks at every turn end ---------------------------------------------------

func _problem(text: String) -> void:
	if problems.size() < 25:
		problems.append("turn %d: %s" % [clock.turns, text])


func _assert_clean() -> void:
	assert_eq(problems, [] as Array[String], "every turn end held the grid, the shots and the danger promise")


func _between() -> void:
	if clock.turns != _last_turn + 1:
		_problem("follows turn %d" % _last_turn)
	_last_turn = clock.turns
	_check_grid()
	_check_shots()
	_check_danger()
	if recording:
		trace.append(_turn_state())


## 3b.8 Grid: every enemy and every shot on a tile centre, no two enemies on one tile,
## none on the player's, and the player on P.
func _check_grid() -> void:
	var p := clock.player_tile
	if game.player.global_position.distance_to(p) > 0.5:
		_problem("the player is at %s, P is %s" % [game.player.global_position, p])
	if not clock.is_free(p):
		_problem("P %s is not free" % p)
	var held := {}
	for e in _live(&"enemy"):
		var c := TurnClock.tile_center(e.global_position)
		if e.global_position.distance_to(c) > 0.5:
			_problem("%s is off its tile centre at %s" % [e.name, e.global_position])
		if not TurnClock.on_grid(e):
			_problem("%s is not on the grid" % e.name)
		if not clock.is_free(c):
			_problem("%s stands on a blocked tile %s" % [e.name, c])
		if c == p:
			_problem("%s stands on the player's tile" % e.name)
		if held.has(c):
			_problem("%s shares %s with %s" % [e.name, c, held[c]])
		held[c] = e.name
	for s in _live(&"enemy_projectile"):
		if s.global_position.distance_to(TurnClock.tile_center(s.global_position)) > 0.5:
			_problem("a shot is off its tile centre at %s" % s.global_position)
		if not TurnClock.on_grid(s):
			_problem("an enemy shot is not on the grid")


## 3b.3: each shot moves exactly grid_shot_tiles along its line per turn or is gone
## (stopped by a wall or a corner, or it hit), shots appear only where last turn's aims
## said, an aim always has a clear line through P, and the intents match the wall rule.
func _check_shots() -> void:
	var p := _p()
	var now := {}
	for s in _live(&"enemy_projectile"):
		now[_id_of(s)] = _tile(s)
	for id: int in _shot_next:
		if not now.has(id):
			continue
		if _shot_next[id] == NO_TILE:
			_problem("a shot that could not move %d tiles is still there" % Tuning.grid_shot_tiles)
		elif now[id] != _shot_next[id]:
			_problem("a shot is on %s, its line said %s" % [now[id], _shot_next[id]])
	var fresh: Array[Vector2i] = []
	for id: int in now:
		_shot_age[id] = int(_shot_age.get(id, 0)) + 1
		if _shot_age[id] >= Tuning.grid_shot_turns:   # 8 turns of motion: the 8th resolution removes it
			_problem("a shot outlived grid_shot_turns")
		if not _known_shots.has(id):
			fresh.append(now[id])
	for aim: Dictionary in _aimed:
		var i := fresh.find(aim.path[-1])
		if i >= 0:
			fresh.remove_at(i)
		elif not aim.path.has(p) and not aim.capped:   # a shot that entered P hit and is gone
			_problem("an aiming shooter fired no shot onto %s, with room under the projectile cap" % aim.path[-1])
	if not fresh.is_empty():
		_problem("shots no aim announced, on %s" % [fresh])
	_known_shots.clear()
	for id: int in now:
		_known_shots[id] = true
	_shot_next.clear()
	_aimed.clear()
	# Room under the projectile cap for next turn's shots, after the player's own.
	var room := Tuning.hard_max_projectiles - 1 - RunState.count(&"player_projectile") - RunState.count(&"enemy_projectile")
	for intent in clock.intents:
		if not is_instance_valid(intent.entity) or intent.kind == &"rest":
			continue
		var from := _tile(intent.entity as Node2D)
		var d := Vector2i(intent.dir)
		if not EIGHT.has(d):
			_problem("a line along %s" % intent.dir)
			continue
		var first := _line(from, d, Tuning.grid_shot_tiles)
		var moves := first.size() == Tuning.grid_shot_tiles and not _blocked(first[-1], d)
		if intent.kind == &"shot":
			if _centres(first) != intent.tiles:
				_problem("a shot on %s goes to %s, its line is %s" % [from, intent.tiles, first])
			_shot_next[_id_of(intent.entity)] = first[-1] if moves else NO_TILE
		elif intent.kind == &"aim":
			var line := _line(from, d, Tuning.grid_shot_tiles * Tuning.grid_shot_turns)
			if _centres(line) != intent.tiles:
				_problem("an aim from %s is drawn %s, its line is %s" % [from, intent.tiles, line])
			if not line.has(p):
				_problem("a shooter on %s aimed along %s without a clear line to P %s" % [from, d, p])
			if moves:
				# Shooters fire in attach order, the order of the intents.
				_aimed.append({"path": first, "capped": room <= _aimed.size()})


## 3b.4 Danger: every hit, logged or blocked, comes at the turn-end resolution on a tile
## the map marked when the player chose the action, and every source on the tile the
## player ended on hits unless a logged exemption says why not.
func _check_danger() -> void:
	var p := clock.player_tile
	var sources: Array = input.map_seen.get(p, [])
	_turn_hits = _hits(input.log_seen)
	var entries := _events(input.log_seen, &"turn_danger")
	stats["turns"] += 1
	stats["hits"] += _turn_hits
	if not sources.is_empty():
		stats["marked"] += 1
	if _turn_hits > 0 and sources.is_empty():
		_problem("%d hit(s) on an unmarked tile %s" % [_turn_hits, p])
	if entries.is_empty():
		if not sources.is_empty():
			_problem("ended on a marked tile and nothing was logged")
		return
	var entry: Dictionary = entries[-1]
	if entries.size() != 1 or entry.turn != clock.turns:
		_problem("turn_danger entries %s" % [entries])
		return
	if not entry.unmarked.is_empty():
		_problem("attacks on P that the map never marked: %s" % [entry.unmarked])
	if entry.hits != _turn_hits:
		_problem("%d hit(s) this turn, %d at resolution" % [_turn_hits, entry.hits])
	if entry.marked == sources.is_empty() or entry.sources.size() != sources.size():
		_problem("the log says %s, the map held %d source(s)" % [entry, sources.size()])
		return
	var landed := 0
	for i in sources.size():
		var result: String = entry.sources[i].result
		var results: Dictionary = stats["results"]
		results[result] = int(results.get(result, 0)) + 1
		if result == "hit" or result == "invincible":
			landed += 1
		elif result in GONE:
			if _alive(sources[i].entity):
				_problem("a %s source is logged %s but lives" % [sources[i].kind, result])
		elif result == "no_shot":
			if sources[i].kind != &"aim":
				_problem("no_shot for a %s source" % sources[i].kind)
		elif not result in BLOCKED:
			_problem("a %s source on P: %s" % [sources[i].kind, result])
	if landed != _turn_hits:
		_problem("%d source(s) landed, %d hit(s) logged" % [landed, _turn_hits])


## One line per turn for same seed, same run: P, every enemy's tile and role, every
## shot's tile, and the hits.
func _turn_state() -> String:
	var parts: Array[String] = []
	for e in _live(&"enemy"):
		parts.append("e%s%s" % [_tile(e), _role(e)])
	for s in _live(&"enemy_projectile"):
		parts.append("s%s" % _tile(s))
	parts.sort()
	return "%s h%d %s" % [_p(), _turn_hits, " ".join(PackedStringArray(parts))]


## A shot's lane along one of `dirs`: the shooter on S and T, `len` tiles on (odd, at
## most 7), the last tile the shot can enter. Every step S..T is open and the step
## after T is blocked: by a corner when `corner` (T + d itself is free), by a wall
## otherwise. The player stands on P, two tiles before T, and steps out of the line
## by `step`.
func _find_lane(dirs: Array[Vector2i], corner: bool) -> Dictionary:
	for length: int in [7, 5, 3]:
		for d in dirs:
			for y in range(1, Arena.ROWS - 1):
				for x in range(1, Arena.COLS - 1):
					var s := Vector2i(x, y)
					if not clock.free_tile(s) or _line(s, d, length).size() != length:
						continue
					var t := s + d * length
					if not _blocked(t, d) or clock.free_tile(t + d) != corner:
						continue
					var p := s + d * (length - 2)
					for step in EIGHT.slice(0, 4):
						if clock.free_tile(p + step) and _misalignment(p + step - s) != 0:
							return {"d": d, "len": length, "s": s, "p": p, "t": t, "step": Vector2(step)}
	return {}


func _assert_left_the_grid() -> void:
	assert_false(clock.active)
	assert_false(RunState.is_paused_for(&"turn"))
	for e in RunState.live_entities():
		assert_false(TurnClock.on_grid(e), "%s left the grid" % e.name)
	var snap := RunState.snapshot()
	var tag := String(b2.id)
	for sig: StringName in snap.connections:
		for owner: String in snap.connections[sig]:
			assert_false(owner.begins_with(tag + "."), "listener left: %s" % owner)
	for path: String in snap.entities:
		for comp: String in snap.entities[path]:
			assert_false(comp.ends_with("@" + tag), "component left on %s" % path)
	assert_false(RunState.patch_state.has(b2.id))


## Off the grid every enemy steers again: some of them want to move.
func _assert_enemies_steer() -> void:
	var steering := 0
	for e in _live(&"enemy"):
		var mover := Component.find(e, Mover) as Mover
		if mover and mover.wish != Vector2.ZERO:
			steering += 1
	assert_gt(steering, 0, "enemies steer in real time again")


func _shot_into_flight() -> void:
	RunState.spawn(PROJECTILE, TurnClock.centre_of(Vector2i(62, 4)), {
		&"kind": &"enemy_projectile", &"faction": &"enemy", &"velocity": Vector2(0, 30)})
	await wait_physics_frames(1)


# --- Steps and dashes ---------------------------------------------------------------

func test_a_step_into_an_enemy_is_refused_and_takes_no_turn() -> void:
	await _start(1, Vector2i(62, 10))
	await _enter_b2()
	var chaser := await _spawn(CHASER, Vector2i(63, 10))
	assert_eq(_tile(chaser), Vector2i(63, 10))
	var t0 := RunState.game_time
	var turns := clock.turns
	await _play([_step(Vector2.RIGHT)])
	assert_eq(clock.turns, turns, "no turn taken")
	assert_eq(RunState.game_time, t0, "the world did not run")
	assert_eq(_tile(game.player), Vector2i(62, 10))
	assert_true(clock.is_waiting() and RunState.is_paused_for(&"turn"))
	await _play([_step(Vector2.LEFT)])
	assert_eq(clock.turns, turns + 1)
	assert_eq(_tile(game.player), Vector2i(61, 10))
	_assert_clean()


func test_a_dash_stops_before_walls_and_enemies_and_a_zero_tile_dash_is_refused() -> void:
	await _start(2, Vector2i(63, 4))
	await _enter_b2()
	assert_false(clock.free_tile(Vector2i(65, 4)), "the border is two tiles right")
	var dasher := Component.find(game.player, Dasher) as Dasher
	var turns := clock.turns
	await _play([_dash(Vector2.RIGHT)])
	assert_eq(clock.turns, turns + 1)
	assert_eq(_tile(game.player), Vector2i(64, 4), "the dash stops before the wall")
	await _ready_to_dash(dasher)

	turns = clock.turns
	await _play([_dash(Vector2.RIGHT)])
	assert_eq(clock.turns, turns, "a dash into the wall would move 0 tiles: refused")
	assert_eq(_tile(game.player), Vector2i(64, 4))
	assert_true(dasher.is_ready(), "a refused dash spends no cooldown")

	var chaser := await _spawn(CHASER, Vector2i(64, 6))
	await _play([_dash(Vector2.DOWN)])
	assert_eq(_tile(game.player), Vector2i(64, 5), "the dash stops before the enemy")
	await _ready_to_dash(dasher)
	turns = clock.turns
	await _play([_dash(Vector2.DOWN)])
	assert_eq(clock.turns, turns, "a dash into an enemy would move 0 tiles: refused")
	assert_eq(_tile(game.player), Vector2i(64, 5))
	assert_eq(_tile(chaser), Vector2i(64, 6))
	_assert_clean()


func _ready_to_dash(dasher: Dasher) -> void:
	for i in 8:
		if dasher.is_ready():
			return
		await _play([_wait()])
	assert_true(dasher.is_ready(), "the dash cooled down")


# --- One action per turn -------------------------------------------------------------

func test_one_action_a_step_never_shoots_and_auto_attack_fires_only_on_waits() -> void:
	await _start(3, Vector2i(62, 10))
	await _enter_b2()
	var shots := [0]
	var count := func(p: Node) -> void:
		if p.get(&"faction") == &"player":
			shots[0] += 1
	EventBus.projectile_fired.connect(count)
	input.aim_dir = Vector2.RIGHT
	await _play([_step(Vector2.LEFT, true)])
	assert_eq(_tile(game.player), Vector2i(61, 10), "the step was taken")
	assert_eq(shots[0], 0, "a step with fire held does not shoot")
	await _play([_shot(Vector2.RIGHT)])
	assert_eq(shots[0], 1, "a shot turn shoots once")

	assert_true(RunState.apply(MutationDB.get_mutation(&"auto_attack")))
	await _spawn(TANK, Vector2i(61, 16))
	shots[0] = 0
	await _play([_step(Vector2.UP), _dash(Vector2.UP)])
	assert_eq(_tile(game.player), Vector2i(61, 7))
	assert_eq(shots[0], 0, "auto-attack never fires on a step or a dash turn")
	await _play([_wait()])
	assert_eq(shots[0], 1, "auto-attack fires on a wait turn")
	EventBus.projectile_fired.disconnect(count)
	_assert_clean()


# --- Enemies ------------------------------------------------------------------------

func test_a_chaser_next_to_p_attacks_and_one_further_away_steps_toward_it() -> void:
	await _start(4, Vector2i(62, 10))
	await _enter_b2()
	_health().invuln_time = 0.0
	var near := await _spawn(CHASER, Vector2i(63, 10))
	var far := await _spawn(CHASER, Vector2i(62, 13))
	assert_true(_marked_by(_p(), near), "the adjacent chaser marks P")
	var from := RunState.run_log.size()
	await _play([_wait()])
	assert_eq(_tile(near), Vector2i(63, 10), "next to P it attacks instead of moving")
	assert_eq(_tile(far), Vector2i(62, 12), "further away it steps toward P")
	assert_eq(_hits(from, &"contact"), 1)
	await _play([_wait()])
	assert_eq(_tile(far), Vector2i(62, 11))
	from = RunState.run_log.size()
	await _play([_wait()])
	assert_eq(_tile(far), Vector2i(62, 11), "now next to P: it attacks")
	assert_eq(_hits(from, &"contact"), 2, "both chasers hit")
	_assert_clean()


func test_a_chaser_around_a_wall_follows_the_shortest_free_path() -> void:
	var p := Vector2i(34, 16)
	await _start(5, p)
	await _enter_b2()
	for x in range(32, 37):
		assert_false(clock.free_tile(Vector2i(x, 15)), "the ledge between them")
	var chaser := await _spawn(CHASER, Vector2i(33, 13))
	var field := _field(p)
	var d: int = field[Vector2i(33, 13)]
	assert_eq(d, 8, "around the ledge's near end; the far end is 10")
	for i in d - 1:
		await _play([_wait()])
		assert_eq(int(field.get(_tile(chaser), -1)), d - 1 - i, "turn %d: one step down the shortest path" % (i + 1))
	var from := RunState.run_log.size()
	var at := _tile(chaser)
	await _play([_wait()])
	assert_eq(_tile(chaser), at, "it arrived and attacks")
	assert_eq(_hits(from, &"contact"), 1)
	_assert_clean()


func test_a_tank_acts_every_second_turn_and_hits_all_eight_neighbours() -> void:
	await _start(6, Vector2i(62, 10))
	await _enter_b2()
	_health().invuln_time = 0.0
	var near := await _spawn(TANK, Vector2i(63, 11))   # diagonal to P
	var far := await _spawn(TANK, Vector2i(62, 15))
	assert_false(_marked_by(_p(), near), "a tank that rests next turn marks nothing")
	assert_eq(_intents(&"rest", near).size(), 1, "and shows its resting mark")
	var far_at := _tile(far)
	for turn in range(1, 5):
		var from := RunState.run_log.size()
		await _play([_wait()])
		var acted := turn % 2 == 0
		assert_eq(_hits(from, &"contact"), 1 if acted else 0, "turn %d: the diagonal tank hits only when it acts" % turn)
		assert_eq(_tile(far) != far_at, acted, "turn %d: the far tank moves only when it acts" % turn)
		far_at = _tile(far)
		if not acted:
			for o in EIGHT:
				var t := _tile(near) + o
				if clock.free_tile(t):
					assert_true(_marked_by(t, near), "turn %d: the acting tank marks %s" % [turn, t])
	_assert_clean()


func test_a_shooter_off_its_lines_aligns_within_six_turns_while_the_player_waits() -> void:
	await _start(7, Vector2i(61, 13))
	await _enter_b2()
	var shooter := await _spawn(SHOOTER, Vector2i(64, 8))
	var field := _field(_p())
	var band := Vector2i(roundi(Tuning.shooter_near / Tuning.TILE), roundi(Tuning.shooter_far / Tuning.TILE))
	var d: int = field[_tile(shooter)]
	assert_between(d, band.x, band.y, "the shooter starts in the band")
	assert_gt(_misalignment(_p() - _tile(shooter)), 0, "and off its lines")
	var aligned_after := -1
	for turn in range(1, 7):
		await _play([_wait()])
		if _misalignment(_p() - _tile(shooter)) == 0:
			aligned_after = turn
			break
	assert_between(aligned_after, 1, 6, "aligned within 6 turns")
	await _play([_wait()])
	assert_eq(_intents(&"aim", shooter).size(), 1, "aligned with a clear line, it aims on its next action")
	_assert_clean()


func test_a_shooter_never_aims_through_a_wall() -> void:
	await _start(8, Vector2i(34, 16))
	await _enter_b2()
	assert_false(clock.free_tile(Vector2i(34, 15)), "a ledge between them")
	var shooter := await _spawn(SHOOTER, Vector2i(34, 10))
	assert_lte(6.0 * Tuning.TILE, Tuning.shooter_range, "on its column, in range")
	await _play([_wait()])
	assert_eq(_intents(&"aim", shooter).size(), 0, "no aim without a clear line")
	_assert_clean()


func test_an_aiming_shooter_fires_on_its_next_action_along_the_locked_line() -> void:
	await _start(9, Vector2i(62, 10))
	await _enter_b2()
	var shooter := await _spawn(SHOOTER, Vector2i(62, 16))
	await _play([_wait()])
	var aims := _intents(&"aim", shooter)
	assert_eq(aims.size(), 1, "in line, in range, clear: it aims")
	if aims.is_empty():
		return
	assert_eq(aims[0].dir, Vector2.UP)
	assert_true(_marked_by(Vector2i(62, 15), shooter) and _marked_by(Vector2i(62, 14), shooter),
			"the first tiles its shot will enter are marked")
	await _play([_step(Vector2.LEFT)])
	var shots := _live(&"enemy_projectile")
	assert_eq(shots.size(), 1, "it fired on its next action, though the player left the line")
	if shots.is_empty():
		return
	assert_eq(_tile(shots[0]), Vector2i(62, 14), "from its tile, grid_shot_tiles along the locked line")
	assert_eq(_tile(shooter), Vector2i(62, 16), "a firing shooter does not move")
	await _play([_wait()])
	assert_eq(_tile(shots[0]), Vector2i(62, 12))
	_assert_clean()


## 3b.2 Hold: aligned with a clear line in the band and only waiting on its cooldown,
## a shooter stays where it is, then aims again once the cooldown is over.
func test_a_shooter_on_cooldown_holds_its_line() -> void:
	await _start(10, Vector2i(62, 10))
	await _enter_b2()
	var shooter := await _spawn(SHOOTER, Vector2i(62, 16))
	await _play([_wait()])
	assert_eq(_intents(&"aim", shooter).size(), 1, "it aims")
	await _play([_wait()])
	assert_eq(_intents(&"aim", shooter).size(), 0, "it fired")
	var home := _tile(shooter)
	var aimed_after := -1
	for turn in range(1, Tuning.grid_shooter_cooldown + 3):
		await _play([_wait()])
		assert_eq(_tile(shooter), home, "it holds its tile on turn %d of the cooldown" % turn)
		if not _intents(&"aim", shooter).is_empty():
			aimed_after = turn
			break
	assert_eq(aimed_after, Tuning.grid_shooter_cooldown, "it aims again when the cooldown is over")
	_assert_clean()


# --- Shots --------------------------------------------------------------------------

func test_a_straight_shot_moves_two_tiles_a_turn_and_stops_at_a_wall() -> void:
	await _shot_lane(EIGHT.slice(0, 4), false)


func test_a_diagonal_shot_moves_two_tiles_a_turn_and_stops_at_a_corner() -> void:
	await _shot_lane(EIGHT.slice(4, 8), true)


## The shooter on S aims at P, the player steps aside, and the shot goes 2 tiles a turn
## (S+2d, S+4d, ...) until one tile is left, enters T, where the next step is blocked,
## and is removed.
func _shot_lane(dirs: Array[Vector2i], corner: bool) -> void:
	assert_eq(Tuning.grid_shot_tiles, 2, "the lane is laid out for 2 tiles a turn")
	var stop := "corner" if corner else "wall"
	await _start(10, NO_TILE)
	var lane := _find_lane(dirs, corner)
	assert_false(lane.is_empty(), "the arena has a lane that ends at a %s" % stop)
	if lane.is_empty():
		return
	var d: Vector2i = lane.d
	var s: Vector2i = lane.s
	var length: int = lane.len
	game.player.global_position = TurnClock.centre_of(lane.p)
	await _enter_b2()
	assert_eq(_p(), lane.p)
	var shooter := await _spawn(SHOOTER, s)
	assert_eq(_tile(shooter), s)
	await _play([_wait()])
	var aims := _intents(&"aim", shooter)
	assert_eq(aims.size(), 1, "it aims at P")
	if aims.is_empty():
		return
	var line: Array[Vector2i] = []
	for i in range(1, length + 1):
		line.append(s + d * i)
	assert_eq(aims[0].tiles, _centres(line), "the locked line runs to the last open tile")
	await _play([_step(lane.step)])
	var shots := _live(&"enemy_projectile")
	assert_eq(shots.size(), 1)
	if shots.is_empty():
		return
	var shot := shots[0]
	for k in range(2, length, 2):
		if k > 2:
			await _play([_wait()])
		assert_eq(_tile(shot), s + d * k, "exactly %d tiles a turn along %s" % [Tuning.grid_shot_tiles, d])
	var last: Array[Vector2i] = [lane.t]
	var next := _intents(&"shot", shot)
	assert_eq(next.size(), 1)
	if next.size() == 1:
		assert_eq(next[0].tiles, _centres(last), "one tile left before the %s" % stop)
	await _play([_wait()])
	assert_eq(_live(&"enemy_projectile").size(), 0, "stopped at the %s and removed" % stop)
	_assert_clean()


## Fails today, from a bug outside B2's code: RunState.spawn() counts a spawn as
## pending under the scene's default kind, read before the params are set, and
## register_entity() releases it under the kind the params gave. Every enemy shot
## (projectile.tscn defaults to player_projectile, its params say enemy_projectile)
## leaves one pending player_projectile behind for the rest of the run. After
## hard_max_projectiles enemy shots no projectile can be spawned: shooters aim and never
## fire (the turn log calls it no_shot), and the player cannot shoot either. Here the cap
## is lowered to 4, and a lone shooter must fire every 7 turns.
func test_a_grid_shooter_keeps_firing_past_hard_max_projectiles_shots_in_a_run() -> void:
	Tuning.hard_max_projectiles = 4
	await _start(17, Vector2i(62, 10), true)
	await _enter_b2()
	await _spawn(SHOOTER, Vector2i(62, 16))
	var fired := {&"enemy": 0, &"player": 0}
	var count := func(p: Node) -> void:
		fired[p.get(&"faction")] += 1
	EventBus.projectile_fired.connect(count)
	await _play(_waits(1 + 6 * (Tuning.grid_shooter_cooldown + 1)))
	assert_eq(fired[&"enemy"], 6, "one shot every %d turns, never more than 2 alive" % (Tuning.grid_shooter_cooldown + 1))
	await _play([_shot(Vector2.LEFT)])
	assert_eq(fired[&"player"], 1, "the player can still shoot")
	EventBus.projectile_fired.disconnect(count)
	_assert_clean()


# --- Kills and deaths at a turn ------------------------------------------------------

func test_an_adjacent_enemy_killed_by_the_players_shot_during_the_turn_does_not_attack() -> void:
	await _start(11, Vector2i(62, 10))
	await _enter_b2()
	var chaser := await _spawn(CHASER, Vector2i(63, 10), {&"hp_mult": 0.1})
	assert_true(_marked_by(_p(), chaser), "P is marked by the chaser")
	var from := RunState.run_log.size()
	await _play([_shot(Vector2.RIGHT)])
	assert_false(_alive(chaser), "the player's shot killed it during the turn")
	assert_eq(_hits(from), 0, "a killed enemy does not attack")
	var entries := _events(from, &"turn_danger")
	assert_eq(entries.size(), 1)
	if entries.size() == 1:
		assert_eq(entries[0].sources.size(), 1)
		assert_eq(str(entries[0].sources), str([{"kind": "chaser", "result": "died"}]), "logged as an exemption")
	_assert_clean()


func test_death_at_turn_end_by_a_chaser_stops_the_clock_and_opens_the_report() -> void:
	await _start(12, Vector2i(62, 10))
	await _enter_b2()
	await _spawn(CHASER, Vector2i(63, 10))
	await _die_at_turn_end(&"contact", 1)


func test_death_at_turn_end_by_a_grid_shot_stops_the_clock_and_opens_the_report() -> void:
	await _start(13, Vector2i(62, 10))
	await _enter_b2()
	await _spawn(SHOOTER, Vector2i(62, 12))
	await _die_at_turn_end(&"projectile", 2)


## A 1-HP player waits until the hit of `kind` kills them at a resolution, after
## `turns` turns. Then the clock lets go, game time runs, and the report opens.
func _die_at_turn_end(kind: StringName, turns: int) -> void:
	RunState.invincible = false
	var health := _health()
	health.hp_ratio = 1.0 / health.max_hp()
	var from := RunState.run_log.size()
	await _play(_waits(turns))
	assert_true(health.dead, "killed at the end of turn %d" % turns)
	# The lethal turn ends with the clock stopped, so the input never reaches its
	# between-turns check: run it here, against the map seen when the last wait was chosen.
	_between()
	var lethal := _events(input.log_seen, &"turn_danger")
	assert_eq(lethal.size(), 1, "the lethal resolution is logged")
	if lethal.size() == 1:
		assert_true(lethal[0].marked, "the lethal tile was marked before the player acted")
		assert_eq(str(lethal[0].sources.map(func(s: Dictionary) -> String: return s.result)), str(["hit"]),
				"by the source that killed")
	var hits := _events(from, &"player_hit")
	assert_eq(hits.size(), 1)
	if hits.size() == 1:
		assert_eq(hits[0].kind, kind)
	var entries := _events(from, &"turn_danger")
	assert_true(not entries.is_empty() and entries[-1].hits == 1, "the hit came at the resolution")
	assert_true(game.run_loop.is_over())
	assert_false(clock.active, "the clock stopped")
	assert_false(RunState.is_paused_for(&"turn"), "the turn pause is off")
	var t0 := RunState.game_time
	await wait_physics_frames(10)
	assert_gt(RunState.game_time, t0, "game time advances after a death at a turn end")
	for i in 150:
		if game.report.is_open():
			break
		await wait_physics_frames(1)
	assert_true(game.report.is_open(), "the report opens")
	_assert_clean()


# --- Long runs -----------------------------------------------------------------------

func test_the_grid_holds_at_every_turn_end_with_a_mixed_wave_at_full_turn_length() -> void:
	await _start(14)
	_spawn_mix()
	game.spawn_wave(6)
	await wait_physics_frames(1)
	await _enter_b2()
	rng.seed = 14
	await _run_policy(80)
	assert_gte(stats.turns, 80)
	_assert_clean()


## 3b.8 Danger is exact: a seeded random policy, invincible, horde and splits, with
## shooters, on several seeds. Short i-frames so both landed and blocked hits occur.
func test_the_danger_map_is_exact_over_random_turns() -> void:
	Tuning.spawn_interval_start = 0.3
	Tuning.spawn_interval_end = 0.3
	Tuning.spawn_tank_delay = 0.0
	for run_seed: int in [101, 202, 303, 404]:
		await _start(run_seed, NO_TILE, true)
		rng.seed = run_seed
		game.spawner.enabled = true
		assert_true(RunState.apply(MutationDB.get_mutation(&"horde_mode")))
		assert_true(RunState.apply(MutationDB.get_mutation(&"enemies_split")))
		_spawn_mix()
		await wait_physics_frames(1)
		await _enter_b2()
		_health().invuln_time = 1.5 * FAST_TURN
		await _run_policy(510)
		await _drop_game()
	gut.p("danger run: %s" % [stats])
	assert_gte(stats.turns, 2000, "turns played")
	assert_gte(stats.marked, 200, "turns ended on a marked tile")
	assert_gt(stats.hits, 0)
	assert_gt(int(stats.results.get("iframes", 0)), 0, "some sources were blocked by i-frames")
	_assert_clean()


## Same seed, same run for the world: the seeded random policy plays, twice in this
## process, 300 turns each, the same line per turn. The bot's own replay is the next test.
func test_same_seed_same_run() -> void:
	var runs: Array[Array] = []
	for run in 2:
		await _start(4242, NO_TILE, true)
		rng.seed = 77
		game.spawner.enabled = true
		RunState.apply(MutationDB.get_mutation(&"horde_mode"))
		RunState.apply(MutationDB.get_mutation(&"enemies_split"))
		_spawn_mix()
		game.spawn_wave(6)
		await wait_physics_frames(1)
		await _enter_b2()
		trace.clear()
		recording = true
		await _run_policy(300)
		recording = false
		runs.append(trace.duplicate())
		await _drop_game()
	assert_gte(runs[0].size(), 300)
	assert_gte(runs[1].size(), 300)
	for i in mini(300, mini(runs[0].size(), runs[1].size())):
		if runs[0][i] != runs[1][i]:
			fail_test("turn %d differs:\n%s\n%s" % [i + 1, runs[0][i], runs[1][i]])
			break
	assert_eq(hash(runs[0].slice(0, 300)), hash(runs[1].slice(0, 300)), "the per-turn hash matches")
	_assert_clean()


## 3b.8 Same seed, same run, with the invincible bot (the sweeps compare configs seed by
## seed through it): its choices must replay too, not only the world's.
func test_same_seed_same_run_with_the_bot() -> void:
	var runs: Array[Array] = []
	for run in 2:
		await _start(4243, NO_TILE, true)
		game.spawner.enabled = true
		RunState.apply(MutationDB.get_mutation(&"horde_mode"))
		RunState.apply(MutationDB.get_mutation(&"enemies_split"))
		_spawn_mix()
		game.spawn_wave(6)
		await wait_physics_frames(1)
		await _enter_b2()
		game.player.set_bot(true)
		RunState.invincible = true
		var lines: Array[String] = []
		# The bot's turns never pass through _between, so the run log's length stands in
		# for the hits (every hit, blocked or not, adds entries).
		var record := func(_n: int) -> void: lines.append("%s L%d" % [_turn_state(), RunState.run_log.size()])
		EventBus.turn_ended.connect(record)
		var goal := clock.turns + 300
		for i in 300 * 40:
			if clock.turns >= goal or not clock.active:
				break
			await wait_physics_frames(5)
		EventBus.turn_ended.disconnect(record)
		runs.append(lines)
		await _drop_game()
	assert_gte(runs[0].size(), 300, "the bot played 300 turns")
	assert_gte(runs[1].size(), 300)
	for i in mini(300, mini(runs[0].size(), runs[1].size())):
		if runs[0][i] != runs[1][i]:
			fail_test("turn %d differs:\n%s\n%s" % [i + 1, runs[0][i], runs[1][i]])
			break
	assert_eq(hash(runs[0].slice(0, 300)), hash(runs[1].slice(0, 300)), "the per-turn hash matches")


# --- Swaps in the middle of a wave ----------------------------------------------------

func test_none_to_b2_and_back_mid_wave() -> void:
	await _start(15)
	game.spawn_wave(6)
	_spawn_mix()
	await wait_physics_frames(40)
	await _shot_into_flight()
	RunState.spawn(CHASER, game.player.global_position)   # crowds the player's own tile
	await wait_physics_frames(1)
	await _assert_entry()
	await _run_policy(15)
	# Reset is the only way back to no big patch (PLAN v3 1.2).
	RunState.reset(15)
	RunState.invincible = true
	var before := {}
	for e in _live(&"enemy"):
		before[e] = e.global_position
	await wait_physics_frames(20)
	_assert_left_the_grid()
	_assert_enemies_steer()
	var moved := 0
	for e in before:
		if is_instance_valid(e) and (e as Node2D).global_position.distance_to(before[e]) > 4.0:
			moved += 1
	assert_gt(moved, 0, "enemies move off their tiles in real time")
	_assert_clean()


func test_b1_and_b2_swap_both_ways_mid_wave() -> void:
	await _start(16)
	game.spawn_wave(6)
	_spawn_mix()
	RunState.swap_big(b1)
	await wait_physics_frames(30)
	for i in 2:
		await _shot_into_flight()
		await _assert_entry()
		await _run_policy(12)
		RunState.swap_big(b1)
		await wait_physics_frames(3)
		assert_eq(RunState.big, b1)
		_assert_left_the_grid()
		_assert_enemies_steer()
	_assert_clean()


## Swaps B2 in with enemies and an enemy shot in flight: the player snaps first, to the
## free tile nearest to where it stood, then every enemy takes its own tile, and the
## shots in flight are removed.
func _assert_entry() -> void:
	assert_gt(RunState.count(&"enemy_projectile"), 0, "a shot is in flight")
	assert_gt(RunState.count(&"enemy"), 5, "mid-wave")
	var expected := clock.nearest_free_tile(game.player.global_position)
	var from := RunState.run_log.size()
	RunState.swap_big(b2)
	_track()
	assert_true(clock.active)
	assert_eq(game.player.global_position, expected, "the player snapped first, to its nearest free tile")
	_check_grid()
	assert_eq(problems, [] as Array[String], "every enemy on its own tile at once")
	assert_eq(RunState.count(&"enemy_projectile"), 0, "shots in flight are removed")
	assert_gt(_events(from, &"enemy_shot_removed").size(), 0, "and logged")
	await wait_physics_frames(1)
