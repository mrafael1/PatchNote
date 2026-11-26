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
## The session order an M42.2 save's `campaign.index` counted in (frozen, PLAN v9 1.14):
## a save without `campaign.next` maps its index through it.
const M42_2_ORDER: Array[StringName] = [&"s1_00_nothing", &"s1_01_move", &"s1_02_enemies",
		&"s1_03_shooting", &"s1_04_level", &"s1_05_wrong", &"s1_06_playground"]
## M47 (frozen, PLAN v9 1.14, D3): the sessions a save may have in `done` from a stub that a
## later milestone replaced (the M43.2 S7 stub: the owner's v0.8.0 save). While the save is
## stub-era (_stub_era) they are ignored by the furthest-done scan and by stage_card_due(),
## so the real session plays, with its card; version_after() still sees them done (no
## second bump). Completing the real session points `next` past it: the rule turns off.
const STUB_DONE: Array[StringName] = [&"s2_01_tryout"]

var campaign: CampaignDef
## The AI's live reactions (PLAN v8 1.7), every file in REACTIONS_DIR, sorted by id.
var reactions: Array[ReactionDef] = []
var active := false
## M47.4: a --session= jump happened this process (a dev replay plays S7's full door beat).
var jumped := false
## M47.4 (PLAN 1.16): the session whose stage card brings the front door (S7).
const FRONT_DOOR_SESSION := &"s2_01_tryout"
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
## unique ids, stages never going back, each fork asked once, every "fork:" field asked
## by an earlier session, every stage titled, died_in: naming a session, and (PLAN v9
## D4) what is parsed but not built yet.
func problems(c: CampaignDef = campaign) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	var forks := {}
	var last_stage := 1
	var ids := {}
	var cooking_seen: StringName = &""   ## M43.2: the first cooking session
	for s in c.sessions:
		if s != null:
			ids[s.id] = true
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
		if not c.stage_titles.has(s.stage):
			out.append("campaign: stage %d (%s) has no title" % [s.stage, s.id])
		for f in s.fork_refs():
			if not forks.has(f):
				out.append("campaign: %s uses fork:%s before it is asked" % [s.id, f])
		out.append_array(_unbuilt_problems(s))
		if cooking_seen != &"" and not s.is_cooking():
			out.append("campaign: %s is playable after %s, which is still cooking" % [s.id, cooking_seen])
		if s.is_cooking() and cooking_seen == &"":
			cooking_seen = s.id
		for cond in _session_conditions(s):
			out.append_array(_died_in_problems(cond, ids, "session %s" % s.id))
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
			# M45a: a path's own basic (PathDef.basics) is per path and per session: each
			# session adds it again, so it does not carry.
			if cue.action == &"add" and cue.problem == "" and not cue.target in next.basics \
					and PathDB.owner_of_basic(cue.target) == &"":
				out.append("campaign: %s adds %s but %s does not have it" % [s.id, cue.target, next.id])
	if c == campaign:
		for e in RuleDB.all():
			out.append_array(RuleDB.problems(e))
		for ev in EventDB.all():
			out.append_array(EventDB.problems(ev))
		for r in reactions:
			out.append_array(r.problems())
			out.append_array(reaction_problems(r, c))
	return out


## A reaction against the campaign's order (PLAN v9 1.13): after / until are known
## session ids, until not before after; its when and lines name known sessions.
func reaction_problems(r: ReactionDef, c: CampaignDef = campaign) -> Array[String]:
	var out: Array[String] = []
	var order := {}
	for i in c.sessions.size():
		if c.sessions[i] != null:
			order[c.sessions[i].id] = i
	for pair: Array in [[&"after", r.after], [&"until", r.until]]:
		if pair[1] != &"" and not order.has(pair[1]):
			out.append("reaction %s: %s names no session %s" % [r.id, pair[0], pair[1]])
	if r.after != &"" and r.until != &"" and order.has(r.after) and order.has(r.until) \
			and int(order[r.until]) < int(order[r.after]):
		out.append("reaction %s: until %s is before after %s" % [r.id, r.until, r.after])
	var conds: Array[String] = [r.when]
	for l in r.line_list():
		conds.append(String(l.when))
	for cond in conds:
		out.append_array(_died_in_problems(cond, order, "reaction %s" % r.id))
	return out


