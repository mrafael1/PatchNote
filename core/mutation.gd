class_name Mutation
extends Resource
## Definition of one patch the AI can propose (PLAN 2.4).
## Loaded .tres files are shared for the life of the process, so a Mutation keeps no
## per-run data: use state() for that. The only thing it tracks is its own connections.

@export var id: StringName               ## equals the folder and file name
@export var title: String                ## card title
@export var description: String          ## one-line effect summary
@export var line_proposal: String
@export var line_applied: String
@export var line_reverted: String
@export var tags: Array[StringName] = []
@export var requires: Array[StringName] = []   ## mutation ids, all needed
@export var conflicts: Array[StringName] = []  ## mutation ids, checked both ways
@export var weight := 1.0
@export var is_mode_switch := false      ## selects the long transition presentation
## Big patch (PLAN v3 1.1): changes the genre, lives alone in RunState.big, is never
## reverted (only replaced by another big patch). Has no requires and no conflicts.
@export var is_big := false
@export var genre_label := ""            ## big patches: short name for the HUD and history
## AI tier (PLAN v4 1.1): lives in RunState.ai, never in the stack. A patch is exactly
## one of small, medium, boss-only or big.
@export var is_medium := false   ## how you move and see: a stage default the boss may also push
@export var boss_only := false   ## a boss hazard: only the boss pushes it, never a stage
@export var starter := false     ## in the first run's offer pool (read from M19 on)
@export var boss_weight := 0.0   ## > 0: the boss may push it live

var _connections: Array = []


## Lives in RunState.ai (added by a stage or the boss), never in the stack.
func is_ai_tier() -> bool:
	return is_medium or boss_only


## Pure: change rule values only.
func apply_rules(_rules: WorldRules) -> void:
	pass


## Attach components with Component.attach(entity, Script, id). Must be idempotent:
## it runs for every live entity on apply and for every entity spawned afterwards.
func on_entity_spawned(_entity: Node) -> void:
	pass


## Connect to EventBus here, only through _listen().
func enable() -> void:
	pass


## Disconnects everything _listen() recorded. Not meant to be overridden.
func disable() -> void:
	for c: Array in _connections:
		var sig: Signal = c[0]
		var method: Callable = c[1]
		if sig.is_connected(method):
			sig.disconnect(method)
	_connections.clear()


## Connect one of this mutation's own methods to a signal. No lambdas.
func _listen(sig: Signal, method: Callable) -> void:
	assert(method.get_object() == self, "Mutation %s: _listen() takes its own methods only" % id)
	if sig.is_connected(method):
		return
	sig.connect(method)
	_connections.append([sig, method])


## Per-run scratch data for this patch. Cleared on revert and on reset.
func state() -> Dictionary:
	if not RunState.patch_state.has(id):
		RunState.patch_state[id] = {}
	return RunState.patch_state[id]
