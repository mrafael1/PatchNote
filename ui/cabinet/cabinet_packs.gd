class_name CabinetPacks
extends Control
## M48.6d: the cabinet's pack stage (PLAN 0.9.2 "Packs and cards"; the mockup's S.openAllFlow and
## S.fuseMoment): one press opens EVERY stacked pack. The packs fly from the dock to the view,
## shake and tear together; each is one row of cards. The front row is live (the PickPanel's own
## buttons, keys and focus sit under its cards; the fuse card is its 4th when the hand
## qualifies), the rows behind wait face-down, smaller and dimmed; the pick pops, flies into its
## hand slot and the next row comes forward. Past SHOWN packs the rest read "+N more".
##
## The draw order is today's (PathRunner / BoosterPack, untouched): a pack is drawn from
## pack_rng when it OPENS, for the hand as it is then. So a row behind is a face-down
## placeholder, and its cards are drawn only when the row before it is picked: after a pick this
## stage asks the PathRunner for the next pack (open_pack(), what the open key does and what the
## bot's standing ask does every tick), which opens it on the next physics tick. Between two
## rows the game runs that one tick, exactly as the bot's stack always has; the stage stays up
## across it. If the next pack may not open (a warning, a swap, the session's end), the stage
## closes and the packs stay on the stack.
##
## Reveals (owner, 2026-11-28): no rays, no halo, no banner on a card. Every card flips at the
## same speed (FLIP); a rare gets a gold burst, a ring and sparks, an epic a bigger shard burst,
## a short dither flash and a small shake. The fuse moment: the two hand cards fly up, meet, a
## flash, the fused card slams in with the FUSED! stamp beside it and the keeps / loses note,
## then drops into the hand. Under reduce flashing: fades only (no flash, shake, sparks, flips).
## With the panel's `beats` off (headless: bots, hashes) nothing here takes time.
##
## A child of the host over the view's glass (it also draws the flights to the deck). It reads
## the PickPanel and the PathRunner and writes neither, except that one ask. No RNG (the
## particles spread by a hash of their index), no Tuning, no rules.

const SHOWN := 4          ## rows on screen: the front one and three behind
const ROW_Y := 86         ## the front row's top in the view (art px; the view is 384x216)
const GAP := 7            ## between two cards of a row (art px)
const BACK_FIRST := 24    ## the first row behind sits this much higher (art px)
const BACK_STEP := 14     ## and each one after it this much more
const BACK_K := 2.0 / 3.0 ## and is drawn at this size (2 screen px per art px at the design size)
const FLIP := 0.18        ## one card's flip, the same for every tier
const FLIP_STEP := 0.11   ## the next card starts this much later
const INTRO := 1.8        ## the packs: fly, land, three shakes, the tear, the peek, the deal
const INTRO_REDUCE := 0.3
const ROW_TIME := 0.24    ## a row behind comes forward
const POP := 0.19         ## the pick pops before it flies
const OUTRO := 0.62       ## the pop, then the flight into the hand slot
const OUTRO_REDUCE := 0.25
const FUSE_TIME := 2.6    ## the fuse moment
const FUSE_REDUCE := 1.6
const GAP_MAX := 0.5      ## real seconds the stage waits for the next pack before it closes
const SCRIM := 0.62
const SLOT_FLASH := 0.9   ## a slot's flash and its rising label
const T_FLY := 0.45
const T_SHAKE0 := 0.54
const T_CROUCH := 0.99
const T_TEAR := 1.08
const T_RIP := 1.215
const T_PEEK := 1.275
const T_DEAL := 1.455
const CONFETTI: Array[StringName] = [&"confetti_strip", &"confetti_square", &"confetti_curl"]
const SHARDS: Array[StringName] = [&"foil_shard_a", &"foil_shard_b", &"foil_shard_c", &"confetti_strip", &"confetti_square"]

var frame: Node            ## the CabinetFrame
var panel: PickPanel       ## the live game's pick panel (bind)
var active := false        ## the stage is up (from the press until the last row is picked)
var chaining := false      ## a row was picked and the next pack is asked for
var total := 0             ## the packs stacked when the press landed
var done := 0              ## rows picked since
var specs: Array = []      ## the front row's card faces (CabinetCard specs), choice order
var asks := 0              ## open_pack() calls made (tests)

var _t := 0.0              ## real seconds since the front row opened
var _intro := 0.0          ## the part of it before the cards are dealt
var _packs_intro := false  ## this row opened with the packs' flight (the first one)
var _juiced := {}
var _events := {}
var _gap := 0.0
var _gap_stack := -1
var _out_slot := -1
var _fuse := {}            ## the moment playing: {a, b, id, rank, keeps, loses, hand}
var _fuse_t := -1.0
var _fuse_len := 0.0
var _parts: Array = []     ## particles and one-shot sheets
var _rings: Array = []
var _flights: Array = []
var _flash := {}
var _slot_flashes: Array = []   ## a hand slot's flash as a pick lands: {slot, age, label, ramp}
var _shake_t := -1.0
var _shake_amp := 0.0
var _seed := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# --- The panel's side -----------------------------------------------------------------------------

## The cabinet shows on a live game: the panel hands its packs to this stage.
func live() -> bool:
	return frame != null and is_instance_valid(frame) and bool(frame.get(&"on")) and frame.layout.has("view")


## The frame's refresh: the live game's panel (null between sessions).
func bind(p: PickPanel) -> void:
	if p == panel:
		return
	if panel != null and is_instance_valid(panel):
		if panel.stage == self:
			panel.stage = null
		if panel.picked.is_connected(_on_picked):
			panel.picked.disconnect(_on_picked)
	panel = p
	_reset()
	if panel != null:
		panel.stage = self
		if not panel.picked.is_connected(_on_picked):
			panel.picked.connect(_on_picked)


func _reset() -> void:
	active = false
	chaining = false
	specs = []
	_fuse = {}
	_fuse_t = -1.0
	_parts.clear()
	_rings.clear()
	_flights.clear()
	_slot_flashes.clear()
	_flash = {}
	_shake_t = -1.0
	queue_redraw()


func _runner() -> Node:
	return panel.runner if panel != null and is_instance_valid(panel) and is_instance_valid(panel.runner) else null


func _stack() -> int:
	var r := _runner()
	return int(r.call(&"pack_stack")) if r != null and r.has_method(&"pack_stack") else 0


func _reduce() -> bool:
	return SaveGame.reduce_flashing()


func _beats() -> bool:
	return panel != null and panel.beats


