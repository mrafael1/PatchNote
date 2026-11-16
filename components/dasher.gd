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


func try_dash(dir: Vector2) -> bool:
	if _cooldown_left > 0.0 or dir == Vector2.ZERO:
		return false
	var entity := get_parent()
	var mover := Component.find(entity, Mover) as Mover
	if mover == null:
		return false
	mover.dash(dir.normalized() * (Tuning.dash_distance / Tuning.dash_time), Tuning.dash_time)
	var health := Component.find(entity, Health) as Health
	if health:
		health.grant_invulnerability(Tuning.dash_time)
	_cooldown_left = Tuning.dash_cooldown
	dashed.emit()
	return true
