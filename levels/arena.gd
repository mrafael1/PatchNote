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

const COLOR_BACKGROUND := Palette.BG
const COLOR_GRID := Palette.GRID
const COLOR_BLOCK := Palette.WALL
const COLOR_STANDABLE := Palette.STANDABLE
const COLOR_DEPTH := Palette.DEPTH
const STRIP := 5.0

var def: ArenaDef                      ## the layout this arena was built from
var blocks: Array[Rect2] = []          ## pixels
var bounds: Rect2                      ## whole arena including the border, pixels
var spawn_points: Array[Vector2] = []  ## pixels
var player_start: Vector2

var _reach := PackedByteArray()        ## is_reachable's flood fill, built on first use
var _was_busy := false                 ## M48b: redrawn once more after a morph or a bug ends

## M47.6c1 (design 3, S4): the walls grow in. strip_layout keeps the blocks it removed;
## grow_layout adds them back one by one over GROW_SECONDS of game time, from the middle out
## (distance of each block's centre from the arena's centre, then x, then y). Each block's
## collision lands on the physics tick it appears (sim); its look scales in over GROW_LOOK
## (presentation; reduce flashing: a fade). A body under a new block is pushed to the nearest
## free tile centre (rings, row-major); the reach map is rebuilt after every block.
const GROW_SECONDS := 2.5
const GROW_LOOK := 0.2
var _stripped: Array[Rect2] = []
var _grow: Array[Rect2] = []
var _grown := 0
var _grow_from := 0.0
var _grow_seconds := GROW_SECONDS
var _appear := {}                      ## index in blocks -> game time it appeared
var _body: StaticBody2D


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
	_stripped = blocks.slice(4)
	blocks.resize(4)   # the border is the first four blocks


## M47.6c1: the layout was stripped and has not grown back yet.
func stripped() -> bool:
	return not _stripped.is_empty()


## M47.6c1: the stripped blocks grow back over `seconds` of game time (S4's `add level`).
func grow_layout(seconds := GROW_SECONDS) -> void:
	if _stripped.is_empty():
		return
	var centre := bounds.get_center()
	_grow = _stripped.duplicate()
	_grow.sort_custom(func(a: Rect2, b: Rect2) -> bool:
		var da := snappedf(a.get_center().distance_squared_to(centre), 0.01)
		var db := snappedf(b.get_center().distance_squared_to(centre), 0.01)
		if da != db:
			return da < db
		if a.position.x != b.position.x:
			return a.position.x < b.position.x
		return a.position.y < b.position.y)
	_stripped.clear()
	_grown = 0
	_grow_from = RunState.game_time
	_grow_seconds = maxf(seconds, 0.0)
	_grow_step()


## M47.6c1: blocks still to grow (tests).
func growing() -> bool:
	return _grown < _grow.size()


func _physics_process(_delta: float) -> void:
	if _grown < _grow.size():
		_grow_step()


func _grow_step() -> void:
	var n := _grow.size()
	while _grown < n and RunState.game_time >= _grow_from + _grow_seconds * float(_grown + 1) / n - 0.0001:
		_add_grown(_grow[_grown])
		_grown += 1


