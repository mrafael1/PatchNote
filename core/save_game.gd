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
##
## Schema 2 (PLAN v8 1.2): the campaign (which session is next, the attempts, the
## events seen, the mascot) and the settings. A schema-1 file (v5/v6, the run loop) is
## moved aside as save.v1.json and a new campaign starts (last_load OLD).

const DEFAULT_PATH := "user://save/save.json"
const SCHEMA := 2
## Old change ids and what they became (PLAN v6 1.1); %s is the save's look take.
const RENAMED := {"look_1": "look_1_%s"}
const LOOK_PREFIX := "look:"   ## taste ids that name a look take, not a patch
## A genre's maturity steps (ROADMAP 1.3); v5 uses only the first two.
const STEPS: Array[String] = ["mockup", "playable", "stages", "boss", "deep"]

## How the last load went: new (no file), loaded, corrupt, newer, or inert (no load).
const LOADED := &"loaded"
const NEW := &"new"
const CORRUPT := &"corrupt"
const NEWER := &"newer"
const INERT := &"inert"
const OLD := &"old"   ## a schema-1 file was moved aside (save.v1.json)

static var save_path := DEFAULT_PATH
static var persist := false       ## writes go to save_path
static var unlock_all := true     ## everything counts as shipped (Unlocks)
static var read_only := false     ## the file on disk is from a newer build
static var last_load: StringName = INERT
static var data := {}   ## read through state(): filled on first use, once GenreDB exists
## M47 (PLAN v9 2, D17): replay-as-path. While non-empty the game plays a deep copy of the
## save in memory (never written); it holds the mode to restore exactly (end_replay).
static var _replay := {}


## The current state (a new save until something loads or resets it).
static func state() -> Dictionary:
	if data.is_empty():
		data = new_state()
	return data


# --- Modes -------------------------------------------------------------------

## The real game: read path (default: the real save) and write to it from now on.
## fresh starts from a new save, whatever the file holds (bot --fresh --keep-save).
static func go_live(path := DEFAULT_PATH, fresh := false) -> void:
	_replay = {}   # M47: a mode change ends any replay
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
	_replay = {}   # M47: a mode change ends any replay
	persist = false
	unlock_all = false
	save_path = path if path != "" else DEFAULT_PATH
	if fresh or path == "":
		_use(new_state(), NEW)
	else:
		load_file()


## Back to the default: inert, everything unlocked, the real path, a new save in memory.
static func go_inert() -> void:
	_replay = {}   # M47: a mode change ends any replay
	save_path = DEFAULT_PATH
	persist = false
	unlock_all = true
	_use(new_state(), INERT)


## M47: is a replay-as-path playing (the copy in memory)?
static func in_replay() -> bool:
	return not _replay.is_empty()


## M47 (D17): from now on the game plays a deep copy of the save, never written, with
## `fork_id` answered by `change_id` in memory and no version bump (ship() would bump).
## The current mode (persist, unlock_all, path, data, last load) is stored for end_replay().
static func begin_replay(fork_id: StringName, change_id: StringName) -> void:
	if in_replay():
		return
	_replay = {"persist": persist, "unlock_all": unlock_all, "save_path": save_path, "data": state(),
			"last_load": last_load, "read_only": read_only}
	data = state().duplicate(true)
	persist = false
	var f := ChangeDB.get_fork(fork_id)
	if f != null:
		for c in f.changes():
			(state().shipped as Array).erase(String(c.id))
	if not has_shipped(change_id):
		(state().shipped as Array).append(String(change_id))


## M47 (D17): back to exactly the stored mode and state (never a load from disk). Settings
## changed during the replay (reduce flashing...) are kept, and written only if the restored
## mode persists.
static func end_replay() -> void:
	if not in_replay():
		return
	var settings: Dictionary = (state().get("settings", {}) as Dictionary).duplicate(true)
	persist = bool(_replay.persist)
	unlock_all = bool(_replay.unlock_all)
	save_path = String(_replay.save_path)
	data = _replay.data
	last_load = _replay.last_load
	read_only = bool(_replay.read_only)
	_replay = {}
	var changed: bool = settings != state().get("settings", {})
	state().settings = settings
	if changed and persist:
		write()


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
		"campaign": new_campaign(),
		"settings": {"reduce_flashing": false, "asked": false},
	}


