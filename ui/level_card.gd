class_name LevelCard
extends Control
## M50.4b (Auto depth design 7, the M50.4m sheet `Auto_Choices`): one dressed level-up card
## in the pick panel's non-pack mode (Auto's level-ups): a header with the kind (WEAPON,
## PASSIVE, BONUS) and the level badge ("LV 3 > 4", "NEW"), a window with the big glyph, the
## name plate, the rank pips (the path's cap, the new one lit), the effect line and, on an
## item, "pairs with <weapon>". Drawn in code, no image file.
##
## Two looks, as the sheet: with the Pixel UI revealed (Skins.is_on(ui_panel)) the plum-and-
## paper cards (CardArt / RailArt colours; a passive on peach); else the flat tier-0 card
## (Palette roles: the face, a cyan or orange edge). The key chip under the card is the
## player's key for it (choose_n). Presentation only: it reads the card's dictionary and
## WeaponDB, never the simulation.
##
## M50.4c1 (the sheet's third card): the EVOLVE choice (data_for_evolve), a wider card in the gold
## `card_evolve` frame: an EVOLVE ribbon, the two parents (the maxed weapon and its catalyst) with
## a "+" and merge arrows, a window with the evolution's gun, its gold name plate and one line.
## Steady: no pulse, so reduce flashing has nothing to hold back.
##
## M50.4f (the cards match the sheet): the Pixel window draws the big card art at the window's
## own scale on the sheet's backdrop (a floor band, stars, the laser's beam); a MAX card (the
## path's last rank) wears a gold tag and a gold ring; tall pips mark the mechanic ranks (flat:
## diamonds); the effect line leads with the mechanic's icon and bold name; an item's pair row
## shows the paired gun and READY when EVOLVE is on offer; the focused card's key reads
## "focused"; the flat cards draw flat guns. Still steady: nothing pulses.

const SIZE := Vector2(232, 356)    ## the card (316) and its key row (40: clear of the focus ring)
const CARD_H := 316.0
const PIP_W := 22.0
const KIND_WEAPON := &"weapon"
const KIND_ITEM := &"item"
const KIND_FILLER := &"filler"
const KIND_EVOLVE := &"evolve"
const SIZE_EVO := Vector2(264, 356)   ## M50.4c1: the EVOLVE card (the sheet's 256 + its gold rim)
const EFFECT_PX := 16      ## M50.4f: the Pixel effect line (the sheet's 16 px)
const EFFECT_FLAT := 15    ## M50.4f: the flat effect line

## {kind, kind_label, title, icon, from, to, cap, new, max, effect, mech, mech_name, pair,
## pair_icon, paired, ready, key}
var data := {}
var pixel := false

static var _bold_flat: FontVariation


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = card_size()
	var b := get_parent() as Button
	if b != null:
		b.focus_entered.connect(queue_redraw)
		b.focus_exited.connect(queue_redraw)


## The card's dictionary for offer card `card` (PickOffer's) on a path capped at `cap`, with
## `key` its key label. The texts come from the defs, never from card.text (that stays the
## plain panel's and the logs'). M50.4f: `evolve` is the offer's EVOLVE choice ({} none): an
## item that is its catalyst reads READY.
static func data_for(card: Dictionary, cap: int, key: String, evolve := {}) -> Dictionary:
	var d := {"kind": KIND_WEAPON, "kind_label": "WEAPON", "title": "", "icon": &"", "from": 0,
			"to": int(card.get("rank", 1)), "cap": maxi(1, cap), "new": card.get("kind") == &"new",
			"max": false, "effect": String(card.get("text", "")), "mech": &"", "mech_name": "",
			"pair": "", "pair_icon": &"", "paired": false, "ready": false, "key": key}
	var kind: StringName = card.get("kind", &"")
	if kind == PickOffer.HP or kind == PickOffer.BOOST:
		d.kind = KIND_FILLER
		d.kind_label = "BONUS"
		d.new = false
		d.icon = &"hp" if kind == PickOffer.HP else &"boost"
		d.title = "+1 MAX HP" if kind == PickOffer.HP else "+%d%% DAMAGE" % roundi(Loadout.BOOST_STEP * 100.0)
		d.effect = "Heal 1 and +1 max HP, this session." if kind == PickOffer.HP \
				else "Every gun hits a little harder, this session. Stacks."
		d.cap = 0
		return d
	d.from = 0 if d.new else int(d.to) - 1
	d.max = not d.new and cap > 0 and int(d.to) >= cap   # M50.4f: the last rank (the sheet's MAX)
	if card.get("item", false):
		var it := WeaponDB.item(card.id)
		if it == null:
			return d
		d.kind = KIND_ITEM
		d.kind_label = "PASSIVE"
		d.title = it.title
		d.icon = it.icon
		d.effect = it.effect(int(d.to)) + ("" if d.new else " (was %s)" % it.pct(int(d.from)))
		var w := WeaponDB.get_weapon(it.pairs)
		d.pair = "pairs with %s" % (w.title if w != null else String(it.pairs))
		d.pair_icon = w.icon if w != null else &""
		d.paired = bool(card.get("paired", false))
		d.ready = d.paired and StringName(evolve.get("catalyst", &"")) == StringName(card.id)
		return d
	var wd := WeaponDB.get_weapon(card.id)
	if wd == null:
		return d
	d.title = wd.title
	d.icon = wd.icon
	if d.new:
		d.effect = wd.card_text[0] if not wd.card_text.is_empty() else wd.pitch
	elif cap > Loadout.MAX_RANK:
		var gain := WeaponCurve.gain_text(wd, int(d.from), int(d.to))
		d.effect = gain if gain != "" else "rank %d" % int(d.to)
	elif int(d.to) - 1 < wd.card_text.size():
		d.effect = wd.card_text[int(d.to) - 1]
	if not d.new:
		d.mech = gained_mechanic(wd, int(d.from), int(d.to), cap > Loadout.MAX_RANK)
		d.mech_name = String(d.mech).replace("_", " ").capitalize() if d.mech != &"" else ""
	return d


