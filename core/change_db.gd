extends Node
## Autoload "ChangeDB" (PLAN v5 1.6). Finds every Change under res://devsession/changes/,
## like MutationDB: ResourceLoader.list_directory, sorted by id. Loads after MutationDB,
## whose patch ids a change may unlock. v5's chain of changes ships with M29; until then
## the folder may be empty or missing. A genre's own changes and questions (its
## maturity steps, M35) live in its folder, res://genres/<id>/devsession/changes/ and
## forks/, so the shell never names a genre; they load the same way.

const DIR := "res://devsession/changes/"
## The questions (PLAN v6 1.1): each groups 2-3 changes as alternatives.
const FORK_DIR := "res://devsession/forks/"
const GENRES_DIR := "res://genres/"
const GENRE_SUBDIR := "/devsession/"

var all: Array[Change] = []
var forks: Array[Fork] = []
var _by_id := {}
var _forks_by_id := {}


func _ready() -> void:
	reload()
	print(summary_line())


func summary_line() -> String:
	var ids: Array[String] = []
	for c in all:
		ids.append(String(c.id))
	var fork_ids: Array[String] = []
	for f in forks:
		fork_ids.append(String(f.id))
	return "[changes] %d: %s\n[forks] %d: %s" % [all.size(), ", ".join(ids), forks.size(), ", ".join(fork_ids)]


func reload() -> void:
	all.clear()
	_by_id.clear()
	for dir in _dirs(DIR, "changes/"):
		for entry in ResourceLoader.list_directory(dir):
			if not entry.ends_with(".tres"):
				continue
			var c := load(dir + entry) as Change
			if c == null:
				push_error("Change at %s is not a Change" % (dir + entry))
				continue
			if entry.get_basename() != String(c.id):
				push_error("Change id '%s' does not match its file name %s" % [c.id, entry])
				continue
			_add(c)
	_sort()
	forks.clear()
	_forks_by_id.clear()
	for dir in _dirs(FORK_DIR, "forks/"):
		for entry in ResourceLoader.list_directory(dir):
			if not entry.ends_with(".tres"):
				continue
			var f := load(dir + entry) as Fork
			if f == null or entry.get_basename() != String(f.id):
				push_error("Fork at %s is not a Fork named after its file" % (dir + entry))
				continue
			_add_fork(f)
	_link_forks()
	for c in all:
		for problem in problems(c):
			push_error(problem)
	for f in forks:
		for problem in fork_problems(f):
			push_error(problem)


## The shared folder, then each genre folder's `<sub>` (in folder name order), those that exist.
func _dirs(shared: String, sub: String) -> Array[String]:
	var out: Array[String] = []
	if DirAccess.dir_exists_absolute(shared):
		out.append(shared)
	if DirAccess.dir_exists_absolute(GENRES_DIR):
		var names := Array(DirAccess.get_directories_at(GENRES_DIR))
		names.sort()
		for g: String in names:
			var dir := GENRES_DIR + g + GENRE_SUBDIR + sub
			if DirAccess.dir_exists_absolute(dir):
				out.append(dir)
	return out


func get_fork(id: StringName) -> Fork:
	return _forks_by_id.get(id)


## The fork c answers, or null.
func fork_of(c: Change) -> Fork:
	return _forks_by_id.get(c.fork) if c != null else null


## For tests: add a fork that does not live on disk (its options must be registered).
func register_fork(f: Fork) -> void:
	_add_fork(f)
	_link_forks()


func unregister_fork(f: Fork) -> void:
	forks.erase(f)
	_forks_by_id.erase(f.id)
	_link_forks()


func _add_fork(f: Fork) -> void:
	if _forks_by_id.has(f.id) or _by_id.has(f.id):
		push_error("Duplicate id '%s' (forks and changes share one namespace)" % f.id)
		return
	forks.append(f)
	_forks_by_id[f.id] = f
	forks.sort_custom(func(a: Fork, b: Fork) -> bool: return String(a.id) < String(b.id))


## Sets Change.fork from the forks (the first fork that lists a change wins; a second
## one is reported by fork_problems).
func _link_forks() -> void:
	for c in all:
		c.fork = &""
	for f in forks:
		for o in f.options:
			var c: Change = _by_id.get(o)
			if c != null and c.fork == &"":
				c.fork = f.id


## What is wrong with fork f (empty = valid).
func fork_problems(f: Fork) -> Array[String]:
	var out: Array[String] = []
	if f.id == &"":
		out.append("A fork has no id")
	if f.options.size() < 2 or f.options.size() > 3:
		out.append("Fork '%s' has %d options, not 2 or 3" % [f.id, f.options.size()])
	if f.bump != GameVersion.PATCH and f.bump != GameVersion.MINOR:
		out.append("Fork '%s' has an unknown bump '%s'" % [f.id, f.bump])
	if f.genre != &"" and GenreDB.get_genre(f.genre) == null:
		out.append("Fork '%s' names an unknown genre '%s'" % [f.id, f.genre])
	for o in f.options:
		var c: Change = _by_id.get(o)
		if c == null:
			out.append("Fork '%s' lists unknown change '%s'" % [f.id, o])
			continue
		if c.fork != f.id:
			out.append("Change '%s' is in two forks ('%s' and '%s')" % [o, c.fork, f.id])
		if c.is_basic():
			out.append("Fork '%s' lists the basic '%s'" % [f.id, o])
		if f.mockup and (c.take == null or c.take.image == null):
			out.append("Mockup fork '%s' has an option with no still: '%s'" % [f.id, o])
	for r in f.requires_forks:
		if not _forks_by_id.has(r):
			out.append("Fork '%s' requires unknown fork '%s'" % [f.id, r])
	if _fork_in_cycle(f):
		out.append("Fork '%s' is in a requires cycle" % f.id)
	return out


func _fork_in_cycle(start: Fork) -> bool:
	var seen := {}
	var todo: Array[StringName] = start.requires_forks.duplicate()
	while not todo.is_empty():
		var id: StringName = todo.pop_back()
		if id == start.id:
			return true
		if seen.has(id):
			continue
		seen[id] = true
		var f: Fork = _forks_by_id.get(id)
		if f != null:
			todo.append_array(f.requires_forks)
	return false


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
	if c.kind == &"look" and (c.take == null or c.take.preset == null):
		out.append("Look change '%s' has no take with a preset" % c.id)
	if c.kind == &"mascot" and (c.take == null or not c.take.id in Change.MASCOTS):
		out.append("Mascot change '%s' has no take naming a body (%s)" % [c.id, Change.MASCOTS])
	if c.kind == &"stages":
		if c.take == null or not c.take.preset is StageSet:
			out.append("Stages change '%s' has no take with a stage set" % c.id)
		else:
			for p in (c.take.preset as StageSet).problems():
				out.append("Stages change '%s': %s" % [c.id, p])
		if c.genre == &"":
			out.append("Stages change '%s' names no genre" % c.id)
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
