class_name EnemyDB
extends RefCounted
## The enemy lists (PLAN v9 1.3). BASES are the five scenes (the legacy list, in the order
## every v6 / Stage 1 run has read it: Unlocks.enemies() and the spawner depend on it).
## VARIANTS are data on a base (EnemyVariant, from M47); none yet. Cues and sessions
## validate against all(). Scenes live at res://entities/enemy_<id>.tscn (reactions.gd
## reads that name). No preload here: Unlocks names this file, and the enemy scenes'
## scripts read Unlocks, so a scene preload could close a load cycle.

const BASES: Array[StringName] = [&"chaser", &"shooter", &"tank", &"bomber", &"lancer"]
const VARIANTS: Array[StringName] = []


## Every enemy id a cue or a session may name: BASES then VARIANTS (a fresh typed array).
static func all() -> Array[StringName]:
	var out: Array[StringName] = BASES.duplicate()
	out.append_array(VARIANTS)
	return out


## True for a base or a variant id (no allocation).
static func has(id: StringName) -> bool:
	return id in BASES or id in VARIANTS


## A base's scene path; "" for anything else.
static func scene_path(id: StringName) -> String:
	return "res://entities/enemy_%s.tscn" % id if id in BASES else ""


## {id: PackedScene} for every base, in BASES order (loaded on demand, for the spawner).
static func base_scenes() -> Dictionary:
	var out := {}
	for id in BASES:
		out[id] = load(scene_path(id))
	return out
