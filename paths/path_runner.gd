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
##
## M50.1a (Arsenal depth): a path with PathDef.pack_every > 0 deals booster packs (PackMeter,
## BoosterPack on RunState.pack_rng) instead of the card meter's cards: no session cap, owed
## packs queue (until M50.6 they opened by themselves, PACK_GAP s apart; now see M50.6 below),
## and the pick counts feed the telemetry.
##
## M50.1b (fusion): once the `fusion` basic is live, a hand that is a built recipe pair with
## both cards at rank 4+ gets a FUSE choice in its packs (BoosterPack.fuse_option): FUSE melts
## them into the fused card (Loadout.fuse), the same pack reopens for the new hand, the first
## fusion of a recipe is learned (SaveGame.learn_recipe, a patch-note line) and the hand's link
## shows (link_state). `fuse fail` (S9's beat, fuse_fail()) is the misfuse: an overlay for
## MISFUSE_SECONDS of game time (the Loadout untouched; its shots leave the wrong way, switching
## locked, no pack opens), then the AI patches it (a patch-note line).
##
## M50.4c1 (Auto depth design 2.5, 6): once the `evolve` basic is live on a levelups path, a held
## deep weapon at the rank cap whose catalyst item is held (its evolution built, none of it held
## yet, at most MAX_EVOLUTIONS a session) puts an EVOLVE choice in the next level-up
## (evolve_option; the choice after the cards). Taking it spends the level-up: the weapon
## becomes its evolution in place (Loadout.evolve), the first of each id is learned as a recipe.
## While a held weapon below the cap has its catalyst held, its upgrade is offered first (a give
## wins). S9's `evolved 1: nerf 8` arms the evolution's launch numbers (too strong); 8 s of game
## time later the AI patches them down live (one glitch pulse, a patch-note line written from the
## effective numbers); a session that ends first lands it at stop(), a path swap drops it.
##
## M50.2a (pack tuning): a 1-card pack (toast_pack: no choice to make) applies at once with no
## pause and shows as PickPanel.toast(); it still counts as a pack. packs_short / packs_toast /
## rares_shown feed the telemetry and the bot's line.
##
## M50.2b (the give step, Arcade through S10 design 2): a `give` on a full pack hand (packs
## live) no longer queues in the next packs (G4 is retired here): it opens the give step on the
## first free tick (can_open_now(), never on the misfuse's last tick, before an owed pack): the
## replace step on the given card alone, "Replace <card>" per slot or "Keep your hand". It
## draws nothing, is not a pack pick (no `picked`, no pick_offered, PackMeter untouched). Keep
## leaves the weapon in the live pool. (M50.6: a stacked pack after it waits for the key.)
##
## M50.6 (stacked packs and weapon rarity): a pack no longer opens by itself. Each pack the
## meter deals goes on the stack (pack_stack(); the same count as pending_picks()); the player's
## open_pack action (PlayerInput.open_pack_pressed, or open_pack()) opens the top one on that
## tick when can_open_now() holds, with the same panel and pause as before. One press, one
## pack: nothing chains, and no timer spaces packs (the press is the gap). The bot asks every tick,
## so its packs open on the first free tick and a seed replays. A waiting give step still opens
## by itself, before a pack. Unopened packs carry to the path's next session (bank_packs() at a
## session the player moves on from, SaveGame.packs_banked() when the pack meter is built; never
## in a tryout or outside a session). The path's pack_first_line is said when a session's first
## pack lands, its pack_stack_line once when the stack reaches Tuning.pack_nudge_at. An EPIC
## card (BoosterPack.epic_card, only once `fusion` is live) is a ready-made fusion: taken, it
## melts the held parents (Loadout.fuse / absorb) or joins / replaces like a new card, and is
## recorded like a fusion made (`fusions` with epic: true, the recipe learned).
##
## M50.6a: in a tryout whose path sets PathDef.taste_auto_open (S7's Arsenal taste), every tick
## counts as asked: the taste's packs open by themselves on the first free tick (what the bot
## does everywhere), and the pack lines that teach the key wait for S8.

signal started(path_id: StringName)
## M47.6d1: a `path` cue landed (its warning starts): the title card (PathTitle) shows.
signal swap_requested(path_id: StringName)

