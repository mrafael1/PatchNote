class_name TurnOverlay
extends Node2D
## B2 readability (PLAN v3 sections 3 and 3b.7), drawn in the world while turn-based is
## on: the danger tiles (dimmed in grace), each shooter's locked line, the tiles each
## enemy shot enters next turn, a mark on a resting tank, the player's tile and the aim
## line. Reads only TurnClock (danger, intents). Presentation only.

const COLOR := Color(1.0, 0.8, 0.45, 0.8)
const COLOR_DANGER := Color(1.0, 0.2, 0.2, 0.3)
const COLOR_AIM := Color(1.0, 0.35, 0.3, 0.9)
const COLOR_SHOT := Color(1.0, 0.6, 0.25, 0.95)
const COLOR_REST := Color(0.65, 0.8, 1.0, 0.9)
const GRACE_DIM := 0.35        ## danger alpha multiplier while grace is on
const AIM_TILES := 5

var player: Node2D


func _ready() -> void:
	z_index = 5
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	visible = RunState.rules.turn_based and is_instance_valid(player) and player.visible
	if visible:
		queue_redraw()
		# The player is paused between turns, so its own aim visual would freeze;
		# keep the gun pointing where the next shot will go.
		var input := player.get(&"input") as PlayerInput
		var aim := player.get_node_or_null(^"Aim") as Node2D
		if input and aim:
			aim.rotation = input.aim_dir.angle()


func _draw() -> void:
	var clock := TurnClock.current()
	if clock != null:
		_draw_danger(clock)
		_draw_intents(clock)
	var t := Tuning.TILE
	var center := TurnClock.tile_center(player.global_position)
	draw_rect(Rect2(center - Vector2(t, t) * 0.5, Vector2(t, t)), COLOR, false, 2.0)
	var input := player.get(&"input") as PlayerInput
	if input == null:
		return
	var from := player.global_position
	var dir := input.aim_dir.normalized()
	for i in range(1, AIM_TILES * 2):
		if i % 2 == 1:
			draw_line(from + dir * (i * t * 0.5), from + dir * ((i + 0.6) * t * 0.5), COLOR, 2.0)


## Every tile the next turn can hit the player on, slightly inset so the grid shows.
func _draw_danger(clock: TurnClock) -> void:
	var color := COLOR_DANGER
	if RunState.in_grace():
		color.a *= GRACE_DIM
	var size := Vector2(Tuning.TILE, Tuning.TILE) - Vector2(4, 4)
	for c: Vector2 in clock.danger:
		draw_rect(Rect2(c - size * 0.5, size), color)


func _draw_intents(clock: TurnClock) -> void:
	for intent in clock.intents:
		match intent.kind:
			&"aim":
				_draw_aim(intent)
			&"shot":
				_draw_shot(intent)
			&"rest":
				_draw_rest(intent.tile)


## A shooter's locked line: dashed from the shooter to the wall or the shot's reach.
func _draw_aim(intent: Dictionary) -> void:
	var tiles: Array = intent.tiles
	if tiles.is_empty():
		return
	var end: Vector2 = tiles[-1]
	var from := end - (intent.dir as Vector2) * Tuning.TILE * tiles.size()
	draw_dashed_line(from, end, COLOR_AIM, 2.0, 8.0)
	draw_arc(end, 5.0, 0.0, TAU, 12, COLOR_AIM, 2.0)


## A shot's next move: a line from the shot to the last tile it enters, a dot on each.
func _draw_shot(intent: Dictionary) -> void:
	var tiles: Array = intent.tiles
	if tiles.is_empty():
		return
	var from := (tiles[0] as Vector2) - (intent.dir as Vector2) * Tuning.TILE
	draw_line(from, tiles[-1], COLOR_SHOT, 3.0)
	for c: Vector2 in tiles:
		draw_circle(c, 4.0, COLOR_SHOT)


## A tank that does not act next turn: a small "z" above it.
func _draw_rest(tile: Vector2) -> void:
	var o := tile + Vector2(10, -26)
	draw_polyline(PackedVector2Array([o, o + Vector2(8, 0), o + Vector2(0, 8), o + Vector2(8, 8)]),
			COLOR_REST, 2.0)
