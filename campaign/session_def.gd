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
## PLAN v9 1.2 (stubs in M43: never end on the clock; "not built yet" in campaign data).
const STAGES := &"stages"     ## won when the stage set's last part clears (M50)
const BOSS := &"boss"         ## won when the boss's HP reaches 0 (M49)
const GOALS: Array[StringName] = [SURVIVE, KILLS, STOP, OVERRUN, STAGES, BOSS]
const FORK_ENEMY := &"fork:fork_enemy"
## The path ids a `path` field may name (PLAN v9 1.5; PathDef arrives in M45a).
const PATHS: Array[StringName] = [&"arsenal", &"auto", &"survival"]
const STAGE_SETS_DIR := "res://levels/stages/"

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
## PLAN v9 1.2: also "fork:<id>" (the answer's take) and an "@<tier>" suffix (look_spec()).
@export var look := ""
## PLAN v9 1.2 (M43: validated; their runtimes come later, "not built yet" in the data).
## The path: "" = Stage 1's plain gun, "fork:fork_path" or a path id (M45a).
@export var path: StringName = &""
## The weapons this session may hand out (M44).
@export var weapons: Array[StringName] = []
## "" = the single arena; a stage set id or "fork:<id>" (goal stages, M50).
@export var stages: StringName = &""
## "" = today's corner text, or "fork:<id>" (M51).
@export var hud: StringName = &""
## A boss id or "fork:<id>"; needed by goal boss (M49).
@export var boss: StringName = &""
## No Move on, hints and help (goal boss needs it; M49).
@export var checkpoint := false
## Allows `path` cues (S7 only).
@export var tryout := false
## Archetype -> weight; empty = today's Tuning chances (first used M50).
@export var spawn_weights: Dictionary = {}
## The player's HP never goes below this in this session (WorldRules.hp_floor; 0 = none).
@export var hp_floor := 0

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

@export_group("Cooking")
## M43.2 (G13b): not playable yet. The campaign flow never plays this session: it shows
## the cooking screen (the stage card, the AI building it: these progress lines, then
## "To be continued"). A dev jump (--session=, the bot's --only=) still plays its data.
## Empty = a playable session. The real session's milestone clears it (M47 for S7).
@export var cooking: PackedStringArray = []

var _intro: Array[Line] = []
var _cues: Array[Cue] = []
var _debrief: Array[Line] = []
var _parsed := false


## The campaign shows this session cooking instead of playing it (M43.2).
func is_cooking() -> bool:
	return not cooking.is_empty()


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
		var fork_id := fork_of(e)
		if fork_id != &"":
			var answer := Unlocks.answer(fork_id)
			if answer != null:
				for u in answer.unlocks:
					if u in Unlocks.ARCHETYPES and not out.has(u):
						out.append(u)
		elif not out.has(e):
			out.append(e)
	return out


## The <id> of a "fork:<id>[@n]" value, or &"" for anything else (PLAN v9 1.1).
static func fork_of(value: Variant) -> StringName:
	var s := String(value)
	if not s.begins_with("fork:"):
		return &""
	return StringName(s.trim_prefix("fork:").get_slice("@", 0))


## A content field's value (path, stages, hud, boss), with "fork:<id>" resolved to the
## save's answer's take (&"" while unanswered).
func resolve(field: StringName) -> StringName:
	var value := StringName(String(get(field)))
	var fork_id := fork_of(value)
	return Unlocks.take(fork_id) if fork_id != &"" else value


## Every fork this session names in a field or a cue ("fork:<id>"), once each, in field
## order: enemies, spawn cues, path, look, stages, hud, boss.
func fork_refs() -> Array[StringName]:
	var values: Array = []
	values.append_array(enemies)
	for c in cue_list():
		if c.action == &"spawn":
			values.append(c.archetype)
		elif c.action in [&"look", &"boss"]:
			values.append(c.target)
	values.append_array([path, look, stages, hud, boss])
	var out: Array[StringName] = []
	for v: Variant in values:
		var f := fork_of(v)
		if f != &"" and not out.has(f):
			out.append(f)
	return out


