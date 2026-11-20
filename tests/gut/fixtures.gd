extends RefCounted
## Test-only mutations, components and entities. They cover every kind of patch
## (rules, component, event, dependent, conflicting) without depending on the real set.


class FxComp extends Component:
	pass


class FxEntity extends Node2D:
	var kind: StringName = &"enemy"

	func _ready() -> void:
		RunState.register_entity(self, kind)


## A PlayerInput the test drives by hand. tap_*() presses for exactly one physics tick.
class ScriptedInput extends PlayerInput:
	var _jump_seen := false
	var _dash_seen := false
	var _wait_seen := false

	func tap_jump() -> void:
		jump_pressed = true
		jump_held = true

	func tap_dash() -> void:
		dash_pressed = true

	func tap_wait() -> void:
		wait_pressed = true

	func _physics_process(_delta: float) -> void:
		# Runs before the player reads the flags; clear each once it has been seen.
		if _jump_seen:
			jump_pressed = false
		_jump_seen = jump_pressed
		if _dash_seen:
			dash_pressed = false
		_dash_seen = dash_pressed
		if _wait_seen:
			wait_pressed = false
		_wait_seen = wait_pressed


class FxBounce extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.projectile_max_bounces += 2


class FxArc extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.projectile_gravity_scale += 0.5


class FxExtraJump extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.jumps += 1


class FxFlipGravity extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.gravity_dir = -r.gravity_dir


class FxRules extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.spawn_rate_mult *= 2.0
		r.max_enemies += 5


class FxComponent extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.projectile_max_bounces += 1

	func on_entity_spawned(e: Node) -> void:
		if e.is_in_group(&"enemy"):
			Component.attach(e, FxComp, id)


class FxEvent extends Mutation:
	func enable() -> void:
		_listen(EventBus.enemy_killed, _on_killed)
		_listen(EventBus.player_dashed, _on_dashed)

	func _on_killed(_e: Node, _info: RefCounted) -> void:
		state()["kills"] = int(state().get("kills", 0)) + 1

	func _on_dashed() -> void:
		pass


class FxDependent extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.gravity_dir = -r.gravity_dir


class FxConflict extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.camera_zoom *= 0.5


class FxAll extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.enemy_hp_mult *= 0.5

	func on_entity_spawned(e: Node) -> void:
		if e.is_in_group(&"player"):
			Component.attach(e, FxComp, id)

	func enable() -> void:
		_listen(EventBus.entity_spawned, _on_spawned)

	func _on_spawned(_e: Node) -> void:
		pass


## Big patch fixtures (PLAN v3): each sets an assigned rule, adds a component and a
## listener, so a swap has something of every class B kind to strip.
class FxBigA extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.turn_duration = 0.5
		r.camera_zoom *= 0.8

	func on_entity_spawned(e: Node) -> void:
		Component.attach(e, FxComp, id)

	func enable() -> void:
		_listen(EventBus.enemy_killed, _on_killed)

	func _on_killed(_e: Node, _info: RefCounted) -> void:
		state()["kills"] = int(state().get("kills", 0)) + 1


class FxBigB extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.turn_duration = 0.1
		r.time_follows_motion = true

	func on_entity_spawned(e: Node) -> void:
		if e.is_in_group(&"player"):
			Component.attach(e, FxComp, id)

	func enable() -> void:
		_listen(EventBus.player_dashed, _on_dashed)

	func _on_dashed() -> void:
		pass


## A small patch that only makes sense under big patch A.
class FxUnderA extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.turn_duration *= 2.0

	func enable() -> void:
		_listen(EventBus.entity_spawned, _on_spawned)

	func _on_spawned(_e: Node) -> void:
		pass


## A small patch that cannot live under big patch B (as gravity cannot under B2).
class FxAgainstB extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.max_enemies += 3

	func on_entity_spawned(e: Node) -> void:
		if e.is_in_group(&"enemy"):
			Component.attach(e, FxComp, id)


## A small patch that requires fx_against_b, so a swap to B drops it too.
class FxOnAgainstB extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.max_enemies *= 2

	func enable() -> void:
		_listen(EventBus.player_dashed, _on_dashed)

	func _on_dashed() -> void:
		pass


## AI-tier fixtures (PLAN v4 1.2). fx_med_a adds to turn_duration, so the layer order
## base -> big -> AI -> stack shows in one value (under fx_big_a and fx_under_a).
class FxMedA extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.turn_duration += 0.25
		r.camera_zoom *= 1.1

	func on_entity_spawned(e: Node) -> void:
		if e.is_in_group(&"enemy"):
			Component.attach(e, FxComp, id)

	func enable() -> void:
		_listen(EventBus.enemy_killed, _on_killed)

	func _on_killed(_e: Node, _info: RefCounted) -> void:
		state()["kills"] = int(state().get("kills", 0)) + 1