func _add_grown(rect: Rect2) -> void:
	blocks.append(rect)
	_appear[blocks.size() - 1] = RunState.game_time
	_reach = PackedByteArray()   # cached on first use: never trust a tile the growth made solid
	if _body != null:
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = rect.get_center()
		_body.add_child(cs)
	var reach := Tuning.TILE * 0.45
	for group: StringName in [&"player", &"enemy"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node2D
			if body == null or body.is_queued_for_deletion() or not rect.grow(reach).has_point(body.global_position):
				continue
			body.global_position = free_tile_near(body.global_position)
	queue_redraw()


## M47.6c1: the centre of the free tile nearest `p` (no block on it or within half a tile of
## its centre), in rings of growing radius, row-major; `p` when none is within 8 tiles.
func free_tile_near(p: Vector2) -> Vector2:
	var t := Tuning.TILE
	var c := Vector2i(int(floorf(p.x / t)), int(floorf(p.y / t)))
	for radius in 9:
		var best := Vector2.INF
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile := c + Vector2i(dx, dy)
				if tile.x < 1 or tile.y < 1 or tile.x >= COLS - 1 or tile.y >= ROWS - 1:
					continue
				var centre := (Vector2(tile) + Vector2(0.5, 0.5)) * t
				if distance_to_blocks(centre) < t * 0.5 - 0.01:
					continue
				if best == Vector2.INF or centre.distance_squared_to(p) < best.distance_squared_to(p):
					best = centre
		if best != Vector2.INF:
			return best
	return p


## M47.6c1 (presentation): block i as drawn now: a fresh grown block scales in from 0.6 over
## GROW_LOOK (reduce flashing: full size, faded in by the caller's alpha).
func _shown(i: int) -> Rect2:
	var rect := blocks[i]
	var u := _grow_u(i)
	if u >= 1.0 or SaveGame.reduce_flashing():
		return rect
	var k := lerpf(0.6, 1.0, u)
	return Rect2(rect.get_center() - rect.size * k / 2.0, rect.size * k)


func _grow_u(i: int) -> float:
	if not _appear.has(i):
		return 1.0
	return clampf((RunState.game_time - float(_appear[i])) / GROW_LOOK, 0.0, 1.0)


func _add_block(col: float, row: float, w: float, h: float, t: float) -> void:
	blocks.append(Rect2(col * t, row * t, w * t, h * t))


func _ready() -> void:
	z_index = -10
	EventBus.rules_changed.connect(func(_r: Resource) -> void: queue_redraw())
	add_to_group(Skins.SKINNED)   # M48a: redrawn on rules_changed and on a look swap only
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
	_body = body


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
	var painted := ROWS
	if Skins.is_on(&"floor_a"):
		painted = painted_rows()
		if painted >= ROWS and _draw_skin(ROWS):
			return
	_draw_tier_0()
	if painted < ROWS and painted > 0 and Skins.current != null:
		_draw_skin(painted)   # M48b: the arena paints in row by row over today's


## M48b: how many rows (from the top) the skin paints: all once revealed, fewer mid-morph.
func painted_rows() -> int:
	var u := Skins.morph_of(&"floor_a")
	return ROWS if u < 0.0 else clampi(int(floor(u * ROWS)), 0, ROWS)


## M48b: keeps redrawing while the arena morphs or the tiles bug is live (and once after).
func _process(_delta: float) -> void:
	if not _appear.is_empty():   # M47.6c1: a grown block is still scaling in
		var fresh := false
		for i: int in _appear:
			fresh = fresh or _grow_u(i) < 1.0
		if fresh or growing():
			queue_redraw()
		elif not growing():
			_appear.clear()
			queue_redraw()
	if Skins.current == null:
		return
	var busy := Skins.morphing(&"floor_a") or Skins.glitch_kind() == &"tiles"
	if busy or _was_busy:
		queue_redraw()
	_was_busy = busy


## M48b (tests): what cell (c, r) shows now: &"tier0" (today's flat tiles) or the tile id
## the skin draws there (the tiles bug swaps floor and wall).
func tile_key(c: int, r: int) -> StringName:
	if not Skins.is_on(&"floor_a") or r >= painted_rows():
		return &"tier0"
	var centre := (Vector2(c, r) + Vector2(0.5, 0.5)) * Tuning.TILE
	var block := false
	for rect in blocks:
		if rect.has_point(centre):
			block = true
			break
	var tiles := Skins.glitch_kind() == &"tiles"
	if block:
		return &"floor_a" if tiles else &"wall"
	if tiles:
		return &"wall"
	return &"floor_b" if Skins.cell_hash(c, r) == 0 and Skins.current.has(&"floor_b") else &"floor_a"


func _draw_tier_0() -> void:
	draw_rect(bounds, COLOR_BACKGROUND)
	var t := Tuning.TILE
	var rules := RunState.rules
	if not rules.gravity_enabled:
		for c in range(1, COLS):
			draw_line(Vector2(c * t, 0), Vector2(c * t, bounds.size.y), COLOR_GRID)
		for r in range(1, ROWS):
			draw_line(Vector2(0, r * t), Vector2(bounds.size.x, r * t), COLOR_GRID)
		for i in blocks.size():
			var a := _grow_u(i) if SaveGame.reduce_flashing() else 1.0
			draw_rect(_shown(i), Color(COLOR_BLOCK, COLOR_BLOCK.a * a))
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
## M48b: `rows` < ROWS paints only the top rows (the arena's morph); the tiles bug draws
## the floor as wall and the blocks as floor, and the real blocks keep their rim.
func _draw_skin(rows := ROWS) -> bool:
	var skin := Skins.current
	if not (skin.has(&"floor_a") and skin.has(&"wall")):
		return false
	var t := Tuning.TILE
	var tiles := Skins.glitch_kind() == &"tiles"
	var floor_id := &"wall" if tiles else &"floor_a"
	var wall_id := &"floor_a" if tiles else &"wall"
	var top := Rect2(bounds.position, Vector2(bounds.size.x, minf(bounds.size.y, rows * t)))
	skin.draw_tile(self, floor_id, top)
	if skin.has(&"floor_b") and not tiles:
		for r in rows:
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
				draw_rect(Rect2(c * t, 0, t, top.size.y), Color(COLOR_DEPTH, COLOR_DEPTH.a * depth))
		else:
			for r in rows:
				var depth := float(r) / (ROWS - 1)
				if g.y < 0.0:
					depth = 1.0 - depth
				draw_rect(Rect2(0, r * t, bounds.size.x, t), Color(COLOR_DEPTH, COLOR_DEPTH.a * depth))
	for i in blocks.size():
		var rect := _shown(i)   # M47.6c1: a grown block scales in
		var clipped := rect.intersection(top) if rows < ROWS else rect
		if clipped.has_area():
			skin.draw_tile(self, wall_id, clipped)
	_draw_wall_rim(skin.wall_rim(), rows)
	if rules.gravity_enabled and skin.has(&"standable") and rows >= ROWS:
		for rect in blocks:
			_draw_standable(skin, rect, g)
	return true


## The Pixel walls' rim: a 2 px outline on every block cell edge that faces an open cell
## (plus a lit line under an open top), so blocks read as one shape and the arena's outer
## edge gets none. Cells only, so touching blocks never show a seam. {} rim: nothing.
func _draw_wall_rim(rim: Dictionary, rows := ROWS) -> void:
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
		if c.y >= rows:
			continue
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
