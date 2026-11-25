class_name BoosterPack
extends RefCounted
# path:arsenal
## Arsenal's booster pack (M50.1a, Arsenal depth design 2): up to 3 weapon cards, common or
## rare, drawn from RunState.pack_rng. Every pack draws EXACTLY DRAWS numbers in a fixed order
## (card 1, 2, 3: a rarity roll then an id roll), whatever the hand or the pool, so two runs
## whose hands differ keep the same stream position and the bot probes stay paired by seed.
## A roll that is not needed is drawn and ignored. Never draws anything else (PLAN 1.4).
##
## Candidates: the live pool (PathRunner.offer_pool) plus the held aimed cards, one per id:
## held -> `upgrade` (+1, rare +2), not held -> `new` (rank 1, rare 3). Passives are not in a
## pack yet (none is reachable on Arsenal before S11). Weights: the taste's, x UPGRADE_LEAN
## for an upgrade (PickOffer's).
## Guarantees: G1 card 1 is a held card (the most-fired; ties slot order); G2 no two cards share
## (id, rarity), and with fewer ids than cards a shown id comes back at its other rarity (a
## one-weapon pool shows 2 cards); G3 with room in the hand card 2 is a new weapon when one
## exists; G4 a weapon a full-hand `give` queued is card 2, a new card at the give's rarity.
##
## M50.1b (fusion): a held fusion's parent ids fold into the fused id (one candidate: a parent's
## card feeds the fusion). G1 prefers the lower-ranked half of a held recipe pair (one half
## below FUSE_RANK) over the most-fired card. G5: fuse_option() is the pack's 4th choice when
## the hand is a built recipe pair with both at FUSE_RANK or more (the caller checks the
## `fusion` basic). After FUSE the same pack stays open: recompute() rebuilds its cards for
## the new hand (a pure function, nothing drawn).

const DRAWS := 6
## M50.1b: both halves of a recipe pair need this rank to fuse (owner, 2026-11-25).
const FUSE_RANK := 4
const RARE := &"rare"
const COMMON := &"common"


## The pack for `loadout` on path `def`. `give` (G4): {} or {id, rare}. Card dictionaries:
## {id, rank (the rank it gives), from (the held rank, 0 for new), kind, rarity, title, gain,
## text}.
static func draw(loadout: Loadout, def: PathDef, pool: Array[StringName], give: Dictionary,
		rng: RandomNumberGenerator, taste: Taste) -> PickOffer:
	var rolls: Array[float] = []
	for i in DRAWS:
		rolls.append(rng.randf())
	var chance := def.rare_chance if def != null else 0.0
	var offer := PickOffer.new()
	offer.pack = true
	offer.line = def.pick_line if def != null else "Pack. Pick one."
	offer.max_slots = loadout.max_slots
	for w in loadout.slots:
		offer.hand.append({"id": w.def.id, "title": w.def.title, "rank": w.rank})
	var cands := candidates(loadout, pool)
	# G1: card 1 is a held card (M50.1b: the lower half of a recipe pair first).
	var first := recipe_low_half(loadout)
	if first == &"":
		first = most_fired(loadout)
	if first == &"":
		for c: Dictionary in cands:
			if c.kind == &"upgrade":
				first = c.id
				break
	if first != &"":
		offer.cards.append(card(loadout, first, rolls[0] < chance))
	var rest := cands.filter(func(c: Dictionary) -> bool: return c.id != first)
	# Card 2: G4, else G3, else any.
	var given: StringName = give.get("id", &"")
	if given != &"" and loadout.holder(given) == null and WeaponDB.has(given):
		offer.cards.append(card(loadout, given, bool(give.get("rare", false))))
		rest = rest.filter(func(c: Dictionary) -> bool: return c.id != given)
	else:
		var from := rest
		if not loadout.hand_full():
			var news := rest.filter(func(c: Dictionary) -> bool: return c.kind == &"new")
			if not news.is_empty():
				from = news
		_take(offer, loadout, from, rest, rolls[2], rolls[3], chance, taste)
	# Card 3.
	_take(offer, loadout, rest, rest, rolls[4], rolls[5], chance, taste)
	return offer


## One card from `from` by weight (removed from `rest`), else a shown id at its other rarity
## (G2), else nothing.
static func _take(offer: PickOffer, loadout: Loadout, from: Array, rest: Array, rarity_roll: float,
		id_roll: float, chance: float, taste: Taste) -> void:
	if not from.is_empty():
		var pick := weighted(from, id_roll, taste)
		var id: StringName = from[pick].id
		offer.cards.append(card(loadout, id, rarity_roll < chance))
		for i in rest.size():
			if rest[i].id == id:
				rest.remove_at(i)
				break
		return
	for c: Dictionary in offer.cards.duplicate():
		var other: bool = c.rarity == COMMON
		if not _shown(offer, c.id, RARE if other else COMMON):
			offer.cards.append(card(loadout, c.id, other))
			return


