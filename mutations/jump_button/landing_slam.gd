extends Component
## Deals a small area hit around the point where the player lands, whether that is
## the end of a hop (no gravity) or a touchdown (gravity).

var radius := 90.0
var damage := 1.0
var knockback := 380.0


func _ready() -> void:
	EventBus.player_landed.connect(_on_landed)


func _exit_tree() -> void:
	if EventBus.player_landed.is_connected(_on_landed):
		EventBus.player_landed.disconnect(_on_landed)


func _on_landed(pos: Vector2, _impact_speed: float) -> void:
	Explosion.blast(pos, radius, damage, knockback, &"slam", source_patch, false)
