class_name CardFace
extends Control
## M50.2c: one Arcade card drawn as a card (design `.check/arcade_s10/design.md` 2.5, the
## mockups `.check/mockups/cards/Arcade_Cards` / `Arcade_Pack`): a frame by rarity, the top
## band in the weapon's colour, the art box with WeaponGlyph's picture, the rank badge, the
## NEW / "3 > 4" / FUSE tag, the name bar, rank pips with "+N", the gain line and the key.
## Kinds (`face.style`): card_common, card_rare (gold foil, "RARE +2" ribbon), card_fuse (the
## FUSE card: two-tone band, both parents' pictures, "Shotgun 5 + Laser 4" at its foot) and
## card_give (the give step's gold card). Small forms: MINI_HAND (the hand under a pack) and
## MINI_TOAST (the 1-card pack's toast, next to the rail's `pack` icon from RailArt).
##
## Tier 0 (before S9's `skin ui`) draws a rounded flat card in CardFaceArt.FLAT; once the look's
## `ui_panel` is on (Pixel) the CardFaceArt frames and PIXEL colours. Presentation only: it reads
## the card dictionaries (BoosterPack.card, fuse_option, give_card) and never changes them.
##
## The reveal (reveal_at): cards flip face-up in sequence, REVEAL_STEP apart, each in FLIP_TIME,
## all inside PickPanel.INPUT_DELAY, so no input or bot timing moves. A short white flash as a
## face lands and a shine sweeping a rare card every SHINE_EVERY. Reduce flashing: no flip, no
## flash, no shine, a fade only.

const SIZE := Vector2(240, 316)     ## the mockup's 176 x 232 at 1.36 (the game view is drawn scaled down in the rail)
const MINI_HAND := Vector2(200, 56)
const MINI_TOAST := Vector2(118, 86)
const REVEAL_STEP := 0.08
const FLIP_TIME := 0.1
const FLASH_TIME := 0.12
const SHINE_EVERY := 1.8
const SHINE_TIME := 0.45
const PIPS := 8
const MIN_FS := 6.0     ## M50.2c review: the smallest FUSE text (card units)

## The card shown: {style, title, rank, from, icon, icon_a, icon_b, tag, ribbon, gain, foot}.
var face := {}
## &"" (a full card), &"hand" or &"toast".
var mini: StringName = &""
var flip_sx := 1.0      ## 1 = flat on the table; near 0 = edge-on (mid flip)
var back := false       ## face-down (before or during the first half of the flip)
var flash := 0.0        ## the landing flash's alpha
var shine := -1.0       ## the rare shine's sweep 0..1, < 0 none
var lit := false        ## the focused / hovered choice
## M50.2c review: the last drawn FUSE text box: {text, fs, height, box} (gain_fit). Read by tests.
var fuse_drawn := {}


## The face for a pack card c (BoosterPack.card's dict); `key` its hint ("[1]") or "".
static func face_of(c: Dictionary, key := "", give := false) -> Dictionary:
	var w := WeaponDB.get_weapon(c.get("id", &""))
	var rare: bool = c.get("rarity") == BoosterPack.RARE
	var upgrade: bool = c.get("kind") == &"upgrade"
	var rank := int(c.get("rank", 1))
	var from := int(c.get("from", 0))
	var style := &"card_give" if give else (&"card_rare" if rare else &"card_common")
	var ribbon := ""
	if give:
		ribbon = "GOLD CARD"
	elif rare:
		ribbon = "RARE +2" if upgrade else "RARE"
	return {"style": style, "title": String(w.title) if w != null else String(c.get("id", "")),
			"rank": rank, "from": from, "icon": w.icon if w != null else &"",
			"tag": "%d > %d" % [from, rank] if upgrade else "NEW", "ribbon": ribbon,
			"gain": String(c.get("gain", c.get("text", ""))), "foot": key}


