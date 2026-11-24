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

const SHOVE_IMPULSE := 610.0   ## calibrated in test_auto_scale: a chaser moves ~1 T
const DASH_WAIT := 3.0
const BODY_MARGIN := 12.0      ## as Explosion's: enemies count from their edge

var weapon_id: StringName = &"nova"
var cooldown := 3.0
var radius := 1.5 * Tuning.TILE
var damage := 3.0
var shove := false
var dash_nova := false
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
	Explosion.blast(pos, radius, damage, 0.0, &"blast", source(), false)
	novas += 1
	if shove:
		_shove(pos)


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
			mover.knockback((away.normalized() if away.length() > 1.0 else Vector2.UP) * SHOVE_IMPULSE)


func _on_dashed() -> void:
	if not dash_nova or RunState.game_time < _dash_ready_at:
		return
	_dash_ready_at = RunState.game_time + DASH_WAIT
	dash_novas += 1
	go_off()
