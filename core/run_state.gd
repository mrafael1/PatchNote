extends Node
## Autoload "RunState" (PLAN 2.5). Owns the patch stack and everything derived from it.
##
## rules is always base_rules + the big patch's apply_rules (if any) + each AI patch's
## + each stacked patch's, in that layer order. Nothing else writes a rule.
##
## Small patches live in `stack` and can be reverted. A big patch (PLAN v3 1.2) lives
## alone in `big`: it is never reverted, only replaced through swap_big(), and only
## reset() empties the slot. AI-tier patches (PLAN v4 1.2: mediums and boss-only) live
## in `ai`, added and removed by a stage or the boss. This node is also the single
## owner of pausing, of Engine.time_scale, and of the one path by which entities enter
## the world.

const BASE_RULES_PATH := "res://core/base_rules.tres"
const MIN_TIME_SCALE := 0.05
const HIT_STOP := &"hit_stop"   ## the look's time factor (PLAN v5 1.7); not a slow-motion cue

var base_rules: WorldRules
var rules: WorldRules
var stack: Array[Mutation] = []
var big: Mutation             ## the big slot (PLAN v3 1.2); null = base gameplay
var ai: Array[Mutation] = []  ## the AI layer (PLAN v4 1.2): live AI-tier patches, in add order
var ai_owner := {}            ## AI patch id -> &"stage" or &"boss"
var patch_state := {}

var genre: StringName         ## the run's genre (PLAN v5 1.1); set by reset(), never during a run
var run_seed := 0
var director_rng := RandomNumberGenerator.new()
var gameplay_rng := RandomNumberGenerator.new()

var game_time := 0.0          ## unpaused, time-scaled seconds since the run started
var real_frames := 0          ## physics frames since the run started, pauses included (telemetry)
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
var _time_factors := {}       ## owner -> time scale factor (PLAN v5 1.4): B1, hit stop


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	base_rules = load(BASE_RULES_PATH)
	EventBus.entity_damaged.connect(_on_entity_damaged)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	reset(0)


func _physics_process(delta: float) -> void:
	real_frames += 1
	if not get_tree().paused:
		game_time += delta
	_update_time_scale()


# --- Patch stack -----------------------------------------------------------

## Small patches in the stack, the big patch in its slot, and the AI layer.
func has_patch(id: StringName) -> bool:
	if big != null and big.id == id:
		return true
	for m in stack:
		if m.id == id:
			return true
	for m in ai:
		if m.id == id:
			return true
	return false


## Small patches only: a big patch goes through swap_big(), an AI-tier one through
## add_ai(). Requires are met only by the stack or the big slot (an AI patch can go
## without its dependents seeing it, PLAN v4 1.1). Conflicts are checked against the
## stack, the AI layer and the big slot.
func can_apply(m: Mutation) -> bool:
	if m == null or m.is_big or m.is_ai_tier() or has_patch(m.id):
		return false
	for req in m.requires:
		if not (big != null and big.id == req) and not _has_id(stack, req):
			return false
	for other in stack + ai:
		if conflicting(m, other):
			return false
	return big == null or not conflicting(m, big)


func _has_id(patches: Array[Mutation], id: StringName) -> bool:
	for m in patches:
		if m.id == id:
			return true
	return false


## True when either patch lists the other in its conflicts.
func conflicting(a: Mutation, b: Mutation) -> bool:
	return b.id in a.conflicts or a.id in b.conflicts


