extends PatchTake
## Top-down take (PLAN v6 3): each player shot fires again DELAY seconds of game time
## later, from where it was fired, the same way. An echo does not echo, and it is the
## patch's shot (source_patch), not the trigger's (no projectile_fired).

const PROJECTILE := preload("res://entities/projectile.tscn")
@export var delay := 0.6
## M33 parity: at full damage the echo doubled the gun (+15% mortal time); half keeps it a copy.
@export var damage_factor := 0.5


func enable() -> void:
	_listen(EventBus.projectile_fired, _on_fired)


func _on_fired(projectile: Node) -> void:
	if not is_instance_valid(projectile) or projectile.get(&"faction") != &"player" \
			or projectile.get(&"source_patch") == id:
		return
	var shot := projectile as Node2D
	# Physics time, paused with the tree: the same seed fires the same echoes.
	var timer := RunState.get_tree().create_timer(delay, false, true)
	timer.timeout.connect(_echo.bind(shot.position, shot.get(&"velocity"), float(shot.get(&"damage")) * damage_factor))


func _echo(pos: Vector2, velocity: Vector2, damage: float) -> void:
	if not RunState.has_patch(id) or not is_instance_valid(RunState.world):
		return   # reverted, or the run is over, while the echo was on its way
	RunState.spawn(PROJECTILE, pos, {&"kind": &"player_projectile", &"faction": &"player",
			&"velocity": velocity, &"damage": damage, &"source_patch": id})
