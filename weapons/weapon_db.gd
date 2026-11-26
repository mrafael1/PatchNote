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
##
## M50.4c1 (Auto depth design 5): the evolved weapons live in weapons/evolutions/<id>.tres and
## load into their own list (evolutions(), evolution_for()); get_weapon() / has() resolve them
## like the fusions, all() / ids() stay the base weapons. evolution_problems() checks the rows.

const DIR := "res://weapons/"
const FUSION_DIR := "res://weapons/fusions/"
const ITEM_DIR := "res://weapons/items/"
const EVO_DIR := "res://weapons/evolutions/"

static var _by_id := {}
static var _all: Array[WeaponDef] = []
static var _fusions: Array[WeaponDef] = []
static var _evolutions: Array[WeaponDef] = []
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


## M50.4c1: the evolved weapons, sorted by id (built or not).
static func evolutions() -> Array[WeaponDef]:
	_load()
	return _evolutions.duplicate()


## M50.4c1: the evolution of base weapon `weapon_id` (&"" for none; built or not).
static func evolution_for(weapon_id: StringName) -> StringName:
	_load()
	for e in _evolutions:
		if e.base == weapon_id:
			return e.id
	return &""


## M50.4c1: an evolution that plays (its row is built).
static func evolution_built(id: StringName) -> bool:
	var e := get_weapon(id)
	return e != null and e.is_evolution() and e.built_in == ""


## M50.4c1: every evolution's problems. Its base is a base weapon, its catalyst an item that
## pairs with it; a built one's catalyst is a built item, and its `mechanics` are the base's
## three plus a built signature. An unbuilt row gives its one "not built yet" line.
static func evolution_problems() -> Array[String]:
	_load()
	var out: Array[String] = []
	for e in _evolutions:
		out.append_array(e.problems())
		var b := get_weapon(e.base)
		if b == null or b.is_fusion() or b.is_evolution():
			out.append("evolution %s: base %s is not a base weapon" % [e.id, e.base])
			continue
		var it := item(e.catalyst)
		if it == null:
			out.append("evolution %s: catalyst %s is not an item" % [e.id, e.catalyst])
			continue
		if it.pairs != e.base:
			out.append("evolution %s: %s pairs with %s, not %s" % [e.id, e.catalyst, it.pairs, e.base])
		if e.built_in != "":
			continue
		if not it.built():
			out.append("evolution %s: its catalyst %s is %s" % [e.id, e.catalyst, it.built_in])
		var mech := WeaponCurve.mechanics(b)
		if e.mechanics.size() != mech.size() + 1 or e.mechanics.slice(0, mech.size()) != mech:
			out.append("evolution %s: mechanics must be %s's %s plus a signature" % [e.id, b.id, mech])
		elif not WeaponCurve.built(e.mechanics[e.mechanics.size() - 1]):
			out.append("evolution %s: its signature %s is not built" % [e.id, e.mechanics[e.mechanics.size() - 1]])
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
	_evolutions.clear()
	_items.clear()
	_item_by_id.clear()
	_load_dir(DIR, _all)
	_load_dir(FUSION_DIR, _fusions)
	_load_dir(EVO_DIR, _evolutions)
	_load_items()
	_all.sort_custom(func(a: WeaponDef, b: WeaponDef) -> bool: return String(a.id) < String(b.id))
	_fusions.sort_custom(func(a: WeaponDef, b: WeaponDef) -> bool: return String(a.id) < String(b.id))
	_evolutions.sort_custom(func(a: WeaponDef, b: WeaponDef) -> bool: return String(a.id) < String(b.id))


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