const Gems := preload("res://paths/auto/gems.gd")
const LevelMeter := preload("res://paths/auto/level_meter.gd")
const LevelWidget := preload("res://paths/auto/level_widget.gd")
const CardMeter := preload("res://paths/arsenal/card_meter.gd")
const PackMeter := preload("res://paths/arsenal/pack_meter.gd")
const HandWidget := preload("res://paths/arsenal/hand_widget.gd")
const Drops := preload("res://paths/survival/drops.gd")
const AmmoWidget := preload("res://paths/survival/ammo_widget.gd")
const AmmoOverheadScript := preload("res://paths/survival/ammo_overhead.gd")
const SWAP_WARN_SECONDS := 1.5
## M50.1a: owed packs never opened back to back. M50.6: unused (the player opens each pack);
## kept for the tools and tests that name it.
const PACK_GAP := 2.0
## M50.1b: the misfuse lasts this much game time (the pause stops it).
const MISFUSE_SECONDS := 6.0
const MISFUSE_SKIN := &"shot_misfuse_player"
const MISFUSE_NOTE := "Fixed: cards fusing into a gun with guns on it."
## M50.4c1: at most this many evolutions a session (one per weapon; 2 passive slots).
const MAX_EVOLUTIONS := 2
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
## M50.1a (packs): what was taken, for the telemetry and the bot's line.
## M50.6: `rare` counts the rare-tier cards taken (no bonus any more), `epic` the epic ones.
var pack_picks := {"upgrade": 0, "rare": 0, "new": 0, "replace": 0, "back": 0, "fuse": 0, "epic": 0}
## M50.4a (levelups picks): what each level-up took, for the telemetry and the bot's line.
## item_new / item_up are the passive items (M50.4b); evolve stays 0 until M50.4c1.
var level_picks := {"upgrade": 0, "new": 0, "item_new": 0, "item_up": 0, "evolve": 0, "filler": 0}
## M50.2a (telemetry, the bot's line): packs dealt with fewer than 3 cards, the 1-card ones
## applied as a toast (no pause), and the rare cards shown in all packs.
var packs_short := 0
var packs_toast := 0
var rares_shown := 0
## M50.6: epic cards shown, packs opened (a toast counts), the packs carried in from the last
## session, the most ever stacked, and whether the two pack lines were said.
var epics_shown := 0
var packs_opened := 0
var packs_carried := 0
var stack_peak := 0
var first_pack_said := false
var stack_nudged := false
## M50.2b: each give step closed: {weapon, rank, choice: "replace:<id>" | "keep", t}.
var gives: Array[Dictionary] = []
## M50.1b: each fusion made: {id, t, from: ["shotgun:5", "laser:4"], rank}.
var fusions: Array[Dictionary] = []
## M50.1b: the times FUSE became available (the `fuse_ready n` cues read it) and the ticks it
## stayed available unused (telemetry's link_lit_s).
var fuse_ready_count := 0
var link_lit_ticks := 0
## M50.1b: the misfuse ({} none): {t, pair, restored}.
var misfuse := {}
## M47.6d1: the last title card shown (PathTitle) and every title shown, in order (tests).
var title_card: PathTitle
var titles_shown: Array[String] = []
## M50.4c1: each evolution made: {id, t, from: "pistol:6", catalyst: "haste:2"}.
var evolutions: Array[Dictionary] = []
## M50.4c1: the times EVOLVE became available (the `evolve_ready n` cues), the first one's game
## time (-1 never), and the nerfs landed (`nerfed n`).
var evolve_ready_count := 0
var evolve_ready_t := -1.0
var nerfs_landed := 0
## M50.4c1: the live nerf ({} none): {id, t_armed, t_landed (-1 pending), text}.
var nerf := {}

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
var _overhead: Node2D       ## M47.6d1: Survival's rounds over the player (AmmoOverhead)
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
var _open_req := false           ## M50.6: open_pack() was asked (read on the next tick)
## M50.2b: full-hand gives waiting for their give step ({id, rank}, in cue order).
var _gives: Array[Dictionary] = []
var _misfuse_end_tick := -1      ## M50.2b: the tick the misfuse ended (the give step waits a tick)
var _fuse_was_ready := false
var _misfuse_left := 0           ## M50.1b: physics ticks the misfuse has left (0: none)
var _misfuse_before := ""
var _evolve_was_ready := false
var _nerf_left := 0              ## M50.4c1: physics ticks until the nerf lands (0: none pending)


func _ready() -> void:
	EventBus.basic_added.connect(_on_basic_added)
	EventBus.pickup_taken.connect(_on_pickup_taken)
	if panel != null:
		panel.picked.connect(_on_picked)
		panel.went_back.connect(_on_back)
		panel.fuse_requested.connect(_on_fuse)
		panel.give_done.connect(_on_give_done)


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


## M50.1a: Arsenal's booster packs (a cards path with pack_every > 0).
func pack_path() -> bool:
	return _cards_growth() and def.pack_every > 0


## M50.2b: the weapon whose give step is waiting to open (&"" none).
func give_pending() -> StringName:
	return _gives[0].id if not _gives.is_empty() else &""


## M50.2b: the give steps closed so far (the `give_choice n` cues read it).
func give_steps() -> int:
	return gives.size()


## M50.2b (`paired`, a hand fact): the hand is a built recipe pair, whatever the `fusion` basic.
func paired() -> bool:
	var lo := loadout()
	return lo != null and not BoosterPack.recipe_pair(lo).is_empty()


func meter() -> RefCounted:
	return _meter


## M47.6d1: Survival's ammo over the player (null on other paths).
func overhead() -> Node2D:
	return _overhead if is_instance_valid(_overhead) else null


func widget() -> Control:
	return _widget


func overlay() -> PathOverlay:
	return _overlay


## Picks asked and not made yet (a pack path: the packs on the stack).
func pending_picks() -> int:
	return _want


## M50.6: the booster packs waiting to be opened (0 off a pack path).
func pack_stack() -> int:
	return _want if pack_path() else 0


## M50.6: asks for the top pack of the stack (the open_pack action; tests). It opens on the
## next physics tick if it may. False with no pack stacked or when nothing may open now.
func open_pack() -> bool:
	if pack_stack() <= 0 or not can_open_now():
		return false
	_open_req = true
	return true


## M50.6: the stack's key on the player's layout ("F"), for the HUD.
static func open_key() -> String:
	return InputSetup.expand_keys("{key:open_pack}")


## M50.6: the session is done and the player moves on: the unopened packs wait in the save for
## the path's next session (not a tryout's, nothing outside a session). Main._end_session.
func bank_packs() -> void:
	if RunState.session == null or RunState.session.tryout or not pack_path() or SaveGame.in_replay():
		return
	SaveGame.bank_packs(pack_stack())


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
	swap_requested.emit(target)
	_show_title(to)
	return true


## M47.6d1: the target's title card on the HUD layer (none for `off`).
func _show_title(to: PathDef) -> void:
	if to == null or to.title == "":
		return
	if is_instance_valid(title_card):
		title_card.queue_free()
	title_card = PathTitle.make(to.title)
	titles_shown.append(to.title)
	var hud: Node = game.get(&"hud") if game != null else null
	if hud != null:
		hud.add_child(title_card)
	else:
		add_child(title_card)


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
	if is_instance_valid(_overhead) and not _overhead.is_queued_for_deletion() and growth != &"pickups":
		out.append("overhead")
	if _meter != null and growth == &"":
		out.append("meter")
	if is_instance_valid(_widget) and (def == null or not _widget_fits()):
		out.append("widget")
	if EventBus.enemy_killed.is_connected(_on_enemy_killed) and growth != &"cards":
		out.append("card_feed")
	if RunState.ai_owner.values().has(&"path") and not _crowd_wanted():
		out.append("crowd")
	var lo := loadout()
	if lo != null:
		var start: Array = def.start.duplicate() if def != null else [Loadout.PISTOL]
		var want := ",".join(start.map(func(w: StringName) -> String: return "%s:1" % w))
		if lo.summary() != want:
			out.append("loadout")
	return out


