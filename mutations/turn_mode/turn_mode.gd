extends Mutation
## Big patch B2 (PLAN v3 sections 3 and 3b): the world only runs when the player acts,
## and everything hostile lives on the grid. The TurnClock reads the rule and owns the
## turn; this patch puts enemies and their shots on tiles (GridActor) and plays their
## side of every turn (TurnLogic), listening to the clock's two signals.

const GridActor := preload("res://mutations/turn_mode/grid_actor.gd")
const TurnLogic := preload("res://mutations/turn_mode/turn_logic.gd")

@export var turn_duration := 0.25   ## game seconds the world runs per player action


func apply_rules(rules: WorldRules) -> void:
	rules.turn_based = true
	rules.turn_duration = turn_duration   # assigned: only the big patch in the slot owns it


func enable() -> void:
	_listen(EventBus.turn_started, _on_turn_started)
	_listen(EventBus.turn_ended, _on_turn_ended)


## Enemies join the grid (the player has already snapped: the clock enters on the rule
## change, before this runs). An enemy shot without a GridActor was in flight before B2
## and is removed: every shot on the grid comes from a grid shooter.
func on_entity_spawned(entity: Node) -> void:
	if Component.find(entity, GridActor) != null:
		return
	if entity.is_in_group(&"enemy_projectile"):
		entity.set_physics_process(false)
		entity.queue_free()
		RunState.log_event(&"enemy_shot_removed", {"reason": "turn_based"})
		return
	if not entity.is_in_group(&"enemy"):
		return
	var a := Component.attach(entity, GridActor, id) as GridActor
	a.role = _role(entity)
	a.order = TurnLogic.next_order(state())
	TurnLogic.join(a, TurnClock.current())


func _role(entity: Node) -> StringName:
	if Component.find(entity, Shooter) != null:
		return GridActor.SHOOTER
	return GridActor.TANK if entity.get(&"archetype") == &"tank" else GridActor.CHASER


func _on_turn_started(_number: int) -> void:
	var clock := TurnClock.current()
	if clock and clock.active:
		TurnLogic.plan(clock, self)


func _on_turn_ended(number: int) -> void:
	var clock := TurnClock.current()
	if clock and clock.active:
		TurnLogic.resolve(clock, self, number)
