class_name RuleBook
extends Node
## The rule book (PLAN v8 1.4): the AI changes a rule of the game in front of the
## player. request() warns first (the mascot's line at priority 3, it points, a marker
## at the screen edge, a rising sound), lands the edit after its warn_seconds
## (RunState.add_ai, owner &"edit"), and after its duration takes it back
## (remove_ai, reason expired) with its done line. clear() takes everything back with
## no lines (the session ends, the player dies).
##
## A campaign shell node (main.gd): null in the run loop. It counts its own physics
## ticks, so warnings and durations are the seconds the player lives through (slow
## motion does not stretch them, the pause stops them) and the same seed lands the same
## edits on the same frames.

signal edit_landed(edit: RuleEdit)
signal edit_ended(edit: RuleEdit, reason: StringName)

var game: Node                    ## main.gd: genre, player, arena
var mascot: Mascot
var reactions: Reactions
var session_runner: SessionRunner
var sound: Sound
var muted := false

## {id, at (game time), by} for every edit that landed (telemetry, the bot).
var landed: Array[Dictionary] = []
## Every line the rule book gave the mascot (tests, the bot).
var said: Array[String] = []

var _tick := 0
var _pending: Array[Dictionary] = []   ## {edit, by, seconds, land_tick}
var _live := {}                        ## id -> {edit, end_tick (-1: until the session ends)}
var _marker: EditMarker


func _ready() -> void:
	# Ticks before the session runner and the event player, so an edit asked for in a
	# frame counts its warning from the next tick: never landing a frame early.
	process_physics_priority = -10
	_marker = EditMarker.new()
	_marker.name = "EditMarker"
	add_child(_marker)
	EventBus.run_ended.connect(func(_o: StringName) -> void: clear())
	EventBus.ai_patch_removed.connect(_on_ai_removed)


## Asks for edit `id`. by: &"cue", &"console", &"event". seconds: how long it stays
## (-1: the edit's own duration; 0: until the session ends). warn: false lands it at the
## next tick with no line, no marker (M41's event). Refused: the game is over, an
## unknown id, the edit pending or live, or it conflicts with one pending or live.
func request(id: StringName, by := &"cue", seconds := -1.0, warn := true) -> bool:
	if _over():
		return false
	var e := RuleDB.get_edit(id)
	if e == null or _live.has(id) or is_pending(id):
		return false
	for p: Dictionary in _pending:
		if RunState.conflicting(e, p.edit):
			return false
	if not RunState.can_add_ai(e):
		return false
	var ticks := roundi((e.warn_seconds if warn else 0.0) * Engine.physics_ticks_per_second)
	_pending.append({"edit": e, "by": by, "seconds": seconds, "land_tick": _tick + maxi(ticks, 1), "warned": warn,
			"asked_frame": Engine.get_physics_frames()})
	RunState.log_event(&"edit_requested", {"id": String(id), "by": String(by)})
	if warn:
		_speak(e.warn(), 3)
		_point(e)
		_marker.show_for(e.target, _point_screen(e), e.gentle())
		if sound != null:
			sound.play(&"edit_warn", 0.0)
	return true


func is_pending(id: StringName) -> bool:
	for p: Dictionary in _pending:
		if p.edit.id == id:
			return true
	return false


func is_live(id: StringName) -> bool:
	return _live.has(id)


## Live edits' ids, in the order they landed.
func live_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _live:
		out.append(id)
	return out


## Seconds left on a live edit (-1: until the session ends, or not live).
func seconds_left(id: StringName) -> float:
	if not _live.has(id) or int(_live[id].end_tick) < 0:
		return -1.0
	return float(int(_live[id].end_tick) - _tick) / Engine.physics_ticks_per_second


## Cancels a pending edit or takes a live one back, with no done line (F2, M41).
func remove(id: StringName, reason := &"console") -> bool:
	for i in _pending.size():
		if _pending[i].edit.id == id:
			_pending.remove_at(i)
			_show_marker()
			return true
	if not _live.has(id):
		return false
	var e: RuleEdit = _live[id].edit
	var key := _gravity_key()
	_live.erase(id)
	RunState.remove_ai(e, reason)
	_after_gravity_change(key)
	edit_ended.emit(e, reason)
	return true


## Everything back, no lines: the session ended (any outcome), the player died. Pending
## edits never land.
func clear() -> void:
	_pending.clear()
	_marker.hide_marker()
	var gone := _live.values().map(func(l: Dictionary) -> RuleEdit: return l.edit)
	_live.clear()
	RunState.expire_ai(&"edit", &"cleared")
	for e: RuleEdit in gone:
		edit_ended.emit(e, &"cleared")


