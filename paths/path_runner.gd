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
##
## M47: Survival (`pickups`: Drops, crates, the ammo widget; `kill_heal`), per-cue swap
## warnings, picks counted per path since the last swap (`picked n` cues), a second sweep
## on the tick after a swap (deferred spawns from the swap tick) and leftovers(), checked
## then and logged as `path_leftovers`; S7's per-taste fingerprints.

signal started(path_id: StringName)

const Gems := preload("res://paths/auto/gems.gd")
const LevelMeter := preload("res://paths/auto/level_meter.gd")
const LevelWidget := preload("res://paths/auto/level_widget.gd")
const CardMeter := preload("res://paths/arsenal/card_meter.gd")
const HandWidget := preload("res://paths/arsenal/hand_widget.gd")
const Drops := preload("res://paths/survival/drops.gd")
const AmmoWidget := preload("res://paths/survival/ammo_widget.gd")
const SWAP_WARN_SECONDS := 1.5
const GLITCH := 0.6        ## one pulse: one flash, far under 3 a second (D12)
const FADE_SECONDS := 0.4  ## the pulse under reduce flashing
## The mascot's word after a pick (priority 1, muted with --mute-ai; D8, first to cut).
const PICK_LINES: Array[String] = ["happy: Ooh, that one.", "proud: Good pick."]
## M47 (1.12, D15): S7 captures a still of each taste this long after it lands (windowed
## only), for fork_path's cards.
const STILL_AFTER := 30.0
const STILL_SIZE := Vector2i(480, 270)

## M47: path id (String) -> ImageTexture of the player's taste (process memory only, never
## saved; cleared when a tryout starts and when its scene goes).
static var taste_stills := {}

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
## M47: picks made since the live path started (the `picked n` cues read it).
var picks_on_path := 0
var pickup_kinds := {}          ## M47: kind -> pickups taken (telemetry)
## M47 (S7): path id -> the fingerprint of that taste (taken at the swap away from it).
var taste_fps := {}
## M47: the leftovers found on the tick after each swap ([] = clean), in order.
var leftover_checks: Array = []
var wipes := 0                  ## M47 review: one per swap (a glitch pulse, or the fade)

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
var _drops: Node
var _sweep_tick := -1      ## the physics frame after a swap: the second sweep
var _check_tick := -1      ## the frame after that: the leftovers check
## M47 review: what the swap's two sweeps removed (weak refs). The check a frame later
## reports any of them still alive, so it can fail (a sweep that frees nothing shows).
var _swept: Array[WeakRef] = []
## Tests turn the second sweep's freeing off to see the check report the swap-tick spawns.
var late_sweep := true
var _late_swept := 0
var _fp_base := [0, 0, 0]   ## picks, switches, pickups when the taste started
var _still_tick := -1


func _ready() -> void:
	EventBus.basic_added.connect(_on_basic_added)
	EventBus.pickup_taken.connect(_on_pickup_taken)
	if panel != null:
		panel.picked.connect(_on_picked)


func _exit_tree() -> void:
	if _tryout():
		taste_stills.clear()
	_feed_cards(false)
	if EventBus.basic_added.is_connected(_on_basic_added):
		EventBus.basic_added.disconnect(_on_basic_added)
	if EventBus.pickup_taken.is_connected(_on_pickup_taken):
		EventBus.pickup_taken.disconnect(_on_pickup_taken)


## The session's own path at boot (none: nothing happens until a `path` cue or F2).
func begin() -> void:
	if _tryout():
		taste_stills.clear()
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
	return fp.values(picks - int(_fp_base[0]), (lo.switches if lo != null else 0) - int(_fp_base[1]),
			pickups_taken - int(_fp_base[2]))


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
func request_swap(target: StringName, warn: Line = null) -> bool:
	if _stopped or _over():
		return false
	var to := PathDB.get_def(target)
	# M47 (D12): the cue's own line, else the path's fallback (keys expanded either way).
	var line := warn if warn != null else (to.warn() if to != null else null)
	_speak(SessionRunner.with_keys(line) if line != null else null, 3)
	_swap_target = target
	_swap_tick = _tick + roundi(SWAP_WARN_SECONDS * Engine.physics_ticks_per_second)
	RunState.log_event(&"path_requested", {"to": String(target)})
	return true


## Swaps now (the cue's landing, F2): player shots and pickups go (enemies stay), the path
## starts, one glitch pulse. &"off" = no path: the legacy pistol again.
func swap_now(target: StringName) -> void:
	_swap_tick = -1
	_swept.clear()
	_sweep()
	# M47: what a deferred spawn adds on this frame goes on the next physics frame (counted
	# in frames, so a swap from F2 or a test before this node's own tick waits as well).
	_sweep_tick = Engine.get_physics_frames() + 1
	_check_tick = -1
	if RunState.session != null and RunState.session.tryout and path_id != &"":
		taste_fps[String(path_id)] = fingerprint()
	RunState.session_path = &"off" if target == &"off" or target == &"" else target
	_apply(RunState.live_path())
	RunState.log_event(&"path_swapped", {"to": String(target)})
	_wipe()


