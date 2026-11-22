class_name DevSession
extends RefCounted
## One dev session (PLAN v5 4): what the AI proposes after a run, what ships, and the
## patch notes of the new version. Logic only: ui/dev_session.gd and ui/patch_notes.gd
## show it, the shell appends telemetry_record() to the playtest log.
##
## Shapes (4.2):
## - MOCKUP: an available change with takes is due (due_after_run <= runs): its 3 takes
##   are the cards. Picking one ships the change and sets the look.
## - CHANGES: up to Tuning.session_cards available changes, taste-weighted by tag, and
##   one agenda card (the least liked by tag) whenever at least
##   Tuning.agenda_min_available cards are shown.
## - AI_LAST: only one change is left: no card, the AI ships it itself (finish()).
## - NONE: nothing is left: no card, no bump ("I'm working on something bigger.").
## Every Tuning.ai_own_ship_every sessions (counted in the save), after the player's
## pick, the AI also ships one available non-mockup change (the agenda rule) with its
## own bump (4.4).
##
## Cards come from a generator seeded with the run's seed and the session number, so a
## same-seed chain from the same save gets the same cards. Nothing here knows a genre or
## a change by name.

const MOCKUP := &"mockup"
const CHANGES := &"changes"
const AI_LAST := &"ai_last"
const NONE := &"none"

const PLAYER := &"player"
const AI := &"ai"

const PENDING_LINE := "The last build is still on my desk."
const MOCKUP_LINE := "Before more features: the look. I built three takes. Pick the one we ship."
const CHANGES_LINE := "Here is what I can do for the next version. Pick one."
const AI_LAST_LINE := "Last one on my list. I shipped it."
## AI_LAST when more changes wait behind the one it shipped (their requires).
const AI_ONLY_LINE := "Only one change was ready, so I shipped it myself. More are coming."
const NONE_LINE := "I'm working on something bigger."
const AGENDA_LABEL := "AI's wish"
const AGENDA_LINE := "This is the one I want to build. You will not pick it. Pick it anyway."
const AI_OWN_LINE := "I also shipped something you didn't ask for: %s."

var shape: StringName = NONE
## {"id": String (change id, or "change:take"), "change": Change, "take": MockupTake or
## null, "agenda": bool, "taste_id": StringName, "tags": Array}
var cards: Array[Dictionary] = []
var mockup: Change            ## the mockup session's change
var number := 0               ## this session's number in the save (1 = the first)
var after_run := 0            ## the save's runs when it opened
var version_before: GameVersion
var opening := ""             ## the AI's opening line
## What shipped, in order: {"change": Change, "take": MockupTake or null, "by": PLAYER or AI}
var shipped: Array[Dictionary] = []
var pick_id := ""
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
	var avail := available()
	for c in avail:
		if c.is_mockup() and c.due_after_run <= s.after_run:
			s.shape = MOCKUP
			s.mockup = c
			for t in c.takes:
				s.cards.append({"id": "%s:%s" % [c.id, t.id], "change": c, "take": t, "agenda": false,
						"taste_id": StringName(SaveGame.LOOK_PREFIX + String(t.id)), "tags": []})
			break
	if s.shape != MOCKUP:
		var regular := _regular(avail)
		if regular.size() >= 2:
			s.shape = CHANGES
			s._deal(regular)
		elif regular.size() == 1:
			s.shape = AI_LAST
		else:
			s.shape = NONE
	s.opening = s._opening(context)
	return s


## Changes the save can ship now: not shipped, every requires shipped, and a genre (if
## any) at least Playable. In ChangeDB order (by id).
static func available() -> Array[Change]:
	var out: Array[Change] = []
	for c in ChangeDB.all:
		if SaveGame.has_shipped(c.id):
			continue
		var ready := true
		for req in c.requires:
			if not SaveGame.has_shipped(req):
				ready = false
				break
		if ready and (c.genre == &"" or _genre_playable(c.genre)):
			out.append(c)
	return out


static func _genre_playable(genre: StringName) -> bool:
	var entry := SaveGame.genre_entry(genre)
	var step := SaveGame.STEPS.find(String(entry.get("step", "")))
	return step >= SaveGame.STEPS.find("playable")


## Changes that are not mockups: a mockup is only ever shown as its takes.
static func _regular(changes: Array[Change]) -> Array[Change]:
	var out: Array[Change] = []
	for c in changes:
		if not c.is_mockup():
			out.append(c)
	return out


## The 3-changes deal: due changes first, then the agenda card (the least liked of the
## rest, so it really is what the player likes least), then taste-weighted picks. The
## agenda card is shown last, as in the run's offers.
func _deal(regular: Array[Change]) -> void:
	var pool := regular.duplicate()
	var shown := mini(Tuning.session_cards, pool.size())
	var agenda_count := 1 if shown >= Tuning.agenda_min_available else 0
	for c in regular:
		if cards.size() >= shown - agenda_count:
			break
		if c.due_after_run > 0 and c.due_after_run <= after_run:
			_add_card(c, false)
			pool.erase(c)
	var wish: Change = null
	if agenda_count > 0 and not pool.is_empty():
		wish = least_liked(pool, _taste, _rng)
		pool.erase(wish)
	while cards.size() < shown - agenda_count and not pool.is_empty():
		var c := _weighted_pick(pool)
		_add_card(c, false)
		pool.erase(c)
	if wish != null:
		_add_card(wish, true)


