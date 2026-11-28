extends Control
## M48.5a: the version rail's HUD modules, each a plum cell hanging from the version that
## shipped it (Pixel_A / Pixel_A_hud): KILLS, HP, DASH, then the path slot (Arsenal HAND +
## PACK, Auto ITEMS, Survival AMMO). A module whose basic or path is not live is an empty
## inset well. It draws RailFrame.snap (RailState.read()); the frame redraws it when the
## reading changes.

var frame: Node   ## the RailFrame (M48.6a: in the cabinet's deck its ms() / mpx() are smaller than s() / px())
## M50.7: a hand card's rank-up highlight (title -> rank seen, title -> msec it changed) and the
## stack chip's pulse on a landed pack (real time; steady under reduce flashing).
var _ranks := {}
var _ranked_at := {}
var _stack_seen := 0
var _stack_at := -100000
const FLASH_MS := 600


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## M50.7: keeps drawing while a rank-up or pack highlight is fading (the frame redraws only on a
## new reading).
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _stack_at < FLASH_MS + 50:
		queue_redraw()
		return
	for t: String in _ranked_at:
		if now - int(_ranked_at[t]) < FLASH_MS + 50:
			queue_redraw()
			return


## M50.7: 1 at a change fading to 0 over FLASH_MS (a steady 1 until then under reduce flashing).
func _glow(at_ms: int) -> float:
	var k := float(Time.get_ticks_msec() - at_ms) / FLASH_MS
	if k < 0.0 or k >= 1.0:
		return 0.0
	return 1.0 if SaveGame.reduce_flashing() else 1.0 - k


## The modules shown now (their basic or path live), in rail order.
func shown_modules() -> Array[StringName]:
	var out: Array[StringName] = []
	var sn: Dictionary = frame.snap
	if sn.is_empty():
		return out
	# M48.6b: in the cabinet only the modules it gives a cell (the path's) are shown.
	var cells: Dictionary = frame.layout.get("cells", {})
	var all: bool = not frame.layout.get("cabinet", false)
	if sn.kills.on and (all or cells.has(&"kills")):
		out.append(&"kills")
	if sn.hp.on and (all or cells.has(&"hp")):
		out.append(&"hp")
	if sn.dash.on and (all or cells.has(&"dash")):
		out.append(&"dash")
	match sn.path.kind:
		&"hand":
			out.append(&"path")
			if sn.path.pack.on:
				out.append(&"pack")
		&"items", &"ammo":
			out.append(&"path")
	return out


## A module's cell in window px (path: the whole slot, or HAND when Arsenal splits it).
func cell_rect(m: StringName) -> Rect2:
	var cells: Dictionary = frame.layout.get("cells", {})
	if m == &"path" and not frame.snap.is_empty() and frame.snap.path.kind == &"hand":
		return cells.get(&"hand", Rect2())
	return cells.get(m, Rect2())


func _draw() -> void:
	var l: Dictionary = frame.layout
	if not l.get("rail", false) or frame.snap.is_empty():
		return
	var sn: Dictionary = frame.snap
	var sc: float = frame.ms()
	if l.has("caption"):   # M48.6a: the cabinet's marquee carries it
		RailFrame.text(self, l.caption, frame.caption(), RailLayout.text_px(12, sc), RailArt.c(&"mute"))
	var cells: Dictionary = l.cells
	# M48.6b: a module is drawn only where the layout gives it a cell (the cabinet gives KILLS,
	# HP and DASH none: they are on the player and on the view's corner plate).
	if not cells.has(&"kills"):
		pass
	elif sn.kills.on:
		_kills(cells.kills, sn.kills)
	else:
		_empty(cells.kills, "KILLS")
	if not cells.has(&"hp"):
		pass
	elif sn.hp.on:
		_hp(cells.hp, sn.hp)
	else:
		_empty(cells.hp, "HP")
	if not cells.has(&"dash"):
		pass
	elif sn.dash.on:
		_dash(cells.dash, sn.dash)
	else:
		_empty(cells.dash, "DASH")
	match sn.path.kind:
		&"hand":
			_hand(cells.hand, sn.path.hand)
			if sn.path.pack.on:
				_pack(cells.pack, sn.path.pack)
			else:
				_empty(cells.pack, "PACK")
		&"items":
			_items(cells.path, sn.path.items)
		&"ammo":
			_ammo(cells.path, sn.path.ammo)
		_:
			_empty(cells.path, "next ?")


# --- Shared pieces -------------------------------------------------------------------------------

## The module's cell and its tab with the title (`accent`: the gold part after it).
func _cell(r: Rect2, title: String, accent := "") -> void:
	var p: float = frame.mpx()
	var sc: float = frame.ms()
	RailArt.bevel(self, r, RailArt.c(&"cell"), RailArt.c(&"hi"), RailArt.c(&"lo"), p)
	var tab := Rect2(r.position, Vector2(r.size.x, roundf(28 * sc)))
	RailArt.bevel(self, tab, RailArt.c(&"base"), RailArt.c(&"cell"), RailArt.c(&"base"), p)
	draw_rect(Rect2(Vector2(tab.position.x, tab.end.y - p), Vector2(tab.size.x, p)), RailArt.c(&"ink"))
	var fs := RailLayout.text_px(16, sc)
	var at := r.position + Vector2(12, 6) * sc
	RailFrame.text(self, at, title, fs, RailArt.c(&"text"), true)
	if accent != "":
		RailFrame.text(self, at + Vector2(RailFrame.text_w(title, fs, true) + 6 * sc, 0), accent, fs, RailArt.c(&"gold"))


