class_name DevSession
extends RefCounted
## One dev session (PLAN v6 1.2): what the AI asks after a run, what ships, and the
## patch notes of the new version. Logic only: ui/dev_session.gd and ui/patch_notes.gd
## show it, the shell appends telemetry_record() to the playtest log.
##
## Kinds:
## - BASIC: one of the game's basics is still missing (v5 4.8): no card, the AI ships
##   the next one itself (finish()) and the flow goes straight to the patch notes.
## - FORK: one question (a Fork) with its 2-3 options as cards. Picking one ships it
##   and shelves the others. A non-mockup fork marks its least-liked option as the
##   AI's wish. Every Tuning.ai_own_ship_every sessions (counted in the save), after
##   the pick, the AI also answers a second ready non-mockup fork with its wish, if at
##   least Tuning.ai_fork_min_ready of them are left (it never takes the last one).
##   Once Tuning.rework_after_forks forks are answered and the shelf is not empty, it
##   also offers Rework (can_rework()): swapping a past answer costs the session.
## - IMPLEMENT: no fork is ready but a new in-run patch is left (a change in no fork,
##   owner feedback after M34: "dev session should never be about new patch in future
##   run"; questions are only for big features that change a run from its start). The
##   AI builds one itself, drawn by taste (implement()), and says so. Once
##   Tuning.rework_after_forks forks are answered and the shelf is not empty, the screen
##   also offers Rework, on top of the AI's patch; otherwise the flow goes straight to
##   the patch notes.
## - REWORK: nothing new is left but the shelf is not empty (PLAN v6 1.2-1.3): the
##   rework list and "Keep it as it is" (no bump).
## - NONE: nothing is ready and the shelf is empty: no card, no bump.
##
## The fork and its order come from a generator seeded with the run's seed and the
## session number, so a same-seed chain from the same save asks the same questions.
## Nothing here knows a genre, a fork or a change by name.

const BASIC := &"basic"
const FORK := &"fork"
const IMPLEMENT := &"implement"
const REWORK := &"rework"
const NONE := &"none"

const PLAYER := &"player"
const AI := &"ai"

const PENDING_LINE := "The last build is still on my desk."
const NONE_LINE := "I'm working on something bigger."
const BASIC_LINE := "That build was missing something basic. Fixed it."
const IMPLEMENT_LINE := "No question this time. I built something for your runs: \"%s\"."
const IMPLEMENT_NOTE := "Built by the AI. It shows up among your patch offers."
const AGENDA_LABEL := "AI's wish"
const AGENDA_LINE := "This is the one I want to build. You will not pick it. Pick it anyway."
const SHELF_LINE := "On the shelf: %s."
const AI_FORK_LINE := "I answered \"%s\" myself: %s. Rework it if you disagree."
const REWORK_LINE := "Nothing new on my list. Want to change something?"
const REWORK_TITLE := "Rework…"
const REWORK_PITCH := "Swap one of your past answers for one on the shelf. No new feature this time."
const KEEP_LABEL := "Keep it as it is"
const REWORKED_LINE := "• Reworked \"%s\": %s → %s"
const BACK_ON_SHELF_LINE := "Back on the shelf: %s."

var shape: StringName = NONE
var fork: Fork                ## the question asked (FORK)
var new_patch: Change         ## what the AI builds (IMPLEMENT)
## {"id": String (change id), "change": Change, "take": MockupTake or null,
## "agenda": bool, "taste_id": StringName, "tags": Array}
var cards: Array[Dictionary] = []
var number := 0               ## this session's number in the save (1 = the first)
var after_run := 0            ## the save's runs when it opened
var version_before: GameVersion
var opening := ""             ## the AI's opening line
## What shipped, in order: {"change": Change, "take": MockupTake or null, "by": PLAYER
## or AI, "fork": Fork or null}
var shipped: Array[Dictionary] = []
var pick_id := ""
## {"fork": Fork, "from": Change, "to": Change} once a rework shipped, else empty.
var reworked := {}
var kept := false             ## REWORK: "Keep it as it is"
var done := false

var _rng := RandomNumberGenerator.new()
var _taste: Taste


# --- Planning ----------------------------------------------------------------------

