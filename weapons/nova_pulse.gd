extends Node2D
## The nova weapon (PLAN v9 1.4, M45b): a passive on the player. Every `cooldown` seconds of
## game time (3 s; its own timer on the physics tick, so it waits while the tree is paused)
## it blasts around the player: Explosion.blast at `radius` (1.5 T), `damage` (3), kind
## `blast`, credited "weapon:nova", no knockback, the player never pushed. Its look is the
## shared explosion feedback (EventBus.explosion: burst, shake, look-gated flash, sound).
## Rank 2 `shove`: every enemy still alive within the radius is pushed SHOVE_IMPULSE away
## (~1 T on a chaser, no falloff). Rank 3 `dash_nova`: a dash sets it off now (and restarts
## the 3 s timer); the dash trigger then waits DASH_WAIT seconds. A rank-up rebuilds the node
## (Loadout._rank_to), so both clocks restart then. Deterministic: no random stream.
## M50.4a (Auto depth, the deep curve): rank 6 `shockwave`: each blast also sends a ring from
## its radius out to RING_TO tiles over ShockwaveRing.SECONDS of game time, hitting each enemy
## it passes once for RING_MULT x the damage (at most ShockwaveRing.MAX_ALIVE rings at once).
## reconfigure(w) re-reads the numbers (a boost) and keeps both clocks.
## M50.4c2 (Auto depth design 5): the Supernova runs on this node too. Its `supernova` trait
## sets ring_to (6 T), ring_mult (0.75) and shove_impulse (1.5 T); evolving keeps nova's clocks
## (Loadout.evolve: clocks() then keep_clocks(), the next blast never past the new period).

const SHOVE_IMPULSE := 610.0   ## calibrated in test_auto_scale: a chaser moves ~1 T
const DASH_WAIT := 3.0
const BODY_MARGIN := 12.0      ## as Explosion's: enemies count from their edge
const RING_TO := 4.0           ## M50.4a: the shockwave's reach, tiles
const RING_MULT := 0.5
const ShockwaveRing := preload("res://weapons/traits/shockwave_ring.gd")

var weapon_id: StringName = &"nova"
var cooldown := 3.0
var radius := 1.5 * Tuning.TILE
var damage := 3.0
var shove := false
var dash_nova := false
var shockwave := false  ## M50.4a: set by the shockwave trait
var ring_to := RING_TO              ## M50.4c2: tiles (the supernova trait: 6)
var ring_mult := RING_MULT          ## M50.4c2: the ring's share of the damage (supernova: 0.75)
var shove_impulse := SHOVE_IMPULSE  ## M50.4c2: the shove (supernova: 1.5 T)
var rings := 0          ## tests: shockwave rings sent
var novas := 0          ## tests: blasts
var dash_novas := 0     ## tests: blasts a dash set off
var _left := 3.0
var _dash_ready_at := -1.0


## Takes the weapon's numbers at its rank (Loadout._attach, before the traits).
func configure(w: Weapon) -> void:
	weapon_id = w.def.id
	cooldown = float(w.value(&"cooldown"))
	radius = float(w.value(&"blast_radius")) * Tuning.TILE
	damage = float(w.value(&"damage"))
	_left = cooldown


## M50.4a: the weapon's numbers again (a boost or an item), the clocks kept: the next blast
## never moves past the new period.
func reconfigure(w: Weapon) -> void:
	cooldown = float(w.value(&"cooldown"))
	radius = float(w.value(&"blast_radius")) * Tuning.TILE
	damage = float(w.value(&"damage"))
	_left = minf(_left, cooldown)


## M50.4c2: the clocks, to carry over an evolution ([blast left, dash ready at]).
func clocks() -> Array:
	return [_left, _dash_ready_at]


## M50.4c2: an evolution keeps the base's clocks: the next blast never past the new period.
func keep_clocks(c: Array) -> void:
	_left = minf(float(c[0]), cooldown)
	_dash_ready_at = float(c[1])


func _ready() -> void:
	EventBus.player_dashed.connect(_on_dashed)


func _exit_tree() -> void:
	if EventBus.player_dashed.is_connected(_on_dashed):
		EventBus.player_dashed.disconnect(_on_dashed)


func _physics_process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0001:
		go_off()


func source() -> StringName:
	return StringName("weapon:%s" % weapon_id)


## One blast now; the timer starts over.
func go_off() -> void:
	_left = cooldown
	var host := get_parent() as Node2D
	if host == null:
		return
	var pos := host.global_position
	var inside := _inside(pos) if shockwave else []
	Explosion.blast(pos, radius, damage, 0.0, &"blast", source(), false)
	novas += 1
	if shove:
		_shove(pos)
	if shockwave:
		_ring(pos, inside)


## M50.4a: the enemies the blast itself reaches (the ring skips them, even once shoved out).
func _inside(pos: Vector2) -> Array:
	var out := []
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := e as Node2D
		if enemy != null and (enemy.global_position - pos).length() <= radius + BODY_MARGIN:
			out.append(enemy)
	return out


func _ring(pos: Vector2, skip: Array) -> void:
	if not is_instance_valid(RunState.world):
		return
	if get_tree().get_nodes_in_group(ShockwaveRing.GROUP).size() >= ShockwaveRing.MAX_ALIVE:
		return
	var ring: Node2D = ShockwaveRing.new()
	ring.position = pos
	ring.set(&"from_r", radius)
	ring.set(&"to_r", ring_to * Tuning.TILE)
	ring.set(&"damage", damage * ring_mult)
	ring.set(&"source", source())
	ring.call(&"skip", skip)
	ring.add_to_group(ShockwaveRing.GROUP)
	RunState.world.add_child(ring)
	rings += 1


func _shove(pos: Vector2) -> void:
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := e as Node2D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		var away := enemy.global_position - pos
		if away.length() > radius + BODY_MARGIN:
			continue
		var health := Component.find(enemy, Health) as Health
		if health != null and health.dead:
			continue
		var mover := Component.find(enemy, Mover) as Mover
		if mover != null:
			mover.knockback((away.normalized() if away.length() > 1.0 else Vector2.UP) * shove_impulse)


func _on_dashed() -> void:
	if not dash_nova or RunState.game_time < _dash_ready_at:
		return
	_dash_ready_at = RunState.game_time + DASH_WAIT
	dash_novas += 1
	go_off()
