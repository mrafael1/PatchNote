class_name PathRunner
extends Node
## The live path in a game scene (PLAN v9 1.5, M45a): shared by every path. main.gd makes it
## only in a session with a path, a tryout, or on F2's demand, so Stage 1 never has one.
##
## It starts the path (RunState.session_path for S7's cue and F2, the Loadout's fire mode and
## start weapons, the growth piece when its basic is live, the crowd overlay in the AI layer
## with owner &"path"), swaps it on a `path` cue (a 1.5 s warning on the physics tick clock,
## then shots and pickups cleared, enemies kept, one glitch pulse), keeps the live weapon
## pool (the pool rule, 1.2) and runs the in-run picks: PickOffer + PickPanel, never
## RunState.apply, build_number, the save or the patch notes (0.4). A pick panel waits while
## a rule edit's warning or an event is playing (1.5's pause rule).
##
## Power stays in the session: nothing here is saved, and the next scene starts without it.
##
## Growth per path (M46): `levelups` (Auto: gems, LevelMeter, LevelWidget) or `cards`
## (Arsenal: the card meter fed by player kills, HandWidget), each built once its basic is
## live; Arsenal's `quick_draw` basic turns its quick-draw on. It also samples the play
## fingerprint (1.15, report-only).

signal started(path_id: StringName)

const Gems := preload("res://paths/auto/gems.gd")
const LevelMeter := preload("res://paths/auto/level_meter.gd")
const LevelWidget := preload("res://paths/auto/level_widget.gd")
const CardMeter := preload("res://paths/arsenal/card_meter.gd")
const HandWidget := preload("res://paths/arsenal/hand_widget.gd")
const SWAP_WARN_SECONDS := 1.5
const GLITCH := 0.6        ## one pulse: one flash, far under 3 a second (D12)
const FADE_SECONDS := 0.4  ## the pulse under reduce flashing
## The mascot's word after a pick (priority 1, muted with --mute-ai; D8, first to cut).
const PICK_LINES: Array[String] = ["happy: Ooh, that one.", "proud: Good pick."]

var game: Node            ## main.gd
var panel: PickPanel
var muted := false
## --loadout= (the bot, D13): a fixed loadout for the whole session, no growth: no gems are
## dropped and the meter never asks.
var frozen := false

var path_id: StringName = &""   ## the live path (&"" none)
var def: PathDef
var starts := 0                 ## paths started (the boot's and each swap)
var picks := 0
var pickups_taken := 0
## The live pool (1.2): the path's start weapons, then each weapon a `give` or a tagged `say`
## cue announced. Offers draw only from it (and the session's weapons).
var live_pool: Array[StringName] = []
var taste := Taste.new()        ## the session's, never saved (D7)
var said: Array[String] = []    ## every line it gave the mascot (tests, the bot)
var offers: Array[PickOffer] = []
var fp := Fingerprint.new()     ## the play fingerprint (1.15, report-only)

var _gems: Node
var _meter: RefCounted
var _widget: Control
var _overlay: PathOverlay
var _tick := 0
var _swap_target: StringName = &""
var _swap_tick := -1
var _want := 0
var _first: StringName = &""
var _opening := false
var _stopped := false
var _fade: CanvasLayer


func _ready() -> void:
	EventBus.basic_added.connect(_on_basic_added)
	EventBus.pickup_taken.connect(_on_pickup_taken)
	if panel != null:
		panel.picked.connect(_on_picked)


func _exit_tree() -> void:
	_feed_cards(false)
	if EventBus.basic_added.is_connected(_on_basic_added):
		EventBus.basic_added.disconnect(_on_basic_added)
	if EventBus.pickup_taken.is_connected(_on_pickup_taken):
		EventBus.pickup_taken.disconnect(_on_pickup_taken)


## The session's own path at boot (none: nothing happens until a `path` cue or F2).
func begin() -> void:
	var id := RunState.live_path()
	if id != &"":
		_apply(id)


func loadout() -> Loadout:
	var p: Node = game.get(&"player") if game != null else null
	return Component.find(p, Loadout) as Loadout if is_instance_valid(p) else null


## Auto's level (1 on any other growth, so `level N` cues never fire on Arsenal).
func level() -> int:
	return int(_meter.get(&"level")) if _meter != null and _levelups() else 1


func gems() -> int:
	return int(_meter.get(&"gems")) if _meter != null and _levelups() else 0


## Arsenal's cards dealt (0 on any other growth).
func cards() -> int:
	return int(_meter.get(&"cards")) if _meter != null and _cards_growth() else 0


## Kills to the next card (-1: none, or not a cards path).
func kills_to_next() -> int:
	if _meter == null or not _cards_growth():
		return -1
	var need := int(_meter.call(&"next_need"))
	return maxi(0, need - int(_meter.get(&"kills"))) if need >= 0 else -1


