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

var _reach := PackedByteArray()        ## is_reachable's flood fill, built on first use


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


## Is p on a tile the player can walk to from player_start (4-neighbour flood fill over
## the tiles no block covers, built once)? False in a sealed pocket and outside the arena.
## The teleport (M42.1) reads it: only it could reach a pocket, and nothing could follow.
func is_reachable(p: Vector2) -> bool:
	var t := Tuning.TILE
	var c := int(floorf(p.x / t))
	var r := int(floorf(p.y / t))
	if c < 0 or r < 0 or c >= COLS or r >= ROWS:
		return false
	if _reach.is_empty():
		_build_reach()
	return _reach[r * COLS + c] == 2


## The sealed pockets: open tiles (no block) the flood fill from player_start never
## reaches, as tile coordinates (tests list them).
func sealed_tiles() -> Array[Vector2i]:
	if _reach.is_empty():
		_build_reach()
	var out: Array[Vector2i] = []
	for r in ROWS:
		for c in COLS:
			if _reach[r * COLS + c] == 1:
				out.append(Vector2i(c, r))
	return out


## 0 = a block covers the tile's centre, 1 = open, 2 = open and reachable.
func _build_reach() -> void:
	var t := Tuning.TILE
	_reach.resize(COLS * ROWS)
	for r in ROWS:
		for c in COLS:
			var centre := Vector2((c + 0.5) * t, (r + 0.5) * t)
			var open := 1
			for rect in blocks:
				if rect.has_point(centre):
					open = 0
					break
			_reach[r * COLS + c] = open
	var start := Vector2i(int(floorf(player_start.x / t)), int(floorf(player_start.y / t)))
	if start.x < 0 or start.y < 0 or start.x >= COLS or start.y >= ROWS:
		return
	var todo: Array[Vector2i] = [start]
	while not todo.is_empty():
		var tile: Vector2i = todo.pop_back()
		if tile.x < 0 or tile.y < 0 or tile.x >= COLS or tile.y >= ROWS:
			continue
		var i := tile.y * COLS + tile.x
		if _reach[i] != 1:
			continue
		_reach[i] = 2
		todo.append(tile + Vector2i.LEFT)
		todo.append(tile + Vector2i.RIGHT)
		todo.append(tile + Vector2i.UP)
		todo.append(tile + Vector2i.DOWN)


## Readability cues, driven by the rules: without gravity the floor is a flat grid
## seen from above; with gravity the background darkens toward "down" (or the side
## gravity pulls to) and every block shows a bright strip on the face you can stand on.
func _draw() -> void:
	if Skins.current != null and _draw_skin():
		return
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


## The Pixel preview (PLAN 1.7): floor tiles (a rarer variant by a pure cell hash), the
## same gravity shading as today, wall tiles over every block and, under gravity, the lit
## `standable` edge turned onto the face a body rests on. False without the tiles.
func _draw_skin() -> bool:
	var skin := Skins.current
	if not (skin.has(&"floor_a") and skin.has(&"wall")):
		return false
	var t := Tuning.TILE
	skin.draw_tile(self, &"floor_a", bounds)
	if skin.has(&"floor_b"):
		for r in ROWS:
			for c in COLS:
				if Skins.cell_hash(c, r) == 0:
					skin.draw_tile(self, &"floor_b", Rect2(c * t, r * t, t, t))
	var rules := RunState.rules
	var g := rules.gravity_dir
	if rules.gravity_enabled:
		if absf(g.x) > absf(g.y):
			for c in COLS:
				var depth := float(c) / (COLS - 1)
				if g.x < 0.0:
					depth = 1.0 - depth
				draw_rect(Rect2(c * t, 0, t, bounds.size.y), Color(COLOR_DEPTH, COLOR_DEPTH.a * depth))
		else:
			for r in ROWS:
				var depth := float(r) / (ROWS - 1)
				if g.y < 0.0:
					depth = 1.0 - depth
				draw_rect(Rect2(0, r * t, bounds.size.x, t), Color(COLOR_DEPTH, COLOR_DEPTH.a * depth))
	for rect in blocks:
		skin.draw_tile(self, &"wall", rect)
	_draw_wall_rim(skin.wall_rim())
	if rules.gravity_enabled and skin.has(&"standable"):
		for rect in blocks:
			_draw_standable(skin, rect, g)
	return true


## The Pixel walls' rim: a 2 px outline on every block cell edge that faces an open cell
## (plus a lit line under an open top), so blocks read as one shape and the arena's outer
## edge gets none. Cells only, so touching blocks never show a seam. {} rim: nothing.
func _draw_wall_rim(rim: Dictionary) -> void:
	if rim.is_empty():
		return
	var t := Tuning.TILE
	var cells := {}
	for rect in blocks:
		for cy in range(floori(rect.position.y / t), ceili(rect.end.y / t)):
			for cx in range(floori(rect.position.x / t), ceili(rect.end.x / t)):
				cells[Vector2i(cx, cy)] = true
	var outline: Color = rim["outline"]
	var lit: Color = rim["lit"]
	for c: Vector2i in cells:
		var x := c.x * t
		var y := c.y * t
		var up := c.y > 0 and not cells.has(c + Vector2i.UP)
		var dn := c.y + 1 < ROWS and not cells.has(c + Vector2i.DOWN)
		var lf := c.x > 0 and not cells.has(c + Vector2i.LEFT)
		var rt := c.x + 1 < COLS and not cells.has(c + Vector2i.RIGHT)
		if up:
			draw_rect(Rect2(x, y, t, 2), outline)
			var l := 2.0 if lf else 0.0
			draw_rect(Rect2(x + l, y + 2, t - l - (2.0 if rt else 0.0), 2), lit)
		if dn:
			draw_rect(Rect2(x, y + t - 2, t, 2), outline)
		if lf:
			draw_rect(Rect2(x, y, 2, t), outline)
		if rt:
			draw_rect(Rect2(x + t - 2, y, 2, t), outline)


## The standable tile along the face of `rect` a body rests on under gravity g (the face
## standable_strip names), its lit edge on that face.
func _draw_standable(skin: ArtSkin, rect: Rect2, g: Vector2) -> void:
	var t := Tuning.TILE
	var at: Vector2
	var angle := 0.0
	var length := rect.size.x
	if absf(g.x) > absf(g.y):
		length = rect.size.y
		if g.x < 0.0:
			at = Vector2(rect.end.x, rect.get_center().y)
			angle = PI / 2.0
		else:
			at = Vector2(rect.position.x, rect.get_center().y)
			angle = -PI / 2.0
	elif g.y >= 0.0:
		at = Vector2(rect.get_center().x, rect.position.y)
	else:
		at = Vector2(rect.get_center().x, rect.end.y)
		angle = PI
	draw_set_transform(at, angle)
	skin.draw_tile(self, &"standable", Rect2(-length / 2.0, 0.0, length, t))
	draw_set_transform(Vector2.ZERO)


## The bright strip on the face a body rests on under gravity g (the face whose normal
## is -g): the top under DOWN, the right face under LEFT.
static func standable_strip(rect: Rect2, g: Vector2) -> Rect2:
	if absf(g.x) > absf(g.y):
		var x := rect.end.x - STRIP if g.x < 0.0 else rect.position.x
		return Rect2(x, rect.position.y, STRIP, rect.size.y)
	var y := rect.position.y if g.y >= 0.0 else rect.end.y - STRIP
	return Rect2(rect.position.x, y, rect.size.x, STRIP)
