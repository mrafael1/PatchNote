extends PatchTake
## Top-down take (PLAN v5 1.2).
## B1, "Time moves when you move": a small patch since PLAN v5 (1.4). Stand still and
## the world almost stops; move, shoot or dash and it runs. The patch owns the motion
## factor and hands it to RunState.set_time_factor every tick; RunState stays the only
## writer of Engine.time_scale. Reverting strips the factor in the same tick.


func apply_rules(rules: WorldRules) -> void:
	rules.time_follows_motion = true
	rules.idle_time_scale *= 0.08


func enable() -> void:
	_listen(EventBus.projectile_fired, _on_projectile_fired)
	_listen(EventBus.player_dashed, _on_player_dashed)
	_listen(RunState.get_tree().physics_frame, _step)


## What the motion factor is heading for right now (PLAN v3 section 2). Full speed
## (or a held direction, so time starts the moment the player decides to move) runs
## time at 1; standing still runs it at idle_time_scale. A pause, a dead or missing
## player, and the pulse after a manual shot or a dash all give 1.
func target() -> float:
	var tree := RunState.get_tree()
	if tree.paused or float(state().get("pulse", 0.0)) > 0.0:
		return 1.0
	var player := tree.get_first_node_in_group(&"player") as CharacterBody2D
	if player == null or not is_instance_valid(player):
		return 1.0
	var health := Component.find(player, Health) as Health
	if health and health.dead:
		return 1.0
	var amount := player.velocity.length() / maxf(Tuning.player_speed, 1.0)
	var input := player.get(&"input") as PlayerInput
	if input:
		amount = maxf(amount, input.move.length())
	return lerpf(RunState.rules.idle_time_scale, 1.0, clampf(amount, 0.0, 1.0))


## One physics tick, on real time (the fixed physics step, whatever the time scale).
func _step() -> void:
	# A revert during this same physics_frame emission disconnects the listener only for
	# the next one: without this, the stripped patch would write its state and factor back.
	if not RunState.has_patch(id):
		return
	var real_delta := 1.0 / float(Engine.physics_ticks_per_second)
	var s := state()
	s["pulse"] = maxf(0.0, float(s.get("pulse", 0.0)) - real_delta)
	var goal := target()
	var motion := 1.0
	if goal < 1.0:   # full speed, a pause or a pulse: time runs at once, no ramp
		motion = lerpf(float(s.get("motion", 1.0)), goal, 1.0 - exp(-real_delta / Tuning.motion_smoothing))
	s["motion"] = motion
	RunState.set_time_factor(id, motion)


## Only the player's own trigger pulses time. Auto-attack shots keep the slow motion
## (owner, 2026-11-20): standing still while the weapon fires by itself is B1's bonus.
func _on_projectile_fired(projectile: Node) -> void:
	if projectile.get(&"faction") == &"player" and not projectile.get(&"auto_fired"):
		state()["pulse"] = Tuning.motion_pulse


func _on_player_dashed() -> void:
	state()["pulse"] = Tuning.motion_pulse