## The play fingerprint's 8 values (1.15).
func fingerprint() -> Dictionary:
	var lo := loadout()
	return fp.values(picks, lo.switches if lo != null else 0, pickups_taken)


func _levelups() -> bool:
	return def != null and def.growth == &"levelups"


func _cards_growth() -> bool:
	return def != null and def.growth == &"cards"


func meter() -> RefCounted:
	return _meter


func widget() -> Control:
	return _widget


func overlay() -> PathOverlay:
	return _overlay


## Picks asked and not made yet.
func pending_picks() -> int:
	return _want


func swap_pending() -> bool:
	return _swap_tick >= 0


# --- Swaps -------------------------------------------------------------------------------

## A `path` cue (S7): the warning (the target's warn_line at priority 3, as a rule edit's),
## then 1.5 s later the swap. False when the session is over.
func request_swap(target: StringName) -> bool:
	if _stopped or _over():
		return false
	var to := PathDB.get_def(target)
	_speak(to.warn() if to != null else null, 3)
	_swap_target = target
	_swap_tick = _tick + roundi(SWAP_WARN_SECONDS * Engine.physics_ticks_per_second)
	RunState.log_event(&"path_requested", {"to": String(target)})
	return true


## Swaps now (the cue's landing, F2): player shots and pickups go (enemies stay), the path
## starts, one glitch pulse. &"off" = no path: the legacy pistol again.
func swap_now(target: StringName) -> void:
	_swap_tick = -1
	for group: StringName in [&"player_projectile", &"pickup"]:
		for n in get_tree().get_nodes_in_group(group):
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				n.queue_free()
	RunState.session_path = &"off" if target == &"off" or target == &"" else target
	_apply(RunState.live_path())
	RunState.log_event(&"path_swapped", {"to": String(target)})
	_wipe()


func _apply(id: StringName) -> void:
	_clear_growth()
	RunState.expire_ai(&"path")   # no-op (no build) when no overlay is live
	_overlay = null
	path_id = id
	def = PathDB.get_def(id)
	var lo := loadout()
	if lo != null:
		lo.apply_path(def)
	if def != null:
		for w in def.start:
			if not w in live_pool:
				live_pool.append(w)
		_grow()
	starts += 1
	started.emit(id)


## The growth piece and the crowd, each once its basic is live.
func _grow() -> void:
	if def == null or _stopped:
		return
	if def.growth == &"levelups" and _meter == null and not frozen and Unlocks.has_basic(&"levelups"):
		_build_levels()
	if def.growth == &"cards" and _meter == null and not frozen and Unlocks.has_basic(&"cards"):
		_build_cards()
	var lo := loadout()
	if lo != null and def.quick_draw_mult > 1.0 and &"quick_draw" in def.basics \
			and Unlocks.has_basic(&"quick_draw"):
		lo.quick_draw_mult = def.quick_draw_mult
	# The crowd overlay only on its own path (D6, M46): outside a session every basic is on.
	if _overlay == null and &"crowd" in def.basics and Unlocks.has_basic(&"crowd"):
		_overlay = PathOverlay.make(def)
		if not RunState.add_ai(_overlay, &"path"):
			_overlay = null


func _build_levels() -> void:
	_gems = Gems.new()
	_gems.name = "Gems"
	add_child(_gems)
	_gems.gem_taken.connect(_on_gem_taken)
	_meter = LevelMeter.new()
	_meter.def = def
	_meter.tryout = RunState.session != null and RunState.session.tryout
	_meter.on_level = want_pick
	_meter.on_full = _on_meter_full
	_widget = LevelWidget.new()
	_widget.name = "LevelWidget"
	_widget.meter = _meter
	_widget.loadout = loadout()
	var hud: Node = game.get(&"hud") if game != null else null
	if hud != null and hud.has_method(&"set_path_widget"):
		hud.set_path_widget(_widget)
	else:
		add_child(_widget)


## Arsenal (M46): the card meter, fed by player kills, and the hand widget.
func _build_cards() -> void:
	_meter = CardMeter.new()
	_meter.def = def
	_meter.tryout = RunState.session != null and RunState.session.tryout
	_meter.on_card = want_pick
	_meter.on_full = _on_meter_full
	_feed_cards(true)
	_widget = HandWidget.new()
	_widget.name = "HandWidget"
	_widget.meter = _meter
	_widget.loadout = loadout()
	_widget.max_cards = def.max_picks
	var hud: Node = game.get(&"hud") if game != null else null
	if hud != null and hud.has_method(&"set_path_widget"):
		hud.set_path_widget(_widget)
	else:
		add_child(_widget)


