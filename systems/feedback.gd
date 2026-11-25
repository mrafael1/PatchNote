class_name Feedback
extends Node
## Hit feedback. Presentation only: it listens to gameplay events and never changes
## gameplay state. Hit flash, particles (death puff, wall sparks, landing dust, dash
## trail, explosion sparks, player hit burst), screen shake.
##
## Two layers (PLAN v5 1.7, 2.2). Readability, in every look: the hit flash and HP
## bar, the kill pop, the player-hit vignette. Juice, scaled by Look.preset: shake,
## particle counts, hit stop, the muzzle flash and the screen flash. Hit stop is a
## time factor set through RunState (the one time-scale writer) for real seconds.

const PUFF_COUNT := 12
const MAX_LIVE_EFFECTS := 80   ## beyond this, new bursts are skipped (a horde of bounces)
const DUST := Palette.DUST
const HIT := Palette.HIT
const KILL_STOP_SHARE := 0.35   ## a kill's hit stop, as a share of the preset's
const MUZZLE := Palette.MUZZLE
const DASH := Palette.DASH   ## the dash burst's colour (the hook, the teleport)

var camera: CameraRig
var effects_parent: Node
var screen: ScreenFx
var kill_pops := 0   ## kill pops shown this run (tests)

var _live := 0


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ScreenFxLayer"
	layer.layer = 40
	add_child(layer)
	screen = ScreenFx.new()
	layer.add_child(screen)
	EventBus.projectile_fired.connect(_on_projectile_fired)
	EventBus.player_died.connect(_on_player_died)
	EventBus.entity_damaged.connect(_on_entity_damaged)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_hit.connect(_on_player_hit)
	EventBus.projectile_hit_wall.connect(_on_hit_wall)
	EventBus.player_landed.connect(_on_player_landed)
	EventBus.player_dashed.connect(_on_player_dashed)
	EventBus.player_hooked.connect(_on_player_hooked)
	EventBus.player_hook_missed.connect(_on_player_hook_missed)
	EventBus.player_teleported.connect(_on_player_teleported)
	EventBus.player_dash_fizzled.connect(_on_player_dash_fizzled)
	EventBus.explosion.connect(_on_explosion)


func _on_entity_damaged(target: Node, _info: RefCounted) -> void:
	var visual := target.get_node_or_null("Visual") as RectVisual
	if visual:
		visual.flash()
		if target.is_in_group(&"enemy"):
			var health := Component.find(target, Health) as Health
			if health:
				visual.hp_shown = health.hp_ratio


func _on_enemy_killed(enemy: Node, _info: RefCounted) -> void:
	var visual := enemy.get_node_or_null("Visual") as RectVisual
	var color := _body_color(visual)
	var pos := (enemy as Node2D).global_position
	puff(pos, color)
	kill_pop(pos, color)
	hit_stop(Look.preset.hit_stop * KILL_STOP_SHARE)


func _on_player_hit(_info: RefCounted) -> void:
	if camera:
		camera.shake(9.0)
	if screen:
		screen.vignette()
	hit_stop(Look.preset.hit_stop)
	var player := _player()
	if player:
		burst(player.global_position, Palette.color(&"hit"), 10, 120.0, 260.0, 0.35, 5.0)


func _on_hit_wall(projectile: Node, pos: Vector2, normal: Vector2) -> void:
	var visual := projectile.get_node_or_null("Visual") as RectVisual if is_instance_valid(projectile) else null
	var color := _body_color(visual)
	burst(pos, color, 5, 60.0, 180.0, 0.18, 3.0, normal, 70.0)


func _on_player_landed(pos: Vector2, impact_speed: float) -> void:
	var rules := RunState.rules
	var up := -rules.gravity_dir.normalized() if rules.gravity_enabled else Vector2.UP
	var amount := int(clampf(impact_speed / 60.0, 6.0, 16.0))
	burst(pos - up * 16.0, Palette.color(&"dust"), amount, 50.0, 160.0, 0.35, 4.0, up, 80.0, 0.3)
	if camera and impact_speed > 700.0:
		camera.shake(4.0)


