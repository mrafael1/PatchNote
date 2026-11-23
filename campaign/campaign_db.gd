extends Node
## Autoload "CampaignDB" (PLAN v8 1.1): loads campaign/campaign.tres, checks it, and
## answers which session the game plays. Loads after ChangeDB (sessions name forks and
## changes).
##
## `active` says the game scene runs the campaign: the start screen's New game and
## Continue, the bot's --campaign and the game's --session=<id> set it. While it is
## false (GUT, main.tscn booted directly, the --legacy-loop start screen) the game runs
## the v6 run loop, untouched.

const PATH := "res://campaign/campaign.tres"

var campaign: CampaignDef
var active := false
## --session=<id> was read from the command line (once per process).
var _arg_read := false


func _ready() -> void:
	reload()
	print(summary_line())


func reload() -> void:
	campaign = load(PATH) as CampaignDef
	if campaign == null:
		push_error("No campaign at %s" % PATH)
		campaign = CampaignDef.new()
	for p in problems():
		push_error(p)


func summary_line() -> String:
	var ids: Array[String] = []
	for s in campaign.sessions:
		ids.append(String(s.id))
	return "[campaign] %d sessions: %s" % [ids.size(), ", ".join(ids)]


func size() -> int:
	return campaign.sessions.size()


func session(index: int) -> SessionDef:
	return campaign.sessions[index] if index >= 0 and index < size() else null


func index_of(id: StringName) -> int:
	for i in size():
		if campaign.sessions[i].id == id:
			return i
	return -1


func get_session(id: StringName) -> SessionDef:
	return session(index_of(id))


## Everything wrong with the campaign: each session's own problems, then the order:
## unique ids, stages never going back, each fork asked once.
func problems(c: CampaignDef = campaign) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	var forks := {}
	var last_stage := 1
	for s in c.sessions:
		if s == null:
			out.append("campaign: an empty session slot")
			continue
		out.append_array(s.problems())
		if seen.has(s.id):
			out.append("campaign: session %s is listed twice" % s.id)
		seen[s.id] = true
		if s.stage < last_stage:
			out.append("campaign: session %s goes back to stage %d" % [s.id, s.stage])
		last_stage = maxi(last_stage, s.stage)
		if s.fork != &"":
			if forks.has(s.fork):
				out.append("campaign: fork %s is asked twice (%s, %s)" % [s.fork, forks[s.fork], s.id])
			forks[s.fork] = s.id
	return out


# --- The save's campaign -----------------------------------------------------------

func current_index() -> int:
	return int(SaveGame.campaign().index)


## The session the save plays next; null once the campaign is done.
func current() -> SessionDef:
	return session(current_index())


func is_done() -> bool:
	return current_index() >= size()


## Has the save started the campaign (a session done or attempted)?
func started() -> bool:
	return current_index() > 0 or not (SaveGame.campaign().attempts as Dictionary).is_empty()


## The attempt the save is on at session id (1 = first try).
func attempt(id: StringName) -> int:
	return SaveGame.attempts(id) + 1


## The game scene's session: the save's current one while the campaign is active, else
## null (the run loop). A --session=<id> argument makes the campaign active and jumps
## there, once per process.
func session_for_game() -> SessionDef:
	if not _arg_read:
		_arg_read = true
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--session="):
				var id := StringName(arg.trim_prefix("--session="))
				if jump_to(id):
					active = true
				else:
					push_warning("No session %s" % id)
	return current() if active else null


## The next session becomes `id` (in memory; written with the next session done).
func jump_to(id: StringName) -> bool:
	var i := index_of(id)
	if i < 0:
		return false
	SaveGame.set_campaign_index(i)
	return true


## The context Line conditions read (Line.passes).
func line_context(s: SessionDef, outcome: StringName = &"", hits := -1) -> Dictionary:
	var ctx := {"attempt": attempt(s.id), "mascot": SaveGame.mascot(), "shipped": SaveGame.shipped()}
	if outcome != &"":
		ctx.outcome = outcome
	if hits >= 0:
		ctx.hits = hits
	return ctx


## The version the save reaches when `s` is done.
func version_after(s: SessionDef) -> GameVersion:
	var v := SaveGame.version()
	if not String(s.id) in (SaveGame.campaign().done as Array):
		v.bump(s.bump)
	return v


## Session s is done (won, stopped, or moved on after a death): ship and move on.
func complete(s: SessionDef) -> void:
	SaveGame.campaign_done(s.id, s.bump, s.ships, index_of(s.id) + 1)


## A death, then Retry: one more attempt, same session.
func retry(s: SessionDef) -> void:
	SaveGame.count_attempt(s.id)


## The telemetry line of one played attempt (PLAN v8 1.8, schema 4). choice: next,
## retry or move_on. Call before complete()/retry(), so attempt and version are this
## attempt's. reactions, edits, events and fork fill in from M38-M41.
func telemetry_record(s: SessionDef, run_record: Dictionary, outcome: StringName, hits: int,
		choice: StringName, build := "") -> Dictionary:
	return {
		"schema": Telemetry.CAMPAIGN_SCHEMA,
		"type": "campaign",
		"session_id": Telemetry.session(),
		"timestamp": Time.get_datetime_string_from_system(true),
		"build": build,
		"seed": RunState.run_seed,
		"session": String(s.id),
		"stage": s.stage,
		"index": index_of(s.id),
		"attempt": attempt(s.id),
		"outcome": String(outcome),
		"choice": String(choice),
		"moved_on": choice == &"move_on",
		"duration": run_record.get("duration", snappedf(RunState.game_time, 0.01)),
		"real_duration": run_record.get("real_duration", snappedf(RunState.real_time(), 0.01)),
		"goal": run_record.get("goal", {}),
		"deaths": 1 if outcome == &"died" else 0,
		"kills": RunState.kills,
		"hits_taken": hits,
		"reactions": [],
		"edits": [],
		"events": [],
		"fork": null,
		"mascot": String(SaveGame.mascot()),
		"reduce_flashing": bool(SaveGame.setting("reduce_flashing")),
		"game_version": SaveGame.version().label(),
		"bot": bool(run_record.get("bot", false)),
		"invincible": RunState.invincible,
	}