## The card meter's kill feed (connected only while a card meter exists).
func _feed_cards(on: bool) -> void:
	var connected := EventBus.enemy_killed.is_connected(_on_enemy_killed)
	if on and not connected:
		EventBus.enemy_killed.connect(_on_enemy_killed)
	elif not on and connected:
		EventBus.enemy_killed.disconnect(_on_enemy_killed)


## The gems' filter: only the player's kills fill the card meter.
func _on_enemy_killed(_enemy: Node, info: RefCounted) -> void:
	if _meter != null and not frozen and _cards_growth() and (info as DamageInfo).faction == &"player":
		_meter.call(&"add", 1)


func _clear_growth() -> void:
	_feed_cards(false)
	if is_instance_valid(_gems):
		_gems.queue_free()
	_gems = null
	_meter = null
	if is_instance_valid(_widget):
		_widget.queue_free()
	_widget = null
	_want = 0


func _on_basic_added(id: StringName) -> void:
	if id in [&"levelups", &"crowd", &"cards", &"quick_draw"]:
		_grow()


func _on_gem_taken(value: int) -> void:
	if _meter != null and not frozen:
		_meter.call(&"add", value)


func _on_pickup_taken(_kind: StringName, _id: StringName) -> void:
	pickups_taken += 1


## The bot's --loadout= (D13): a fixed loadout from now on, no growth (no gems, no picks).
func freeze() -> void:
	frozen = true
	_want = 0
	_feed_cards(false)   # Arsenal: no kills fill the card meter either
	if is_instance_valid(_gems):
		_gems.queue_free()
	_gems = null


## F2's "+1 level": the gems the next level needs (Arsenal: the kills the next card needs).
func force_level() -> void:
	if _meter == null:
		return
	var need := int(_meter.call(&"next_need"))
	if need < 0:
		return
	var have := int(_meter.get(&"kills")) if _cards_growth() else gems()
	_meter.call(&"add", maxi(1, need - have))


# --- The pool rule (1.2) -----------------------------------------------------------------

## A `say [w]` cue fired: w may be offered from now on.
func announce(w: StringName) -> void:
	if w != &"" and not w in live_pool:
		live_pool.append(w)


## A `give` cue under a path: Auto offers it first at its next level-up (no slot is filled).
## False with no path live, and on Arsenal: the caller hands it over itself (M44's free
## slot: a free card, the weakest non-active card replaced when the hand is full; 1.3).
func give(w: StringName) -> bool:
	announce(w)
	if def == null or def.growth != &"levelups":
		return false
	_first = w
	return true


## What offers draw from: the live pool, within the session's weapons and the path's extras.
func offer_pool() -> Array[StringName]:
	var allowed: Array[StringName] = []
	if RunState.session != null:
		allowed.append_array(RunState.session.weapons)
	if def != null:
		allowed.append_array(def.offer_pool_extra)
	var out: Array[StringName] = []
	for w in live_pool:
		if RunState.session == null or w in allowed:
			out.append(w)
	return out


# --- Picks --------------------------------------------------------------------------------

## The meter levelled up: a pick is owed (opened on the first free tick).
func want_pick() -> void:
	if not frozen:
		_want += 1


func _on_meter_full() -> void:
	if def != null and def.full_line != "":
		_speak(Line.parse(def.full_line), SessionRunner.PRIORITY, true)


## 1.5's pause rule: never over a rule edit's warning, an event or a pending swap, never
## after the session ended. (Not RuleBook.busy(): a live timed edit would hold picks for
## its whole length.)
func can_open_now() -> bool:
	if _stopped or _over() or _swap_tick >= 0 or panel == null or panel.is_open():
		return false
	var book: RuleBook = game.get(&"rule_book") if game != null else null
	if book != null and book.warning_pending():
		return false
	var events: EventPlayer = game.get(&"event_player") if game != null else null
	if events != null and events.is_playing():
		return false
	return not RunState.is_paused_except(PickPanel.PAUSE)


func _physics_process(_delta: float) -> void:
	_tick += 1
	var p: Node = game.get(&"player") if game != null else null
	if not _stopped and def != null and is_instance_valid(p):
		fp.sample(p as Node2D)
	if _swap_tick >= 0 and _tick >= _swap_tick:
		swap_now(_swap_target)
	if _want > 0 and not _opening and can_open_now():
		_opening = true
		_open_offer.call_deferred()


## Deferred (never pause inside a physics callback); checks again, as the run can end in the
## frame the meter asked.
func _open_offer() -> void:
	_opening = false
	var lo := loadout()
	if _want <= 0 or lo == null or not can_open_now():
		return
	var first := _first
	if first == &"" and _cards_growth():
		first = most_fired(lo)   # Arsenal: the most-fired card's upgrade first (1.5, D7)
	var offer := PickOffer.draw(lo, def, offer_pool(), first, RunState.pick_rng, taste)
	_first = &""
	offers.append(offer)
	EventBus.pick_offered.emit(offer)
	fp.menu_open()
	panel.open(offer)