## Every condition a session's lines and cues hold (died_in: is checked against the order).
func _session_conditions(s: SessionDef) -> Array[String]:
	var out: Array[String] = []
	for l in s.intro_lines() + s.debrief_lines():
		out.append(String(l.when))
	for cue in s.cue_list():
		out.append(cue.cond)
		if cue.line != null:
			out.append(String(cue.line.when))
	return out


static func _died_in_problems(cond: String, ids: Dictionary, where: String) -> Array[String]:
	var out: Array[String] = []
	for part in Line.condition_parts(cond):
		if part.begins_with("died_in:") and not ids.has(StringName(part.trim_prefix("died_in:"))):
			out.append("%s: died_in names no session %s" % [where, part.trim_prefix("died_in:")])
	return out


## PLAN v9 D4: the fields, cue actions, whens and tags that parse but have no runtime
## yet. Each later milestone removes its own entry.
static func _unbuilt_problems(s: SessionDef) -> Array[String]:
	var out: Array[String] = []
	var where := "campaign: %s" % s.id
	for cue in s.cue_list():
		if cue.problem == "" and cue.unbuilt() != "":
			out.append("%s: cue '%s': %s" % [where, cue.source, cue.unbuilt()])
	for cue in s.cue_list():
		if cue.problem == "" and cue.action == &"give" and cue.rank > Loadout.MAX_RANK:
			out.append("%s: cue '%s': rank %d is not built yet (M50.1)" % [where, cue.source, cue.rank])
	# M45a: a path runs when PathDB has it (Auto); a fork:fork_path session fails
	# problems() already (no fork until M47).
	var path_id := s.resolve(&"path") if SessionDef.fork_of(s.path) == &"" else &""
	if path_id != &"" and not PathDB.has(path_id):
		out.append("%s: path %s is not built yet" % [where, path_id])
	if s.stages != &"" or s.goal == SessionDef.STAGES:
		out.append("%s: stages are not built yet (M50)" % where)
	if s.hud != &"":
		out.append("%s: hud is not built yet (M51)" % where)
	if s.boss != &"" or s.goal == SessionDef.BOSS:
		out.append("%s: boss is not built yet (M49)" % where)
	if not s.spawn_weights.is_empty():
		out.append("%s: spawn_weights are not built yet (M50)" % where)
	if s.checkpoint:
		out.append("%s: checkpoint is not built yet (M49)" % where)
	return out


# --- The save's campaign -----------------------------------------------------------

## The index of the session the save plays next (PLAN v9 1.14), a pure function of the
## save: `campaign.next` (an id) when it names a known session; a save without the key
## (an M42.2 file) maps its `index` through M42_2_ORDER (7 or more: the session after
## s1_06_playground today); otherwise (next "" on a new or finished save) the session
## after the furthest one done, so content added after the end continues a finished save.
## M43.2: never past the first cooking session (cooking_index()): a save that played the
## old S7 stub (s2_01_tryout done, v0.8.0) lands on the cooking screen, not past it.
func current_index() -> int:
	return mini(_save_index(), cooking_index())


func _save_index() -> int:
	var camp := SaveGame.campaign()
	var next := String(camp.get("next", ""))
	if next != "" and index_of(StringName(next)) >= 0:
		return index_of(StringName(next))
	if not camp.has("next"):
		var old := int(camp.get("index", 0))
		var mapped := -1
		if old < M42_2_ORDER.size():
			mapped = index_of(M42_2_ORDER[old])
		elif index_of(M42_2_ORDER[M42_2_ORDER.size() - 1]) >= 0:
			mapped = index_of(M42_2_ORDER[M42_2_ORDER.size() - 1]) + 1
		if mapped >= 0:
			return mapped
	var furthest := -1
	var stub := _stub_era(camp)
	for d: Variant in (camp.done as Array):
		if stub and StringName(String(d)) in STUB_DONE:
			continue
		furthest = maxi(furthest, index_of(StringName(String(d))))
	return furthest + 1


