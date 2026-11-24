class_name WeaponDB
extends RefCounted
## The weapons (PLAN v9 1.4): every weapons/<id>.tres, loaded on first use and sorted by
## id (the RuleDB pattern). Not an autoload; no preloads (the export lists .tres files).

const DIR := "res://weapons/"

static var _by_id := {}
static var _all: Array[WeaponDef] = []
static var _loaded := false


static func all() -> Array[WeaponDef]:
	_load()
	return _all.duplicate()


static func ids() -> Array[StringName]:
	_load()
	var out: Array[StringName] = []
	for w in _all:
		out.append(w.id)
	return out


static func get_weapon(id: StringName) -> WeaponDef:
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
	for w in _all:
		out.append_array(w.problems())
	return out


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
		var w := load(path) as WeaponDef
		if w == null:
			push_error("%s is not a WeaponDef" % path)
			continue
		if String(w.id) != file.get_basename():
			push_error("%s: id %s is not its file's name" % [path, w.id])
			continue
		_by_id[w.id] = w
		_all.append(w)
	_all.sort_custom(func(a: WeaponDef, b: WeaponDef) -> bool: return String(a.id) < String(b.id))