func _tryout() -> bool:
	return RunState.session != null and RunState.session.tryout


## The taste's still (windowed only: a headless viewport has no image). Tests call it.
func capture_still() -> bool:
	if path_id == &"" or DisplayServer.get_name() == "headless" or not is_inside_tree():
		return false
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return false
	img.resize(STILL_SIZE.x, STILL_SIZE.y)
	taste_stills[String(path_id)] = ImageTexture.create_from_image(img)
	return true


## Player shots and pickups go (enemies stay), except `keep` (the new path's own spawns:
## Survival's first crates). Each one goes on _swept for the check; `free` false only
## records (the test hook late_sweep).
func _sweep(keep: Array = [], free := true) -> void:
	for group: StringName in [&"player_projectile", &"pickup"]:
		for n in get_tree().get_nodes_in_group(group):
			if is_instance_valid(n) and not n.is_queued_for_deletion() and not keep.has(n):
				_swept.append(weakref(n))
				if free:
					n.queue_free()


## What another path left behind after a swap (M47, "no leftovers"): shots, pickups, a
## growth node or widget of another path, the crowd overlay off its path, a kill feed on
## the wrong path, weapons other than the path's start. [] = clean.
func leftovers() -> Array[String]:
	var out: Array[String] = []
	# A shot or pickup the swap's sweeps took is gone by now (freed at the end of its frame).
	for group: StringName in [&"player_projectile", &"pickup"]:
		for r in _swept:
			var n: Variant = r.get_ref()
			if n != null and is_instance_valid(n) and (n as Node).is_in_group(group):
				out.append(String(group))
				break
	var growth: StringName = def.growth if def != null else &""
	if is_instance_valid(_gems) and growth != &"levelups":
		out.append("gems")
	if is_instance_valid(_drops) and growth != &"pickups":
		out.append("drops")
	if _meter != null and growth == &"":
		out.append("meter")
	if is_instance_valid(_widget) and (def == null or not _widget_fits()):
		out.append("widget")
	if EventBus.enemy_killed.is_connected(_on_enemy_killed) and growth != &"cards":
		out.append("card_feed")
	if RunState.ai_owner.values().has(&"path") and (def == null or not &"crowd" in def.basics):
		out.append("crowd")
	var lo := loadout()
	if lo != null:
		var start: Array = def.start.duplicate() if def != null else [Loadout.PISTOL]
		var want := ",".join(start.map(func(w: StringName) -> String: return "%s:1" % w))
		if lo.summary() != want:
			out.append("loadout")
	return out


func _widget_fits() -> bool:
	match def.widget:
		&"hand":
			return _widget.get_script() == HandWidget
		&"level":
			return _widget.get_script() == LevelWidget
		&"ammo":
			return _widget.get_script() == AmmoWidget
	return false


func _apply(id: StringName) -> void:
	_clear_growth()
	picks_on_path = 0
	_still_tick = _tick + roundi(STILL_AFTER * Engine.physics_ticks_per_second) if _tryout() and id != &"" else -1
	var lo0 := loadout()
	_fp_base = [picks, lo0.switches if lo0 != null else 0, pickups_taken]
	if RunState.session != null and RunState.session.tryout:
		fp = Fingerprint.new()
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
	if def.growth == &"pickups" and not frozen:
		_grow_survival()
	var lo := loadout()
	if lo != null and def.quick_draw_mult > 1.0 and &"quick_draw" in def.basics \
			and Unlocks.has_basic(&"quick_draw"):
		lo.quick_draw_mult = def.quick_draw_mult
	# The crowd overlay only on its own path (D6, M46): outside a session every basic is on.
	if _overlay == null and &"crowd" in def.basics and Unlocks.has_basic(&"crowd"):
		_overlay = PathOverlay.make(def)
		if not RunState.add_ai(_overlay, &"path"):
			_overlay = null


## Survival (M47): Drops and the ammo widget while the path is live; `pickups` arms the
## drops (and crates outside a tryout), `kill_heal` its heals, each only as its own basic.
func _grow_survival() -> void:
	if _drops == null:
		_drops = Drops.new()
		_drops.name = "Drops"
		_drops.runner = self
		_drops.crates = RunState.session == null or not RunState.session.tryout
		add_child(_drops)
		_widget = AmmoWidget.new()
		_widget.name = "AmmoWidget"
		_widget.loadout = loadout()
		var hud: Node = game.get(&"hud") if game != null else null
		if hud != null and hud.has_method(&"set_path_widget"):
			hud.set_path_widget(_widget)
		else:
			add_child(_widget)
	if &"pickups" in def.basics and Unlocks.has_basic(&"pickups"):
		_drops.arm_pickups()
	if &"kill_heal" in def.basics and Unlocks.has_basic(&"kill_heal"):
		_drops.arm_kill_heal()