## The session the save calls for now. context (all optional) comes from the run that
## just ended (context_from_record) and voices the opening line; {"pending": true}
## means the game closed before the last session.
static func plan(run_seed: int, context := {}) -> DevSession:
	var s := DevSession.new()
	var state := SaveGame.state()
	s.number = SaveGame.session_count() + 1
	s.after_run = int(state.runs)
	s.version_before = SaveGame.version()
	s._taste = Taste.from_save(state.taste)
	s._rng.seed = hash([run_seed, s.number, s.after_run])
	if not basics_left().is_empty():
		s.shape = BASIC
	else:
		var ready := ready_forks()
		if not ready.is_empty():
			s.shape = FORK
			s.fork = s._choose_fork(ready)
			s._deal()
		elif not new_patches_left().is_empty():
			s.shape = IMPLEMENT
			s.new_patch = s._choose_patch(new_patches_left())
		elif not rework_rows().is_empty():
			s.shape = REWORK
	s.opening = s._opening(context)
	return s


## The basics still to ship, in id order (v5 4.8): every requires shipped first.
static func basics_left() -> Array[Change]:
	var out: Array[Change] = []
	for c in ChangeDB.all:
		if c.is_basic() and not SaveGame.has_shipped(c.id) \
				and c.requires.all(func(r: StringName) -> bool: return SaveGame.has_shipped(r)):
			out.append(c)
	return out


## Forks the save can ask now: not answered, every required fork answered, the runs
## and the genre's play past their thresholds, the genre at least Playable. While a
## basic is missing, none. In ChangeDB order (by id).
static func ready_forks() -> Array[Fork]:
	var out: Array[Fork] = []
	if ChangeDB.all.any(func(c: Change) -> bool: return c.is_basic() and not SaveGame.has_shipped(c.id)):
		return out
	var runs := int(SaveGame.state().runs)
	for f in ChangeDB.forks:
		if f.is_answered() or f.changes().size() < 2:
			continue
		if not f.requires_forks.all(func(r: StringName) -> bool:
				var req := ChangeDB.get_fork(r)
				return req != null and req.is_answered()):
			continue
		if f.due_after_run > runs:
			continue
		if f.genre != &"":
			if not _genre_playable(f.genre) or _genre_runs(f.genre) < f.play_runs:
				continue
		elif f.play_runs > runs:
			continue
		out.append(f)
	return out


## The in-run patches the AI still has to build (IMPLEMENT): changes in no fork that
## are not basics, not shipped, with every requires shipped. In id order.
static func new_patches_left() -> Array[Change]:
	var out: Array[Change] = []
	for c in ChangeDB.all:
		if c.is_basic() or c.fork != &"" or SaveGame.has_shipped(c.id):
			continue
		if c.requires.all(func(r: StringName) -> bool: return SaveGame.has_shipped(r)):
			out.append(c)
	return out


## One of them, drawn by taste over its tags (what the player picks in runs leans it).
func _choose_patch(pool: Array[Change]) -> Change:
	var weights: Array[float] = []
	var total := 0.0
	for c in pool:
		var w := _taste.weight_mult_raw(&"", c.tags)
		weights.append(w)
		total += w
	var roll := _rng.randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll < 0.0:
			return pool[i]
	return pool[pool.size() - 1]


static func _genre_playable(genre: StringName) -> bool:
	var entry := SaveGame.genre_entry(genre)
	var step := SaveGame.STEPS.find(String(entry.get("step", "")))
	return step >= SaveGame.STEPS.find("playable")


static func _genre_runs(genre: StringName) -> int:
	return int(SaveGame.genre_entry(genre).get("runs", 0))


## A fork that is due comes first (the lowest due_after_run, then by id); otherwise one
## drawn by weight and taste over the fork's tags.
func _choose_fork(ready: Array[Fork]) -> Fork:
	var due: Fork = null
	for f in ready:
		if f.due_after_run > 0 and (due == null or f.due_after_run < due.due_after_run):
			due = f
	if due != null:
		return due
	var total := 0.0
	for f in ready:
		total += _fork_weight(f)
	var roll := _rng.randf() * total
	for f in ready:
		roll -= _fork_weight(f)
		if roll < 0.0:
			return f
	return ready[ready.size() - 1]


func _fork_weight(f: Fork) -> float:
	return maxf(f.weight, 0.0) * _taste.weight_mult_raw(&"", f.tags)


## The fork's options as cards, in its order; on a non-mockup fork the least-liked one
## is the AI's wish and is shown last (ROADMAP 1.8 rule 4).
func _deal() -> void:
	var options := fork.changes()
	var wish: Change = null
	if not fork.mockup and options.size() >= Tuning.agenda_min_available:
		wish = least_liked(options, _taste, _rng)
	for c in options:
		if c != wish:
			_add_card(c, false)
	if wish != null:
		_add_card(wish, true)