## {tier, take} of the look field (PLAN v9 1.2): a plain take is tier 1, "@n" sets the
## tier, "fork:<id>" is the answer's take; "" or an unanswered fork is {0, ""}. The take
## is a String, as Unlocks.look() has always returned.
func look_spec() -> Dictionary:
	if look == "":
		return {"tier": 0, "take": ""}
	var base := look.get_slice("@", 0)
	var tier := look.get_slice("@", 1).to_int() if "@" in look else 1
	var take_id := String(Unlocks.take(fork_of(base))) if fork_of(base) != &"" else base
	if take_id == "":
		return {"tier": 0, "take": ""}
	return {"tier": tier, "take": take_id}


## Every fork the debrief asks, in order: `fork` (if set), then `more_forks`.
func asked_forks() -> Array[StringName]:
	var out: Array[StringName] = []
	if fork != &"":
		out.append(fork)
	out.append_array(more_forks)
	return out


## M44 (PLAN v9 1.2, 1.3): `weapons` names known weapons once each and, when set, lists the
## pistol (the start weapon with no path); every `give` cue hands out one of them.
func _weapon_problems(where: String) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for w in weapons:
		if not WeaponDB.has(w):
			out.append("%s: unknown weapon %s" % [where, w])
		if seen.has(w):
			out.append("%s: weapon %s is listed twice" % [where, w])
		seen[w] = true
	if not weapons.is_empty() and not Loadout.PISTOL in weapons:
		out.append("%s: weapons must list %s (the start weapon)" % [where, Loadout.PISTOL])
	for c in cue_list():
		if c.problem != "" or c.action != &"give":
			continue
		if not WeaponDB.has(c.target):
			out.append("%s: cue '%s': unknown weapon %s" % [where, c.source, c.target])
		elif not c.target in weapons:
			out.append("%s: cue '%s': give %s: not in the session's weapons" % [where, c.source, c.target])
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
		elif not EnemyDB.has(e):
			out.append("%s: unknown enemy %s" % [where, e])
	if not enemies.is_empty() and not &"enemies" in basics:
		out.append("%s: enemies listed without the enemies basic" % where)
	out.append_array(_look_problems(where))
	out.append_array(_field_problems(where))
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
	out.append_array(_weapon_problems(where))
	for k in cooking:
		if k.strip_edges() == "":
			out.append("%s: an empty cooking line" % where)
	for l in intro_lines() + debrief_lines():
		if l.problem != "":
			out.append("%s: %s" % [where, l.problem])
	for c in cue_list():
		if c.problem != "":
			out.append("%s: %s" % [where, c.problem])
		elif c.action == &"say" and reads_outcome(c.line.when):
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
		elif c.action == &"say" and reads_event(c.line.when):
			out.append("%s: cue '%s': a cue line cannot depend on an event" % [where, c.source])
		elif c.action == &"path" and not tryout:
			out.append("%s: cue '%s': path cues need a tryout session" % [where, c.source])
		elif c.when == &"room" and stages == &"":
			out.append("%s: cue '%s': room needs a stage set" % [where, c.source])
		elif c.when == &"boss_hp" and goal != BOSS and not cue_list().any(
				func(x: Cue) -> bool: return x.action == &"boss"):
			out.append("%s: cue '%s': boss_hp needs a boss" % [where, c.source])
		elif c.when == &"pct" and goal != SURVIVE:
			out.append("%s: cue '%s': pct needs a survive goal" % [where, c.source])
		elif c.when == &"hp" and not &"health" in basics and not cue_list().any(
				func(x: Cue) -> bool: return x.action == &"add" and x.target == &"health"):
			out.append("%s: cue '%s': hp needs the health basic" % [where, c.source])
	# M43.2: a quiet edit says nothing itself, so an earlier warned edit cue with the same
	# time must announce it (PLAN v8 0.4: the AI says so before it edits).
	var all_cues := cue_list()
	for i in all_cues.size():
		var q := all_cues[i]
		if q.problem != "" or q.action != &"edit" or not q.quiet:
			continue
		var announced := false
		for j in i:
			var w := all_cues[j]
			if w.problem == "" and w.action == &"edit" and not w.quiet and w.when == q.when and w.value == q.value:
				announced = true
		if not announced:
			out.append("%s: cue '%s': a quiet edit needs an earlier warned edit cue at the same time" % [where, q.source])
	for l in intro_lines():
		if reads_outcome(l.when):
			out.append("%s: an intro line cannot depend on the outcome" % where)
		elif reads_event(l.when):
			out.append("%s: an intro line cannot depend on an event" % where)
	for l in intro_lines() + debrief_lines():
		for w in Line.condition_parts(String(l.when)):
			if w.begins_with("event:") and EventDB.get_event(StringName(w.trim_prefix("event:"))) == null:
				out.append("%s: unknown event %s" % [where, w.trim_prefix("event:")])
	return out