## The path's crowd numbers apply: Auto's once its `crowd` basic is live (D6, M46); M47.6d1: a
## path with no crowd basic whose numbers differ from 1 (Survival's smaller crowd) from its
## start. Arsenal (all 1.0) never has one.
func _crowd_wanted() -> bool:
	if def == null:
		return false
	if &"crowd" in def.basics:
		return Unlocks.has_basic(&"crowd")
	return def.spawn_rate_mult != 1.0 or def.max_enemies_mult != 1.0 or def.enemy_hp_mult != 1.0


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
	if _overlay == null and _crowd_wanted():
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
		var lo := loadout()
		if lo != null and lo.get_parent() is Node2D:
			_overhead = AmmoOverheadScript.new()
			_overhead.name = "AmmoOverhead"
			_overhead.set(&"loadout", lo)
			lo.get_parent().add_child(_overhead)
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
	_widget.runner = self   # M50.4c1: the evolve hint
	var hud: Node = game.get(&"hud") if game != null else null
	if hud != null and hud.has_method(&"set_path_widget"):
		hud.set_path_widget(_widget)
	else:
		add_child(_widget)


## Arsenal (M46): the card meter, fed by player kills, and the hand widget.
func _build_cards() -> void:
	_meter = PackMeter.new() if pack_path() else CardMeter.new()
	_meter.def = def
	_meter.tryout = RunState.session != null and RunState.session.tryout
	_meter.on_card = want_pick
	_meter.on_full = _on_meter_full
	if pack_path() and RunState.session != null and not RunState.session.tryout and not frozen and not SaveGame.in_replay():
		# M50.6: the packs the last session left unopened.
		packs_carried = SaveGame.packs_banked()
		_want = mini(_want + packs_carried, Tuning.pack_stack_max)
		stack_peak = maxi(stack_peak, _want)
	_feed_cards(true)
	_widget = HandWidget.new()
	_widget.name = "HandWidget"
	_widget.meter = _meter
	_widget.loadout = loadout()
	_widget.max_cards = def.max_picks
	_widget.runner = self   # M50.1b: the link (link_state)
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
	if is_instance_valid(_overhead):
		_overhead.queue_free()
	_overhead = null
	_meter = null
	if is_instance_valid(_widget):
		_widget.queue_free()
	_widget = null
	_want = 0
	_open_req = false
	_gives.clear()
	_end_misfuse(false)
	_fuse_was_ready = false
	_drop_nerf()
	_evolve_was_ready = false


func _on_basic_added(id: StringName) -> void:
	if id in [&"levelups", &"crowd", &"cards", &"quick_draw", &"pickups", &"kill_heal", &"fusion"]:
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
## M50.1a (packs): a full hand never loses a card silently once the packs are live. M50.2b: it
## opens the give step (logged `give_offered`; rank 3+ = a gold card) and this returns true;
## before the `cards` basic the old replace applies, logged `give_replaced`.
func give(w: StringName, rank := 1) -> bool:
	announce(w)
	if pack_path():
		var lo := loadout()
		var wd := WeaponDB.get_weapon(w)
		var fed := lo.holder(w) if lo != null else null
		if fed != null and fed.def.is_fusion():
			lo.upgrade(fed.def.id)
			return true   # M50.1b: a parent's give feeds the fusion
		if lo != null and wd != null and not wd.is_passive() and lo.held(w) == null and lo.hand_full():
			if _meter != null and not frozen and not _stopped:
				_gives.append({"id": w, "rank": rank})
				RunState.log_event(&"give_offered", {"weapon": String(w), "rank": rank})
				return true
			RunState.log_event(&"give_replaced", {"weapon": String(w)})
		return false
	if def != null and def.growth == &"pickups" and is_instance_valid(_drops):
		# M47 (1.3): a crate near the player; with no tile free, the gun into the slot.
		return bool(_drops.call(&"crate_near_player", w))
	if def == null or def.growth != &"levelups":
		return false
	_first = w
	return true


## What offers draw from: the live pool, within the session's weapons and the path's extras.
## M47.6d1: on a manual_ammo path whose sidearm is not the pistol (Survival's revolver), a
## pistol in the pool is that sidearm (S7's Arcade taste put the pistol there), once.
func offer_pool() -> Array[StringName]:
	var allowed: Array[StringName] = []
	if RunState.session != null:
		allowed.append_array(RunState.session.weapons)
	if def != null:
		allowed.append_array(def.offer_pool_extra)
	var side: StringName = &""
	if def != null and def.fire_mode == &"manual_ammo" and not def.start.is_empty() and def.start[0] != Loadout.PISTOL:
		side = def.start[0]
	var out: Array[StringName] = []
	for w in live_pool:
		if RunState.session == null or w in allowed:
			var id := side if side != &"" and w == Loadout.PISTOL else w
			if not id in out:
				out.append(id)
	return out


# --- Picks --------------------------------------------------------------------------------

## The meter levelled up: a pick is owed (opened on the first free tick). M50.6: on a pack
## path it is a pack on the stack, opened only when the player asks.
func want_pick() -> void:
	if frozen:
		return
	if not pack_path():
		_want += 1
		return
	_want = mini(_want + 1, Tuning.pack_stack_max)
	stack_peak = maxi(stack_peak, _want)
	if auto_opens():
		return   # M50.6a: nothing to teach, the taste's packs open by themselves
	if not first_pack_said and def.pack_first_line != "":
		first_pack_said = true
		_speak(SessionRunner.with_keys(Line.parse(def.pack_first_line)), SessionRunner.PRIORITY, true)
	elif not stack_nudged and _want >= Tuning.pack_nudge_at and def.pack_stack_line != "":
		stack_nudged = true
		_speak(SessionRunner.with_keys(Line.parse(def.pack_stack_line)), SessionRunner.PRIORITY, true)


