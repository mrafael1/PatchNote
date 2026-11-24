class_name SeparationGrid
extends RefCounted
## Enemy separation through a spatial hash (PLAN v9 1.9 "Separation", 5 "Enemies", M45b):
## path sessions only (RunState.path_live()). Stage 1 and the legacy loop keep the O(n^2)
## loop (EnemyCommon.separation_all) byte for byte, so their hashes hold.
##
## Cells are Tuning.enemy_separation_radius wide, keyed by floor(pos / cell), filled in
## group order from the `enemy` group once per (physics frame, world). push() reads the 3x3
## cells around an enemy with the legacy loop's math on each neighbour's live position.
## Deterministic: no random stream, no instance ids, insertion order.

static var builds := 0          ## tests: grids built
static var _cells := {}         ## Vector2i -> Array of enemies
static var _cell := 36.0
static var _frame := -1
static var _world: Node = null


## True in a path session (and the grid is current for this physics frame); false clears it.
static func active() -> bool:
	if not RunState.path_live():
		if not _cells.is_empty() or _world != null:
			clear()
		return false
	var world: Node = RunState.world if is_instance_valid(RunState.world) else null
	if _frame != Engine.get_physics_frames() or not is_same(_world, world):
		_frame = Engine.get_physics_frames()
		_world = world
		rebuild(RunState.get_tree())
	return true


static func clear() -> void:
	_cells.clear()
	_frame = -1
	_world = null


## Buckets every enemy (tests call it after placing a layout).
static func rebuild(tree: SceneTree) -> void:
	builds += 1
	_cells.clear()
	_cell = Tuning.enemy_separation_radius
	for e in tree.get_nodes_in_group(&"enemy"):
		var n := e as Node2D
		if n == null:
			continue
		var key := key_of(n.global_position)
		if not _cells.has(key):
			_cells[key] = []
		(_cells[key] as Array).append(n)


static func key_of(pos: Vector2) -> Vector2i:
	return Vector2i((pos / _cell).floor())


## The legacy loop's push, over the 3x3 cells around `me`.
static func push(me: Node2D) -> Vector2:
	var push_sum := Vector2.ZERO
	var radius := Tuning.enemy_separation_radius
	var at := key_of(me.global_position)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell: Variant = _cells.get(at + Vector2i(dx, dy))
			if cell == null:
				continue
			for other in cell:
				if not is_instance_valid(other) or other == me:
					continue
				var away: Vector2 = me.global_position - (other as Node2D).global_position
				var dist := away.length()
				if dist > 0.01 and dist < radius:
					push_sum += away / dist * (1.0 - dist / radius)
	return push_sum
