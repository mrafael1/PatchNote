extends Node2D
## A caltrop (the shotgun's shrapnel, M50.1a): DAMAGE to the first enemy whose body touches it,
## then it is gone; else it goes after `life` seconds of game time. Not an entity and not a
## projectile (RunState's budgets never see it); at most CAP alive (the oldest goes). Colour:
## the player_shot role (the current look).

const DAMAGE := 1.0
const CAP := 30
const RADIUS := 5.0
const GROUP := &"caltrop"

var life := 3.0
var source: StringName = &""
var hits := 0   ## tests
var _born := -1.0


## Drops one at `pos` (deferred into the world), making room under CAP first.
static func drop(pos: Vector2, p_life: float, p_source: StringName) -> Node2D:
	make_room(CAP)
	var c: Node2D = (load("res://weapons/traits/caltrop.gd") as GDScript).new()
	c.position = pos
	c.life = p_life
	c.source = p_source
	c.add_to_group(GROUP)
	RunState.world.add_child.call_deferred(c)
	return c


## Frees the oldest (tree order) until fewer than `cap` are alive.
static func make_room(cap: int) -> void:
	var alive: Array[Node] = []
	for z in RunState.get_tree().get_nodes_in_group(GROUP):
		if not z.is_queued_for_deletion():
			alive.append(z)
	var i := 0
	while alive.size() - i >= cap and i < alive.size():
		alive[i].remove_from_group(GROUP)
		alive[i].queue_free()
		i += 1


func _physics_process(_delta: float) -> void:
	if _born < 0.0:
		_born = RunState.game_time
	if RunState.game_time - _born >= life:
		queue_free()
		return
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := e as Node2D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		var half: float = enemy.get(&"half_width") if enemy.get(&"half_width") != null else 15.0
		if enemy.global_position.distance_to(global_position) > half + RADIUS:
			continue
		var hp := Component.find(enemy, Health) as Health
		if hp and hp.take(DamageInfo.make(DAMAGE, &"caltrop", &"player", global_position, source)):
			hits += 1
			remove_from_group(GROUP)
			queue_free()
			return


func _draw() -> void:
	var c := Palette.color(&"player_shot")
	var pts := PackedVector2Array([Vector2(0, -RADIUS), Vector2(RADIUS, RADIUS * 0.7), Vector2(-RADIUS, RADIUS * 0.7)])
	draw_colored_polygon(pts, Color(c, 0.85))
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, Palette.color(&"outline"), 1.0)