## The FUSE card's face from BoosterPack.fuse_option's dict.
static func fuse_face(f: Dictionary, key := "") -> Dictionary:
	var fw := WeaponDB.get_weapon(f.get("id", &""))
	var wa := WeaponDB.get_weapon(f.get("a", &""))
	var wb := WeaponDB.get_weapon(f.get("b", &""))
	var parents := String(f.get("title", "")).trim_prefix("FUSE: ").get_slice(" -> ", 0)
	# M50.2c review: every kept mechanic on its own line, then "loses: ..." on its own (red),
	# all fitted into the FUSE face's taller text box (gain_fit), never cut.
	var gain := "\n".join(f.get("keeps", []))
	var loses: Array = f.get("loses", [])
	return {"style": &"card_fuse", "title": String(fw.title) if fw != null else "Fuse",
			"rank": int(f.get("rank", 1)), "from": int(f.get("rank", 1)), "icon": fw.icon if fw != null else &"",
			"icon_a": wa.icon if wa != null else &"", "icon_b": wb.icon if wb != null else &"",
			"tag": "FUSE", "ribbon": "", "gain": gain,
			"loses": "loses: " + ", ".join(loses) if not loses.is_empty() else "", "foot": ("%s  " % key if key != "" else "") + parents}


## The hand preview's face for {id, title, rank}.
static func hand_face(h: Dictionary) -> Dictionary:
	var w := WeaponDB.get_weapon(h.get("id", &""))
	return {"style": &"card_common", "title": String(h.get("title", "")), "rank": int(h.get("rank", 1)),
			"from": int(h.get("rank", 1)), "icon": w.icon if w != null else &"", "tag": "", "ribbon": "",
			"gain": "", "foot": ""}


## Card i's look at `t` seconds after the cards were dealt: {sx, back, alpha, flash}.
static func reveal_at(t: float, i: int, reduce: bool) -> Dictionary:
	var p := clampf((t - i * REVEAL_STEP) / FLIP_TIME, 0.0, 1.0)
	if reduce:
		return {"sx": 1.0, "back": false, "alpha": p, "flash": 0.0}
	var after := t - i * REVEAL_STEP - FLIP_TIME
	var fl := 0.0 if after < 0.0 else 0.6 * clampf(1.0 - after / FLASH_TIME, 0.0, 1.0)
	return {"sx": maxf(0.04, absf(cos(p * PI))), "back": p < 0.5, "alpha": 1.0, "flash": fl}


## When the last of n cards is face-up (seconds after the deal).
static func reveal_end(n: int) -> float:
	return maxi(n - 1, 0) * REVEAL_STEP + FLIP_TIME


## A rare card's shine sweep at `t` (0..1 while it crosses, -1 between), none when reducing.
static func shine_at(t: float, n: int, reduce: bool) -> float:
	var since := t - reveal_end(n)
	if reduce or since < 0.0:
		return -1.0
	var ph := fmod(since, SHINE_EVERY)
	return ph / SHINE_TIME if ph < SHINE_TIME else -1.0


func set_reveal(r: Dictionary) -> void:
	flip_sx = r.sx
	back = r.back
	flash = r.flash
	modulate = Color(1, 1, 1, r.alpha)


## Pixel frames once the look's UI panel is on (S9 after `skin ui`, `--look=pixel`).
static func pixel() -> bool:
	return Skins.is_on(&"ui_panel")


func _draw() -> void:
	match mini:
		&"hand":
			_draw_hand()
			return
		&"toast":
			_draw_toast()
			return
	var w := size.x
	var lift := -8.0 * _u() if lit else 0.0
	draw_set_transform(Vector2(w * 0.5 * (1.0 - flip_sx), lift), 0.0, Vector2(flip_sx, 1.0))
	if back:
		_draw_back()
	elif pixel():
		_draw_pixel()
	else:
		_draw_flat()
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, flash))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _u() -> float:
	return size.x / 176.0


func _r(x: float, y: float, rw: float, rh: float) -> Rect2:
	var u := _u()
	return Rect2(Vector2(x, y) * u, Vector2(rw, rh) * u)


func _font(bold := false) -> Font:
	return UiTheme.pixel_font(bold) if pixel() else UiTheme.font()


func _text(at: Vector2, t: String, fs: float, color: Color, bold := false, align := HORIZONTAL_ALIGNMENT_LEFT,
		width := -1.0) -> void:
	var f := _font(bold)
	var s := int(roundf(fs * _u()))
	draw_string(f, Vector2(at.x, at.y + f.get_ascent(s)), t, align, width, s, color)


# --- Pixel ----------------------------------------------------------------------------------