## A module that is not live: an inset well, its name dim.
func _empty(r: Rect2, title: String) -> void:
	var p: float = frame.mpx()
	var sc: float = frame.ms()
	RailArt.bevel(self, r, RailArt.c(&"sunk"), RailArt.c(&"ink"), RailArt.c(&"base"), p)
	RailFrame.text(self, r.position + Vector2(12, 8) * sc, title, RailLayout.text_px(16, sc), RailArt.c(&"hi"), true)


## A big number in the pixel digits (design size `d_size`: 64, 32, 24...), top-left at
## `top_left`; returns its width.
func _num(top_left: Vector2, t: String, d_size: float, color: Color) -> float:
	var cell := maxf(1.0, roundf(d_size * frame.ms() / 9.0))
	RailArt.draw_digits(self, top_left.round(), t, cell, color)
	return RailArt.digits_width(t, cell) + cell


func _num_h(d_size: float) -> float:
	return maxf(1.0, roundf(d_size * frame.ms() / 9.0)) * 7.0


func _d(r: Rect2, d: Vector2) -> Vector2:
	return (r.position + d * frame.ms()).round()


func _small(r: Rect2, d: Vector2, t: String, color := Color.WHITE, size := 12) -> void:
	RailFrame.text(self, _d(r, d), t, RailLayout.text_px(size, frame.ms()), RailArt.c(&"dim") if color == Color.WHITE else color)


