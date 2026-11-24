class_name ReactionDef
extends Resource
## One live reaction of the AI (PLAN v8 1.7), in campaign/reactions/<id>.tres: when its
## trigger happens during a session, the mascot says one of its lines (picked by the
## run's seed), if the speaking rules let it (Reactions).
##
## trigger is plain text, a name and maybe an argument: "first_kill", "kill_streak 4",
## "enemy_seen shooter". lines use the Line syntax, so "mascot:blob happy: Eep!" is a
## line only the blob says; when a mascot has lines of its own they replace the shared
## ones (per-mascot flavour).

## Trigger names, and whether each takes a number ("n"), a word ("w") or nothing ("").
const TRIGGERS := {
	&"first_kill": "",              ## the session's first kill
	&"kill_streak": "n",            ## n kills within STREAK_WINDOW seconds
	&"kills_at_least": "n",         ## the session's kills reach n
	&"enemy_count_at_least": "n",   ## n enemies alive at once (each time it climbs there)
	&"enemy_seen": "w",             ## the first enemy of that archetype appears
	&"player_hp_at_most": "n",      ## the player's HP drops to n (or below, alive)
	&"player_hit": "",              ## the player takes a hit
	&"streak_broken": "n",          ## a hit after n seconds without one
	&"near_miss": "",               ## an enemy shot passes within NEAR_MISS px and misses
	&"camping": "",                 ## the player stays in a 3-tile area for CAMP_SECONDS
	&"not_shooting": "",            ## no shot for IDLE_GUN_SECONDS with enemies around
	&"no_hit_for": "n",             ## n seconds without a hit
	&"wave_cleared": "",            ## the arena empties after at least WAVE_MIN enemies
	&"session_half": "",            ## half the goal (survive time or kills)
	&"last_seconds": "",            ## LAST_SECONDS left on a survive goal
	&"first_dash": "",              ## the session's first dash
	&"quiet": "n",                  ## nothing said by anyone for n seconds
}
const STREAK_WINDOW := 3.0
const NEAR_MISS := 12.0
const CAMP_SECONDS := 8.0
const CAMP_RADIUS := 72.0       ## 1.5 tiles: a 3-tile area
const IDLE_GUN_SECONDS := 8.0
const WAVE_MIN := 3
const LAST_SECONDS := 5.0

@export var id: StringName
@export var trigger := ""
@export var lines: PackedStringArray = []
## 1 chatter, 2 notable, 3 important (cuts in, ignores the gap and the cues).
@export_range(1, 3) var priority := 1
@export var cooldown := 30.0           ## seconds before this reaction can fire again
@export var once_per_session := false
## The first session (an id, inclusive) where the AI knows enough to say it; &"" = from
## the start (PLAN v9 1.13: ids survive sessions added in a stage's middle).
@export var after: StringName = &""
## The last session it fits (an id, inclusive; &"" = no end). A discovery line goes stale
## once it's not new.
@export var until: StringName = &""
## A Line condition on the save ("!answer:path_auto"; "" = always), checked when the
## session starts: a reaction it gates is not loaded, so it never takes a cooldown slot.
@export var when := ""


func trigger_name() -> StringName:
	var words := trigger.strip_edges().split(" ", false)
	return StringName(words[0]) if not words.is_empty() else &""


## The trigger's number (0 when it has none or a word).
func trigger_value() -> float:
	var words := trigger.strip_edges().split(" ", false)
	return float(words[1]) if words.size() > 1 and words[1].is_valid_float() else 0.0


## The trigger's word ("" when it has none).
func trigger_word() -> String:
	var words := trigger.strip_edges().split(" ", false)
	return words[1] if words.size() > 1 else ""


## Whether this reaction fits session `session_id`, by the campaign's order.
func fits(session_id: StringName) -> bool:
	var i := CampaignDB.index_of(session_id)
	if i < 0:
		return false
	if after != &"" and i < CampaignDB.index_of(after):
		return false
	if until != &"" and i > CampaignDB.index_of(until):
		return false
	return true


func line_list() -> Array[Line]:
	return Line.parse_all(lines)


## What is wrong with this reaction (empty = fine).
func problems() -> Array[String]:
	var out: Array[String] = []
	var where := "reaction %s" % id
	if id == &"":
		out.append("a reaction has no id")
	var name := trigger_name()
	if not TRIGGERS.has(name):
		out.append("%s: unknown trigger '%s'" % [where, trigger])
	else:
		var words := trigger.strip_edges().split(" ", false)
		match String(TRIGGERS[name]):
			"n":
				if words.size() != 2 or not words[1].is_valid_float() or float(words[1]) <= 0.0:
					out.append("%s: '%s' needs a number > 0" % [where, name])
			"w":
				if words.size() != 2:
					out.append("%s: '%s' needs one word" % [where, name])
			_:
				if words.size() != 1:
					out.append("%s: '%s' takes nothing" % [where, name])
	if lines.is_empty():
		out.append("%s: no lines" % where)
	var shared := 0
	for l in line_list():
		if l.problem != "":
			out.append("%s: %s" % [where, l.problem])
		if not String(l.when).begins_with("mascot:"):
			shared += 1
	if not lines.is_empty() and shared == 0:
		out.append("%s: every line is for one mascot; the others would say nothing" % where)
	if priority < 1 or priority > 3:
		out.append("%s: priority %d is not 1-3" % [where, priority])
	if cooldown < 0.0:
		out.append("%s: cooldown < 0" % where)
	# after / until against the order: CampaignDB.reaction_problems().
	var cond_problem := Line.condition_problem(when, "%s when" % where)
	if cond_problem != "":
		out.append("%s: %s" % [where, cond_problem])
	return out