func _draw_pixel() -> void:
	var u := _u()
	var style: StringName = face.get("style", &"card_common")
	var box := CardFaceArt.frame(style)
	if box != null:
		draw_style_box(box, Rect2(Vector2.ZERO, size))
	var ink := CardFaceArt.px(&"ink")
	var icon: StringName = face.get("icon", &"")
	# The top band: the weapon's colour (FUSE: its two parents, half each).
	var band := _r(14, 12, 148, 6)
	if style == &"card_fuse":
		var half := Rect2(band.position, Vector2(band.size.x * 0.5, band.size.y))
		draw_rect(half, CardFaceArt.band(face.get("icon_a", &""))[0])
		draw_rect(Rect2(half.position + Vector2(half.size.x, 0), half.size), CardFaceArt.band(face.get("icon_b", &""))[0])
	else:
		draw_rect(band, CardFaceArt.band(icon)[0])
	draw_rect(Rect2(band.position + Vector2(0, band.size.y - 2 * u), Vector2(band.size.x, 2 * u)), CardFaceArt.band(icon)[1])
	# The art box: the plum checker, the picture on it. M50.2c review: FUSE's is shorter, so its
	# kept mechanics and losses fit below.
	var fuse := style == &"card_fuse"
	var art := _r(14, 22, 148, 50 if fuse else 96)
	draw_rect(art.grow(3 * u), ink)
	draw_rect(art, CardFaceArt.px(&"cell"))
	var cell := 8.0 * u
	for y in int(art.size.y / cell):
		for x in int(art.size.x / cell):
			if (x + y) % 2 == 0:
				draw_rect(Rect2(art.position + Vector2(x, y) * cell, Vector2(cell, cell)), CardFaceArt.px(&"check"))
	draw_rect(Rect2(Vector2(art.position.x, art.end.y - 6 * u), Vector2(art.size.x, 6 * u)), CardFaceArt.px(&"cell_lo"))
	_art(art)
	if shine >= 0.0:
		_shine(Rect2(Vector2.ZERO, size))
	# The tag, top right of the art box.
	var tag := String(face.get("tag", ""))
	if tag != "":
		var fs := 12.0
		var tw := _font(true).get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, int(roundf(fs * u))).x + 10 * u
		var tr := Rect2(Vector2(art.end.x - tw - 6 * u, art.position.y + 6 * u), Vector2(tw, 18 * u))
		draw_rect(tr, ink)
		_text(tr.position + Vector2(5 * u, 2 * u), tag, fs, CardFaceArt.px(&"gold") if tag == "NEW" or tag == "FUSE" else CardFaceArt.px(&"paper"), true)
	# The name bar.
	var nb := _r(8, 80 if fuse else 126, 160, 22)
	draw_rect(nb, ink)
	draw_rect(Rect2(Vector2(nb.position.x, nb.end.y - 3 * u), Vector2(nb.size.x, 3 * u)), CardFaceArt.band(icon)[0])
	_text(nb.position + Vector2(0, 2 * u), String(face.get("title", "")).to_upper(), 15, CardFaceArt.px(&"name"), true,
			HORIZONTAL_ALIGNMENT_CENTER, nb.size.x)
	# The gain line (two lines at most) and the foot. FUSE: no pips (its rank is the badge), the
	# whole kept / lost text fitted from under the name bar down to the foot.
	var rare := style == &"card_rare" or style == &"card_give"
	if fuse:
		_fuse_text(_r(12, 110, 152, 98), 12, CardFaceArt.px(&"text"), CardFaceArt.px(&"red"))
	else:
		_pips(Vector2(12, 156), true)
		var gain := String(face.get("gain", ""))
		var gf := int(roundf(12 * u))
		draw_multiline_string(_font(), Vector2(12 * u, 174 * u + _font().get_ascent(gf)), gain, HORIZONTAL_ALIGNMENT_LEFT,
				152 * u, gf, 2, CardFaceArt.px(&"text"))
	_foot(Vector2(12, 211) * u, 13, 134 * u, CardFaceArt.px(&"rare_foot") if rare else CardFaceArt.px(&"foot"))
	var gem := _r(152, 212, 12, 12)
	draw_rect(gem.grow(2 * u), ink)
	draw_rect(gem, Palette.color(&"card_rare") if rare else CardFaceArt.px(&"gem"))
	_badge(_r(-10, -10, 40, 40))
	_ribbon()