func _on_player_dashed() -> void:
	var player := _player()
	if player:
		burst(player.global_position, Color(Palette.color(&"dash"), 0.8), 10, 20.0, 90.0, 0.3, 6.0)


## The hook (M42.1): a line from the player to the anchor for the pull, a burst there.
func _on_player_hooked(anchor: Vector2) -> void:
	burst(anchor, Palette.color(&"dash"), 6, 20.0, 90.0, 0.25, 4.0)
	var player := _player()
	if player == null or not is_instance_valid(effects_parent):
		return
	var line := _dash_line(2.0, Color(Palette.color(&"dash"), 0.9))
	var follow := func(u: float) -> void:
		if is_instance_valid(player) and is_instance_valid(line):
			line.points = PackedVector2Array([player.global_position, anchor])
			line.modulate.a = 1.0 - u * u
	var t := line.create_tween()
	t.tween_method(follow, 0.0, 1.0, 0.25)
	t.tween_callback(line.queue_free)


## A hook that caught nothing: always seen (and heard, Sound): out to full range and back.
func _on_player_hook_missed(from: Vector2, to: Vector2) -> void:
	if not is_instance_valid(effects_parent):
		return
	var line := _dash_line(2.0, Color(Palette.color(&"dash"), 0.7))
	var fly := func(u: float) -> void:
		if is_instance_valid(line):
			line.points = PackedVector2Array([from, from.lerp(to, 1.0 - absf(1.0 - 2.0 * u))])
	var t := line.create_tween()
	t.tween_method(fly, 0.0, 1.0, 0.15)
	t.tween_callback(line.queue_free)


## A blink: a fading ghost where the player was, the dash burst at both ends, a faint line.
func _on_player_teleported(from: Vector2, to: Vector2) -> void:
	burst(from, Color(Palette.color(&"dash"), 0.8), 8, 20.0, 90.0, 0.25, 5.0)
	burst(to, Color(Palette.color(&"dash"), 0.8), 8, 20.0, 90.0, 0.25, 5.0)
	if not is_instance_valid(effects_parent):
		return
	var ghost := RectVisual.new()
	ghost.size = Vector2(34, 34)
	ghost.color = Color(Palette.color(&"dash"), 0.5)
	ghost.position = from
	effects_parent.add_child(ghost)
	var gt := ghost.create_tween()
	gt.tween_property(ghost, "modulate:a", 0.0, 0.25)
	gt.tween_callback(ghost.queue_free)
	var line := _dash_line(1.0, Color(Palette.color(&"dash"), 0.25))
	line.points = PackedVector2Array([from, to])
	var lt := line.create_tween()
	lt.tween_property(line, "modulate:a", 0.0, 0.25)
	lt.tween_callback(line.queue_free)


## A teleport with no free spot: a small grey puff, nothing spent.
func _on_player_dash_fizzled() -> void:
	var player := _player()
	if player:
		burst(player.global_position, Palette.color(&"dust"), 5, 10.0, 50.0, 0.2, 3.0)


func _dash_line(width: float, color: Color) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.z_index = 5
	effects_parent.add_child(line)
	return line


func _on_explosion(pos: Vector2, radius: float) -> void:
	burst(pos, Palette.color(&"spark"), int(clampf(radius / 6.0, 8.0, 20.0)), radius * 1.5, radius * 3.5, 0.3, 4.0)
	if camera:
		camera.shake(3.0)
	if screen and Look.preset.screen_flash:
		screen.flash(0.12)   # was 0.25 on every blast until the M34 feedback


func _on_player_died() -> void:
	RunState.clear_time_factor(RunState.HIT_STOP)


