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
const REACTIONS_DIR := "res://campaign/reactions/"

var campaign: CampaignDef
## The AI's live reactions (PLAN v8 1.7), every file in REACTIONS_DIR, sorted by id.
var reactions: Array[ReactionDef] = []
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
	reactions.clear()
	if DirAccess.dir_exists_absolute(REACTIONS_DIR):
		for entry in ResourceLoader.list_directory(REACTIONS_DIR):
			if not entry.ends_with(".tres"):
				continue
			var r := load(REACTIONS_DIR + entry) as ReactionDef
			if r == null or String(r.id) != entry.get_basename():
				push_error("Reaction at %s is not a ReactionDef named after its file" % (REACTIONS_DIR + entry))
				continue
			reactions.append(r)
	reactions.sort_custom(func(a: ReactionDef, b: ReactionDef) -> bool: return String(a.id) < String(b.id))
	for p in problems():
		push_error(p)


func summary_line() -> String:
	var ids: Array[String] = []
	for s in campaign.sessions:
		ids.append(String(s.id))
	return "[campaign] %d sessions: %s; %d reactions" % [ids.size(), ", ".join(ids), reactions.size()]


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
		var mine := {}   # a fork repeated within one session is the session's own problem
		for f in s.asked_forks():
			if mine.has(f):
				continue
			mine[f] = true
			if forks.has(f):
				out.append("campaign: fork %s is asked twice (%s, %s)" % [f, forks[f], s.id])
			forks[f] = s.id
	for i in c.sessions.size() - 1:
		var s := c.sessions[i]
		var next := c.sessions[i + 1]
		if s == null or next == null:
			continue
		for cue in s.cue_list():
			if cue.action == &"add" and cue.problem == "" and not cue.target in next.basics:
				out.append("campaign: %s adds %s but %s does not have it" % [s.id, cue.target, next.id])
	if c == campaign:
		for e in RuleDB.all():
			out.append_array(RuleDB.problems(e))
		for ev in EventDB.all():
			out.append_array(EventDB.problems(ev))
		for r in reactions:
			out.append_array(r.problems())
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
## there, once per process. --dash=<style> (M42.1, with --session=) answers fork_dash with
## that style first, so a jump plays S4-S6 with any dash (keep --autostart with it: the
## pick is shipped like a debrief's, and only --autostart keeps it off the real save).
## --dash-aim=<aim|move> (M42.2) answers fork_dash_aim the same way.
func session_for_game() -> SessionDef:
	if not _arg_read:
		_arg_read = true
		var args := OS.get_cmdline_user_args()
		for arg in args:
			if arg.begins_with("--session="):
				var id := StringName(arg.trim_prefix("--session="))
				if jump_to(id):
					active = true
					for a in args:
						if a.begins_with("--dash="):
							answer_dash(StringName(a.trim_prefix("--dash=")))
						elif a.begins_with("--dash-aim="):
							answer_dash_aim(StringName(a.trim_prefix("--dash-aim=")))
					answer_forks(get_session(id))
				else:
					push_warning("No session %s" % id)
	return current() if active else null


## Ships dash_<style> unless fork_dash is answered (a jump's --dash=; the bot's too).
## False for a style that is not in Change.DASHES.
func answer_dash(style: StringName) -> bool:
	if not style in Change.DASHES:
		push_warning("No dash %s (%s)" % [style, Change.DASHES])
		return false
	var f := ChangeDB.get_fork(&"fork_dash")
	if f != null and not f.is_answered():
		SaveGame.ship(StringName("dash_%s" % style), GameVersion.PATCH)
	return true


## Ships dashdir_<aim> unless fork_dash_aim is answered (--dash-aim=; the bot's too).
## False for a direction that is not in Change.DASH_AIMS.
func answer_dash_aim(aim: StringName) -> bool:
	if not aim in Change.DASH_AIMS:
		push_warning("No dash direction %s (%s)" % [aim, Change.DASH_AIMS])
		return false
	var f := ChangeDB.get_fork(&"fork_dash_aim")
	if f != null and not f.is_answered():
		SaveGame.ship(StringName("dashdir_%s" % aim), GameVersion.PATCH)
	return true