func _add_card(c: Change, is_agenda: bool) -> void:
	var take := c.take
	cards.append({"id": String(c.id), "change": c, "take": take, "agenda": is_agenda,
			"taste_id": StringName(SaveGame.LOOK_PREFIX + String(take.id)) if take else &"",
			"tags": [] if take else c.tags.duplicate()})


## The change the player likes least by tag (the agenda rule); ties at random.
static func least_liked(pool: Array[Change], taste: Taste, rng: RandomNumberGenerator) -> Change:
	var lowest: Array[Change] = []
	var low := INF
	for c in pool:
		var sc := taste.score_raw(&"", c.tags)
		if sc < low - 0.001:
			low = sc
			lowest = [c]
		elif absf(sc - low) <= 0.001:
			lowest.append(c)
	return lowest[rng.randi_range(0, lowest.size() - 1)]


func agenda_card() -> Dictionary:
	for c in cards:
		if c.agenda:
			return c
	return {}


## The player has a choice to make (a FORK session, not done yet).
func can_pick() -> bool:
	return not done and shape == FORK and not cards.is_empty()


## What a rework can swap (PLAN v6 1.3): {"fork": Fork, "from": Change (the answer),
## "to": Array[Change] (its shelf)} for every answered fork with a shelf, in fork order.
static func rework_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in ChangeDB.forks:
		var shelf := f.shelf()
		if f.is_answered() and not shelf.is_empty():
			out.append({"fork": f, "from": f.answer(), "to": shelf})
	return out


## The Rework card (FORK) or list (REWORK) is on offer now.
func can_rework() -> bool:
	if done or rework_rows().is_empty():
		return false
	return shape == REWORK or ((shape == FORK or shape == IMPLEMENT) \
			and answers().size() >= Tuning.rework_after_forks)


## Swaps fork fork_id's answer for its shelved option to_id (PLAN v6 1.3): the old
## answer goes back to the shelf, the new one ships with one patch step (never a minor
## one), taste counts both, and the session is logged. No new fork is answered and the
## AI answers none. False if that swap is not on offer.
func rework(fork_id: StringName, to_id: StringName) -> bool:
	if not can_rework():
		return false
	var f := ChangeDB.get_fork(fork_id)
	var to := ChangeDB.get_change(to_id)
	if f == null or to == null or not to in f.shelf():
		return false
	var from := f.answer()
	implement()   # an IMPLEMENT session's patch ships whatever the player reworks
	SaveGame.unship(from.id)
	SaveGame.ship(to.id, GameVersion.PATCH)
	if to.take != null and to.take.preset is LookPreset:
		SaveGame.set_look((to.take.preset as LookPreset).tier, to.take.id)
	_taste.on_rework(_taste_side(from), _taste_side(to))
	reworked = {"fork": f, "from": from, "to": to}
	shipped.append({"change": to, "take": to.take, "by": PLAYER, "fork": f})
	_finish()
	return true


## REWORK: "Keep it as it is". Logged, no bump.
func keep() -> bool:
	if done or shape != REWORK:
		return false
	kept = true
	_finish()
	return true


## The taste side of a change, as a card has it.
static func _taste_side(c: Change) -> Dictionary:
	return {"taste_id": StringName(SaveGame.LOOK_PREFIX + String(c.take.id)) if c.take else &"",
			"tags": [] if c.take else c.tags.duplicate()}


# --- Shipping ----------------------------------------------------------------------

## The player picks card index: ships it (and, on the cadence, the AI's own answer to
## another fork), feeds taste, logs the session and writes the save. False if there is
## no such pick.
func pick(index: int) -> bool:
	if not can_pick() or index < 0 or index >= cards.size():
		return false
	var card := cards[index]
	pick_id = card.id
	_taste.on_session_pick(cards, card)
	_ship(card.change, fork, PLAYER)
	if Tuning.ai_own_ship_every > 0 and number % Tuning.ai_own_ship_every == 0:
		var other := ready_forks().filter(func(f: Fork) -> bool: return not f.mockup)
		if other.size() >= Tuning.ai_fork_min_ready:   # never the player's last question
			var f: Fork = other[_rng.randi_range(0, other.size() - 1)]
			_ship(least_liked(f.changes(), _taste, _rng), f, AI)
	_finish()
	return true


## IMPLEMENT: the AI ships its new patch (once). The session stays open for Rework
## until finish() or rework().
func implement() -> void:
	if shape != IMPLEMENT or done or new_patch == null or SaveGame.has_shipped(new_patch.id):
		return
	_ship(new_patch, null, AI)


