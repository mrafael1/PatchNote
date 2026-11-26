class_name PickOffer
extends RefCounted
## An in-run pick (PLAN v9 1.4, 1.5): up to three weapon cards (Arsenal's card meter, Auto's
## level-ups; the panel's line is the path's pick_line, M46). Never an Offer: a pick goes to the Loadout only, never RunState.apply, the
## AiDirector, the save, build_number or the patch notes (0.4). Drawn from pick_rng out of
## the live pool (the pool rule, 1.2), leaning on the session's taste.

## Each card: {id, rank, kind: new | upgrade | hp, text}. M50.4b: an item card adds `item: true`
## (its rank is the item's level). M50.1a: a pack's cards add rarity
## (common | rare), from, title and gain (BoosterPack).
var cards: Array[Dictionary] = []
var line := ""
## M50.1a: a booster pack (BoosterPack.draw; Arsenal). Its cards also carry rarity, from, title
## and gain; `hand` is the hand when it was drawn ([{id, title, rank}], slot order) and
## max_slots its size, for the panel's hand preview and the replace step.
var pack := false
var hand: Array[Dictionary] = []
var max_slots := 0
## M50.1b: the pack's FUSE choice (BoosterPack.fuse_option; {} none). It is the choice after
## the cards (key choose_4 on a 3-card pack) and never replaces one.
var fuse := {}
## M50.4b (Auto depth design 7): a level-up offer (PathRunner, a levelups path) carries the level
## it was drawn at and the path's rank cap, for the dressed cards (LevelCard). 0: a plain panel.
var level := 0
var cap := 0
## M50.4c1 (Auto depth design 2.5): the level-up's EVOLVE choice ({} none): {from, into,
## catalyst, rank, text}. Like Arsenal's FUSE it is the choice after the cards (key choose_4 on
## 3 cards, choose_3 on 2) and never replaces one, so the pick_rng draws do not change. Taking it
## spends the level-up (PathRunner._take_evolve).
var evolve := {}
## M50.2b (the give step): a `give` that landed on a full pack hand. `cards` is the one given
## card (BoosterPack.give_card, plus `links`: the hand index it makes a built recipe with, -1
## none; `recipe`: the fused title once the `fusion` basic is live, else ""). The panel opens it
## straight on the replace step, whose last choice is "Keep your hand". It draws nothing and is
## not a pack pick (`pack` is set only for the hand preview and the bot's chooser).
var give_step := false

const HP := &"hp"
## M50.4a (Auto depth design 2.8): the second filler, +Loadout.BOOST_STEP damage this session.
const BOOST := &"boost"
## Auto leans to the weapons it holds (D7): an upgrade card weighs this much more.
const UPGRADE_LEAN := 1.4
const ROMAN: Array[String] = ["I", "II", "III", "IV"]


## The offer for `loadout` on path `def`. `pool`: the live pool (ids, in order). `first`: a
## weapon a `give` cue is waiting to offer first ("" for none). `taste`: the session's
## (never saved). Upgrades stop at the top rank (classic: Loadout.MAX_RANK; deep: the
## Loadout's rank_cap, M50.4a); nothing to offer gives the filler, +1 HP (M50.4a: on a
## levelups path two fillers, +1 max HP and +5% damage; never padding an offer that has cards).
static func draw(loadout: Loadout, def: PathDef, pool: Array[StringName], first: StringName,
		rng: RandomNumberGenerator, taste: Taste) -> PickOffer:
	var offer := PickOffer.new()
	var candidates: Array[Dictionary] = []
	for id in pool:
		var card := candidate(loadout, def, id)
		if not card.is_empty():
			candidates.append(card)
	for i in candidates.size():
		if candidates[i].id == first:
			offer.cards.append(candidates[i])
			candidates.remove_at(i)
			break
	while offer.cards.size() < 3 and not candidates.is_empty():
		var weights: Array[float] = []
		var total := 0.0
		for c in candidates:
			var w := taste.weight_mult_raw(c.id, []) * (UPGRADE_LEAN if c.kind == &"upgrade" else 1.0)
			weights.append(w)
			total += w
		var roll := rng.randf() * total
		var pick := candidates.size() - 1
		for i in candidates.size():
			roll -= weights[i]
			if roll < 0.0:
				pick = i
				break
		offer.cards.append(candidates[pick])
		candidates.remove_at(pick)
	if offer.cards.is_empty() and def != null and def.growth == &"levelups" and def.shared_slots:
		offer.cards.append({"id": HP, "rank": 0, "kind": HP, "text": "+1 max HP, heal 1"})
		offer.cards.append({"id": BOOST, "rank": 0, "kind": BOOST,
				"text": "+%d%% damage, every gun (this session)" % roundi(Loadout.BOOST_STEP * 100.0)})
	elif offer.cards.is_empty():
		offer.cards.append({"id": HP, "rank": 0, "kind": HP, "text": "+1 HP (this session)"})
	offer.line = def.pick_line if def != null else "Level up. Pick one."
	return offer


