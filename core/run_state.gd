extends Node
## Autoload "RunState" (PLAN 2.5). Owns the patch stack and everything derived from it.
##
## rules is always base_rules + the big patch's apply_rules (if any) + each stacked
## patch's apply_rules, in order. Nothing else writes a rule.
##
## Small patches live in `stack` and can be reverted. A big patch (PLAN v3 1.2) lives
## alone in `big`: it is never reverted, only replaced through swap_big(), and only
## reset() empties the slot. This node is also the single owner of pausing, of
## Engine.time_scale, and of the one path by which entities enter the world.

const BASE_RULES_PATH := "res://core/base_rules.tres"
const MIN_TIME_SCALE := 0.05

var base_rules: WorldRules
var rules: WorldRules
var stack: Array[Mutation] = []
var big: Mutation             ## the big slot (PLAN v3 1.2); null = base gameplay
var patch_state := {}

var run_seed := 0
var director_rng := RandomNumberGenerator.new()
var gameplay_rng := RandomNumberGenerator.new()

var game_time := 0.0          ## unpaused, time-scaled seconds since the run started
var build_number := 1         ## monotonic: every apply or revert is a new build
var run_log: Array[Dictionary] = []
var kills := 0
var kills_by_source := {}
var damage_by_source := {}

var world: Node               ## container that spawned entities are added to
var invincible := false       ## debug (F3): the player takes no damage

var _grace_until := -1.0       ## game time until which enemies deal no damage
var _pause_reasons := {}
var _pending := {}            ## kind -> spawns requested but not yet in the tree
var _motion := 1.0            ## smoothed motion factor (B1)
var _pulse_left := 0.0        ## real seconds the motion factor stays at 1 after a shot or dash


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	base_rules = load(BASE_RULES_PATH)
	EventBus.entity_damaged.connect(_on_entity_damaged)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.projectile_fired.connect(_on_projectile_fired)
	EventBus.player_dashed.connect(_on_player_dashed)
	reset(0)


func _physics_process(delta: float) -> void:
	if not get_tree().paused:
		game_time += delta
	# The physics delta is scaled; motion smoothing runs on real time.
	_step_motion(delta / maxf(Engine.time_scale, 0.001))
	_update_time_scale()


# --- Patch stack -----------------------------------------------------------

## Small patches in the stack, and the big patch in its slot.
func has_patch(id: StringName) -> bool:
	if big != null and big.id == id:
		return true
	for m in stack:
		if m.id == id:
			return true
	return false


## Small patches only: a big patch goes through swap_big().
func can_apply(m: Mutation) -> bool:
	if m == null or m.is_big or has_patch(m.id):
		return false
	for req in m.requires:
		if not has_patch(req):
			return false
	for other in stack:
		if other.id in m.conflicts or m.id in other.conflicts:
			return false
	return true


## force skips the requires/conflicts check (debug console only). Never takes a big patch.
func apply(m: Mutation, force := false) -> bool:
	if m == null or m.is_big or has_patch(m.id):
		return false
	if not force and not can_apply(m):
		return false
	stack.append(m)
	recompute()
	m.enable()
	for e in live_entities():
		m.on_entity_spawned(e)
	build_number += 1
	_log(&"apply", m.id)
	EventBus.patch_applied.emit(m)
	return true


## Reverts m and every patch that depends on it. Returns what was removed,
## dependents first. One call is one build. A big patch is never reverted: it
## returns an empty list and changes nothing.
func revert(m: Mutation) -> Array[Mutation]:
	var removed: Array[Mutation] = []
	if m == null or m.is_big or not stack.has(m):
		return removed
	removed = dependents_of(m)
	removed.append(m)
	for x in removed:
		_remove(x)
	recompute()
	build_number += 1
	for x in removed:
		_log(&"revert", x.id)
		EventBus.patch_reverted.emit(x)
	return removed


## Small patches that (directly or indirectly) require m, latest first. Excludes m.
## m may be the big patch.
func dependents_of(m: Mutation) -> Array[Mutation]:
	var ids: Array[StringName] = [m.id]
	var found: Array[Mutation] = []
	var grew := true
	while grew:
		grew = false
		for x in stack:
			if x == m or found.has(x):
				continue
			for req in x.requires:
				if req in ids:
					found.append(x)
					ids.append(x.id)
					grew = true
					break
	var ordered: Array[Mutation] = []
	for i in range(stack.size() - 1, -1, -1):
		if found.has(stack[i]):
			ordered.append(stack[i])
	return ordered