## The campaign's part of a new save (PLAN v8 1.2): the next session's index, the
## sessions done, attempts per session id, scripted events seen, the mascot (a body id,
## "" until fork_mascot is answered). PLAN v9 1.14 (M43, schema still 2): `next`, the
## next session's id ("" = after the furthest done; CampaignDB.current_index()); `index`
## stays as its derived mirror. An M42.2 file has no `next` key (parse keeps it absent).
static func new_campaign() -> Dictionary:
	return {"index": 0, "done": [], "attempts": {}, "events_seen": [], "mascot": "", "next": ""}


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
## session (DevSession) calls this, then logs the session and writes. Returns false if it was
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


## Takes a change back out of the save (PLAN v6 1.3, a rework): no bump of its own,
## the rework's ship bumps. False if it was not shipped.
static func unship(id: StringName) -> bool:
	if not has_shipped(id):
		return false
	(state().shipped as Array).erase(String(id))
	return true


# --- The campaign (PLAN v8) -----------------------------------------------------

static func campaign() -> Dictionary:
	return state().campaign


## One more attempt at session `id` (a death, then Retry). Writes.
static func count_attempt(id: StringName) -> void:
	var a: Dictionary = campaign().attempts
	a[String(id)] = int(a.get(String(id), 0)) + 1
	write()


## Attempts at session `id` that ended (deaths retried); the current one is this + 1.
static func attempts(id: StringName) -> int:
	return int((campaign().attempts as Dictionary).get(String(id), 0))


## Session `id` is done: the version bumps once by `bump`, `ships` go into `shipped`
## (no bump of their own), the save points at the next session (next_after, "" after the
## last; index_after is its index mirror, from CampaignDB, which knows the order), and the
## save is written. A session already done never bumps twice (a replayed debug jump).
static func campaign_done(id: StringName, bump: StringName, ships: Array[StringName], index_after: int,
		next_after: StringName) -> void:
	var c := campaign()
	if not String(id) in (c.done as Array):
		(c.done as Array).append(String(id))
		var v := version()
		if v.bump(bump):
			state().version = v.to_array()
	for s in ships:
		if not has_shipped(s):
			(state().shipped as Array).append(String(s))
	c.index = index_after
	c["next"] = String(next_after)
	write()


## The next session (its index mirror and id) without finishing anything (debug jumps,
## --session).
static func set_campaign_position(index: int, next: StringName) -> void:
	campaign().index = maxi(0, index)
	campaign()["next"] = String(next)


static func set_mascot(id: StringName) -> void:
	campaign().mascot = String(id)


static func mascot() -> StringName:
	return StringName(campaign().mascot)


static func event_seen(id: StringName) -> bool:
	return String(id) in (campaign().events_seen as Array)


static func mark_event_seen(id: StringName) -> void:
	if not event_seen(id):
		(campaign().events_seen as Array).append(String(id))


## The "reduce flashing" setting (PLAN v8 1.9): half shake, no white screen flash, the
## gentle variants of photosensitive edits and events.
static func reduce_flashing() -> bool:
	return bool((state().settings as Dictionary).get("reduce_flashing", false))


static func setting(key: String) -> Variant:
	return (state().settings as Dictionary).get(key)


## A setting (reduce_flashing; asked once it was answered at first launch). Writes.
static func set_setting(key: String, value: Variant) -> void:
	(state().settings as Dictionary)[key] = value
	write()


