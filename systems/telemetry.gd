class_name Telemetry
extends RefCounted
## Playtest telemetry (PLAN 8): one JSON line per finished run, appended to a file.
## Nothing in the game ever reads it back.

const DEFAULT_PATH := "user://playtest/runs.jsonl"

## Where lines go. Tools and tests point it elsewhere so they never mix with real playtests.
static var log_path := DEFAULT_PATH
## One id per process; runs in the same session share it.
static var session_id := ""
static var _runs_this_session := 0


static func session() -> String:
	if session_id == "":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		session_id = "%08x%08x" % [rng.randi(), int(Time.get_unix_time_from_system()) & 0xffffffff]
	return session_id


## The record for the run that just ended, built from RunState. extra is merged in
## (build name, bot flag, ...).
static func build_record(outcome: StringName, extra := {}) -> Dictionary:
	_runs_this_session += 1
	var events: Array[Dictionary] = []
	var prompts: Array[Dictionary] = []
	var reverts_used := 0
	var history_opens := 0
	var big_offers: Array[Dictionary] = []
	var big_swaps: Array[Dictionary] = []
	var ai_events: Array[Dictionary] = []   ## PLAN v4 9.3, early: AI layer adds and removals
	var ai_owners := {}
	for entry: Dictionary in RunState.run_log:
		match entry.event:
			&"big_prompt":
				big_offers.append({"index": entry.index, "offers": entry.offers, "agenda": entry.agenda,
						"pick": entry.pick, "keep": entry.keep, "kept": entry.kept,
						"mandatory": entry.mandatory, "time": snappedf(entry.time, 0.01)})
			&"big_prompt_skipped":
				big_offers.append({"index": entry.index, "offers": [], "agenda": [], "pick": "",
						"keep": "", "kept": false, "mandatory": false, "time": snappedf(entry.time, 0.01)})
			&"big_swap":
				big_swaps.append({"time": snappedf(entry.time, 0.01), "from": entry.from,
						"to": entry.to, "dropped": entry.dropped, "build": entry.build})
			&"apply", &"revert":
				events.append({"event": String(entry.event), "id": String(entry.id),
						"time": snappedf(entry.time, 0.01), "build": entry.build})
			&"prompt":
				prompts.append({"index": entry.index, "offers": entry.offers, "pick": entry.pick,
						"mandatory": entry.mandatory, "time": snappedf(entry.time, 0.01)})
			&"prompt_skipped":
				prompts.append({"index": entry.index, "offers": [], "pick": "",
						"mandatory": false, "time": snappedf(entry.time, 0.01)})
			&"ai_apply":
				ai_owners[String(entry.id)] = String(entry.owner)
				ai_events.append({"time": snappedf(entry.time, 0.01), "id": String(entry.id),
						"owner": String(entry.owner), "op": "add", "reason": ""})
			&"ai_remove":
				for id: String in entry.ids:
					ai_events.append({"time": snappedf(entry.time, 0.01), "id": id,
							"owner": ai_owners.get(id, ""), "op": "remove", "reason": String(entry.reason)})
			&"revert_used":
				reverts_used += 1   # AI rollbacks (option D)
			&"history_open":
				history_opens += 1
	var record := {
		"schema": 1,
		"session_id": session(),
		"run_index": _runs_this_session,
		"timestamp": Time.get_datetime_string_from_system(true),
		"seed": RunState.run_seed,
		"outcome": String(outcome),
		"duration": snappedf(RunState.game_time, 0.01),
		"real_duration": snappedf(RunState.real_time(), 0.01),
		"version": RunState.version_label(),
		"build_number": RunState.build_number,
		"game_version": SaveGame.version().label(),
		"genre": String(RunState.genre),
		"kills": RunState.kills,
		"kills_by_source": _plain(RunState.kills_by_source),
		"damage_by_source": _plain(RunState.damage_by_source),
		"events": events,
		"prompts": prompts,
		"reverts_used": reverts_used,
		"history_opens": history_opens,
		"final_stack": RunState.stack.map(func(m: Mutation) -> String: return String(m.id)),
		"final_big": String(RunState.big.id) if RunState.big else "",
		"big_offers": big_offers,
		"big_swaps": big_swaps,
		"ai_events": ai_events,
		"genre_seconds": genre_seconds(),
		"genre_hits": genre_hits(),
		"genre_hits_by_kind": genre_hits_by_kind(),
	}
	record.merge(extra)
	return record


## Game seconds spent under each big patch so far, "base" for none, in the order
## they were first entered.
static func genre_seconds() -> Dictionary:
	var out := {"base": 0.0}
	var current := "base"
	var since := 0.0
	for entry: Dictionary in RunState.run_log:
		if entry.event == &"big_swap":
			out[current] = float(out.get(current, 0.0)) + entry.time - since
			current = entry.to
			since = entry.time
	out[current] = float(out.get(current, 0.0)) + RunState.game_time - since
	for key: String in out:
		out[key] = snappedf(out[key], 0.01)
	return out


## Hits the player took under each big patch, keyed like genre_seconds. Hits an
## invincible player would have taken count too (bot runs measure difficulty that way).
static func genre_hits() -> Dictionary:
	var out := {"base": 0}
	var current := "base"
	for entry: Dictionary in RunState.run_log:
		if entry.event == &"big_swap":
			current = entry.to
			if not out.has(current):
				out[current] = 0
		elif entry.event == &"player_hit":
			out[current] = int(out[current]) + 1
	return out


## The same hits split by kind ("contact", "projectile", ...), with "_blocked" added to
## hits an invincible player would have taken. Keyed like genre_hits. A genre that
## looks deadly is often one kind of hit the bot never avoids (M12), so sweeps read this.
static func genre_hits_by_kind() -> Dictionary:
	var out := {"base": {}}
	var current := "base"
	for entry: Dictionary in RunState.run_log:
		if entry.event == &"big_swap":
			current = entry.to
			if not out.has(current):
				out[current] = {}
		elif entry.event == &"player_hit":
			var kind := String(entry.get("kind", "unknown")) + ("_blocked" if entry.get("blocked", false) else "")
			var kinds: Dictionary = out[current]
			kinds[kind] = int(kinds.get(kind, 0)) + 1
	return out


## Appends one line. Returns OK or the error.
static func append(record: Dictionary, file_path := "") -> Error:
	if file_path == "":
		file_path = log_path
	var dir := file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var made := DirAccess.make_dir_recursive_absolute(dir)
		if made != OK:
			push_warning("telemetry: cannot create %s (%s)" % [dir, error_string(made)])
			return made
	var f := FileAccess.open(file_path, FileAccess.READ_WRITE if FileAccess.file_exists(file_path) else FileAccess.WRITE)
	if f == null:
		var err := FileAccess.get_open_error()
		push_warning("telemetry: cannot open %s (%s)" % [file_path, error_string(err)])
		return err
	f.seek_end()
	f.store_line(JSON.stringify(record))
	f.close()
	return OK


## StringName keys and odd number types become plain JSON-friendly values.
static func _plain(d: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in d:
		var v: Variant = d[key]
		out[String(key)] = snappedf(v, 0.01) if v is float else v
	return out
