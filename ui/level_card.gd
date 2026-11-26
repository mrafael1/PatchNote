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

const SIZE := Vector2(232, 356)    ## the card (316) and its key row (40: clear of the focus ring)
const CARD_H := 316.0
const PIP_W := 22.0
const KIND_WEAPON := &"weapon"
const KIND_ITEM := &"item"
const KIND_FILLER := &"filler"
const KIND_EVOLVE := &"evolve"
const SIZE_EVO := Vector2(264, 356)   ## M50.4c1: the EVOLVE card (the sheet's 256 + its gold rim)

## {kind, kind_label, title, icon, from, to, cap, new, effect, pair, paired, key, hint}
var data := {}
var pixel := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = card_size()
	var b := get_parent() as Button
	if b != null:
		b.focus_entered.connect(queue_redraw)
		b.focus_exited.connect(queue_redraw)


## The card's dictionary for offer card `card` (PickOffer's) on a path capped at `cap`, with
## `key` its key label. The texts come from the defs, never from card.text (that stays the
## plain panel's and the logs').
static func data_for(card: Dictionary, cap: int, key: String) -> Dictionary:
	var d := {"kind": KIND_WEAPON, "kind_label": "WEAPON", "title": "", "icon": &"", "from": 0,
			"to": int(card.get("rank", 1)), "cap": maxi(1, cap), "new": card.get("kind") == &"new",
			"effect": String(card.get("text", "")), "pair": "", "paired": false, "key": key}
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
		d.paired = bool(card.get("paired", false))
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
	return d


## M50.4c1: the EVOLVE choice's dictionary from PickOffer.evolve ({from, into, catalyst, rank}).
static func data_for_evolve(ev: Dictionary, key: String) -> Dictionary:
	var d := {"kind": KIND_EVOLVE, "kind_label": "EVOLVE", "title": "", "icon": &"", "from": 0, "to": 0,
			"cap": 0, "new": false, "effect": "", "pair": "", "paired": true, "key": key, "key_word": "evolve",
			"from_title": "", "from_icon": &"", "rank": int(ev.get("rank", 0)), "item_title": "", "item_icon": &""}
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
			if after > before * 1.2 else into.pitch
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
	if _focused():
		draw_rect(r.grow(12), CardArt.c(&"ink"))
		draw_rect(r.grow(8), CardArt.c(&"gold"))
	var face := CardArt.c(&"passive") if item else CardArt.c(&"paper")
	var lip := CardArt.c(&"passive_lo") if item else CardArt.c(&"paper_lo")
	RailArt.block(self, r, face, 4.0, 6.0, lip)
	# Header: the kind, a NEW tag, the level badge.
	var head := Rect2(r.position, Vector2(r.size.x, 32))
	draw_rect(head, CardArt.c(&"base"))
	draw_rect(Rect2(Vector2(head.position.x, head.end.y - 4), Vector2(head.size.x, 4)), CardArt.c(&"ink"))
	var kx := head.position.x + 10
	if data.new:
		var tw := RailFrame.text_w("NEW", 12, true) + 10
		RailArt.block(self, Rect2(Vector2(kx, head.position.y + 7), Vector2(tw, 16)), CardArt.c(&"pink"), 2.0)
		RailFrame.text(self, Vector2(kx + 5, head.position.y + 8), "NEW", 12, CardArt.c(&"ink"), true)
		kx += tw + 8
	RailFrame.text(self, Vector2(kx, head.position.y + 9), data.kind_label, 11, CardArt.c(&"gold"), true)
	var badge := _badge_text()
	if badge != "":
		var bw := RailFrame.text_w(badge, 14, true) + 12
		var br := Rect2(Vector2(head.end.x - 8 - bw, head.position.y + 5), Vector2(bw, 20))
		draw_rect(br, CardArt.c(&"ink"))
		RailFrame.text(self, br.position + Vector2(6, 2), badge, 14, CardArt.c(&"gold") if data.new or data.cap == 0 else CardArt.c(&"paper"), true)
	# The window with the big glyph.
	var win := Rect2(r.position + Vector2(10, 42), Vector2(r.size.x - 20, 106))
	RailArt.block(self, win, CardArt.c(&"sunk"), 4.0)
	for k in 3:   # the sheet's faint grid dots
		draw_rect(Rect2(win.position + Vector2(10 + k * 64, 12), Vector2(4, 4)), CardArt.c(&"lo"))
	WeaponGlyph.draw_card(self, data.icon, win.get_center(), 76.0, Color.WHITE)
	# The name plate.
	var plate := Rect2(Vector2(r.position.x + 20, win.end.y + 12), Vector2(r.size.x - 40, 28))
	RailArt.block(self, plate, CardArt.c(&"paper"), 4.0, 4.0, CardArt.c(&"paper_lo"))
	var title := String(data.title).to_upper()
	RailFrame.text(self, plate.position + Vector2(0, 4), title, RailFrame.fit(title, 16, plate.size.x - 8, true, 9),
			CardArt.c(&"ink"), true, HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)
	# Pips, the effect, the pair line.
	var y := plate.end.y + 12
	if int(data.cap) > 0:
		_pips_pixel(Vector2(r.position.x, y), r.size.x, item)
		y += 30
	else:
		y += 6
	var ink := CardArt.c(&"ink")
	var font := UiTheme.pixel_font(false)
	draw_multiline_string(font, Vector2(r.position.x + 12, y + font.get_ascent(14)), String(data.effect),
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24, 14, 2 if String(data.pair) != "" else 3, ink)
	if String(data.pair) != "":
		var pr := Rect2(Vector2(r.position.x + 10, r.end.y - 34), Vector2(r.size.x - 20, 22))
		RailArt.block(self, pr, CardArt.c(&"paper"), 2.0)
		var col := CardArt.c(&"passive_ink") if data.paired else CardArt.c(&"note_dim")
		RailFrame.text(self, pr.position + Vector2(8, 3), data.pair, RailFrame.fit(data.pair, 13, pr.size.x - 16, false, 8), col)
	_key_row(CardArt.c(&"key"), CardArt.c(&"ink"), CardArt.c(&"dim"), true)


