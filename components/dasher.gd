class_name Dasher
extends Component
## Short burst of movement with invulnerability. The same definition in every
## rule state: direction comes from the caller, never from the mouse.

signal dashed

var _cooldown_left := 0.0


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)


func is_ready() -> bool:
	return _cooldown_left <= 0.0


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
	if health:
		health.grant_invulnerability(duration)
	_cooldown_left = Tuning.dash_cooldown
	dashed.emit()
	return true