## Puts m in the big slot (PLAN v3 1.2), replacing the big patch there. Small
## patches that require the old big patch are dropped first, at no rollback cost.
## Returns the dropped patches, latest first. One call is one build. Refuses null,
## a small patch, and the patch already in the slot (empty list, nothing changes).
func swap_big(m: Mutation) -> Array[Mutation]:
	var dropped: Array[Mutation] = []
	if m == null or not m.is_big or m == big:
		return dropped
	var old := big
	if old != null:
		dropped = dependents_of(old)
		for x in dropped:
			_remove(x)
		_strip(old)
	big = m
	recompute()
	m.enable()
	for e in live_entities():
		m.on_entity_spawned(e)
	build_number += 1
	var dropped_ids: Array[String] = []
	for x in dropped:
		dropped_ids.append(String(x.id))
	log_event(&"big_swap", {"from": String(old.id) if old else "", "to": String(m.id), "dropped": dropped_ids})
	EventBus.big_swapped.emit(old, m, dropped)
	return dropped


func recompute() -> void:
	rules = preview_rules(stack)
	_update_time_scale()
	EventBus.rules_changed.emit(rules)


## The rules a given small stack would produce under a big patch (by default the one
## in the slot), without touching the current state.
func preview_rules(patches: Array[Mutation], with_big: Mutation = big) -> WorldRules:
	var r := base_rules.duplicate() as WorldRules
	if with_big != null:
		with_big.apply_rules(r)
	for m in patches:
		m.apply_rules(r)
	return r


## How much the player's motion scales time (PLAN v3 1.4). 1 unless a big patch turns
## time_follows_motion on (B1); then a smoothed value between idle_time_scale and 1.
func motion_factor() -> float:
	return _motion if rules.time_follows_motion else 1.0


## What the motion factor is heading for right now (PLAN v3 section 2). Full speed
## (or a held direction, so time starts the moment the player decides to move) runs
## time at 1; standing still runs it at idle_time_scale. A pause, a dead or missing
## player, and the pulse after a shot or dash all give 1.
func motion_target() -> float:
	if not rules.time_follows_motion or get_tree().paused or _pulse_left > 0.0:
		return 1.0
	var player := get_tree().get_first_node_in_group(&"player") as CharacterBody2D
	if player == null or not is_instance_valid(player):
		return 1.0
	var health := Component.find(player, Health) as Health
	if health and health.dead:
		return 1.0
	var amount := player.velocity.length() / maxf(Tuning.player_speed, 1.0)
	var input := player.get(&"input") as PlayerInput
	if input:
		amount = maxf(amount, input.move.length())
	return lerpf(rules.idle_time_scale, 1.0, clampf(amount, 0.0, 1.0))


func _step_motion(real_delta: float) -> void:
	_pulse_left = maxf(0.0, _pulse_left - real_delta)
	var target := motion_target()
	if target >= 1.0:
		_motion = 1.0   # full speed, a pause or a pulse: time runs at once, no ramp
	else:
		_motion = lerpf(_motion, target, 1.0 - exp(-real_delta / Tuning.motion_smoothing))


func _on_projectile_fired(projectile: Node) -> void:
	if rules.time_follows_motion and projectile.get(&"faction") == &"player":
		_pulse_left = Tuning.motion_pulse


func _on_player_dashed() -> void:
	if rules.time_follows_motion:
		_pulse_left = Tuning.motion_pulse


## RunState is the only writer of Engine.time_scale: rules x motion, every tick.
func _update_time_scale() -> void:
	var scale := maxf(rules.time_scale * motion_factor(), MIN_TIME_SCALE)
	if not is_equal_approx(Engine.time_scale, scale):
		Engine.time_scale = scale


## Enemies deal no damage to the player for `seconds` of game time.
func start_grace(seconds: float) -> void:
	_grace_until = maxf(_grace_until, game_time + seconds)


func in_grace() -> bool:
	return game_time < _grace_until


## Back to a clean run. "New build" and every test start here.
func reset(new_seed: int) -> void:
	for i in range(stack.size() - 1, -1, -1):
		_remove(stack[i])
	if big != null:
		_strip(big)
		big = null
	patch_state.clear()
	run_log.clear()
	kills = 0
	kills_by_source.clear()
	damage_by_source.clear()
	build_number = 1
	game_time = 0.0
	invincible = false
	run_seed = new_seed
	director_rng.seed = hash([new_seed, "director"])
	gameplay_rng.seed = hash([new_seed, "gameplay"])
	_pending.clear()
	_grace_until = -1.0
	_motion = 1.0
	_pulse_left = 0.0
	_pause_reasons.clear()
	get_tree().paused = false
	recompute()


func version_label() -> String:
	return "v0.%d" % build_number


func _remove(m: Mutation) -> void:
	stack.erase(m)
	_strip(m)


## Takes everything class B of m out of the world: listeners, state, components.
func _strip(m: Mutation) -> void:
	m.disable()
	patch_state.erase(m.id)
	for e in live_entities():
		for c in e.get_children():
			if c is Component and c.source_patch == m.id:
				# remove_child first so the component is gone immediately, not at frame end.
				e.remove_child(c)
				c.queue_free()


