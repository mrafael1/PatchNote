class_name SaveGame
extends RefCounted
## The save (PLAN v5 1.5): the game's version, what shipped, the look, genre play and
## the player's taste. Static state, like Telemetry.
##
## Inert by default: `persist = false` and `unlock_all = true`, the file is never read or
## written, and everything counts as shipped. Only the start screen (a read-only peek
## when it opens, go_live when it starts a game or resets) and tools/bot_runs.gd
## --save / --fresh change that, so GUT, main.tscn booted directly, check.ps1's boots
## (--inert-save) and the export's --autostart boot never touch the real file.
##
## Reading: a missing file is a new save (nothing written until a run ends); a missing
## key takes its default; a corrupt file (bad JSON or a wrong type) is renamed to
## save.bad.json with a warning (never an error: check.ps1 fails on "ERROR:") and play
## goes on from a new save; a file from a newer build (higher schema) is used read-only
## as a new save and never overwritten; unknown genres, changes and taste ids are
## dropped. Writing is atomic: a .tmp file, then a rename.

const DEFAULT_PATH := "user://save/save.json"
const SCHEMA := 1
const LOOK_PREFIX := "look:"   ## taste ids that name a look take, not a patch
## A genre's maturity steps (ROADMAP 1.3); v5 uses only the first two.
const STEPS: Array[String] = ["mockup", "playable", "stages", "boss", "deep"]

## How the last load went: new (no file), loaded, corrupt, newer, or inert (no load).
const LOADED := &"loaded"
const NEW := &"new"
const CORRUPT := &"corrupt"
const NEWER := &"newer"
const INERT := &"inert"

static var save_path := DEFAULT_PATH
static var persist := false       ## writes go to save_path
static var unlock_all := true     ## everything counts as shipped (Unlocks)
static var read_only := false     ## the file on disk is from a newer build
static var last_load: StringName = INERT
static var data := {}   ## read through state(): filled on first use, once GenreDB exists


## The current state (a new save until something loads or resets it).
static func state() -> Dictionary:
	if data.is_empty():
		data = new_state()
	return data


# --- Modes -------------------------------------------------------------------

## The real game: read path (default: the real save) and write to it from now on.
## fresh starts from a new save, whatever the file holds (bot --fresh --keep-save).
static func go_live(path := DEFAULT_PATH, fresh := false) -> void:
	save_path = path
	persist = true
	unlock_all = false
	if fresh:
		_use(new_state(), NEW)
	else:
		load_file()


## A read-only snapshot (bot runs without --keep-save): every run sees the same state
## and nothing is written. An empty path or fresh means a new save in memory.
static func use_snapshot(path := "", fresh := false) -> void:
	persist = false
	unlock_all = false
	save_path = path if path != "" else DEFAULT_PATH
	if fresh or path == "":
		_use(new_state(), NEW)
	else:
		load_file()


## Back to the default: inert, everything unlocked, the real path, a new save in memory.
static func go_inert() -> void:
	save_path = DEFAULT_PATH
	persist = false
	unlock_all = true
	_use(new_state(), INERT)


static func _use(state: Dictionary, how: StringName) -> void:
	data = state
	last_load = how
	read_only = how == NEWER


# --- The state -----------------------------------------------------------------

## A new save: v0.0.0, nothing shipped, look tier 0, every listed genre at its step.
static func new_state() -> Dictionary:
	var genres := {}
	for g: GenreDef in GenreDB.all:
		genres[String(g.id)] = _new_genre(g)
	return {
		"schema": SCHEMA,
		"version": [0, 0, 0],
		"runs": 0,
		"wins": 0,
		"genres": genres,
		"shipped": [],
		"look": {"tier": 0, "take": ""},
		"taste": {"by_id": {}, "by_tag": {}},
		"sessions": [],
		"pending_session": false,
	}


static func _new_genre(g: GenreDef) -> Dictionary:
	return {"step": "playable" if g.playable else "mockup", "runs": 0, "play_time": 0.0}


static func version() -> GameVersion:
	return GameVersion.from_array(state().version)


static func shipped() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in state().shipped:
		out.append(StringName(id))
	return out


static func has_shipped(id: StringName) -> bool:
	return String(id) in state().shipped