## M50.4f: the mechanic a rank-up from `from` to `to` unlocks or strengthens (&"" none): on the
## deep curve the first whose level moves, on the classic curve the new rank's first trait.
static func gained_mechanic(wd: WeaponDef, from: int, to: int, deep: bool) -> StringName:
	if not deep:
		var t := wd.traits_at(to)
		return t[0] if not t.is_empty() else &""
	var mech := WeaponCurve.mechanics(wd)
	var a := WeaponCurve.levels_of(wd, from)
	var b := WeaponCurve.levels_of(wd, to)
	for i in mech.size():
		if i < a.size() and i < b.size() and a[i] != b[i] and WeaponCurve.built(mech[i]):
			return mech[i]
	return &""


## M50.4f: rank `k` (1-based) of a weapon card brings a mechanic: the tall pip (flat: a diamond).
## The deep curve's even ranks (WeaponCurve.gain_text's), the classic curve's ranks 2-3.
func mechanic_rank(k: int) -> bool:
	if data.get("kind") != KIND_WEAPON:
		return false
	if int(data.cap) > Loadout.MAX_RANK:
		return k % 2 == 0
	return k >= 2


## M50.4c1: the EVOLVE choice's dictionary from PickOffer.evolve ({from, into, catalyst, rank}).
static func data_for_evolve(ev: Dictionary, key: String) -> Dictionary:
	var d := {"kind": KIND_EVOLVE, "kind_label": "EVOLVE", "title": "", "icon": &"", "from": 0, "to": 0,
			"cap": 0, "new": false, "max": false, "effect": "", "pair": "", "paired": true, "key": key,
			"key_word": "evolve", "from_title": "", "from_icon": &"", "rank": int(ev.get("rank", 0)),
			"item_title": "", "item_icon": &""}
	var into := WeaponDB.get_weapon(ev.get("into", &""))
	var base := WeaponDB.get_weapon(ev.get("from", &""))
	var it := WeaponDB.item(ev.get("catalyst", &""))
	if into == null or base == null or it == null:
		return d
	d.title = into.title
	d.icon = into.icon
	d.from_title = base.title
	d.from_icon = base.icon
	d.item_title = it.title
	d.item_icon = it.icon
	var before := PathRunner.fire_rate(float(WeaponCurve.value(base, &"cooldown", int(d.rank))))
	var after := PathRunner.fire_rate(into.cooldown)
	d.effect = "fire rate x%s, a sweeping stream" % WeaponCurve.num(snappedf(after / maxf(0.1, before), 0.5)) \
			if after > before * 1.2 and &"sweep" in into.mechanics else into.pitch   # M50.4c2: the others' pitch
	return d


## The card's size (the EVOLVE card is wider).
func card_size() -> Vector2:
	return SIZE_EVO if data.get("kind") == KIND_EVOLVE else SIZE


func set_card(p_data: Dictionary, p_pixel: bool) -> void:
	data = p_data
	pixel = p_pixel
	queue_redraw()


func _focused() -> bool:
	var b := get_parent() as Button
	return b != null and b.has_focus() and not b.disabled


## M50.4f: the word under the card: "focused" on the focused card, else its own ("choose",
## EVOLVE's "evolve").
func key_word() -> String:
	var own := String(data.get("key_word", "choose"))
	if data.get("kind") == KIND_EVOLVE:
		return own
	return "focused" if _focused() else own


func _draw() -> void:
	if data.is_empty():
		return
	if data.kind == KIND_EVOLVE:
		if pixel:
			_draw_evolve_pixel()
		else:
			_draw_evolve_flat()
		return
	if pixel:
		_draw_pixel()
	else:
		_draw_flat()


# --- Pixel (the sheet's top half) ----------------------------------------------------------

