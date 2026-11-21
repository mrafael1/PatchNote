extends Node
## Autoload "MutationDB" (PLAN 2.6). Finds every mutation under res://mutations/.
## Uses ResourceLoader.list_directory so it also works in an exported build, and
## sorts by id because that listing has no guaranteed order. For each card it builds
## one take per genre that has a file next to it (mutations/<id>/<genre>.gd, PLAN v5 1.2).

const DIR := "res://mutations/"

var all: Array[Mutation] = []
var _by_id := {}


func _ready() -> void:
	reload()
	print(summary_line())


## The boot line the export check reads: every id, big patches marked "(BIG)",
## mediums "(MED)" and boss-only patches "(BOSS)", then parked ones "(PARKED)".
func summary_line() -> String:
	var ids: Array[String] = []
	for m in all:
		ids.append(String(m.id) + _mark(m))
	return "[mutations] %d: %s" % [all.size(), ", ".join(ids)]


func _mark(m: Mutation) -> String:
	var mark := ""
	if m.is_big:
		mark = " (BIG)"
	elif m.is_medium:
		mark = " (MED)"
	elif m.boss_only:
		mark = " (BOSS)"
	return mark + (" (PARKED)" if m.parked else "")


## Patches the game may offer or ship: every loaded one that is not parked (PLAN v5 1.3).
func offerable() -> Array[Mutation]:
	var out: Array[Mutation] = []
	for m in all:
		if not m.parked:
			out.append(m)
	return out


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
	if path != "":
		_build_takes(m, path.get_base_dir())


## One take per genre with a file in dir. Cards are cached for the life of the process,
## so a reload keeps the takes it built first (and any bot --set values on them).
func _build_takes(m: Mutation, dir: String) -> void:
	if not m.takes.is_empty():
		return
	for g in GenreDB.all:
		var path := "%s/%s.gd" % [dir, g.id]
		if not ResourceLoader.exists(path):
			continue
		var take := (load(path) as Script).new() as PatchTake
		if take == null:
			push_error("Take %s does not extend PatchTake" % path)
			continue
		take.patch = m
		take.id = m.id
		take.genre = g.id
		m.takes[g.id] = take


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
	if int(m.is_medium) + int(m.boss_only) + int(m.is_big) > 1:
		out.append("Mutation '%s' sets more than one of is_medium, boss_only, is_big" % m.id)
	if GenreDB.get_genre(m.id) != null:
		out.append("Mutation id '%s' is also a genre id" % m.id)
	# PLAN v5 1.2: behaviour lives in takes. Only a parked card may keep its own script,
	# and an unparked card needs a take for every Playable genre (ROADMAP 1.4).
	if m.is_legacy():
		if m.resource_path != "" and not m.parked:
			out.append("Mutation '%s' has its own script; only a parked patch may (move it into takes)" % m.id)
	elif not m.parked:
		for g in GenreDB.playable_ids():
			if not m.takes.has(g):
				out.append("Mutation '%s' has no take for the playable genre '%s'" % [m.id, g])
	if m.boss_only and m.boss_weight <= 0.0:
		out.append("Boss-only mutation '%s' needs a boss_weight above 0" % m.id)
	for ref in m.requires + m.conflicts:
		if not _by_id.has(ref):
			out.append("Mutation '%s' references unknown id '%s'" % [m.id, ref])
	# AI-tier patches may require only mediums; a small may not require an AI-tier
	# patch, or a stage end would drop the player's pick (PLAN v4 1.1).
	for ref in m.requires:
		var other: Mutation = _by_id.get(ref)
		if other == null:
			continue
		if m.is_ai_tier() and not other.is_medium:
			out.append("AI-tier mutation '%s' may require only mediums, not '%s'" % [m.id, ref])
		elif not m.is_ai_tier() and not m.is_big and other.is_ai_tier():
			out.append("Small mutation '%s' may not require AI-tier '%s'" % [m.id, ref])
	return out
