class_name Unlocks
extends RefCounted
## What the save has unlocked (PLAN v5 1.6), read from SaveGame. With
## SaveGame.unlock_all (inert, the default) everything is: every unparked patch, every
## enemy and the tier 1 `punchy` look, today's feel. The Director and the spawner read
## this from M28 on (start content gating).

## Every enemy archetype the spawner knows (a change may unlock one of these).
const ARCHETYPES: Array[StringName] = [&"chaser", &"shooter", &"tank"]
const FULL_LOOK := {"tier": 1, "take": "punchy"}


## Patches that may be offered: the starters plus what shipped changes unlock, never
## a parked one. Sorted by id, like MutationDB.
static func pool() -> Array[Mutation]:
	if SaveGame.unlock_all:
		return MutationDB.offerable()
	var unlocked := shipped_unlocks()
	var out: Array[Mutation] = []
	for m in MutationDB.offerable():
		if m.starter or unlocked.has(m.id):
			out.append(m)
	return out


## Enemy archetypes that may spawn: Tuning.starter_enemies plus shipped ones.
static func enemies() -> Array[StringName]:
	if SaveGame.unlock_all:
		return ARCHETYPES.duplicate()
	var unlocked := shipped_unlocks()
	var out: Array[StringName] = []
	for a in ARCHETYPES:
		if a in Tuning.starter_enemies or unlocked.has(a):
			out.append(a)
	return out


## {tier, take}: the save's look (tier 0 when nothing shipped).
static func look() -> Dictionary:
	if SaveGame.unlock_all:
		return FULL_LOOK.duplicate()
	var l: Dictionary = SaveGame.state().look
	return {"tier": int(l.get("tier", 0)), "take": String(l.get("take", ""))}


## Everything the shipped changes unlock (patch ids and archetypes), in ship order.
static func shipped_unlocks() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in SaveGame.shipped():
		var c := ChangeDB.get_change(id)
		if c == null:
			continue
		for u in c.unlocks:
			if not out.has(u):
				out.append(u)
	return out


## "look=1:punchy pool=7 enemies=chaser,shooter,tank" for the bot line and F1.
static func summary() -> String:
	var l := look()
	return "look=%d:%s pool=%d enemies=%s" % [l.tier, l.take if l.take != "" else "-", pool().size(),
			",".join(enemies().map(func(a: StringName) -> String: return String(a)))]
