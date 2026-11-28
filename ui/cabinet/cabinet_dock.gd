class_name CabinetDock
extends Control
## M48.6d: the Arcade dock (PLAN 0.9.2 "The Arcade dock"; the mockup's .dock), in the cabinet's
## deck right of the caption. It takes the place of the rail's HAND and PACK modules there.
##
## The hand: two card slots in a bay. A held slot shows the weapon's splash art on its screen,
## its name on the plate, its rank chip, its key cap and a tab that says ACTIVE or HELD (a
## word, not only a colour); a free slot says EMPTY. Between the two slots the fuse link: none
## before the fusion basic or off a recipe pair, idle on a pair below the fuse rank, charged
## (lit) only when the pair can fuse now.
## The package: the pack art (up to three stacked), a red xN badge when more than one waits,
## the kills gauge (k of N to the next pack), the "[F] OPEN ALL" call (live while one waits),
## "n kills to next" and "n waiting". A click on the pack or the call asks for the packs, as
## the key does.
##
## It draws RailFrame.snap (RailState.read()) and writes nothing but that one ask. What moves
## by itself: the charged link, the active slot's arrow, the waiting stack's hop, a landed
## pack's drop; all still under reduce flashing. Presentation only: no RNG, no Tuning, no rules.

const AT := Vector2(513, 3)   ## the dock's top-left in the deck (design px)
const SLOT_X := 5             ## the first slot's left in the dock (art px)
const SLOT_W := 47
const SLOT_H := 42
const PKG_X := 114            ## the package's left
const PACK_AT := Vector2(5, 10)   ## the pack art inside it
const SIDE_X := 44            ## the call and the two lines, right of the pack art
const SLOTS := 2              ## the bay's width: the hand never shows more
const DROP_MS := 420

var frame: Node               ## the CabinetFrame
var _open: Button             ## the click area over the package
var _stack_seen := -1
var _drop_at := -100000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_open = Button.new()
	_open.name = "OpenAll"
	_open.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for st: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		_open.add_theme_stylebox_override(st, empty)
	_open.pressed.connect(open_all)
	_open.visible = false
	add_child(_open)


# --- What it shows (tests and captures read these) ------------------------------------------------

## The dock shows: the cabinet is on, on a live game whose path grows by cards (Arcade).
func shown() -> bool:
	if frame == null or not is_instance_valid(frame) or not bool(frame.get(&"on")):
		return false
	var sn: Dictionary = frame.snap
	return frame.layout.get("cabinet", false) and not sn.is_empty() and sn.path.kind == &"hand"


func _hand() -> Dictionary:
	return frame.snap.path.hand


func _pack() -> Dictionary:
	return frame.snap.path.pack


func _stage() -> Node:
	var st: Variant = frame.get(&"packs")
	return st if st != null and is_instance_valid(st) else null


## The hand's slots, left to right: {state: &"empty" / &"idle" / &"active", id, name, rank, tier,
## key, tab: "ACTIVE" / "HELD" / "", parents}. One per hand slot (two at most).
func slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not shown():
		return out
	var d := _hand()
	var cards: Array = d.cards
	var st := _stage()
	var hidden := st != null and bool(st.call(&"hand_hidden"))   # the fuse moment: the cards are up in the view
	for i in mini(SLOTS, int(d.max)):
		var key := InputSetup.expand_keys("{key:weapon_%d}" % (i + 1)).left(1).to_upper()
		if hidden or i >= cards.size():
			out.append({"state": &"empty", "id": &"", "name": "EMPTY", "rank": 0, "tier": &"common", "key": key, "tab": "",
					"parents": []})
			continue
		var c: Dictionary = cards[i]
		var tier: StringName = c.get("tier", &"common")
		out.append({"state": &"active" if c.active else &"idle", "id": c.get("id", &""), "name": String(c.title).to_upper(),
				"rank": int(c.rank), "tier": tier if tier in [&"rare", &"epic"] else &"common", "key": key,
				"tab": "ACTIVE" if c.active else "HELD", "parents": c.get("parent_ids", [])})
	return out


## The fuse link between the two slots: 0 none, 1 idle (a recipe pair below the fuse rank), 2
## charged (the pair can fuse now).
func link() -> int:
	if not shown() or slots().size() < 2:
		return 0
	var st := _stage()
	if st != null and bool(st.call(&"hand_hidden")):
		return 0
	return clampi(int(_hand().link), 0, 2)


func link_lit() -> bool:
	return link() == 2


## The hand is in S9's misfuse (the two cards seem to fuse, then come back).
func misfusing() -> bool:
	return shown() and bool(_hand().misfuse) and (_hand().cards as Array).size() >= 2