## Answers, with their first option, the forks a session's enemies name ("fork:<id>")
## that the save has not answered: a session jumped to (--session=) still gets its
## forked enemy. Ships the change like a debrief pick would (in memory until a write).
func answer_forks(s: SessionDef) -> void:
	if s == null:
		return
	for e in s.enemies:
		if not String(e).begins_with("fork:"):
			continue
		var f := ChangeDB.get_fork(StringName(String(e).trim_prefix("fork:")))
		if f != null and not f.is_answered() and not f.changes().is_empty():
			SaveGame.ship(f.changes()[0].id, GameVersion.PATCH)


## The next session becomes `id` (in memory; written with the next session done).
func jump_to(id: StringName) -> bool:
	var i := index_of(id)
	if i < 0:
		return false
	SaveGame.set_campaign_index(i)
	return true


## The context Line conditions read (Line.passes).
## events: the scripted events played this attempt (String ids; the debrief's event:<id>).
## moved_on: the player chose Move on after a death (the `ended` condition, M42).
func line_context(s: SessionDef, outcome: StringName = &"", hits := -1, events: Array = [],
		moved_on := false) -> Dictionary:
	var ctx := {"attempt": attempt(s.id), "mascot": SaveGame.mascot(), "shipped": SaveGame.shipped(),
			"events": events, "dash": Unlocks.dash_answer(), "dash_aim": Unlocks.dash_aim_answer()}
	if outcome != &"":
		ctx.outcome = outcome
		ctx.moved_on = moved_on
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
## pick: the option chosen in the debrief's first fork (shipped with the session; a
## mascot option also gives the AI its body), or null. more_picks: the options of its
## later forks (M42.1), in order. One version bump for the session, none per pick.
func complete(s: SessionDef, pick: Change = null, more_picks: Array[Change] = []) -> void:
	var ships: Array[StringName] = s.ships.duplicate()
	var all: Array[Change] = []
	if pick != null:
		all.append(pick)
	all.append_array(more_picks)
	for c in all:
		if c == null:
			continue
		ships.append(c.id)
		if c.kind == &"mascot":
			SaveGame.set_mascot(c.take.id)
	SaveGame.campaign_done(s.id, s.bump, ships, index_of(s.id) + 1)


## A death, then Retry: one more attempt, same session.
func retry(s: SessionDef) -> void:
	SaveGame.count_attempt(s.id)


## The telemetry line of one played attempt (PLAN v8 1.8, schema 4). choice: next,
## retry or move_on. Call before complete()/retry(), so attempt and version are this
## attempt's. reactions, edits, events and fork fill in from M38-M41. M42.1 (additive,
## schema still 4): `fork` stays the first pick's record; `forks` lists every pick of the
## attempt (pick, then more_picks), `dash` is the dash style after them. M42.2 (additive):
## `dash_aim` is where the dash goes after them (aim or move).
func telemetry_record(s: SessionDef, run_record: Dictionary, outcome: StringName, hits: int,
		choice: StringName, build := "", pick: Change = null, reactions: Array[String] = [],
		edits: Array = [], events: Array = [], more_picks: Array[Change] = []) -> Dictionary:
	var fork_record: Variant = null
	var mascot := SaveGame.mascot()
	var dash := Unlocks.dash_answer()
	var dash_aim := Unlocks.dash_aim_answer()
	var all: Array[Change] = []
	if pick != null:
		all.append(pick)
	all.append_array(more_picks)
	var fork_records: Array = []
	for c in all:
		if c == null:
			continue
		var rec := _fork_record(c)
		fork_records.append(rec)
		if c == pick:
			fork_record = rec
		if c.kind == &"mascot":
			mascot = c.take.id
		elif c.kind == &"dash":
			dash = c.take.id
		elif c.kind == &"dash_aim":
			dash_aim = c.take.id
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
		"reactions": reactions,
		"edits": edits,
		"events": events,
		"fork": fork_record,
		"forks": fork_records,
		"dash": String(dash),
		"dash_aim": String(dash_aim),
		"mascot": String(mascot),
		"reduce_flashing": bool(SaveGame.setting("reduce_flashing")),
		"game_version": SaveGame.version().label(),
		"bot": bool(run_record.get("bot", false)),
		"invincible": RunState.invincible,
	}


## {id, pick, shelved} of one fork pick (telemetry).
func _fork_record(pick: Change) -> Dictionary:
	var shelved: Array[String] = []
	var f := ChangeDB.fork_of(pick)
	if f != null:
		for c in f.changes():
			if c != pick:
				shelved.append(String(c.id))
	return {"id": String(pick.fork), "pick": String(pick.id), "shelved": shelved}