## Kill-heals on Survival (0 elsewhere).
func heals() -> int:
	return int(_drops.get(&"heals")) if is_instance_valid(_drops) else 0


func crates_taken() -> int:
	return int(_drops.get(&"crates_taken")) if is_instance_valid(_drops) else 0


## A `drop` cue (D9): false unless Survival is live (the caller warns).
func drop(what: StringName, n: int) -> bool:
	if not is_instance_valid(_drops) or def == null or def.growth != &"pickups" or _stopped:
		return false
	return int(_drops.call(&"drop_now", what, n)) > 0


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
	if is_instance_valid(_drops):
		remove_child(_drops)   # its kill listener goes now (_exit_tree), not at frame end
		_drops.queue_free()
	_drops = null
	_meter = null
	if is_instance_valid(_widget):
		_widget.queue_free()
	_widget = null
	_want = 0


func _on_basic_added(id: StringName) -> void:
	if id in [&"levelups", &"crowd", &"cards", &"quick_draw", &"pickups", &"kill_heal"]:
		_grow()


func _on_gem_taken(value: int) -> void:
	if _meter != null and not frozen:
		_meter.call(&"add", value)


func _on_pickup_taken(kind: StringName, _id: StringName) -> void:
	pickups_taken += 1
	pickup_kinds[String(kind)] = int(pickup_kinds.get(String(kind), 0)) + 1


## The bot's --loadout= (D13): a fixed loadout from now on, no growth (no gems, no picks).
func freeze() -> void:
	frozen = true
	_want = 0
	_feed_cards(false)   # Arsenal: no kills fill the card meter either
	if is_instance_valid(_gems):
		_gems.queue_free()
	_gems = null
	if is_instance_valid(_drops):   # M47: Survival drops nothing either
		_drops.set(&"pickups_on", false)
		_drops.set(&"heal_on", false)
		_drops.set(&"_next_crate", -1)


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
	if def != null and def.growth == &"pickups" and is_instance_valid(_drops):
		# M47 (1.3): a crate near the player; with no tile free, the gun into the slot.
		return bool(_drops.call(&"crate_near_player", w))
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
		if def.growth == &"pickups":
			var lo := loadout()
			fp.survival_tick(lo != null and lo.on_sidearm() and Unlocks.has_basic(&"pickups"))
	if _still_tick >= 0 and _tick >= _still_tick:
		_still_tick = -1
		capture_still()
	if _sweep_tick >= 0 and Engine.get_physics_frames() >= _sweep_tick:
		_sweep_tick = -1
		var before := _swept.size()
		var keep := []   # untyped: has() is asked of shots too, never only Pickups
		if is_instance_valid(_drops):
			keep.append_array(_drops.get(&"_mine") as Array)
		_sweep(keep, late_sweep)
		_late_swept = _swept.size() - before
		_check_tick = Engine.get_physics_frames() + 1
	elif _check_tick >= 0 and Engine.get_physics_frames() >= _check_tick:
		_check_tick = -1
		var left := leftovers()
		leftover_checks.append(left)
		RunState.log_event(&"path_leftovers", {"to": String(path_id), "left": left, "late": _late_swept})
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
	picks_on_path += 1
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
	wipes += 1
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
	rect.color = Color(Palette.SHADOW, 0.6)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.add_child(rect)
	add_child(_fade)
	var tween := rect.create_tween()
	tween.tween_property(rect, ^"color:a", 0.0, FADE_SECONDS)
	tween.tween_callback(_fade.queue_free)


## F1's line: "path=auto level=2 picks=1 pickups=7"; Arsenal (M46):
## "path=arsenal cards=1 kills=20/36 picks=1 pickups=0"; Survival (M47):
## "path=survival weapon=shotgun:2 ammo=18/24 picks=0 pickups=7 heals=2" (the sidearm: ammo=-).
func state_text() -> String:
	if def != null and def.growth == &"pickups":
		var lo := loadout()
		var w: Weapon = lo.current() if lo != null else null
		var ammo := "-"
		if w != null and not lo.on_sidearm() and w.def.ammo > 0:
			ammo = "%d/%d" % [w.ammo_left, w.def.ammo]
		return "path=survival weapon=%s ammo=%s picks=%d pickups=%d heals=%d" % [
				"%s:%d" % [w.def.id, w.rank] if w != null else "-", ammo, picks, pickups_taken, heals()]
	if _cards_growth():
		var need := int(_meter.call(&"next_need")) if _meter != null else -1
		return "path=%s cards=%d kills=%d/%s picks=%d pickups=%d" % [path_id, cards(),
				int(_meter.get(&"kills")) if _meter != null else 0, str(need) if need >= 0 else "-", picks,
				pickups_taken]
	return "path=%s level=%d picks=%d pickups=%d" % [path_id if path_id != &"" else &"-", level(), picks,
			pickups_taken]