## M47 (D3): the save finished a stub session in STUB_DONE and nothing after it: a STUB_DONE
## id is in `done`, no `done` id comes after it in the campaign, and `next` is "", absent or
## a STUB_DONE id.
func _stub_era(camp: Dictionary = SaveGame.campaign()) -> bool:
	var next := StringName(String(camp.get("next", "")))
	if next != &"" and not next in STUB_DONE:
		return false
	var done: Array = camp.get("done", [])
	var stub_at := -1
	for id in STUB_DONE:
		if String(id) in done:
			stub_at = maxi(stub_at, index_of(id))
	if stub_at < 0:
		return false
	for d: Variant in done:
		if index_of(StringName(String(d))) > stub_at:
			return false
	return true


## Is the save stub-era (M47, D3)? Tests and the report read it.
func stub_era() -> bool:
	return _stub_era(SaveGame.campaign())


## The session the save plays next; the cooking session (M43.2) when nothing playable is
## left (is_done() is true then: the flow shows the cooking screen, a dev jump plays it);
## null past the end.
func current() -> SessionDef:
	return session(current_index())


## Nothing playable is left: the save stands at the first cooking session (M43.2) or past
## the last session.
func is_done() -> bool:
	return current_index() >= cooking_index()


## The index of the first session still cooking (SessionDef.cooking), or size() if none.
func cooking_index() -> int:
	for i in size():
		if campaign.sessions[i] != null and campaign.sessions[i].is_cooking():
			return i
	return size()


## The session the cooking screen shows (M43.2), or null when no session is cooking.
func cooking() -> SessionDef:
	return session(cooking_index())


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
## --dash-aim=<aim|move> (M42.2) answers fork_dash_aim the same way. PLAN v9 1.1 (M43):
## --answer=<fork>=<change> (repeatable) answers any fork (the dash flags are its aliases),
## then every fork an earlier session asks that is still unanswered gets option 0. All of
## it is read only inside the --session= branch (the bot's own --dash= / --answer= flags
## never reach here; read_jump_args).
func session_for_game() -> SessionDef:
	if not _arg_read:
		_arg_read = true
		read_jump_args(OS.get_cmdline_user_args())
	return current() if active else null


## The game's command-line jump (session_for_game, split out so a test can hand it any
## args): a --session=<id> jumps there, makes the campaign active and answers forks from
## --answer= / --dash= / --dash-aim= (answers_from_args) then every earlier fork with
## option 0. Without --session= nothing is parsed, shipped or activated. True on a jump.
func read_jump_args(args: PackedStringArray) -> bool:
	var did_jump := false
	for arg in args:
		if arg.begins_with("--session="):
			var id := StringName(arg.trim_prefix("--session="))
			if jump_to(id):
				active = true
				did_jump = true
				self.jumped = true   # M47.4: a dev jump replays S7's full door beat
				var answers := answers_from_args(args)
				for f: StringName in answers:
					answer_fork(f, answers[f])
				answer_earlier_forks(id)
			else:
				push_warning("No session %s" % id)
	return did_jump


## fork id -> change id from command-line arguments: every --answer=<fork>=<change>, then
## the aliases --dash=<style> (fork_dash=dash_<style>; "none" and unknown styles answer
## nothing) and --dash-aim=<aim> (fork_dash_aim=dashdir_<aim>). One rule, the bot's too
## (bot_runs builds its answers with this function): an --answer= wins over an alias for
## the same fork wherever it stands, and among valid flags of one kind the first wins
## (a first --dash=none answers nothing and a later --dash= does not either).
static func answers_from_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if a.begins_with("--answer="):
			var pair := a.trim_prefix("--answer=")
			var eq := pair.find("=")
			if eq <= 0 or eq == pair.length() - 1:
				push_warning("Bad %s (--answer=<fork>=<change>)" % a)
				continue
			var f := StringName(pair.left(eq))
			if not out.has(f):
				out[f] = StringName(pair.substr(eq + 1))
	var dash_seen := false   # the first --dash= decides, "none" too (it answers nothing)
	for a in args:
		if a.begins_with("--dash="):
			var style := StringName(a.trim_prefix("--dash="))
			if not style in Change.DASHES and style != &"none":
				push_warning("No dash %s (%s)" % [style, Change.DASHES])
				continue
			if dash_seen:
				continue
			dash_seen = true
			if style != &"none" and not out.has(&"fork_dash"):
				out[&"fork_dash"] = StringName("dash_%s" % style)
		elif a.begins_with("--dash-aim="):
			var aim := StringName(a.trim_prefix("--dash-aim="))
			if not aim in Change.DASH_AIMS:
				push_warning("No dash direction %s (%s)" % [aim, Change.DASH_AIMS])
			elif not out.has(&"fork_dash_aim"):
				out[&"fork_dash_aim"] = StringName("dashdir_%s" % aim)
	return out