func _physics_process(_delta: float) -> void:
	_tick += 1
	if _over():
		return
	var key := _gravity_key()
	var i := 0
	while i < _pending.size():
		var p: Dictionary = _pending[i]
		if int(p.land_tick) > _tick:
			i += 1
			continue
		_pending.remove_at(i)
		_land(p)
		_show_marker()
	var ending: Array[StringName] = []
	for id: StringName in _live:
		var end_tick := int(_live[id].end_tick)
		if end_tick >= 0 and end_tick <= _tick:
			ending.append(id)
	for id in ending:
		var e: RuleEdit = _live[id].edit
		_live.erase(id)
		RunState.remove_ai(e, &"expired")
		edit_ended.emit(e, &"expired")
		_speak(e.done(), SessionRunner.PRIORITY, true)
	_after_gravity_change(key)


## The marker shows the latest edit still in its warning, or nothing.
func _show_marker() -> void:
	for k in range(_pending.size() - 1, -1, -1):
		var p: Dictionary = _pending[k]
		if p.warned:
			_marker.show_for(p.edit.target, _point_screen(p.edit), p.edit.gentle())
			return
	_marker.hide_marker()


func _land(p: Dictionary) -> void:
	var e: RuleEdit = p.edit
	if not RunState.add_ai(e, &"edit"):
		RunState.log_event(&"edit_refused", {"id": String(e.id)})
		return
	var secs: float = p.seconds if float(p.seconds) >= 0.0 else e.duration
	var end_tick := _tick + roundi(secs * Engine.physics_ticks_per_second) if secs > 0.0 else -1
	# The frames are for tests (the warning's real length); nothing plays on them.
	_live[e.id] = {"edit": e, "end_tick": end_tick, "warned_frames": Engine.get_physics_frames() - int(p.asked_frame)}
	landed.append({"id": String(e.id), "at": snappedf(RunState.game_time, 0.01), "by": String(p.by)})
	RunState.log_event(&"edit_landed", {"id": String(e.id), "by": String(p.by)})
	edit_landed.emit(e)


## An edit removed by someone else (F2's v6 rows, a rollback): forget it, no line.
func _on_ai_removed(m: Resource, _reason: StringName) -> void:
	if m is RuleEdit and _live.has(m.id):
		_live.erase(m.id)


## Gravity changed (an edit landed or ended): no contact damage for a moment, so a flip
## never lands the player in a bite (PLAN v8 1.5).
func _gravity_key() -> Array:
	var r := RunState.rules
	return [r.gravity_enabled, r.gravity_dir]


func _after_gravity_change(before: Array) -> void:
	if _gravity_key() != before:
		RunState.start_grace(Tuning.edit_gravity_grace)


func _over() -> bool:
	return game == null or game.genre == null or game.genre.is_over()


## A line to the mascot. A warning (priority 3) goes straight to it: the player must
## hear it before the rule changes. A done line queues behind the script's lines.
func _speak(line: Line, priority: int, queued := false) -> void:
	if line == null or muted:
		return
	said.append(line.text)
	if queued and session_runner != null:
		session_runner.say(line)
		return
	if reactions != null:
		reactions.note_spoken(line, priority)
	if mascot != null:
		mascot.say(line, priority)


func _point(e: RuleEdit) -> void:
	if mascot != null:
		mascot.point_at_screen(_point_screen(e), e.warn_seconds + 0.3)


## Where the edit points, on screen.
func _point_screen(e: RuleEdit) -> Vector2:
	var view := get_viewport()
	var centre := view.get_visible_rect().size * 0.5
	var world_pos := Vector2.INF
	match e.point_at:
		&"player":
			if is_instance_valid(game.player):
				world_pos = game.player.global_position
		&"nearest_enemy":
			world_pos = _nearest_enemy()
		&"walls":
			world_pos = _nearest_wall()
	if world_pos == Vector2.INF:
		return centre
	return view.get_canvas_transform() * world_pos


func _nearest_enemy() -> Vector2:
	if not is_instance_valid(game.player):
		return Vector2.INF
	var from: Vector2 = game.player.global_position
	var best := Vector2.INF
	var best_d := INF
	for n in get_tree().get_nodes_in_group(&"enemy"):
		var e := n as Node2D
		if e == null or e.is_queued_for_deletion():
			continue
		var d := from.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e.global_position
	return best


func _nearest_wall() -> Vector2:
	var arena: Node = game.get(&"arena")
	if arena == null or not is_instance_valid(game.player):
		return Vector2.INF
	var from: Vector2 = game.player.global_position
	var best := Vector2.INF
	var best_d := INF
	for rect: Rect2 in arena.get(&"blocks"):
		var c := rect.get_center()
		var d := from.distance_squared_to(c)
		if d < best_d:
			best_d = d
			best = c
	return best