static func _shown(offer: PickOffer, id: StringName, rarity: StringName) -> bool:
	return offer.cards.any(func(c: Dictionary) -> bool: return c.id == id and c.rarity == rarity)


## The index `roll` (0..1) picks out of `cands` by cumulative weight (PickOffer's loop).
static func weighted(cands: Array, roll: float, taste: Taste) -> int:
	var weights: Array[float] = []
	var total := 0.0
	for c: Dictionary in cands:
		var w := (taste.weight_mult_raw(c.id, []) if taste != null else 1.0) \
				* (PickOffer.UPGRADE_LEAN if c.kind == &"upgrade" else 1.0)
		weights.append(w)
		total += w
	var left := roll * total
	for i in cands.size():
		left -= weights[i]
		if left < 0.0:
			return i
	return cands.size() - 1


## One candidate per id: the held aimed cards (slot order), then the pool's.
static func candidates(loadout: Loadout, pool: Array[StringName]) -> Array:
	var out: Array = []
	var ids: Array[StringName] = []
	for w in loadout.slots:
		ids.append(w.def.id)
	ids.append_array(pool)
	var seen := {}
	for raw in ids:
		var id := fold(loadout, raw)
		if seen.has(id):
			continue
		seen[id] = true
		var w := WeaponDB.get_weapon(id)
		if w == null or w.is_passive():
			continue
		var held := loadout.held(id)
		if held != null and loadout.rank_cap > 0 and held.rank >= loadout.rank_cap:
			continue
		out.append({"id": id, "kind": &"upgrade" if held != null else &"new"})
	return out


## M50.1b: `id`, or the held fusion it is a parent of (its cards feed the fusion).
static func fold(loadout: Loadout, id: StringName) -> StringName:
	var w := loadout.holder(id)
	return w.def.id if w != null else id


## M50.1b: the hand's recipe pair ([a, b, fused id], slot order) when its two aimed cards are
## different base weapons whose fusion is built; [] otherwise.
static func recipe_pair(loadout: Loadout) -> Array:
	if loadout.slots.size() != 2:
		return []
	var a := loadout.slots[0].def
	var b := loadout.slots[1].def
	if a.is_fusion() or b.is_fusion():
		return []
	var f := WeaponDB.recipe(a.id, b.id)
	if f == &"" or not WeaponDB.fusion_built(f):
		return []
	return [a.id, b.id, f]


## M50.1b (G1): the lower-ranked half of the hand's recipe pair while one half is below
## FUSE_RANK (ties: slot order), else &"".
static func recipe_low_half(loadout: Loadout) -> StringName:
	var pair := recipe_pair(loadout)
	if pair.is_empty():
		return &""
	var ra := loadout.rank_of(pair[0])
	var rb := loadout.rank_of(pair[1])
	if ra >= FUSE_RANK and rb >= FUSE_RANK:
		return &""
	return pair[1] if rb < ra else pair[0]


## M50.1b: the hand is a recipe pair with both halves at FUSE_RANK or more (cheap: no texts).
static func can_fuse(loadout: Loadout) -> bool:
	var pair := recipe_pair(loadout)
	return not pair.is_empty() and loadout.rank_of(pair[0]) >= FUSE_RANK and loadout.rank_of(pair[1]) >= FUSE_RANK


## M50.1b (G5): the FUSE choice for this hand, or {} when the pair is not ready: {a, b, id,
## rank (ceili of the average), title, keeps (the 4 inherited mechanics' lines at the fused
## rank), loses (the parents' rank-6 mechanics they hold), text}.
static func fuse_option(loadout: Loadout) -> Dictionary:
	var pair := recipe_pair(loadout)
	if pair.is_empty():
		return {}
	var wa := loadout.held(pair[0])
	var wb := loadout.held(pair[1])
	if wa.rank < FUSE_RANK or wb.rank < FUSE_RANK:
		return {}
	var f := WeaponDB.get_weapon(pair[2])
	var rank := loadout.cap(ceili((wa.rank + wb.rank) / 2.0))
	var keeps: Array[String] = []
	for t: Array in WeaponCurve.traits(f, rank):
		keeps.append(WeaponTrait.make(t[0], t[1], true).describe(t[1]))
	var loses: Array[String] = []
	for w in [wa, wb]:
		var mech := WeaponCurve.mechanics(w.def)
		var lv := WeaponCurve.levels_of(w.def, w.rank)
		for i in range(2, mech.size()):
			if lv[i] > 0:
				loses.append(String(mech[i]).replace("_", " "))
	var title := "FUSE: %s %d + %s %d -> %s %d" % [wa.def.title, wa.rank, wb.def.title, wb.rank, f.title, rank]
	var text := title + "\n" + "\n".join(keeps)
	if not loses.is_empty():
		text += "\nloses: " + ", ".join(loses)
	return {"a": pair[0], "b": pair[1], "id": pair[2], "rank": rank, "title": title, "keeps": keeps,
			"loses": loses, "text": text}