## Adds an entry to the run log. Game time and build are filled in.
func log_event(event: StringName, data := {}) -> void:
	var entry := {"event": event, "time": game_time, "build": build_number}
	entry.merge(data)
	run_log.append(entry)


func _log(event: StringName, id: StringName) -> void:
	run_log.append({"event": event, "id": id, "time": game_time, "build": build_number})


# --- Entities --------------------------------------------------------------

func live_entities() -> Array[Node]:
	var out: Array[Node] = []
	for e in get_tree().get_nodes_in_group(&"entities"):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			out.append(e)
	return out


func count(kind: StringName) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group(kind):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			n += 1
	return n


## Every entity calls this from _ready. Kinds: player, enemy, player_projectile,
## enemy_projectile.
func register_entity(entity: Node, kind: StringName) -> void:
	entity.add_to_group(&"entities")
	entity.add_to_group(kind)
	if entity.has_meta(&"via_spawn"):
		_pending[kind] = maxi(0, int(_pending.get(kind, 0)) - 1)
	if big != null:
		big.on_entity_spawned(entity)
	for m in stack:
		m.on_entity_spawned(entity)
	EventBus.entity_spawned.emit(entity)


## The one way to add an entity at runtime. Returns null when a hard cap is reached.
## The node enters the tree deferred, so this is safe to call from physics callbacks.
func spawn(scene: PackedScene, pos: Vector2, params := {}) -> Node:
	if not is_instance_valid(world):
		return null
	var node := scene.instantiate()
	var kind_value: Variant = node.get(&"kind")
	var kind: StringName = kind_value if kind_value != null else &""
	if not _under_cap(kind):
		node.free()
		return null
	for key: StringName in params:
		node.set(key, params[key])
	if node is Node2D:
		(node as Node2D).position = pos
	node.set_meta(&"via_spawn", true)
	_pending[kind] = int(_pending.get(kind, 0)) + 1
	world.add_child.call_deferred(node)
	return node


func _under_cap(kind: StringName) -> bool:
	if kind == &"enemy":
		return count(&"enemy") + int(_pending.get(&"enemy", 0)) < Tuning.hard_max_enemies
	if kind == &"player_projectile" or kind == &"enemy_projectile":
		var n := count(&"player_projectile") + count(&"enemy_projectile")
		n += int(_pending.get(&"player_projectile", 0)) + int(_pending.get(&"enemy_projectile", 0))
		return n < Tuning.hard_max_projectiles
	return true


# --- Pause -----------------------------------------------------------------

## Reasons: &"prompt", &"history", &"transition", &"report". The tree is paused
## while any reason is active.
func set_pause(reason: StringName, on: bool) -> void:
	if on:
		_pause_reasons[reason] = true
	else:
		_pause_reasons.erase(reason)
	get_tree().paused = not _pause_reasons.is_empty()


func is_paused_for(reason: StringName) -> bool:
	return _pause_reasons.has(reason)


# --- Run log ---------------------------------------------------------------

func _source_key(info: DamageInfo) -> StringName:
	return info.source_patch if info.source_patch != &"" else &"base"


func _on_entity_damaged(target: Node, info: RefCounted) -> void:
	if target.is_in_group(&"enemy"):
		var key := _source_key(info as DamageInfo)
		damage_by_source[key] = float(damage_by_source.get(key, 0.0)) + (info as DamageInfo).amount


func _on_enemy_killed(_enemy: Node, info: RefCounted) -> void:
	kills += 1
	var key := _source_key(info as DamageInfo)
	kills_by_source[key] = int(kills_by_source.get(key, 0)) + 1


# --- Invariant support -----------------------------------------------------

## Everything that must be a pure function of the stack: rules, patch-added
## components per entity, and mutation-owned EventBus connections.
func snapshot() -> Dictionary:
	var entities := {}
	for e in live_entities():
		var comps: Array[String] = []
		for c in e.get_children():
			if c is Component and c.source_patch != &"":
				var script: Script = c.get_script()
				comps.append("%s#%d@%s" % [script.resource_path, script.get_instance_id(), c.source_patch])
		comps.sort()
		entities[str(e.get_path())] = comps
	var connections := {}
	for sig: Dictionary in EventBus.get_signal_list():
		var owners: Array[String] = []
		for conn: Dictionary in EventBus.get_signal_connection_list(sig.name):
			var callable: Callable = conn.callable
			var obj := callable.get_object()
			if obj is Mutation:
				owners.append("%s.%s" % [(obj as Mutation).id, callable.get_method()])
		owners.sort()
		if not owners.is_empty():
			connections[sig.name] = owners
	var ids: Array[String] = []
	for m in stack:
		ids.append(String(m.id))
	return {
		"big": String(big.id) if big else "",
		"stack": ids,
		"rules": rules.to_dict(),
		"entities": entities,
		"connections": connections,
		"time_scale": Engine.time_scale,
		"paused": get_tree().paused,
	}
