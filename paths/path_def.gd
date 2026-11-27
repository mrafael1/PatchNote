class_name PathDef
extends Resource
## One shooter path (PLAN v9 1.5): paths/<id>.tres, the take of a `path` change. What your
## hands do (fire_mode), where power comes from (growth), what kills you (the crowd numbers,
## a WorldRules overlay owned by &"path"). Never saved: the session's path is read from the
## save's answer or from S7's `path` cue (RunState.session_path).
##
## M45a adds data fields to 1.5's list: `basics` (the path's own campaign basics, for the
## "path basic under another path" problem), `level_thresholds` / `taste_thresholds`
## (Auto's levels; a tryout levels on the taste list), `max_picks` (the meter stops there;
## M50.4a: 0 = no cap),
## `warn_line` (the `path` cue's fallback warning; M47 gives each S7 cue its own) and
## `max_passives`. M46 adds `full_line`, `pick_line` and `quick_draw_mult` (Arsenal). M47 adds
## Survival (paths/survival.tres: `manual_ammo`, `pickups`, one slot, no thresholds). M47.6d1
## adds `title` (the display name) and Survival's revolver start.

const FIRE_MODES: Array[StringName] = [&"manual_one", &"auto_all", &"manual_ammo"]
const GROWTHS: Array[StringName] = [&"cards", &"levelups", &"pickups"]
const WIDGETS: Array[StringName] = [&"hand", &"level", &"ammo"]
## After the last threshold, each level needs this many more.
const THRESHOLD_STEP := 20

@export var id: StringName
## M47.6d1 (PLAN v9.4 0.8): the display name, the title card a `path` cue shows (ARCADE,
## SURVIVAL, AUTO). The id never changes (saves, answers and logs keep `arsenal`).
@export var title := ""
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
## The session cap on picks (the meter stops there). M50.4a: 0 = no cap on a levelups path
## (Auto: no level cap; a tryout still stops after its taste list).
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
## M50.1a (Arsenal depth): a booster pack every `pack_every` player kills (0 = the classic
## card meter's thresholds). A pack path has no session cap (max_picks, level_thresholds
## and full_line are unused there); a tryout deals `pack_taste` packs, then stops quietly.
@export var pack_every := 0
@export var pack_taste := 0
## M50.6: per pack card slot after the first, the chance of an epic card (a ready-made fusion;
## at most one a pack, BoosterPack). Rarity itself is the weapon's (WeaponDef.rarity).
@export var epic_chance := 0.0
## M50.6 (Line syntax, "" = none): said once a session when its first pack lands on the stack,
## and once when the stack reaches Tuning.pack_nudge_at.
@export var pack_first_line := ""
@export var pack_stack_line := ""
## M50.6a: in a tryout's taste (S7) a pack opens by itself on the first free tick, as before
## M50.6: a player who never presses the key still gets the taste's cards. The key and the
## stack are taught where the path is built for real (S8's first pack). The pack lines above
## are not said while this holds.
@export var taste_auto_open := false
## The top rank (0 = none). Classic paths keep Loadout.MAX_RANK (3).
@export var rank_cap := 3
## &"classic" (WeaponDef.ranks 2-3) or &"deep" (WeaponCurve: odd ranks damage, even ranks
## mechanics, no top).
@export var rank_curve: StringName = &"classic"

## M50.4a (Auto depth design 2): weapons of every mode (aimed and passive-mode: nova, well,
## orbit) share max_slots (Loadout.shared_slots; max_passives is then unused, 0). Auto only.
@export var shared_slots := false
## M50.4a: passive items held (Loadout items, built in M50.4b; 0 = none).
@export var max_items := 0
## M50.4a: every level threshold x this, rounded (a tool knob: --probe=human_pace, M50.4b).
@export var threshold_mult := 1.0

const RANK_CURVES: Array[StringName] = [&"classic", &"deep"]


## The gems needed to reach level `level + 1` from `level` (level >= 1); -1 past a tryout's
## list (no more levels).
func threshold(level: int, tryout := false) -> int:
	var list := taste_thresholds if tryout and not taste_thresholds.is_empty() else level_thresholds
	var i := level - 1
	var need := -1
	if i < list.size():
		need = list[i]
	elif tryout and not taste_thresholds.is_empty():
		return -1
	elif list.is_empty():
		return -1
	else:
		need = list[list.size() - 1] + THRESHOLD_STEP * (i - list.size() + 1)
	return need if threshold_mult == 1.0 else roundi(need * threshold_mult)


func warn() -> Line:
	return Line.parse(warn_line) if warn_line != "" else null


## Everything wrong with this path on its own. `file_id` is its file name.
func problems(file_id: StringName = id) -> Array[String]:
	var out: Array[String] = []
	var where := "path %s" % file_id
	if id != file_id:
		out.append("%s: id %s is not its file's name" % [where, id])
	if title.strip_edges() == "":
		out.append("%s: no title" % where)
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
		if not WeaponDB.has(w) and not WeaponDB.has_item(w):   # M50.4b: items too
			out.append("%s: offer_pool_extra: unknown weapon or item %s" % [where, w])
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
	if growth == &"cards" and pack_every <= 0 and level_thresholds.size() < max_picks:
		out.append("%s: a cards path needs a threshold for each of its %d picks" % [where, max_picks])
	for pair: Array in [["warn_line", warn_line], ["full_line", full_line], ["pack_first_line", pack_first_line],
			["pack_stack_line", pack_stack_line]]:
		var text: String = pair[1]
		if text != "" and Line.parse(text).problem != "":
			out.append("%s: %s: %s" % [where, pair[0], Line.parse(text).problem])
	if pick_line == "":
		out.append("%s: an empty pick_line" % where)
	if quick_draw_mult < 1.0:
		out.append("%s: quick_draw_mult must be >= 1" % where)
	if pack_every < 0 or pack_taste < 0:
		out.append("%s: pack_every and pack_taste must be >= 0" % where)
	if pack_every > 0 and growth != &"cards":
		out.append("%s: pack_every needs the cards growth" % where)
	if epic_chance < 0.0 or epic_chance >= 1.0:
		out.append("%s: epic_chance must be in [0, 1)" % where)
	if rank_cap < 0:
		out.append("%s: rank_cap must be >= 0 (0 = none)" % where)
	if not rank_curve in RANK_CURVES:
		out.append("%s: unknown rank_curve %s (%s)" % [where, rank_curve, RANK_CURVES])
	if rank_curve == &"classic" and (rank_cap == 0 or rank_cap > Loadout.MAX_RANK):
		out.append("%s: the classic curve stops at rank %d" % [where, Loadout.MAX_RANK])
	if max_items < 0:
		out.append("%s: max_items must be >= 0" % where)
	if threshold_mult <= 0.0:
		out.append("%s: threshold_mult must be > 0" % where)
	if shared_slots and max_passives != 0:
		out.append("%s: shared_slots counts passive-mode weapons in max_slots: max_passives must be 0" % where)
	if max_picks == 0 and growth == &"cards" and pack_every <= 0:
		out.append("%s: max_picks 0 (no cap) needs packs or level-ups" % where)
	return out