func _draw_pixel() -> void:
	var item: bool = data.kind == KIND_ITEM
	var r := Rect2(Vector2(4, 4), Vector2(SIZE.x - 8, CARD_H - 8))
	var focused := _focused()
	var maxed := bool(data.get("max", false))
	if focused:
		draw_rect(r.grow(12), CardArt.c(&"ink"))
		draw_rect(r.grow(8), CardArt.c(&"gold"))
	elif maxed:   # M50.4f: the MAX card's gold ring
		draw_rect(r.grow(10), CardArt.c(&"ink"))
		draw_rect(r.grow(7), CardArt.c(&"gold"))
	var face := CardArt.c(&"passive") if item else CardArt.c(&"paper")
	var lip := CardArt.c(&"passive_lo") if item else CardArt.c(&"paper_lo")
	RailArt.block(self, r, face, 4.0, 6.0, lip)
	# Header: the kind, a NEW or MAX tag, the level badge.
	var head := Rect2(r.position, Vector2(r.size.x, 32))
	draw_rect(head, CardArt.c(&"base"))
	draw_rect(Rect2(Vector2(head.position.x, head.end.y - 4), Vector2(head.size.x, 4)), CardArt.c(&"ink"))
	var kx := head.position.x + 10
	var tag := "NEW" if data.new else ("MAX" if maxed else "")
	if tag != "":
		var tw := RailFrame.text_w(tag, 12, true) + 10
		RailArt.block(self, Rect2(Vector2(kx, head.position.y + 7), Vector2(tw, 16)),
				CardArt.c(&"pink") if data.new else CardArt.c(&"gold"), 2.0)
		RailFrame.text(self, Vector2(kx + 5, head.position.y + 8), tag, 12, CardArt.c(&"ink"), true)
		kx += tw + 8
	RailFrame.text(self, Vector2(kx, head.position.y + 9), data.kind_label, 11,
			CardArt.c(&"warn") if item else CardArt.c(&"gold"), true)
	var badge := _badge_text()
	if badge != "":
		var bw := RailFrame.text_w(badge, 14, true) + 12
		var br := Rect2(Vector2(head.end.x - 8 - bw, head.position.y + 5), Vector2(bw, 20))
		draw_rect(br, CardArt.c(&"ink"))
		RailFrame.text(self, br.position + Vector2(6, 2), badge, 14, CardArt.c(&"gold") if data.new or data.cap == 0 or maxed \
				else CardArt.c(&"paper"), true)
	# The window: the sheet's backdrop, then the big card art at the window's own scale.
	var win := Rect2(r.position + Vector2(10, 42), Vector2(r.size.x - 20, 106))
	RailArt.block(self, win, CardArt.c(&"sunk") if not item else CardArt.c(&"base"), 4.0)
	_backdrop(win, item)
	_card_art(win, data.icon, item)
	# The name plate.
	var plate := Rect2(Vector2(r.position.x + 20, win.end.y + 12), Vector2(r.size.x - 40, 28))
	RailArt.block(self, plate, CardArt.c(&"paper"), 4.0, 4.0, CardArt.c(&"paper_lo"))
	var title := String(data.title).to_upper()
	RailFrame.text(self, plate.position + Vector2(0, 4), title, RailFrame.fit(title, 16, plate.size.x - 8, true, 9),
			CardArt.c(&"ink"), true, HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)
	# Pips, the effect, the pair row.
	var y := plate.end.y + 10
	if int(data.cap) > 0:
		_pips_pixel(Vector2(r.position.x, y), r.size.x, item)
		y += 29
	else:
		y += 6
	var ink := CardArt.c(&"ink")
	var has_pair := String(data.pair) != ""
	var lines := 2 if has_pair else 3
	var bottom := r.end.y - 40 if has_pair else r.end.y - 22   # the pair row, or the legend
	var tx := r.position.x + 12
	if data.get("mech", &"") != &"":
		CardArt.draw_mech(self, data.mech, Vector2(tx + 3, y + 3), 3.0)
		tx += 34
	_paragraph(String(data.get("mech_name", "")), effect_body(), Vector2(tx, y), r.end.x - 12 - tx, lines,
			EFFECT_PX, 11, ink, UiTheme.pixel_font(false), UiTheme.pixel_font(true), HORIZONTAL_ALIGNMENT_LEFT, bottom - y - 4)
	if has_pair:
		_pair_pixel(Rect2(Vector2(r.position.x + 10, r.end.y - 36), Vector2(r.size.x - 20, 26)))
	elif focused and data.kind == KIND_WEAPON and int(data.cap) > 0:   # the sheet's legend
		RailFrame.text(self, Vector2(r.position.x + 12, r.end.y - 18), "tall pips = new mechanic", 9,
				CardArt.c(&"note_dim"), true)
	_key_row(CardArt.c(&"gold") if focused else CardArt.c(&"key"), ink,
			CardArt.c(&"gold") if focused else CardArt.c(&"dim"), true, SIZE.x,
			CardArt.c(&"gold_lo") if focused else CardArt.c(&"key_lo"))


## M50.4f: the sheet's window backdrop: the lower floor band, two faint stars and a gold one; a
## passive's window has the faint centre column instead of the floor.
func _backdrop(win: Rect2, item: bool) -> void:
	if item:
		var col := Rect2(Vector2(win.get_center().x - win.size.x * 0.16, win.position.y), Vector2(win.size.x * 0.32, win.size.y))
		draw_rect(col, Color(CardArt.c(&"cell"), 0.6))
		return
	var band := roundf(win.size.y * 12.0 / 34.0)
	var floor_r := Rect2(Vector2(win.position.x, win.end.y - band), Vector2(win.size.x, band))
	draw_rect(floor_r, CardArt.c(&"lo"))
	draw_rect(Rect2(floor_r.position, Vector2(floor_r.size.x, 4)), CardArt.c(&"cell"))
	draw_rect(Rect2(win.position + Vector2(18, 14), Vector2(4, 4)), CardArt.c(&"hi"))
	draw_rect(Rect2(Vector2(win.end.x - 30, win.position.y + 22), Vector2(4, 4)), CardArt.c(&"hi"))
	draw_rect(Rect2(Vector2(win.end.x - 58, win.position.y + 8), Vector2(4, 4)), CardArt.c(&"gold"))


