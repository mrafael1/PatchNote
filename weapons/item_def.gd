class_name ItemDef
extends Resource
## A passive item (M50.4b, Auto depth design 4): weapons/items/<id>.tres. A stat item with
## levels 1..the path's rank_cap (Auto 6) that touches every held weapon through one role
## (Weapon.mods: role -> multiplier, written by Loadout), and the catalyst of one weapon's
## evolution (`pairs`; the evolutions come in M50.4c1). Items never fire and own no node.
## Never saved: power stays in the session. Magnet's id is `attract` (`magnet` is a v6
## mutation id, linted in session tags).

## The roles an item can move (Weapon.FIELDS maps them to weapon fields; `area` also reaches
## the node knobs that read Weapon.stat_mult). Only these three are wired in M50.4b.
const STATS: Array[StringName] = [&"haste", &"area", &"might", &"duration", &"amount", &"speed", &"attract"]

@export var id: StringName
@export var title := ""
@export var icon: StringName = &""        ## a WeaponGlyph key (item glyphs: ITEM_KEYS)
@export var stat: StringName = &""        ## one of STATS
## The role's multiplier per level: mult(level) = 1 + per_level * level (Haste -0.06: x0.64 at 6).
@export var per_level := 0.0
@export var pairs: StringName = &""       ## the weapon it evolves (its catalyst)
@export_multiline var pitch := ""
## The effect with %s for the percent at a level: "guns fire %s faster".
@export var card_text := ""
## "" = built; else "not built yet (<where>)": never a candidate, a give / tag of it is a
## CampaignDB problem.
@export var built_in := ""


## The role's multiplier at `level` (0: none, 1.0).
func mult(level: int) -> float:
	return 1.0 + per_level * maxi(0, level)


## The percent at `level` as the card says it: "6%" (Haste), "+8%" (Might, Area).
func pct(level: int) -> String:
	var p := roundi(absf(per_level) * level * 100.0)
	return ("%d%%" if per_level < 0.0 else "+%d%%") % p


## "guns fire 12% faster" at `level`.
func effect(level: int) -> String:
	return card_text % pct(level) if "%s" in card_text else card_text


func built() -> bool:
	return built_in == ""


## Everything wrong with this item on its own (`file_id`: its file name).
func problems(file_id: StringName = id) -> Array[String]:
	var out: Array[String] = []
	var where := "item %s" % file_id
	if id != file_id:
		out.append("%s: id %s is not its file's name" % [where, id])
	if title.strip_edges() == "":
		out.append("%s: no title" % where)
	if not stat in STATS:
		out.append("%s: unknown stat %s (%s)" % [where, stat, STATS])
	if per_level == 0.0:
		out.append("%s: per_level is 0" % where)
	if pairs == &"":
		out.append("%s: pairs no weapon" % where)
	if card_text.strip_edges() == "":
		out.append("%s: no card_text" % where)
	if icon == &"":
		out.append("%s: no icon" % where)
	return out