## A pack opens on the panel (before its buttons are built): the intro's length in real
## seconds. The first pack of a press flies the packs out; a later one only comes forward.
func opening(_p: PickPanel) -> float:
	_packs_intro = not active
	if not active:
		active = true
		total = maxi(1, _stack())
		done = 0
	chaining = false
	_t = 0.0
	_juiced = {}
	_events = {}
	_out_slot = -1
	_intro = intro_time(_packs_intro)
	queue_redraw()
	return _intro


func intro_time(packs: bool) -> float:
	if not _beats():
		return 0.0
	if _reduce():
		return INTRO_REDUCE if packs else INTRO_REDUCE * 0.5
	return INTRO if packs else ROW_TIME


## The panel built the row's buttons. `fresh`: a new deal (a pack opened, or the same pack back
## after a fuse), not a return from the replace step.
func dealt(p: PickPanel, fresh: bool) -> void:
	specs = []
	var o := p.offer
	if o == null:
		return
	var hints := Settings.key_hints()
	var full := o.max_slots > 0 and o.hand.size() >= o.max_slots
	for i in o.cards.size():
		var c: Dictionary = o.cards[i]
		specs.append(CabinetCard.spec_of(c, key_label(i) if hints else "", full and c.get("kind") == &"new"))
	if p.has_fuse():
		specs.append(CabinetCard.fuse_spec(o.fuse, key_label(o.cards.size()) if hints else ""))
	if fresh and _t > _intro:   # the same pack again after a fuse: its cards turn over once more
		_t = 0.0
		_intro = 0.0
		_packs_intro = false
		_juiced = {}
	queue_redraw()


## This row opened with the packs' flight (the first of a press), not by coming forward.
func packs_intro() -> bool:
	return _packs_intro


## Choice i's key as one glyph for the key cap ("1"; the layout's own label).
static func key_label(i: int) -> String:
	return InputSetup.expand_keys("{key:choose_%d}" % (i + 1)).left(1).to_upper()


## Real seconds until every card of an n-card row is face-up.
static func deal_time(n: int) -> float:
	return maxi(n - 1, 0) * FLIP_STEP + FLIP


## A card's flip takes this long, whatever its tier (owner: a rare or an epic flips as fast as
## a common one).
static func flip_time(_tier: StringName) -> float:
	return FLIP


func outro_time() -> float:
	return OUTRO_REDUCE if _reduce() else OUTRO


## The pick's flight begins (the panel's outro): where it will land.
func picking(p: PickPanel, i: int) -> void:
	_out_slot = slot_for(p.offer, i)
	if _reduce() or i < 0 or i >= specs.size():
		return
	var r := card_rect(i, specs.size())
	var tier: StringName = specs[i].get("tier", &"common")
	var ramp := ArcadePaint.tier_ramp(tier)
	ring(r.get_center(), 60, 0.36, ramp, 14)
	puff(r.position + Vector2(5, 5) * _a(), &"spark", ramp, 16)
	puff(r.end - Vector2(5, 15) * _a(), &"spark", &"white", 16)


## The hand slot card i of `o` goes to: the held card it ranks up (or the fusion it feeds), the
## slot it replaces, the parent it absorbs, else the next free one.
static func slot_for(o: PickOffer, i: int) -> int:
	if o == null or i < 0 or i >= o.cards.size():
		return 0
	var c: Dictionary = o.cards[i]
	if c.has("replace"):
		return int(c.replace)
	var ids: Array = [c.get("id", &"")]
	ids.append_array(c.get("absorbs", []))
	var w := WeaponDB.get_weapon(c.get("id", &""))
	for k in o.hand.size():
		var held: StringName = o.hand[k].get("id", &"")
		if held in ids:
			return k
		var hw := WeaponDB.get_weapon(held)
		if hw != null and hw.is_fusion() and w != null and w.id in hw.parents:
			return k
	return mini(o.hand.size(), maxi(0, o.max_slots - 1))


func fuse_time() -> float:
	return FUSE_REDUCE if _reduce() else FUSE_TIME


## The fuse was made: the moment plays for `length` real seconds. `f`: the FUSE choice
## (BoosterPack.fuse_option), `hand` the hand before it ([{id, title, rank}]).
func fusing(f: Dictionary, hand: Array, length: float) -> void:
	_fuse = f.duplicate()
	_fuse["hand"] = hand.duplicate(true)
	_fuse_t = 0.0
	_fuse_len = maxf(0.01, length)
	_events = {}
	queue_redraw()


## The fuse moment is playing.
func in_fuse() -> bool:
	return _fuse_t >= 0.0


## The dock shows no hand: the two cards are up in the view (the fuse moment, until the fused
## card drops back).
func hand_hidden() -> bool:
	return in_fuse() and _beats()


## The panel is gone for good (the session ended).
func closed() -> void:
	_reset()


func _on_picked(o: PickOffer, index: int) -> void:
	if not active:
		return
	if o != null and index >= 0 and index < o.cards.size():
		var c: Dictionary = o.cards[index]
		var slot := slot_for(o, index)
		if _out_slot < 0 and _beats() and not _reduce():   # picked through the replace step: no flight yet
			fly(ArcadePaint.mini_tex(c.get("id", &""), CabinetCard.tier_of(c)), _view().get_center(), _slot_point(slot), 0.3, 12.0)
		slot_flash(slot, land_label(c), ArcadePaint.tier_ramp(CabinetCard.tier_of(c)))
	_out_slot = -1
	done += 1
	specs = []
	chaining = true
	_gap = 0.0
	_gap_stack = -1
	queue_redraw()


## What a landed card says over its slot: "RANK 3 > 4", or "NEW · RANK 1".
static func land_label(c: Dictionary) -> String:
	if c.get("kind") == &"upgrade":
		return "RANK %d > %d" % [int(c.get("from", 0)), int(c.get("rank", 1))]
	return "NEW · RANK %d" % int(c.get("rank", 1))


## A hand slot flashes as a card lands in it (a dither flash, a ring, two sparks and the label
## rising; the label alone, fading, under reduce flashing). Nothing headless.
func slot_flash(slot: int, label: String, ramp: StringName) -> void:
	if not _beats() or _dock() == null:
		return
	_slot_flashes.append({"slot": slot, "age": 0.0, "label": label, "ramp": ramp})
	var at := _slot_point(slot)
	ring(at, 32, 0.4, ramp, 6)
	puff(at - Vector2(14, 8) * _a(), &"spark", ramp, 14)
	puff(at + Vector2(14, -4) * _a(), &"spark", &"white", 14, 0.08)


## A 1-card pack applied by itself (the panel's toast): its card goes straight to the hand.
func toasted(o: PickOffer) -> void:
	if not live() or o == null or o.cards.is_empty() or not _beats() or _reduce():
		return
	var c: Dictionary = o.cards[0]
	var from := _view().get_center() if active else _dock_pack()
	fly(ArcadePaint.mini_tex(c.get("id", &""), CabinetCard.tier_of(c)), from, _slot_point(slot_for(o, 0)), 0.43, 20.0)
	slot_flash(slot_for(o, 0), land_label(c), ArcadePaint.tier_ramp(CabinetCard.tier_of(c)))
	if active:
		done += 1