## A genre's maturity step (STEPS), e.g. "stages" once the Stages take ships (M35).
static func set_genre_step(genre: StringName, step: String) -> void:
	if not step in STEPS:
		return
	var key := String(genre)
	var d := state()
	if not d.genres.has(key):
		var def := GenreDB.get_genre(genre)
		d.genres[key] = _new_genre(def) if def else {"step": "playable", "runs": 0, "play_time": 0.0}
	(d.genres[key] as Dictionary).step = step


## The look a shipped look take sets (PLAN v5 1.7): {tier, take}. Written with the
## session (finish_session).
static func set_look(tier: int, take: StringName) -> void:
	state().look = {"tier": tier, "take": String(take)}


## The dev session is done: log it, keep the taste it ended with (when given), clear
## pending_session, write.
static func finish_session(entry: Dictionary, taste := {}) -> void:
	(state().sessions as Array).append(entry)
	if not taste.is_empty():
		state().taste = _clean_taste(taste)
	state().pending_session = false
	write()


## Dev sessions logged so far (the next one is number session_count() + 1).
static func session_count() -> int:
	return (state().sessions as Array).size()


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
	if parsed is Dictionary and (parsed as Dictionary).has("schema") and _schema_of(parsed) < SCHEMA:
		_move_aside_old()
		_use(new_state(), OLD)
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
	# shipped: known change ids, once each, in order. A v5 save's "look_1" (one change
	# with 3 takes) is now the option of the look_1 fork named after the save's take.
	var shipped: Array = []
	for raw: Variant in out.shipped:
		if not raw is String:
			return null
		var id: String = raw
		if RENAMED.has(id):
			var take: Variant = (out.look as Dictionary).get("take", "")
			id = String(RENAMED[id]) % (take if take is String and take != "" else "punchy")
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
	var camp: Variant = _parse_campaign(out.campaign)
	if camp == null:
		return null
	out.campaign = camp
	var settings: Dictionary = {"reduce_flashing": false, "asked": false}
	for k: String in settings:
		if (out.settings as Dictionary).has(k):
			if not out.settings[k] is bool:
				return null
			settings[k] = out.settings[k]
	# M47.3 (PLAN 1.16): the Settings keys, sparse; a wrong one reads as its default.
	settings.merge(Settings.parse(out.settings))
	out.settings = settings
	return out


## The campaign block, clean, or null on a wrong type. Missing keys take defaults.
static func _parse_campaign(src: Dictionary) -> Variant:
	var out := new_campaign()
	# `next` only when the file has it: an M42.2 file without it maps its index (CampaignDB).
	out.erase("next")
	if src.has("next"):
		if not src.next is String:
			return null
		out["next"] = src.next
	if src.has("index"):
		if not _is_number(src.index) or int(src.index) < 0:
			return null
		out.index = int(src.index)
	for key: String in ["done", "events_seen"]:
		if src.has(key):
			if not src[key] is Array:
				return null
			for x: Variant in src[key]:
				if not x is String:
					return null
				if not x in out[key]:
					(out[key] as Array).append(x)
	if src.has("attempts"):
		if not src.attempts is Dictionary:
			return null
		for k: Variant in src.attempts:
			if not _is_number(src.attempts[k]) or int(src.attempts[k]) < 0:
				return null
			out.attempts[String(k)] = int(src.attempts[k])
	if src.has("mascot"):
		if not src.mascot is String:
			return null
		out.mascot = src.mascot
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


## A schema-1 save (the v5/v6 run loop) -> save.v1.json, replacing an older one. Only
## when persist: a snapshot read never moves a file.
static func _move_aside_old() -> void:
	push_warning("Save %s is from the prototype run loop (schema 1): kept aside, starting a new campaign" % save_path)
	if not persist:
		return
	var old := old_path()
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)
	DirAccess.rename_absolute(save_path, old)


static func old_path() -> String:
	return save_path.get_basename() + ".v1." + save_path.get_extension()


static func bad_path() -> String:
	return save_path.get_basename() + ".bad." + save_path.get_extension()
