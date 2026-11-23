class_name EventContext
extends RefCounted
## What a scripted event's play(ctx) may do (PLAN v8 1.5): the event's whole API, so an
## event script never reaches into nodes. One per play; it holds the play's state (the
## ScriptedEvent resource is shared). Waits count the EventPlayer's own physics ticks:
## never the goal clock (the event holds it), never the wall clock or the mascot's
## speech (the bot runs faster than speech), so the same seed plays the same frames.

var player: EventPlayer
var event: ScriptedEvent
var by: StringName
var aborted := false
## {id, by, start, end, steps_done, steps, completed, aborted, skipped}; start/end in game time.
var record := {}
var start_frame := 0   ## Engine.get_physics_frames() at play(): tests only, never logged


## The gentle variant applies (a photosensitive event, reduce_flashing on).
func gentle() -> bool:
	return event.gentle()


## Marks how far the event got (the bot, F1, tests).
func step(n: int) -> void:
	record.steps_done = n
	RunState.log_event(&"event_step", {"id": String(event.id), "step": n})


## Waits `seconds` of the player's ticks. false: the session ended under it; return.
func wait(seconds: float) -> bool:
	var until := player.tick + maxi(1, roundi(seconds * Engine.physics_ticks_per_second))
	while player.tick < until and not aborted:
		await player.ticked
	return not aborted


## Says the event's line `key` at priority 3. cut: replace the line on screen now.
func say(key: StringName, cut := false) -> void:
	player.speak(event.line(key), cut)


## The rule book warns with edit as_id's warning, then lands real_id instead.
func pose_warning(real_id: StringName, as_id: StringName) -> bool:
	return player.rule_book != null and player.rule_book.request(real_id, &"event", 0.0, true, as_id)


func warn_seconds(edit_id: StringName) -> float:
	var e := RuleDB.get_edit(edit_id)
	return e.warn_seconds if e != null else 0.0


## An edit through the rule book (seconds 0: until the session ends).
func request_edit(id: StringName, seconds := 0.0, warn := false) -> bool:
	return player.rule_book != null and player.rule_book.request(id, &"event", seconds, warn)


func swap_edit(old_id: StringName, new_id: StringName) -> bool:
	return player.rule_book != null and player.rule_book.swap(old_id, new_id, &"event")


func remove_edit(id: StringName) -> bool:
	return player.rule_book != null and player.rule_book.remove(id, &"event")


## Holds the session's goal clock (the player still gets the full goal).
func hold_clock(on: bool) -> void:
	player.hold_clock(event.id, on)


## A face with no line (dropped when muted).
func expression(e: StringName) -> void:
	player.show_expression(e)


## Glitches the mascot (1.5's "shake or glitch the mascot"); with screen > 0 and not
## gentle, the screen glitches too, with its sound.
func glitch(seconds: float, screen := 0.0) -> void:
	player.glitch(seconds, 0.0 if gentle() else screen)


## A mutation the event applies itself (owner &"event", not the rule book's): the
## player takes it back when the session ends.
func apply_mutation(edit_id: StringName) -> bool:
	return player.apply(RuleDB.get_edit(edit_id))
