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
## The path ids a `path` field may name (PLAN v9 1.5; PathDB has Auto from M45a).
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
## M48b (PLAN 1.7.1, D1): the code-drawn art this session wears: "" keeps whatever the
## command line or F10 chose (no look by default), "pixel" puts on Pixel (Skins.apply_session).
## Not the legacy `look` (the juice take, whose presets M48a never made for Pixel).
@export var skin: StringName = &""
## M48b: "all" (every id drawn from the start) or "manual" (nothing until `skin` cues
## reveal it: S9's transformation). Manual needs a skin.
@export var look_reveal: StringName = &"all"
## M48b (D10): the spawner stays silent for this long (s of spawner time) before its first
## wave (S9's specimen moment). 0 = today.
@export var spawn_after := 0.0
## M48b (D8): after a `skin enemies` cue, each new enemy id met says the next of these
## lines (in order, wrapping) as it is drawn in. Lines (Line syntax).
@export var reveal_lines: PackedStringArray = []

@export_group("Goal")
@export var goal: StringName = SURVIVE
@export var goal_value := 60.0
@export var time_limit := 0.0
## M47.2 (owner G14a): path id -> the goal_value on that path ({} = goal_value on every
## path; S8 Survival survives 90 s). Not on a tryout (a swap never rescales) or a
## pathless session; a kills goal is still multiplied by the path's kill_goal_mult.
@export var goal_by_path: Dictionary[StringName, float] = {}

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
## M47 (D16): Lines the debrief says after the take line of the session's last asked fork
## (S7: "The other two go in a drawer.").
@export var after_pick: PackedStringArray = []
## Changes shipped into the save when the session is done (none needed for the basics:
## the next session's data says what its build has).
@export var ships: Array[StringName] = []

@export_group("Cooking")
## M43.2 (G13b): not playable yet. The campaign flow never plays this session: it shows
## the cooking screen (the stage card, the AI building it: these progress lines, then
## "To be continued"). A dev jump (--session=, the bot's --only=) still plays its data.
## Empty = a playable session. The real session's milestone clears it (M47 for S7).
@export var cooking: PackedStringArray = []
## M47 (D2): progress lines the stage card shows before its title when it plays before this
## session (the AI cooking it, a short beat; S7). Empty = the plain card.
@export var cook_beat: PackedStringArray = []
## M47.4 (PLAN 3.2, v9.1): the front door's beat on the stage card, before the cook_beat
## (S7): Line syntax (`expression: text`, `{key:..}` allowed, no condition), at most
## DoorBeat.LINE_AT.size() lines. Empty = no door beat.
@export var door_beat: PackedStringArray = []

var _intro: Array[Line] = []
var _cues: Array[Cue] = []
var _debrief: Array[Line] = []
var _after_pick: Array[Line] = []
var _reveal_lines: Array[Line] = []
var _door_beat: Array[Line] = []
var _parsed := false


## The campaign shows this session cooking instead of playing it (M43.2).
func is_cooking() -> bool:
	return not cooking.is_empty()


## M47.2: the goal value this session plays on path `path_id` (goal_by_path, else
## goal_value; &"" = no path).
func goal_for(path_id: StringName) -> float:
	return float(goal_by_path.get(path_id, goal_value))


func intro_lines() -> Array[Line]:
	_parse()
	return _intro


func cue_list() -> Array[Cue]:
	_parse()
	return _cues


func debrief_lines() -> Array[Line]:
	_parse()
	return _debrief


func after_pick_lines() -> Array[Line]:
	_parse()
	return _after_pick


func reveal_line_list() -> Array[Line]:
	_parse()
	return _reveal_lines


## M47.4: the door beat's lines, parsed (DoorBeat says them at LINE_AT).
func door_beat_lines() -> Array[Line]:
	_parse()
	return _door_beat


