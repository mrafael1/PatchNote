extends Node
## Autoload "RunState" (PLAN 2.5). Owns the patch stack and everything derived from it.
##
## rules is always base_rules + each stacked patch's apply_rules, in order. Nothing
## else writes a rule. This node is also the single owner of pausing, of
## Engine.time_scale, and of the one path by which entities enter the world.

const BASE_RULES_PATH := "res://core/base_rules.tres"
const MIN_TIME_SCALE := 0.05

var base_rules: WorldRules
var rules: WorldRules
var stack: Array[Mutation] = []
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	base_rules = load(BASE_RULES_PATH)
	EventBus.entity_damaged.connect(_on_entity_damaged)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	reset(0)


func _physics_process(delta: float) -> void:
	if not get_tree().paused:
		game_time += delta


# --- Patch stack -----------------------------------------------------------

func has_patch(id: StringName) -> bool:
	for m in stack:
		if m.id == id:
			return true
	return false


func can_apply(m: Mutation) -> bool:
	if m == null or has_patch(m.id):
		return false
	for req in m.requires:
		if not has_patch(req):
			return false
	for other in stack:
		if other.id in m.conflicts or m.id in other.conflicts:
			return false
	return true


## force skips the requires/conflicts check (debug console only).
func apply(m: Mutation, force := false) -> bool:
	if m == null or has_patch(m.id):
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
## dependents first. One call is one build.
func revert(m: Mutation) -> Array[Mutation]:
	var removed: Array[Mutation] = []
	if m == null or not stack.has(m):
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


## Patches that (directly or indirectly) require m, latest first. Excludes m.
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


func recompute() -> void:
	rules = base_rules.duplicate() as WorldRules
	for m in stack:
		m.apply_rules(rules)
	Engine.time_scale = maxf(rules.time_scale, MIN_TIME_SCALE)
	EventBus.rules_changed.emit(rules)


## The rules a given stack would produce, without touching the current state.
func preview_rules(patches: Array[Mutation]) -> WorldRules:
	var r := base_rules.duplicate() as WorldRules
	for m in patches:
		m.apply_rules(r)
	return r


## Enemies deal no damage to the player for `seconds` of game time.
func start_grace(seconds: float) -> void:
	_grace_until = maxf(_grace_until, game_time + seconds)


func in_grace() -> bool:
	return game_time < _grace_until


## Back to a clean run. "New build" and every test start here.
func reset(new_seed: int) -> void:
	for i in range(stack.size() - 1, -1, -1):
		_remove(stack[i])
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
	_pause_reasons.clear()
	get_tree().paused = false
	recompute()


func version_label() -> String:
	return "v0.%d" % build_number


func _remove(m: Mutation) -> void:
	stack.erase(m)
	m.disable()
	patch_state.erase(m.id)
	for e in live_entities():
		for c in e.get_children():
			if c is Component and c.source_patch == m.id:
				# remove_child first so the component is gone immediately, not at frame end.
				e.remove_child(c)
				c.queue_free()


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
		"stack": ids,
		"rules": rules.to_dict(),
		"entities": entities,
		"connections": connections,
		"time_scale": Engine.time_scale,
		"paused": get_tree().paused,
	}
