class_name WeaponCurve
extends RefCounted
## The deep rank curve (M50.1a, Arsenal depth design 3; shared: Auto moves to it later with a
## cap). Odd ranks hit harder at kill breakpoints (MULT), ranks 2, 4 and 6 each unlock a
## mechanic (WeaponDef.mechanics A, B, C), and every even rank after that strengthens one in
## the cycle A, B, C, A... (3 steps each, a maxed one skipped; once all are maxed each even
## rank keeps strengthening: overflow, WeaponTrait.OVERFLOW). No top rank. Pure functions:
## nothing here reads RunState or any random stream. The classic curve (WeaponDef.ranks 2-3)
## never comes here.

const CLASSIC := &"classic"
const DEEP := &"deep"
## Damage multiplier at each odd rank up to 11; past 11, +1 per odd rank (13: x7, 15: x8).
const MULT := {1: 1.0, 3: 1.5, 5: 2.0, 7: 3.0, 9: 4.0, 11: 6.0}
## Ranks that unlock mechanic A, B, C.
const UNLOCK: Array[int] = [2, 4, 6]
## Strengthen steps per mechanic (levels 2-4), then overflow.
const STEPS := 3
const TOP_LEVEL := 1 + STEPS
## The breakpoint text reads the roster from EnemyDB.READING and each HP from Tuning
## ("<id>_hp"): no second enemy list here.


## An enemy's HP for the breakpoint text (Tuning "<id>_hp").
static func roster_hp(id: StringName) -> float:
	return float(Tuning.get("%s_hp" % id))


## The damage multiplier at `rank` (even ranks keep the odd rank below).
static func mult(rank: int) -> float:
	var r := maxi(1, rank)
	if r % 2 == 0:
		r -= 1
	if MULT.has(r):
		return float(MULT[r])
	return 6.0 + float(r - 11) / 2.0


## Each mechanic's level at `rank` for `n` mechanics (0 = locked, 1 = unlocked, 2-4 =
## strengthened, 5+ = overflow). `fused` (M50.1b): all n unlocked from rank 1, strengthens
## from rank 6.
static func levels(rank: int, n: int, fused := false) -> Array[int]:
	var lv: Array[int] = []
	lv.resize(n)
	lv.fill(1 if fused else 0)
	if n <= 0:
		return lv
	var next := 0
	var r := 2
	while r <= rank:
		var unlock_rank := not fused and r <= UNLOCK[UNLOCK.size() - 1]
		if unlock_rank:
			var i := UNLOCK.find(r)
			if i >= 0 and i < n:
				lv[i] = 1
		elif not fused or r >= 6:
			var pick := -1
			for k in n:
				var j := (next + k) % n
				if lv[j] > 0 and lv[j] < TOP_LEVEL:
					pick = j
					break
			if pick < 0:   # all maxed (or locked): overflow in the same cycle
				for k in n:
					var j := (next + k) % n
					if lv[j] > 0:
						pick = j
						break
			if pick >= 0:
				lv[pick] += 1
				next = (pick + 1) % n
		r += 2
	return lv


## M50.1b: `def`'s mechanic levels at `rank` (a fusion: all unlocked from rank 1). M50.4c1: an
## evolution too (held at rank 1, so every mechanic is at level 1).
static func levels_of(def: WeaponDef, rank: int) -> Array[int]:
	return levels(rank, mechanics(def).size(), def.is_fusion() or def.is_evolution())


## The deep-curve mechanics of `def`: its `mechanics` list, else its classic ranks' new
## traits in order (A at rank 2, B at rank 3).
static func mechanics(def: WeaponDef) -> Array[StringName]:
	if not def.mechanics.is_empty():
		return def.mechanics.duplicate()
	var out: Array[StringName] = []
	for r in range(2, def.max_rank() + 1):
		for t in def.traits_at(r):
			if not t in out:
				out.append(t)
	return out


## A built mechanic (its trait script exists).
static func built(trait_id: StringName) -> bool:
	return ResourceLoader.exists(WeaponDef.TRAITS_DIR + String(trait_id) + ".gd")