static func genre_entry(id: StringName) -> Dictionary:
	return state().genres.get(String(id), {})


## Live and writable: the run's taste comes from (and goes to) the save. A newer
## build's file is live but read-only, so taste falls back to the session carry.
static func is_live() -> bool:
	return persist and not read_only


## A reset is refused on a newer build's file.
static func can_reset() -> bool:
	return not read_only


# --- Changes ---------------------------------------------------------------------

## A finished run of a live game: runs, wins, the genre's runs and play time (real
## seconds, so slow motion and hit stop do not shrink it), the run's taste, and a dev
## session now pending. Writes when persist. Returns whether anything changed.
static func record_run(genre: StringName, outcome: StringName, play_seconds: float, taste: Dictionary) -> bool:
	if not persist or read_only:
		return false
	var d := state()
	d.runs = int(d.runs) + 1
	if outcome == &"win":
		d.wins = int(d.wins) + 1
	var key := String(genre)
	if not d.genres.has(key):
		var def := GenreDB.get_genre(genre)
		d.genres[key] = _new_genre(def) if def else {"step": "playable", "runs": 0, "play_time": 0.0}
	var entry: Dictionary = d.genres[key]
	entry.runs = int(entry.runs) + 1
	entry.play_time = snappedf(float(entry.play_time) + play_seconds, 0.001)
	d.taste = _clean_taste(taste)
	d.pending_session = true
	write()
	return true


## The player's taste after the report's ratings (live only).
static func set_taste(taste: Dictionary) -> void:
	if not persist or read_only:
		return
	state().taste = _clean_taste(taste)
	write()


## Ships a change: adds it to `shipped` (once) and bumps the version by kind. The dev
## session (M29) calls this, then logs the session and writes. Returns false if it was
## already shipped or the kind is unknown.
static func ship(id: StringName, bump: StringName) -> bool:
	if has_shipped(id):
		return false
	var v := version()
	if not v.bump(bump):
		return false
	(state().shipped as Array).append(String(id))
	state().version = v.to_array()
	return true


## The dev session is done: log it, clear pending_session, write.
static func finish_session(entry: Dictionary) -> void:
	(state().sessions as Array).append(entry)
	state().pending_session = false
	write()


## The start screen's "Reset save": a new save, written at once when live.
static func reset() -> bool:
	if read_only:
		return false
	_use(new_state(), NEW if persist else last_load)
	if persist:
		write()
	return true


# --- Disk ------------------------------------------------------------------------

## Reads save_path into data (see the header for every case).
static func load_file() -> void:
	if not FileAccess.file_exists(save_path):
		_use(new_state(), NEW)
		return
	var text := FileAccess.get_file_as_string(save_path)
	# JSON.parse (not parse_string, which logs an ERROR: line on bad input).
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if parsed is Dictionary and _schema_of(parsed) > SCHEMA:
		push_warning("Save %s is from a newer build (schema %d): read-only" % [save_path, _schema_of(parsed)])
		_use(new_state(), NEWER)
		return
	var state: Variant = parse(parsed)
	if state == null:
		_quarantine()
		_use(new_state(), CORRUPT)
		return
	_use(state, LOADED)


static func _schema_of(d: Dictionary) -> int:
	var s: Variant = d.get("schema", SCHEMA)
	return int(s) if (s is int or s is float) else SCHEMA


