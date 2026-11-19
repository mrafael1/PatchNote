extends Node
## Autoload "MutationDB" (PLAN 2.6). Finds every mutation under res://mutations/.
## Uses ResourceLoader.list_directory so it also works in an exported build, and
## sorts by id because that listing has no guaranteed order.

const DIR := "res://mutations/"

var all: Array[Mutation] = []
var _by_id := {}


func _ready() -> void:
	reload()
	var ids: Array[String] = []
	for m in all:
		ids.append(String(m.id))
	print("[mutations] %d: %s" % [all.size(), ", ".join(ids)])


func reload() -> void:
	all.clear()
	_by_id.clear()
	for path in _collect(DIR):
		var res := load(path)
		if res is Mutation:
			_add(res as Mutation, path)
	_sort()
	_validate_references()


func get_mutation(id: StringName) -> Mutation:
	return _by_id.get(id)


## For tests and tools: add a mutation that does not live on disk.
func register(m: Mutation) -> void:
	_add(m, "")
	_sort()


func unregister(m: Mutation) -> void:
	all.erase(m)
	_by_id.erase(m.id)


func _collect(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in ResourceLoader.list_directory(dir):
		if entry.ends_with("/"):
			out.append_array(_collect(dir + entry))
		elif entry.ends_with(".tres"):
			out.append(dir + entry)
	return out


func _add(m: Mutation, path: String) -> void:
	if m.id == &"":
		push_error("Mutation at %s has no id" % path)
		return
	if path != "" and path.get_file().get_basename() != String(m.id):
		push_error("Mutation id '%s' does not match its file name %s" % [m.id, path])
		return
	if _by_id.has(m.id):
		push_error("Duplicate mutation id '%s'" % m.id)
		return
	all.append(m)
	_by_id[m.id] = m


func _sort() -> void:
	all.sort_custom(func(a: Mutation, b: Mutation) -> bool: return String(a.id) < String(b.id))


func _validate_references() -> void:
	for m in all:
		for problem in problems(m):
			push_error(problem)


## What is wrong with m against the loaded pool (empty when it is valid).
func problems(m: Mutation) -> Array[String]:
	var out: Array[String] = []
	if m.is_big and not (m.requires.is_empty() and m.conflicts.is_empty()):
		out.append("Big mutation '%s' must have no requires and no conflicts" % m.id)
	for ref in m.requires + m.conflicts:
		if not _by_id.has(ref):
			out.append("Mutation '%s' references unknown id '%s'" % [m.id, ref])
	return out