## A session with no choice: BASIC ships the next basic as the AI's own; IMPLEMENT its
## new patch; NONE ships nothing and does not bump; REWORK keeps everything (keep()).
## All are logged. False if the session needs a pick.
func finish() -> bool:
	if done or can_pick():
		return false
	if shape == REWORK:
		return keep()
	implement()
	if shape == BASIC:
		var basics := basics_left()
		if not basics.is_empty():
			_ship(basics[0], null, AI)
	_finish()
	return true


func _ship(c: Change, f: Fork, by: StringName) -> void:
	if not SaveGame.ship(c.id, f.bump if f else c.bump):
		return
	if c.take != null and c.take.preset is LookPreset:
		SaveGame.set_look((c.take.preset as LookPreset).tier, c.take.id)
	shipped.append({"change": c, "take": c.take, "by": by, "fork": f})


func _finish() -> void:
	done = true
	SaveGame.finish_session(log_entry(), _taste.to_save())


func version_after() -> GameVersion:
	return SaveGame.version() if done else version_before


## The id of what the AI shipped on its own ("" when nothing).
func ai_ship_id() -> String:
	for s in shipped:
		if s.by == AI:
			return String((s.change as Change).id)
	return ""


## "fork_enemy:enemy_bomber" for the AI's own fork answer, "" when none.
func ai_fork() -> String:
	for s in shipped:
		if s.by == AI and s.fork != null:
			return "%s:%s" % [(s.fork as Fork).id, (s.change as Change).id]
	return ""


## The options of this session's fork that did not ship (after the pick).
func shelved_ids() -> Array[String]:
	var out: Array[String] = []
	if fork == null or pick_id == "":
		return out
	for c in cards:
		if c.id != pick_id:
			out.append(String(c.id))
	return out


## The save's session log line (PLAN v6 1.4).
func log_entry() -> Dictionary:
	return {
		"after_run": after_run,
		"version": version_after().short(),
		"shape": String(shape),
		"fork": String(fork.id) if fork else "",
		"cards": cards.map(func(c: Dictionary) -> String: return c.id),
		"pick": pick_id,
		"shelved": shelved_ids(),
		"agenda": String(agenda_card().get("id", "")),
		"ai_ship": ai_ship_id(),
		"ai_fork": ai_fork(),
		"rework": rework_id(),
		"kept": kept,
	}


## "fork_enemy:enemy_tank->enemy_bomber" for this session's rework, "" when none.
func rework_id() -> String:
	if reworked.is_empty():
		return ""
	return "%s:%s->%s" % [(reworked.fork as Fork).id, (reworked.from as Change).id, (reworked.to as Change).id]


## The "session" telemetry line (PLAN v6 1.4, schema 3).
func telemetry_record(run_index := 0) -> Dictionary:
	var e := log_entry()
	return {
		"type": "session",
		"schema": Telemetry.SCHEMA,
		"session_id": Telemetry.session(),
		"run_index": run_index,
		"number": number,
		"version_before": version_before.label(),
		"version_after": version_after().label(),
		"shape": e.shape,
		"fork": e.fork,
		"cards": e.cards,
		"pick": e.pick,
		"shelved": e.shelved,
		"agenda": e.agenda,
		"ai_ship": e.ai_ship,
		"ai_fork": e.ai_fork,
		"rework": {"fork": String((reworked.fork as Fork).id), "from": String((reworked.from as Change).id),
				"to": String((reworked.to as Change).id)} if not reworked.is_empty() else null,
		"kept": kept,
	}


## {fork id: answer id} of every answered fork, for run records (PLAN v6 1.4).
static func answers() -> Dictionary:
	var out := {}
	for f in ChangeDB.forks:
		var a := f.answer()
		if a != null:
			out[String(f.id)] = String(a.id)
	return out


# --- Words ---------------------------------------------------------------------------

## What the opening line reads from the run that just ended: its outcome, a patch the
## player picked, and the kind of hit that hurt most.
static func context_from_record(record: Dictionary) -> Dictionary:
	var picks: Array[String] = []
	for p: Dictionary in record.get("prompts", []):
		if String(p.get("pick", "")) != "":
			picks.append(String(p.pick))
	var kinds := {}
	for genre_key: String in record.get("genre_hits_by_kind", {}):
		var by_kind: Dictionary = record.genre_hits_by_kind[genre_key]
		for k: String in by_kind:
			var kind := k.trim_suffix("_blocked")
			kinds[kind] = int(kinds.get(kind, 0)) + int(by_kind[k])
	var worst := ""
	var most := 0
	var keys := kinds.keys()
	keys.sort()
	for k: String in keys:
		if int(kinds[k]) > most:
			most = int(kinds[k])
			worst = k
	return {"outcome": String(record.get("outcome", "")), "picks": picks, "worst_hit": worst}


