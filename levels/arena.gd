class_name Arena
extends Node2D
## The one arena (PLAN 3). Geometry is data: axis-aligned rectangles in tile units,
## turned into a single StaticBody2D. Keeping it as data lets other views (and tests)
## read the same layout.
##
## Layout rule: ledges are one tile thick and sit on a 3-tile lattice (tops at rows
## 18, 15, 12, 9, 6, 3), which makes the level the same staircase measured from the
## floor or from the ceiling.

const COLS := 66
const ROWS := 22

## [row, first column, length]
const LEDGES := [
	[18, 6, 6], [18, 24, 7], [18, 40, 6], [18, 54, 6],
	[15, 14, 6], [15, 32, 5], [15, 47, 6],
	[12, 5, 6], [12, 22, 6], [12, 38, 7], [12, 55, 6],
	[9, 13, 6], [9, 30, 6], [9, 46, 6],
	[6, 6, 5], [6, 22, 6], [6, 39, 6], [6, 54, 6],
	[3, 14, 5], [3, 31, 5], [3, 47, 5],
]
## [column, row, width, height] — chunky blocks standing on the floor or ceiling
const CHUNKS := [[20, 19, 2, 2], [44, 19, 2, 2], [28, 1, 2, 2], [52, 1, 2, 2]]

const SPAWN_TILES := [
	Vector2(3, 5), Vector2(3, 11), Vector2(3, 17),
	Vector2(62.5, 5), Vector2(62.5, 11), Vector2(62.5, 17),
	Vector2(20, 14), Vector2(45, 14), Vector2(33, 8), Vector2(50, 11),
	Vector2(12, 20), Vector2(58, 20), Vector2(28, 5), Vector2(33, 20),
]
const PLAYER_START_TILE := Vector2(33, 14)

const COLOR_BACKGROUND := Color(0.09, 0.1, 0.13)
const COLOR_GRID := Color(1, 1, 1, 0.035)
const COLOR_BLOCK := Color(0.42, 0.45, 0.52)

var blocks: Array[Rect2] = []          ## pixels
var bounds: Rect2                      ## whole arena including the border, pixels
var spawn_points: Array[Vector2] = []  ## pixels
var player_start: Vector2


func _init() -> void:
	var t := Tuning.TILE
	bounds = Rect2(0, 0, COLS * t, ROWS * t)
	# Border, one tile thick on all four sides.
	_add_block(0, 0, COLS, 1, t)
	_add_block(0, ROWS - 1, COLS, 1, t)
	_add_block(0, 1, 1, ROWS - 2, t)
	_add_block(COLS - 1, 1, 1, ROWS - 2, t)
	for l: Array in LEDGES:
		_add_block(l[1], l[0], l[2], 1, t)
	for c: Array in CHUNKS:
		_add_block(c[0], c[1], c[2], c[3], t)
	for s: Vector2 in SPAWN_TILES:
		spawn_points.append(s * t)
	player_start = PLAYER_START_TILE * t


func _add_block(col: float, row: float, w: float, h: float, t: float) -> void:
	blocks.append(Rect2(col * t, row * t, w * t, h * t))


func _ready() -> void:
	z_index = -10
	var body := StaticBody2D.new()
	body.name = "Blocks"
	body.collision_layer = Tuning.LAYER_WORLD
	body.collision_mask = 0
	for rect in blocks:
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = rect.get_center()
		body.add_child(cs)
	add_child(body)


## Shortest distance from a point to any block (0 if inside one).
func distance_to_blocks(p: Vector2) -> float:
	var best := INF
	for rect in blocks:
		var dx := maxf(maxf(rect.position.x - p.x, 0.0), p.x - rect.end.x)
		var dy := maxf(maxf(rect.position.y - p.y, 0.0), p.y - rect.end.y)
		best = minf(best, Vector2(dx, dy).length())
	return best


func _draw() -> void:
	draw_rect(bounds, COLOR_BACKGROUND)
	var t := Tuning.TILE
	for c in range(1, COLS):
		draw_line(Vector2(c * t, 0), Vector2(c * t, bounds.size.y), COLOR_GRID)
	for r in range(1, ROWS):
		draw_line(Vector2(0, r * t), Vector2(bounds.size.x, r * t), COLOR_GRID)
	for rect in blocks:
		draw_rect(rect, COLOR_BLOCK)
