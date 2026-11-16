class_name Mover
extends Component
## Moves its CharacterBody2D parent. Whoever controls the entity (player input,
## enemy AI) only sets `wish`; the Mover decides how that becomes motion from the
## current rules. M1: no-gravity movement only. Gravity arrives in M2.

var speed := 300.0
var accel := 3200.0
var friction := 3600.0

var wish := Vector2.ZERO   ## desired direction, length 0..1
var height := 0.0          ## distance above the ground plane when gravity is off (0 = grounded)


func _physics_process(delta: float) -> void:
	var body := get_parent() as CharacterBody2D
	if body == null:
		return
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	body.wall_min_slide_angle = 0.0
	var target := wish.limit_length(1.0) * speed
	var rate := accel if wish != Vector2.ZERO else friction
	body.velocity = body.velocity.move_toward(target, rate * delta)
	body.move_and_slide()


func knockback(impulse: Vector2) -> void:
	var body := get_parent() as CharacterBody2D
	if body:
		body.velocity += impulse
