class_name Fork
extends Resource
## One question a dev session asks (PLAN v6 1.1), in devsession/forks/<id>.tres. Its
## options are changes; picking one ships it and shelves the others. "Answered" and
## "shelved" are derived from the save's shipped list, so a fork has no state of its own.

@export var id: StringName
@export var question := ""                        ## the AI's line, e.g. "Who joins the fight?"
@export var options: Array[StringName] = []       ## 2 or 3 change ids
@export var requires_forks: Array[StringName] = [] ## those forks answered first, whatever the answer
@export var due_after_run := 0                    ## > 0: asked first once runs >= this
@export var genre: StringName = &""               ## &"" = shared by every genre
@export var play_runs := 0                        ## the genre's runs in the save first (hidden threshold)
@export var bump: StringName = &"patch"           ## GameVersion.PATCH or GameVersion.MINOR
@export var tags: Array[StringName] = []          ## taste: which fork comes up
@export var weight := 1.0
@export var mockup := false                       ## options are shown as stills
## Asked only by a campaign session's debrief (PLAN v8 1.6); the v6 dev session never
## offers it.
@export var campaign := false


## The options as changes, in order (unknown ids skipped).
func changes() -> Array[Change]:
	var out: Array[Change] = []
	for o in options:
		var c := ChangeDB.get_change(o)
		if c != null:
			out.append(c)
	return out


## The shipped option, or null.
func answer() -> Change:
	for c in changes():
		if SaveGame.has_shipped(c.id):
			return c
	return null


func is_answered() -> bool:
	return answer() != null


## The options not shipped of an answered fork (empty while unanswered).
func shelf() -> Array[Change]:
	var out: Array[Change] = []
	if not is_answered():
		return out
	for c in changes():
		if not SaveGame.has_shipped(c.id):
			out.append(c)
	return out