## [[trait id, level], ...] at `rank` on the deep curve (unlocked and built only, A first).
static func traits(def: WeaponDef, rank: int) -> Array:
	var out: Array = []
	var mech := mechanics(def)
	var lv := levels_of(def, rank)
	for i in mech.size():
		if lv[i] > 0 and built(mech[i]):
			out.append([mech[i], lv[i]])
	return out


## A field on the deep curve: damage = base x mult(rank); any other field is the def's, as
## each unlocked mechanic's WeaponDef.mechanic_values sets it (never WeaponDef.ranks).
static func value(def: WeaponDef, field: StringName, rank: int) -> Variant:
	if field == &"damage":
		return def.damage * mult(rank)
	var v: Variant = def.get(field)
	var lv := levels_of(def, rank)
	for i in mini(lv.size(), def.mechanic_values.size()):
		if lv[i] <= 0:
			continue
		var d: Dictionary = def.mechanic_values[i]
		if d.has(String(field)):
			v = d[String(field)]
		elif d.has(field):
			v = d[field]
	return v


## Hits to kill `hp` at `damage` per hit (0 damage: a huge number).
static func hits_to_kill(hp: float, damage: float) -> int:
	if damage <= 0.0:
		return 1 << 20
	return maxi(1, ceili(hp / damage - 0.0001))


## What crossing from rank `from` to `to` changes in kill counts against the roster (per
## pellet for the shotgun): "one-shots chasers and lancers", "tank in 3". "" when nothing.
static func breakpoint_text(def: WeaponDef, from: int, to: int) -> String:
	var before := def.damage * mult(from)
	var after := def.damage * mult(to)
	var ones: Array[String] = []
	var others := {}   # count -> names
	var order: Array[int] = []
	for e in EnemyDB.READING:
		var hp := roster_hp(e)
		var a := hits_to_kill(hp, before)
		var b := hits_to_kill(hp, after)
		if b >= a:
			continue
		if b == 1:
			ones.append(String(e) + "s")
		else:
			if not others.has(b):
				others[b] = []
				order.append(b)
			(others[b] as Array).append(String(e))
	var parts: Array[String] = []
	if not ones.is_empty():
		parts.append("one-shots " + _and(ones))
	for b in order:
		parts.append("%s in %d" % ["/".join(others[b]), b])
	return ", ".join(parts)


## The card line's gain from rank `from` to `to` (to > from): per rank, the breakpoint or
## the damage on an odd rank, the mechanic unlocked or strengthened on an even rank.
static func gain_text(def: WeaponDef, from: int, to: int) -> String:
	var parts: Array[String] = []
	var mech := mechanics(def)
	var lv_from := levels_of(def, from)
	var dmg_from := from
	for r in range(from + 1, to + 1):
		if r % 2 == 1:
			continue
		var lv := levels_of(def, r)
		for i in mech.size():
			if lv[i] != lv_from[i]:
				if not built(mech[i]):
					parts.append("%s (not built yet)" % String(mech[i]).replace("_", " "))
				else:
					var t := WeaponTrait.make(mech[i], lv[i], true)
					parts.append(("%s" if lv[i] == 1 else "+%s") % t.describe(lv[i]))
		lv_from = lv
	if mult(to) != mult(dmg_from):
		var bp := breakpoint_text(def, dmg_from, to)
		if bp != "":
			parts.push_front(bp)
		else:
			parts.push_front("damage %s -> %s" % [num(def.damage * mult(dmg_from)), num(def.damage * mult(to))])
	return ", ".join(parts)


## What a card at `rank` has (a new card's line): its unlocked mechanics, or the pitch.
static func have_text(def: WeaponDef, rank: int) -> String:
	var parts: Array[String] = []
	for pair: Array in traits(def, rank):
		parts.append(WeaponTrait.make(pair[0], pair[1], true).describe(pair[1]))
	if parts.is_empty():
		return def.pitch
	return ", ".join(parts)


## "4th", "2nd", "3rd", "21st".
static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [n, suffix]


## 1 -> "1", 1.5 -> "1.5", 1.25 -> "1.25".
static func num(x: float) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(roundi(x))
	return str(snappedf(x, 0.01))


static func _and(names: Array[String]) -> String:
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]
