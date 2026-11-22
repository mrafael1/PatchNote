class_name StageSet
extends Resource
## A run's stages in order (PLAN v6 4), in levels/stages/<id>.tres. Without the Stages
## step a run is single(): one stage on arena_0 that ends with its prompts, which is
## the v0.0 run exactly. The Stages fork (M35) ships a set: the shipped take's preset
## (Unlocks.stage_set()).

const DIR := "res://levels/stages/"
const ARENA_0 := "res://levels/arenas/arena_0.tres"

## Debug, bot and test override (`--stages=<id>`, PLAN v6 5): every run plays this
## set. A static, so it survives the scene reloads between runs; null = none.
static var override: StageSet

@export var id: StringName
@export var stages: Array[Resource] = []   ## StageDef
## Shifting (M35): one place whose layout changes, so at a stage change the player stays
## where it stands (unless the new layout puts a block there).
@export var keep_position := false


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


## The set the next run plays: the override, else the save's shipped Stages take, else
## the one-stage run.
static func for_run() -> StageSet:
	if override != null:
		return override
	var shipped := Unlocks.stage_set()
	return shipped if shipped != null else single()


static func named(set_id: StringName) -> StageSet:
	var path := DIR + String(set_id) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as StageSet


static func ids() -> Array[StringName]:
	var names: Array[String] = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".tres"):
			names.append(f.get_basename())
	names.sort()   # as strings: StringNames sort by pointer
	var out: Array[StringName] = []
	for n in names:
		out.append(StringName(n))
	return out


## What is wrong with this set (empty = fine): stages, goals, arenas.
func problems() -> Array[String]:
	var out: Array[String] = []
	if stages.is_empty():
		out.append("%s has no stage" % id)
	for i in stages.size():
		var s := stages[i] as StageDef
		if s == null or s.arena == null:
			out.append("%s: stage %d has no arena" % [id, i])
			continue
		if not s.goal in StageDef.GOALS:
			out.append("%s: stage %d has an unknown goal '%s'" % [id, i, s.goal])
		if s.prompts < 1 and stages.size() > 1:
			out.append("%s: stage %d of a staged run needs a prompt" % [id, i])
		for p in s.arena.problems(&"topdown"):
			out.append("%s: stage %d: %s" % [id, i, p])
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