# --- The clock ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if panel != null and not is_instance_valid(panel):
		panel = null
		_reset()
	if panel == null:
		return
	if RunState.is_paused_for(RunState.MENU):
		return
	var dt := delta / maxf(Engine.time_scale, 0.001)
	if not live():
		if active:
			_reset()
		return
	_step_fx(dt)
	if in_fuse():
		_step_fuse(dt)
	if active:
		_t += dt
		_step_row()
		if chaining and not panel.is_open():
			_ask(dt)
		queue_redraw()
	elif fx_live():
		queue_redraw()
	elif _fx_was:   # the last fx just ended: one more draw clears it
		_fx_was = false
		queue_redraw()
	if fx_live():
		_fx_was = true


var _fx_was := false


## Something of the stage's fx is still on screen.
func fx_live() -> bool:
	return not (_parts.is_empty() and _rings.is_empty() and _flights.is_empty() and _flash.is_empty() and _slot_flashes.is_empty())


## After a pick: the next pack is asked for (the PathRunner opens it on its next physics tick,
## as for the open key). No pack left, or none may open now: the stage closes.
func _ask(dt: float) -> void:
	var left := _stack()
	if left <= 0:
		_end()
		return
	if left != _gap_stack:   # a 1-card pack applied by itself: the wait starts again
		_gap_stack = left
		_gap = 0.0
	_gap += dt
	var r := _runner()
	if r == null or _gap > GAP_MAX:
		_end()
		return
	asks += 1
	r.call(&"open_pack")


func _end() -> void:
	active = false
	chaining = false
	specs = []
	queue_redraw()


## The row's timed events: the tear's burst, each rare's and epic's juice when its flip ends.
func _step_row() -> void:
	if not _beats() or panel == null or not front():
		return
	var reduce := _reduce()
	if _packs_intro and not reduce and _t >= T_RIP and not _events.has("rip"):
		_events["rip"] = true
		flash(ArcadePaint.SLIP, [8, 4, 2, 1], 0.05)
		shake(1.0)
		for b in packs_shown():
			var mouth := pack_spot(b, packs_shown()) + Vector2(15, 8) * _a()
			burst(mouth, [&"fuse", &"white"], 12, 120.0, SHARDS)
			puff(mouth, &"smoke_puff", &"smoke", 16)
			ring(mouth, 24, 0.3, &"white", 5)
	if _t < _intro or reduce:
		return
	var td := _t - _intro
	for i in specs.size():
		if _juiced.has(i) or td < i * FLIP_STEP + FLIP:
			continue
		_juiced[i] = true
		var tier: StringName = specs[i].get("tier", &"common")
		var r := card_rect(i, specs.size())
		if tier == &"rare":
			juice_rare(r)
		elif tier == &"epic":
			juice_epic(r)
		elif tier == &"fuse":
			burst(r.get_center(), [&"fuse", &"white"], 18, 130.0, CONFETTI)
			ring(r.get_center(), 44, 0.36, &"fuse", 8)
		else:
			puff(Vector2(r.get_center().x, r.position.y + 10 * _a()), &"spark", &"white", 18)


## A rare card turned over: a gold burst, a ring, four sparks. No ray, no banner.
func juice_rare(r: Rect2) -> void:
	var a := _a()
	var at := Vector2(r.get_center().x, r.position.y + r.size.y / 3.0)
	burst(at, [&"gold", &"gold", &"white"], 18, 140.0, CONFETTI)
	ring(at, 44, 0.4, &"gold", 8)
	puff(r.position + Vector2(4, 5) * a, &"spark", &"gold", 12)
	puff(Vector2(r.end.x - 4 * a, r.position.y + 20 * a), &"spark", &"white", 12, 0.11)
	puff(Vector2(r.position.x + 8 * a, r.end.y - 12 * a), &"spark", &"gold", 12, 0.22)
	puff(Vector2(r.end.x - 6 * a, r.end.y - 30 * a), &"spark", &"gold", 12, 0.33)


## An epic card turned over: a bigger shard burst, two rings, a short dither flash, a small shake.
func juice_epic(r: Rect2) -> void:
	var a := _a()
	var at := r.get_center()
	flash(ArcadePaint.EPIC_FLASH, [8, 4, 1], 0.05)
	shake(1.0)
	burst(at, [&"epic", &"mint", &"cool", &"white", &"fuse"], 30, 220.0, SHARDS)
	ring(at, 72, 0.4, &"epic", 12)
	ring(at, 52, 0.36, &"mint", 8, 0.09)
	puff(r.position + Vector2(4, 5) * a, &"spark", &"mint", 12)
	puff(Vector2(r.end.x - 4 * a, r.position.y + 20 * a), &"spark", &"epic", 12)
	puff(Vector2(r.position.x + 8 * a, r.end.y - 12 * a), &"spark", &"white", 12, 0.12)
	puff(Vector2(r.end.x - 6 * a, r.end.y - 30 * a), &"spark", &"mint", 12, 0.12)


func _step_fuse(dt: float) -> void:
	_fuse_t += dt
	queue_redraw()
	var k := _fuse_t / _fuse_len
	if _beats() and not _reduce():
		var c := (fuse_layout().card as Rect2).get_center()
		if k >= 0.42 and not _events.has("hit"):   # the two cards meet
			_events["hit"] = true
			flash(ArcadePaint.SLIP, [16, 16, 12, 10, 8, 6, 4, 2, 1], 0.055)
			shake(2.0)
			burst(c, [&"fuse", &"epic", &"mint", &"white", &"gold"], 48, 340.0, SHARDS)
			burst(c - Vector2(0, 14) * _a(), [&"fuse", &"gold", &"cool"], 26, 210.0, CONFETTI)
			ring(c, 110, 0.55, &"fuse", 12)
			ring(c, 86, 0.5, &"gold", 10, 0.09)
			ring(c, 64, 0.45, &"white", 8, 0.18)
		if k >= 0.54 and not _events.has("slam"):   # the fused card lands
			_events["slam"] = true
			shake(1.0)
			ring(c, 80, 0.4, &"epic", 40)
			burst(c + Vector2(0, 46) * _a(), [&"epic", &"mint", &"white"], 20, 220.0, CONFETTI)
		if k >= 0.84 and not _events.has("home"):   # it drops into the hand
			_events["home"] = true
			fly(ArcadePaint.mini_tex(_fuse.get("id", &""), &"fuse"), c, _slot_point(0), (1.0 - 0.84) * _fuse_len, 20.0)
	if _fuse_t >= _fuse_len:
		slot_flash(0, "FUSED · RANK %d" % int(_fuse.get("rank", 0)), &"fuse")
		_fuse_t = -1.0
		_fuse = {}


