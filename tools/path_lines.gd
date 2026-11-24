extends SceneTree
## Path-only lines (PLAN v9 1.5, 0.4): each path's own code is countable against its budget
## of 250 lines. Path-only code lives under res://paths/<id>/ or carries a "# path:<id>"
## header line; a line counts when it is not blank and not a comment. Shared path code
## (paths/*.gd at the top, PathRunner, PickOffer, Pickup) does not count.
##
##   godot --headless --path . -s tools/path_lines.gd
##
## Prints "[path_lines] arsenal=N auto=N survival=0 budget=250" and exits 1 over budget
## (Arsenal since M46: paths/arsenal/; Survival since M47: paths/survival/, built there
## instead of PLAN 1.6's systems/drops.gd so it counts, D11).

const BUDGET := 250
const PATHS: Array[String] = ["arsenal", "auto", "survival"]


func _initialize() -> void:
	var counts := {}
	for p in PATHS:
		counts[p] = 0
	var seen := {}
	for p in PATHS:
		for f in _scripts("res://paths/%s/" % p):
			seen[f] = true
			counts[p] += _count(f)
	for f in _scripts("res://"):
		if seen.has(f):
			continue
		var text := FileAccess.get_file_as_string(f)
		for p in PATHS:
			if text.contains("\n# path:%s\n" % p) or text.begins_with("# path:%s\n" % p) \
					or text.contains("\n# path:%s\r\n" % p):
				counts[p] += _count(f)
	var parts: Array[String] = []
	var over := false
	for p in PATHS:
		parts.append("%s=%d" % [p, counts[p]])
		over = over or int(counts[p]) > BUDGET
	print("[path_lines] %s budget=%d%s" % [" ".join(parts), BUDGET, " OVER" if over else ""])
	quit(1 if over else 0)


func _count(path: String) -> int:
	var n := 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var s := line.strip_edges()
		if s != "" and not s.begins_with("#"):
			n += 1
	return n


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for entry in DirAccess.get_directories_at(dir):
		if entry.begins_with(".") or entry in ["addons", "builds", ".godot"]:
			continue
		out.append_array(_scripts(dir.path_join(entry) + "/"))
	for entry in DirAccess.get_files_at(dir):
		if entry.ends_with(".gd"):
			out.append(dir.path_join(entry))
	return out