func _pips_pixel(at: Vector2, width: float, item: bool) -> void:
	var cap := int(data.cap)
	var step := minf(PIP_W + 8.0, (width - 20.0) / cap)
	var pw := step - 8.0
	var x0 := at.x + (width - cap * step + 8.0) * 0.5
	for k in cap:
		var lit := k < int(data.to)
		var fresh := k == int(data.to) - 1
		var h := 18.0 if fresh else 12.0
		var pr := Rect2(Vector2(roundf(x0 + k * step), at.y + 18.0 - h), Vector2(pw, h))
		if not lit:
			draw_rect(pr.grow(2), CardArt.c(&"pip_off_lo"))
			draw_rect(pr, CardArt.c(&"pip_off"))
			continue
		var fill := CardArt.c(&"warn") if item else CardArt.c(&"gold")
		if fresh:
			draw_rect(pr.grow(5), CardArt.c(&"warn") if not item else CardArt.c(&"gold"))
			fill = CardArt.c(&"gold_hi")
		RailArt.block(self, pr, fill, 3.0, 3.0, CardArt.c(&"warn_lo") if item else CardArt.c(&"gold_lo"))


# --- Flat (the sheet's bottom half: S7-S8, before the art patch) -----------------------------

func _draw_flat() -> void:
	var item: bool = data.kind == KIND_ITEM
	var edge := Palette.color(&"card_item") if item else Palette.color(&"info")
	if data.kind == KIND_FILLER:
		edge = Palette.color(&"card_lit")
	var r := Rect2(Vector2(4, 4), Vector2(SIZE.x - 8, CARD_H - 8))
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.color(&"ui_panel")
	box.border_color = edge if _focused() else Color(edge, 0.55)
	box.set_border_width_all(4 if _focused() else 2)
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
	if data.new:
		var tag := StyleBoxFlat.new()
		tag.bg_color = Palette.color(&"hit")
		tag.set_corner_radius_all(8)
		var tr := Rect2(r.position + Vector2(90, 10), Vector2(44, 20))
		draw_style_box(tag, tr)
		draw_string(font, tr.position + Vector2(8, 15), "NEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text)
	var win := Rect2(r.position + Vector2(14, 42), Vector2(r.size.x - 28, 106))
	var wbox := StyleBoxFlat.new()
	wbox.bg_color = Color(Palette.color(&"shadow"), 0.35)
	wbox.set_corner_radius_all(10)
	draw_style_box(wbox, win)
	WeaponGlyph.draw(self, data.icon, win.get_center(), 76.0, edge)
	draw_string(font, Vector2(r.position.x, win.end.y + 32), data.title, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22, text)
	var y := win.end.y + 46
	if int(data.cap) > 0:
		var cap := int(data.cap)
		var step := minf(22.0, (r.size.x - 40.0) / cap)
		var x0 := r.position.x + (r.size.x - (cap - 1) * step) * 0.5
		for k in cap:
			var c := Vector2(x0 + k * step, y + 6)
			var lit := k < int(data.to)
			if k == int(data.to) - 1:
				draw_circle(c, 9.0, Color(edge, 0.35))
			draw_circle(c, 6.0 if lit else 5.0, edge if lit else Color(dim, 0.25))
		y += 24
	draw_multiline_string(font, Vector2(r.position.x + 14, y + 14), String(data.effect), HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x - 28, 14, 3, text)
	if String(data.pair) != "":
		draw_string(font, Vector2(r.position.x, r.end.y - 14), data.pair, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13,
				edge if data.paired else dim)
	_key_row(edge, Palette.color(&"shadow"), dim, false)


# --- EVOLVE (M50.4c1, the sheet's third card) ---------------------------------------------------

func _draw_evolve_pixel() -> void:
	var w := SIZE_EVO.x
	var r := Rect2(Vector2(12, 20), Vector2(w - 24, CARD_H - 22))
	var ink := CardArt.c(&"ink")
	var gold := Palette.color(&"card_evolve") if Skins.current == null else CardArt.c(&"gold")
	if _focused():
		draw_rect(r.grow(16), ink)
		draw_rect(r.grow(13), CardArt.c(&"pink"))
	draw_rect(r.grow(12), ink)
	draw_rect(r.grow(8), gold)
	draw_rect(r.grow(4), ink)
	draw_rect(r, CardArt.c(&"base"))
	# The faint cross and rings of the sheet's back.
	draw_rect(Rect2(Vector2(r.get_center().x - 8, r.position.y), Vector2(16, r.size.y)), CardArt.c(&"cell"))
	draw_rect(Rect2(Vector2(r.position.x, r.position.y + 184), Vector2(r.size.x, 16)), CardArt.c(&"cell"))
	for k in 4:
		var corner := Vector2(r.position.x + 8 + (r.size.x - 24) * (k % 2), r.position.y + 8 + (r.size.y - 24) * (k / 2))
		draw_rect(Rect2(corner, Vector2(8, 8)), gold)
	# The ribbon.
	draw_rect(Rect2(Vector2(r.position.x - 14, r.position.y - 14), Vector2(14, 36)), CardArt.c(&"passive_ink"))
	draw_rect(Rect2(Vector2(r.end.x, r.position.y - 14), Vector2(14, 36)), CardArt.c(&"passive_ink"))
	var rib := Rect2(Vector2(r.position.x - 6, r.position.y - 20), Vector2(r.size.x + 12, 40))
	RailArt.block(self, rib, CardArt.c(&"pink"), 4.0, 6.0, CardArt.c(&"passive_ink"))
	draw_rect(Rect2(rib.position + Vector2(0, 4), Vector2(rib.size.x, 4)), CardArt.c(&"pink_hi"))
	RailFrame.text(self, rib.position + Vector2(2, 8), "EVOLVE", 24, ink, true, HORIZONTAL_ALIGNMENT_CENTER, rib.size.x)
	RailFrame.text(self, rib.position + Vector2(0, 6), "EVOLVE", 24, CardArt.c(&"paper"), true, HORIZONTAL_ALIGNMENT_CENTER, rib.size.x)
	# The parents: the maxed weapon + its catalyst.
	var pw := 76.0
	var a := Rect2(Vector2(r.position.x + 16, r.position.y + 34), Vector2(pw, 52))
	var b := Rect2(Vector2(r.end.x - 16 - pw, r.position.y + 34), Vector2(pw, 52))
	RailArt.block(self, a, CardArt.c(&"paper"), 4.0)
	draw_rect(a.grow(-4), CardArt.c(&"paper"))
	draw_rect(Rect2(a.position + Vector2(4, 4), Vector2(a.size.x - 8, 3)), gold)
	RailArt.block(self, b, CardArt.c(&"passive"), 4.0)
	draw_rect(Rect2(b.position + Vector2(4, 4), Vector2(b.size.x - 8, 3)), CardArt.c(&"warn"))
	WeaponGlyph.draw_card(self, data.from_icon, a.position + Vector2(pw * 0.5, 20), 34.0, Color.WHITE)
	WeaponGlyph.draw(self, data.item_icon, b.position + Vector2(pw * 0.5, 19), 30.0, CardArt.c(&"warn"))
	var fl := "%s %d MAX" % [String(data.from_title).to_upper(), int(data.rank)]
	RailFrame.text(self, a.position + Vector2(0, 36), fl, RailFrame.fit(fl, 10, pw - 4, true, 7), ink, true,
			HORIZONTAL_ALIGNMENT_CENTER, pw)
	RailFrame.text(self, b.position + Vector2(0, 36), String(data.item_title).to_upper(), 10, ink, true,
			HORIZONTAL_ALIGNMENT_CENTER, pw)
	RailFrame.text(self, Vector2(r.get_center().x - 16, r.position.y + 36), "+", 40, gold, true,
			HORIZONTAL_ALIGNMENT_CENTER, 32)
	# The merge arrows (gold from the weapon, orange from the item, a bright spark between).
	var mid := Vector2(r.get_center().x, r.position.y + 118)
	for k in 3:
		draw_rect(Rect2(Vector2(a.get_center().x + 8 + k * 14, r.position.y + 94 + k * 7), Vector2(14, 7)), gold)
		draw_rect(Rect2(Vector2(b.get_center().x - 22 - k * 14, r.position.y + 94 + k * 7), Vector2(14, 7)), CardArt.c(&"warn"))
	draw_rect(Rect2(mid + Vector2(-14, -6), Vector2(28, 14)), CardArt.c(&"gold_hi"))
	# The window with the evolution's gun.
	var win := Rect2(Vector2(r.position.x + 8, r.position.y + 128), Vector2(r.size.x - 16, 88))
	draw_rect(win.grow(8), ink)
	draw_rect(win.grow(4), gold)
	draw_rect(win, ink)
	draw_rect(Rect2(Vector2(win.position.x, win.get_center().y - 6), Vector2(win.size.x, 12)), CardArt.c(&"base"))
	draw_rect(Rect2(win.get_center() - Vector2(56, 36), Vector2(112, 72)), CardArt.c(&"cell"))
	draw_rect(Rect2(win.get_center() - Vector2(36, 24), Vector2(72, 48)), CardArt.c(&"sunk"))
	WeaponGlyph.draw_card(self, data.icon, win.get_center(), 112.0, Color.WHITE)
	# The name plate and the line.
	var plate := Rect2(Vector2(r.position.x + 28, win.end.y + 14), Vector2(r.size.x - 56, 28))
	RailArt.block(self, plate, gold, 4.0, 5.0, CardArt.c(&"gold_lo"))
	draw_rect(Rect2(plate.position, Vector2(plate.size.x, 4)), CardArt.c(&"gold_hi"))
	var title := String(data.title).to_upper()
	RailFrame.text(self, plate.position + Vector2(0, 5), title, RailFrame.fit(title, 16, plate.size.x - 8, true, 9), ink, true,
			HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)
	var eff := String(data.effect)
	RailFrame.text(self, Vector2(r.position.x, plate.end.y + 8), eff, RailFrame.fit(eff, 13, r.size.x - 8, false, 8),
			CardArt.c(&"paper"), false, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_key_row(CardArt.c(&"gold"), ink, CardArt.c(&"gold"), true, w)


func _draw_evolve_flat() -> void:
	var w := SIZE_EVO.x
	var gold := Palette.color(&"card_evolve")
	var r := Rect2(Vector2(8, 14), Vector2(w - 16, CARD_H - 14))
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
		WeaponGlyph.draw(self, pair[2], (pair[0] as Rect2).position + Vector2(pw * 0.5, 20), 28.0, pair[1])
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
	WeaponGlyph.draw(self, data.icon, win.get_center(), 92.0, gold)
	draw_string(font, Vector2(r.position.x, win.end.y + 30), data.title, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 24, gold)
	draw_string(font, Vector2(r.position.x, win.end.y + 52), data.effect, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, text)
	_key_row(gold, Palette.color(&"shadow"), gold, false, w)


# --- Shared -----------------------------------------------------------------------------------

## "LV 3 > 4", "LV 1" for a new card, "" for a filler.
func _badge_text() -> String:
	if data.kind == KIND_FILLER:
		return ""
	if data.new:
		return "LV 1"
	return "LV %d > %d" % [int(data.from), int(data.to)]


## The key chip under the card and its word ("choose").
func _key_row(chip: Color, ink: Color, word: Color, pixel_font: bool, width := SIZE.x) -> void:
	var key := String(data.get("key", ""))
	if key == "":
		return
	var font: Font = UiTheme.pixel_font(true) if pixel_font else ThemeDB.fallback_font
	var kw := maxf(28.0, font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 12)
	var label := String(data.get("key_word", "choose"))
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var x := (width - kw - 10 - lw) * 0.5
	var kr := Rect2(Vector2(x, CARD_H + 14), Vector2(kw, 24))
	if pixel_font:
		RailArt.block(self, kr, chip, 3.0, 4.0, CardArt.c(&"key_lo"))
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
			draw_rect(Rect2(plate.position + Vector2(-22, 12), Vector2(22, 26)), CardArt.c(&"pink"))
			draw_rect(Rect2(Vector2(plate.end.x, plate.position.y + 12), Vector2(22, 26)), CardArt.c(&"pink"))
			RailArt.block(self, plate, CardArt.c(&"gold"), 4.0, 6.0, CardArt.c(&"gold_lo"))
			RailFrame.text(self, plate.position + Vector2(0, 8), title, 30, CardArt.c(&"ink"), true,
					HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)
			RailFrame.text(self, Vector2(0, 64), sub, 13, CardArt.c(&"dim"), false, HORIZONTAL_ALIGNMENT_CENTER, w)
			return
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0, 46), title, HORIZONTAL_ALIGNMENT_CENTER, w, 44, Palette.color(&"ui_text"))
		draw_rect(Rect2(Vector2(w * 0.5 - 80, 56), Vector2(160, 4)), Palette.color(&"info"))
		draw_string(font, Vector2(0, 78), sub, HORIZONTAL_ALIGNMENT_CENTER, w, 14, Palette.color(&"ui_dim"))