## force skips the requires/conflicts check (debug console only). Never takes a big
## or an AI-tier patch.
func apply(m: Mutation, force := false) -> bool:
	if m == null or m.is_big or m.is_ai_tier() or has_patch(m.id):
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
## patches that require the old big patch, and those that conflict with m (with
## everything that depends on them, PLAN v3 3b.6), are dropped first, at no rollback
## cost. AI patches that conflict with m go too, with their AI dependents (logged as
## ai_remove, reason dropped, PLAN v4 1.2). Returns the dropped small patches,
## dependents before what they depend on. One call is one build. Refuses null, a small
## patch, and the patch already in the slot (empty list, nothing changes).
func swap_big(m: Mutation) -> Array[Mutation]:
	if m == null or not m.is_big or m == big:
		return [] as Array[Mutation]
	var old := big
	var dropped := swap_drops(m)
	var ai_dropped := ai_swap_drops(m)
	for x in dropped:
		_remove(x)
	for x in ai_dropped:
		_remove_ai(x)
	if old != null:
		_strip(old)
	big = m
	recompute()
	m.enable()
	for e in live_entities():
		m.on_entity_spawned(e)
	build_number += 1
	if not ai_dropped.is_empty():
		_log_ai_remove(ai_dropped, &"dropped")
	var dropped_ids: Array[String] = []
	for x in dropped:
		dropped_ids.append(String(x.id))
	log_event(&"big_swap", {"from": String(old.id) if old else "", "to": String(m.id), "dropped": dropped_ids})
	for x in ai_dropped:
		EventBus.ai_patch_removed.emit(x, &"dropped")
	EventBus.big_swapped.emit(old, m, dropped)
	return dropped


## Pure: the small patches swap_big(m) would drop, in the order it returns them.
func swap_drops(m: Mutation) -> Array[Mutation]:
	var dropped: Array[Mutation] = []
	if m == null or not m.is_big or m == big:
		return dropped
	if big != null:
		dropped = dependents_of(big)
	for x in stack:
		if not conflicting(x, m):
			continue
		for d in dependents_of(x):
			if not dropped.has(d):
				dropped.append(d)
		if not dropped.has(x):
			dropped.append(x)
	return dropped


## Pure: the AI patches swap_big(m) would drop (those that conflict with m, with
## their AI dependents), latest first.
func ai_swap_drops(m: Mutation) -> Array[Mutation]:
	var hit: Array[Mutation] = []
	if m == null or not m.is_big or m == big:
		return hit
	for x in ai:
		if conflicting(x, m):
			hit.append(x)
	return _ai_closure(hit)


func recompute() -> void:
	rules = preview_rules(stack)
	_update_time_scale()
	EventBus.rules_changed.emit(rules)


## The rules a given small stack would produce under a big patch and an AI layer (by
## default the live ones), without touching the current state. Layer order: base,
## big, AI, stack.
func preview_rules(patches: Array[Mutation], with_big: Mutation = big,
		with_ai: Array[Mutation] = ai) -> WorldRules:
	var r := base_rules.duplicate() as WorldRules
	if with_big != null:
		with_big.apply_rules(r)
	for m in with_ai:
		m.apply_rules(r)
	for m in patches:
		m.apply_rules(r)
	return r


# --- AI layer (PLAN v4 1.2) --------------------------------------------------

## m is AI-tier and not live, its requires are met by the AI layer (as in
## can_add_ai_list), and it conflicts with nothing live.
func can_add_ai(m: Mutation) -> bool:
	if m == null or not m.is_ai_tier() or has_patch(m.id):
		return false
	for req in m.requires:
		if not _has_id(ai, req):
			return false
	if big != null and conflicting(m, big):
		return false
	for other in stack + ai:
		if conflicting(m, other):
			return false
	return true


## Pure: could `ids` be added in order to an empty AI layer over with_big and
## with_stack (Mutations; an untyped array is fine)? Each one's requires must be met
## by an earlier id in the list. Never reads the live AI layer. An unknown id or one
## that is not AI-tier is illegal.
func can_add_ai_list(ids: Array, with_big: Mutation = null, with_stack: Array = []) -> bool:
	var layer: Array[Mutation] = []
	var layer_ids: Array[StringName] = []
	for raw: Variant in ids:
		var id := StringName(raw)
		var m := MutationDB.get_mutation(id)
		if m == null or not m.is_ai_tier() or id in layer_ids:
			return false
		for req in m.requires:
			if not req in layer_ids:
				return false
		if with_big != null and conflicting(m, with_big):
			return false
		for other in with_stack + layer:
			if conflicting(m, other):
				return false
		layer.append(m)
		layer_ids.append(id)
	return true