## One card for weapon `id`, or {} when it cannot be offered: held below its top rank (an
## upgrade to the next rank), or not held with a free slot (new, rank 1; passives against
## def.max_passives). M50.4a: a deep weapon tops out at the Loadout's rank_cap (Auto 6), and
## with shared slots a new weapon of any mode needs one of max_slots free.
static func candidate(loadout: Loadout, def: PathDef, id: StringName) -> Dictionary:
	if WeaponDB.has_item(id):
		return item_candidate(loadout, def, id)
	var w := WeaponDB.get_weapon(id)
	if w == null:
		return {}
	var held := loadout.held(id)
	if held == null and loadout.shared_slots and loadout.evolution_of(id) != null:
		return {}   # M50.4c1: evolved; the base never comes back
	if held != null and w.is_evolution():
		return {}   # M50.4c1: an evolution has no further ranks
	if held != null:
		var top := mini(Loadout.MAX_RANK, w.max_rank())
		if held.deep():
			top = loadout.rank_cap if loadout.rank_cap > 0 else 1 << 20
		if held.rank >= top:
			return {}
		return {"id": id, "rank": held.rank + 1, "kind": &"upgrade",
				"text": card_line(w, held.rank + 1, true, held.deep())}
	if loadout.shared_slots:
		if loadout.weapon_count() >= loadout.max_slots:
			return {}
		return {"id": id, "rank": 1, "kind": &"new", "text": card_line(w, 1, false, loadout.curve == WeaponCurve.DEEP)}
	if w.is_passive():
		if loadout.passives.size() >= (def.max_passives if def != null else 0):
			return {}
	elif loadout.slots.size() >= loadout.max_slots:
		return {}
	return {"id": id, "rank": 1, "kind": &"new", "text": card_line(w, 1, false)}


## M50.4b (Auto depth design 2.4): an item card, or {}: held below the rank cap (+1 level), or
## not held, built, with one of def.max_items free (level 1). Unbuilt items are never offered.
static func item_candidate(loadout: Loadout, def: PathDef, id: StringName) -> Dictionary:
	var it := WeaponDB.item(id)
	if it == null or not it.built():
		return {}
	var top := loadout.rank_cap if loadout.rank_cap > 0 else Loadout.MAX_RANK
	var held := loadout.item_level(id)
	if held > 0:
		if held >= top:
			return {}
		return {"id": id, "rank": held + 1, "kind": &"upgrade", "item": true,
				"paired": loadout.held(it.pairs) != null, "text": item_line(it, held + 1, loadout)}
	if loadout.items.size() >= (def.max_items if def != null else loadout.max_items):
		return {}
	return {"id": id, "rank": 1, "kind": &"new", "item": true, "paired": loadout.held(it.pairs) != null,
			"text": item_line(it, 1, loadout)}


## M50.4b: "Haste 1: guns fire 6% faster  (new)" / "Haste 2 -> 3: guns fire 18% faster (was
## 12%)", then " · your Pistol evolves with this" when its weapon is held.
static func item_line(it: ItemDef, level: int, loadout: Loadout = null) -> String:
	var text := "%s 1: %s  (new)" % [it.title, it.effect(1)] if level <= 1 else 			"%s %d -> %d: %s (was %s)" % [it.title, level - 1, level, it.effect(level), it.pct(level - 1)]
	var w := WeaponDB.get_weapon(it.pairs)
	if loadout != null and w != null and loadout.held(it.pairs) != null:
		text += " · your %s evolves with this" % w.title
	return text


## "Shotgun II: knockback.  (I -> II)" for an upgrade, the rank-1 line plus "(new)" else.
## M50.4a: on the deep curve the digits and the gain ("Pistol 3 -> 4: seeker"); ROMAN is the
## classic curve's only (ranks 2-3).
static func card_line(w: WeaponDef, rank: int, upgrade: bool, deep := false) -> String:
	if deep and upgrade:
		var gain := WeaponCurve.gain_text(w, rank - 1, rank)
		return "%s %d -> %d%s" % [w.title, rank - 1, rank, (": " + gain) if gain != "" else ""]
	if deep:
		return "%s  (new)" % (w.card_text[0] if not w.card_text.is_empty() else w.title)
	var text := w.card_text[rank - 1] if rank - 1 < w.card_text.size() else w.title
	if upgrade:
		return "%s  (%s -> %s)" % [text, ROMAN[rank - 2], ROMAN[rank - 1]]
	return "%s  (new)" % text


## M50.4c1: the EVOLVE choice's line, "EVOLVE: Pistol 6 + Haste -> MINIGUN: a stream of
## bullets." (the plain panel's text and the logs').
static func evolve_line(from: WeaponDef, item: ItemDef, into: WeaponDef, rank: int) -> String:
	return "EVOLVE: %s %d + %s -> %s: %s" % [from.title, rank, item.title, into.title.to_upper(),
			into.pitch.to_lower().trim_suffix(".") + "."]


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for c in cards:
		out.append(c.id)
	return out