# --- Layout (window px) ---------------------------------------------------------------------------

func _a() -> float:
	return float(frame.call(&"art"))


func _view() -> Rect2:
	return frame.layout.view


## A view point in art px, as window px.
func _vp(x: float, y: float) -> Vector2:
	return _view().position + Vector2(x, y) * _a()


## The front row is on screen (a pack's own step; not the replace step, the give step or the
## fuse moment).
func front() -> bool:
	return active and panel != null and panel.is_open() and panel.staged() and panel.replacing() < 0 \
			and not panel.fusing() and not specs.is_empty()


## The stage draws now (its scrim is up).
func showing() -> bool:
	if not active or panel == null:
		return false
	if panel.is_open() and (not panel.staged() or panel.replacing() >= 0):
		return false
	return true


## Packs waiting behind the front row.
func behind() -> int:
	return maxi(0, _stack() - (1 if panel != null and panel.is_open() and panel.staged() else 0))


## Rows drawn behind the front one, and the packs past them ("+N more").
func behind_shown() -> int:
	return mini(behind(), SHOWN - 1)


func more() -> int:
	return behind() - behind_shown()


func more_text() -> String:
	var n := more()
	return "+%d more pack%s waiting" % [n, "" if n == 1 else "s"] if n > 0 else ""


## The header's two lines.
func header() -> Array[String]:
	var all := maxi(total, done + behind() + (1 if front() else 0))
	var title := "%d PACKS · PICK 1 FROM EACH" % all if all > 1 else "PACK · PICK 1"
	return [title, "game paused · pack %d of %d" % [mini(done + 1, all), all]]


## The focused card's full line ("Shotgun 4 -> 5: one-shots shooters ..."), "" with no focus.
func focus_detail() -> String:
	var focus := panel.focused_choice() if panel != null else -1
	return String(specs[focus].get("detail", "")) if focus >= 0 and focus < specs.size() else ""


## The footer's line: the row's keys on the player's layout, then what a pick does.
func footer() -> String:
	var what := "pick from the front row · it drops into your hand"
	if not Settings.key_hints() or specs.is_empty():
		return what
	var keys := PackedStringArray()
	for i in specs.size():
		keys.append(key_label(i) + (" fuse" if bool(specs[i].get("fuse", false)) else ""))
	return "%s   %s" % ["  ".join(keys), what]


## Card i of an n-card front row.
func card_rect(i: int, n: int) -> Rect2:
	var w := n * CabinetCard.W + (n - 1) * GAP
	return Rect2(_vp((384 - w) * 0.5 + i * (CabinetCard.W + GAP), ROW_Y), Vector2(CabinetCard.W, CabinetCard.H) * _a())


## Card i of the three face-down cards of the row `depth` rows behind (1..).
func back_rect(i: int, depth: float) -> Rect2:
	var k := lerpf(1.0, BACK_K, clampf(depth, 0.0, 1.0))
	var cw := CabinetCard.W * k
	var w := 3 * cw + 2 * GAP * k
	var up := BACK_FIRST * clampf(depth, 0.0, 1.0) + BACK_STEP * maxf(0.0, depth - 1.0)
	return Rect2(_vp((384 - w) * 0.5 + i * (cw + GAP * k), ROW_Y - up), Vector2(cw, CabinetCard.H * k) * _a())