func _parse() -> void:
	if _parsed:
		return
	_parsed = true
	_intro = Line.parse_all(intro)
	_cues = Cue.parse_all(cues)
	_debrief = Line.parse_all(debrief)
	_after_pick = Line.parse_all(after_pick)
	_reveal_lines = Line.parse_all(reveal_lines)
	_door_beat = Line.parse_all(door_beat)


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
	# M45a (the pool rule): a [tag] names a weapon the session lists or a path's extra.
	for c in cue_list():
		if c.problem != "" or c.tag == &"" or c.tag in weapons:
			continue
		if not PathDB.all().any(func(p: PathDef) -> bool: return c.tag in p.offer_pool_extra):
			out.append("%s: cue '%s': [%s] is not in the session's weapons or a path's offer_pool_extra"
					% [where, c.source, c.tag])
	return out


## M45a (PLAN v9 1.2, deferred from M43): a path's own basic (PathDef.basics: Auto's
## levelups and crowd) belongs to that path. Outside a tryout, in a session whose path is
## not its owner (a "fork:fork_path" session too), an `add` of it needs a positive
## answer:path_<owner> in its condition, and another path's answer is the same problem; the
## session's own `basics` may list it only when its path is the owner.
func _path_basic_problems(where: String) -> Array[String]:
	var out: Array[String] = []
	var own := path if fork_of(path) == &"" else &""
	for b in basics:
		var owner := PathDB.owner_of_basic(b)
		if owner != &"" and not tryout and own != owner:
			out.append("%s: basics list %s, %s's basic; it needs path %s" % [where, b, owner, owner])
	for c in cue_list():
		if c.problem != "" or c.action != &"add":
			continue
		var owner := PathDB.owner_of_basic(c.target)
		if owner == &"" or tryout or own == owner:
			continue
		var want := "answer:path_%s" % owner
		var has_want := false
		var other := false
		for part in c.cond.split("&", false):   # "!answer:..." parts are negative: neither
			if part == want:
				has_want = true
			elif part.begins_with("answer:path_"):
				other = true
		if not has_want or other:
			out.append("%s: cue '%s': %s is %s's basic; it needs %s" % [where, c.source, c.target, owner, want])
	return out


## M47.2: goal_by_path names known paths with values > 0, only on a session with a path
## that is not a tryout. And (survive and stop goals) no `at s` cue that can run on path
## p comes after that path's end: s >= goal_for(p) on survive (it would never fire),
## s > goal_for(p) + Tuning.smoke_stop_read on stop (a stop session runs on that long).
func _goal_by_path_problems(where: String) -> Array[String]:
	var out: Array[String] = []
	for k: Variant in goal_by_path:
		if typeof(k) != TYPE_STRING_NAME or not StringName(k) in PATHS:
			out.append("%s: goal_by_path: unknown path %s (%s)" % [where, k, PATHS])
		elif float(goal_by_path[k]) <= 0.0:
			out.append("%s: goal_by_path: %s must be > 0" % [where, k])
	if not goal_by_path.is_empty() and path == &"":
		out.append("%s: goal_by_path needs a path" % where)
	if not goal_by_path.is_empty() and tryout:
		out.append("%s: goal_by_path is not for a tryout (a swap never rescales)" % where)
	if goal != SURVIVE and goal != STOP:
		return out
	var paths: Array[StringName] = PATHS
	if path == &"":
		paths = [&""]
	for p in paths:
		var end := goal_for(p) + (Tuning.smoke_stop_read if goal == STOP else 0.0)
		for c in cue_list():
			if c.problem != "" or c.when != &"at" or not _cue_can_run_on(c, p):
				continue
			if c.value > end or (goal == SURVIVE and c.value >= end):
				out.append("%s: cue '%s' is after the goal's end (%s s%s)" % [where, c.source, end,
						" on %s" % p if p != &"" else ""])
	return out