## Whether any part of a line condition ("&"-joined, "!" or not) reads the outcome
## (won, died, stopped, ended): an intro or cue line never has one, so it would never
## be said (M43 review: checked per part, not on the whole condition).
static func reads_outcome(when: StringName) -> bool:
	return Line.condition_parts(String(when)).any(func(p: String) -> bool:
		return StringName(p) in Line.OUTCOMES or p == "ended")


## Whether any part of a line condition reads an event (event:<id>), which an intro or
## cue line has no record of yet.
static func reads_event(when: StringName) -> bool:
	return Line.condition_parts(String(when)).any(func(p: String) -> bool: return p.begins_with("event:"))


## The look field: "<take>[@tier]" or "fork:<id>[@tier]". The preset file is checked by
## path (only presentation may read the Look class, M28 lint): look_<tier>_<take>.tres,
## for each option's take of a fork.
func _look_problems(where: String) -> Array[String]:
	var out: Array[String] = []
	if look == "":
		return out
	var base := look.get_slice("@", 0)
	var tier := 1
	if "@" in look:
		var t := look.get_slice("@", 1)
		if not t.is_valid_int() or t.to_int() < 1:
			out.append("%s: bad look tier in %s" % [where, look])
			return out
		tier = t.to_int()
	var takes: Array[String] = []
	var fork_id := fork_of(base)
	if fork_id != &"":
		var f := ChangeDB.get_fork(fork_id)
		if f == null:
			out.append("%s: no fork %s" % [where, fork_id])
			return out
		for c in f.changes():
			takes.append(String(c.take.id) if c.take != null else "")
	else:
		takes.append(base)
	for t in takes:
		if t == "" or not ResourceLoader.exists("res://systems/looks/look_%d_%s.tres" % [tier, t]):
			out.append("%s: no look %s" % [where, t if tier == 1 and fork_id == &"" else "%s@%d" % [t, tier]])
	return out


## The PLAN v9 1.2 fields, by shape (CampaignDB.problems() adds "not built yet").
func _field_problems(where: String) -> Array[String]:
	var out: Array[String] = []
	for pair: Array in [[&"path", path], [&"stages", stages], [&"hud", hud], [&"boss", boss]]:
		var f := fork_of(pair[1])
		if f != &"" and ChangeDB.get_fork(f) == null:
			out.append("%s: %s names no fork %s" % [where, pair[0], f])
	if path != &"" and fork_of(path) == &"" and not path in PATHS:
		out.append("%s: unknown path %s (%s)" % [where, path, PATHS])
	if stages != &"" and fork_of(stages) == &"" and not ResourceLoader.exists(STAGE_SETS_DIR + "%s.tres" % stages):
		out.append("%s: no stage set %s" % [where, stages])
	if (goal == STAGES) != (stages != &""):
		out.append("%s: goal stages and a stage set go together" % where)
	if goal == BOSS and (boss == &"" or not checkpoint):
		out.append("%s: goal boss needs a boss and checkpoint" % where)
	if boss != &"" and goal != BOSS:
		out.append("%s: a boss needs goal boss" % where)
	if hud != &"" and fork_of(hud) == &"":
		out.append("%s: hud must be a fork (fork:<id>)" % where)
	for k: Variant in spawn_weights:
		if not EnemyDB.has(StringName(String(k))):
			out.append("%s: spawn_weights: unknown enemy %s" % [where, k])
		elif not (spawn_weights[k] is float or spawn_weights[k] is int) or float(spawn_weights[k]) <= 0.0:
			out.append("%s: spawn_weights: %s must be > 0" % [where, k])
	if hp_floor < 0:
		out.append("%s: hp_floor must be >= 0" % where)
	return out