## The front row's cards in the game view's own coordinates (the panel's buttons go there).
func hit_rects(n: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var v := _view()
	var k := 1280.0 / maxf(1.0, v.size.x)
	for i in n:
		var r := card_rect(i, n)
		out.append(Rect2((r.position - v.position) * k, r.size * k))
	return out


func packs_shown() -> int:
	return mini(maxi(total, 1), SHOWN)


## Where pack b of n lands in the view (its top-left).
func pack_spot(b: int, n: int) -> Vector2:
	var gap := minf(54.0, 320.0 / maxf(1.0, n - 1.0)) if n > 1 else 0.0
	return _vp(192.0 - ((n - 1) * gap + 30.0) * 0.5 + b * gap, 40.0)


func _dock() -> Node:
	var d: Variant = frame.get(&"dock")
	return d if d != null and is_instance_valid(d) else null


func _dock_pack() -> Vector2:
	var d := _dock()
	if d != null:
		return (d.call(&"pack_rect") as Rect2).get_center()
	return _view().position + Vector2(_view().size.x * 0.75, _view().size.y)


func _slot_point(i: int) -> Vector2:
	var d := _dock()
	if d != null:
		return (d.call(&"slot_rect", i) as Rect2).get_center()
	return _view().position + Vector2(_view().size.x * 0.5, _view().size.y)


## What the stage shows now, for tests and captures: the front row first ({front, live, cards:
## its specs, rects}), then each row behind ({front: false, live: false, depth, rects}).
func rows() -> Array:
	var out := []
	if not showing():
		return out
	if front():
		var rects: Array[Rect2] = []
		for i in specs.size():
			rects.append(card_rect(i, specs.size()))
		out.append({"front": true, "live": panel.can_choose(), "cards": specs, "rects": rects})
	for d in behind_shown():
		var rects2: Array[Rect2] = []
		for i in 3:
			rects2.append(back_rect(i, d + 1.0))
		out.append({"front": false, "live": false, "depth": d + 1, "cards": [], "rects": rects2})
	return out


# --- Fx (window px; no RNG: a hash of the spawn's index spreads them) -----------------------------

func _sr(x: float, y: float) -> float:
	var v := sin(x * 12.9898 + y * 78.233) * 43758.5453
	return v - floorf(v)


## n tumbling bits thrown out of `at` in the given fx ramps.
func burst(at: Vector2, ramps: Array, n: int, speed: float, sheets: Array[StringName]) -> void:
	if _reduce():
		return
	var a := _a()
	for i in n:
		_seed += 1
		var ang := _sr(_seed, 1.0) * TAU
		var d := speed / 3.0 * (0.5 + _sr(_seed, 2.0) * 0.9) * a
		var sheet: StringName = sheets[i % sheets.size()]
		_parts.append({"p": at, "v": Vector2(cos(ang) * d * 1.7, sin(ang) * d * 1.7 - 24.0 * a), "g": 110.0 * a, "sheet": sheet,
				"ramp": &"foil" if String(sheet).begins_with("foil") else ramps[i % ramps.size()],
				"f": int(_sr(_seed, 3.0) * 4.0), "life": 0.7 + _sr(_seed, 4.0) * 0.5, "age": 0.0, "fps": 10.0, "once": false,
				"wait": 0.0})


## One fx sheet played once at `at` (its centre), after `wait` seconds.
func puff(at: Vector2, sheet: StringName, ramp: StringName, fps := 14.0, wait := 0.0) -> void:
	if _reduce():
		return
	_parts.append({"p": at, "v": Vector2.ZERO, "g": 0.0, "sheet": sheet, "ramp": ramp, "f": 0,
			"life": ArcadePaint.fx_frames(sheet) / fps, "age": 0.0, "fps": fps, "once": true, "wait": wait})


## An expanding pixel ring (radius r0 to r1 art px) that breaks into a dither as it ends.
func ring(at: Vector2, r1: int, dur: float, ramp: StringName, r0 := 4, wait := 0.0) -> void:
	if _reduce():
		return
	_rings.append({"p": at, "r0": r0, "r1": r1, "dur": dur, "ramp": ramp, "age": -wait})


## A dithered flash over the view: `levels` of 16, one every `step` seconds.
func flash(col: String, levels: Array, step: float) -> void:
	if _reduce():
		return
	_flash = {"col": col, "levels": levels, "step": step, "age": 0.0}


## A small shake of the rows (art px), a quarter second.
func shake(amp: float) -> void:
	if _reduce():
		return
	_shake_t = 0.0
	_shake_amp = amp


## A sprite flying from `from` to `to` (its centre) in `dur` seconds over an arc.
func fly(tex: Texture2D, from: Vector2, to: Vector2, dur: float, arc := 0.0, wait := 0.0) -> void:
	_flights.append({"tex": tex, "from": from, "to": to, "dur": maxf(0.01, dur), "arc": arc, "age": -wait})


func _step_fx(dt: float) -> void:
	for i in range(_parts.size() - 1, -1, -1):
		var p: Dictionary = _parts[i]
		if float(p.wait) > 0.0:
			p.wait = float(p.wait) - dt
			continue
		p.age = float(p.age) + dt
		if float(p.age) >= float(p.life):
			_parts.remove_at(i)
			continue
		var v: Vector2 = p.v
		v.y += float(p.g) * dt
		v.x *= 0.985
		p.v = v
		p.p = (p.p as Vector2) + v * dt
	for i in range(_rings.size() - 1, -1, -1):
		_rings[i].age = float(_rings[i].age) + dt
		if float(_rings[i].age) >= float(_rings[i].dur):
			_rings.remove_at(i)
	for i in range(_flights.size() - 1, -1, -1):
		_flights[i].age = float(_flights[i].age) + dt
		if float(_flights[i].age) >= float(_flights[i].dur):
			_flights.remove_at(i)
	if not _flash.is_empty():
		_flash.age = float(_flash.age) + dt
		if float(_flash.age) >= (_flash.levels as Array).size() * float(_flash.step):
			_flash = {}
	for i in range(_slot_flashes.size() - 1, -1, -1):
		_slot_flashes[i].age = float(_slot_flashes[i].age) + dt
		if float(_slot_flashes[i].age) >= SLOT_FLASH:
			_slot_flashes.remove_at(i)
	if _shake_t >= 0.0:
		_shake_t += dt
		if _shake_t > 0.25:
			_shake_t = -1.0


func _shake_offset() -> Vector2:
	if _shake_t < 0.0:
		return Vector2.ZERO
	var seq: Array[Vector2] = [Vector2(-1, 0), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 0), Vector2.ZERO]
	return seq[mini(int(_shake_t / 0.05), seq.size() - 1)] * _shake_amp * _a()


func _snap(p: Vector2) -> Vector2:
	var a := _a()
	return (p / a).floor() * a


static func _steps(k: float, n: int) -> float:
	return floorf(clampf(k, 0.0, 1.0) * n) / n


# --- Drawing --------------------------------------------------------------------------------------

func _draw() -> void:
	if not live():
		return
	if showing():
		_draw_stage()
	_draw_fx()


func _draw_stage() -> void:
	var a := _a()
	var s: float = frame.s()
	var v := _view()
	draw_rect(v, Color(CabinetArt.c(&"night"), SCRIM))
	if in_fuse():
		_draw_fuse()
		return
	var reduce := _reduce()
	var off := _shake_offset()
	# The header: how many packs, which one is up.
	var head := header()
	var big := CabinetLayout.text_px(3, s)
	var small := CabinetLayout.text_px(2, s)
	var hy := v.position.y + 5 * a
	RailFrame.text(self, Vector2(v.position.x + a, hy + a), head[0], big, CabinetArt.c(&"ink"), true, HORIZONTAL_ALIGNMENT_CENTER, v.size.x)
	RailFrame.text(self, Vector2(v.position.x, hy), head[0], big, CabinetArt.c(&"slip"), true, HORIZONTAL_ALIGNMENT_CENTER, v.size.x)
	RailFrame.text(self, Vector2(v.position.x, hy + 13 * a), head[1], small, CabinetArt.c(&"metal"), false, HORIZONTAL_ALIGNMENT_CENTER, v.size.x)
	var mt := more_text()
	if mt != "":
		var mw := ceili(RailFrame.text_w(mt, small) / a) + 6
		var mr := Rect2(Vector2(v.end.x - (mw + 7) * a, v.position.y + 32 * a), Vector2(mw, 9) * a)
		CabinetArt.draw9_rect(self, &"cap_ink", mr, a)
		RailFrame.text(self, Vector2(mr.position.x, roundf(mr.position.y + (mr.size.y - UiTheme.pixel_font().get_height(small)) * 0.5)), mt, small,
				CabinetArt.c(&"gold"), false, HORIZONTAL_ALIGNMENT_CENTER, mr.size.x)
	var has_front := front()
	var beats := _beats()
	# A row coming forward: the rows behind slide one step with it.
	var come := 0.0
	if has_front and beats and not _packs_intro and _t < _intro and not reduce:
		come = 1.0 - _steps(_t / _intro, 3)
	var hide_rows := has_front and beats and _packs_intro and _t < (T_DEAL if not reduce else _intro)
	# The rows behind, the deepest first: face-down, smaller, dimmed.
	if not hide_rows:
		for d in range(behind_shown(), 0, -1):
			var depth := d + come
			for i in 3:
				var r := back_rect(i, depth)
				CabinetCard.draw(self, {}, r.position + off, a, s, {"back": true, "cell": r.size.x / CabinetCard.W,
						"shade": clampf(0.25 + 0.15 * depth, 0.0, 0.75), "still": true})
	if has_front:
		_draw_front(off, come)
		if beats and _packs_intro and _t < _intro:
			_draw_packs()
	# The footer: the focused card's full line (the card itself says the short form), then the keys.
	if has_front and _t >= _intro:
		var width := v.size.x - 16 * a
		var x := v.position.x + 8 * a
		var fy := v.position.y + (ROW_Y + CabinetCard.H + 3) * a
		var detail := focus_detail()
		if detail != "":
			var ds := RailFrame.fit(detail, small, width, false, 11)
			RailFrame.text(self, Vector2(x + a, fy + a), detail, ds, CabinetArt.c(&"ink"), false, HORIZONTAL_ALIGNMENT_CENTER, width)
			RailFrame.text(self, Vector2(x, fy), detail, ds, CabinetArt.c(&"slip"), false, HORIZONTAL_ALIGNMENT_CENTER, width)
		var keys := footer()
		RailFrame.text(self, Vector2(x, fy + 9 * a), keys, RailFrame.fit(keys, small, width, false, 11),
				CabinetArt.c(&"metal"), false, HORIZONTAL_ALIGNMENT_CENTER, width)