## Whether a cue's condition can hold on path p: no positive answer:path_<other> part and
## no "!answer:path_<p>" part (other parts can hold on any path).
static func _cue_can_run_on(c: Cue, p: StringName) -> bool:
	for part in c.cond.split("&", false):
		if p != &"" and part == "!answer:path_%s" % p:
			return false
		if part.begins_with("answer:path_") and (p == &"" or part != "answer:path_%s" % p):
			return false
	return true


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
	out.append_array(_path_basic_problems(where))
	out.append_array(_goal_by_path_problems(where))
	out.append_array(_skin_problems(where))
	for k in cooking:
		if k.strip_edges() == "":
			out.append("%s: an empty cooking line" % where)
	for k in cook_beat:
		if k.strip_edges() == "":
			out.append("%s: an empty cook_beat line" % where)
	out.append_array(_door_beat_problems(where))
	if not after_pick.is_empty() and asked_forks().is_empty():
		out.append("%s: after_pick lines need a fork" % where)
	for l in after_pick_lines():
		if l.problem != "":
			out.append("%s: after_pick: %s" % [where, l.problem])
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
		elif c.when in [&"fused", &"fuse_ready"] and not _has_basic(&"fusion"):
			out.append("%s: cue '%s': %s needs the fusion basic" % [where, c.source, c.when])
		elif c.action == &"fuse" and not _has_basic(&"cards"):
			out.append("%s: cue '%s': fuse needs the cards basic (a pack path)" % [where, c.source])
		elif (c.action == &"fuse" or c.when in [&"fused", &"fuse_ready"]) and not _arsenal_only(c):
			out.append("%s: cue '%s': a fusion cue needs answer:path_arsenal (it can run on another path)" % [where, c.source])
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
		elif reads_fusion(l.when):
			out.append("%s: an intro line cannot depend on a fusion (fused / misfused)" % where)
	for l in intro_lines() + debrief_lines():
		for w in Line.condition_parts(String(l.when)):
			if w.begins_with("event:") and EventDB.get_event(StringName(w.trim_prefix("event:"))) == null:
				out.append("%s: unknown event %s" % [where, w.trim_prefix("event:")])
	return out


## The enemy bases a `spawn ... specimen` may name (a walker: the chaser and the scripts
## that extend it); a variant counts by its base.
const SPECIMEN_BASES: Array[StringName] = EnemyDB.WALKERS
const SKINS: Array[StringName] = [&"", &"pixel"]
const REVEALS: Array[StringName] = [&"all", &"manual"]
## M47.4: the door beat's line slots (DoorBeat.LINE_AT.size(); test_front_door pins it).
const DOOR_BEAT_MAX := 3


## M47.4 (PLAN 3.2): the door beat plays on the stage card (stage 2 on), one Line per slot,
## never conditional (it is not a debrief).
func _door_beat_problems(where: String) -> Array[String]:
	var out: Array[String] = []
	if door_beat.is_empty():
		return out
	if stage <= 1:
		out.append("%s: door_beat needs a stage card (stage 2 or later)" % where)
	if door_beat.size() > DOOR_BEAT_MAX:
		out.append("%s: door_beat has %d lines (at most %d)" % [where, door_beat.size(), DOOR_BEAT_MAX])
	for k in door_beat:
		if k.strip_edges() == "":
			out.append("%s: an empty door_beat line" % where)
	for l in door_beat_lines():
		if l.problem != "":
			out.append("%s: door_beat: %s" % [where, l.problem])
		elif l.when != &"":
			out.append("%s: door_beat: '%s' cannot have a condition" % [where, l.text])
	return out