## The package: {on, waiting, stacked: packs drawn (1..3; one dim pack when none waits), badge:
## "x3" or "", kills, every, lit: gauge segments of 6, live: the call is live, call, next, queue}.
func package() -> Dictionary:
	var out := {"on": false, "waiting": 0, "stacked": 1, "badge": "", "kills": 0, "every": 1, "lit": 0, "live": false,
			"call": "", "next": "", "queue": ""}
	if not shown():
		return out
	var d := _pack()
	out.on = bool(d.on)
	if not out.on:
		return out
	var n := int(d.get("waiting", d.get("stack", 0)))
	out.waiting = n
	out.stacked = clampi(n, 1, 3)
	out.badge = "x%d" % n if n > 1 else ""
	out.kills = int(d.x)
	out.every = maxi(1, int(d.every))
	out.lit = clampi(floori(6.0 * out.kills / out.every), 0, 6)
	var st := _stage()
	out.live = n > 0 and not (st != null and bool(st.get(&"active")))
	var key := String(d.get("key", ""))
	out.call = "[%s] OPEN ALL" % key.to_upper() if key != "" else "OPEN ALL"
	var left := int(d.left)
	out.next = "%d kill%s to next" % [left, "" if left == 1 else "s"] if left >= 0 else "no more packs"
	out.queue = "%d waiting" % n if n > 0 else "none yet"
	return out


## Asks for the packs (the call's click; the same ask as the key). False when none may open.
func open_all() -> bool:
	if not shown() or not bool(package().live):
		return false
	var runner: Node = frame.game.get(&"path_runner") if frame.game != null and is_instance_valid(frame.game) else null
	return runner != null and is_instance_valid(runner) and bool(runner.call(&"open_pack"))


# --- Layout (window px) ---------------------------------------------------------------------------

func _a() -> float:
	return float(frame.call(&"art"))


## The dock's top-left.
func origin() -> Vector2:
	return frame.at(CabinetLayout.DECK.position + AT)


## Slot i (its whole grid: the screen, the plate, the tab's row).
func slot_rect(i: int) -> Rect2:
	var a := _a()
	return Rect2(origin() + Vector2(SLOT_X + clampi(i, 0, SLOTS - 1) * int(ArcadeArt.SLOT_LAYOUT.next), 0) * a, Vector2(SLOT_W, SLOT_H) * a)


## The pack art (the top pack of the stack).
func pack_rect() -> Rect2:
	var a := _a()
	return Rect2(origin() + (Vector2(PKG_X, 0) + PACK_AT) * a, Vector2(ArcadeArt.PACK_META.dock_w, ArcadeArt.PACK_META.dock_h) * a)


## The call ("[F] OPEN ALL"): 12 art px tall, as wide as its text.
func call_rect() -> Rect2:
	var a := _a()
	var w := ceili(RailFrame.text_w(String(package().call), _text_size()) / a) + 8
	return Rect2(origin() + Vector2(PKG_X + SIDE_X, 3) * a, Vector2(w, 12) * a)


## The whole dock (the hand's bay to the call's right edge).
func rect() -> Rect2:
	var r := Rect2(origin(), Vector2(112, SLOT_H) * _a())
	if bool(package().on):
		r = r.merge(pack_rect()).merge(call_rect())
	return r


func _text_size() -> int:
	return CabinetLayout.text_px(2, float(frame.s()))


func _process(_delta: float) -> void:
	var on := shown()
	if visible != on:
		visible = on
	if not on:
		return
	var pk := package()
	_open.visible = bool(pk.on)
	if _open.visible:
		var r := pack_rect().merge(call_rect())
		_open.position = r.position
		_open.size = r.size
		_open.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if bool(pk.live) else Control.CURSOR_ARROW
	var n := int(pk.waiting)
	if _stack_seen >= 0 and n > _stack_seen:   # a pack landed: it drops onto the stack
		_drop_at = Time.get_ticks_msec()
	_stack_seen = n
	queue_redraw()


# --- Drawing --------------------------------------------------------------------------------------

## The pixel font's row of 7-px capitals centred in a box `h` art px tall.
func _text_y(top: float, h: float, size: int, bold := false) -> float:
	var font := UiTheme.pixel_font(bold)
	var cap := size * 7.0 / 11.0
	return roundf(top + (h * _a() - cap) * 0.5 - (font.get_ascent(size) - cap))


func _tex(t: Texture2D, at: Vector2, alpha := 1.0) -> void:
	draw_texture_rect(t, Rect2(at, Vector2(t.get_size()) * _a()), false, Color(1, 1, 1, alpha))


