class_name Unlocks
extends RefCounted
## What the save has unlocked (PLAN v5 1.6), read from SaveGame. In a campaign session
## (RunState.session, PLAN v8) the session's data says it instead: its basics, its
## enemies, its look, and no offer pool. With
## SaveGame.unlock_all (inert, the default) everything is: every unparked patch, every
## enemy and the tier 1 `punchy` look, today's feel. The Director and the spawner read
## this from M28 on (start content gating).

## Every enemy archetype the spawner knows (a change may unlock one of these).
const ARCHETYPES: Array[StringName] = [&"chaser", &"shooter", &"tank", &"bomber", &"lancer"]
const FULL_LOOK := {"tier": 1, "take": "punchy"}
## The game's basics (PLAN v5 4.8): the first builds miss them and the first dev
## sessions ship them. Without movement the player can only aim and shoot; without
## enemies nothing spawns; without the level the arena is an empty box.
const BASICS: Array[StringName] = [&"movement", &"enemies", &"level"]
## The campaign's basics (PLAN v8, owner 2026-11-23): its first sessions also miss the
## gun and the dash, getting hurt (`health`: damage, death, the HP readout) and shots
## that hit (`hits`) (owner, M39.2: "nothing by default", the AI adds each piece), and the
## version stamp (`version`, S5, M42). Outside a session these are always on (the v6 loop
## never ships them).
const CAMPAIGN_BASICS: Array[StringName] = [&"movement", &"shooting", &"dash", &"enemies", &"level",
		&"health", &"hits", &"version"]


## Patches that may be offered: the starters plus what shipped changes unlock, never
## a parked one. Sorted by id, like MutationDB. A campaign session offers none: the AI
## hands things over itself (PLAN v8 0.2).
static func pool() -> Array[Mutation]:
	if RunState.session != null:
		return [] as Array[Mutation]
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
	if RunState.session != null:
		return RunState.session.enemy_types()
	if SaveGame.unlock_all:
		return ARCHETYPES.duplicate()
	var unlocked := shipped_unlocks()
	var out: Array[StringName] = []
	for a in ARCHETYPES:
		if a in Tuning.starter_enemies or unlocked.has(a):
			out.append(a)
	return out


## Whether a basic has shipped (always, while inert).
static func has_basic(id: StringName) -> bool:
	if RunState.session != null:
		return id in RunState.session.basics or id in RunState.session_added
	if not id in BASICS:
		return true
	return SaveGame.unlock_all or shipped_unlocks().has(id)


## The basics still missing, in BASICS order (none while inert).
static func missing_basics() -> Array[StringName]:
	var out: Array[StringName] = []
	for b in BASICS:
		if not has_basic(b):
			out.append(b)
	return out


## fork_dash's answer in the save (a style in Change.DASHES), classic while unanswered.
## Reads the save only, so Line conditions work with no session running.
static func dash_answer() -> StringName:
	var f: Fork = ChangeDB.get_fork(&"fork_dash")
	var a: Change = f.answer() if f != null else null
	return a.take.id if a != null and a.take != null else &"classic"


## The player's dash: the answer in a campaign session, always classic outside one
## (the v6 loop, run_hash, B2).
static func dash_style() -> StringName:
	return dash_answer() if RunState.session != null else &"classic"


## fork_dash_aim's answer in the save (aim or move, Change.DASH_AIMS), move while
## unanswered (an old save past S3 is never asked, so it stays on move). Save only.
static func dash_aim_answer() -> StringName:
	var f: Fork = ChangeDB.get_fork(&"fork_dash_aim")
	var a: Change = f.answer() if f != null else null
	return a.take.id if a != null and a.take != null else &"move"


## The dash goes along the player's aim (M42.2): the aim answer, in a campaign session
## only (outside one it always goes where you move: the v6 loop, run_hash, B2).
static func dash_aims() -> bool:
	return RunState.session != null and dash_aim_answer() == &"aim"


## The stage set the save's shipped Stages take plays (PLAN v6 4, M35); null when the
## Stages step has not shipped, and while inert (the v0.0 run is the inert run).
static func stage_set() -> StageSet:
	if SaveGame.unlock_all or RunState.session != null:
		return null
	var out: StageSet = null
	for id in SaveGame.shipped():
		var c := ChangeDB.get_change(id)
		if c != null and c.kind == &"stages" and c.take != null and c.take.preset is StageSet:
			out = c.take.preset as StageSet
	return out


## {tier, take}: the save's look (tier 0 when nothing shipped).
static func look() -> Dictionary:
	if RunState.session != null:
		var take := RunState.session.look
		return {"tier": 1 if take != "" else 0, "take": take}
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


## "look=1:punchy pool=7 enemies=chaser,shooter,tank missing=-" for the bot line and F1.
static func summary() -> String:
	var l := look()
	var missing := missing_basics().map(func(b: StringName) -> String: return String(b))
	return "look=%d:%s pool=%d enemies=%s missing=%s" % [l.tier, l.take if l.take != "" else "-", pool().size(),
			",".join(enemies().map(func(a: StringName) -> String: return String(a))),
			",".join(missing) if not missing.is_empty() else "-"]
