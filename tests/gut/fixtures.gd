extends RefCounted
## Test-only mutations, components and entities. They cover every kind of patch
## (rules, component, event, dependent, conflicting) without depending on the real set.


class FxComp extends Component:
	pass


class FxEntity extends Node2D:
	var kind: StringName = &"enemy"

	func _ready() -> void:
		RunState.register_entity(self, kind)


## A PlayerInput the test drives by hand.
class ScriptedInput extends PlayerInput:
	func tap_jump() -> void:
		jump_pressed = true
		jump_held = true

	func _physics_process(_delta: float) -> void:
		# Runs before the player reads it; clear the one-tick flag after it was seen once.
		if _seen:
			jump_pressed = false
		_seen = jump_pressed

	var _seen := false


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


static func make_entity(kind: StringName, entity_name: String) -> FxEntity:
	var e := FxEntity.new()
	e.kind = kind
	e.name = entity_name
	return e
