class_name StageSet
extends Resource
## A run's stages in order (PLAN v6 4), in levels/stages/<id>.tres. Without the Stages
## step a run is single(): one stage on arena_0 that ends with its prompts, which is
## the v0.0 run exactly. The Stages fork (M35) will pick a set from the save.

const DIR := "res://levels/stages/"
const ARENA_0 := "res://levels/arenas/arena_0.tres"

## Debug, bot and test override (`--stages=<id>`, PLAN v6 5): every run plays this
## set. A static, so it survives the scene reloads between runs; null = none.
static var override: StageSet

@export var id: StringName
@export var stages: Array[Resource] = []   ## StageDef


func size() -> int:
	return stages.size()


func stage(i: int) -> StageDef:
	return stages[i] as StageDef


## Returns false when there is no such set (the override is then left alone).
static func use_override(set_id: StringName) -> bool:
	var set := named(set_id)
	if set != null:
		override = set
	return set != null


## The set the next run plays.
static func for_run() -> StageSet:
	return override if override != null else single()


static func named(set_id: StringName) -> StageSet:
	var path := DIR + String(set_id) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as StageSet


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".tres"):
			out.append(StringName(f.get_basename()))
	out.sort()
	return out


## The one-stage run: arena_0, ends when the run's prompts are done.
static func single() -> StageSet:
	var s := StageDef.new()
	s.arena = load(ARENA_0) as ArenaDef
	s.duration = 0.0
	s.prompts = -1
	var set := StageSet.new()
	set.id = &"single"
	set.stages = [s]
	return set
