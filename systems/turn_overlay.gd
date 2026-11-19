class_name TurnOverlay
extends Node2D
## B2 readability (PLAN v3 section 3): the player's tile and the aim line, drawn in
## the world while turn-based is on. Presentation only.

const COLOR := Color(1.0, 0.8, 0.45, 0.8)
const AIM_TILES := 5

var player: Node2D


func _ready() -> void:
	z_index = 5
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	visible = RunState.rules.turn_based and is_instance_valid(player) and player.visible
	if visible:
		queue_redraw()
		# The player is paused between turns, so its own aim visual would freeze;
		# keep the gun pointing where the next shot will go.
		var input := player.get(&"input") as PlayerInput
		var aim := player.get_node_or_null(^"Aim") as Node2D
		if input and aim:
			aim.rotation = input.aim_dir.angle()


func _draw() -> void:
	var t := Tuning.TILE
	var center := TurnClock.tile_center(player.global_position)
	draw_rect(Rect2(center - Vector2(t, t) * 0.5, Vector2(t, t)), COLOR, false, 2.0)
	var input := player.get(&"input") as PlayerInput
	if input == null:
		return
	var from := player.global_position
	var dir := input.aim_dir.normalized()
	for i in range(1, AIM_TILES * 2):
		if i % 2 == 1:
			draw_line(from + dir * (i * t * 0.5), from + dir * ((i + 0.6) * t * 0.5), COLOR, 2.0)