## A key chip ("SHIFT", "1"): paper, ink outline, a bottom lip; gold when `gold`.
func _key(top_left: Vector2, t: String, gold := false, alpha := 1.0) -> float:
	var sc: float = frame.ms()
	var p: float = frame.mpx()
	var fs := RailLayout.text_px(12, sc)
	var w := maxf(24 * sc, RailFrame.text_w(t, fs, true) + 12 * sc)
	var r := Rect2(top_left, Vector2(roundf(w), roundf(22 * sc)))
	var fill := RailArt.c(&"gold") if gold else RailArt.c(&"key")
	var lip := RailArt.c(&"gold_lo") if gold else RailArt.c(&"key_lo")
	RailArt.block(self, r, Color(fill, alpha), p, roundf(4 * sc), Color(lip, alpha))
	RailFrame.text(self, r.position + Vector2(0, 3 * sc), t, fs, Color(RailArt.c(&"ink"), alpha), true, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	return r.size.x


## A row of square segments (16x16 design, 2 px gaps): `lit` of `n` in `color`.
func _segments(top_left: Vector2, n: int, lit: int, color: Color, seg := 16.0, gap := 4.0) -> void:
	var sc: float = frame.ms()
	var p: float = frame.mpx()
	for i in n:
		var r := Rect2(top_left + Vector2(2 + i * (seg + gap), 2) * sc, Vector2(seg, seg) * sc)
		RailArt.block(self, Rect2(r.position.round(), r.size.round()), color if i < lit else RailArt.c(&"sunk"), p)


# --- KILLS, HP, DASH --------------------------------------------------------------------------

func _kills(r: Rect2, d: Dictionary) -> void:
	var sc: float = frame.ms()
	_cell(r, "KILLS")
	var gpx := roundf(5 * sc)
	var gs := RailArt.grid_size(RailArt.SKULL, gpx)
	RailArt.draw_grid(self, RailArt.SKULL, RailArt.SKULL_LEGEND, (Vector2(r.get_center().x - gs.x * 0.5, r.position.y + 40 * sc)).round(), gpx)
	var n := str(int(d.n))
	var size := 64.0 if n.length() <= 2 else 40.0
	var cell := maxf(1.0, roundf(size * sc / 9.0))
	_num(Vector2(r.get_center().x - RailArt.digits_width(n, cell) * 0.5, r.position.y + 92 * sc), n, size, RailArt.c(&"gold"))
	RailFrame.text(self, _d(r, Vector2(0, 172)), "this run", RailLayout.text_px(16, sc), RailArt.c(&"dim"), false, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _hp(r: Rect2, d: Dictionary) -> void:
	var sc: float = frame.ms()
	_cell(r, "HP")
	var n := mini(int(d.max), 10)
	var avail := r.size.x - 14 * sc
	var hpx := clampf(floorf(avail / float(n * 7 + (n - 1))), 1.0, roundf(4 * sc))
	var x := r.position.x + 10 * sc
	for i in n:
		RailArt.draw_grid(self, RailArt.HEART, RailArt.HEART_LEGEND if i < int(d.hp) else RailArt.HEART_EMPTY_LEGEND,
				Vector2(roundf(x), roundf(r.position.y + 44 * sc)), hpx)
		x += hpx * 8.0
	# M48.5b: "10/10" (Auto's health) shrinks to fit the cell instead of running past it.
	var hp_s := str(int(d.hp))
	var max_s := "/%d" % int(d.max)
	var big := 64.0
	while big > 18.0 and RailArt.digits_width(hp_s + max_s, maxf(1.0, roundf(big * sc / 9.0))) + 2.0 * maxf(1.0, roundf(big * sc / 9.0)) > r.size.x - 24 * sc:
		big -= 1.0
	var w := _num(_d(r, Vector2(12, 92)), hp_s, big, RailArt.c(&"hp"))
	_num(_d(r, Vector2(12, 92)) + Vector2(w, 0), max_s, big, RailArt.c(&"dim"))
	var hits := int(d.hits)
	RailFrame.text(self, _d(r, Vector2(12, 172)), "%d hit%s taken" % [hits, "" if hits == 1 else "s"], RailLayout.text_px(16, sc), RailArt.c(&"dim"))


func _dash(r: Rect2, d: Dictionary) -> void:
	var sc: float = frame.ms()
	var style: String = d.style
	_cell(r, "DASH", "· " + ("tp" if style == "teleport" else style))
	var hot: Dictionary = frame.hotfix
	if not hot.is_empty() and hot.module == &"dash":
		_solder(r, hot.version)
	else:
		_small(r, Vector2(12, 36), "pick: classic / grapple / tp")
	var ready: bool = d.ready
	var apx := roundf(4 * sc)
	RailArt.draw_grid(self, RailArt.ARROW, RailArt.ARROW_LEGEND, _d(r, Vector2(12, 56)), apx, true)
	_small(r, Vector2(68, 56), "state")
	RailFrame.text(self, _d(r, Vector2(68, 70)), "READY" if ready else "RECHARGING", RailLayout.text_px(16, sc),
			RailArt.c(&"mint") if ready else RailArt.c(&"warn"), true)
	var frac: float = d.frac
	_segments(_d(r, Vector2(10, 100)), 10, 10 if ready else floori(frac * 10.0), RailArt.c(&"mint"))
	var pct := "%d%%" % roundi(100.0 * (1.0 if ready else frac))
	var pw := _num(_d(r, Vector2(12, 134)), pct, 24, RailArt.c(&"text"))
	if not ready:
		RailFrame.text(self, _d(r, Vector2(12, 134)) + Vector2(pw + 6 * sc, 0),
				"ready in %.1f s" % float(d.left), RailLayout.text_px(16, sc), RailArt.c(&"dim"))
	var kw := _key(_d(r, Vector2(12, 172)), String(d.key).to_upper(), ready, 1.0 if ready else 0.6)
	var hint := "press to %s" % String(d.label) if ready else "cooldown %.1f s" % float(d.total)
	RailFrame.text(self, _d(r, Vector2(12, 175)) + Vector2(kw + 8 * sc, 0), hint, RailLayout.text_px(16, sc), RailArt.c(&"dim"))


## The hotfix's solder on a module's tab: a gold strip, three beads and the chip.
func _solder(r: Rect2, version: String) -> void:
	var sc: float = frame.ms()
	var p: float = frame.mpx()
	draw_rect(Rect2(r.position, Vector2(roundf(220 * sc), roundf(4 * sc))), RailArt.c(&"gold"))
	draw_rect(Rect2(r.position + Vector2(0, 4 * sc), Vector2(roundf(220 * sc), p)), RailArt.c(&"gold_lo"))
	for bx in [28.0, 150.0, 196.0]:
		RailArt.block(self, Rect2(_d(r, Vector2(bx, -2)), Vector2(8, 8) * sc), RailArt.c(&"gold_hi"), p)
	var fs := RailLayout.text_px(12, sc)
	var t := "hotfix " + version
	var cr := Rect2(_d(r, Vector2(12, 34)), Vector2(RailFrame.text_w(t, fs) + 8 * sc, roundf(14 * sc)))
	RailArt.block(self, cr, RailArt.c(&"gold"), p)
	RailFrame.text(self, cr.position + Vector2(4 * sc, 0), t, fs, RailArt.c(&"ink"))


# --- Arsenal: HAND + PACK -----------------------------------------------------------------------

func _hand(r: Rect2, d: Dictionary) -> void:
	var sc: float = frame.ms()
	var p: float = frame.mpx()
	var cards: Array = d.cards
	_cell(r, "HAND", str(int(d.max)))
	var hot: Dictionary = frame.hotfix
	if not hot.is_empty() and hot.module == &"path":
		_solder(r, hot.version)
	# The switch keys, top right.
	var kx := r.end.x - 10 * sc - RailFrame.text_w("swap", RailLayout.text_px(12, sc)) - 8 * sc
	var keys: Array[String] = []
	for c: Dictionary in cards:
		keys.append(String(c.key).to_upper())
	RailFrame.text(self, Vector2(kx + 6 * sc, r.position.y + 8 * sc), "swap", RailLayout.text_px(12, sc), RailArt.c(&"dim"))
	for i in range(keys.size() - 1, -1, -1):
		var w := maxf(24 * sc, RailFrame.text_w(keys[i], RailLayout.text_px(12, sc), true) + 12 * sc)
		kx -= w + 8 * sc
		_key(Vector2(roundf(kx), roundf(r.position.y + 3 * sc)), keys[i])
	if d.misfuse and cards.size() >= 2:
		_misfuse(r, d)
	else:
		for i in cards.size():
			_card(Rect2(_d(r, Vector2(12 + i * 170, 38)), (Vector2(156, 140) * sc).round()), cards[i])
	# The fusion strip: lit once FUSE is available, dim while a half is below rank 4.
	var link := int(d.link)
	if link > 0 and String(d.recipe) != "":
		var strip := Rect2(_d(r, Vector2(12, 186)), (Vector2(326, 22) * sc).round())
		var fs := RailLayout.text_px(16, sc)
		if link == 2:
			RailArt.block(self, strip, RailArt.c(&"gold"), p, roundf(3 * sc), RailArt.c(&"gold_lo"))
			RailFrame.text(self, strip.position + Vector2(8, 2) * sc, "%s READY" % String(d.recipe).to_upper(), fs, RailArt.c(&"ink"), true)
			# M50.7: how to fuse, with the open key (as the pack module names it).
			var how := "[%s] open a pack to fuse  " % PathRunner.open_key() if Settings.key_hints() else "open a pack to fuse  "
			if bool(d.get("pack_open", false)):   # M50.7 review: the pack is already open
				how = "FUSE is in this pack  "
			RailFrame.text(self, strip.position + Vector2(0, 2 * sc), how, RailFrame.fit(how, fs, strip.size.x * 0.55, false, 8),
					RailArt.c(&"ink"), false, HORIZONTAL_ALIGNMENT_RIGHT, strip.size.x)
		else:
			RailArt.block(self, strip, RailArt.c(&"sunk"), p)
			RailFrame.text(self, strip.position + Vector2(8, 3) * sc, "%s at rank 4" % String(d.recipe).to_lower(), RailLayout.text_px(12, sc), RailArt.c(&"mute"))
	elif cards.size() < int(d.max):
		_small(r, Vector2(14, 190), "%d free slot%s: the next pack fills it" % [int(d.max) - cards.size(), "" if int(d.max) - cards.size() == 1 else "s"])


## One card: rank badge, title, rank line, the weapon's picture, rank pips (8 then +N).
func _card(cr: Rect2, c: Dictionary) -> void:
	var sc: float = frame.ms()
	var p: float = frame.mpx()
	var lit: bool = c.active
	RailArt.block(self, cr, RailArt.c(&"paper"), 2 * p)
	# M50.7: a rank-up lights the card for FLASH_MS (steady under reduce flashing).
	var title_key := String(c.title)
	# Review: only a rise is a rank-up (a new session's rank 1, or a card back after a fuse, is not).
	if _ranks.has(title_key) and int(c.rank) > int(_ranks[title_key]):
		_ranked_at[title_key] = Time.get_ticks_msec()
	_ranks[title_key] = int(c.rank)
	var g := _glow(int(_ranked_at.get(title_key, -100000)))
	if g > 0.0:
		draw_rect(cr.grow(3 * p), Color(RailArt.c(&"gold"), 0.85 * g), false, 3 * p)
		draw_rect(cr, Color(RailArt.c(&"gold_hi"), 0.35 * g))
	if lit:
		for side: Rect2 in [Rect2(cr.position, Vector2(cr.size.x, 2 * p)), Rect2(cr.position, Vector2(2 * p, cr.size.y)),
				Rect2(Vector2(cr.end.x - 2 * p, cr.position.y), Vector2(2 * p, cr.size.y))]:
			draw_rect(side, RailArt.c(&"gold"))
		draw_rect(Rect2(Vector2(cr.position.x, cr.end.y - 4 * p), Vector2(cr.size.x, 4 * p)), RailArt.c(&"paper_lo"))
		draw_rect(Rect2(Vector2(cr.position.x, cr.end.y - 2 * p), Vector2(cr.size.x, 2 * p)), RailArt.c(&"gold"))
	else:
		draw_rect(Rect2(Vector2(cr.position.x, cr.end.y - 2 * p), Vector2(cr.size.x, 2 * p)), RailArt.c(&"paper_lo"))
	if c.fused:
		draw_rect(Rect2(Vector2(cr.end.x - p * 2, cr.position.y + cr.size.y * 0.4), Vector2(p * 2, cr.size.y * 0.6)), RailArt.c(&"pink"))
		draw_rect(Rect2(Vector2(cr.position.x + cr.size.x * 0.4, cr.end.y - p * 2), Vector2(cr.size.x * 0.6, p * 2)), RailArt.c(&"pink"))
	var rank := int(c.rank)
	var digits := str(rank)
	var bw := 36.0 if digits.length() < 2 else 44.0
	var badge := Rect2((cr.position + Vector2(8, 8) * sc).round(), (Vector2(bw, 36) * sc).round())
	RailArt.block(self, badge, RailArt.c(&"gold") if lit else RailArt.c(&"warn"), roundf(1.5 * p), roundf(4 * sc),
			RailArt.c(&"gold_lo") if lit else RailArt.c(&"warn_lo"))
	var bcell := maxf(1.0, roundf(3 * sc))
	RailArt.draw_digits(self, (badge.position + (badge.size - Vector2(RailArt.digits_width(digits, bcell), 7 * bcell)) * 0.5).round(),
			digits, bcell, RailArt.c(&"ink"))
	var tx := badge.end.x + 8 * sc
	var tw := cr.end.x - tx - 6 * sc
	var title: String = c.title
	RailFrame.text(self, Vector2(tx, cr.position.y + 10 * sc), title, RailFrame.fit(title, RailLayout.text_px(16, sc), tw, true, 8), RailArt.c(&"ink"), true)
	var sub := "rank %d · %s" % [rank, "active" if lit else ("fuse rank" if rank >= 4 else "held")]
	if c.fused:
		sub = " + ".join(c.parents).to_lower()
	RailFrame.text(self, Vector2(tx, cr.position.y + 30 * sc), sub, RailFrame.fit(sub, RailLayout.text_px(12, sc), tw, false, 6), RailArt.c(&"hi"))
	# M50.5a: the hand card shows its gun (CardArt, as Auto's rail slots do), not its shot.
	WeaponGlyph.draw_card(self, c.icon, cr.position + Vector2(cr.size.x * 0.5, 76 * sc),
			roundf((64.0 if Skins.current != null else 44.0) * sc), Color.WHITE)
	# Rank pips: the classic curve to its top, the deep curve 8 then "+N".
	var n := rank if c.deep else Loadout.MAX_RANK
	var shown := mini(n, 8)
	var pip := roundf(12 * sc)
	# M50.7 review: the "+N" chip stays inside the card (the pips close up to make room for it).
	var more := "+%d" % (n - 8) if n > 8 else ""
	var cell := maxf(1.0, roundf(2 * sc))
	var chip_w := RailArt.digits_width(more, cell) + 6 * sc + 2 * sc if more != "" else 0.0
	var step := minf(16.0, (cr.size.x / sc - 20.0 - chip_w / sc) / 8.0) if more != "" else 16.0
	for k in shown:
		var on_pip: bool = c.deep or k < rank
		RailArt.block(self, Rect2((cr.position + Vector2(10 + k * step, 112) * sc).round(), Vector2(minf(pip, (step - 2) * sc), pip)),
				(RailArt.c(&"gold") if lit else RailArt.c(&"warn")) if on_pip else RailArt.c(&"pip_off"), p)
	if more != "":
		var t := more
		var at := (cr.position + Vector2(10 + 8 * step + 2, 110) * sc).round()
		draw_rect(Rect2(at, Vector2(RailArt.digits_width(t, cell) + 6 * sc, roundf(16 * sc))), RailArt.c(&"ink"))
		RailArt.draw_digits(self, at + Vector2(3 * sc, roundf(1 * sc)), t, cell, RailArt.c(&"gold"))


## The misfuse: both cards as one tilted card across the two slots (no tilt under reduce flashing).
func _misfuse(r: Rect2, d: Dictionary) -> void:
	var sc: float = frame.ms()
	var p: float = frame.mpx()
	var cr := Rect2(_d(r, Vector2(80, 38)), (Vector2(180, 140) * sc).round())
	var tilt := 0.0 if SaveGame.reduce_flashing() else deg_to_rad(4.0 * sin(Time.get_ticks_msec() * 0.001 * TAU * 2.0))
	draw_set_transform(cr.get_center(), tilt, Vector2.ONE)
	var box := Rect2(-cr.size * 0.5, cr.size)
	RailArt.block(self, box, RailArt.c(&"paper"), 2 * p)
	draw_rect(Rect2(box.position + Vector2(0, 18 * sc), Vector2(box.size.x, 4 * sc)), RailArt.c(&"warn"))
	var title: String = d.misfuse_title
	RailFrame.text(self, box.position + Vector2(0, 28 * sc), title, RailLayout.text_px(24, sc), RailArt.c(&"who"), true, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	var cards: Array = d.cards
	WeaponGlyph.draw(self, cards[0].icon, Vector2(-10 * sc, 30 * sc), roundf(44 * sc), Color.WHITE)
	WeaponGlyph.draw(self, cards[1].icon, Vector2(10 * sc, 40 * sc), roundf(44 * sc), Color(1, 1, 1, 0.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_small(r, Vector2(14, 190), "misfuse: the AI is patching it", RailArt.c(&"warn"))


func _pack(r: Rect2, d: Dictionary) -> void:
	var sc: float = frame.ms()
	var stack := int(d.get("stack", 0))
	var waiting := int(d.get("waiting", stack))   # M50.7: not the pack on screen
	_cell(r, "PACK", "x%d" % waiting if waiting > 0 else "")   # M50.6: the stack's count (M50.7 review: waiting)
	if stack > _stack_seen:   # M50.7: a landed pack pulses the module once
		_stack_at = Time.get_ticks_msec()
	_stack_seen = stack
	var pg := _glow(_stack_at)
	if pg > 0.0:
		draw_rect(r.grow(2 * frame.mpx()), Color(RailArt.c(&"gold"), pg), false, 3 * frame.mpx())
	RailArt.draw_grid(self, RailArt.PACK, RailArt.PACK_LEGEND, _d(r, Vector2(16, 40)), roundf(5 * sc), true)
	var pw := _num(_d(r, Vector2(84, 46)), str(int(d.x)), 56, RailArt.c(&"gold"))
	_num(_d(r, Vector2(84, 46)) + Vector2(pw, 0), "/%d" % int(d.every), 56, RailArt.c(&"dim"))
	var every := int(d.every)
	var seg := minf(16.0, (r.size.x / sc - 90.0) / every - 4.0)
	_segments(_d(r, Vector2(82, 110)), every, int(d.x), RailArt.c(&"gold"), seg)
	var left := int(d.left)
	var line := "%d kill%s to pack %d" % [left, "" if left == 1 else "s", int(d.next)] if left >= 0 else "no more packs"
	RailFrame.text(self, _d(r, Vector2(14, 146)), line, RailLayout.text_px(16, sc), RailArt.c(&"text"))
	if waiting <= 0:   # M50.7: the next pack's real card count
		RailFrame.text(self, _d(r, Vector2(14, 174)), RailState.pick_line(int(d.get("cards_next", 3)), int(d.get("cards_max", -1))), RailLayout.text_px(16, sc),
				RailArt.c(&"dim"))
		return
	# M50.6: packs wait until the player opens one: the key chip, then how many are stacked.
	var at := _d(r, Vector2(14, 171))
	var key := String(d.get("key", ""))
	if key != "":
		at.x += _key(at, key.to_upper(), true) + roundf(6 * sc)
	RailFrame.text(self, Vector2(at.x, _d(r, Vector2(14, 174)).y), "open  -  %d waiting" % waiting, RailLayout.text_px(16, sc),
			RailArt.c(&"gold"))


# --- Auto: ITEMS -------------------------------------------------------------------------------

func _items(r: Rect2, d: Dictionary) -> void:
	var sc: float = frame.ms()
	var p: float = frame.mpx()
	var weapons: Array = d.weapons
	var passives: Array = d.passives
	var n_w := int(d.slots)
	var n_p := int(d.passive_slots)
	_cell(r, "ITEMS", "%d+%d" % [weapons.size(), passives.size()])
	_small(r, Vector2(150, 9), "%d weapon slots · cap lv %d" % [n_w, int(d.cap)])
	if n_p > 0:
		_small(r, Vector2(380, 9), "%d passives" % n_p)
	var divider := 14.0 if n_p > 0 else 0.0
	var slot_w := floorf((568.0 - 24.0 - divider) / float(n_w + n_p)) - 6.0
	var x := 12.0
	for i in n_w:
		_slot(r, x, slot_w, weapons[i] if i < weapons.size() else {}, int(d.cap), false, int(d.get("new_slot", -1)) == i)
		x += slot_w + 6.0
	if n_p > 0:
		draw_rect(Rect2(_d(r, Vector2(x + 2, 36)), Vector2(roundf(4 * sc), roundf(120 * sc))), RailArt.c(&"ink"))
		draw_rect(Rect2(_d(r, Vector2(x + 6, 36)), Vector2(p, roundf(120 * sc))), RailArt.c(&"hi"))
		x += divider
		for i in n_p:
			_slot(r, x, slot_w, passives[i] if i < passives.size() else {}, int(d.cap), true, int(d.get("new_passive", -1)) == i)
			x += slot_w + 6.0
	# The XP strip on the plate floor.
	var floor_r := Rect2(_d(r, Vector2(0, 164)), Vector2(r.size.x, r.end.y - roundf(r.position.y + 164 * sc)))
	draw_rect(floor_r, RailArt.c(&"base"))
	draw_rect(Rect2(floor_r.position, Vector2(floor_r.size.x, p)), RailArt.c(&"ink"))
	var lv := "LV %d" % int(d.level)
	var lw := _num(_d(r, Vector2(12, 172)), lv, 32, RailArt.c(&"gold"))
	var bx := maxf(92.0, 12.0 + lw / sc + 8.0)
	var bar := Rect2(_d(r, Vector2(bx, 176)), (Vector2(472.0 - bx, 16) * sc).round())
	RailArt.block(self, bar, RailArt.c(&"sunk"), p)
	var picking := bool(d.get("picking", false))   # M50.4f: a level-up is open: the bar is full
	var xp: float = 1.0 if picking else float(d.xp)
	var fill := Rect2(bar.position, Vector2(roundf(bar.size.x * xp), bar.size.y))
	if fill.size.x > 0.0:
		draw_rect(fill, RailArt.c(&"gold"))
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, roundf(3 * sc))), RailArt.c(&"gold_hi"))
		draw_rect(Rect2(Vector2(fill.position.x, fill.end.y - roundf(3 * sc)), Vector2(fill.size.x, roundf(3 * sc))), RailArt.c(&"gold_lo"))
	var tick := bar.position.x + 38 * sc
	while tick < bar.end.x - 2:
		draw_rect(Rect2(Vector2(roundf(tick), bar.position.y), Vector2(p, bar.size.y)), Color(RailArt.c(&"ink"), 0.5))
		tick += 38 * sc
	if picking:
		_num(_d(r, Vector2(486, 177)), "UP!", 18, RailArt.c(&"gold"))
	else:
		_num(_d(r, Vector2(486, 177)), "%d%%" % roundi(100.0 * xp), 18, RailArt.c(&"text"))
	var hint := String(d.get("hint", ""))
	var legend := String(d.get("legend", ""))
	if picking and legend != "":   # M50.4f: the open level-up's per-key legend
		# M50.7: never under the module's small text size (it shrank to 7 px); from the cell's left.
		var lx := _d(r, Vector2(12, 198)).x
		RailFrame.text(self, Vector2(lx, _d(r, Vector2(12, 198)).y), legend,
				maxi(RailLayout.text_px(12, sc), RailFrame.fit(legend, RailLayout.text_px(16, sc), r.end.x - lx - 8 * sc, false, 8)),
				RailArt.c(&"gold"))
	elif hint == "":
		_small(r, Vector2(bx, 198), "next level: pick 1 of 3", RailArt.c(&"gold"))
	else:   # M50.4c1: the evolve hint (pink when EVOLVE is ready, dim while ranking up)
		_small(r, Vector2(bx, 198), hint, RailArt.c(&"pink") if hint.begins_with("EVOLVE") else RailArt.c(&"dim"))


func _slot(r: Rect2, x: float, w: float, item: Dictionary, cap: int, passive: bool, new_well := false) -> void:
	var sc: float = frame.ms()
	var p: float = frame.mpx()
	var sr := Rect2(_d(r, Vector2(x, 36)), (Vector2(w, 120) * sc).round())
	# M50.4f (the sheet's FOCUS): the slot the focused choice changes lifts in a gold ring.
	var lift := bool(item.get("lift", false)) or new_well
	if lift:
		sr.position.y -= roundf(3 * sc)   # (a small lift: the ring stays under the cell's title)
		draw_rect(sr.grow(4 * p), RailArt.c(&"ink"))
		draw_rect(sr.grow(3 * p), RailArt.c(&"gold"))
	if item.is_empty():
		RailArt.bevel(self, sr, RailArt.c(&"sunk"), RailArt.c(&"ink"), RailArt.c(&"base"), p)
		RailFrame.text(self, sr.position + Vector2(0, 46 * sc), "+", RailLayout.text_px(24, sc),
				RailArt.c(&"gold") if new_well else RailArt.c(&"hi"), true, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x)
		if new_well:
			var fs0 := RailLayout.text_px(12, sc)
			var nw := RailFrame.text_w("NEW", fs0, true) + 6 * sc
			var nr := Rect2(Vector2(sr.position.x + 8 * sc, sr.position.y + 6 * sc), Vector2(nw, roundf(14 * sc)))
			RailArt.block(self, nr, RailArt.c(&"pink"), p)
			RailFrame.text(self, nr.position + Vector2(3 * sc, 0), "NEW", fs0, RailArt.c(&"ink"), true)
		return
	var rank := int(item.rank)
	var evo := bool(item.get("evo", false))   # M50.4c1: an evolution: gold ring, "EVO", no pips
	var maxed := rank >= cap and not evo
	RailArt.block(self, sr, RailArt.c(&"passive") if passive else RailArt.c(&"paper"), 2 * p, roundf(4 * sc),
			RailArt.c(&"passive_lo") if passive else RailArt.c(&"paper_lo"))
	if maxed and not passive:
		for side: Rect2 in [Rect2(sr.position, Vector2(sr.size.x, 2 * p)), Rect2(sr.position, Vector2(2 * p, sr.size.y)),
				Rect2(Vector2(sr.end.x - 2 * p, sr.position.y), Vector2(2 * p, sr.size.y))]:
			draw_rect(side, RailArt.c(&"gold"))
	if bool(item.get("evo_ring", false)):   # M50.4f: a focused EVOLVE would take this weapon
		draw_rect(sr.grow(-p), RailArt.c(&"pink"), false, 2 * p)
		draw_rect(sr.grow(4 * p), RailArt.c(&"pink"), false, 2 * p)
	if bool(item.get("cat_tick", false)):   # ... with this catalyst
		draw_rect(Rect2(sr.position + Vector2(0, -5 * p), Vector2(sr.size.x, 2 * p)), RailArt.c(&"pink"))
	var fs := RailLayout.text_px(12, sc)
	if evo:
		for k in 2:
			var g := sr.grow(-(k * 2 + 1) * p)
			draw_rect(g, RailArt.c(&"gold") if k == 0 else RailArt.c(&"gold_hi"), false, p)
		var ew := RailFrame.text_w("EVO", fs, true) + 6 * sc
		var er := Rect2(Vector2(sr.position.x + 8 * sc, sr.position.y + 6 * sc), Vector2(ew, roundf(14 * sc)))
		RailArt.block(self, er, RailArt.c(&"pink"), p)
		RailFrame.text(self, er.position + Vector2(3 * sc, 0), "EVO", fs, RailArt.c(&"ink"), true)
		WeaponGlyph.draw_card(self, item.icon, sr.position + Vector2(sr.size.x * 0.5, 46 * sc), roundf(minf(48.0, w - 12.0) * sc), Color.WHITE)
		var et := String(item.title).to_upper()
		RailFrame.text(self, sr.position + Vector2(0, 74 * sc), et, RailFrame.fit(et, RailLayout.text_px(16, sc), sr.size.x - 8 * sc, true, 8),
				RailArt.c(&"ink"), true, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x)
		return
	RailFrame.text(self, sr.position + Vector2(8, 6) * sc, "LV %d" % rank, fs, RailArt.c(&"passive_ink") if passive else RailArt.c(&"lv_ink"), true)
	if maxed:
		var mw := RailFrame.text_w("MAX", fs, true) + 6 * sc
		var mr := Rect2(Vector2(sr.end.x - 8 * sc - mw, sr.position.y + 6 * sc), Vector2(mw, roundf(14 * sc)))
		RailArt.block(self, mr, RailArt.c(&"gold"), p)
		RailFrame.text(self, mr.position + Vector2(3 * sc, 0), "MAX", fs, RailArt.c(&"ink"), true)
	WeaponGlyph.draw_card(self, item.icon, sr.position + Vector2(sr.size.x * 0.5, 44 * sc), roundf(minf(40.0, w - 16.0) * sc), Color.WHITE)
	var title: String = item.title
	RailFrame.text(self, sr.position + Vector2(0, 66 * sc), title, RailFrame.fit(title, RailLayout.text_px(16, sc), sr.size.x - 8 * sc, true, 8),
			RailArt.c(&"ink"), true, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x)
	var pip := roundf(10 * sc)
	var step := 14.0 * sc
	var x0 := sr.position.x + (sr.size.x - cap * step) * 0.5 + 2 * sc
	for k in cap:
		var on_pip := k < rank
		var col := (RailArt.c(&"warn") if passive else RailArt.c(&"gold")) if on_pip else RailArt.c(&"pip_off")
		var pr := Rect2(Vector2(roundf(x0 + k * step), roundf(sr.position.y + 96 * sc)), Vector2(pip, pip))
		if bool(item.get("next", false)) and k == rank:   # M50.4f: the pip this pick lights (a steady glow)
			draw_rect(pr.grow(3 * p), Color(RailArt.c(&"gold"), 0.45))
			RailArt.block(self, pr, RailArt.c(&"gold_hi"), p)
			continue
		RailArt.block(self, pr, col, p if on_pip else roundf(p * 0.5))


# --- Survival: AMMO ----------------------------------------------------------------------------

func _ammo(r: Rect2, d: Dictionary) -> void:
	var sc: float = frame.ms()
	var p: float = frame.mpx()
	_cell(r, "AMMO", "· scavenged")
	var cr := Rect2(_d(r, Vector2(12, 36)), (Vector2(160, 164) * sc).round())
	RailArt.block(self, cr, RailArt.c(&"paper"), 2 * p, roundf(4 * sc), RailArt.c(&"paper_lo"))
	RailFrame.text(self, cr.position + Vector2(8, 8) * sc, "weapon", RailLayout.text_px(12, sc), RailArt.c(&"hi"))
	var cap := int(d.cap)
	for k in cap:
		var on_pip := k < int(d.rank)
		RailArt.block(self, Rect2((cr.position + Vector2(160 - 8 - (cap - k) * 16, 6) * sc).round(), Vector2.ONE * roundf(12 * sc)),
				RailArt.c(&"gold") if on_pip else RailArt.c(&"pip_off"), p)
	if d.icon != &"":
		WeaponGlyph.draw(self, d.icon, cr.position + Vector2(80, 60) * sc, roundf(56 * sc), Color.WHITE)
	var title: String = d.title
	RailFrame.text(self, cr.position + Vector2(0, 92 * sc), title, RailFrame.fit(title, RailLayout.text_px(16, sc), cr.size.x - 10 * sc, true),
			RailArt.c(&"ink"), true, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	RailFrame.text(self, cr.position + Vector2(0, 118 * sc), "rank %d of %d" % [int(d.rank), cap], RailLayout.text_px(12, sc), RailArt.c(&"hi"), false, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	var mag := int(d.get("magazine", 0))
	var sub := "reloads" if mag > 0 else ("no reload" if int(d.total) > 0 else "never runs dry")
	RailFrame.text(self, cr.position + Vector2(0, 136 * sc), sub, RailLayout.text_px(12, sc), RailArt.c(&"hi"), false, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	var total := int(d.total)
	if mag > 0:
		# M48.5b (M47.6d1): the revolver's load, a round per pip; while it reloads, a fill.
		var reload := float(d.get("reload", -1.0))
		var left := 0 if reload >= 0.0 else int(d.mag)
		var aw := _num(_d(r, Vector2(192, 40)), str(left), 64, RailArt.c(&"gold") if reload < 0.0 else RailArt.c(&"dim"))
		_num(_d(r, Vector2(192, 40)) + Vector2(aw, _num_h(64) - _num_h(36)), "/%d" % mag, 36, RailArt.c(&"dim"))
		_small(r, Vector2(194, 102), "reloading" if reload >= 0.0 else "rounds · then it reloads")
		for i in mini(mag, 12):
			RailArt.block(self, Rect2(_d(r, Vector2(192.0 + i * 14.0 + 2, 120)), (Vector2(10, 16) * sc).round()),
					RailArt.c(&"warn") if i < left else RailArt.c(&"sunk"), p)
		if reload >= 0.0:
			var bar := Rect2(_d(r, Vector2(192, 142)), (Vector2(mini(mag, 12) * 14.0, 8) * sc).round())
			RailArt.block(self, bar, RailArt.c(&"sunk"), p)
			RailArt.block(self, Rect2(bar.position, Vector2(roundf(bar.size.x * reload), bar.size.y)), RailArt.c(&"gold"), p)
	elif total > 0:
		var aw := _num(_d(r, Vector2(192, 40)), str(int(d.left)), 64, RailArt.c(&"gold"))
		_num(_d(r, Vector2(192, 40)) + Vector2(aw, _num_h(64) - _num_h(36)), "/%d" % total, 36, RailArt.c(&"dim"))
		_small(r, Vector2(194, 102), "shells" if total <= 24 else "shells · 1 per %d rounds" % ceili(total / 24.0))
		var per := maxi(1, ceili(total / 24.0))
		var n := ceili(float(total) / per)
		var lit := ceili(float(int(d.left)) / per)
		for i in n:
			var sx := 192.0 + (i % 12) * 14.0
			var sy := 118.0 + floorf(i / 12.0) * 22.0
			RailArt.block(self, Rect2(_d(r, Vector2(sx + 2, sy + 2)), (Vector2(10, 16) * sc).round()),
					RailArt.c(&"warn") if i < lit else RailArt.c(&"sunk"), p)
	else:
		RailArt.draw_grid(self, RailArt.INFINITY, RailArt.INFINITY_LEGEND, _d(r, Vector2(196, 50)), roundf(6 * sc))
		_small(r, Vector2(194, 102), "the sidearm: no ammo to count")
	RailArt.draw_grid(self, RailArt.CRATE, RailArt.CRATE_LEGEND, _d(r, Vector2(384, 44)), roundf(4 * sc))
	RailFrame.text(self, _d(r, Vector2(428, 42)), "ammo crate", RailLayout.text_px(16, sc), RailArt.c(&"text"))
	RailFrame.text(self, _d(r, Vector2(384, 76)), "%d taken" % int(d.crates), RailLayout.text_px(16, sc), RailArt.c(&"dim"))
	if String(d.get("battery_title", "")) != "":
		# M51 review: the orbit's battery (Survival, S11): seconds left, or out until a pickup.
		var left := float(d.battery)
		var btxt := "%s · %d s" % [String(d.battery_title).to_lower(), ceili(left)] if left > 0.0 				else "%s · battery out" % String(d.battery_title).to_lower()
		RailFrame.text(self, _d(r, Vector2(384, 112)), btxt, RailLayout.text_px(16, sc),
				RailArt.c(&"warn") if left > 0.0 else RailArt.c(&"dim"))
	var row := Rect2(_d(r, Vector2(192, 168)), (Vector2(364, 32) * sc).round())
	RailArt.block(self, row, RailArt.c(&"base"), p)
	var fs := RailLayout.text_px(16, sc)
	var side := "+ %s" % String(d.sidearm)
	RailFrame.text(self, row.position + Vector2(10, 7) * sc, side, fs, RailArt.c(&"text"), true)
	RailArt.draw_grid(self, RailArt.INFINITY, RailArt.INFINITY_LEGEND, (row.position + Vector2(18 * sc + RailFrame.text_w(side, fs, true), 10 * sc)).round(), roundf(2 * sc))
	RailFrame.text(self, row.position + Vector2(0, 9 * sc), ("in hand · " if d.on_sidearm else "") + "sidearm · never runs dry  ",
			RailLayout.text_px(12, sc), RailArt.c(&"dim"), false, HORIZONTAL_ALIGNMENT_RIGHT, row.size.x)