## Adds AI-tier patch m for owner_id (&"stage" or &"boss"). force skips the requires
## and conflicts check (debug console only). One call is one build.
func add_ai(m: Mutation, owner_id: StringName, force := false) -> bool:
	if m == null or not m.is_ai_tier() or has_patch(m.id):
		return false
	if not force and not can_add_ai(m):
		return false
	ai.append(m)
	ai_owner[m.id] = owner_id
	recompute()
	m.enable()
	for e in live_entities():
		m.on_entity_spawned(e)
	build_number += 1
	log_event(&"ai_apply", {"id": m.id, "owner": owner_id})
	EventBus.ai_patch_added.emit(m, owner_id)
	return true


## AI patches that (directly or indirectly) require m, latest first. Excludes m.
## Scans only the AI layer.
func ai_dependents_of(m: Mutation) -> Array[Mutation]:
	var found := _ai_closure([m] as Array[Mutation])
	found.erase(m)
	return found


## Removes m and its AI dependents, latest first. reason: &"rollback", &"expired",
## &"dropped", or &"console" (the F2 console: no charge, not a rollback). Returns what
## was removed. One call is one build; m not in the layer changes nothing.
func remove_ai(m: Mutation, reason: StringName) -> Array[Mutation]:
	if m == null or not ai.has(m):
		return [] as Array[Mutation]
	return _drop_ai(_ai_closure([m] as Array[Mutation]), reason)


## Removes every AI patch of owner_id (with their AI dependents), reason expired, as
## one build. Returns what was removed.
func expire_ai(owner_id: StringName) -> Array[Mutation]:
	var hit: Array[Mutation] = []
	for x in ai:
		if ai_owner.get(x.id) == owner_id:
			hit.append(x)
	if hit.is_empty():
		return hit
	return _drop_ai(_ai_closure(hit), &"expired")


## The patches of `roots` that are in the layer, plus every AI patch that requires one
## of them, transitively. Latest first.
func _ai_closure(roots: Array[Mutation]) -> Array[Mutation]:
	var ids: Array[StringName] = []
	var found: Array[Mutation] = []
	for x in roots:
		ids.append(x.id)
		if ai.has(x):
			found.append(x)
	var grew := true
	while grew:
		grew = false
		for x in ai:
			if found.has(x):
				continue
			for req in x.requires:
				if req in ids:
					found.append(x)
					ids.append(x.id)
					grew = true
					break
	var ordered: Array[Mutation] = []
	for i in range(ai.size() - 1, -1, -1):
		if found.has(ai[i]):
			ordered.append(ai[i])
	return ordered


func _drop_ai(going: Array[Mutation], reason: StringName) -> Array[Mutation]:
	for x in going:
		_remove_ai(x)
	recompute()
	build_number += 1
	_log_ai_remove(going, reason)
	for x in going:
		EventBus.ai_patch_removed.emit(x, reason)
	return going


func _remove_ai(m: Mutation) -> void:
	ai.erase(m)
	ai_owner.erase(m.id)
	_strip(m)


func _log_ai_remove(going: Array[Mutation], reason: StringName) -> void:
	var ids: Array[String] = []
	for x in going:
		ids.append(String(x.id))
	log_event(&"ai_remove", {"ids": ids, "reason": reason})


## The product of every live time factor (B1's motion, hit stop): 1 when none is set.
## RunState multiplies it into the time scale. The slow-motion cues read
## felt_time_scale() instead, which leaves hit stop out.
func motion_factor() -> float:
	var f := 1.0
	for v: float in _time_factors.values():
		f *= v
	return f


## A patch or a presentation effect scales time by f until it clears it (PLAN v5 1.4).
## RunState stays the only writer of Engine.time_scale; it applies the product next tick.
func set_time_factor(owner_id: StringName, f: float) -> void:
	if is_equal_approx(f, 1.0):
		_time_factors.erase(owner_id)
	else:
		_time_factors[owner_id] = f


func clear_time_factor(owner_id: StringName) -> void:
	_time_factors.erase(owner_id)


func has_time_factor(owner_id: StringName) -> bool:
	return _time_factors.has(owner_id)


## The time scale the rules and patches set, without hit stop: what the slow-motion
## cues (TimeTint, Sound's pitch) read, so a hit stop never looks or sounds like B1.
func felt_time_scale() -> float:
	var f := rules.time_scale
	for id: StringName in _time_factors:
		if id != HIT_STOP:
			f *= float(_time_factors[id])
	return maxf(f, MIN_TIME_SCALE)


