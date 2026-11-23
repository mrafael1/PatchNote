class_name Arena
extends Node2D
## An arena on screen (PLAN v6 4). Its layout is data, an ArenaDef in levels/arenas/
## (rectangles in tile units, markers, the start), turned here into a single
## StaticBody2D. Every arena is COLS x ROWS tiles inside a one-tile border.
##
## arena_0 is the M14 arena. Its ledges are one tile thick and sit on a 3-tile lattice
## (tops at rows 18, 15, 12, 9, 6, 3), the same staircase seen from the floor or the
## ceiling; tests/gut/test_gravity.gd checks every ledge is reachable both ways.

const COLS := 66
const ROWS := 22
const DEFAULT := "res://levels/arenas/arena_0.tres"

const COLOR_BACKGROUND := Color(0.09, 0.1, 0.13)
const COLOR_GRID := Color(1, 1, 1, 0.035)
const COLOR_BLOCK := Color(0.42, 0.45, 0.52)
const COLOR_STANDABLE := Color(0.95, 0.97, 1.0)
const COLOR_DEPTH := Color(0.0, 0.0, 0.0, 0.5)
const STRIP := 5.0

var def: ArenaDef                      ## the layout this arena was built from
var blocks: Array[Rect2] = []          ## pixels
var bounds: Rect2                      ## whole arena including the border, pixels
var spawn_points: Array[Vector2] = []  ## pixels
var player_start: Vector2


func _init(p_def: ArenaDef = null) -> void:
	def = p_def if p_def != null else load(DEFAULT) as ArenaDef
	var t := Tuning.TILE
	bounds = Rect2(0, 0, COLS * t, ROWS * t)
	# Border, one tile thick on all four sides.
	_add_block(0, 0, COLS, 1, t)
	_add_block(0, ROWS - 1, COLS, 1, t)
	_add_block(0, 1, 1, ROWS - 2, t)
	_add_block(COLS - 1, 1, 1, ROWS - 2, t)
	for r in def.blocks:
		_add_block(r.position.x, r.position.y, r.size.x, r.size.y, t)
	for tile in def.spawn_tiles:
		spawn_points.append(tile * t)
	player_start = def.player_start * t


## The first builds have no level yet (PLAN v5 4.8): only the border stays. Call it
## before the arena enters the tree (its collision is built in _ready).
func strip_layout() -> void:
	blocks.resize(4)   # the border is the first four blocks


func _add_block(col: float, row: float, w: float, h: float, t: float) -> void:
	blocks.append(Rect2(col * t, row * t, w * t, h * t))


func _ready() -> void:
	z_index = -10
	EventBus.rules_changed.connect(func(_r: Resource) -> void: queue_redraw())
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


## Readability cues, driven by the rules: without gravity the floor is a flat grid
## seen from above; with gravity the background darkens toward "down" (or the side
## gravity pulls to) and every block shows a bright strip on the face you can stand on.
func _draw() -> void:
	draw_rect(bounds, COLOR_BACKGROUND)
	var t := Tuning.TILE
	var rules := RunState.rules
	if not rules.gravity_enabled:
		for c in range(1, COLS):
			draw_line(Vector2(c * t, 0), Vector2(c * t, bounds.size.y), COLOR_GRID)
		for r in range(1, ROWS):
			draw_line(Vector2(0, r * t), Vector2(bounds.size.x, r * t), COLOR_GRID)
		for rect in blocks:
			draw_rect(rect, COLOR_BLOCK)
		return
	var g := rules.gravity_dir
	if absf(g.x) > absf(g.y):   # sideways (M41's wrong_variable): darkens toward the side gravity pulls to
		for c in COLS:
			var depth := float(c) / (COLS - 1)
			if g.x < 0.0:
				depth = 1.0 - depth
			draw_rect(Rect2(c * t, 0, t, bounds.size.y), Color(COLOR_DEPTH, COLOR_DEPTH.a * depth))
		for rect in blocks:
			draw_rect(rect, COLOR_BLOCK)
			draw_rect(standable_strip(rect, g), COLOR_STANDABLE)
		return
	var down := rules.gravity_dir.y >= 0.0
	for r in ROWS:
		var depth := float(r) / (ROWS - 1)
		if not down:
			depth = 1.0 - depth
		draw_rect(Rect2(0, r * t, bounds.size.x, t), Color(COLOR_DEPTH, COLOR_DEPTH.a * depth))
	for rect in blocks:
		draw_rect(rect, COLOR_BLOCK)
		var y := rect.position.y if down else rect.end.y - STRIP
		draw_rect(Rect2(rect.position.x, y, rect.size.x, STRIP), COLOR_STANDABLE)


## The bright strip on the face a body rests on under gravity g (the face whose normal
## is -g): the top under DOWN, the right face under LEFT.
static func standable_strip(rect: Rect2, g: Vector2) -> Rect2:
	if absf(g.x) > absf(g.y):
		var x := rect.end.x - STRIP if g.x < 0.0 else rect.position.x
		return Rect2(x, rect.position.y, STRIP, rect.size.y)
	var y := rect.position.y if g.y >= 0.0 else rect.end.y - STRIP
	return Rect2(rect.position.x, y, rect.size.x, STRIP)