## M50.6a: this path's packs open by themselves here (a tryout's taste, PathDef.taste_auto_open).
func auto_opens() -> bool:
	return def != null and def.taste_auto_open and _tryout() and pack_path()


func _on_meter_full() -> void:
	if def != null and def.full_line != "":
		_speak(Line.parse(def.full_line), SessionRunner.PRIORITY, true)


## 1.5's pause rule: never over a rule edit's warning, an event or a pending swap, never
## after the session ended. (Not RuleBook.busy(): a live timed edit would hold picks for
## its whole length.)
func can_open_now() -> bool:
	if _stopped or _over() or _swap_tick >= 0 or panel == null or panel.is_open() or _misfuse_left > 0:
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
	if _misfuse_left > 0:
		_misfuse_left -= 1
		if _misfuse_left == 0:
			_end_misfuse(true)
			_misfuse_end_tick = _tick
	if fusion_live() and not _stopped:
		var lo_f := loadout()
		var ready := lo_f != null and BoosterPack.can_fuse(lo_f)
		if ready:
			link_lit_ticks += 1
			if not _fuse_was_ready:
				fuse_ready_count += 1
		_fuse_was_ready = ready
	if _nerf_left > 0:
		_nerf_left -= 1
		if _nerf_left == 0:
			_land_nerf()
	if evolve_live() and not _stopped:
		var ready_e := not evolve_option().is_empty()
		if ready_e and not _evolve_was_ready:
			evolve_ready_count += 1
			if evolve_ready_t < 0.0:
				evolve_ready_t = snappedf(RunState.game_time, 0.1)
		_evolve_was_ready = ready_e
	# M50.6: a stacked pack opens only when asked on this tick (the player's key, the bot's
	# standing ask, open_pack()); any other pick opens by itself, as before.
	var asked := _open_req or not pack_path() or auto_opens()
	_open_req = false
	if not asked and is_instance_valid(p):
		var input := p.get(&"input") as PlayerInput
		asked = input != null and input.open_pack_pressed
	# M50.2b: a waiting give step opens first (never on the misfuse's last tick), then packs.
	if not _gives.is_empty() and not _opening and _tick > _misfuse_end_tick and can_open_now():
		_opening = true
		_open_give.call_deferred()
	elif _want > 0 and asked and not _opening and can_open_now():
		_opening = true
		_open_offer.call_deferred()


## Deferred (never pause inside a physics callback); checks again, as the run can end in the
## frame the meter asked.
func _open_offer() -> void:
	_opening = false
	var lo := loadout()
	if _want <= 0 or lo == null or not can_open_now():
		return
	var offer: PickOffer
	if pack_path():
		# M50.2b: no G4. M50.6: epic cards only once the `fusion` basic is live.
		offer = BoosterPack.draw(lo, def, offer_pool(), {}, RunState.pack_rng, taste, fusion_live())
		offer.fuse = fuse_option()
		if &"fusion" in def.basics:
			BoosterPack.mark_keeps(offer, lo)
		packs_opened += 1
		if offer.cards.size() < 3:
			packs_short += 1
		for c: Dictionary in offer.cards:
			if c.get("rarity") == BoosterPack.RARE:
				rares_shown += 1
			elif BoosterPack.is_epic(c):
				epics_shown += 1
		if toast_pack(offer, lo):
			# M50.2a (D3): a 1-card pack has no choice: it applies now, with no pause, and a
			# short toast shows it. It still counts as a pack (the meter, `picked n`, the log).
			packs_toast += 1
			offers.append(offer)
			EventBus.pick_offered.emit(offer)
			panel.toast(offer)
			_pick(offer, 0)
			return
	else:
		var first := _first
		if first == &"" and _cards_growth():
			first = most_fired(lo)   # Arsenal: the most-fired card's upgrade first (1.5, D7)
		if first == &"" and evolve_live():
			first = steer(lo)   # M50.4c1: a weapon whose catalyst is held ranks first
		offer = PickOffer.draw(lo, def, offer_pool(), first, RunState.pick_rng, taste)
		_first = &""
		if def != null and def.growth == &"levelups":
			# M50.4b: the dressed cards' banner and pips (presentation only).
			offer.level = level()
			offer.cap = lo.rank_cap if lo.rank_cap > 0 else Loadout.MAX_RANK
			offer.evolve = evolve_option()   # M50.4c1: never one of the cards
	offers.append(offer)
	EventBus.pick_offered.emit(offer)
	fp.menu_open()
	panel.open(offer)


## M50.2b: the waiting give's step (deferred, like a pack; checks again). The hand may have
## changed since the cue: a weapon now held (or fed into a fusion) ranks up, a hand with room
## takes it at once; else the panel opens the give step on the given card alone.
func _open_give() -> void:
	_opening = false
	var lo := loadout()
	if _gives.is_empty() or lo == null or not can_open_now():
		return
	var g: Dictionary = _gives.pop_front()
	var id: StringName = g.id
	var rank := int(g.rank)
	var fed := lo.holder(id)
	if fed != null:   # as give() does: a fusion's parent feeds it, a held card ranks up
		if fed.def.is_fusion():
			lo.upgrade(fed.def.id)
		else:
			lo.give(id, rank)
		return
	if not lo.hand_full():
		lo.give(id, rank)
		return
	var offer := PickOffer.new()
	offer.pack = true
	offer.give_step = true
	offer.max_slots = lo.max_slots
	for w in lo.slots:
		offer.hand.append({"id": w.def.id, "title": w.def.title, "rank": w.rank})
	var card := BoosterPack.give_card(lo, id, rank)
	var links: Array[int] = []
	for j in lo.slots.size():
		var f := WeaponDB.recipe(id, lo.slots[j].def.id)
		if not lo.slots[j].def.is_fusion() and f != &"" and WeaponDB.fusion_built(f):
			links.append(j)
	card["links"] = links[0] if links.size() == 1 else -1
	card["recipe"] = ""
	if links.size() == 1 and fusion_live():
		card["recipe"] = String(WeaponDB.get_weapon(WeaponDB.recipe(id, lo.slots[links[0]].def.id)).title)
	offer.cards.append(card)
	offer.line = ("A gold card: %s." if card.rarity == BoosterPack.RARE else "A new card: %s.") % card.title
	offers.append(offer)
	fp.menu_open()
	panel.open_give(offer)