## RunState is the only writer of Engine.time_scale: rules x time factors, every tick.
func _update_time_scale() -> void:
	var scale := maxf(rules.time_scale * motion_factor(), MIN_TIME_SCALE)
	if not is_equal_approx(Engine.time_scale, scale):
		Engine.time_scale = scale


## Enemies deal no damage to the player for `seconds` of game time.
func start_grace(seconds: float) -> void:
	_grace_until = maxf(_grace_until, game_time + seconds)


func in_grace() -> bool:
	return game_time < _grace_until


## Back to a clean run. "New build" and every test start here. An empty or unknown
## genre means the default one (the first Playable genre in GenreDB).
func reset(new_seed: int, new_genre: StringName = &"") -> void:
	for i in range(stack.size() - 1, -1, -1):
		_remove(stack[i])
	for i in range(ai.size() - 1, -1, -1):
		_remove_ai(ai[i])
	ai_owner.clear()
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
	real_frames = 0
	invincible = false
	run_seed = new_seed
	genre = new_genre if GenreDB.get_genre(new_genre) != null else GenreDB.default_id()
	director_rng.seed = hash([new_seed, "director"])
	gameplay_rng.seed = hash([new_seed, "gameplay"])
	_pending.clear()
	_grace_until = -1.0
	_time_factors.clear()
	_pause_reasons.clear()
	get_tree().paused = false
	recompute()


## Seconds of play the player sat through, pauses included: physics frames at the
## project tick rate. Under B1 and B2 this runs ahead of game_time.
func real_time() -> float:
	return real_frames / float(Engine.physics_ticks_per_second)


func version_label() -> String:
	return "v0.%d" % build_number


func _remove(m: Mutation) -> void:
	stack.erase(m)
	_strip(m)


## Takes everything class B of m out of the world: listeners, state, components.
func _strip(m: Mutation) -> void:
	m.disable()
	patch_state.erase(m.id)
	_time_factors.erase(m.id)
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
	for m in ai:
		m.on_entity_spawned(entity)
	for m in stack:
		m.on_entity_spawned(entity)
	EventBus.entity_spawned.emit(entity)


## The one way to add an entity at runtime. Returns null when a hard cap is reached.
## The node enters the tree deferred, so this is safe to call from physics callbacks.
func spawn(scene: PackedScene, pos: Vector2, params := {}) -> Node:
	if not is_instance_valid(world):
		return null
	var node := scene.instantiate()
	# params may set the kind (an enemy shot is projectile.tscn with kind enemy_projectile):
	# count it under the kind it will register with, or the pending count leaks.
	var kind_value: Variant = params.get(&"kind", node.get(&"kind"))
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

## Reasons: &"prompt", &"history", &"transition", &"report", and &"turn" (B2: the
## world waits for the player's next action). The tree is paused
## while any reason is active.
func set_pause(reason: StringName, on: bool) -> void:
	if on:
		_pause_reasons[reason] = true
	else:
		_pause_reasons.erase(reason)
	get_tree().paused = not _pause_reasons.is_empty()


func is_paused_for(reason: StringName) -> bool:
	return _pause_reasons.has(reason)


## True if anything other than `reason` pauses the tree (a panel, a transition...).
func is_paused_except(reason: StringName) -> bool:
	for r: StringName in _pause_reasons:
		if r != reason:
			return true
	return false


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

## Everything that must be a pure function of the layers: rules, patch-added
## components per entity, EventBus connections owned by mutations and their takes,
## and the AI layer's ids with their owners.
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
			elif obj is PatchTake:
				owners.append("%s/%s.%s" % [(obj as PatchTake).id, (obj as PatchTake).genre, callable.get_method()])
		owners.sort()
		if not owners.is_empty():
			connections[sig.name] = owners
	var ids: Array[String] = []
	for m in stack:
		ids.append(String(m.id))
	var ai_pairs: Array = []
	for m in ai:
		ai_pairs.append([String(m.id), String(ai_owner.get(m.id, &""))])
	return {
		"big": String(big.id) if big else "",
		"ai": ai_pairs,
		"stack": ids,
		"rules": rules.to_dict(),
		"entities": entities,
		"connections": connections,
		"time_scale": Engine.time_scale,
		"paused": get_tree().paused,
	}
