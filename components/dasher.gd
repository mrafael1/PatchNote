class_name Dasher
extends Component
## Short burst of movement with invulnerability (none under turn-based, where a dash
## is movement, not protection). Direction comes from the caller, never from the mouse.
##
## The campaign asks which dash (M42.1, fork_dash; Unlocks.dash_style() sets `style`):
## classic is try_dash(), as built; grapple throws a hook along the move direction and
## pulls the player to the wall it catches (Mover.pull_to); teleport blinks ahead,
## through walls, to the nearest free spot in the arena. Outside a session the style is
## always classic (the v6 loop, B2, run_hash).

signal dashed
## The hook caught a wall: the pull runs toward anchor (the wall point).
signal hooked(anchor: Vector2)
## The hook flew out and caught nothing (no move, a short cooldown, no `dashed`).
signal hook_missed(from: Vector2, to: Vector2)
signal teleported(from: Vector2, to: Vector2)
## A teleport found no free spot: nothing happens, nothing is spent.
signal fizzled

const STYLES: Array[StringName] = [&"classic", &"grapple", &"teleport"]
const LABELS := {&"classic": "dash", &"grapple": "hook", &"teleport": "teleport"}
const HOOK_GAP := 2.0          ## the pull stops this far short of the wall
const TELEPORT_STEP := 8.0     ## the teleport steps back by this much to find a free spot

var style: StringName = &"classic"

var _cooldown_left := 0.0


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)


func is_ready() -> bool:
	return _cooldown_left <= 0.0


## The HUD's word for it: "dash", "hook" or "teleport".
func label() -> String:
	return LABELS.get(style, "dash")


## The dash button: the style's own move along move_dir (aim_dir is only read by the
## grapple when Tuning.grapple_aims). Classic is exactly try_dash(move_dir).
func use(move_dir: Vector2, aim_dir := Vector2.ZERO) -> bool:
	match style:
		&"grapple":
			return _grapple(move_dir, aim_dir)
		&"teleport":
			return _teleport(move_dir)
		_:
			return try_dash(move_dir)


## distance and duration default to Tuning's dash; B2 dashes 2 tiles over one turn.
func try_dash(dir: Vector2, distance := -1.0, duration := -1.0) -> bool:
	if _cooldown_left > 0.0 or dir == Vector2.ZERO:
		return false
	var entity := get_parent()
	var mover := Component.find(entity, Mover) as Mover
	if mover == null:
		return false
	if distance <= 0.0:
		distance = Tuning.dash_distance
	if duration <= 0.0:
		duration = Tuning.dash_time
	mover.dash(dir.normalized() * (distance / duration), duration)
	var health := Component.find(entity, Health) as Health
	if health and not RunState.rules.turn_based:
		health.grant_invulnerability(duration)
	_cooldown_left = Tuning.dash_cooldown
	dashed.emit()
	return true


# --- The grappling hook -------------------------------------------------------------

## A box cast of the body's own shape along dir, then 1x and 2x Tuning.grapple_cone_deg
## either side; the first wall hit at least a tile away wins. A hit pulls the player 2 px
## short of it (at rest), with i-frames for the pull. Under gravity, a side wall (not a
## floor or a ceiling) holds the player Tuning.grapple_latch; air jumps are not given back.
func _grapple(move_dir: Vector2, aim_dir: Vector2) -> bool:
	var dir := aim_dir if Tuning.grapple_aims and aim_dir != Vector2.ZERO else move_dir
	if _cooldown_left > 0.0 or dir == Vector2.ZERO:
		return false
	var body := get_parent() as CharacterBody2D
	var mover := Component.find(body, Mover) as Mover
	if body == null or mover == null:
		return false
	dir = dir.normalized()
	var from := body.global_position
	var hit := grapple_target(body, dir)
	if hit.is_empty():
		_cooldown_left = Tuning.grapple_miss_cooldown
		hook_missed.emit(from, from + dir * Tuning.grapple_range)
		return false
	var stop: Vector2 = hit.stop
	var normal: Vector2 = hit.normal
	mover.pull_to(stop, Tuning.grapple_speed)
	var rules := RunState.rules
	if rules.gravity_enabled and not mover.ignores_gravity() \
			and absf(normal.dot(rules.gravity_dir.normalized())) < 0.5:
		mover.hold_after_pull(Tuning.grapple_latch)
	var health := Component.find(body, Health) as Health
	if health and not rules.turn_based:
		health.grant_invulnerability(from.distance_to(stop) / Tuning.grapple_speed + 0.05)
	_cooldown_left = Tuning.grapple_cooldown
	hooked.emit(hit.anchor)
	dashed.emit()
	return true