## M50.2b: the give step closed: `slot` replaced by the given card, or -1 (the hand kept; the
## weapon stays in the live pool, so a later pack can show it as NEW). M50.6: a stacked pack
## after it waits to be asked, like any other.
func _on_give_done(offer: PickOffer, slot: int) -> void:
	fp.menu_close()
	var p: Node = game.get(&"player") if game != null else null
	if is_instance_valid(p) and p.get(&"input") != null:
		(p.get(&"input") as PlayerInput).require_fresh_press()
	var lo := loadout()
	var card: Dictionary = offer.cards[0]
	var choice := "keep"
	if slot >= 0 and lo != null and slot < lo.slots.size():
		var old: StringName = lo.slots[slot].def.id
		if lo.replace_slot(slot, card.id, int(card.rank)):
			choice = "replace:%s" % old
	if choice == "keep":
		pack_picks.give_kept = int(pack_picks.get("give_kept", 0)) + 1
	var rec := {"weapon": String(card.id), "rank": int(card.rank), "choice": choice,
			"t": snappedf(RunState.game_time, 0.1)}
	gives.append(rec)
	RunState.log_event(&"give_choice", rec.duplicate())


## The held aimed card with the most shots that can still rank up (ties: slot order), or
## &"" for none. Offered first only if it is in the live pool (PickOffer.draw).
static func most_fired(lo: Loadout) -> StringName:
	var best: Weapon = null
	for w in lo.slots:
		if w.deep():
			if lo.rank_cap > 0 and w.rank >= lo.rank_cap:
				continue
		elif w.rank >= mini(lo.rank_cap, w.def.max_rank()):
			continue
		if best == null or w.shots > best.shots:
			best = w
	return best.def.id if best != null else &""


## M50.2a (D3): a pack with no choice: one card, no FUSE, and the card ranks a held weapon up
## or joins a hand with room (never a replace step).
static func toast_pack(offer: PickOffer, lo: Loadout) -> bool:
	if not offer.pack or offer.cards.size() != 1 or not offer.fuse.is_empty() or lo == null:
		return false
	var c: Dictionary = offer.cards[0]
	return c.kind == &"upgrade" or (c.kind == &"new" and not lo.hand_full())   # never an `absorb`


func _on_picked(offer: PickOffer, index: int) -> void:
	fp.menu_close()
	# The key that picked card n must not also pick slot n (keys 1-3, M46).
	var p: Node = game.get(&"player") if game != null else null
	if is_instance_valid(p) and p.get(&"input") != null:
		(p.get(&"input") as PlayerInput).require_fresh_press()
	_pick(offer, index)


## The chosen card applies (the panel's pick, or M50.2a's 1-card toast; M50.4c1: or the
## level-up's EVOLVE choice, index cards.size()).
func _pick(offer: PickOffer, index: int) -> void:
	var lo := loadout()
	if not offer.pack and not offer.evolve.is_empty() and index == offer.cards.size():
		_take_evolve(lo, offer.evolve)
		return
	var card: Dictionary = offer.cards[index]
	_want = maxi(0, _want - 1)
	picks += 1
	picks_on_path += 1
	if offer.pack:
		_take_pack_card(lo, card)
	elif card.get("item", false) and lo != null:
		# M50.4b: a passive item joins (level 1) or levels up.
		if card.kind == &"new":
			lo.add_item(card.id)
		else:
			lo.level_item(card.id)
	elif card.kind == &"new" and lo != null:
		lo.give(card.id, 1)
	elif card.kind == &"upgrade" and lo != null:
		lo.upgrade(card.id)
	elif card.kind == PickOffer.HP:
		_one_more_hp()
	elif card.kind == PickOffer.BOOST and lo != null:
		lo.add_boost()
	if not offer.pack and def != null and def.growth == &"levelups":
		var key := String(card.kind) if card.kind in [&"upgrade", &"new"] else "filler"
		if card.get("item", false):
			key = "item_new" if card.kind == &"new" else "item_up"
		level_picks[key] = int(level_picks[key]) + 1
	for c in offer.cards:
		taste._nudge_raw(c.id, [], Taste.PICK if c == card else Taste.PASS)
	RunState.log_event(&"pick", {"offer": offer.ids().map(func(i: StringName) -> String: return String(i)),
			"pick": String(card.id)})
	EventBus.pick_made.emit(card.id)
	if offer.pack:
		# M50.1a: no "good pick" each pack (the `picked n` cues speak).
		return
	_speak(Line.parse(PICK_LINES[(picks - 1) % PICK_LINES.size()]), 1)


# --- Evolution (M50.4c1) -------------------------------------------------------------------

## The `evolve` basic is live on this levelups path (until then no EVOLVE, no steering).
func evolve_live() -> bool:
	return _levelups() and &"evolve" in def.basics and Unlocks.has_basic(&"evolve")


## The EVOLVE choice the loadout has now ({} none, or before the `evolve` basic): a held deep
## weapon at the rank cap, its evolution built, its catalyst item held, none of it held yet,
## fewer than MAX_EVOLUTIONS made. Several: the most shots, ties weapons() order.
## {from, into, catalyst, rank, text}.
func evolve_option() -> Dictionary:
	var lo := loadout()
	if lo == null or not evolve_live() or evolutions.size() >= MAX_EVOLUTIONS or lo.rank_cap <= 0:
		return {}
	var best: Weapon = null
	var best_into: StringName = &""
	for w in lo.weapons():
		var into := _evolve_target(lo, w)
		if into == &"" or w.rank < lo.rank_cap:
			continue
		if lo.item_level(WeaponDB.get_weapon(into).catalyst) <= 0:
			continue
		if best == null or w.shots > best.shots:
			best = w
			best_into = into
	if best == null:
		return {}
	var e := WeaponDB.get_weapon(best_into)
	return {"from": best.def.id, "into": e.id, "catalyst": e.catalyst, "rank": best.rank,
			"text": PickOffer.evolve_line(best.def, WeaponDB.item(e.catalyst), e, best.rank)}


