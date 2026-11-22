extends Component
## On the player (PLAN v6 3): waits for the hunter's time (ARRIVE seconds of run time),
## then sends one hunter (hunter_body.gd) from the spawner's off-screen point. A
## component, so there is one per run (Component.attach), a revert strips it, and it
## takes its hunter with it when it leaves (M33: a watcher node added to the world with
## call_deferred could be orphaned and leak when the world went first). A revert and
## re-apply past ARRIVE puts the same hunter back at once (named "Hunter"), so the world
## is a function of the stack (the smoke matrix rebuilds it that way).

const ARRIVE := 60.0
const BODY := preload("res://mutations/hunter/hunter_body.gd")

var hunter: Node2D


func _ready() -> void:
	_send()


func _physics_process(_delta: float) -> void:
	_send()


func _send() -> void:
	if hunter != null or RunState.game_time < ARRIVE or not is_instance_valid(RunState.world):
		return
	var spawner := RunState.world.get_parent().get_node_or_null(^"Spawner") as Spawner
	hunter = BODY.new()
	hunter.name = "Hunter"
	hunter.position = spawner.pick_point() if spawner and is_instance_valid(spawner.player) else Vector2.ZERO
	RunState.world.add_child(hunter)


func _exit_tree() -> void:
	if is_instance_valid(hunter):
		if hunter.is_inside_tree():
			hunter.get_parent().remove_child(hunter)   # gone now: a re-apply reuses the name
		hunter.queue_free()
	hunter = null
