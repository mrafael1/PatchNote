class_name PathDB
extends RefCounted
## The shooter paths (PLAN v9 1.5): every paths/<id>.tres, loaded on first use and sorted by
## id (the WeaponDB pattern). Not an autoload; no preloads (the export lists .tres files).
## M45a built Auto, M46 Arsenal, M47 Survival.

const DIR := "res://paths/"

static var _by_id := {}
static var _all: Array[PathDef] = []
static var _loaded := false


static func all() -> Array[PathDef]:
	_load()
	return _all.duplicate()


static func ids() -> Array[StringName]:
	_load()
	var out: Array[StringName] = []
	for p in _all:
		out.append(p.id)
	return out


static func get_def(id: StringName) -> PathDef:
	if id == &"":
		return null
	_load()
	return _by_id.get(id)


static func has(id: StringName) -> bool:
	_load()
	return _by_id.has(id)


static func reload() -> void:
	_loaded = false
	_load()


static func problems() -> Array[String]:
	_load()
	var out: Array[String] = []
	for p in _all:
		out.append_array(p.problems())
	return out


## The path whose basics list `basic` (&"" for a shared basic).
static func owner_of_basic(basic: StringName) -> StringName:
	_load()
	for p in _all:
		if basic in p.basics:
			return p.id
	return &""


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_by_id.clear()
	_all.clear()
	for file in ResourceLoader.list_directory(DIR):
		if not file.ends_with(".tres"):
			continue
		var path := DIR + file
		var p := load(path) as PathDef
		if p == null:
			push_error("%s is not a PathDef" % path)
			continue
		if String(p.id) != file.get_basename():
			push_error("%s: id %s is not its file's name" % [path, p.id])
			continue
		_by_id[p.id] = p
		_all.append(p)
	_all.sort_custom(func(a: PathDef, b: PathDef) -> bool: return String(a.id) < String(b.id))