## The built evolution weapon `w` could become (&"" none: an evolution, a fusion, unbuilt, or
## one of it held already).
func _evolve_target(lo: Loadout, w: Weapon) -> StringName:
	if not w.deep() or w.def.is_evolution() or w.def.is_fusion():
		return &""
	var into := WeaponDB.evolution_for(w.def.id)
	if into == &"" or not WeaponDB.evolution_built(into) or lo.evolution_of(w.def.id) != null:
		return &""
	return into


## M50.4c1 (design 2.6, steering): the held weapon below the cap whose catalyst is held
## (highest rank first, ties weapons() order), offered first; &"" none.
func steer(lo: Loadout) -> StringName:
	var best: Weapon = null
	for w in lo.weapons():
		var into := _evolve_target(lo, w)
		if into == &"" or (lo.rank_cap > 0 and w.rank >= lo.rank_cap):
			continue
		if lo.item_level(WeaponDB.get_weapon(into).catalyst) <= 0:
			continue
		if best == null or w.rank > best.rank:
			best = w
	return best.def.id if best != null else &""


## EVOLVE was chosen: it is the level-up's pick (counted, `pick_made`), no pick line, no taste
## nudge. The first of each evolution is learned as a recipe (a patch-note line).
func _take_evolve(lo: Loadout, ev: Dictionary) -> void:
	_want = maxi(0, _want - 1)
	picks += 1
	picks_on_path += 1
	level_picks.evolve = int(level_picks.evolve) + 1
	if lo == null:
		return
	var from_id: StringName = ev.from
	var into_id: StringName = ev.into
	var from := "%s:%d" % [from_id, lo.rank_of(from_id)]
	var cat := "%s:%d" % [ev.catalyst, lo.item_level(ev.catalyst)]
	if not lo.evolve(from_id, into_id):
		return
	var t := snappedf(RunState.game_time, 0.1)
	evolutions.append({"id": String(into_id), "t": t, "from": from, "catalyst": cat})
	RunState.log_event(&"evolved", {"weapon": String(into_id), "from": from, "catalyst": cat})
	var into := WeaponDB.get_weapon(into_id)
	if SaveGame.learn_recipe(into_id):
		RunState.log_event(&"patch_note", {"text": "New recipe: %s (%s + %s)" % [into.title, from_id, ev.catalyst]})
	_evolve_was_ready = false
	EventBus.pick_made.emit(into_id)


## S9's `nerf <s>` cue (it sits on an `evolved n` cue): the evolution just made starts at its
## launch numbers, and `seconds` of game time later the AI patches it to its steady ones. False
## (logged nerf_skipped) with no evolution held, no launch numbers or a nerf already armed.
func arm_nerf(seconds: float) -> bool:
	var lo := loadout()
	var w: Weapon = null
	if lo != null and not evolutions.is_empty():
		for x in lo.weapons():
			if String(x.def.id) == String(evolutions[evolutions.size() - 1].id):
				w = x
	if w == null or w.def.launch_values.is_empty() or not nerf.is_empty() or _stopped:
		RunState.log_event(&"nerf_skipped", {})
		return false
	var launch := {}
	for k: Variant in w.def.launch_values:
		launch[StringName(k)] = w.def.launch_values[k]
	w.launch = launch
	lo.reread(w)   # M50.4c2: a node weapon (the Supernova) takes its launch numbers now
	_nerf_left = maxi(1, roundi(seconds * Engine.physics_ticks_per_second))
	nerf = {"id": String(w.def.id), "t_armed": snappedf(RunState.game_time, 0.1), "t_landed": -1.0, "text": ""}
	RunState.log_event(&"nerf_armed", {"weapon": String(w.def.id), "seconds": seconds})
	return true


## The nerf is pending (tests).
func nerf_pending() -> bool:
	return _nerf_left > 0


## The AI's live patch: the launch numbers go (slot, shots and item mods kept), one glitch
## pulse, a patch-note line from the effective numbers before and after.
func _land_nerf() -> void:
	_nerf_left = 0
	if nerf.is_empty() or float(nerf.t_landed) >= 0.0:
		return
	var lo := loadout()
	var w: Weapon = null
	if lo != null:
		for x in lo.weapons():
			if String(x.def.id) == String(nerf.id):
				w = x
	nerf.t_landed = snappedf(RunState.game_time, 0.1)
	if w == null:
		return
	# M50.4c2 review: the note names only the launch keys (the Thunderclap has no cooldown one,
	# and its blast radius is the cut the player sees), in a fixed order.
	var keys: Array[StringName] = []
	for k: Variant in w.launch:
		keys.append(StringName(k))
	var before := {}
	for k in [&"cooldown", &"damage", &"blast_radius"]:
		before[k] = float(w.value(k))
	w.launch = {}
	lo.reread(w)   # M50.4c2: a node weapon re-reads its steady numbers, its clock kept
	nerf.text = "Balance: %s %s. It was too strong." % [w.def.title, nerf_parts(w, keys, before)]
	nerfs_landed += 1
	RunState.log_event(&"patch_note", {"text": nerf.text})
	RunState.log_event(&"nerfed", {"weapon": String(w.def.id)})
	_pulse()


