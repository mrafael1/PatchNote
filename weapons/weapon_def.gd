class_name WeaponDef
extends Resource
## One weapon (PLAN v9 1.4): weapons/<id>.tres. Rank 1 is the fields; `ranks[0]` is rank 2
## and `ranks[1]` rank 3, each a dictionary of absolute values (not deltas) over the
## fields, with `traits` the full trait list at that rank (cumulative). Rank 4 comes with
## the evolutions (M50.1). Never saved: a weapon is the session's, not the save's.

const MODES: Array[StringName] = [&"aimed", &"passive"]
const TRAITS_DIR := "res://weapons/traits/"
const RANK_KEYS_EXTRA: Array[String] = ["traits"]

@export var id: StringName
@export var title := ""
@export var mode: StringName = &"aimed"
@export var cooldown := 0.18
@export var damage := 1.0
## Projectiles a shot fires (a fan of spread_deg). A passive weapon: its shard count.
@export var pellets := 1
@export var spread_deg := 0.0
@export var pierce := 0
@export var bounces := 0
@export var speed := 900.0
## Seconds a shot lives; -1 = Tuning.projectile_lifetime.
@export var lifetime := -1.0
## The shot's visual size (1 = today's 14x6). Visual only: the hit test stays a ray.
@export var size := 1.0
## Tiles; 0 = no blast.
@export var blast_radius := 0.0
@export var ammo := -1
@export var pickup_ammo := 0
@export var color_role: StringName = &"player_shot"   ## used from M48 (Palette)
@export var icon: StringName = &""                    ## a shape key; F2 label only in M44
@export var sound: StringName = &"shoot"
## A passive's node script (M45b): "" = the orbit shards (M44's); else a script whose node
## has configure(weapon) and the flags its traits set (nova_pulse.gd, well_weapon.gd).
@export var node_script := ""
@export var ranks: Array[Dictionary] = []
@export_multiline var pitch := ""
## One line per rank ("Shotgun II: knockback").
@export var card_text: PackedStringArray = []
## M50.1a (the deep curve, WeaponCurve): the mechanics unlocked at ranks 2, 4 and 6 (trait
## ids, A first). Empty: the classic ranks' new traits in order. The classic curve never
## reads it.
@export var mechanics: Array[StringName] = []
## M50.1a: per mechanic, the fields it sets once unlocked (absolute, like `ranks`): the
## shotgun's B (point blank) tightens the cone to 18 degrees. The classic curve never reads it.
@export var mechanic_values: Array[Dictionary] = []
## M50.1b (fusion, Arsenal depth design 4): a fused card's two parent weapon ids (empty: a
## base weapon). A fusion lives in weapons/fusions/<id>.tres (WeaponDB.fusions()); its
## `mechanics` are its own trait list (A2, B2, A4, B4 in the cycle's order), all at level 1
## from rank 1 (WeaponCurve.levels(rank, 4, true)).
@export var parents: Array[StringName] = []
## M50.1b: the mechanic names it keeps (parent A's rank-2 and rank-4, then B's): the UI, the
## recipe and the check (every one covered by a `mechanics` trait: the same id, or a variant
## named <id>_<fusion>).
@export var inherits: Array[StringName] = []
## M50.1b: "" = built; else the milestone that builds this fusion (a data row until then).
@export var built_in := ""
## M50.3b (Cluster): bomblets thrown on each blast of a player's shell (weapons/cluster_mod.gd,
## attached by Weapon.attach from the Loadout, never in Shooter.fire). 0 = none.
@export var burst := 0


## A field's value at `rank`: the rank's override, else the field.
func value(field: StringName, rank := 1) -> Variant:
	if rank >= 2 and rank - 2 < ranks.size() and ranks[rank - 2].has(String(field)):
		return ranks[rank - 2][String(field)]
	if rank >= 2 and rank - 2 < ranks.size() and ranks[rank - 2].has(field):
		return ranks[rank - 2][field]
	return get(field)


