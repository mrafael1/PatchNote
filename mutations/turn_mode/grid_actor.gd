extends Component
## Puts its host on B2's grid (PLAN v3 3b.5): an enemy or an enemy shot that moves
## only on tiles, as the turn logic plans it. It holds what lasts between turns (tile,
## role, rest counter, cooldown, locked aim, attach order) and what the logic decided
## for the turn under way. While it is attached the host is in TurnClock.GRID_GROUP, so
## the host's own script skips its steering, contact damage, firing and motion.

const CHASER := &"chaser"
const TANK := &"tank"
const SHOOTER := &"shooter"
const SHOT := &"shot"

var role: StringName = CHASER
var order := 0                  ## attach order: actors plan in this order (from a counter)
var tile := Vector2i.ZERO       ## the tile it holds; during a turn, the one it ends on
var turns_seen := 0             ## turns planned since it joined (a tank acts on even ones)
var cooldown := 0               ## shooter: turns before it may aim again
var aim := Vector2i.ZERO        ## shooter: locked line, zero when not aiming
var attacks := false            ## melee: attacks P at this turn's end

# Shots only.
var dir := Vector2i.ZERO        ## one of the 8 directions
var turns_left := 0             ## turns of motion left, the one under way included
var start := Vector2i.ZERO      ## tile at the start of this turn
var path: Array[Vector2i] = []  ## tiles entered this turn, in order
var spent := false              ## stopped at a wall: removed at this turn's end

var _elapsed := 0.0             ## game seconds into this turn's shot motion


func _enter_tree() -> void:
	get_parent().add_to_group(TurnClock.GRID_GROUP)


func _exit_tree() -> void:
	get_parent().remove_from_group(TurnClock.GRID_GROUP)


func _ready() -> void:
	stop_host()


## Clears the host's speed so all motion comes from the turn.
func stop_host() -> void:
	var mover := Component.find(get_parent(), Mover) as Mover
	if mover:
		mover.stop()
	var body := get_parent() as CharacterBody2D
	if body:
		body.velocity = Vector2.ZERO


## Called once at the start of every turn, before this actor plans.
func begin_turn() -> void:
	turns_seen += 1
	cooldown = maxi(0, cooldown - 1)
	attacks = false


## An enemy moves to `to` over the turn, by its Mover, like the player's step.
func move_to(to: Vector2i) -> void:
	tile = to
	var mover := Component.find(get_parent(), Mover) as Mover
	var host := get_parent() as Node2D
	var duration := RunState.rules.turn_duration
	if mover:
		mover.dash((TurnClock.centre_of(to) - host.global_position) / duration, duration)


## Turn end: stop and stand exactly on the tile.
func settle() -> void:
	stop_host()
	(get_parent() as Node2D).global_position = TurnClock.centre_of(tile)


## Shots: play this turn's path as a straight slide from start to the last tile.
## Visual only; the turn end sets the exact tile.
func _physics_process(delta: float) -> void:
	if role != SHOT or path.is_empty():
		return
	_elapsed += delta
	var u := clampf(_elapsed / RunState.rules.turn_duration, 0.0, 1.0)
	(get_parent() as Node2D).global_position = TurnClock.centre_of(start).lerp(TurnClock.centre_of(path[-1]), u)


func begin_motion() -> void:
	_elapsed = 0.0