func _opening(context: Dictionary) -> String:
	var parts: Array[String] = []
	if context.get("pending", false):
		parts.append(PENDING_LINE)
	else:
		match String(context.get("outcome", "")):
			"win":
				parts.append("The build survived its playtest.")
			"lose":
				parts.append("The build crashed in playtest. Noted.")
		var picks: Array = context.get("picks", [])
		if not picks.is_empty():
			var m := MutationDB.get_mutation(StringName(picks[picks.size() - 1]))
			if m:
				parts.append("You went with \"%s\"." % m.title)
		var worst := String(context.get("worst_hit", ""))
		if worst != "":
			parts.append("%s hits hurt you the most." % worst.capitalize())
	match shape:   # a fork's question is the screen's title (PLAN v6 2)
		BASIC:
			parts.append(BASIC_LINE)
		IMPLEMENT:
			parts.append(IMPLEMENT_LINE % new_patch.short_name())
		REWORK:
			parts.append(REWORK_LINE)
		NONE:
			parts.append(NONE_LINE)
	return " ".join(parts)


## A card's title and line, as the dev-session screen shows them.
static func card_title(card: Dictionary) -> String:
	var take: MockupTake = card.take
	return take.title if take else (card.change as Change).title


static func card_line(card: Dictionary) -> String:
	if card.agenda:
		return AGENDA_LINE
	var take: MockupTake = card.take
	return take.line if take else (card.change as Change).pitch


## The patch notes (PLAN v6 2), one entry per line, for ui/patch_notes.gd. "Version
## 0.1.0" first; then a bullet per shipped change and what it unlocked, the shelf of
## the player's fork, and the AI's own answer. Empty when nothing shipped.
func notes_lines() -> Array[String]:
	var out: Array[String] = []
	if shipped.is_empty():
		return out
	out.append("Version %s" % version_after().short())
	for s in shipped:
		if s.by == AI and s.fork == null and shape == IMPLEMENT:
			var c: Change = s.change
			out.append("• %s: %s" % [c.title, c.pitch])
			for line in unlock_lines(c):
				out.append("    " + line)
			out.append("    " + IMPLEMENT_NOTE)
	if not reworked.is_empty():
		var from: Change = reworked.from
		var to: Change = reworked.to
		out.append(REWORKED_LINE % [(reworked.fork as Fork).question, from.short_name(), to.short_name()])
		for line in removal_lines(from) + unlock_lines(to):
			out.append("    " + line)
		out.append(BACK_ON_SHELF_LINE % from.short_name())
		return out
	for s in shipped:
		if s.by == AI and s.fork == null and shape == IMPLEMENT:
			continue   # listed above
		var c: Change = s.change
		var take: MockupTake = s.take
		out.append("• %s: %s" % [c.title, take.line if take else c.pitch])
		for line in unlock_lines(c):
			if line != c.title:   # "New enemy: Tank" is already the bullet's title
				out.append("    " + line)
	var shelf := shelved_ids().map(func(id: String) -> String:
		return (ChangeDB.get_change(StringName(id)) as Change).short_name())
	if not shelf.is_empty():
		out.append(SHELF_LINE % ", ".join(shelf))
	for s in shipped:
		if s.by == AI and s.fork != null:
			out.append(AI_FORK_LINE % [(s.fork as Fork).question, (s.change as Change).short_name()])
	return out


## What a reworked-away change takes with it: "Out of the pool: Automate attacking",
## "No more Tanks". A look needs no line: the new look's line says it.
static func removal_lines(c: Change) -> Array[String]:
	var out: Array[String] = []
	for u in c.unlocks:
		var m := MutationDB.get_mutation(u)
		if m:
			out.append("Out of the pool: %s" % m.title)
		elif not u in Unlocks.BASICS:
			out.append("No more %ss" % String(u).capitalize())
	return out


## "New patch in the pool: Automate attacking", "New enemy: Tank", "New look: Punchy".
static func unlock_lines(c: Change) -> Array[String]:
	var out: Array[String] = []
	if c.take != null and c.kind == &"look":
		out.append("New look: %s" % c.take.title)
	for u in c.unlocks:
		var m := MutationDB.get_mutation(u)
		if m:
			out.append("New patch in the pool: %s" % m.title)
		elif not u in Unlocks.BASICS:
			out.append("New enemy: %s" % String(u).capitalize())
	return out