## The held aimed card with the most shots that can still rank up (ties: slot order), or
## &"" for none. Offered first only if it is in the live pool (PickOffer.draw).
static func most_fired(lo: Loadout) -> StringName:
	var best: Weapon = null
	for w in lo.slots:
		if w.rank >= mini(Loadout.MAX_RANK, w.def.max_rank()):
			continue
		if best == null or w.shots > best.shots:
			best = w
	return best.def.id if best != null else &""


func _on_picked(offer: PickOffer, index: int) -> void:
	fp.menu_close()
	# The key that picked card n must not also pick slot n (keys 1-3, M46).
	var p: Node = game.get(&"player") if game != null else null
	if is_instance_valid(p) and p.get(&"input") != null:
		(p.get(&"input") as PlayerInput).require_fresh_press()
	var card: Dictionary = offer.cards[index]
	_want = maxi(0, _want - 1)
	picks += 1
	var lo := loadout()
	if card.kind == &"new" and lo != null:
		lo.give(card.id, 1)
	elif card.kind == &"upgrade" and lo != null:
		lo.upgrade(card.id)
	elif card.kind == PickOffer.HP:
		_one_more_hp()
	for c in offer.cards:
		taste._nudge_raw(c.id, [], Taste.PICK if c == card else Taste.PASS)
	RunState.log_event(&"pick", {"offer": offer.ids().map(func(i: StringName) -> String: return String(i)),
			"pick": String(card.id)})
	EventBus.pick_made.emit(card.id)
	_speak(Line.parse(PICK_LINES[(picks - 1) % PICK_LINES.size()]), 1)


## The filler card: +1 max HP and 1 HP back, this session only.
func _one_more_hp() -> void:
	var p: Node = game.get(&"player") if game != null else null
	var h := Component.find(p, Health) as Health if is_instance_valid(p) else null
	if h == null or h.dead:
		return
	var before := h.hp()
	h.base_max_hp += 1.0
	h.hp_ratio = minf(1.0, (before + 1.0) / h.max_hp())


## The session ended: no more picks or gems (the panel closes with its pause reason). The
## crowd overlay stays until the next scene's RunState.reset() (expiring it now would bump
## the build and log under the debrief).
func stop() -> void:
	_stopped = true
	_want = 0
	_swap_tick = -1
	fp.menu_close()
	if panel != null:
		panel.dismiss()
	if is_instance_valid(_gems):
		_gems.queue_free()
	_gems = null
	if _meter != null:
		_meter.set(&"stopped", true)


func _over() -> bool:
	var genre: Node = game.get(&"genre") if game != null else null
	return genre == null or genre.call(&"is_over")


func _speak(line: Line, priority: int, queued := false) -> void:
	if line == null or muted:
		return
	said.append(line.text)
	var runner: SessionRunner = game.get(&"session_runner") if game != null else null
	if queued and runner != null:
		runner.say(line)
		return
	var reactions: Reactions = game.get(&"reactions") if game != null else null
	if reactions != null:
		reactions.note_spoken(line, priority)
	var mascot: Mascot = game.get(&"mascot") if game != null else null
	if mascot != null:
		mascot.say(line, priority)


## One glitch pulse, or a 0.4 s fade under reduce flashing (D12).
func _wipe() -> void:
	if not SaveGame.reduce_flashing():
		var transition: Transition = game.get(&"transition") if game != null else null
		if transition != null:
			transition.glitch(GLITCH)
		return
	if is_instance_valid(_fade):
		_fade.queue_free()
	_fade = CanvasLayer.new()
	_fade.layer = 79
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 0.6)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.add_child(rect)
	add_child(_fade)
	var tween := rect.create_tween()
	tween.tween_property(rect, ^"color:a", 0.0, FADE_SECONDS)
	tween.tween_callback(_fade.queue_free)


## F1's line: "path=auto level=2 picks=1 pickups=7"; Arsenal (M46):
## "path=arsenal cards=1 kills=20/36 picks=1 pickups=0".
func state_text() -> String:
	if _cards_growth():
		var need := int(_meter.call(&"next_need")) if _meter != null else -1
		return "path=%s cards=%d kills=%d/%s picks=%d pickups=%d" % [path_id, cards(),
				int(_meter.get(&"kills")) if _meter != null else 0, str(need) if need >= 0 else "-", picks,
				pickups_taken]
	return "path=%s level=%d picks=%d pickups=%d" % [path_id if path_id != &"" else &"-", level(), picks,
			pickups_taken]