## The front row: dealt face-down, each card flipping in turn at the same speed; the focused
## one lifts; after the pick it pops and flies while the others tumble away.
func _draw_front(off: Vector2, come: float) -> void:
	var a := _a()
	var s: float = frame.s()
	var n := specs.size()
	var reduce := _reduce()
	var beats := _beats()
	var focus := panel.focused_choice()
	var out: Array = panel.outro_progress()
	var out_i := int(out[0])
	var out_t := float(out[1]) * outro_time()
	var td := _t - _intro
	for i in n:
		var r := card_rect(i, n)
		var at := r.position + off
		var o := {"still": reduce}
		if not beats:
			pass   # headless: face-up at once
		elif _t < _intro:
			if reduce:
				o["alpha"] = clampf(_t / _intro, 0.0, 1.0)
			elif _packs_intro:
				# The small card-backs shoot out of the packs; the real back pops in when one lands.
				if _t < T_DEAL + i * 0.045 + 0.24:
					continue
				o["back"] = true
				at.y += [5.0, -2.0, 0.0][mini(2, int((_t - T_DEAL - i * 0.045 - 0.24) / 0.05))] * a
			else:
				var from := back_rect(mini(i, 2), 1.0)
				at = from.position.lerp(r.position, 1.0 - come) + off
				o["back"] = true
				o["cell"] = lerpf(a, from.size.x / CabinetCard.W, come)
				o["shade"] = 0.4 * come
		elif reduce:
			o["alpha"] = clampf(td / 0.2, 0.0, 1.0)
		else:
			var p := clampf((td - i * FLIP_STEP) / FLIP, 0.0, 1.0)
			var e := _steps(p, 3) if p < 1.0 else 1.0
			o["sx"] = maxf(0.04, absf(cos(e * PI)))
			o["back"] = e < 0.5
			if p > 0.0 and p < 1.0:
				at.y -= 3.0 * a
		if out_i >= 0:   # the pick: it pops, then flies; the others tumble away
			if reduce:
				o["alpha"] = 1.0 - float(out[1])
			elif i == out_i:
				if out_t >= POP:
					continue
				at.y += [-12.0, -8.0, -9.0][mini(2, int(out_t / (POP / 3.0)))] * a
			else:
				var e2 := _steps(out_t / 0.4, 7)
				at += Vector2((-8.0 if i < out_i else 8.0) * e2, 90.0 * e2 * e2 - 5.0 * minf(1.0, e2 * 5.0)) * a
				o["alpha"] = 1.0 - e2
		elif i == focus and panel.can_choose():
			at.y -= 5.0 * a
		CabinetCard.draw(self, specs[i], _snap(at), a, s, o)
	if out_i >= 0 and not reduce and out_t >= POP and out_i < n:
		var from2 := card_rect(out_i, n).get_center() - Vector2(0, 9) * a
		var to := _slot_point(_out_slot)
		var k := _steps((out_t - POP) / (OUTRO - POP), 10)
		var mid := (from2 + to) * 0.5 - Vector2(0, 20.0 * a)
		var pos := from2.lerp(mid, k).lerp(mid.lerp(to, k), k)
		var tex := ArcadePaint.mini_tex(specs[out_i].get("id", &""), specs[out_i].get("tier", &"common"))
		draw_texture_rect(tex, Rect2(_snap(pos - Vector2(ArcadePaint.MINI_W, ArcadePaint.MINI_H) * a * 0.5),
				Vector2(ArcadePaint.MINI_W, ArcadePaint.MINI_H) * a), false)