func traits_at(rank: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if rank < 2 or rank - 2 >= ranks.size():
		return out
	var d: Dictionary = ranks[rank - 2]
	var list: Variant = d.get("traits", d.get(&"traits", []))
	for t: Variant in list:
		out.append(StringName(t))
	return out


func max_rank() -> int:
	return 1 + ranks.size()


func is_passive() -> bool:
	return mode == &"passive"


## M50.1b: a fused card (two parents).
func is_fusion() -> bool:
	return not parents.is_empty()


## M50.1b: `mechanics` covers inherited mechanic `name` (the same trait, or its variant).
func covers(name: StringName) -> bool:
	return mechanics.any(func(m: StringName) -> bool: return m == name or String(m).begins_with(String(name) + "_"))


## Everything wrong with this weapon on its own. `file_id` is its file name.
func problems(file_id: StringName = id) -> Array[String]:
	var out: Array[String] = []
	var where := "weapon %s" % file_id
	if id != file_id:
		out.append("%s: id %s is not its file's name" % [where, id])
	if not mode in MODES:
		out.append("%s: unknown mode %s (%s)" % [where, mode, MODES])
	if cooldown <= 0.0:
		out.append("%s: cooldown must be > 0" % where)
	if pellets < 1:
		out.append("%s: pellets must be >= 1 (passive: the shard count)" % where)
	if title.strip_edges() == "":
		out.append("%s: no title" % where)
	if is_fusion():
		if parents.size() != 2 or parents[0] == parents[1]:
			out.append("%s: a fusion needs two different parents (%s)" % [where, parents])
		if inherits.size() != 4:
			out.append("%s: a fusion inherits 4 mechanics, not %d" % [where, inherits.size()])
		if built_in != "":
			out.append("%s: not built yet (%s)" % [where, built_in])
			return out
		for name in inherits:
			if not covers(name):
				out.append("%s: no trait covers the inherited %s" % [where, name])
	if node_script != "" and not is_passive():
		out.append("%s: node_script on an aimed weapon" % where)
	if node_script != "" and not ResourceLoader.exists(node_script):
		out.append("%s: no node script %s" % [where, node_script])
	var fields := {}
	for p: Dictionary in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			fields[p.name] = true
	var previous: Array[StringName] = []
	for i in ranks.size():
		var rank := i + 2
		for key: Variant in ranks[i]:
			var k := String(key)
			if k in RANK_KEYS_EXTRA:
				continue
			if not fields.has(k) or k in ["id", "mode", "ranks", "card_text", "pitch", "title"]:
				out.append("%s: rank %d sets %s, not a rank field" % [where, rank, k])
		var now := traits_at(rank)
		for t in now:
			if not ResourceLoader.exists(TRAITS_DIR + String(t) + ".gd"):
				out.append("%s: rank %d: no trait %s (%s%s.gd)" % [where, rank, t, TRAITS_DIR, t])
		for t in previous:
			if not t in now:
				out.append("%s: rank %d drops rank %d's trait %s (traits are cumulative)" % [where, rank, rank - 1, t])
		previous = now
		if rank >= 4:
			out.append("%s: rank 4 is not built yet (M50.1)" % where)
	for m in mechanics:
		if not ResourceLoader.exists(TRAITS_DIR + String(m) + ".gd"):
			out.append("%s: mechanic %s is not built yet (%s%s.gd)" % [where, m, TRAITS_DIR, m])
	if mechanic_values.size() > maxi(mechanics.size(), 3):
		out.append("%s: %d mechanic_values for %d mechanics" % [where, mechanic_values.size(), mechanics.size()])
	for i in mechanic_values.size():
		for key: Variant in mechanic_values[i]:
			var k := String(key)
			if not fields.has(k) or k in ["id", "mode", "ranks", "card_text", "pitch", "title", "damage"]:
				out.append("%s: mechanic %d sets %s, not a rank field" % [where, i, k])
	if card_text.size() != max_rank():
		out.append("%s: %d card lines for %d ranks" % [where, card_text.size(), max_rank()])
	return out
