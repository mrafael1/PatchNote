class_name Change
extends Resource
## One change a dev session can ship (PLAN v5 1.6), in devsession/changes/<id>.tres.
## Shipping it adds its id to the save's `shipped` list; what it unlocks follows from
## that (Unlocks). The cards, the screens and the content come with M29.

const KINDS: Array[StringName] = [&"patch", &"enemy", &"look"]

@export var id: StringName
@export var title := ""
@export var pitch := ""                          ## the AI's line on the card
@export var kind: StringName = &"patch"          ## patch, enemy or look
@export var genre: StringName = &""              ## &"" = shared by every genre
@export var bump: StringName = &"patch"          ## GameVersion.PATCH or GameVersion.MINOR
@export var requires: Array[StringName] = []     ## change ids, all shipped first
@export var unlocks: Array[StringName] = []      ## mutation ids or enemy archetypes
@export var tags: Array[StringName] = []         ## taste
@export var weight := 1.0
@export var due_after_run := 0                   ## offered first once runs >= this
@export var takes: Array[MockupTake] = []        ## a mockup: exactly 3 takes


func is_mockup() -> bool:
	return not takes.is_empty()