## Answers fork_id with change_id unless it is answered: shipped like a debrief pick (a
## patch, as the dash flags always did; in memory until a write), and a mascot option
## gives the AI its body. False (with a warning) for an unknown fork or a change that is
## not one of its options.
func answer_fork(fork_id: StringName, change_id: StringName) -> bool:
	var f := ChangeDB.get_fork(fork_id)
	if f == null:
		push_warning("No fork %s" % fork_id)
		return false
	if not change_id in f.options or ChangeDB.get_change(change_id) == null:
		push_warning("%s is not an option of %s (%s)" % [change_id, fork_id, f.options])
		return false
	if not f.is_answered():
		SaveGame.ship(change_id, GameVersion.PATCH)
		var c := ChangeDB.get_change(change_id)
		if c.kind == &"mascot" and c.take != null:
			SaveGame.set_mascot(c.take.id)
	return true


## Ships dash_<style> unless fork_dash is answered (the bot's --dash=; answer_fork).
## False for a style that is not in Change.DASHES.
func answer_dash(style: StringName) -> bool:
	if not style in Change.DASHES:
		push_warning("No dash %s (%s)" % [style, Change.DASHES])
		return false
	answer_fork(&"fork_dash", StringName("dash_%s" % style))
	return true


## Ships dashdir_<aim> unless fork_dash_aim is answered (the bot's --dash-aim=; answer_fork).
## False for a direction that is not in Change.DASH_AIMS.
func answer_dash_aim(aim: StringName) -> bool:
	if not aim in Change.DASH_AIMS:
		push_warning("No dash direction %s (%s)" % [aim, Change.DASH_AIMS])
		return false
	answer_fork(&"fork_dash_aim", StringName("dashdir_%s" % aim))
	return true


## A jump to `id` (--session=, PLAN v9 1.1): every fork a session before it asks, still
## unanswered, gets its option 0, then the session's own "fork:" enemies (answer_forks).
func answer_earlier_forks(id: StringName) -> void:
	var i := index_of(id)
	if i < 0:
		return
	for j in i:
		for f in session(j).asked_forks():
			var fork := ChangeDB.get_fork(f)
			if fork != null and not fork.is_answered() and not fork.changes().is_empty():
				answer_fork(f, fork.changes()[0].id)
	answer_forks(session(i))


## Answers, with their first option, the forks a session's enemies name ("fork:<id>")
## that the save has not answered: a session jumped to (--session=) still gets its
## forked enemy. Ships the change like a debrief pick would (in memory until a write).
func answer_forks(s: SessionDef) -> void:
	if s == null:
		return
	for e in s.enemies:
		var fork_id := SessionDef.fork_of(e)
		if fork_id == &"":
			continue
		var f := ChangeDB.get_fork(fork_id)
		if f != null and not f.is_answered() and not f.changes().is_empty():
			answer_fork(fork_id, f.changes()[0].id)


## Every shelved option of the forks asked by stage `stage`'s sessions, in order (PLAN v9
## 1.1: the shelf for Phase 8). Empty for a fork still unanswered (Fork.shelf()).
func shelf(stage: int) -> Array[Change]:
	var out: Array[Change] = []
	for s in campaign.sessions:
		if s == null or s.stage != stage:
			continue
		for f in s.asked_forks():
			var fork := ChangeDB.get_fork(f)
			if fork != null:
				out.append_array(fork.shelf())
	return out


## The next session becomes `id` (in memory; written with the next session done).
func jump_to(id: StringName) -> bool:
	var i := index_of(id)
	if i < 0:
		return false
	SaveGame.set_campaign_position(i, id)
	return true


