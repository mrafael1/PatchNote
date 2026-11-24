class_name PathDef
extends Resource
## One shooter path (PLAN v9 1.5): paths/<id>.tres, the take of a `path` change. What your
## hands do (fire_mode), where power comes from (growth), what kills you (the crowd numbers,
## a WorldRules overlay owned by &"path"). Never saved: the session's path is read from the
## save's answer or from S7's `path` cue (RunState.session_path).
##
## M45a adds data fields to 1.5's list: `basics` (the path's own campaign basics, for the
## "path basic under another path" problem), `level_thresholds` / `taste_thresholds`
## (Auto's levels; a tryout levels on the taste list), `max_picks` (the meter stops there),
## `warn_line` (the `path` cue's fallback warning; M47 gives each S7 cue its own) and
## `max_passives`. M46 adds `full_line`, `pick_line` and `quick_draw_mult` (Arsenal).

const FIRE_MODES: Array[StringName] = [&"manual_one", &"auto_all", &"manual_ammo"]
const GROWTHS: Array[StringName] = [&"cards", &"levelups", &"pickups"]
const WIDGETS: Array[StringName] = [&"hand", &"level", &"ammo"]
## After the last threshold, each level needs this many more.
const THRESHOLD_STEP := 20

@export var id: StringName
@export var fire_mode: StringName = &"manual_one"
@export var growth: StringName = &"cards"
## The start loadout: weapon ids at rank 1.
@export var start: Array[StringName] = [&"pistol"]
@export var max_slots := 3          ## aimed weapons held
@export var max_passives := 0
## Weapons only this path offers (Auto: its two passives, M45b). They still join the live
## pool only through a give or a tagged say cue (the pool rule).
@export var offer_pool_extra: Array[StringName] = []
@export var spawn_rate_mult := 1.0
@export var max_enemies_mult := 1.0
@export var enemy_hp_mult := 1.0
@export var kill_goal_mult := 1.0
@export var boss_hp_mult := 1.0
@export var widget: StringName = &"level"
@export var bot_policy: StringName = &""
## The path's own basics (Unlocks.CAMPAIGN_BASICS).
@export var basics: Array[StringName] = []
## Total gems for level 2, 3, ... (then +THRESHOLD_STEP each). Cards growth (Arsenal, M46):
## the cumulative player kills for card 1, 2, ...; it needs at least max_picks entries (past
## the list only +THRESHOLD_STEP would follow, which is not the ×1.4 of 1.5).
@export var level_thresholds: PackedInt32Array = PackedInt32Array()
## In a tryout (S7's taste): the only levels, then the meter stops quietly.
@export var taste_thresholds: PackedInt32Array = PackedInt32Array()
@export var max_picks := 10
## Line syntax: the mascot's warning before a `path` cue swaps to this path.
@export var warn_line := ""
## Line syntax (M46): said once when the growth meter stops after max_picks.
@export var full_line := ""
## The pick panel's line (M46).
@export var pick_line := "Level up. Pick one."
## Quick-draw (M46, Arsenal): the first shot after a real switch does this much damage, once
## the `quick_draw` basic is live. 1.0 = none.
@export var quick_draw_mult := 1.0


## The gems needed to reach level `level + 1` from `level` (level >= 1); -1 past a tryout's
## list (no more levels).
func threshold(level: int, tryout := false) -> int:
	var list := taste_thresholds if tryout and not taste_thresholds.is_empty() else level_thresholds
	var i := level - 1
	if i < list.size():
		return list[i]
	if tryout and not taste_thresholds.is_empty():
		return -1
	if list.is_empty():
		return -1
	return list[list.size() - 1] + THRESHOLD_STEP * (i - list.size() + 1)


func warn() -> Line:
	return Line.parse(warn_line) if warn_line != "" else null


## Everything wrong with this path on its own. `file_id` is its file name.
func problems(file_id: StringName = id) -> Array[String]:
	var out: Array[String] = []
	var where := "path %s" % file_id
	if id != file_id:
		out.append("%s: id %s is not its file's name" % [where, id])
	if not fire_mode in FIRE_MODES:
		out.append("%s: unknown fire_mode %s (%s)" % [where, fire_mode, FIRE_MODES])
	if not growth in GROWTHS:
		out.append("%s: unknown growth %s (%s)" % [where, growth, GROWTHS])
	if not widget in WIDGETS:
		out.append("%s: unknown widget %s (%s)" % [where, widget, WIDGETS])
	if start.is_empty():
		out.append("%s: an empty start loadout" % where)
	for w in start:
		if not WeaponDB.has(w):
			out.append("%s: start: unknown weapon %s" % [where, w])
	for w in offer_pool_extra:
		if not WeaponDB.has(w):
			out.append("%s: offer_pool_extra: unknown weapon %s" % [where, w])
	if max_slots < 1:
		out.append("%s: max_slots must be >= 1" % where)
	if max_passives < 0 or max_picks < 0:
		out.append("%s: max_passives and max_picks must be >= 0" % where)
	for b in basics:
		if not b in Unlocks.CAMPAIGN_BASICS:
			out.append("%s: unknown basic %s" % [where, b])
	for pair: Array in [["level_thresholds", level_thresholds], ["taste_thresholds", taste_thresholds]]:
		var list: PackedInt32Array = pair[1]
		for i in list.size():
			if list[i] <= 0 or (i > 0 and list[i] <= list[i - 1]):
				out.append("%s: %s must be positive and strictly increasing" % [where, pair[0]])
				break
	if growth == &"levelups" and level_thresholds.is_empty():
		out.append("%s: a levelups path needs level_thresholds" % where)
	if growth == &"cards" and level_thresholds.size() < max_picks:
		out.append("%s: a cards path needs a threshold for each of its %d picks" % [where, max_picks])
	for pair: Array in [["warn_line", warn_line], ["full_line", full_line]]:
		var text: String = pair[1]
		if text != "" and Line.parse(text).problem != "":
			out.append("%s: %s: %s" % [where, pair[0], Line.parse(text).problem])
	if pick_line == "":
		out.append("%s: an empty pick_line" % where)
	if quick_draw_mult < 1.0:
		out.append("%s: quick_draw_mult must be >= 1" % where)
	return out