## The changed numbers of a live nerf, from the launch `keys` and the effective `before` values
## (cooldown, damage, blast_radius) to `w`'s now: "30 -> 15 shots/s" (aimed) or "every 1.2 s ->
## every 2 s" (a node weapon, on its own clock), "damage a -> b", "blast a T -> b T". A part
## whose number did not move is left out.
static func nerf_parts(w: Weapon, keys: Array[StringName], before: Dictionary) -> String:
	var parts: PackedStringArray = []
	if &"cooldown" in keys:
		var cd_before := float(before[&"cooldown"])
		var cd_after := float(w.value(&"cooldown"))
		if w.def.is_passive():
			if not is_equal_approx(snappedf(cd_before, 0.01), snappedf(cd_after, 0.01)):
				parts.append("every %s s -> every %s s" % [WeaponCurve.num(snappedf(cd_before, 0.01)), WeaponCurve.num(snappedf(cd_after, 0.01))])
		elif not is_equal_approx(fire_rate(cd_before), fire_rate(cd_after)):
			parts.append("%s -> %s shots/s" % [WeaponCurve.num(fire_rate(cd_before)), WeaponCurve.num(fire_rate(cd_after))])
	for pair: Array in [[&"damage", "damage %s -> %s"], [&"blast_radius", "blast %s T -> %s T"]]:
		var k: StringName = pair[0]
		if not k in keys:
			continue
		var a := snappedf(float(before[k]), 0.01)
		var b := snappedf(float(w.value(k)), 0.01)
		if not is_equal_approx(a, b):
			parts.append((pair[1] as String) % [WeaponCurve.num(a), WeaponCurve.num(b)])
	if parts.is_empty():
		return "patched down"
	return ", ".join(parts)


## A path swap (or a new path) drops a pending nerf: the launch numbers go, no note.
func _drop_nerf() -> void:
	if _nerf_left <= 0:
		return
	_nerf_left = 0
	var lo := loadout()
	if lo != null:
		for x in lo.weapons():
			if not x.launch.is_empty():
				x.launch = {}
				lo.reread(x)
	nerf = {}


## Shots a second for a cooldown `cd` on the 60 Hz auto clock: a weapon fires at most once a
## tick and drops the overshoot (Loadout.auto_tick), so every ceil(cd * 60) ticks.
static func fire_rate(cd: float) -> float:
	var ticks := maxi(1, ceili(cd * Engine.physics_ticks_per_second - 0.0001))
	return snappedf(float(Engine.physics_ticks_per_second) / ticks, 0.1)


## The evolve hint (the rail's bottom line, the raw HUD's last row): "EVOLVE next level: pistol
## lv 6 + haste -> MINIGUN" when ready, "pistol lv 4/6 + haste -> MINIGUN" while the catalyst is
## held below the cap, "" before `evolve` or with no pair.
func evolve_hint() -> String:
	var lo := loadout()
	if lo == null or not evolve_live():
		return ""
	var ev := evolve_option()
	if not ev.is_empty():
		return "EVOLVE next level: %s lv %d + %s -> %s" % [ev.from, int(ev.rank), ev.catalyst,
				WeaponDB.get_weapon(ev.into).title.to_upper()]
	if evolutions.size() >= MAX_EVOLUTIONS:
		return ""
	var s_id := steer(lo)
	if s_id == &"":
		return ""
	var into := WeaponDB.get_weapon(WeaponDB.evolution_for(s_id))
	return "%s lv %d/%d + %s -> %s" % [s_id, lo.rank_of(s_id), lo.rank_cap, into.catalyst, into.title.to_upper()]


## M50.1a: a pack card goes to the hand: a held weapon ranks up (M50.6: always +1), a new one
## joins at the card's rank or replaces the slot the panel's replace step chose. M50.6: an epic
## card melts the held parents into its fusion (`absorb`) or is a new card at rank 4.
func _take_pack_card(lo: Loadout, card: Dictionary) -> void:
	var rare: bool = card.get("rarity") == BoosterPack.RARE
	var epic := BoosterPack.is_epic(card)
	var from: Array[String] = []
	if lo != null:
		if card.kind == &"upgrade":
			lo.upgrade(card.id)
			pack_picks.upgrade += 1
		elif card.kind == &"absorb":
			var ab: Array = card.get("absorbs", [])
			for a: StringName in ab:
				from.append("%s:%d" % [a, lo.rank_of(a)])
			if ab.size() == 2:
				lo.fuse(ab[0], ab[1], card.id, int(card.rank))
			elif ab.size() == 1:
				lo.absorb(ab[0], card.id, int(card.rank))
			pack_picks.new += 1
		elif card.kind == &"new":
			if card.has("replace"):
				var at := int(card.replace)
				var old: StringName = lo.slots[at].def.id if at < lo.slots.size() else &""
				lo.replace_slot(at, card.id, int(card.rank))
				pack_picks.replace += 1
				RunState.log_event(&"card_replaced", {"weapon": String(card.id), "lost": String(old)})
			else:
				lo.give(card.id, int(card.rank))
			pack_picks.new += 1
	if rare:
		pack_picks.rare += 1
	if epic:
		# Recorded like a fusion made (the `fused n` cues, the debrief, the recipe book).
		pack_picks.epic += 1
		fusions.append({"id": String(card.id), "t": snappedf(RunState.game_time, 0.1), "from": from,
				"rank": int(card.rank), "epic": true})
		RunState.log_event(&"fused", {"weapon": String(card.id), "from": from, "rank": int(card.rank), "epic": true})
		if SaveGame.learn_recipe(card.id):
			RunState.log_event(&"patch_note", {"text": "New recipe: %s" % WeaponDB.get_weapon(card.id).title})
		_fuse_was_ready = false


## M50.1a: the pack panel's Back (the replace step, back to the same pack).
func _on_back(_offer: PickOffer) -> void:
	pack_picks.back += 1


# --- Fusion (M50.1b) ---------------------------------------------------------------------

## The `fusion` basic is live on this pack path (until then no link, no FUSE).
func fusion_live() -> bool:
	return pack_path() and &"fusion" in def.basics and Unlocks.has_basic(&"fusion")


## The FUSE choice the hand has now ({} none, or before the `fusion` basic).
func fuse_option() -> Dictionary:
	var lo := loadout()
	if lo == null or not fusion_live():
		return {}
	return BoosterPack.fuse_option(lo)


## The hand's link: 0 hidden (no `fusion` basic, or not a recipe pair), 1 dim (a recipe pair
## with a half below rank 4), 2 lit (FUSE is available).
func link_state() -> int:
	var lo := loadout()
	if lo == null or not fusion_live() or BoosterPack.recipe_pair(lo).is_empty():
		return 0
	return 2 if BoosterPack.can_fuse(lo) else 1