## A stage card plays before session s (PLAN v9 2): its stage is past 1, has a title, and
## no session of it is done or retried yet (Retry does not show it again).
func stage_card_due(s: SessionDef) -> bool:
	if s == null or s.stage <= 1 or not campaign.stage_titles.has(s.stage):
		return false
	var camp := SaveGame.campaign()
	var stub := _stub_era(camp)
	for other in campaign.sessions:
		if other == null or other.stage != s.stage or (stub and other.id in STUB_DONE):
			continue   # M47 (D3): the old stub's done entry does not count
		if String(other.id) in (camp.done as Array) or int((camp.attempts as Dictionary).get(String(other.id), 0)) > 0:
			return false
	return true


## M47.4 (PLAN 1.16): the title replaces the raw start screen once the save's progress is at
## S7 or later: S7 done (the old stub's done S7 counts) or attempted, the save past it, or
## standing at it after the door beat played (quit mid-S7). A save standing at S7 that never
## played it (the end of Stage 1) still gets the raw screen: the beat shows it change.
func front_door_open() -> bool:
	var at := index_of(FRONT_DOOR_SESSION)
	if at < 0:
		return false
	var camp := SaveGame.campaign()
	if String(FRONT_DOOR_SESSION) in (camp.done as Array):
		return true
	if int((camp.attempts as Dictionary).get(String(FRONT_DOOR_SESSION), 0)) > 0:
		return true
	var now := current_index()
	return now > at or (now >= at and bool(Settings.get_value("front_door_seen")))


## M47.4 (PLAN 3.2): S7's stage card plays its door beat first when the save has not seen
## the front door yet, or on a dev jump (--session=), which replays it in full.
func door_beat_due(s: SessionDef) -> bool:
	if s == null or s.door_beat.is_empty() or not stage_card_due(s):
		return false
	return jumped or not bool(Settings.get_value("front_door_seen"))


## The context Line conditions read (Line.passes).
## events: the scripted events played this attempt (String ids; the debrief's event:<id>).
## moved_on: the player chose Move on after a death (the `ended` condition, M42).
func line_context(s: SessionDef, outcome: StringName = &"", hits := -1, events: Array = [],
		moved_on := false) -> Dictionary:
	var ctx := {"attempt": attempt(s.id), "mascot": SaveGame.mascot(), "shipped": SaveGame.shipped(),
			"events": events, "dash": Unlocks.dash_answer(), "dash_aim": Unlocks.dash_aim_answer(),
			"attempts_by_session": SaveGame.campaign().attempts}
	if outcome != &"":
		ctx.outcome = outcome
		ctx.moved_on = moved_on
	if hits >= 0:
		ctx.hits = hits
	# M50.1b: the `fused` / `misfused` conditions (this attempt's run log; Arsenal only).
	ctx.fused = false
	ctx.misfused = false
	# M50.2b: give_kept / give_taken (this attempt's give steps), made:<id> (its fusions).
	ctx.give_kept = false
	ctx.give_taken = false
	ctx.made = []
	for e: Dictionary in RunState.run_log:
		if e.get("event") == &"fused":
			ctx.fused = true
			(ctx.made as Array).append(String(e.get("weapon", "")))
		elif e.get("event") == &"fuse_fail":
			ctx.misfused = true
		elif e.get("event") == &"give_choice":
			if String(e.get("choice", "")) == "keep":
				ctx.give_kept = true
			else:
				ctx.give_taken = true
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
	var after := session(index_of(s.id) + 1)
	SaveGame.campaign_done(s.id, s.bump, ships, index_of(s.id) + 1, after.id if after != null else &"")


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
		edits: Array = [], events: Array = [], more_picks: Array[Change] = [],
		path_runner: Node = null) -> Dictionary:
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
	var rec := {
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
		# PLAN v9 1.15 (M45b, additive: the schema stays 4): shots refused at their cap.
		"enemy_shots_refused": RunState.enemy_shots_refused,
		"player_shots_refused": RunState.player_shots_refused,
	}
	rec.merge(path_record(s, path_runner))
	return rec


