class_name SessionDef
extends Resource
## One scripted development session of the campaign (PLAN v8 1.1), in
## campaign/sessions/<id>.tres. It says what the build has, what the player must do,
## what the AI says and does, and what ships when it is done. The shell runs whatever
## the campaign says; it never names a session.
##
## Lines and cues are plain text (Line.parse, Cue.parse), so they can be edited for
## tone in the inspector or the .tres without sub-resources.

const SURVIVE := &"survive"   ## won once the goal clock reaches goal_value seconds
const KILLS := &"kills"       ## won at goal_value kills; time_limit > 0 ends it "stopped"
const STOP := &"stop"         ## the AI ends it at goal_value seconds ("stopped")
## More and more enemies (the cues) until you go down: going down is the expected end
## (the debrief offers Next, not Retry). Still standing at goal_value seconds: "stopped".
const OVERRUN := &"overrun"
const GOALS: Array[StringName] = [SURVIVE, KILLS, STOP, OVERRUN]
const FORK_ENEMY := &"fork:fork_enemy"

@export var id: StringName
@export var stage := 1
@export var title := ""

@export_group("Build")
## The game's basics this build has (Unlocks.CAMPAIGN_BASICS): movement, shooting,
## dash, enemies, level, health, hits, version.
@export var basics: Array[StringName] = []
## Enemy archetypes that may spawn; "fork:fork_enemy" is the save's answer to that fork.
@export var enemies: Array[StringName] = []
@export var arena: ArenaDef   ## null: arena_0
## The spawn preset (as a StageDef's): multipliers on the spawner's rate and its cap
## (Tuning.max_enemies). S2 dodges a few chasers with no gun: a low cap.
@export var spawn_rate := 1.0
@export var spawn_cap := 1.0
## The look take ("punchy", "clean", "arcade") at tier 1; "" is tier 0 (squares).
@export var look := ""

@export_group("Goal")
@export var goal: StringName = SURVIVE
@export var goal_value := 60.0
@export var time_limit := 0.0

@export_group("The AI")
## The mascot has a body (false before fork_mascot is answered).
@export var face := false
@export var intro: PackedStringArray = []
@export var cues: PackedStringArray = []
@export var debrief: PackedStringArray = []

@export_group("After")
@export var fork: StringName = &""
## More forks asked after `fork`, in order (M42.1: S3 asks the face, then the dash).
@export var more_forks: Array[StringName] = []
@export var bump: StringName = &"minor"
## The patch notes: what changed with this session.
@export var notes: PackedStringArray = []
## Changes shipped into the save when the session is done (none needed for the basics:
## the next session's data says what its build has).
@export var ships: Array[StringName] = []

var _intro: Array[Line] = []
var _cues: Array[Cue] = []
var _debrief: Array[Line] = []
var _parsed := false


func intro_lines() -> Array[Line]:
	_parse()
	return _intro


func cue_list() -> Array[Cue]:
	_parse()
	return _cues


func debrief_lines() -> Array[Line]:
	_parse()
	return _debrief


func _parse() -> void:
	if _parsed:
		return
	_parsed = true
	_intro = Line.parse_all(intro)
	_cues = Cue.parse_all(cues)
	_debrief = Line.parse_all(debrief)


## The arena this session plays.
func arena_def() -> ArenaDef:
	return arena if arena != null else load(StageSet.ARENA_0) as ArenaDef


## The archetypes that may spawn, with "fork:fork_enemy" resolved from the save (the
## answer's unlocks; nothing while the fork is unanswered).
func enemy_types() -> Array[StringName]:
	var out: Array[StringName] = []
	for e in enemies:
		if String(e).begins_with("fork:"):
			var f := ChangeDB.get_fork(StringName(String(e).trim_prefix("fork:")))
			var answer := f.answer() if f else null
			if answer != null:
				for u in answer.unlocks:
					if u in Unlocks.ARCHETYPES and not out.has(u):
						out.append(u)
		elif not out.has(e):
			out.append(e)
	return out


## Every fork the debrief asks, in order: `fork` (if set), then `more_forks`.
func asked_forks() -> Array[StringName]:
	var out: Array[StringName] = []
	if fork != &"":
		out.append(fork)
	out.append_array(more_forks)
	return out