## The packs' flight: out of the dock, three shakes, the tear, the cards peeking, the deal.
func _draw_packs() -> void:
	var a := _a()
	var n := packs_shown()
	var size := Vector2(30, 42) * a
	if _reduce():
		var k := _t / _intro
		var alpha := clampf(k * 2.0, 0.0, 1.0) if k < 0.5 else clampf(2.0 - k * 2.0, 0.0, 1.0)
		for b in n:
			var at := pack_spot(b, n)
			draw_texture_rect(ArcadePaint.pack_tex(&"peek", 4), Rect2(at - Vector2(0, 19) * a, Vector2(30, 61) * a), false,
					Color(1, 1, 1, alpha))
		return
	var from := _dock_pack() - size * 0.5
	for b in n:
		var spot := pack_spot(b, n)
		var at := spot
		if _t < T_FLY + b * 0.03:
			var k2 := _steps((_t - b * 0.03) / T_FLY, 9)
			var mid := _vp(177.0 + (b - (n - 1) * 0.5) * 3.0, 4.0)
			at = from.lerp(mid, k2).lerp(mid.lerp(spot, k2), k2)
			draw_texture_rect(ArcadePaint.pack_tex(&"full"), Rect2(_snap(at), size), false)
			continue
		if _t < T_SHAKE0:   # the landing's squash
			at.y += [3.0, -2.0, 0.0][mini(2, int((_t - T_FLY) / 0.03))] * a
		elif _t < T_CROUCH:
			var sh := int((_t - T_SHAKE0) / 0.15)
			var amp := (sh + 1.0) * a
			var step := int(fmod(_t - T_SHAKE0, 0.15) / 0.03)
			at += [Vector2.ZERO, Vector2(-amp, 0), Vector2(amp, -a), Vector2(-amp, a), Vector2(amp, 0)][mini(step, 4)]
		elif _t < T_TEAR:
			at.y += 2.0 * a
		if _t < T_TEAR:
			draw_texture_rect(ArcadePaint.pack_tex(&"full"), Rect2(_snap(at), size), false)
		elif _t < T_RIP:
			draw_texture_rect(ArcadePaint.pack_tex(&"tear", int((_t - T_TEAR) / 0.045)),
					Rect2(_snap(at - Vector2(0, 3) * a), Vector2(30, 45) * a), false)
		else:
			# Open: the strip flings away, the cards peek, then the empty pack drops out.
			var drop := 0.0
			var alpha2 := 1.0
			if _t >= T_DEAL + 0.1:
				var e := _steps((_t - T_DEAL - 0.1) / 0.24, 6)
				drop = 50.0 * e * e * a
				alpha2 = 1.0 - e
			if _t < T_PEEK:
				draw_texture_rect(ArcadePaint.pack_tex(&"open"), Rect2(_snap(at + Vector2(0, 7) * a), Vector2(30, 35) * a), false)
			else:
				var pf := mini(4, int((_t - T_PEEK) / 0.036))
				draw_texture_rect(ArcadePaint.pack_tex(&"peek", pf), Rect2(_snap(at + Vector2(0, drop - 19 * a)), Vector2(30, 61) * a),
						false, Color(1, 1, 1, alpha2))
			var sk := (_t - T_RIP) / 0.42
			if sk < 1.0:
				var e3 := _steps(sk, 7)
				var sp := Vector2(36.0 * e3, -36.0 * sin(e3 * PI) + 14.0 * e3) * a
				draw_texture_rect(ArcadePaint.pack_tex(&"strip"), Rect2(_snap(at + sp), Vector2(30, 8) * a), false,
						Color(1, 1, 1, 1.0 - maxf(0.0, e3 - 0.7) / 0.3))
			# The front row's cards shoot out of the first pack as small card-backs.
			if b == 0 and _t >= T_DEAL:
				for i in specs.size():
					var fk := (_t - T_DEAL - i * 0.045) / 0.24
					if fk < 0.0 or fk >= 1.0:
						continue
					var e4 := _steps(fk, 8)
					var src := at + Vector2(15, -6) * a
					var dst := card_rect(i, specs.size()).get_center()
					var m2 := (src + dst) * 0.5 - Vector2(0, 30) * a
					var pos := src.lerp(m2, e4).lerp(m2.lerp(dst, e4), e4)
					draw_texture_rect(ArcadePaint.mini_back_tex(), Rect2(_snap(pos - Vector2(11, 13) * a), Vector2(22, 26) * a), false)
	if _t >= T_TEAR and _t < T_DEAL:   # the rip word, under the packs (gone before a card is dealt)
		var rip := ArcadePaint.fx_tex(&"rip_word", int(_t * 8.0) % 2, &"gold")
		var rs := Vector2(34, 12) * a * 2.0
		draw_texture_rect(rip, Rect2(_snap(Vector2(_view().get_center().x - rs.x * 0.5, _view().position.y + 92 * a)), rs), false)


## The fuse moment: the two hand cards up in the view, meeting; the flash; the fused card with
## the FUSED! stamp over it and the keeps / loses note beside it; then down into the hand.
func _draw_fuse() -> void:
	var a := _a()
	var s: float = frame.s()
	var v := _view()
	var k := clampf(_fuse_t / _fuse_len, 0.0, 1.0)
	var reduce := _reduce() or not _beats()
	var lay := fuse_layout()
	var centre: Vector2 = (lay.card as Rect2).position
	var apart := minf(82.0 * a, centre.x - v.position.x - 4 * a)   # the two parents stay inside the view
	var hand: Array = _fuse.get("hand", [])
	var show_result := k >= (0.35 if reduce else 0.54)
	if not show_result:
		for i in mini(2, hand.size()):
			var side := -1.0 if i == 0 else 1.0
			var at := centre + Vector2(side * apart, 0)
			var o := {"still": reduce}
			if reduce:
				o["alpha"] = clampf(k / 0.12, 0.0, 1.0) * clampf((0.35 - k) / 0.08, 0.0, 1.0)
			elif k < 0.19:   # up from the hand
				var e := _steps(k / 0.19, 8)
				at.y += (1.0 - e) * 80.0 * a
				o["alpha"] = minf(1.0, e * 2.0)
			elif k >= 0.27:   # a wind-up apart, then together
				var e2 := clampf((k - 0.27) / 0.15, 0.0, 1.0)
				var pull := -0.12 * sin(minf(1.0, e2 * 3.0) * PI) + _steps(e2 * e2, 8)
				at.x -= side * apart * clampf(pull, -0.2, 0.86)
			if not reduce and k >= 0.42:
				continue
			CabinetCard.draw(self, CabinetCard.hand_spec(hand[i]), _snap(at), a, s, o)
		return
	var spec := CabinetCard.fused_spec(_fuse.get("id", &""), int(_fuse.get("rank", 0)))
	var at2 := centre
	var o2 := {"still": reduce}
	var home := 0.84
	if reduce:
		o2["alpha"] = clampf((k - 0.35) / 0.12, 0.0, 1.0) * clampf((1.0 - k) / 0.1, 0.0, 1.0)
	else:
		if k >= home:
			return   # it is flying to the hand as the small card
		var e3 := (k - 0.54) * _fuse_len / 0.33
		if e3 < 1.0:   # the slam: down, a bounce
			at2.y += [-30.0, -15.0, 4.0, -2.0, 0.0, 0.0][mini(5, int(e3 * 6.0))] * a
	CabinetCard.draw(self, spec, _snap(at2), a, s, o2)
	var alpha := float(o2.get("alpha", 1.0))
	# The stamp over the card's top edge, never on its face.
	draw_texture_rect(ArcadePaint.fx_tex(&"banner_fused", 0, &"fuse"), lay.stamp, false, Color(1, 1, 1, alpha))
	# The note beside the card: what it keeps, what it loses.
	var box: Rect2 = lay.note
	if alpha >= 0.99:
		CabinetArt.draw9_rect(self, &"bubble", box, a)
	else:
		draw_rect(box, Color(CabinetArt.c(&"slip"), alpha))
	var y := box.position.y + 4 * a
	for row: Dictionary in lay.rows:
		RailFrame.text(self, Vector2(box.position.x + 5 * a, roundf(y)), String(row.t), int(lay.size),
				Color(CabinetCard.text_color(row.c), alpha), bool(row.get("b", false)))
		y += float(lay.step)