## PLAN v9 1.15 (M47, additive: the schema stays 4): the path keys of a campaign line. path:
## the answered path ("" in a tryout and Stage 1); fp: the play fingerprint (null in a
## tryout and without a path); fp_tastes / swaps: a tryout's per-taste fingerprints and its
## swaps ("arsenal@14.5"); weapons {id: rank}; pickups {kind: n}; kill_heal n; picks
## [{at, offer, pick}]; replay (a replay-as-path, SaveGame.in_replay()).
func path_record(s: SessionDef, runner: Node = null) -> Dictionary:
	var tryout := s != null and s.tryout
	var out := {"path": "" if tryout or s == null else String(s.resolve(&"path")), "fp": null,
			"fp_tastes": {}, "swaps": [], "weapons": {}, "pickups": {}, "kill_heal": 0, "picks": [],
			"replay": SaveGame.in_replay()}
	for e: Dictionary in RunState.run_log:
		match e.get("event"):
			&"path_swapped":
				if tryout:
					(out.swaps as Array).append("%s@%.1f" % [e.get("to", ""), float(e.get("time", 0.0))])
			&"pick":
				(out.picks as Array).append({"at": snappedf(float(e.get("time", 0.0)), 0.1),
						"offer": e.get("offer", []), "pick": e.get("pick", "")})
			&"kill_heal":
				out.kill_heal = int(out.kill_heal) + 1
	if runner == null:
		return out
	out.pickups = (runner.get(&"pickup_kinds") as Dictionary).duplicate()
	var lo: Loadout = runner.call(&"loadout")
	if lo != null:
		for w in lo.slots + lo.passives:
			(out.weapons as Dictionary)[String(w.def.id)] = w.rank
	if tryout:
		out.fp_tastes = (runner.get(&"taste_fps") as Dictionary).duplicate()
	elif String(out.path) != "":
		out.fp = runner.call(&"fingerprint")
	# M50.1a (additive, Arsenal's packs only): packs, what was taken, ranks at the end.
	if runner.has_method(&"pack_path") and bool(runner.call(&"pack_path")):
		out.packs = int(runner.call(&"packs"))
		out.pack_picks = (runner.get(&"pack_picks") as Dictionary).duplicate()
		# M50.2a (additive): packs with fewer than 3 cards, 1-card toasts, rare cards shown.
		out.packs_short = int(runner.get(&"packs_short"))
		out.packs_toast = int(runner.get(&"packs_toast"))
		out.rares_shown = int(runner.get(&"rares_shown"))
		# M50.3a (additive): the launcher's mines laid and blown (the run log's mine events).
		var mines := {"laid": 0, "blown": 0}
		for e: Dictionary in RunState.run_log:
			if e.get("event") == &"mine_laid":
				mines.laid = int(mines.laid) + 1
			elif e.get("event") == &"mine_blown":
				mines.blown = int(mines.blown) + 1
		out.mines = mines
		out.ranks_end = (out.weapons as Dictionary).duplicate()
		var top := 0
		for r: Variant in (out.weapons as Dictionary).values():
			top = maxi(top, int(r))
		out.max_rank = top
		# M50.1b (additive): fusions made, the misfuse, the seconds FUSE sat available, the
		# recipes the save knows.
		out.fusions = (runner.get(&"fusions") as Array).duplicate(true)
		# M50.2b (additive): each give step closed ({weapon, rank, choice, t}).
		out.gives = (runner.get(&"gives") as Array).duplicate(true)
		var mf: Dictionary = runner.get(&"misfuse")
		out.misfuse = {"t": mf.t, "pair": mf.pair, "restored": mf.restored} if not mf.is_empty() else null
		out.link_lit_s = snappedf(float(runner.get(&"link_lit_ticks")) / Engine.physics_ticks_per_second, 0.1)
		out.recipes_known = SaveGame.recipes().map(func(id: StringName) -> String: return String(id))
	return out


## {id, pick, shelved} of one fork pick (telemetry).
func _fork_record(pick: Change) -> Dictionary:
	var shelved: Array[String] = []
	var f := ChangeDB.fork_of(pick)
	if f != null:
		for c in f.changes():
			if c != pick:
				shelved.append(String(c.id))
	return {"id": String(pick.fork), "pick": String(pick.id), "shelved": shelved}