## A parsed JSON value as a clean state, or null if it is not a save (a wrong type
## anywhere). Missing keys take their defaults; unknown ids are dropped.
static func parse(parsed: Variant) -> Variant:
	if not parsed is Dictionary:
		return null
	var src := parsed as Dictionary
	var out := new_state()
	for key: String in out:
		if not src.has(key):
			continue
		var value: Variant = src[key]
		var default: Variant = out[key]
		if _is_number(default):
			if not _is_number(value):
				return null
			out[key] = int(value)
		elif typeof(value) != typeof(default):
			return null
		else:
			out[key] = value
	if GameVersion.from_array(out.version).to_array() != _ints(out.version):
		return null
	out.version = GameVersion.from_array(out.version).to_array()
	# genres: known ids only, every listed genre present.
	var genres: Dictionary = new_state().genres
	for id: String in (out.genres as Dictionary):
		var g: Variant = out.genres[id]
		if not g is Dictionary:
			return null
		if not genres.has(id):
			continue   # a genre removed since
		var entry: Dictionary = genres[id]
		var src_entry := g as Dictionary
		if src_entry.has("step"):
			if not src_entry.step is String or not src_entry.step in STEPS:
				return null
			entry.step = src_entry.step
		for field: String in ["runs", "play_time"]:
			if src_entry.has(field):
				if not _is_number(src_entry[field]) or float(src_entry[field]) < 0.0:
					return null
				entry[field] = int(src_entry[field]) if field == "runs" else float(src_entry[field])
	out.genres = genres
	# shipped: known change ids, once each, in order.
	var shipped: Array = []
	for id: Variant in out.shipped:
		if not id is String:
			return null
		if ChangeDB.get_change(StringName(id)) != null and not id in shipped:
			shipped.append(id)
	out.shipped = shipped
	# look
	var look: Dictionary = out.look
	if not _is_number(look.get("tier", 0)) or not look.get("take", "") is String:
		return null
	out.look = {"tier": int(look.get("tier", 0)), "take": look.get("take", "")}
	# taste
	var taste: Dictionary = out.taste
	for part: String in ["by_id", "by_tag"]:
		var scores: Variant = taste.get(part, {})
		if not scores is Dictionary:
			return null
		for k: Variant in scores:
			if not _is_number(scores[k]):
				return null
	out.taste = _clean_taste(taste)
	for s: Variant in out.sessions:
		if not s is Dictionary:
			return null
	return out


static func _is_number(v: Variant) -> bool:
	return v is int or v is float


static func _ints(a: Array) -> Array:
	return a.map(func(x: Variant) -> Variant: return int(x) if _is_number(x) else x)


## Taste with numbers only and no unknown ids: a by_id key must be a patch or a look take.
static func _clean_taste(taste: Dictionary) -> Dictionary:
	var by_id := {}
	var by_tag := {}
	var src_ids: Variant = taste.get("by_id", {})
	var src_tags: Variant = taste.get("by_tag", {})
	if src_ids is Dictionary:
		for k: Variant in src_ids:
			var id := String(k)
			if _is_number(src_ids[k]) and (id.begins_with(LOOK_PREFIX) or MutationDB.get_mutation(StringName(id)) != null):
				by_id[id] = snappedf(float(src_ids[k]), 0.001)
	if src_tags is Dictionary:
		for k: Variant in src_tags:
			if _is_number(src_tags[k]):
				by_tag[String(k)] = snappedf(float(src_tags[k]), 0.001)
	return {"by_id": by_id, "by_tag": by_tag}


## Writes data to save_path atomically (a .tmp, then a rename). Only when persist and
## not read-only.
static func write() -> Error:
	if not persist or read_only:
		return ERR_UNAVAILABLE
	var dir := save_path.get_base_dir()
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and not DirAccess.dir_exists_absolute(dir):
		push_warning("Save: cannot create %s (%s)" % [dir, error_string(err)])
		return err
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Save: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return FileAccess.get_open_error()
	var stored := f.store_string(JSON.stringify(state(), "\t") + "\n")
	err = f.get_error()
	f.close()
	if not stored or err != OK:
		# A short or failed write never replaces the good save.
		DirAccess.remove_absolute(tmp)
		push_warning("Save: writing %s failed (%s); the save is unchanged" % [tmp, error_string(err)])
		return err if err != OK else ERR_FILE_CANT_WRITE
	# Godot's rename replaces an existing file on every desktop platform.
	err = DirAccess.rename_absolute(tmp, save_path)
	if err != OK:
		push_warning("Save: cannot replace %s (%s); the new state is in %s" % [save_path, error_string(err), tmp])
	return err


## save.json -> save.bad.json, replacing an older one. Only when persist: an inert or
## snapshot read never moves a file.
static func _quarantine() -> void:
	push_warning("Save %s is corrupt: moved aside, starting a new save" % save_path)
	if not persist:
		return
	var bad := bad_path()
	if FileAccess.file_exists(bad):
		DirAccess.remove_absolute(bad)
	DirAccess.rename_absolute(save_path, bad)


static func bad_path() -> String:
	return save_path.get_basename() + ".bad." + save_path.get_extension()
