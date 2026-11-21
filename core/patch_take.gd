class_name PatchTake
extends RefCounted
## One genre's take on a patch (PLAN v5 1.2): the behaviour, in
## mutations/<id>/<genre>.gd. The card (title, lines, tags, requires, conflicts) stays
## on the patch's .tres. The Mutation forwards its hooks to the take of the run's genre,
## so a take is written exactly like a v2 mutation script: rules, components, listeners.
##
## MutationDB builds one instance per (patch, genre) at boot. Like the card, a take is
## shared for the life of the process and keeps no per-run data: use state().

## The card this take belongs to. Held weakly: the card holds its takes, and a strong
## reference back would be a cycle that is never freed.
var patch: Mutation:
	get: return _patch.get_ref() as Mutation if _patch else null
	set(value): _patch = weakref(value) if value else null
var id: StringName        ## the patch id: Component.attach(e, X, id), Explosion.blast(..., id)
var genre: StringName     ## the genre this take is for

var _patch: WeakRef
var _connections: Array = []


## Pure: change rule values only.
func apply_rules(_rules: WorldRules) -> void:
	pass


## Attach components with Component.attach(entity, Script, id). Must be idempotent.
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


## Connect one of this take's own methods to a signal. No lambdas.
func _listen(sig: Signal, method: Callable) -> void:
	assert(method.get_object() == self, "Take %s/%s: _listen() takes its own methods only" % [id, genre])
	if sig.is_connected(method):
		return
	sig.connect(method)
	_connections.append([sig, method])


## The patch's per-run scratch data (cleared on revert and on reset).
func state() -> Dictionary:
	return patch.state()


## The number of live connections this take holds (tests and the invariant check).
func connection_count() -> int:
	return _connections.size()
