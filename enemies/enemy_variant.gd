class_name EnemyVariant
extends Resource
## An enemy variant (PLAN v9 1.9, M47): data on a base scene (EnemyDB.BASES), in
## enemies/variants/<id>.tres. Spawned only by a cue until M50's spawn_weights; never a fork
## unlock (D13: ChangeDB and the fork resolvers stay on the bases). M47 builds the splitter
## (on_death split); the other fields are read from M48-M50 (colour_role, shields, packs).

const ON_DEATH: Array[StringName] = [&"none", &"split", &"blast"]

@export var id: StringName
@export var base: StringName = &"chaser"
@export var scale := 1.0
@export var hp_mult := 1.0
@export var speed_mult := 1.0
@export var colour_role: StringName = &""   ## unread until M48 (Palette)
@export var on_death: StringName = &"none"
@export var split_count := 2
@export var blast_radius := 0.0
@export var shield_arc_deg := 0.0
@export var pack := 1
@export var keep_range := 0.0
@export var telegraph := 0.0


func problems(file_id: StringName = id) -> Array[String]:
	var out: Array[String] = []
	var where := "variant %s" % file_id
	if id != file_id:
		out.append("%s: id %s is not its file's name" % [where, id])
	if not base in EnemyDB.BASES:
		out.append("%s: unknown base %s (%s)" % [where, base, EnemyDB.BASES])
	if scale <= 0.0 or hp_mult <= 0.0 or speed_mult <= 0.0:
		out.append("%s: scale, hp_mult and speed_mult must be > 0" % where)
	if not on_death in ON_DEATH:
		out.append("%s: unknown on_death %s (%s)" % [where, on_death, ON_DEATH])
	if on_death == &"split" and split_count < 1:
		out.append("%s: split_count must be >= 1" % where)
	if on_death == &"blast" and blast_radius <= 0.0:
		out.append("%s: a blast needs blast_radius > 0" % where)
	if pack < 1 or shield_arc_deg < 0.0 or keep_range < 0.0 or telegraph < 0.0:
		out.append("%s: pack >= 1, shield_arc_deg / keep_range / telegraph >= 0" % where)
	return out