## M50.4f: the card art in `win`: a gun or item grid at the window's scale (CardArt.draw_card_art),
## the laser's beam out of the muzzle, Haste's speed lines; a key without a grid keeps its glyph.
func _card_art(win: Rect2, icon: StringName, item: bool) -> void:
	var box := win.size - Vector2(16, 8)
	var art := CardArt.draw_card_art(self, icon, win.get_center(), box) if Skins.current != null else Rect2()
	if art.size == Vector2.ZERO:
		WeaponGlyph.draw_card(self, icon, win.get_center(), minf(win.size.y - 12.0, 92.0), Color.WHITE)
		return
	var grid: Array = (CardArt.GUNS.get(icon, CardArt.GLYPHS.get(icon, [[""]])) as Array)[0]
	var px := art.size.y / maxf(1.0, grid.size())
	if CardArt.MUZZLE_ROW.has(icon):   # the beam leaving the muzzle (the sheet's laser)
		var by := art.position.y + (int(CardArt.MUZZLE_ROW[icon]) - 0.5) * px
		var bx := art.end.x + px
		if bx < win.end.x:
			draw_rect(Rect2(Vector2(bx, by), Vector2(win.end.x - bx, px * 2.0)), Color(CardArt.c(&"pink"), 0.55))
			draw_rect(Rect2(Vector2(bx, by + px * 0.5), Vector2(win.end.x - bx, maxf(2.0, px * 0.6))), CardArt.c(&"pink_hi"))
	if item and icon == &"haste":   # the sheet's speed lines
		for k in 4:
			var ly := art.position.y + art.size.y * (0.25 + 0.17 * k)
			var lw := px * (4.0 + (k % 2) * 2.0)
			var lx := art.position.x - px * 2.0 - lw + (k % 2) * px * 2.0
			if lx > win.position.x + 2:
				draw_rect(Rect2(Vector2(lx, ly), Vector2(lw, maxf(2.0, px * 0.6))), CardArt.c(&"warn"))


func _pips_pixel(at: Vector2, width: float, item: bool) -> void:
	var cap := int(data.cap)
	var step := minf(PIP_W + 8.0, (width - 20.0) / cap)
	var pw := step - 8.0
	var x0 := at.x + (width - cap * step + 8.0) * 0.5
	var maxed := bool(data.get("max", false))
	for k in cap:
		var lit := k < int(data.to)
		var fresh := k == int(data.to) - 1
		var h := 20.0 if mechanic_rank(k + 1) else 13.0   # M50.4f: tall = a mechanic rank
		var pr := Rect2(Vector2(roundf(x0 + k * step), at.y + 20.0 - h), Vector2(pw, h))
		if not lit:
			draw_rect(pr.grow(2), CardArt.c(&"pip_off_lo"))
			draw_rect(pr, CardArt.c(&"pip_off"))
			continue
		var fill := CardArt.c(&"warn") if item else CardArt.c(&"gold")
		if fresh and not maxed:   # the new one glows (steady)
			draw_rect(pr.grow(9), Color(CardArt.c(&"gold"), 0.3))
			draw_rect(pr.grow(6), CardArt.c(&"warn") if not item else CardArt.c(&"gold"))
			fill = CardArt.c(&"gold_hi")
		RailArt.block(self, pr, fill, 3.0, 3.0, CardArt.c(&"warn_lo") if item else CardArt.c(&"gold_lo"))


## M50.4f: the item's pair row (the sheet's Haste card): the paired gun, "pairs with Pistol" and,
## when its EVOLVE is on offer, the pink READY tag.
func _pair_pixel(pr: Rect2) -> void:
	RailArt.block(self, pr, CardArt.c(&"paper"), 3.0)
	var x := pr.position.x + 8
	if data.get("pair_icon", &"") != &"" and Skins.current != null:
		var art := CardArt.draw_card_art(self, data.pair_icon, Vector2(x + 18, pr.get_center().y), Vector2(44, 28), 3.0)
		if art.size == Vector2.ZERO:
			WeaponGlyph.draw(self, data.pair_icon, Vector2(x + 18, pr.get_center().y), 24.0, CardArt.c(&"ink"))
		x += 42
	var ready := bool(data.get("ready", false))
	var rw := RailFrame.text_w("READY", 10, true) + 8 if ready else 0.0
	var col := CardArt.c(&"ink") if data.paired else CardArt.c(&"note_dim")
	var t := String(data.pair)
	RailFrame.text(self, Vector2(x, pr.position.y + 6), t, RailFrame.fit(t, 14, pr.end.x - x - rw - 10, false, 8), col)
	if ready:
		var rr := Rect2(Vector2(pr.end.x - rw - 4, pr.position.y - 9), Vector2(rw, 14))
		RailArt.block(self, rr, CardArt.c(&"pink"), 2.0)
		RailFrame.text(self, rr.position + Vector2(4, 1), "READY", 10, CardArt.c(&"ink"), true)


# --- Flat (the sheet's bottom half: S7-S8, before the art patch) -----------------------------

