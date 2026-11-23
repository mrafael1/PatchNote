class_name EventPlayer
extends Node
## Plays scripted events (PLAN v8 1.5), one at a time: a campaign shell node (main.gd),
## null in the run loop. It ticks after the rule book and before the session runner,
## so an edit an event asks for lands on the rule book's next tick and a cue's event
## starts in the frame the cue fires. An event's script (a coroutine on the shared
## resource) resumes inside this node's tick: deterministic.
##
## once_per_save: marked seen when it starts (on disk with the debrief's choice), then
## skipped: the cue does nothing and the session plays on. A forced play (F2) ignores it
## and marks nothing. The session ending (death, win) aborts it: the clock and the
## reactions are released, the mutations it applied are taken back (the rule book's
## clear() takes back its edits), and the script returns at its next wait.

signal ticked

var game: Node
var mascot: Mascot
var reactions: Reactions
var rule_book: RuleBook
var sound: Sound
var transition: Transition
var muted := false

var tick := 0
## One record per play or skip ({id, by, start, end, steps_done, steps, completed,
## aborted, skipped}).
var played: Array[Dictionary] = []
## Every line an event said (tests, the bot).
var said: Array[String] = []

var _ctx: EventContext
var _clock_holds: Array[StringName] = []
var _applied: Array[Mutation] = []


func _ready() -> void:
	# After PlayerInput and the rule book (-10), before the session runner (0) and the run
	# loop (1); not -5 (the TurnClock).
	process_physics_priority = -7
	EventBus.run_ended.connect(_abort)


func _exit_tree() -> void:
	_abort(&"")


func is_playing() -> bool:
	return _ctx != null


## Plays event `id`. by: &"cue", &"console". force: ignore once_per_save and mark
## nothing (F2). false: not played (busy, over, unknown, or seen and skipped).
func play(id: StringName, by := &"cue", force := false) -> bool:
	if _ctx != null or _over():
		return false
	var ev := EventDB.get_event(id)
	if ev == null:
		push_warning("no event %s" % id)
		return false
	if ev.once_per_save and not force and SaveGame.event_seen(id):
		played.append({"id": String(id), "by": String(by), "skipped": true,
				"start": snappedf(RunState.game_time, 0.01), "end": snappedf(RunState.game_time, 0.01),
				"steps_done": 0, "steps": ev.steps, "completed": false, "aborted": false})
		RunState.log_event(&"event_skipped", {"id": String(id)})
		return false
	if ev.once_per_save and not force:
		SaveGame.mark_event_seen(id)
	var ctx := EventContext.new()
	ctx.player = self
	ctx.event = ev
	ctx.by = by
	ctx.start_frame = Engine.get_physics_frames()
	ctx.record = {"id": String(id), "by": String(by), "skipped": false,
			"start": snappedf(RunState.game_time, 0.01), "end": -1.0,
			"steps_done": 0, "steps": ev.steps, "completed": false, "aborted": false}
	_ctx = ctx
	played.append(ctx.record)
	RunState.log_event(&"event_started", {"id": String(id), "by": String(by)})
	if reactions != null:
		reactions.hold(&"event", true)
	_run(ev, ctx)
	return true


## The ids of the events played (not skipped) this attempt.
func played_ids() -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in played:
		if not r.skipped and not String(r.id) in out:
			out.append(String(r.id))
	return out


## F1: "wrong_variable step 3/6 (clock held)", "wrong_variable (skipped)" or "-".
func state_text() -> String:
	if _ctx != null:
		return "%s step %d/%d%s" % [_ctx.event.id, int(_ctx.record.steps_done), _ctx.event.steps,
				" (clock held)" if not _clock_holds.is_empty() else ""]
	if played.is_empty():
		return "-"
	var last: Dictionary = played.back()
	var how := "skipped" if last.skipped else "done" if last.completed else "aborted"
	return "%s (%s)" % [last.id, how]


func _run(ev: ScriptedEvent, ctx: EventContext) -> void:
	var e: Object = ev   # untyped: the base play() is no coroutine
	await e.call(&"play", ctx)
	_finish(ctx)


func _finish(ctx: EventContext) -> void:
	for owner_id in _clock_holds.duplicate():
		hold_clock(owner_id, false)
	if reactions != null:
		reactions.hold(&"event", false)
	ctx.record.end = snappedf(RunState.game_time, 0.01)
	ctx.record.completed = not ctx.aborted and int(ctx.record.steps_done) >= ctx.event.steps
	RunState.log_event(&"event_ended", {"id": String(ctx.event.id), "steps": int(ctx.record.steps_done),
			"completed": ctx.record.completed})
	if _ctx == ctx:
		_ctx = null


func _physics_process(_delta: float) -> void:
	if _ctx == null or _over():
		return
	tick += 1
	ticked.emit()


## The session ended (or the scene goes): the script stops at its next wait, and what
## the events applied themselves goes.
func _abort(_outcome: StringName) -> void:
	if _ctx != null:
		_ctx.aborted = true
		_ctx.record.aborted = true
		ticked.emit()
	for m in _applied:
		RunState.remove_ai(m, &"event")
	_applied.clear()


func hold_clock(owner_id: StringName, on: bool) -> void:
	if game != null and game.genre != null:
		game.genre.hold_session_clock(owner_id, on)
	if on and not owner_id in _clock_holds:
		_clock_holds.append(owner_id)
	elif not on:
		_clock_holds.erase(owner_id)


func clock_held() -> bool:
	return not _clock_holds.is_empty()


## A line at priority 3, straight to the mascot (like a rule edit's warning).
func speak(line: Line, cut := false) -> void:
	if line == null or muted:
		return
	said.append(line.text)
	if reactions != null:
		reactions.note_spoken(line, 3, cut)
	if mascot != null:
		mascot.say(line, 3, cut)


func show_expression(e: StringName) -> void:
	if mascot != null and not muted:
		mascot.show_expression(e)


func glitch(seconds: float, screen: float) -> void:
	if mascot != null:
		mascot.glitch(seconds)
	if screen > 0.0:
		if transition != null:
			transition.glitch(screen)
		if sound != null:
			sound.play(&"glitch", 0.0)


## Applies a mutation owned by the event (taken back when the session ends).
func apply(m: Mutation) -> bool:
	if m == null or not RunState.add_ai(m, &"event"):
		return false
	_applied.append(m)
	return true


func _over() -> bool:
	return game == null or game.genre == null or game.genre.is_over()
