extends Node
## Autoload "ChangeDB" (PLAN v5 1.6). Finds every Change under res://devsession/changes/,
## like MutationDB: ResourceLoader.list_directory, sorted by id. Loads after MutationDB,
## whose patch ids a change may unlock. v5's chain of changes ships with M29; until then
## the folder may be empty or missing.

const DIR := "res://devsession/changes/"

var all: Array[Change] = []
var _by_id := {}


func _ready() -> void:
	reload()
	print(summary_line())


func summary_line() -> String:
	var ids: Array[String] = []
	for c in all:
		ids.append(String(c.id))
	return "[changes] %d: %s" % [all.size(), ", ".join(ids)]


func reload() -> void:
	all.clear()
	_by_id.clear()
	if DirAccess.dir_exists_absolute(DIR):
		for entry in ResourceLoader.list_directory(DIR):
			if not entry.ends_with(".tres"):
				continue
			var c := load(DIR + entry) as Change
			if c == null:
				push_error("Change at %s is not a Change" % (DIR + entry))
				continue
			if entry.get_basename() != String(c.id):
				push_error("Change id '%s' does not match its file name %s" % [c.id, entry])
				continue
			_add(c)
	_sort()
	for c in all:
		for problem in problems(c):
			push_error(problem)


func get_change(id: StringName) -> Change:
	return _by_id.get(id)


## For tests: add a change that does not live on disk.
func register(c: Change) -> void:
	_add(c)
	_sort()


func unregister(c: Change) -> void:
	all.erase(c)
	_by_id.erase(c.id)


## What is wrong with c against the loaded changes, patches and genres (empty = valid).
func problems(c: Change) -> Array[String]:
	var out: Array[String] = []
	if c.id == &"":
		out.append("A change has no id")
	if not c.kind in Change.KINDS:
		out.append("Change '%s' has an unknown kind '%s'" % [c.id, c.kind])
	if c.bump != GameVersion.PATCH and c.bump != GameVersion.MINOR:
		out.append("Change '%s' has an unknown bump '%s'" % [c.id, c.bump])
	if c.genre != &"" and GenreDB.get_genre(c.genre) == null:
		out.append("Change '%s' names an unknown genre '%s'" % [c.id, c.genre])
	for req in c.requires:
		if not _by_id.has(req):
			out.append("Change '%s' requires unknown change '%s'" % [c.id, req])
	for u in c.unlocks:
		var m := MutationDB.get_mutation(u)
		if m != null:
			if m.parked:
				out.append("Change '%s' unlocks the parked patch '%s'" % [c.id, u])
		elif not u in Unlocks.ARCHETYPES and not u in Unlocks.BASICS:
			out.append("Change '%s' unlocks '%s', which is neither a patch nor an enemy" % [c.id, u])
	if c.is_mockup():
		if c.takes.size() != 3:
			out.append("Mockup change '%s' has %d takes, not 3" % [c.id, c.takes.size()])
		for t in c.takes:
			if t == null or t.image == null:
				out.append("Mockup change '%s' has a take with no image" % c.id)
	if _in_cycle(c):
		out.append("Change '%s' is in a requires cycle" % c.id)
	return out


func _in_cycle(start: Change) -> bool:
	var seen := {}
	var todo: Array[StringName] = start.requires.duplicate()
	while not todo.is_empty():
		var id: StringName = todo.pop_back()
		if id == start.id:
			return true
		if seen.has(id):
			continue
		seen[id] = true
		var c: Change = _by_id.get(id)
		if c != null:
			todo.append_array(c.requires)
	return false


func _add(c: Change) -> void:
	if _by_id.has(c.id):
		push_error("Duplicate change id '%s'" % c.id)
		return
	all.append(c)
	_by_id[c.id] = c


func _sort() -> void:
	all.sort_custom(func(a: Change, b: Change) -> bool: return String(a.id) < String(b.id))
