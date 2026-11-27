class_name HotEdges
extends Node2D
## M50.3c (PLAN v9 1.9, edit_hot_edges): while the rule is on (WorldRules.hot_edge_tiles > 0)
## the arena's outer tiles, counted inside its one-tile border, hurt the player: one hit of
## Tuning.hot_edge_damage for every Tuning.hot_edge_tick game seconds stood in the band (the
## count restarts on leaving it). A tile within GATE_CLEAR tiles of an exit gate is never hot.
## With the rule at 0 (every session before S10, the v6 loop) it reads nothing and draws
## nothing. No RNG. The band is drawn in the `danger` role and pulses unless reduce flashing
## is on.

const GATE_CLEAR := 2.0   ## tiles around an exit gate that stay cool
const KIND := &"hot_edge"

var genre: Node          ## TopdownGenre: its arena and player, read each tick (parts swap arenas)
var inside := 0.0        ## game seconds in the band since the player last left it
var burns := 0           ## hits dealt (tests, the bot line)
var _shown := false


func _ready() -> void:
	z_index = 1


## The band's depth in pixels from the arena's bounds (0: off).
func band() -> float:
	var n := RunState.rules.hot_edge_tiles
	return (n + 1) * Tuning.TILE if n > 0 else 0.0


func is_hot(p: Vector2) -> bool:
	var depth := band()
	if depth <= 0.0 or genre == null or genre.get(&"arena") == null:
		return false
	var b: Rect2 = genre.arena.bounds
	if not b.has_point(p):
		return false
	var d := minf(minf(p.x - b.position.x, b.end.x - p.x), minf(p.y - b.position.y, b.end.y - p.y))
	if d >= depth:
		return false
	for g in get_tree().get_nodes_in_group(ExitGate.GROUP):
		if (g as Node2D).global_position.distance_to(p) <= GATE_CLEAR * Tuning.TILE:
			return false
	return true


func _physics_process(delta: float) -> void:
	var on := band() > 0.0
	if on != _shown:
		_shown = on
		queue_redraw()
	if not on:
		inside = 0.0
		return
	if not SaveGame.reduce_flashing():
		queue_redraw()   # the pulse
	var player: Node2D = genre.get(&"player") if genre != null else null
	if player == null or not is_instance_valid(player) or not is_hot(player.global_position):
		inside = 0.0
		return
	inside += delta
	if inside < Tuning.hot_edge_tick:
		return
	inside -= Tuning.hot_edge_tick
	var health := Component.find(player, Health) as Health
	if health != null and health.take(DamageInfo.make(Tuning.hot_edge_damage, KIND, &"enemy", player.global_position)):
		burns += 1
		RunState.log_event(&"hot_edge_hit")


func _draw() -> void:
	var depth := band()
	if depth <= 0.0 or genre == null or genre.get(&"arena") == null:
		return
	var b: Rect2 = genre.arena.bounds
	var a := 0.22
	if not SaveGame.reduce_flashing():
		a = 0.17 + 0.09 * (0.5 + 0.5 * sin(RunState.real_time() * 4.0))
	var c := Color(Palette.color(&"danger"), a)
	draw_rect(Rect2(b.position, Vector2(b.size.x, depth)), c)
	draw_rect(Rect2(b.position.x, b.end.y - depth, b.size.x, depth), c)
	draw_rect(Rect2(b.position.x, b.position.y + depth, depth, b.size.y - 2.0 * depth), c)
	draw_rect(Rect2(b.end.x - depth, b.position.y + depth, depth, b.size.y - 2.0 * depth), c)
	var edge := Color(Palette.color(&"danger"), 0.7)
	draw_rect(Rect2(b.position + Vector2.ONE * depth, b.size - Vector2.ONE * 2.0 * depth), edge, false, 2.0)
