class_name Change
extends Resource
## One change a dev session can ship (PLAN v5 1.6), in devsession/changes/<id>.tres.
## Shipping it adds its id to the save's `shipped` list; what it unlocks follows from
## that (Unlocks). The cards, the screens and the content come with M29.

## basic: one of the game's basics (Unlocks.BASICS), shipped by the AI before anything else.
## stages: a genre's Stages step (M35); its take's preset is a StageSet.
## mascot: the AI's body (PLAN v8 1.6, fork_mascot); its take's id is a body (MASCOTS).
## dash: the player's dash (PLAN v8 6.8, fork_dash); its take's id is a style (DASHES).
## dash_aim: where the dash goes (PLAN v8 6.9, fork_dash_aim); its take's id is in DASH_AIMS.
## path: the shooter path (PLAN v9 1.12, fork_path, M47); its take's id is a PathDB id.
const KINDS: Array[StringName] = [&"patch", &"enemy", &"look", &"basic", &"stages", &"mascot", &"dash",
		&"dash_aim", &"path"]
## The mascot bodies a mascot change can pick (MascotBody.IDS draws them).
const MASCOTS: Array[StringName] = [&"cursor", &"window", &"blob"]
## The dash styles a dash change can pick (Dasher.style plays them).
const DASHES: Array[StringName] = [&"classic", &"grapple", &"teleport"]
## Where the dash goes (M42.2): along the player's aim, or along the move direction.
const DASH_AIMS: Array[StringName] = [&"aim", &"move"]

@export var id: StringName
@export var title := ""
@export var pitch := ""                          ## the AI's line on the card
@export var kind: StringName = &"patch"          ## patch, enemy, look or basic
@export var genre: StringName = &""              ## &"" = shared by every genre
@export var bump: StringName = &"patch"          ## GameVersion.PATCH or GameVersion.MINOR
@export var requires: Array[StringName] = []     ## change ids, all shipped first
@export var unlocks: Array[StringName] = []      ## mutation ids or enemy archetypes
@export var tags: Array[StringName] = []         ## taste
@export var weight := 1.0
@export var due_after_run := 0                   ## offered first once runs >= this
## An option of a mockup fork (PLAN v6 1.1): its still, line and (for a look) preset.
@export var take: MockupTake

## The fork this change answers (set by ChangeDB from devsession/forks/; &"" = none).
var fork: StringName = &""


## The name the AI's lines use: a mockup option is its take ("Punchy"), an enemy
## change its archetype ("Tank"), anything else its title.
func short_name() -> String:
	if take != null:
		return take.title
	if kind == &"enemy" and not unlocks.is_empty():
		return String(unlocks[0]).capitalize()
	return title


func is_basic() -> bool:
	return kind == &"basic"


func is_mockup() -> bool:
	return take != null