func _draw() -> void:
	if not shown():
		return
	var a := _a()
	var o := origin()
	var still := SaveGame.reduce_flashing()
	var t := 0 if still else CabinetCard.tick()
	var sl := slots()
	var n := sl.size()
	var l: Dictionary = ArcadeArt.SLOT_LAYOUT
	var size := _text_size()
	# The hand's bay and its screws.
	var bay_w := SLOT_X * 2 + (n - 1) * int(l.next) + SLOT_W + 1 if n > 0 else 0
	if n > 0:
		CabinetArt.draw9(self, &"hand_bay", o + Vector2(0, 1) * a, bay_w, 39, a)
		for p: Vector2 in [Vector2(2, 3), Vector2(bay_w - 5, 3), Vector2(2, 35), Vector2(bay_w - 5, 35)]:
			CabinetArt.orn(self, &"screw_s", o + p * a, a)
	var lk := link()
	var bad := misfusing()
	if lk > 0 or bad:   # under the slots, as the kit draws it
		_tex(ArcadePaint.link_tex(lk == 2 or bad, t), o + Vector2(SLOT_X + int(l.link[0]), int(l.link[1])) * a)
	for i in n:
		var d := sl[i]
		var at := o + Vector2(SLOT_X + i * int(l.next), 0) * a
		if bad and not still:   # the misfuse: the two cards pull at each other
			at.x += (1.0 if i == 0 else -1.0) * float(t % 2) * a
		var held: bool = d.state != &"empty"
		_tex(ArcadePaint.slot_tex(d.tier, d.state, t >> 1), at)
		_tex(ArcadePaint.keycap_tex(String(d.key), d.state == &"active", not held), at)
		if not held:
			RailFrame.text(self, Vector2(at.x + int(l.screen[0]) * a, _text_y(at.y + int(l.screen[1]) * a, float(l.screen[3]), size)),
					"EMPTY", size, CabinetArt.c(&"metal_lo"), false, HORIZONTAL_ALIGNMENT_CENTER, int(l.screen[2]) * a)
			continue
		if d.tier == &"rare":
			_tex(ArcadePaint.crown_tex(), at + Vector2(19, -2) * a)
		_tex(ArcadePaint.slot_art_tex(d.id, d.parents), at + Vector2(int(l.icon[0]), int(l.icon[1])) * a)
		_tex(ArcadePaint.rank_tex(int(d.rank)), at + Vector2(int(l.rank[0]) - (4 if int(d.rank) > 9 else 0), int(l.rank[1])) * a)
		var label := String(d.name)
		var ns := RailFrame.fit(label, size, int(l.name[2]) * a, false, 11)
		RailFrame.text(self, Vector2(at.x + int(l.name[0]) * a, _text_y(at.y + int(l.name[1]) * a, float(l.name[3]), ns)), label, ns,
				CabinetArt.c(&"ink"), false, HORIZONTAL_ALIGNMENT_CENTER, int(l.name[2]) * a)
		if not bad:
			var tab := ArcadePaint.tab_tex(String(d.tab), d.state == &"active")
			_tex(tab, at + Vector2(23 - (tab.get_width() >> 1), 31) * a)
	if bad:   # one tab across the two slots says what it is
		var warn := ArcadePaint.tab_tex("MISFUSE", false, true)
		_tex(warn, o + Vector2((bay_w - warn.get_width()) >> 1, 31) * a)
	_draw_package(o, t, still)


func _draw_package(o: Vector2, t: int, still: bool) -> void:
	var pk := package()
	if not bool(pk.on):
		return
	var a := _a()
	var size := _text_size()
	var po := o + Vector2(PKG_X, 0) * a
	var n := int(pk.waiting)
	var show := int(pk.stacked)
	# The stack: it hops while more than one waits; a landed pack drops in.
	var lift := 0.0
	if not still:
		var since := Time.get_ticks_msec() - _drop_at
		if since < DROP_MS:
			lift = [-8.0, -4.0, 1.0, 0.0][mini(3, int(since * 4.0 / DROP_MS))]
		elif n > 1 and t % 10 == 0:
			lift = -1.0
	for j in range(show - 1, -1, -1):
		_tex(ArcadePaint.dock_pack_tex(n == 0), po + (PACK_AT + Vector2(j * 2, -j + lift)) * a)
	if String(pk.badge) != "":
		var at: Array = ArcadeArt.PACK_META.badge_at
		_tex(ArcadePaint.badge_tex(String(pk.badge)), po + (PACK_AT + Vector2(int(at[0]) - 1 + (show - 1) * 2, int(at[1]) - 1 - (show - 1) + lift)) * a)
	var gp: Array = ArcadeArt.PACK_META.gauge_at
	_tex(ArcadePaint.gauge_tex(int(pk.lit)), po + (PACK_AT + Vector2(int(gp[0]), int(gp[1]))) * a)
	# The call, then the two lines.
	var cr := call_rect()
	var live := bool(pk.live)
	if live:
		CabinetArt.draw9_rect(self, &"cta_live", cr.grow(a), a)
	else:
		CabinetArt.draw9_rect(self, &"cta_off", Rect2(cr.position, cr.size - Vector2(0, a)), a)
	RailFrame.text(self, Vector2(cr.position.x, _text_y(cr.position.y, 11.0, size)), String(pk.call), size,
			CabinetArt.c(&"ink") if live else CabinetArt.hex(ArcadePaint.DOCK_OFF), false, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	var x := cr.position.x
	RailFrame.text(self, Vector2(x, _text_y(cr.position.y + 15 * a, 7.0, size)), String(pk.next), size, CabinetArt.hex(ArcadePaint.DOCK_LINE))
	RailFrame.text(self, Vector2(x, _text_y(cr.position.y + 24 * a, 7.0, size)), String(pk.queue), size, CabinetArt.hex(ArcadePaint.DOCK_QUEUE))
