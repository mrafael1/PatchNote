extends Node
## Autoload "GenreDB" (PLAN v5 1.1). Finds every genre under res://genres/<id>/genre.tres,
## like MutationDB: ResourceLoader.list_directory (works in an exported build), sorted
## by id because that listing has no guaranteed order. It loads before RunState and
## MutationDB, which read it (the run's default genre, the take files); MutationDB
## checks that no patch id is also a genre id.

const DIR := "res://genres/"

var all: Array[GenreDef] = []
var _by_id := {}


func _ready() -> void:
	reload()
	print(summary_line())


func summary_line() -> String:
	var ids: Array[String] = []
	for g in all:
		ids.append(String(g.id) + ("" if g.playable else " (MOCKUP)"))
	return "[genres] %d: %s" % [all.size(), ", ".join(ids)]


func reload() -> void:
	all.clear()
	_by_id.clear()
	for entry in ResourceLoader.list_directory(DIR):
		if not entry.ends_with("/"):
			continue
		var path := DIR + entry + "genre.tres"
		if not ResourceLoader.exists(path):
			continue
		var g := load(path) as GenreDef
		if g == null:
			push_error("Genre at %s is not a GenreDef" % path)
			continue
		if String(g.id) + "/" != entry:
			push_error("Genre id '%s' does not match its folder %s" % [g.id, entry])
			continue
		_add(g)
	_sort()
	for g in all:
		for problem in problems(g):
			push_error(problem)


func get_genre(id: StringName) -> GenreDef:
	return _by_id.get(id)


## The genre a run starts in when nothing chose one: the first Playable genre by id.
func default_id() -> StringName:
	for g in all:
		if g.playable:
			return g.id
	return &""


func playable_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for g in all:
		if g.playable:
			out.append(g.id)
	return out


## For tests: add a genre that does not live on disk.
func register(g: GenreDef) -> void:
	_add(g)
	_sort()


func unregister(g: GenreDef) -> void:
	all.erase(g)
	_by_id.erase(g.id)


func problems(g: GenreDef) -> Array[String]:
	var out: Array[String] = []
	if g.id == &"":
		out.append("A genre has no id")
	if g.genre_script == null:
		out.append("Genre '%s' has no genre_script" % g.id)
	return out


func _add(g: GenreDef) -> void:
	if _by_id.has(g.id):
		push_error("Duplicate genre id '%s'" % g.id)
		return
	all.append(g)
	_by_id[g.id] = g


func _sort() -> void:
	all.sort_custom(func(a: GenreDef, b: GenreDef) -> bool: return String(a.id) < String(b.id))