func _on_projectile_fired(projectile: Node) -> void:
	if not Look.preset.muzzle_flash or not is_instance_valid(projectile) \
			or projectile.get(&"faction") != &"player":
		return
	var velocity: Variant = projectile.get(&"velocity")
	if not projectile is Node2D or not velocity is Vector2:
		return   # a test's stand-in shot: no direction to flash along
	burst((projectile as Node2D).global_position, Palette.color(&"muzzle"), 4, 80.0, 200.0, 0.08, 5.0,
			(velocity as Vector2).normalized(), 25.0)


## The kill confirmation, in every look: never skipped by the effect cap.
func kill_pop(pos: Vector2, color: Color) -> void:
	kill_pops += 1
	if not is_instance_valid(effects_parent):
		return
	var pop := KillPop.new()
	pop.color = color
	pop.scale_mult = Look.preset.kill_pop_scale
	pop.position = pos
	effects_parent.add_child(pop)


## Near-frozen time for `seconds` real seconds (Look.preset.hit_stop). A stop already
## running is not extended; there is none on the turn grid (time already waits there)
## or once the player is dead (the report is never slowed). The clear is bound to
## RunState, so it runs even if this node is gone by then.
func hit_stop(seconds: float) -> void:
	if seconds <= 0.0 or RunState.has_time_factor(&"hit_stop") or not is_inside_tree() \
			or RunState.rules.turn_based or _player_dead():
		return
	RunState.set_time_factor(&"hit_stop", 0.0)
	get_tree().create_timer(seconds, true, false, true).timeout.connect(
			RunState.clear_time_factor.bind(&"hit_stop"))


func puff(pos: Vector2, color: Color) -> void:
	burst(pos, color, PUFF_COUNT, 90.0, 240.0, 0.45, 6.0, Vector2.ZERO, 180.0, 0.5)


## One-shot CPUParticles2D. dir == ZERO means all directions. gravity_scale scales
## the world gravity (debris falls only when the world has gravity).
func burst(pos: Vector2, color: Color, amount: int, speed_min: float, speed_max: float,
		lifetime: float, size: float, dir := Vector2.ZERO, spread := 180.0, gravity_scale := 0.0) -> void:
	if not is_instance_valid(effects_parent) or _live >= MAX_LIVE_EFFECTS:
		return
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(1, roundi(amount * Look.preset.particle_scale))   # the look's density
	p.lifetime = lifetime
	p.direction = dir if dir != Vector2.ZERO else Vector2.RIGHT
	p.spread = spread if dir != Vector2.ZERO else 180.0
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.damping_min = speed_min * 0.5
	p.damping_max = speed_max
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.3
	p.color = color
	var skin := Skins.current
	if skin != null and skin.particle_texture() != null:
		# A look's particle sprite (PLAN 1.7): square pixels at a whole scale (one size per
		# burst, so they stay crisp), about today's on-screen size. Tier 0: untouched.
		var s := maxf(1.0, roundf(size / 3.0))
		p.texture = skin.particle_texture()
		p.scale_amount_min = s
		p.scale_amount_max = s
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	var rules := RunState.rules
	p.gravity = rules.gravity_dir.normalized() * rules.gravity_strength * gravity_scale \
			if rules.gravity_enabled and gravity_scale > 0.0 else Vector2.ZERO
	p.position = pos
	_live += 1
	p.finished.connect(_on_effect_finished.bind(p))
	effects_parent.add_child(p)
	p.emitting = true


## A body's colour for its puff, pop and sparks: the RectVisual's own (tier 0), or with a
## look the main colour of the sprite it wears.
func _body_color(visual: RectVisual) -> Color:
	var color := visual.color if visual else Color.WHITE
	if visual != null and Skins.current != null:
		color = Skins.current.main_color(Skins.id_for(visual), color)
	return color


func live_effects() -> int:
	return _live


func _on_effect_finished(p: CPUParticles2D) -> void:
	_live -= 1
	p.queue_free()


func _player_dead() -> bool:
	var player := _player()
	var health := Component.find(player, Health) as Health if player else null
	return health != null and health.dead


func _player() -> Node2D:
	return get_tree().get_first_node_in_group(&"player") as Node2D