## M50.2c review: the largest font size (from `fs` down to MIN_FS, in card units) at which
## `text` wrapped to box's width fits box's height: {fs, height}. FUSE uses it so no kept
## mechanic or loss is ever cut off.
static func gain_fit(font: Font, text: String, box: Rect2, fs: float, u: float) -> Dictionary:
	var s := fs
	var h := 0.0
	while true:
		h = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, box.size.x, int(roundf(s * u))).y
		if h <= box.size.y or s <= MIN_FS:
			break
		s -= 0.5
	return {"fs": s, "height": h}


## FUSE's text: the kept mechanics (one per line), then "loses: ..." in `lose_col`, fitted to box.
func _fuse_text(box: Rect2, fs: float, col: Color, lose_col: Color) -> void:
	var f := _font()
	var keeps := String(face.get("gain", ""))
	var loses := String(face.get("loses", ""))
	var all := keeps + ("\n" + loses if loses != "" else "")
	var fit := gain_fit(f, all, box, fs, _u())
	var s := int(roundf(fit.fs * _u()))
	fuse_drawn = {"text": all, "fs": fit.fs, "height": fit.height, "box": box}
	var y := box.position.y + f.get_ascent(s)
	draw_multiline_string(f, Vector2(box.position.x, y), keeps, HORIZONTAL_ALIGNMENT_LEFT, box.size.x, s, -1, col)
	if loses != "":
		var kh := f.get_multiline_string_size(keeps, HORIZONTAL_ALIGNMENT_LEFT, box.size.x, s).y if keeps != "" else 0.0
		draw_multiline_string(f, Vector2(box.position.x, y + kh), loses, HORIZONTAL_ALIGNMENT_LEFT, box.size.x, s, -1, lose_col)


## The foot line (the key, FUSE's parents), shrunk to fit `width`.
func _foot(at: Vector2, fs: float, width: float, color: Color) -> void:
	var t := String(face.get("foot", ""))
	var s := fs
	while s > 7.0 and _font().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(roundf(s * _u()))).x > width:
		s -= 1.0
	_text(at, t, s, color)