## M48b (PLAN 1.7.1): the skin fields and the skin / specimen / release cues.
func _skin_problems(where: String) -> Array[String]:
	var out: Array[String] = []
	if not skin in SKINS:
		out.append("%s: unknown skin %s (%s)" % [where, skin, SKINS])
	if not look_reveal in REVEALS:
		out.append("%s: look_reveal must be all or manual, not %s" % [where, look_reveal])
	elif look_reveal == &"manual" and skin == &"":
		out.append("%s: look_reveal manual needs a skin" % where)
	if spawn_after < 0.0:
		out.append("%s: spawn_after must be >= 0" % where)
	# M48b review: the specimen / release order is checked on cue times and conditions,
	# not list positions. Both are `at` cues; a specimen needs a release that fires on
	# every run it spawns on (no condition, or its own) at a later time (the same time
	# counts when the release is listed after it: same-frame cues fire in list order).
	var specimens: Array = []   # [index, cue]
	var releases: Array = []
	var enemies_cue := false
	var list := cue_list()
	for i in list.size():
		var c: Cue = list[i]
		if c.problem != "":
			continue
		if c.action == &"skin":
			if skin == &"" or look_reveal != &"manual":
				out.append("%s: cue '%s': skin cues need a skin and look_reveal manual" % [where, c.source])
			enemies_cue = enemies_cue or c.target == &"enemies"
		elif c.action == &"spawn" and c.specimen:
			specimens.append([i, c])
			if c.when != &"at":
				out.append("%s: cue '%s': a specimen spawn must be an 'at' cue" % [where, c.source])
			var base := EnemyDB.base_of(c.archetype) if EnemyDB.has(c.archetype) else &""
			if not base in SPECIMEN_BASES:
				out.append("%s: cue '%s': only a walker can be a specimen (%s)" % [where, c.source, SPECIMEN_BASES])
		elif c.action == &"release":
			releases.append([i, c])
			if c.when != &"at":
				out.append("%s: cue '%s': release must be an 'at' cue" % [where, c.source])
	var after := func(a: Array, b: Array) -> bool:   # b fires after a
		var ca: Cue = a[1]
		var cb: Cue = b[1]
		return cb.value > ca.value or (cb.value == ca.value and int(b[0]) > int(a[0]))
	for r: Array in releases:
		var rc: Cue = r[1]
		if rc.when == &"at" and not specimens.any(func(sp: Array) -> bool:
				return (sp[1] as Cue).when == &"at" and after.call(sp, r)):
			out.append("%s: cue '%s': release needs an earlier specimen spawn" % [where, rc.source])
		elif rc.cond != "" and specimens.any(func(sp: Array) -> bool: return (sp[1] as Cue).cond != rc.cond):
			out.append("%s: cue '%s': a release narrower than its specimen's condition" % [where, rc.source])
	for sp: Array in specimens:
		var sc: Cue = sp[1]
		if sc.when != &"at":
			continue
		if not releases.any(func(r: Array) -> bool:
				var rc: Cue = r[1]
				return rc.when == &"at" and (rc.cond == "" or rc.cond == sc.cond) and after.call(sp, r)):
			out.append("%s: cue '%s': a specimen is never released (add a later 'at' release cue with no condition or its own)" % [where, sc.source])
	for l in reveal_line_list():
		if l.problem != "":
			out.append("%s: reveal_lines: %s" % [where, l.problem])
	if not reveal_lines.is_empty() and not enemies_cue:
		out.append("%s: reveal_lines need a 'skin enemies' cue" % where)
	return out


## Whether any part of a line condition ("&"-joined, "!" or not) reads the outcome
## (won, died, stopped, ended): an intro or cue line never has one, so it would never
## be said (M43 review: checked per part, not on the whole condition).
static func reads_outcome(when: StringName) -> bool:
	return Line.condition_parts(String(when)).any(func(p: String) -> bool:
		return StringName(p) in Line.OUTCOMES or p == "ended")


## M50.1b review: whether a line condition reads fused / misfused (this attempt's run log),
## which an intro line has no record of yet.
static func reads_fusion(when: StringName) -> bool:
	return Line.condition_parts(String(when)).any(func(p: String) -> bool:
		return p.trim_prefix("!") in ["fused", "misfused"])


## M50.1b review: basic b is in basics or an `add b` cue brings it.
func _has_basic(b: StringName) -> bool:
	return b in basics or cue_list().any(func(x: Cue) -> bool:
		return x.problem == "" and x.action == &"add" and x.target == b)


## M50.1b review: a fusion cue runs on Arsenal only: the session's own path is Arsenal, or
## (a fork path) the cue cannot run on any other path.
func _arsenal_only(c: Cue) -> bool:
	if path == &"":
		return true   # the cards / fusion basic rules already tie it to Arsenal
	if fork_of(path) == &"":
		return path == &"arsenal"
	for p in PATHS:
		if p != &"arsenal" and _cue_can_run_on(c, p):
			return false
	return true


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