## Where a hook thrown from body along dir lands: {stop, anchor, normal}, or {} for a miss.
static func grapple_target(body: CharacterBody2D, dir: Vector2) -> Dictionary:
	var shape := _body_shape(body)
	if shape == null:
		return {}
	var space := body.get_world_2d().direct_space_state
	var from := body.global_position
	var cone := deg_to_rad(Tuning.grapple_cone_deg)
	for a: float in [0.0, cone, -cone, 2.0 * cone, -2.0 * cone]:
		var d := dir.rotated(a)
		var q := PhysicsShapeQueryParameters2D.new()
		q.shape = shape
		q.transform = Transform2D(0.0, from)
		q.motion = d * Tuning.grapple_range
		q.collision_mask = Tuning.LAYER_WORLD
		q.exclude = [body.get_rid()]
		var r := space.cast_motion(q)
		if r.size() < 2 or r[1] >= 1.0:
			continue
		var safe_len: float = Tuning.grapple_range * float(r[0])
		if safe_len < Tuning.TILE:
			continue   # a wall right there is no hook
		q.transform = Transform2D(0.0, from + d * Tuning.grapple_range * float(r[1]))
		q.motion = Vector2.ZERO
		var rest := space.get_rest_info(q)
		var normal: Vector2 = rest.get("normal", -d)
		var anchor: Vector2 = rest.get("point", from + d * (safe_len + 17.0))
		# cast_motion's safe fraction stops short by about a pixel: put the box's face
		# exactly HOOK_GAP off the wall's plane instead (never past the safe travel).
		var s := safe_len - HOOK_GAP
		var along := -normal.dot(d)
		if rest.has("normal") and along > 0.2:
			var half := _support(shape, normal)
			s = minf(safe_len, (normal.dot(anchor - from) + half + HOOK_GAP) / -along)
		return {"stop": from + d * maxf(s, 0.0), "anchor": anchor, "normal": normal}
	return {}


## How far the body's shape reaches toward -n from its centre (its half extent there).
static func _support(shape: Shape2D, n: Vector2) -> float:
	if shape is RectangleShape2D:
		var h := (shape as RectangleShape2D).size * 0.5
		return absf(n.x) * h.x + absf(n.y) * h.y
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius
	return 17.0


# --- The teleport -------------------------------------------------------------------

## A blink along dir, through walls: the farthest free spot from Tuning.teleport_distance
## down to one tile (8 px steps). Free: the body's box overlaps no world or enemy body,
## it lies inside the arena (the border is one tile and nothing collides beyond it) and
## in the arena's region the player can walk to (no sealed pockets). Nothing free: it
## fizzles and costs nothing.
func _teleport(dir: Vector2) -> bool:
	if _cooldown_left > 0.0 or dir == Vector2.ZERO:
		return false
	var body := get_parent() as CharacterBody2D
	var mover := Component.find(body, Mover) as Mover
	if body == null or mover == null:
		return false
	var from := body.global_position
	var to := teleport_target(body, dir.normalized())
	if to == from:
		fizzled.emit()
		return false
	if mover.is_dashing() or mover.is_holding():
		mover.stop()   # ends a dash or a pull
	body.global_position = to
	var rules := RunState.rules
	if rules.gravity_enabled and not mover.ignores_gravity():
		var g := rules.gravity_dir.normalized()
		body.velocity -= g * body.velocity.dot(g)
	var health := Component.find(body, Health) as Health
	if health and not rules.turn_based:
		health.grant_invulnerability(Tuning.teleport_iframes)
	_cooldown_left = Tuning.teleport_cooldown
	teleported.emit(from, to)
	dashed.emit()
	return true


## Where a teleport from body along dir lands (body's own position = no free spot).
static func teleport_target(body: CharacterBody2D, dir: Vector2) -> Vector2:
	var from := body.global_position
	var shape := _body_shape(body)
	if shape == null or dir == Vector2.ZERO:
		return from
	var arena := arena_of(body)
	var inside := Rect2()
	if arena != null:
		inside = arena.bounds.grow(-(Tuning.TILE + _half_extent(shape)))
	var space := body.get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collision_mask = Tuning.LAYER_WORLD | Tuning.LAYER_ENEMY_BODY
	q.exclude = [body.get_rid()]
	var d := Tuning.teleport_distance
	while d >= Tuning.TILE - 0.01:
		var p := from + dir * d
		d -= TELEPORT_STEP
		if arena != null and (not inside.has_point(p) or not arena.is_reachable(p)):
			continue
		q.transform = Transform2D(0.0, p)
		if not space.intersect_shape(q, 1).is_empty():
			continue
		return p
	return from


## The arena the body plays in (the genre holds it next to RunState.world), or null.
static func arena_of(body: Node) -> Arena:
	var world := RunState.world
	if world != null and is_instance_valid(world) and world.get_parent() != null:
		var a: Variant = world.get_parent().get(&"arena")
		if a is Arena and is_instance_valid(a):
			return a as Arena
	return null


static func _body_shape(body: CharacterBody2D) -> Shape2D:
	for c in body.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape != null:
			return (c as CollisionShape2D).shape
	return null


static func _half_extent(shape: Shape2D) -> float:
	if shape is RectangleShape2D:
		var s := (shape as RectangleShape2D).size
		return maxf(s.x, s.y) * 0.5
	return 17.0
