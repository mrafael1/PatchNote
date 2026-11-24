class_name PickOffer
extends RefCounted
## An in-run pick (PLAN v9 1.4, 1.5): up to three weapon cards (Arsenal's card meter, Auto's
## level-ups). Never an Offer: a pick goes to the Loadout only, never RunState.apply, the
## AiDirector, the save, build_number or the patch notes (0.4). Drawn from pick_rng out of
## the live pool (the pool rule, 1.2), leaning on the session's taste.

## Each card: {id, rank, kind: new | upgrade | hp, text}.
var cards: Array[Dictionary] = []
var line := ""

const HP := &"hp"
## Auto leans to the weapons it holds (D7): an upgrade card weighs this much more.
const UPGRADE_LEAN := 1.4
const ROMAN: Array[String] = ["I", "II", "III", "IV"]


## The offer for `loadout` on path `def`. `pool`: the live pool (ids, in order). `first`: a
## weapon a `give` cue is waiting to offer first ("" for none). `taste`: the session's
## (never saved). Upgrades stop at Loadout.MAX_RANK (rank 4 is M50.1); nothing to offer
## gives the one filler, +1 HP.
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
	if offer.cards.is_empty():
		offer.cards.append({"id": HP, "rank": 0, "kind": HP, "text": "+1 HP (this session)"})
	offer.line = "Level up. Pick one."
	return offer


## One card for weapon `id`, or {} when it cannot be offered: held below its top rank (an
## upgrade to the next rank), or not held with a free slot (new, rank 1; passives against
## def.max_passives).
static func candidate(loadout: Loadout, def: PathDef, id: StringName) -> Dictionary:
	var w := WeaponDB.get_weapon(id)
	if w == null:
		return {}
	var held := loadout.held(id)
	if held != null:
		var top := mini(Loadout.MAX_RANK, w.max_rank())
		if held.rank >= top:
			return {}
		return {"id": id, "rank": held.rank + 1, "kind": &"upgrade", "text": card_line(w, held.rank + 1, true)}
	if w.is_passive():
		if loadout.passives.size() >= (def.max_passives if def != null else 0):
			return {}
	elif loadout.slots.size() >= loadout.max_slots:
		return {}
	return {"id": id, "rank": 1, "kind": &"new", "text": card_line(w, 1, false)}


## "Shotgun II: knockback.  (I -> II)" for an upgrade, the rank-1 line plus "(new)" else.
static func card_line(w: WeaponDef, rank: int, upgrade: bool) -> String:
	var text := w.card_text[rank - 1] if rank - 1 < w.card_text.size() else w.title
	if upgrade:
		return "%s  (%s -> %s)" % [text, ROMAN[rank - 2], ROMAN[rank - 1]]
	return "%s  (new)" % text


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for c in cards:
		out.append(c.id)
	return out