func _add_card(c: Change, is_agenda: bool) -> void:
	cards.append({"id": String(c.id), "change": c, "take": null, "agenda": is_agenda,
			"taste_id": &"", "tags": c.tags.duplicate()})


func _weighted_pick(pool: Array[Change]) -> Change:
	var total := 0.0
	for c in pool:
		total += _weight(c)
	var roll := _rng.randf() * total
	for c in pool:
		roll -= _weight(c)
		if roll < 0.0:
			return c
	return pool[pool.size() - 1]


func _weight(c: Change) -> float:
	return maxf(c.weight, 0.0) * _taste.weight_mult_raw(&"", c.tags)


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


## The player has a choice to make (MOCKUP or CHANGES, not done yet).
func can_pick() -> bool:
	return not done and (shape == MOCKUP or shape == CHANGES) and not cards.is_empty()


# --- Shipping ----------------------------------------------------------------------

## The player picks card index: ships it (and, on the cadence, the AI's own change),
## feeds taste, logs the session and writes the save. False if there is no such pick.
func pick(index: int) -> bool:
	if not can_pick() or index < 0 or index >= cards.size():
		return false
	var card := cards[index]
	pick_id = card.id
	_taste.on_session_pick(cards, card)
	_ship(card.change, card.take, PLAYER)
	if Tuning.ai_own_ship_every > 0 and number % Tuning.ai_own_ship_every == 0:
		var left := _regular(available())
		if not left.is_empty():
			_ship(least_liked(left, _taste, _rng), null, AI)
	_finish()
	return true


## A session with no choice: AI_LAST ships the last change as the AI's own, NONE ships
## nothing and does not bump. Both are logged. False if the session needs a pick.
func finish() -> bool:
	if done or can_pick():
		return false
	if shape == AI_LAST:
		var left := _regular(available())
		if not left.is_empty():
			_ship(left[0], null, AI)
	_finish()
	return true


func _ship(c: Change, take: MockupTake, by: StringName) -> void:
	if not SaveGame.ship(c.id, c.bump):
		return
	if take != null:
		var preset := take.preset as LookPreset
		SaveGame.set_look(preset.tier if preset else 1, take.id)
	shipped.append({"change": c, "take": take, "by": by})


func _finish() -> void:
	done = true
	SaveGame.finish_session(log_entry(), _taste.to_save())


func version_after() -> GameVersion:
	return SaveGame.version() if done else version_before


func ai_ship_id() -> String:
	for s in shipped:
		if s.by == AI:
			return String((s.change as Change).id)
	return ""


## The save's session log line (PLAN v5 1.5). Unpicked takes stay in "cards".
func log_entry() -> Dictionary:
	return {
		"after_run": after_run,
		"version": version_after().short(),
		"shape": String(shape),
		"cards": cards.map(func(c: Dictionary) -> String: return c.id),
		"pick": pick_id,
		"agenda": String(agenda_card().get("id", "")),
		"ai_ship": ai_ship_id(),
	}


## The "session" telemetry line (PLAN v5 4.5).
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
		"cards": e.cards,
		"pick": e.pick,
		"agenda": e.agenda,
		"ai_ship": e.ai_ship,
	}


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
	match shape:
		MOCKUP:
			parts.append(MOCKUP_LINE)
		CHANGES:
			parts.append(CHANGES_LINE)
		AI_LAST:
			parts.append(AI_LAST_LINE if _is_last(_regular(available())[0]) else AI_ONLY_LINE)
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


## The patch notes (PLAN v5 4.1 step 3), one entry per line, for ui/patch_notes.gd.
## "Version 0.1.0" first; then a bullet per shipped change, what it unlocked, and the
## AI's own ship. Empty when nothing shipped.
func notes_lines() -> Array[String]:
	var out: Array[String] = []
	if shipped.is_empty():
		return out
	out.append("Version %s" % version_after().short())
	for s in shipped:
		var c: Change = s.change
		var take: MockupTake = s.take
		var title := "%s (%s)" % [c.title, take.title] if take else c.title
		out.append("• %s: %s" % [title, take.line if take else c.pitch])
		for line in unlock_lines(c, take):
			if line != c.title:   # "New enemy: Tank" is already the bullet's title
				out.append("    " + line)
	for s in shipped:
		if s.by == AI:
			var c: Change = s.change
			if shape == AI_LAST:
				out.append(AI_LAST_LINE if _is_last(c) else AI_ONLY_LINE)
			else:
				out.append(AI_OWN_LINE % c.short_name())
	return out


## Nothing but c is left to ship (shipped or not, every other change is out).
static func _is_last(c: Change) -> bool:
	for other in ChangeDB.all:
		if other != c and not SaveGame.has_shipped(other.id):
			return false
	return true


## "New patch in the pool: Automate attacking", "New enemy: Tank", "New look: Punchy".
static func unlock_lines(c: Change, take: MockupTake = null) -> Array[String]:
	var out: Array[String] = []
	if take != null:
		out.append("New look: %s" % take.title)
	for u in c.unlocks:
		var m := MutationDB.get_mutation(u)
		if m:
			out.append("New patch in the pool: %s" % m.title)
		else:
			out.append("New enemy: %s" % String(u).capitalize())
	return out
