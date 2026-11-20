class_name Health
extends Component
## Hit points. Stores a ratio, not a number, so the effective maximum can follow
## the rules (enemy_hp_mult) and a rule change neither heals nor hurts anyone.

signal died(info: DamageInfo)

@export var base_max_hp := 3.0
@export var scales_with_enemy_rule := true
@export var invuln_time := 0.0   ## seconds of immunity after a hit

var hp_ratio := 1.0
var dead := false
var _invuln_until := -1.0


func max_hp() -> float:
	var mult := RunState.rules.enemy_hp_mult if scales_with_enemy_rule else 1.0
	return base_max_hp * mult


func hp() -> float:
	return hp_ratio * max_hp()


func is_invulnerable() -> bool:
	return RunState.game_time < _invuln_until


func grant_invulnerability(seconds: float) -> void:
	_invuln_until = maxf(_invuln_until, RunState.game_time + seconds)


func heal(amount: float) -> void:
	if dead:
		return
	hp_ratio = minf(1.0, (hp() + amount) / max_hp())


## The only place damage is applied and the only emitter of the damage signals.
## Returns true if the damage was applied.
func take(info: DamageInfo) -> bool:
	if dead or is_invulnerable():
		return false
	var entity := get_parent()
	var is_player := entity.is_in_group(&"player")
	if is_player and info.faction == &"enemy" and RunState.in_grace():
		return false
	if is_player and RunState.invincible:
		# Counted for telemetry (hits per genre in bot runs), with the same i-frames a
		# real hit gives, so an invincible run measures what a mortal one would take.
		if invuln_time > 0.0:
			grant_invulnerability(invuln_time)
		RunState.log_event(&"player_hit", {"amount": info.amount, "kind": info.kind, "blocked": true})
		return false
	hp_ratio = maxf(0.0, (hp() - info.amount) / max_hp())
	if invuln_time > 0.0:
		grant_invulnerability(invuln_time)
	EventBus.entity_damaged.emit(entity, info)
	if is_player:
		RunState.log_event(&"player_hit", {"amount": info.amount, "kind": info.kind, "blocked": false})
		EventBus.player_hit.emit(info)
	if hp() <= 0.001:
		dead = true
		if is_player:
			EventBus.player_died.emit()
		elif entity.is_in_group(&"enemy"):
			EventBus.enemy_killed.emit(entity, info)
		died.emit(info)
	return true