## Everything wrong with this session on its own (CampaignDB adds what needs the order).
func problems() -> Array[String]:
	var out: Array[String] = []
	var where := "session %s" % id
	if id == &"":
		out.append("a session has no id")
	if stage < 1 or stage > 5:
		out.append("%s: stage %d is not 1-5" % [where, stage])
	if not goal in GOALS:
		out.append("%s: unknown goal %s" % [where, goal])
	elif goal_value <= 0.0:
		out.append("%s: goal_value must be > 0" % where)
	if time_limit < 0.0 or (time_limit > 0.0 and goal != KILLS):
		out.append("%s: time_limit is for kills goals only" % where)
	for b in basics:
		if not b in Unlocks.CAMPAIGN_BASICS:
			out.append("%s: unknown basic %s" % [where, b])
	for e in enemies:
		if String(e).begins_with("fork:"):
			if ChangeDB.get_fork(StringName(String(e).trim_prefix("fork:"))) == null:
				out.append("%s: no fork %s" % [where, e])
		elif not e in Unlocks.ARCHETYPES:
			out.append("%s: unknown enemy %s" % [where, e])
	if not enemies.is_empty() and not &"enemies" in basics:
		out.append("%s: enemies listed without the enemies basic" % where)
	# The preset file, by path: only presentation may read the Look class (M28 lint).
	if look != "" and not ResourceLoader.exists("res://systems/looks/look_1_%s.tres" % look):
		out.append("%s: no look %s" % [where, look])
	if spawn_rate <= 0.0 or spawn_cap <= 0.0:
		out.append("%s: spawn_rate and spawn_cap must be > 0" % where)
	if not bump in [GameVersion.PATCH, GameVersion.MINOR]:
		out.append("%s: bump must be patch or minor" % where)
	var asked := {}
	for f in asked_forks():
		if f == &"" or ChangeDB.get_fork(f) == null:
			out.append("%s: no fork %s" % [where, f])
		if asked.has(f):
			out.append("%s: fork %s is asked twice" % [where, f])
		asked[f] = true
	for c in ships:
		if ChangeDB.get_change(c) == null:
			out.append("%s: ships unknown change %s" % [where, c])
	for l in intro_lines() + debrief_lines():
		if l.problem != "":
			out.append("%s: %s" % [where, l.problem])
	for c in cue_list():
		if c.problem != "":
			out.append("%s: %s" % [where, c.problem])
		elif c.action == &"say" and (c.line.when in Line.OUTCOMES or c.line.when == &"ended"):
			out.append("%s: cue '%s' cannot depend on the outcome" % [where, c.source])
		elif c.action == &"add" and not c.target in Unlocks.CAMPAIGN_BASICS:
			out.append("%s: cue '%s': unknown basic %s" % [where, c.source, c.target])
		elif c.action == &"add" and c.target in basics:
			out.append("%s: cue '%s': the session already has %s" % [where, c.source, c.target])
		elif c.action == &"edit" and RuleDB.get_edit(c.target) == null:
			out.append("%s: cue '%s': unknown edit %s" % [where, c.source, c.target])
		elif c.action == &"spawn" and String(c.archetype).begins_with("fork:") and ChangeDB.get_fork(
				StringName(String(c.archetype).trim_prefix("fork:"))) == null:
			out.append("%s: cue '%s': no fork %s" % [where, c.source, String(c.archetype).trim_prefix("fork:")])
		elif c.action == &"event" and EventDB.get_event(c.target) == null:
			out.append("%s: cue '%s': unknown event %s" % [where, c.source, c.target])
		elif c.action == &"say" and String(c.line.when).begins_with("event:"):
			out.append("%s: cue '%s': a cue line cannot depend on an event" % [where, c.source])
		elif c.when == &"pct" and goal != SURVIVE:
			out.append("%s: cue '%s': pct needs a survive goal" % [where, c.source])
		elif c.when == &"hp" and not &"health" in basics and not cue_list().any(
				func(x: Cue) -> bool: return x.action == &"add" and x.target == &"health"):
			out.append("%s: cue '%s': hp needs the health basic" % [where, c.source])
	for l in intro_lines():
		if l.when in Line.OUTCOMES or l.when == &"ended":
			out.append("%s: an intro line cannot depend on the outcome" % where)
		elif String(l.when).begins_with("event:"):
			out.append("%s: an intro line cannot depend on an event" % where)
	for l in intro_lines() + debrief_lines():
		var w := String(l.when)
		if w.begins_with("event:") and EventDB.get_event(StringName(w.trim_prefix("event:"))) == null:
			out.append("%s: unknown event %s" % [where, w.trim_prefix("event:")])
	return out