## The rank badge: a gold block with the rank in the rail's pixel digits.
func _badge(r: Rect2) -> void:
	var u := _u()
	var digits := str(int(face.get("rank", 1)))
	var cellpx := maxf(1.0, roundf(4 * u))
	r.size.x = maxf(r.size.x, RailArt.digits_width(digits, cellpx) + 12 * u)
	if pixel():
		draw_rect(r.grow(3 * u), CardFaceArt.px(&"ink"))
		draw_rect(r, CardFaceArt.px(&"gold"))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3 * u)), CardFaceArt.px(&"gold_hi"))
		draw_rect(Rect2(Vector2(r.position.x, r.end.y - 4 * u), Vector2(r.size.x, 4 * u)), CardFaceArt.px(&"gold_lo"))
		RailArt.draw_digits(self, (r.position + (r.size - Vector2(RailArt.digits_width(digits, cellpx), 7 * cellpx)) * 0.5).round(),
				digits, cellpx, CardFaceArt.px(&"ink"))
	else:
		var c := r.get_center()
		var rad := r.size.y * 0.5
		draw_circle(c, rad + 3 * u, CardFaceArt.flat(&"face"))
		draw_circle(c, rad, CardFaceArt.flat(&"gold"))
		_text(Vector2(r.position.x, c.y - 11 * u), digits, 18, CardFaceArt.flat(&"ink"), true, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## The ribbon on the top edge (RARE +2, RARE, GOLD CARD).
func _ribbon() -> void:
	var t := String(face.get("ribbon", ""))
	if t == "":
		return
	var u := _u()
	var fs := 11.0
	var tw := _font(true).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(roundf(fs * u))).x + 20 * u
	var r := Rect2(Vector2(size.x - tw - 10 * u, -14 * u), Vector2(tw, 24 * u))
	if pixel():
		var box := CardFaceArt.frame(&"ribbon")
		if box != null:
			draw_style_box(box, r)
		_text(r.position + Vector2(0, 5 * u), t, fs, CardFaceArt.px(&"paper_hi"), true, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = CardFaceArt.flat(&"give") if face.get("style") == &"card_give" else CardFaceArt.flat(&"pink")
		sb.set_corner_radius_all(int(12 * u))
		draw_style_box(sb, r)
		_text(r.position + Vector2(0, 4 * u), t, fs, CardFaceArt.flat(&"ink"), true, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## Rank pips: the held ranks on, this card's new ranks in pink, then "+N".
func _pips(at: Vector2, square: bool) -> void:
	var u := _u()
	var rank := int(face.get("rank", 1))
	var from := int(face.get("from", 0))
	var n := mini(rank, PIPS)
	var gold := CardFaceArt.px(&"gold") if square else CardFaceArt.flat(&"gold")
	var fresh := CardFaceArt.px(&"pink") if square else CardFaceArt.flat(&"pink")
	for k in n:
		var on_col := gold if k < from else fresh
		if rank > PIPS and from > 0:
			on_col = gold if k < PIPS - mini(rank - from, PIPS) else fresh
		var c := (at + Vector2(k * 16, 0)) * u
		if square:
			draw_rect(Rect2(c, Vector2(11, 11) * u).grow(2 * u), CardFaceArt.px(&"ink"))
			draw_rect(Rect2(c, Vector2(11, 11) * u), on_col)
		else:
			draw_circle(c + Vector2(5.5, 5.5) * u, 5.5 * u, on_col)
	if rank > from:
		_text((at + Vector2(n * 16 + 2, -4)) * u, "+%d" % (rank - from), 15,
				CardFaceArt.px(&"red") if square else CardFaceArt.flat(&"red"), true)


## The picture(s) in the art box.
func _art(art: Rect2) -> void:
	var u := _u()
	var c := art.get_center() + Vector2(0, -4 * u)
	if face.get("style") == &"card_fuse":
		WeaponGlyph.draw(self, face.get("icon_a", &""), art.position + Vector2(22, art.size.y / u - 22) * u, 30 * u, Color(1, 1, 1, 0.85))
		WeaponGlyph.draw(self, face.get("icon_b", &""), art.end - Vector2(22, 22) * u, 30 * u, Color(1, 1, 1, 0.85))
	WeaponGlyph.draw(self, face.get("icon", &""), c, 64 * u, Color.WHITE)


## The rare shine: a light band crossing the card (no shine under reduce flashing: shine < 0).
func _shine(r: Rect2) -> void:
	var x := lerpf(-r.size.y, r.size.x, shine)
	var band := PackedVector2Array([Vector2(x, r.size.y), Vector2(x + 26 * _u(), r.size.y),
			Vector2(x + 26 * _u() + r.size.y * 0.5, 0), Vector2(x + r.size.y * 0.5, 0)])
	var card := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	for poly in Geometry2D.intersect_polygons(band, card):
		draw_colored_polygon(poly, Color(1, 1, 1, 0.28))


# --- Tier 0 -----------------------------------------------------------------------------------

func _draw_flat() -> void:
	var u := _u()
	var style: StringName = face.get("style", &"card_common")
	var sb := StyleBoxFlat.new()
	sb.bg_color = CardFaceArt.flat(&"face")
	sb.set_corner_radius_all(int(12 * u))
	match style:
		&"card_rare":
			sb.border_color = Palette.color(&"card_rare")
			sb.set_border_width_all(int(3 * u))
		&"card_fuse":
			sb.border_color = CardFaceArt.flat(&"fuse")
			sb.set_border_width_all(int(3 * u))
		&"card_give":
			sb.border_color = CardFaceArt.flat(&"give")
			sb.set_border_width_all(int(4 * u))
		_:
			sb.border_color = CardFaceArt.flat(&"edge")
			sb.set_border_width_all(int(2 * u))
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	var icon: StringName = face.get("icon", &"")
	var line := _r(40, 12, 22, 3)
	draw_rect(line, CardFaceArt.band(icon)[0])
	var fuse := style == &"card_fuse"
	var art := _r(12, 22, 152, 50 if fuse else 100)
	var ab := StyleBoxFlat.new()
	ab.bg_color = CardFaceArt.flat(&"art")
	ab.set_corner_radius_all(int(8 * u))
	draw_style_box(ab, art)
	if style == &"card_fuse":
		draw_rect(Rect2(art.position + Vector2(0, art.size.y - 3 * u), Vector2(art.size.x * 0.5, 3 * u)), CardFaceArt.band(face.get("icon_a", &""))[0])
		draw_rect(Rect2(art.position + Vector2(art.size.x * 0.5, art.size.y - 3 * u), Vector2(art.size.x * 0.5, 3 * u)), CardFaceArt.band(face.get("icon_b", &""))[0])
	_art(art)
	if shine >= 0.0:
		_shine(Rect2(Vector2.ZERO, size))
	var tag := String(face.get("tag", ""))
	if tag != "":
		var tw := _font(true).get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, int(roundf(10 * u))).x + 14 * u
		var tr := Rect2(Vector2(art.end.x - tw - 8 * u, art.position.y + 8 * u), Vector2(tw, 18 * u))
		var tb := StyleBoxFlat.new()
		tb.bg_color = CardFaceArt.flat(&"back")
		tb.set_corner_radius_all(int(9 * u))
		draw_style_box(tb, tr)
		_text(tr.position + Vector2(0, 3 * u), tag, 10, CardFaceArt.flat(&"gold") if tag == "NEW" or tag == "FUSE" else CardFaceArt.flat(&"text"), true,
				HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
	var title := String(face.get("title", ""))
	var ty := 80.0 if fuse else 130.0
	_text(Vector2(14, ty) * u, title, 17, CardFaceArt.flat(&"text"), true)
	var tw2 := _font(true).get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(roundf(17 * u))).x
	_text(Vector2(14 * u + tw2 + 6 * u, (ty + 6) * u), "rank %d" % int(face.get("rank", 1)), 11, CardFaceArt.flat(&"dim"))
	draw_rect(_r(14, ty + 24, 148, 1), CardFaceArt.flat(&"edge"))
	if fuse:   # M50.2c review: the whole kept / lost text, fitted (see _draw_pixel)
		_fuse_text(_r(14, 110, 150, 102), 11, CardFaceArt.flat(&"text"), CardFaceArt.flat(&"red"))
	else:
		_pips(Vector2(14, 162), false)
		var gf := int(roundf(11 * u))
		draw_multiline_string(_font(), Vector2(14 * u, 182 * u + _font().get_ascent(gf)), String(face.get("gain", "")),
				HORIZONTAL_ALIGNMENT_LEFT, 150 * u, gf, 2, CardFaceArt.flat(&"text"))
	_foot(Vector2(14, 216) * u, 11, 136 * u, CardFaceArt.flat(&"dim"))
	_badge(_r(-8, -8, 36, 36))
	_ribbon()


# --- The back, the minis ----------------------------------------------------------------------

## Face-down: the blob's mark (a smiling gold disc) on the card's back.
func _draw_back() -> void:
	var u := _u()
	var r := Rect2(Vector2.ZERO, size)
	if pixel():
		var box := CardFaceArt.frame(&"card_back")
		if box != null:
			draw_style_box(box, r)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = CardFaceArt.flat(&"back")
		sb.border_color = CardFaceArt.flat(&"edge")
		sb.set_border_width_all(int(2 * u))
		sb.set_corner_radius_all(int(12 * u))
		draw_style_box(sb, r)
	var c := r.get_center()
	var gold := CardFaceArt.px(&"gold") if pixel() else CardFaceArt.flat(&"gold")
	var ink := CardFaceArt.px(&"ink") if pixel() else CardFaceArt.flat(&"back")
	draw_circle(c, 34 * u, gold)
	draw_circle(c + Vector2(-11, -6) * u, 4 * u, ink)
	draw_circle(c + Vector2(11, -6) * u, 4 * u, ink)
	draw_arc(c + Vector2(0, 4) * u, 12 * u, 0.3, PI - 0.3, 10, ink, 3 * u)


## The hand under a pack: a paper strip, the picture, the name and the rank.
func _draw_hand() -> void:
	var u := size.y / 50.0
	var r := Rect2(Vector2.ZERO, size)
	var icon: StringName = face.get("icon", &"")
	var title := String(face.get("title", ""))
	var rank := int(face.get("rank", 1))
	if pixel():
		draw_rect(r, CardFaceArt.px(&"ink"))
		var inner := r.grow(-3 * u)
		draw_rect(inner, CardFaceArt.px(&"paper"))
		draw_rect(Rect2(inner.position, Vector2(inner.size.x, 3 * u)), CardFaceArt.band(icon)[0])
		var art := Rect2(inner.position + Vector2(4, 7) * u, Vector2(40, 34) * u)
		draw_rect(art, CardFaceArt.px(&"cell"))
		WeaponGlyph.draw(self, icon, art.get_center(), 30 * u, Color.WHITE)
		var f := UiTheme.pixel_font(true)
		var s := int(roundf(14 * u))
		draw_string(f, Vector2(art.end.x + 6 * u, inner.position.y + 7 * u + f.get_ascent(s)), title.to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, inner.end.x - art.end.x - 8 * u, s, CardFaceArt.px(&"ink"))
		var tag := "RK %d" % rank
		var tr := Rect2(Vector2(art.end.x + 6 * u, inner.position.y + 25 * u), Vector2(50, 16) * u)
		draw_rect(tr, CardFaceArt.px(&"ink"))
		draw_string(f, Vector2(tr.position.x + 4 * u, tr.position.y + f.get_ascent(int(13 * u))), tag,
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * u), CardFaceArt.px(&"gold"))
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = CardFaceArt.flat(&"face")
		sb.border_color = CardFaceArt.flat(&"edge")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(int(8 * u))
		draw_style_box(sb, r)
		WeaponGlyph.draw(self, icon, r.position + Vector2(26, 25) * u, 32 * u, Color.WHITE)
		var f := UiTheme.font()
		var s := int(roundf(15 * u))
		draw_string(f, Vector2(52 * u, 8 * u + f.get_ascent(s)), title, HORIZONTAL_ALIGNMENT_LEFT, -1, s, CardFaceArt.flat(&"text"))
		draw_string(f, Vector2(52 * u, 28 * u + f.get_ascent(int(11 * u))), "rank %d" % rank, HORIZONTAL_ALIGNMENT_LEFT,
				-1, int(11 * u), CardFaceArt.flat(&"gold"))


