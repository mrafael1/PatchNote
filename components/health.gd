class_name Health
extends Component
## Hit points. Stores a ratio, not a number, so the effective maximum can follow
## the rules (enemy_hp_mult) and a rule change neither heals nor hurts anyone.

signal died(info: DamageInfo)
## A hit the shield took whole (shield_hits was above 0): no damage, no damage signal.
signal shield_hit(info: DamageInfo)

@export var base_max_hp := 3.0
@export var scales_with_enemy_rule := true
@export var invuln_time := 0.0   ## seconds of immunity after a hit

## Hits absorbed whole before any damage lands, one per hit (M33: an elite's shield,
## the hunter's stun count). 0 = no shield.
var shield_hits := 0
var hp_ratio := 1.0
var dead := false
## M47: max HP never below this after the rules (0 = no floor; a splitter's minis: 1).
var min_max_hp := 0.0
var _invuln_until := -1.0


func max_hp() -> float:
	if not scales_with_enemy_rule:
		return base_max_hp
	var rules := RunState.rules
	var m := base_max_hp * rules.enemy_hp_mult + rules.enemy_hp_add
	if rules.enemy_hp_one:
		m = minf(m, 1.0)   # edit_tiny_enemies: one hit each
	if min_max_hp > 0.0:
		m = maxf(m, min_max_hp)
	return m


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
	# M48b (PLAN 1.7.1): a specimen (S9's first asset) takes nothing until its release.
	if get_parent().get(&"specimen") == true:
		return false
	# Before the session has `health` nothing hurts the player, and nothing shows it:
	# no i-frames, no telemetry, no player_hit (owner, M39.2).
	if get_parent().get(&"damage_locked") == true:
		EventBus.player_touched.emit()
		return false
	if shield_hits > 0:
		shield_hits -= 1
		shield_hit.emit(info)
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
	var hp_floor := float(RunState.rules.hp_floor) if is_player else 0.0
	if hp_floor > 0.0:
		# PLAN v9 1.2: the hit still counts, signals and grants i-frames; HP never goes
		# below the floor (or below the current HP, if it is already lower).
		hp_ratio = maxf(hp() - info.amount, minf(hp(), hp_floor)) / max_hp()
	else:
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