## M50.1b review: on a full hand that is not a recipe pair, a NEW card that makes a built
## recipe with exactly one held card marks that card kept (`keep`: its hand index): the
## replace step names the link and lets only the other card go, so a first play cannot
## drop the partner and dead-end S9's fusion. Done for a path whose basics hold `fusion`.
static func mark_keeps(offer: PickOffer, loadout: Loadout) -> void:
	if loadout.slots.size() != 2 or not loadout.hand_full() or not recipe_pair(loadout).is_empty():
		return
	for c: Dictionary in offer.cards:
		if c.get("kind") != &"new":
			continue
		var links: Array[int] = []
		for j in 2:
			var h := loadout.slots[j].def
			if h.is_fusion():
				continue
			var f := WeaponDB.recipe(c.id, h.id)
			if f != &"" and WeaponDB.fusion_built(f):
				links.append(j)
		if links.size() == 1:
			c["keep"] = links[0]


## M50.1b: the same pack after FUSE, for the new hand: each card's id folded (a parent's card
## now feeds the fusion), its rarity kept, its kind and text recomputed; a card that would
## repeat a shown (id, rarity) goes. Nothing is drawn.
static func recompute(offer: PickOffer, loadout: Loadout) -> PickOffer:
	var out := PickOffer.new()
	out.pack = true
	out.line = offer.line
	out.max_slots = loadout.max_slots
	for w in loadout.slots:
		out.hand.append({"id": w.def.id, "title": w.def.title, "rank": w.rank})
	for c: Dictionary in offer.cards:
		var id := fold(loadout, c.id)
		var rare: bool = c.get("rarity") == RARE
		if _shown(out, id, RARE if rare else COMMON):
			continue
		out.cards.append(card(loadout, id, rare))
	return out


## The held aimed card with the most shots that can still rank up (ties: slot order).
static func most_fired(loadout: Loadout) -> StringName:
	var best: Weapon = null
	for w in loadout.slots:
		if loadout.rank_cap > 0 and w.rank >= loadout.rank_cap:
			continue
		if best == null or w.shots > best.shots:
			best = w
	return best.def.id if best != null else &""


## The card for weapon `id` (held: an upgrade; else new).
static func card(loadout: Loadout, id: StringName, rare: bool) -> Dictionary:
	var w := WeaponDB.get_weapon(id)
	var held := loadout.held(id)
	var rarity := RARE if rare else COMMON
	if held != null:
		var to := loadout.cap(held.rank + (2 if rare else 1))
		var title := "%s %d -> %d" % [w.title, held.rank, to]
		var gain := WeaponCurve.gain_text(w, held.rank, to) if held.deep() else PickOffer.card_line(w, mini(to, w.max_rank()), true)
		return {"id": id, "rank": to, "from": held.rank, "kind": &"upgrade", "rarity": rarity,
				"title": title, "gain": gain, "text": "%s: %s" % [title, gain]}
	var rank := loadout.cap(3 if rare else 1)
	var title2 := "%s %d" % [w.title, rank]
	var gain2 := ("joins your hand" if not loadout.hand_full() else "replaces a card")
	var have := WeaponCurve.have_text(w, rank) if loadout.curve == WeaponCurve.DEEP else w.pitch
	if have != "":
		gain2 += ": " + have
	return {"id": id, "rank": rank, "from": 0, "kind": &"new", "rarity": rarity, "title": title2,
			"gain": gain2, "text": "%s: %s" % [title2, gain2]}


## A card's tags: "NEW", "RARE +2", "NEW  RARE".
static func tags(c: Dictionary) -> String:
	var out: Array[String] = []
	if c.get("kind") == &"new":
		out.append("NEW")
	if c.get("rarity") == RARE:
		out.append("RARE" if c.get("kind") == &"new" else "RARE +2")
	return "  ".join(out)