func _draw_flat() -> void:
	var item: bool = data.kind == KIND_ITEM
	var maxed := bool(data.get("max", false))
	var focused := _focused()
	var edge := Palette.color(&"card_item") if item else Palette.color(&"info")
	if data.kind == KIND_FILLER:
		edge = Palette.color(&"card_lit")
	var rim := Palette.color(&"card_evolve") if maxed else edge   # M50.4f: MAX's gold edge
	var r := Rect2(Vector2(4, 4), Vector2(SIZE.x - 8, CARD_H - 8))
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.color(&"ui_panel")
	box.border_color = rim if focused or maxed else Color(rim, 0.55)
	box.set_border_width_all(4 if focused else (3 if maxed else 2))
	box.set_corner_radius_all(14)
	draw_style_box(box, r)
	var text := Palette.color(&"ui_text")
	var dim := Palette.color(&"ui_dim")
	var font := ThemeDB.fallback_font
	draw_string(font, r.position + Vector2(16, 26), data.kind_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, edge)
	var badge := _badge_text()
	if badge != "":
		var bw := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 16
		var pill := StyleBoxFlat.new()
		pill.bg_color = Color(Palette.color(&"shadow"), 0.45)
		pill.set_corner_radius_all(6)
		var br := Rect2(Vector2(r.end.x - 12 - bw, r.position.y + 10), Vector2(bw, 22))
		draw_style_box(pill, br)
		draw_string(font, br.position + Vector2(8, 16), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text)
	if data.new or maxed:
		var tag := StyleBoxFlat.new()
		tag.bg_color = Palette.color(&"hit") if data.new else Palette.color(&"card_evolve")
		tag.set_corner_radius_all(8)
		var tr := Rect2(r.position + Vector2(90, 10), Vector2(46, 20))
		draw_style_box(tag, tr)
		draw_string(font, tr.position + Vector2(0, 15), "NEW" if data.new else "MAX", HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 12,
				text if data.new else Palette.color(&"shadow"))
	var win := Rect2(r.position + Vector2(14, 42), Vector2(r.size.x - 28, 106))
	var wbox := StyleBoxFlat.new()
	wbox.bg_color = Color(Palette.color(&"shadow"), 0.35)
	wbox.set_corner_radius_all(10)
	draw_style_box(wbox, win)
	var gun: bool = data.icon in WeaponGlyph.FLAT_GUNS
	WeaponGlyph.draw_card_flat(self, data.icon, win.get_center(), 150.0 if gun else 80.0, edge)
	draw_string(font, Vector2(r.position.x, win.end.y + 32), data.title, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22, text)
	var y := win.end.y + 46
	if int(data.cap) > 0:
		var cap := int(data.cap)
		var step := minf(22.0, (r.size.x - 40.0) / cap)
		var x0 := r.position.x + (r.size.x - (cap - 1) * step) * 0.5
		var lit_col := rim if maxed else edge
		for k in cap:
			var c := Vector2(x0 + k * step, y + 6)
			var lit := k < int(data.to)
			if k == int(data.to) - 1 and not maxed:
				draw_circle(c, 10.0, Color(edge, 0.35))
			var col := lit_col if lit else Color(dim, 0.25)
			if mechanic_rank(k + 1):   # M50.4f: a mechanic rank is a diamond
				var s := 7.5 if lit else 6.5
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s),
						c + Vector2(-s, 0)]), col)
			else:
				draw_circle(c, 6.0 if lit else 5.0, col)
		y += 24
	var has_pair := String(data.pair) != ""
	var tx := r.position.x + 14
	if data.get("mech", &"") != &"":
		_mech_flat(Vector2(tx + 10, y + 12))
		tx += 26
	_paragraph(String(data.get("mech_name", "")), effect_body(), Vector2(tx, y + 2), r.end.x - 12 - tx,
			2 if has_pair else 3, EFFECT_FLAT, 11, text, font, _flat_bold(),
			HORIZONTAL_ALIGNMENT_CENTER if data.get("mech", &"") == &"" else HORIZONTAL_ALIGNMENT_LEFT)
	if has_pair:
		_pair_flat(Rect2(Vector2(r.position.x + 12, r.end.y - 40), Vector2(r.size.x - 24, 28)), edge)
	_key_row(Palette.color(&"info") if focused else edge, Palette.color(&"shadow"),
			Palette.color(&"info") if focused else dim, false)


## M50.4f: the flat mechanic icon (the sheet's pink beam with a gold cross), one shape for all.
func _mech_flat(c: Vector2) -> void:
	draw_rect(Rect2(c + Vector2(-10, -2), Vector2(20, 4)), Palette.color(&"hit"))
	draw_rect(Rect2(c + Vector2(2, -9), Vector2(3, 18)), Palette.color(&"card_evolve"))
	draw_rect(Rect2(c + Vector2(-2, -9), Vector2(11, 3)), Palette.color(&"card_evolve"))
	draw_rect(Rect2(c + Vector2(-2, 6), Vector2(11, 3)), Palette.color(&"card_evolve"))