## A medium that requires fx_med_a (as gravity_reversed requires gravity_on).
class FxMedOnA extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.max_enemies += 1
		r.turn_duration *= 3.0

	func enable() -> void:
		_listen(EventBus.player_dashed, _on_dashed)

	func _on_dashed() -> void:
		pass


## A medium that conflicts with fx_big_b (as gravity_on conflicts with turn_mode).
class FxMedAgainstB extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.spawn_rate_mult *= 1.5

	func on_entity_spawned(e: Node) -> void:
		if e.is_in_group(&"player"):
			Component.attach(e, FxComp, id)


## A boss-only hazard.
class FxBossHazard extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.max_enemies += 4

	func on_entity_spawned(e: Node) -> void:
		if e.is_in_group(&"enemy"):
			Component.attach(e, FxComp, id)

	func enable() -> void:
		_listen(EventBus.entity_spawned, _on_spawned)

	func _on_spawned(_e: Node) -> void:
		pass


## A small patch that conflicts with the medium fx_med_a.
class FxAgainstMed extends Mutation:
	func apply_rules(r: WorldRules) -> void:
		r.enemy_hp_mult *= 0.9

	func enable() -> void:
		_listen(EventBus.enemy_killed, _on_killed)

	func _on_killed(_e: Node, _info: RefCounted) -> void:
		pass


static func make(cls: GDScript, id: StringName, requires: Array = [], conflicts: Array = []) -> Mutation:
	var m: Mutation = cls.new()
	m.id = id
	m.title = String(id)
	m.requires.assign(requires)
	m.conflicts.assign(conflicts)
	return m


## fx_dependent requires fx_rules; fx_conflict conflicts with fx_event.
static func make_all() -> Array[Mutation]:
	var out: Array[Mutation] = []
	out.append(make(FxRules, &"fx_rules"))
	out.append(make(FxComponent, &"fx_component"))
	out.append(make(FxEvent, &"fx_event"))
	out.append(make(FxDependent, &"fx_dependent", [&"fx_rules"]))
	out.append(make(FxConflict, &"fx_conflict", [], [&"fx_event"]))
	out.append(make(FxAll, &"fx_all"))
	return out


static func make_big(cls: GDScript, id: StringName) -> Mutation:
	var m := make(cls, id)
	m.is_big = true
	m.is_mode_switch = true
	m.genre_label = String(id)
	return m


## fx_big_a and fx_big_b (big), fx_under_a (small, requires fx_big_a), fx_against_b
## (small, conflicts with fx_big_b) and fx_on_against_b (small, requires fx_against_b).
static func make_bigs() -> Array[Mutation]:
	var out: Array[Mutation] = []
	out.append(make_big(FxBigA, &"fx_big_a"))
	out.append(make_big(FxBigB, &"fx_big_b"))
	out.append(make(FxUnderA, &"fx_under_a", [&"fx_big_a"]))
	out.append(make(FxAgainstB, &"fx_against_b", [], [&"fx_big_b"]))
	out.append(make(FxOnAgainstB, &"fx_on_against_b", [&"fx_against_b"]))
	return out


static func make_medium(cls: GDScript, id: StringName, requires: Array = [], conflicts: Array = []) -> Mutation:
	var m := make(cls, id, requires, conflicts)
	m.is_medium = true
	m.boss_weight = 1.0
	return m


static func make_boss_only(cls: GDScript, id: StringName) -> Mutation:
	var m := make(cls, id)
	m.boss_only = true
	m.boss_weight = 1.0
	return m


## fx_med_a, fx_med_on_a (requires fx_med_a), fx_med_against_b (conflicts with
## fx_big_b), fx_boss_hazard (boss-only) and fx_against_med (small, conflicts with
## fx_med_a).
static func make_ai_set() -> Array[Mutation]:
	var out: Array[Mutation] = []
	out.append(make_medium(FxMedA, &"fx_med_a"))
	out.append(make_medium(FxMedOnA, &"fx_med_on_a", [&"fx_med_a"]))
	out.append(make_medium(FxMedAgainstB, &"fx_med_against_b", [], [&"fx_big_b"]))
	out.append(make_boss_only(FxBossHazard, &"fx_boss_hazard"))
	out.append(make(FxAgainstMed, &"fx_against_med", [], [&"fx_med_a"]))
	return out


static func make_entity(kind: StringName, entity_name: String) -> FxEntity:
	var e := FxEntity.new()
	e.kind = kind
	e.name = entity_name
	return e
