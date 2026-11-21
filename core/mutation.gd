class_name Mutation
extends Resource
## Definition of one patch the AI can propose (PLAN 2.4): the card. Since PLAN v5 1.2
## its behaviour lives in takes, one per genre (mutations/<id>/<genre>.gd, a PatchTake),
## and the hooks below forward to the take of the run's genre. A legacy mutation (a
## parked one, or a test fixture) overrides the hooks itself, and its overrides win.
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
## Parked (PLAN v5 1.3): kept and tested, but never offered, pooled or shipped. Only
## tests, the F2 console and the bot's --big flag reach it, until its genre's phase.
@export var parked := false

## genre id -> PatchTake, built by MutationDB from the files next to the card.
var takes := {}

var _connections: Array = []
var _active: PatchTake   ## the take enable() switched on, so disable() finds it


## The take that runs this patch in `genre`, or null.
func take_for(genre: StringName) -> PatchTake:
	return takes.get(genre)


## True when this patch does something in `genre`: it has a take there, or it is a
## legacy mutation whose own script is its behaviour in every genre.
func has_take(genre: StringName) -> bool:
	return is_legacy() or takes.has(genre)


## A mutation with its own script (not the plain card): its hook overrides run as-is.
func is_legacy() -> bool:
	return get_script() != Mutation


## Lives in RunState.ai (added by a stage or the boss), never in the stack.
func is_ai_tier() -> bool:
	return is_medium or boss_only


## Pure: change rule values only.
func apply_rules(rules: WorldRules) -> void:
	var take := take_for(RunState.genre)
	if take != null:
		take.apply_rules(rules)


## Attach components with Component.attach(entity, Script, id). Must be idempotent:
## it runs for every live entity on apply and for every entity spawned afterwards.
func on_entity_spawned(entity: Node) -> void:
	var take := take_for(RunState.genre)
	if take != null:
		take.on_entity_spawned(entity)


## Connect to EventBus here, only through _listen().
func enable() -> void:
	_active = take_for(RunState.genre)
	if _active != null:
		_active.enable()


## Disconnects everything _listen() recorded, here and in the active take. Not meant
## to be overridden.
func disable() -> void:
	for c: Array in _connections:
		var sig: Signal = c[0]
		var method: Callable = c[1]
		if sig.is_connected(method):
			sig.disconnect(method)
	_connections.clear()
	if _active != null:
		_active.disable()
		_active = null


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
