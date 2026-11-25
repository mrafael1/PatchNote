class_name ScriptedEvent
extends Resource
## A scripted event (PLAN v8 1.5): events/<id>/<id>.tres + .gd. Its script is a
## coroutine play(ctx) over an EventContext: it says lines, poses warnings, requests,
## swaps and removes rule edits, holds the session clock and glitches the mascot.
## EventPlayer runs one at a time on its own ticks. The .tres is shared by every play,
## so all run state lives in the EventContext, never here.

@export var id: StringName
@export var title := ""                 ## F2's label
@export var once_per_save := true       ## seen once, then a cue for it does nothing
@export var photosensitive := false     ## flashes: a gentle variant with reduce_flashing
## M47.5b (PLAN v9.3 2.9): what the always-on terminal prints when it starts (the command the
## AI thinks it types); "" = nothing.
@export var cmd_text := ""
@export var steps := 1                  ## how many ctx.step(n) a full play reaches (bot, F1, tests)
## The event's lines by key, in Line syntax: the owner edits their tone here, not in the
## script. Said live, so none may have a condition.
@export var lines: Dictionary[StringName, String] = {}


## The gentle variant applies (a photosensitive event, reduce_flashing on).
func gentle() -> bool:
	return photosensitive and SaveGame.reduce_flashing()


func line(key: StringName) -> Line:
	return Line.parse(lines[key]) if lines.has(key) else null


## The coroutine; every event overrides it. Return early whenever `await ctx.wait(...)`
## gives false (the session ended under it).
func play(_ctx: EventContext) -> void:
	push_error("event %s has no play()" % id)
