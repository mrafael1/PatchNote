extends Node2D
## The laser's overcharge beam (M50.1a): a line from the muzzle along the aim to the first wall
## (at most REACH), alive `life` seconds of game time; every TICK each enemy whose centre is
## within its half width + HALF of it takes `damage`. One at a time (a new one is refused while
## one lives). Not an entity, not a projectile. Colour: the player_shot role (the current look).

const REACH := 40.0 * Tuning.TILE
const HALF := 10.0
const TICK := 0.25
const GROUP := &"overcharge_beam"

var from := Vector2.ZERO
var to := Vector2.ZERO
var damage := 1.0
var life := 1.0
var source: StringName = &""
var hits := 0   ## tests
var _born := -1.0
var _next := {}


## Throws a beam; null while another lives (one at a time).
static func fire(p_from: Vector2, dir: Vector2, p_damage: float, p_life: float, p_source: StringName) -> Node2D:
	for b in RunState.get_tree().get_nodes_in_group(GROUP):
		if not b.is_queued_for_deletion():
			return null
	var beam: Node2D = (load("res://weapons/traits/overcharge_beam.gd") as GDScript).new()
	beam.from = p_from
	beam.to = p_from + dir * REACH
	var world := RunState.world as Node2D
	if world != null and world.is_inside_tree():
		var q := PhysicsRayQueryParameters2D.create(p_from, beam.to, Tuning.LAYER_WORLD)
		var hit := world.get_world_2d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			beam.to = hit.position
	beam.damage = p_damage
	beam.life = p_life
	beam.source = p_source
	beam.add_to_group(GROUP)
	RunState.world.add_child.call_deferred(beam)
	return beam


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO


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
		var c := Geometry2D.get_closest_point_to_segment(enemy.global_position, from, to)
		if c.distance_to(enemy.global_position) > half + HALF:
			continue
		if RunState.game_time < float(_next.get(enemy, -1.0)):
			continue
		_next[enemy] = RunState.game_time + TICK
		var hp := Component.find(enemy, Health) as Health
		if hp and hp.take(DamageInfo.make(damage, &"beam", &"player", c, source)):
			hits += 1
	queue_redraw()


func _draw() -> void:
	var age := RunState.game_time - _born if _born >= 0.0 else 0.0
	var a := clampf(1.0 - age / maxf(life, 0.01), 0.0, 1.0)
	var c := Palette.color(&"player_shot")
	draw_line(from, to, Color(c, 0.35 * a), HALF * 2.0)
	draw_line(from, to, Color(1, 1, 1, 0.8 * a), 3.0)
