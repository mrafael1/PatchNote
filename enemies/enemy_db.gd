class_name EnemyDB
extends RefCounted
## The enemy lists (PLAN v9 1.3). BASES are the five scenes (the legacy list, in the order
## every v6 / Stage 1 run has read it: Unlocks.enemies() and the spawner depend on it).
## VARIANTS are data on a base (EnemyVariant, enemies/variants/<id>.tres, M47: the
## splitter; M50.3c: the shielder, the sniper and the swarm; loaded on demand by variant(),
## never preloaded). Cues and sessions
## validate against all(). Scenes live at res://entities/enemy_<id>.tscn (reactions.gd
## reads that name). No preload here: Unlocks names this file, and the enemy scenes'
## scripts read Unlocks, so a scene preload could close a load cycle.

const BASES: Array[StringName] = [&"chaser", &"shooter", &"tank", &"bomber", &"lancer"]
const VARIANTS: Array[StringName] = [&"splitter", &"shielder", &"sniper", &"swarm"]
## M50.3c: the variants drawn as their base under a look (no sprite of their own yet): a
## look tells them apart by what is drawn in code (the shield arc, the aim line, the size).
const PLAIN: Array[StringName] = [&"shielder", &"sniper", &"swarm"]
## The bases in card reading order (M50.1a: WeaponCurve's breakpoint text, "one-shots
## chasers and lancers, tank in 4"). Same ids as BASES.
const READING: Array[StringName] = [&"chaser", &"lancer", &"shooter", &"bomber", &"tank"]
## The bases whose scene is an EnemyWalker (M48b: the ones a `spawn ... specimen` may name).
const WALKERS: Array[StringName] = [&"chaser", &"tank", &"bomber", &"lancer"]
const VARIANTS_DIR := "res://enemies/variants/"

static var _variants := {}


## Every enemy id a cue or a session may name: BASES then VARIANTS (a fresh typed array).
static func all() -> Array[StringName]:
	var out: Array[StringName] = BASES.duplicate()
	out.append_array(VARIANTS)
	return out


## True for a base or a variant id (no allocation).
static func has(id: StringName) -> bool:
	return id in BASES or id in VARIANTS


## A variant's data (null for a base or an unknown id), loaded on first use.
static func variant(id: StringName) -> EnemyVariant:
	if not id in VARIANTS:
		return null
	if not _variants.has(id):
		_variants[id] = load(VARIANTS_DIR + "%s.tres" % id) as EnemyVariant
	return _variants[id]


## The base a variant stands on; a base's own id; &"" when unknown.
static func base_of(id: StringName) -> StringName:
	if id in BASES:
		return id
	var v := variant(id)
	return v.base if v != null else &""


## A base's scene path; "" for anything else.
static func scene_path(id: StringName) -> String:
	return "res://entities/enemy_%s.tscn" % id if id in BASES else ""


## {id: PackedScene} for every base, in BASES order (loaded on demand, for the spawner).
static func base_scenes() -> Dictionary:
	var out := {}
	for id in BASES:
		out[id] = load(scene_path(id))
	return out