## The pack panel's FUSE: the two cards melt into the fused card, and the same pack reopens
## for the new hand (FUSE is free: the pick is still to make).
func _on_fuse(offer: PickOffer) -> void:
	var lo := loadout()
	var f: Dictionary = offer.fuse
	if lo == null or f.is_empty():
		return
	var from: Array[String] = ["%s:%d" % [f.a, lo.rank_of(f.a)], "%s:%d" % [f.b, lo.rank_of(f.b)]]
	if not lo.fuse(f.a, f.b, f.id, int(f.rank)):
		return
	var t := snappedf(RunState.game_time, 0.1)
	fusions.append({"id": String(f.id), "t": t, "from": from, "rank": int(f.rank)})
	pack_picks.fuse += 1
	RunState.log_event(&"fused", {"weapon": String(f.id), "from": from, "rank": int(f.rank)})
	if SaveGame.learn_recipe(f.id):
		RunState.log_event(&"patch_note", {"text": "New recipe: %s" % WeaponDB.get_weapon(f.id).title})
	_fuse_was_ready = false
	var next := BoosterPack.recompute(offer, lo)
	next.fuse = fuse_option()
	if &"fusion" in def.basics:
		BoosterPack.mark_keeps(next, lo)
	offers.append(next)
	panel.after_fuse(next, "%s %d" % [WeaponDB.get_weapon(f.id).title, int(f.rank)])


## S9's `fuse fail` cue (Arsenal depth design 5): the two hand cards seem to fuse into a
## broken card for MISFUSE_SECONDS of game time. An overlay only: the Loadout keeps both cards
## (the active one fires its own shot, each other shot the wrong way, drawn as MISFUSE_SKIN),
## switching is locked and no pack opens. False (logged fuse_fail_skipped) off a pack path,
## with fewer than 2 cards, or while one is live.
func fuse_fail() -> bool:
	var lo := loadout()
	if lo == null or not pack_path() or lo.slots.size() < 2 or _misfuse_left > 0 or _stopped:
		RunState.log_event(&"fuse_fail_skipped", {})
		return false
	_misfuse_left = roundi(MISFUSE_SECONDS * Engine.physics_ticks_per_second)
	_misfuse_before = lo.summary()
	lo.switch_locked = true
	lo.misfuse_skin = MISFUSE_SKIN
	lo.misfuse_shots = 0
	var pair := "%s+%s" % [lo.slots[0].def.id, lo.slots[1].def.id]
	misfuse = {"t": snappedf(RunState.game_time, 0.1), "pair": pair, "restored": false}
	RunState.log_event(&"fuse_fail", {"pair": pair})
	if is_instance_valid(_widget) and _widget.has_method(&"set_misfuse"):
		_widget.call(&"set_misfuse", true)
	return true


## The misfuse is live (tests, the hand).
func misfusing() -> bool:
	return _misfuse_left > 0


## The AI's patch: the overlay goes and the two cards are back (a no-op on the Loadout).
## `noted`: the patch-note line (not on a swap or a clear).
func _end_misfuse(noted: bool) -> void:
	if misfuse.is_empty() or bool(misfuse.get("done", false)):
		return
	_misfuse_left = 0
	var lo := loadout()
	if lo != null:
		lo.switch_locked = false
		lo.misfuse_skin = &""
		misfuse.restored = lo.summary() == _misfuse_before
	misfuse.done = true
	if is_instance_valid(_widget) and _widget.has_method(&"set_misfuse"):
		_widget.call(&"set_misfuse", false)
	if noted:
		RunState.log_event(&"patch_note", {"text": MISFUSE_NOTE})
		RunState.log_event(&"fuse_fail_patched", {"restored": bool(misfuse.restored)})


## M50.1a: the packs dealt so far (0 off a pack path).
func packs() -> int:
	return cards() if pack_path() else 0


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
	if not pack_path():
		_want = 0   # M50.6: a pack path keeps its stack (nothing opens once stopped): bank_packs()
	_swap_tick = -1
	fp.menu_close()
	if panel != null:
		panel.dismiss()
	if is_instance_valid(_gems):
		_gems.queue_free()
	_gems = null
	if _meter != null:
		_meter.set(&"stopped", true)
	if _nerf_left > 0:
		_land_nerf()   # M50.4c1: the session ended inside the window: the note still lands


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
	_pulse()


## M50.4c1: the pulse alone (the nerf's; not a swap, so `wipes` stays the swaps').
func _pulse() -> void:
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
	if pack_path():
		var lo := loadout()
		var k := int(_meter.get(&"kills")) - int(_meter.get(&"cards")) * def.pack_every if _meter != null else 0
		var fused := ",".join(fusions.map(func(f: Dictionary) -> String: return "%s@%d" % [f.id, roundi(float(f.t))]))
		return "path=%s packs=%d stack=%d kills=%d/%d hand=%s fusions=%s picks=%d pickups=%d" % [path_id, cards(),
				pack_stack(), k, def.pack_every, lo.summary() if lo != null else "-", fused if fused != "" else "-", picks,
				pickups_taken]
	if _cards_growth():
		var need := int(_meter.call(&"next_need")) if _meter != null else -1

		return "path=%s cards=%d kills=%d/%s picks=%d pickups=%d" % [path_id, cards(),
				int(_meter.get(&"kills")) if _meter != null else 0, str(need) if need >= 0 else "-", picks,
				pickups_taken]
	var text := "path=%s level=%d picks=%d pickups=%d" % [path_id if path_id != &"" else &"-", level(), picks,
			pickups_taken]
	var lo_i := loadout()
	if lo_i != null and not lo_i.items.is_empty():
		text += " items=%s" % lo_i.items_summary()   # M50.4b
	if not evolutions.is_empty():   # M50.4c1
		text += " evolved=%s" % ",".join(evolutions.map(func(e: Dictionary) -> String: return "%s@%d" % [e.id, roundi(float(e.t))]))
	if not nerf.is_empty():
		text += " nerf=@%s" % (str(roundi(float(nerf.t_landed))) if float(nerf.t_landed) >= 0.0 else "pending")
	return text