## The fuse moment's layout (window px): {card: the fused card (the two parents meet there),
## stamp: FUSED! over its top edge, note: the keeps / loses box beside it, rows, size, step}.
## The card and the note are centred together in the view and never on each other.
func fuse_layout() -> Dictionary:
	var a := _a()
	var v := _view()
	var card := Vector2(CabinetCard.W, CabinetCard.H) * a
	var rows := fuse_note()
	var gap := 8 * a
	var room := v.size.x - card.x - gap - 26 * a
	var size := CabinetLayout.text_px(2, float(frame.s()))
	var widest := ""
	for row: Dictionary in rows:
		if RailFrame.text_w(String(row.t), size, true) > RailFrame.text_w(widest, size, true):
			widest = String(row.t)
	size = RailFrame.fit(widest, size, room, true, 11)
	var step := roundf(size * 10.0 / 11.0)
	var nw := minf(room, RailFrame.text_w(widest, size, true))
	var note_size := Vector2(ceilf(nw / a) + 10, ceilf(rows.size() * step / a) + 8) * a
	var x := v.position.x + (v.size.x - (card.x + gap + note_size.x)) * 0.5
	var y := v.position.y + 60 * a
	var card_r := Rect2(_snap(Vector2(x, y)), card)
	var ss := Vector2(57, 16) * a
	return {"card": card_r, "rows": rows, "size": size, "step": step,
			"note": Rect2(_snap(Vector2(card_r.end.x + gap, y + 10 * a)), note_size),
			"stamp": Rect2(_snap(Vector2(card_r.get_center().x - ss.x * 0.5, y - 22 * a)), ss)}


## The fuse moment's note rows: KEEPS and its lines, LOSES and its lines, then PERMANENT · RANK n.
func fuse_note() -> Array:
	var rows := []
	var keeps: Array = _fuse.get("keeps", [])
	if not keeps.is_empty():
		rows.append({"t": "KEEPS", "c": &"keep", "b": true})
		for t: String in keeps:
			rows.append({"t": "· " + t, "c": &"keep"})
	var loses: Array = _fuse.get("loses", [])
	if not loses.is_empty():
		rows.append({"t": "LOSES", "c": &"warn", "b": true})
		for t: String in loses:
			rows.append({"t": "· " + t, "c": &"warn"})
	rows.append({"t": "PERMANENT · RANK %d" % int(_fuse.get("rank", 0)), "c": &"ink", "b": true})
	return rows


func _draw_fx() -> void:
	var a := _a()
	for rg: Dictionary in _rings:
		if float(rg.age) < 0.0:
			continue
		var t := minf(1.0, float(rg.age) / float(rg.dur))
		var e := 1.0 - (1.0 - t) * (1.0 - t)
		var radius := roundi(float(rg.r0) + (float(rg.r1) - float(rg.r0)) * roundf(e * 10.0) / 10.0)
		var late := t > 0.55
		var last := t > 0.8
		var ramp := ArcadePaint.fx_ramp(rg.ramp)
		var c := _snap(rg.p)
		var bands := [[radius + 2, "K"], [radius + 1, "S"], [radius, "P"], [radius - 1, "W"], [radius - 2, "H"], [radius - 3, "K"]]
		for bi in bands.size():
			var rr := int(bands[bi][0])
			if rr < 1 or (last and (bi == 0 or bi == 5)):
				continue
			var col := CabinetArt.hex(ramp[bands[bi][1]])
			for cell: Array in CabinetArt.ring_cells(rr):
				var cx := int(cell[0])
				var cy := int(cell[1])
				if late and ((cx + cy) & 1) != 0:
					continue
				if last and (((cx >> 1) + (cy >> 1)) & 1) != 0:
					continue
				draw_rect(Rect2(c + Vector2(cx, cy) * a, Vector2(a, a)), col)
	for p: Dictionary in _parts:
		if float(p.wait) > 0.0:
			continue
		var n := ArcadePaint.fx_frames(p.sheet)
		var f := int(float(p.age) * float(p.fps)) if bool(p.once) else int(p.f) + int(float(p.age) * float(p.fps))
		if bool(p.once) and f >= n:
			continue
		var tex := ArcadePaint.fx_tex(p.sheet, f, p.ramp)
		var sz := Vector2(tex.get_size()) * a
		draw_texture_rect(tex, Rect2(_snap((p.p as Vector2) - sz * 0.5), sz), false)
	for fl: Dictionary in _flights:
		if float(fl.age) < 0.0:
			continue
		var k := _steps(float(fl.age) / float(fl.dur), 10)
		var from: Vector2 = fl.from
		var to: Vector2 = fl.to
		var tex2: Texture2D = fl.tex
		var sz2 := Vector2(tex2.get_size()) * a
		if _reduce():
			draw_texture_rect(tex2, Rect2(_snap(to - sz2 * 0.5), sz2), false, Color(1, 1, 1, sin(k * PI)))
			continue
		var mid := (from + to) * 0.5 - Vector2(0, float(fl.arc) * a)
		draw_texture_rect(tex2, Rect2(_snap(from.lerp(mid, k).lerp(mid.lerp(to, k), k) - sz2 * 0.5), sz2), false)
	_draw_slot_flashes()
	if not _flash.is_empty():
		var levels: Array = _flash.levels
		var li := mini(levels.size() - 1, int(float(_flash.age) / float(_flash.step)))
		var frames: Array = ArcadeArt.FX[&"flash_dither"].frames
		var lv := clampi(int(levels[li]), 0, frames.size() - 1)
		draw_texture_rect(CabinetArt.tile(StringName("flash_%d_%s" % [lv, _flash.col]), frames[lv], {"W": String(_flash.col)}, a),
				_view(), true)


## A landed card's slot: the dither flash over it, then its label rising and fading (the label
## alone, fading in place, under reduce flashing).
func _draw_slot_flashes() -> void:
	var d := _dock()
	if d == null:
		return
	var a := _a()
	var reduce := _reduce()
	var size := CabinetLayout.text_px(2, float(frame.s()))
	for f: Dictionary in _slot_flashes:
		var r: Rect2 = d.call(&"slot_rect", int(f.slot))
		var age := float(f.age)
		if not reduce:
			var levels: Array[int] = [16, 12, 8, 5, 3, 1]
			var li := int(age / 0.06)
			if li < levels.size():
				var frames: Array = ArcadeArt.FX[&"flash_dither"].frames
				draw_texture_rect(CabinetArt.tile(StringName("flash_%d_%s" % [levels[li], ArcadePaint.SLIP]), frames[levels[li]],
						{"W": ArcadePaint.SLIP}, a), r, true)
		var k := clampf(age / SLOT_FLASH, 0.0, 1.0)
		var label := String(f.label)
		var w := RailFrame.text_w(label, size, true)
		var rise := 0.0 if reduce else _steps(k, 8) * 12.0 * a
		var at := Vector2(roundf(r.get_center().x - w * 0.5), roundf(r.position.y - 4 * a - rise))
		var alpha := clampf((1.0 - k) * 3.0, 0.0, 1.0)
		RailFrame.text(self, at + Vector2(a, a), label, size, Color(CabinetArt.c(&"ink"), alpha), true)
		RailFrame.text(self, at, label, size, Color(CabinetArt.hex(ArcadePaint.fx_ramp(f.ramp).get("P", ArcadePaint.GOLD)), alpha), true)
