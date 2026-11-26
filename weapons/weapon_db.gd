class_name WeaponDB
extends RefCounted
## The weapons (PLAN v9 1.4): every weapons/<id>.tres, loaded on first use and sorted by
## id (the RuleDB pattern). Not an autoload; no preloads (the export lists .tres files).
##
## M50.1b (fusion, Arsenal depth design 4): the fused cards live in weapons/fusions/<id>.tres
## and load into their own list (fusions(), recipe()); all() and ids() stay the base weapons.
## get_weapon() and has() resolve both. problems() is the base weapons'; fusion_problems() the
## fusions' (an unbuilt row reads "not built yet (<milestone>)").
##
## M50.4b (Auto depth design 4): the passive items live in weapons/items/<id>.tres (ItemDef)
## and load into their own list (items(), item(), has_item()); get_weapon() / has() never
## resolve them, so all(), ids() and every weapon check are unchanged.

const DIR := "res://weapons/"
const FUSION_DIR := "res://weapons/fusions/"
const ITEM_DIR := "res://weapons/items/"

static var _by_id := {}
static var _all: Array[WeaponDef] = []
static var _fusions: Array[WeaponDef] = []
static var _items: Array[ItemDef] = []
static var _item_by_id := {}
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


## M50.1b: the fused cards, sorted by id (built or not).
static func fusions() -> Array[WeaponDef]:
	_load()
	return _fusions.duplicate()


## M50.1b: the fusion whose parents are `a` and `b` (either order), &"" for none (built or not).
static func recipe(a: StringName, b: StringName) -> StringName:
	_load()
	if a == b:
		return &""
	for f in _fusions:
		if f.parents.size() == 2 and ((f.parents[0] == a and f.parents[1] == b) or (f.parents[0] == b and f.parents[1] == a)):
			return f.id
	return &""


## M50.1b: a fusion that plays (its row is built).
static func fusion_built(id: StringName) -> bool:
	var f := get_weapon(id)
	return f != null and f.is_fusion() and f.built_in == ""


## M50.1b: every fusion's problems, its parents checked against the base weapons. An unbuilt
## row gives its one "not built yet" line.
static func fusion_problems() -> Array[String]:
	_load()
	var out: Array[String] = []
	for f in _fusions:
		out.append_array(f.problems())
		if f.built_in != "":
			continue
		for i in f.parents.size():
			var p := get_weapon(f.parents[i])
			if p == null or p.is_fusion():
				out.append("fusion %s: parent %s is not a weapon" % [f.id, f.parents[i]])
				continue
			var mech := WeaponCurve.mechanics(p)
			for k in 2:
				var j := i * 2 + k
				if j < f.inherits.size() and (mech.size() <= k or mech[k] != f.inherits[j]):
					out.append("fusion %s: %s is not %s's rank-%d mechanic" % [f.id, f.inherits[j], p.id, 2 + 2 * k])
	return out


## M50.4b: the passive items, sorted by id (built or not).
static func items() -> Array[ItemDef]:
	_load()
	return _items.duplicate()


static func item(id: StringName) -> ItemDef:
	_load()
	return _item_by_id.get(id)


static func has_item(id: StringName) -> bool:
	_load()
	return _item_by_id.has(id)


## M50.4b: an item that plays (its row is built).
static func item_built(id: StringName) -> bool:
	var it := item(id)
	return it != null and it.built()


## M50.4b: every item's problems; its `pairs` must be a base weapon, and an item id never
## shadows a weapon id. An unbuilt row gives its one "not built yet" line.
static func item_problems() -> Array[String]:
	_load()
	var out: Array[String] = []
	for it in _items:
		out.append_array(it.problems())
		if _by_id.has(it.id):
			out.append("item %s: its id is a weapon's" % it.id)
		var w := get_weapon(it.pairs)
		if w == null or w.is_fusion():
			out.append("item %s: pairs %s, not a base weapon" % [it.id, it.pairs])
		if not it.built():
			out.append("item %s: %s" % [it.id, it.built_in])
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
	_fusions.clear()
	_items.clear()
	_item_by_id.clear()
	_load_dir(DIR, _all)
	_load_dir(FUSION_DIR, _fusions)
	_load_items()
	_all.sort_custom(func(a: WeaponDef, b: WeaponDef) -> bool: return String(a.id) < String(b.id))
	_fusions.sort_custom(func(a: WeaponDef, b: WeaponDef) -> bool: return String(a.id) < String(b.id))


static func _load_dir(dir: String, into: Array[WeaponDef]) -> void:
	for file in ResourceLoader.list_directory(dir):
		if not file.ends_with(".tres"):
			continue
		var path := dir + file
		var w := load(path) as WeaponDef
		if w == null:
			push_error("%s is not a WeaponDef" % path)
			continue
		if String(w.id) != file.get_basename():
			push_error("%s: id %s is not its file's name" % [path, w.id])
			continue
		if _by_id.has(w.id):
			push_error("%s: id %s is taken" % [path, w.id])
			continue
		_by_id[w.id] = w
		into.append(w)


static func _load_items() -> void:
	for file in ResourceLoader.list_directory(ITEM_DIR):
		if not file.ends_with(".tres"):
			continue
		var path := ITEM_DIR + file
		var it := load(path) as ItemDef
		if it == null:
			push_error("%s is not an ItemDef" % path)
			continue
		if String(it.id) != file.get_basename():
			push_error("%s: id %s is not its file's name" % [path, it.id])
			continue
		_item_by_id[it.id] = it
		_items.append(it)
	_items.sort_custom(func(a: ItemDef, b: ItemDef) -> bool: return String(a.id) < String(b.id))
