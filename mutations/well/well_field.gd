extends Node2D
## The well patch's pull field (PLAN v6 3): for LIFE seconds of game time, every enemy
## within RADIUS is dragged toward the centre, harder near it (walls stop it). Never the player, never
## damage. Not an entity.
## M45b: life / radius / pull are vars (the consts by default, so the patch is unchanged) and
## _after_pull is a no-op hook, for the well weapon's field (weapons/well_weapon_field.gd).

const LIFE := 1.0
const RADIUS := 2.6 * Tuning.TILE
const PULL := 230.0         ## px/s of drag at the edge, up to 1.5 times that near the centre
const COLOR := Color(0.6, 0.45, 1.0)

var life := LIFE
var radius := RADIUS
var pull := PULL
var _age := 0.0


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= life:
		queue_free()
		return
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := e as Node2D
		if enemy == null or enemy.is_queued_for_deletion():   # the dead one is on its way out
			continue
		var to_centre := global_position - enemy.global_position
		var d := to_centre.length()
		if d > radius or d < 4.0:
			continue
		# A drag on the position, not a push on the velocity: an enemy's own steering
		# (accel 3200 px/s²) would cancel any push it could stand.
		var body := enemy as CharacterBody2D
		if body and not TurnClock.on_grid(body):
			body.move_and_collide(to_centre / d * minf(pull * (1.5 - 0.5 * d / radius) * delta, d))
	_after_pull(delta)
	queue_redraw()


## After the enemies are dragged, each tick (the patch: nothing).
func _after_pull(_delta: float) -> void:
	pass


func _draw() -> void:
	var u := clampf(_age / life, 0.0, 1.0)
	for k in 3:
		var r := radius * fposmod(1.0 - u * 1.5 - k / 3.0, 1.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(COLOR, 0.5 * (1.0 - u)), 2.0)
	draw_circle(Vector2.ZERO, 6.0, Color(COLOR, 1.0 - u))
