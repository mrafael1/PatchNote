class_name RuleDB
extends RefCounted
## The rule edits (PLAN v8 1.4): every rules/<id>/<id>.tres, loaded on first use and
## sorted by id. Not an autoload (CampaignDB checks edit cues at boot) and not in
## MutationDB: edits are never offered, pooled or shipped.

const DIR := "res://rules/"

static var _by_id := {}
static var _all: Array[RuleEdit] = []
static var _loaded := false


static func all() -> Array[RuleEdit]:
	_load()
	return _all.duplicate()


static func get_edit(id: StringName) -> RuleEdit:
	_load()
	return _by_id.get(id)


static func reload() -> void:
	_loaded = false
	_load()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_by_id.clear()
	_all.clear()
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for folder in ResourceLoader.list_directory(DIR):
		var id := folder.trim_suffix("/")
		var path := DIR + id + "/" + id + ".tres"
		if not ResourceLoader.exists(path):
			continue
		var e := load(path) as RuleEdit
		if e == null:
			push_error("%s is not a RuleEdit" % path)
			continue
		if String(e.id) != id:
			push_error("%s: id %s is not its folder's name" % [path, e.id])
			continue
		_by_id[e.id] = e
		_all.append(e)
	_all.sort_custom(func(a: RuleEdit, b: RuleEdit) -> bool: return String(a.id) < String(b.id))


## Everything wrong with one edit.
static func problems(e: RuleEdit) -> Array[String]:
	var out: Array[String] = []
	var where := "edit %s" % e.id
	if not String(e.id).begins_with("edit_"):
		out.append("%s: an edit id starts with edit_" % where)
	if MutationDB.get_mutation(e.id) != null:
		out.append("%s: also a patch id" % where)
	if not e.target in RuleEdit.TARGETS:
		out.append("%s: unknown target %s" % [where, e.target])
	if not e.point_at in RuleEdit.POINTS:
		out.append("%s: unknown point_at %s" % [where, e.point_at])
	if e.warn_seconds < 0.0 or e.duration < 0.0:
		out.append("%s: warn_seconds and duration must be >= 0" % where)
	if not e.requires.is_empty():
		out.append("%s: edits require nothing" % where)
	for c in e.conflicts:
		if get_edit(c) == null:
			out.append("%s: conflicts with unknown edit %s" % [where, c])
	for l: Line in [e.warn(), e.done()]:
		if l != null and l.problem != "":
			out.append("%s: %s" % [where, l.problem])
	return out