## M50.4f: the flat pair pill: the paired gun, "pairs with Pistol", a READY pill.
func _pair_flat(pr: Rect2, edge: Color) -> void:
	var font := ThemeDB.fallback_font
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(Palette.color(&"shadow"), 0.4)
	pill.set_corner_radius_all(10)
	draw_style_box(pill, pr)
	var x := pr.position.x + 8
	if data.get("pair_icon", &"") != &"":
		WeaponGlyph.draw_card_flat(self, data.pair_icon, Vector2(x + 14, pr.get_center().y), 30.0, edge)
		x += 34
	var ready := bool(data.get("ready", false))
	var rw := font.get_string_size("READY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14 if ready else 0.0
	var fs := 13
	while fs > 9 and font.get_string_size(data.pair, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > pr.end.x - x - rw - 8:
		fs -= 1
	draw_string(font, Vector2(x, pr.position.y + 19), data.pair, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Palette.color(&"ui_text") if data.paired else Palette.color(&"ui_dim"))
	if ready:
		var rr := Rect2(Vector2(pr.end.x - rw - 5, pr.position.y + 5), Vector2(rw, 18))
		var rb := StyleBoxFlat.new()
		rb.bg_color = Palette.color(&"hit")
		rb.set_corner_radius_all(9)
		draw_style_box(rb, rr)
		draw_string(font, rr.position + Vector2(0, 13), "READY", HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 11, Palette.color(&"ui_text"))


static func _flat_bold() -> Font:
	if _bold_flat == null:
		_bold_flat = FontVariation.new()
		_bold_flat.base_font = ThemeDB.fallback_font
		_bold_flat.variation_embolden = 0.9
	return _bold_flat


# --- EVOLVE (M50.4c1, the sheet's third card) ---------------------------------------------------

func _draw_evolve_pixel() -> void:
	var w := SIZE_EVO.x
	var r := Rect2(Vector2(12, 20), Vector2(w - 24, CARD_H - 22))
	var ink := CardArt.c(&"ink")
	var gold := Palette.color(&"card_evolve") if Skins.current == null else CardArt.c(&"gold")
	if _focused():   # M50.4f: a full 4 px ring outside the gold rim (the ribbon cannot hide it)
		draw_rect(r.grow(22), ink)
		draw_rect(r.grow(18), CardArt.c(&"pink"))
		draw_rect(Rect2(r.grow(18).position + Vector2(0, 4), Vector2(r.grow(18).size.x, 4)), CardArt.c(&"pink_hi"))
	draw_rect(r.grow(14), ink)
	draw_rect(r.grow(12), ink)
	draw_rect(r.grow(8), gold)
	draw_rect(r.grow(4), ink)
	draw_rect(r, CardArt.c(&"base"))
	# The faint cross of the sheet's back and its four gold studs (below the line).
	draw_rect(Rect2(Vector2(r.get_center().x - 8, r.position.y), Vector2(16, r.size.y)), CardArt.c(&"cell"))
	for k in 4:
		var corner := Vector2(r.position.x + 8 + (r.size.x - 24) * (k % 2), r.position.y + 8 + (r.size.y - 18) * (k / 2))
		draw_rect(Rect2(corner, Vector2(8, 8)), gold)
	# The ribbon.
	for side in 2:
		var tail := Rect2(Vector2(r.position.x - 14 if side == 0 else r.end.x, r.position.y - 14), Vector2(14, 36))
		RailArt.block(self, tail, CardArt.c(&"passive_ink"), 4.0)
	var rib := Rect2(Vector2(r.position.x - 6, r.position.y - 20), Vector2(r.size.x + 12, 40))
	RailArt.block(self, rib, CardArt.c(&"pink"), 4.0, 6.0, CardArt.c(&"passive_ink"))
	draw_rect(Rect2(rib.position + Vector2(0, 4), Vector2(rib.size.x, 4)), CardArt.c(&"pink_hi"))
	RailFrame.text(self, rib.position + Vector2(2, 8), "EVOLVE", 24, ink, true, HORIZONTAL_ALIGNMENT_CENTER, rib.size.x)
	RailFrame.text(self, rib.position + Vector2(0, 6), "EVOLVE", 24, CardArt.c(&"paper"), true, HORIZONTAL_ALIGNMENT_CENTER, rib.size.x)
	# The parents: the maxed weapon + its catalyst.
	var pw := 76.0
	var a := Rect2(Vector2(r.position.x + 16, r.position.y + 30), Vector2(pw, 50))
	var b := Rect2(Vector2(r.end.x - 16 - pw, r.position.y + 30), Vector2(pw, 50))
	RailArt.block(self, a, CardArt.c(&"paper"), 4.0)
	draw_rect(Rect2(a.position + Vector2(4, 4), Vector2(a.size.x - 8, 3)), gold)
	RailArt.block(self, b, CardArt.c(&"passive"), 4.0)
	draw_rect(Rect2(b.position + Vector2(4, 4), Vector2(b.size.x - 8, 3)), CardArt.c(&"warn"))
	if CardArt.draw_card_art(self, data.from_icon, a.position + Vector2(pw * 0.5, 21), Vector2(60, 30), 3.0).size == Vector2.ZERO:
		WeaponGlyph.draw_card(self, data.from_icon, a.position + Vector2(pw * 0.5, 20), 34.0, Color.WHITE)
	WeaponGlyph.draw(self, data.item_icon, b.position + Vector2(pw * 0.5, 20), 30.0, CardArt.c(&"warn"))
	var fl := "%s %d MAX" % [String(data.from_title).to_upper(), int(data.rank)]
	RailFrame.text(self, a.position + Vector2(0, 36), fl, RailFrame.fit(fl, 10, pw - 4, true, 7), ink, true,
			HORIZONTAL_ALIGNMENT_CENTER, pw)
	RailFrame.text(self, b.position + Vector2(0, 36), String(data.item_title).to_upper(), 10, ink, true,
			HORIZONTAL_ALIGNMENT_CENTER, pw)
	RailFrame.text(self, Vector2(r.get_center().x - 16, r.position.y + 30), "+", 40, gold, true,
			HORIZONTAL_ALIGNMENT_CENTER, 32)
	# The merge arrows (gold from the weapon, orange from the item, a bright spark between).
	var mid := Vector2(r.get_center().x, r.position.y + 96)
	for k in 3:
		draw_rect(Rect2(Vector2(a.get_center().x + 8 + k * 14, r.position.y + 84 + k * 5), Vector2(14, 5)), gold)
		draw_rect(Rect2(Vector2(b.get_center().x - 22 - k * 14, r.position.y + 84 + k * 5), Vector2(14, 5)), CardArt.c(&"warn"))
	draw_rect(Rect2(mid + Vector2(-14, -4), Vector2(28, 8)), CardArt.c(&"gold_hi"))
	# The window: ink with the sheet's floor band and stars, the evolution's gun at the window's scale.
	var win := Rect2(Vector2(r.position.x + 8, r.position.y + 110), Vector2(r.size.x - 16, 104))
	draw_rect(win.grow(8), ink)
	draw_rect(win.grow(4), gold)
	draw_rect(win, ink)
	var band := roundf(win.size.y / 3.0)
	draw_rect(Rect2(Vector2(win.position.x, win.end.y - band), Vector2(win.size.x, band)), CardArt.c(&"base"))
	draw_rect(Rect2(Vector2(win.position.x, win.end.y - band), Vector2(win.size.x, 4)), CardArt.c(&"cell"))
	for s: Array in [[Vector2(14, 14), &"gold"], [Vector2(win.size.x - 22, 20), &"gold"], [Vector2(28, win.size.y - 18), &"warn"],
			[Vector2(win.size.x - 36, win.size.y - 22), &"warn"], [Vector2(win.size.x * 0.5 + 60, 10), &"lo"]]:
		draw_rect(Rect2(win.position + (s[0] as Vector2), Vector2(4, 4)), CardArt.c(s[1]))
	if CardArt.draw_card_art(self, data.icon, win.get_center(), win.size / 0.9, 5.0).size == Vector2.ZERO:
		WeaponGlyph.draw_card(self, data.icon, win.get_center(), 100.0, Color.WHITE)
	# The name plate and the line (up to two lines, inside the studs).
	var plate := Rect2(Vector2(r.position.x + 28, win.end.y + 14), Vector2(r.size.x - 56, 26))
	RailArt.block(self, plate, gold, 4.0, 5.0, CardArt.c(&"gold_lo"))
	draw_rect(Rect2(plate.position, Vector2(plate.size.x, 4)), CardArt.c(&"gold_hi"))
	var title := String(data.title).to_upper()
	RailFrame.text(self, plate.position + Vector2(0, 4), title, RailFrame.fit(title, 16, plate.size.x - 8, true, 9), ink, true,
			HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)
	_paragraph("", String(data.effect), Vector2(r.position.x + 22, plate.end.y + 8), r.size.x - 44, 2, 14, 10,
			CardArt.c(&"paper"), UiTheme.pixel_font(false), UiTheme.pixel_font(true), HORIZONTAL_ALIGNMENT_CENTER)
	_key_row(CardArt.c(&"gold"), ink, CardArt.c(&"gold"), true, w, CardArt.c(&"gold_lo"))


func _draw_evolve_flat() -> void:
	var w := SIZE_EVO.x
	var gold := Palette.color(&"card_evolve")
	var r := Rect2(Vector2(8, 14), Vector2(w - 16, CARD_H - 14))
	if _focused():   # M50.4f: a pink ring outside the gold rim
		var ring := StyleBoxFlat.new()
		ring.bg_color = Color(gold, 0.0)
		ring.border_color = Palette.color(&"hit")
		ring.set_border_width_all(4)
		ring.set_corner_radius_all(22)
		draw_style_box(ring, r.grow(6))
	var rim := StyleBoxFlat.new()
	rim.bg_color = gold if _focused() else Color(gold, 0.85)
	rim.set_corner_radius_all(18)
	draw_style_box(rim, r)
	var face := StyleBoxFlat.new()
	face.bg_color = Palette.color(&"ui_panel")
	face.set_corner_radius_all(15)
	draw_style_box(face, r.grow(-3))
	var text := Palette.color(&"ui_text")
	var font := ThemeDB.fallback_font
	var pill := StyleBoxFlat.new()
	pill.bg_color = gold
	pill.set_corner_radius_all(15)
	var pr := Rect2(Vector2(w * 0.5 - 70, r.position.y - 14), Vector2(140, 30))
	draw_style_box(pill, pr)
	draw_string(font, pr.position + Vector2(0, 21), "EVOLVE", HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, 16, Palette.color(&"shadow"))
	var pw := 74.0
	var a := Rect2(Vector2(r.position.x + 22, r.position.y + 30), Vector2(pw, 56))
	var b := Rect2(Vector2(r.end.x - 22 - pw, r.position.y + 30), Vector2(pw, 56))
	for pair: Array in [[a, gold, data.from_icon, "%s %d MAX" % [String(data.from_title).to_upper(), int(data.rank)]],
			[b, Palette.color(&"card_item"), data.item_icon, String(data.item_title).to_upper()]]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(Palette.color(&"shadow"), 0.4)
		box.border_color = pair[1]
		box.set_border_width_all(2)
		box.set_corner_radius_all(12)
		draw_style_box(box, pair[0])
		var gun := StringName(pair[2]) in WeaponGlyph.FLAT_GUNS
		WeaponGlyph.draw_card_flat(self, pair[2], (pair[0] as Rect2).position + Vector2(pw * 0.5, 20), 46.0 if gun else 28.0, pair[1])
		draw_string(font, (pair[0] as Rect2).position + Vector2(0, 48), pair[3], HORIZONTAL_ALIGNMENT_CENTER, pw, 10, pair[1])
	draw_string(font, Vector2(r.position.x, r.position.y + 68), "+", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 30, gold)
	var spark := Vector2(r.get_center().x, r.position.y + 116)
	draw_line(a.get_center() + Vector2(0, 30), spark, gold, 3.0, true)
	draw_line(b.get_center() + Vector2(0, 30), spark, Palette.color(&"card_item"), 3.0, true)
	draw_circle(spark, 4.0, Color.WHITE)
	var win := Rect2(Vector2(r.position.x + 12, r.position.y + 126), Vector2(r.size.x - 24, 96))
	var wbox := StyleBoxFlat.new()
	wbox.bg_color = Color(Palette.color(&"shadow"), 0.45)
	wbox.border_color = Color(gold, 0.5)
	wbox.set_border_width_all(2)
	wbox.set_corner_radius_all(12)
	draw_style_box(wbox, win)
	var evo_gun: bool = data.icon in WeaponGlyph.FLAT_GUNS
	WeaponGlyph.draw_card_flat(self, data.icon, win.get_center(), 170.0 if evo_gun else 92.0, gold)
	draw_string(font, Vector2(r.position.x, win.end.y + 30), data.title, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 24, gold)
	_paragraph("", String(data.effect), Vector2(r.position.x + 14, win.end.y + 38), r.size.x - 28, 2, 14, 10, text, font,
			_flat_bold(), HORIZONTAL_ALIGNMENT_CENTER)
	_key_row(gold, Palette.color(&"shadow"), gold, false, w)


# --- Shared -----------------------------------------------------------------------------------

## M50.4f: the effect after the bold mechanic name (a describe() that repeats the name drops it).
func effect_body() -> String:
	var body := String(data.get("effect", ""))
	var name := String(data.get("mech_name", ""))
	if name != "" and body.to_lower().begins_with(name.to_lower() + ":"):
		body = body.substr(name.length() + 1).strip_edges()
	return body


## "LV 3 > 4", "LV 1" for a new card, "" for a filler.
func _badge_text() -> String:
	if data.kind == KIND_FILLER:
		return ""
	if data.new:
		return "LV 1"
	return "LV %d > %d" % [int(data.from), int(data.to)]


## M50.4f: the effect paragraph at `at` (top-left), `width` wide, at most `lines` lines: `name`
## in bold with a colon (the mechanic), then `body`. The size steps down from `size` to `least`
## until it fits.
func _paragraph(name: String, body: String, at: Vector2, width: float, lines: int, size: int, least: int, color: Color,
		reg: Font, bold: Font, align := HORIZONTAL_ALIGNMENT_LEFT, max_h := INF) -> void:
	if width <= 8.0:
		return
	var fs := size
	var p := TextParagraph.new()
	while true:
		p = TextParagraph.new()
		p.width = width
		p.alignment = align
		if name != "":
			p.add_string(name + ": ", bold, fs)
		p.add_string(body, reg, fs)
		if (p.get_line_count() <= lines and p.get_size().y <= max_h) or fs <= least:
			break
		fs -= 1
	p.max_lines_visible = lines
	p.draw(get_canvas_item(), at, color)


## The key chip under the card and its word ("choose"; M50.4f: "focused" on the focused card).
func _key_row(chip: Color, ink: Color, word: Color, pixel_font: bool, width := SIZE.x, lip := Color.WHITE) -> void:
	var key := String(data.get("key", ""))
	if key == "":
		return
	var font: Font = UiTheme.pixel_font(true) if pixel_font else ThemeDB.fallback_font
	var kw := maxf(28.0, font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 12)
	var label := key_word()
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var x := (width - kw - 10 - lw) * 0.5
	var kr := Rect2(Vector2(x, CARD_H + 14), Vector2(kw, 24))
	if pixel_font:
		RailArt.block(self, kr, chip, 3.0, 4.0, CardArt.c(&"key_lo") if lip == Color.WHITE else lip)
	else:
		var kb := StyleBoxFlat.new()
		kb.bg_color = chip
		kb.set_corner_radius_all(4)
		draw_style_box(kb, kr)
	draw_string(font, kr.position + Vector2((kw - font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x) * 0.5,
			font.get_ascent(16) + 3), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)
	draw_string(font, Vector2(kr.end.x + 10, kr.position.y + font.get_ascent(16) + 3), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, word)


## M50.4b: the dressed panel's top: "LEVEL n" on a gold plate and "pick 1 of 3 · game paused".
class Banner:
	extends Control
	var level := 0
	var count := 3
	var pixel := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(420, 84)

	func _draw() -> void:
		var title := "LEVEL %d" % level
		var sub := "pick 1 of %d · game paused" % count
		var w := size.x
		if pixel:
			var plate := Rect2(Vector2(w * 0.5 - 160, 4), Vector2(320, 50))
			# M50.4f: the sheet's ribbon tabs (ink-outlined pink with a dark lip and a plum notch)
			# and the small stem under the plate.
			for side in 2:
				var tab := Rect2(Vector2(plate.position.x - 24 if side == 0 else plate.end.x - 4, plate.position.y + 10), Vector2(28, 32))
				RailArt.block(self, tab, CardArt.c(&"pink"), 4.0, 4.0, CardArt.c(&"passive_ink"))
				var notch_x := tab.position.x if side == 0 else tab.end.x - 8
				draw_rect(Rect2(Vector2(notch_x, tab.position.y + 8), Vector2(8, 16)), CardArt.c(&"sunk"))
			draw_rect(Rect2(Vector2(plate.get_center().x - 10, plate.end.y + 4), Vector2(20, 6)), CardArt.c(&"ink"))
			RailArt.block(self, plate, CardArt.c(&"gold"), 4.0, 6.0, CardArt.c(&"gold_lo"))
			draw_rect(Rect2(plate.position, Vector2(plate.size.x, 4)), CardArt.c(&"gold_hi"))
			RailFrame.text(self, plate.position + Vector2(0, 7), title, 32, CardArt.c(&"ink"), true,
					HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)
			RailFrame.text(self, Vector2(0, 66), sub, 13, CardArt.c(&"dim"), false, HORIZONTAL_ALIGNMENT_CENTER, w)
			return
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0, 46), title, HORIZONTAL_ALIGNMENT_CENTER, w, 44, Palette.color(&"ui_text"))
		draw_rect(Rect2(Vector2(w * 0.5 - 80, 56), Vector2(160, 4)), Palette.color(&"info"))
		draw_string(font, Vector2(0, 78), sub, HORIZONTAL_ALIGNMENT_CENTER, w, 14, Palette.color(&"ui_dim"))
