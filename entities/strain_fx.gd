class_name StrainFX
extends Node
## M47.6a (PLAN v9.4 2.2): the square "tries to move". While the player's movement is locked
## (S0: the build has no `movement` yet) and a direction is held, its Visual (never the body)
## leans up to LEAN px toward it, stretched along it (1.12 x 0.88), with a 1 px shake at 12 Hz
## (none under reduce flashing), and springs back on release.
##
## Presentation only: it writes Visual.position / Visual.scale, never the body, collisions or
## the sim, and reads no RNG. It runs ALWAYS: while the tree is paused (the play gate) it reads
## the Input singleton directly; while the sim runs it reads the player's input (bots too).
## M47.7b (PLAN 0.9.1): while the handover slide is pending (the hold before it) or running,
## the lean is the slide's direction: the square still pulls the way it tried, then shoots off.
## A child of the player, so it runs after the body set the Visual for this frame.

const LEAN := 3.0
const STRETCH := 0.12
const SHAKE_PX := 1.0
const SHAKE_HZ := 12.0
const SPRING := 18.0           ## 1/s: how fast the lean follows the held direction

var player: Node
var visual: Node2D
var gentle := false            ## reduce flashing whatever the setting (tests)
var dir := Vector2.ZERO        ## the current (smoothed) lean direction
var _written_pos := Vector2.INF
var _written_scale := Vector2.INF
var _base_pos := Vector2.ZERO
var _base_scale := Vector2.ONE
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## The direction the player is pushing: the keys while paused, the player's input while the
## sim runs.
func wanted() -> Vector2:
	if player == null or not is_instance_valid(player):
		return Vector2.ZERO
	if player.has_method(&"slide_dir") and player.call(&"slide_dir") != Vector2.ZERO:
		return player.call(&"slide_dir")   # M47.7b: read only, never written
	if not bool(player.get(&"movement_locked")):
		return Vector2.ZERO
	var v := Vector2.ZERO
	if get_tree().paused:
		v = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	else:
		var input: Variant = player.get(&"input")
		if input is Object and input != null:
			v = input.get(&"move")
	return v.limit_length(1.0)


func _process(delta: float) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	# The body rewrites the Visual each frame it runs; paused, it keeps our last write.
	if visual.position != _written_pos or visual.scale != _written_scale:
		_base_pos = visual.position
		_base_scale = visual.scale
	var want := wanted()
	dir = dir.lerp(want, 1.0 - exp(-SPRING * delta))
	if want == Vector2.ZERO and dir.length() < 0.01:
		dir = Vector2.ZERO
	_t += delta
	var off := dir * LEAN
	if want != Vector2.ZERO and not (gentle or SaveGame.reduce_flashing()):
		off += want.orthogonal().normalized() * SHAKE_PX * sin(_t * SHAKE_HZ * TAU)
	var ax := absf(dir.x)
	var ay := absf(dir.y)
	var sq := Vector2(1.0 + STRETCH * (ax - ay), 1.0 + STRETCH * (ay - ax))
	visual.position = _base_pos + off
	visual.scale = _base_scale * sq
	_written_pos = visual.position
	_written_scale = visual.scale


## The lean on screen now (tests): the Visual's offset from where the body put it.
func offset() -> Vector2:
	return visual.position - _base_pos if visual != null else Vector2.ZERO