## The 1-card pack's toast: the rail's `pack` icon (RailArt, read, not copied), then the card
## at a small size (its frame, band, picture and rank).
func _draw_toast() -> void:
	var u := size.y / 86.0
	var gp := roundf(3 * u)
	RailArt.draw_grid(self, RailArt.PACK, RailArt.PACK_LEGEND, Vector2(0, size.y - 14 * gp), gp, true)
	var card := Rect2(Vector2(40 * u, 0), Vector2(size.x - 40 * u, size.y))
	var style: StringName = face.get("style", &"card_common")
	var icon: StringName = face.get("icon", &"")
	if pixel():
		var box := CardFaceArt.frame(style)
		if box != null:
			draw_style_box(box, card)
		draw_rect(Rect2(card.position + Vector2(10, 9) * u, Vector2(card.size.x - 20 * u, 4 * u)), CardFaceArt.band(icon)[0])
		var art := Rect2(card.position + Vector2(10, 16) * u, Vector2(card.size.x - 20 * u, 44 * u))
		draw_rect(art, CardFaceArt.px(&"cell"))
		WeaponGlyph.draw(self, icon, art.get_center(), 32 * u, Color.WHITE)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = CardFaceArt.flat(&"face")
		sb.border_color = Palette.color(&"card_rare") if style == &"card_rare" else CardFaceArt.flat(&"edge")
		sb.set_border_width_all(int(3 * u) if style == &"card_rare" else 2)
		sb.set_corner_radius_all(int(8 * u))
		draw_style_box(sb, card)
		draw_rect(Rect2(card.position + Vector2(14, 8) * u, Vector2(14, 3) * u), CardFaceArt.band(icon)[0])
		WeaponGlyph.draw(self, icon, card.position + Vector2(card.size.x * 0.5, 38 * u), 32 * u, Color.WHITE)
	var digits := str(int(face.get("rank", 1)))
	var cellpx := maxf(1.0, roundf(2 * u))
	var bw := RailArt.digits_width(digits, cellpx) + 8 * u
	var badge := Rect2(Vector2(card.position.x + (card.size.x - bw) * 0.5, card.end.y - 24 * u), Vector2(bw, 18 * u))
	draw_rect(badge, CardFaceArt.px(&"ink"))
	RailArt.draw_digits(self, (badge.position + Vector2(4 * u, (badge.size.y - 7 * cellpx) * 0.5)).round(), digits, cellpx,
			CardFaceArt.px(&"gold"))
