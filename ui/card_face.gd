class_name CardFace
extends Control
## M50.2c: one Arcade card drawn as a card (design `.check/arcade_s10/design.md` 2.5, the
## mockups `.check/mockups/cards/Arcade_Cards` / `Arcade_Pack`): a frame by rarity, the top
## band in the weapon's colour, the art box with the weapon's gun (M50.5a: Auto's CardArt / flat guns), the rank badge, the
## NEW / "3 > 4" / FUSE tag, the name bar, rank pips with "+N", the gain line and the key.
## Kinds (`face.style`): card_common, card_rare (gold foil), card_epic (M50.6: a ready-made
## fusion, lilac and mint), each under its tier's ribbon (COMMON / RARE / EPIC), card_fuse (the
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
const MINI_CHOICE := Vector2(280, 78)   ## M50.7: a give / replace step's hand card (MINI_HAND's shape)
const MINI_CHIP := Vector2(200, 52)     ## M50.7: "Keep your hand" / "Back to the pack"
const MINI_SOCKET := Vector2(34, 56)    ## M50.7: the link socket between the hand preview's cards
const REVEAL_STEP := 0.08
const FLIP_TIME := 0.1
const FLASH_TIME := 0.12
const SHINE_EVERY := 1.8
const SHINE_TIME := 0.45
const PIPS := 8
const MIN_FS := 6.0     ## M50.2c review: the smallest FUSE text (card units)
const RIBBON_CELL := 2.0   ## M50.6a: one cell of the Pixel ribbon's block capitals (card units)
const NEXT_CELL := 2.0     ## M50.7 review: one cell of the Pixel NEXT tag's block capitals (screen px)

## The card shown: {style, title, rank, from, icon, icon_a, icon_b, tag, ribbon, gain, foot}.
var face := {}
## &"" (a full card), &"hand" or &"toast".
var mini: StringName = &""
var flip_sx := 1.0      ## 1 = flat on the table; near 0 = edge-on (mid flip)
var back := false       ## face-down (before or during the first half of the flip)
var flash := 0.0        ## the landing flash's alpha
var shine := -1.0       ## the rare shine's sweep 0..1, < 0 none
var lit := false        ## the focused / hovered choice
var offset := Vector2.ZERO   ## M50.7: the slot-in / fuse slide (drawn offset, px)
var shrink := 1.0            ## M50.7: the slot-in's scale
## M50.2c review: the last drawn FUSE text box: {text, fs, height, box} (gain_fit). Read by tests.
var fuse_drawn := {}
## M50.6a (tests): the last ribbon drawn: {text, rect, cell} (cell 0 = the look's font).
var ribbon_drawn := {}
## M50.5a: the pictures drawn in the last _draw, in order: [icon, how] with how = &"gun" (CardArt's
## pixel gun), &"flat" (WeaponGlyph's flat gun) or &"glyph" (the shot glyph). Read by tests.
var art_drawn: Array = []
## M50.7 (tests): the "NEXT: ..." teaser drawn on the art box ("" none).
var next_drawn := ""
## M50.7 review (tests): the NEXT tag's rows as drawn (Pixel: block capitals, wrapped).
var next_rows_drawn: Array[String] = []
## M50.7 review (tests): the gain text as drawn (whole sentences that fit two lines).
var gain_drawn := ""


## The face for a pack card c (BoosterPack.card's dict); `key` its hint ("[1]") or "".
static func face_of(c: Dictionary, key := "", give := false) -> Dictionary:
	var w := WeaponDB.get_weapon(c.get("id", &""))
	# M50.6: the frame and the ribbon are the weapon's tier (the card dict's `rarity`).
	var tier: StringName = c.get("rarity", BoosterPack.COMMON)
	var upgrade: bool = c.get("kind") == &"upgrade"
	var rank := int(c.get("rank", 1))
	var from := int(c.get("from", 0))
	var style: StringName = &"card_common"
	if give:
		style = &"card_give"
	elif tier == BoosterPack.RARE:
		style = &"card_rare"
	elif tier == BoosterPack.EPIC:
		style = &"card_epic"
	var ribbon := "GOLD CARD" if give else String(tier).to_upper()
	# M50.7: the mechanic an upgrade's rank unlocks or strengthens (the gain line's pink icon).
	var mech: StringName = &""
	if upgrade and w != null and not w.is_fusion() and not w.is_evolution():
		mech = LevelCard.gained_mechanic(w, from, rank, true)
	# M50.7: a numbers-only rank's ", next: <mechanic>" (WeaponCurve.gain_text) is a tag on the art
	# box, so the gain line keeps its breakpoints within its two lines.
	var gain := String(c.get("gain", c.get("text", "")))
	var nxt := ""
	var at := gain.rfind("next: ")
	if at >= 0:
		nxt = gain.substr(at + 6).strip_edges()
		gain = gain.substr(0, at).strip_edges().trim_suffix(",")
	return {"style": style, "title": String(w.title) if w != null else String(c.get("id", "")),
			"rank": rank, "from": from, "icon": w.icon if w != null else &"",
			"tag": "%d > %d" % [from, rank] if upgrade else "NEW", "ribbon": ribbon,
			"gain": gain, "next": nxt, "foot": key, "mech": mech,
			"mech_name": String(mech).replace("_", " ").capitalize() if mech != &"" else ""}


## M50.7: pip k (0-based) is tall: a mechanic rank (2/4/6 unlock, 8/10/12... strengthen), as
## the Auto cards draw them.
static func tall_pip(k: int) -> bool:
	return (k + 1) % 2 == 0


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
	art_drawn.clear()
	match mini:
		&"hand":
			draw_set_transform(offset, 0.0, Vector2.ONE)
			_draw_hand()
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
		&"toast":
			_draw_toast()
			return
		&"choice":
			_draw_choice()
			return
		&"socket":
			_draw_socket()
			return
	var w := size.x
	var lift := -8.0 * _u() if lit else 0.0
	var sx := flip_sx * shrink
	draw_set_transform(offset + Vector2(w * 0.5 * (1.0 - sx), lift + size.y * 0.5 * (1.0 - shrink)), 0.0, Vector2(sx, shrink))
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
	var s := _px(fs)
	draw_string(f, Vector2(at.x, at.y + f.get_ascent(s)), t, align, width, s, color)


## M50.7: a size in card units as screen px; on Pixel never one where Pixelify closes C, E, F,
## G or 1 (UiTheme.pixel_size, as the rail's text does).
func _px(fs: float) -> int:
	var s := int(roundf(fs * _u()))
	return UiTheme.pixel_size(s) if pixel() else s


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
	_next_tag(art, ink, CardFaceArt.px(&"pink"), 12.0)
	# The name bar.
	var nb := _r(8, 80 if fuse else 126, 160, 22)
	draw_rect(nb, ink)
	draw_rect(Rect2(Vector2(nb.position.x, nb.end.y - 3 * u), Vector2(nb.size.x, 3 * u)), CardFaceArt.band(icon)[0])
	_text(nb.position + Vector2(0, 2 * u), String(face.get("title", "")).to_upper(), 15, CardFaceArt.px(&"name"), true,
			HORIZONTAL_ALIGNMENT_CENTER, nb.size.x)
	# The gain line (two lines at most) and the foot. FUSE: no pips (its rank is the badge), the
	# whole kept / lost text fitted from under the name bar down to the foot.
	var rare := style == &"card_rare" or style == &"card_give"
	var epic := style == &"card_epic"
	if fuse:
		_fuse_text(_r(12, 110, 152, 98), 12, CardFaceArt.px(&"text"), CardFaceArt.px(&"red"))
	else:
		_pips(Vector2(12, 156), true)
		_gain(Vector2(12, 174), 152, 12, CardFaceArt.px(&"text"), CardFaceArt.px(&"pink"))
	_foot(Vector2(12, 211) * u, 13, 134 * u, CardFaceArt.px(&"rare_foot") if rare else (CardFaceArt.px(&"epic_foot") if epic else CardFaceArt.px(&"foot")))
	var gem := _r(152, 212, 12, 12)
	draw_rect(gem.grow(2 * u), ink)
	draw_rect(gem, Palette.color(&"card_rare") if rare else (Palette.color(&"card_epic") if epic else CardFaceArt.px(&"gem")))
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


## The ribbon on the top edge: the card's tier (M50.6: COMMON, RARE, EPIC) or GOLD CARD. The
## rare and gold ones wear the baked pink strip, a common one a quiet plum box, an epic one violet.
func _ribbon() -> void:
	var t := String(face.get("ribbon", ""))
	if t == "":
		return
	var u := _u()
	var fs := 11.0
	var style: StringName = face.get("style", &"card_common")
	# M50.6a: on Pixel the ribbon's word is block capitals (RailArt.DIGITS, RIBBON_CELL card
	# units a cell, drawn as art like the rank badge): the body font at this size closed its C
	# into a D ("DOMMON", "EPID").
	var cell := maxf(1.0, roundf(RIBBON_CELL * u))
	var tw := (RailArt.digits_width(t, cell) if pixel() else _font(true).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(roundf(fs * u))).x) + 20 * u
	var r := Rect2(Vector2(size.x - tw - 10 * u, -14 * u), Vector2(tw, 24 * u))
	ribbon_drawn = {"text": t, "rect": r, "cell": cell if pixel() else 0.0}
	if pixel():
		if style == &"card_common" or style == &"card_epic":
			draw_rect(r, CardFaceArt.px(&"ink"))
			draw_rect(r.grow(-3 * u), CardFaceArt.px(&"epic") if style == &"card_epic" else CardFaceArt.px(&"common"))
			if style == &"card_epic":
				draw_rect(Rect2(r.position + Vector2(3, 3) * u, Vector2(r.size.x - 6 * u, 3 * u)), CardFaceArt.px(&"epic_hi"))
		else:
			var box := CardFaceArt.frame(&"ribbon")
			if box != null:
				draw_style_box(box, r)
		RailArt.draw_digits(self, (r.position + (r.size - Vector2(RailArt.digits_width(t, cell), 7 * cell)) * 0.5).round(),
				t, cell, CardFaceArt.px(&"paper_hi"))
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = CardFaceArt.flat(&"pink")
		var ink := CardFaceArt.flat(&"ink")
		match style:
			&"card_give":
				sb.bg_color = CardFaceArt.flat(&"give")
			&"card_epic":
				sb.bg_color = CardFaceArt.flat(&"epic")
			&"card_common":
				sb.bg_color = CardFaceArt.flat(&"common")
				ink = CardFaceArt.flat(&"text")
		sb.set_corner_radius_all(int(12 * u))
		draw_style_box(sb, r)
		_text(r.position + Vector2(0, 4 * u), t, fs, ink, true, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## M50.7: the gain line (two lines at most): on a mechanic rank the pink mechanic icon and its
## bold name first (CardArt.MECHS on Pixel, a pink diamond on tier 0).
func _gain(at: Vector2, width: float, fs: float, col: Color, pink: Color) -> void:
	var u := _u()
	var gain := String(face.get("gain", ""))
	var mech: StringName = face.get("mech", &"")
	var x := at.x * u
	if mech != &"":
		if pixel():
			CardArt.draw_mech(self, mech, Vector2(x, at.y * u + 1 * u), maxf(1.0, roundf(2 * u)))
		else:
			var c := Vector2(x + 7 * u, at.y * u + 8 * u)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6) * u, c + Vector2(6, 0) * u, c + Vector2(0, 6) * u,
					c + Vector2(-6, 0) * u]), pink)
		x += 22 * u
	var gf := _px(fs)
	var mech_name := String(face.get("mech_name", ""))
	if mech_name != "" and gain.to_lower().begins_with(mech_name.to_lower() + ":"):
		gain = gain.substr(mech_name.length() + 1).strip_edges()
	# M50.7 review: a gain longer than two lines drops its last whole sentences ("joins your hand:
	# The gun you started with." not "... It still"); one sentence still too long ends in "...".
	var p := _gain_paragraph(mech_name, gain, at.x * u + width * u - x, gf)
	while p.get_line_count() > 2 and gain.rfind(". ") > 0:
		gain = gain.substr(0, gain.rfind(". ") + 1)
		p = _gain_paragraph(mech_name, gain, at.x * u + width * u - x, gf)
	gain_drawn = gain
	p.max_lines_visible = 2
	p.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	p.draw(get_canvas_item(), Vector2(x, at.y * u), col)


func _gain_paragraph(mech_name: String, gain: String, width: float, gf: int) -> TextParagraph:
	var p := TextParagraph.new()
	p.width = width
	if mech_name != "":
		p.add_string(mech_name + ": ", _font(true), gf)
	p.add_string(gain, _font(), gf)
	return p


## M50.7: the next mechanic a numbers-only rank leads to ("NEXT: +SEEKER"), bottom left of the
## art box on a `bg` block in `col`.
func _next_tag(art: Rect2, bg: Color, col: Color, fs: float) -> void:
	next_drawn = ""
	var nxt := String(face.get("next", ""))
	if nxt == "":
		return
	var u := _u()
	var t := "NEXT: " + nxt.to_upper()
	var room := art.size.x - 12 * u
	if pixel():
		# M50.7 review: the rail's block capitals (Pixelify's small C read as O and G as B), the
		# words wrapped to a second row rather than cut at the art box's edge.
		var rows := next_rows("NEXT " + nxt.to_upper(), room - 10.0, NEXT_CELL)
		var wmax := 0.0
		for row in rows:
			wmax = maxf(wmax, RailArt.digits_width(row, NEXT_CELL))
		var h := rows.size() * 7.0 * NEXT_CELL + (rows.size() - 1) * 3.0 + 8.0
		var br := Rect2(Vector2(art.position.x + 6 * u, art.end.y - 6 * u - h), Vector2(minf(room, wmax + 10.0), h))
		draw_rect(br, bg)
		for k in rows.size():
			RailArt.draw_digits(self, (br.position + Vector2(5.0, 4.0 + k * (7.0 * NEXT_CELL + 3.0))).round(), rows[k],
					NEXT_CELL, col)
		next_drawn = t
		next_rows_drawn = rows
		return
	# Flat: the whole tag, its size stepped down until it fits (never cut).
	var f := _font(true)
	var s := _px(fs)
	while s > 7 and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x + 10 * u > room:
		s -= 1
	var tw := minf(room, f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x + 10 * u)
	var tr := Rect2(Vector2(art.position.x + 6 * u, art.end.y - 24 * u), Vector2(tw, 18 * u))
	draw_rect(tr, bg)
	draw_string(f, Vector2(tr.position.x + 5 * u, tr.position.y + 2 * u + f.get_ascent(s)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, s, col)
	next_drawn = t
	next_rows_drawn = [t]


## M50.7 review: `text` in rows of block capitals at `cell`, none wider than `width` (word wrap;
## a word longer than a row keeps a row of its own).
static func next_rows(text: String, width: float, cell: float) -> Array[String]:
	var rows: Array[String] = [""]
	for w in text.split(" ", false):
		var cand := w if rows[-1] == "" else rows[-1] + " " + w
		if rows[-1] != "" and RailArt.digits_width(cand, cell) > width:
			rows.append(w)
		else:
			rows[-1] = cand
	return rows


## Rank pips: the held ranks on, this card's new ranks in pink, then "+N". M50.7: a mechanic
## rank's pip is taller (tall_pip), as the Auto cards draw them.
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
		var rk := k + 1 + (rank - PIPS if rank > PIPS else 0)   # the rank this pip stands for
		var tall := tall_pip(rk - 1)
		if square:
			var pr := Rect2(c - Vector2(0, 5 * u if tall else 0.0), Vector2(11, 16 if tall else 11) * u)
			draw_rect(pr.grow(2 * u), CardFaceArt.px(&"ink"))
			draw_rect(pr, on_col)
		elif tall:
			var m := c + Vector2(5.5, 5.5) * u
			draw_colored_polygon(PackedVector2Array([m + Vector2(0, -8) * u, m + Vector2(6, 0) * u, m + Vector2(0, 7) * u,
					m + Vector2(-6, 0) * u]), on_col)
		else:
			draw_circle(c + Vector2(5.5, 5.5) * u, 5.5 * u, on_col)
	if rank > from:
		_text((at + Vector2(n * 16 + 2, -4)) * u, "+%d" % (rank - from), 15,
				CardFaceArt.px(&"red") if square else CardFaceArt.flat(&"red"), true)


## The picture(s) in the art box. M50.5a (the Arcade_Cards sheet): the weapon's gun, Auto's
## M50.4f art (CardArt's pixel guns, WeaponGlyph's flat guns), not its shot. FUSE: the fused gun
## in the middle, both parents' small guns in the lower corners.
func _art(art: Rect2) -> void:
	var u := _u()
	if face.get("style") == &"card_fuse":
		var pb := Vector2(40, 18) * u
		_gun(face.get("icon_a", &""), art.position + Vector2(24, art.size.y / u - 12) * u, pb, 1.0)
		_gun(face.get("icon_b", &""), art.end - Vector2(24, 12) * u, pb, 1.0)
		_gun(face.get("icon", &""), art.get_center() + Vector2(0, -6 * u), Vector2(84, 30) * u, 1.0)
		return
	_gun(face.get("icon", &""), art.get_center() + Vector2(0, -3 * u), Vector2(art.size.x - 16 * u, art.size.y - 14 * u), 2.0)


## M50.5a: the gun of `icon` centred at `centre`, filling `box`: Pixel draws CardArt's grid (the
## shot glyph for a weapon without one), tier 0 WeaponGlyph's flat gun.
func _gun(icon: StringName, centre: Vector2, box: Vector2, least: float) -> void:
	if icon == &"":
		return
	if pixel():
		if CardArt.draw_card_art(self, icon, centre, box, 7.0, least).has_area():
			art_drawn.append([icon, &"gun"])
			return
		WeaponGlyph.draw(self, icon, centre, minf(box.x, box.y), Color.WHITE)
		art_drawn.append([icon, &"glyph"])
		return
	WeaponGlyph.draw_card_flat(self, icon, centre, minf(box.x * 0.7, box.y * 1.4), Color.WHITE)
	art_drawn.append([icon, &"flat" if icon in WeaponGlyph.FLAT_GUNS else &"glyph"])


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
		&"card_epic":   # M50.6: a double violet edge
			sb.border_color = Palette.color(&"card_epic")
			sb.set_border_width_all(int(5 * u))
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
	if style == &"card_epic":   # the inner line of the double edge
		var inner := StyleBoxFlat.new()
		inner.bg_color = Color(1, 1, 1, 0)
		inner.border_color = CardFaceArt.flat(&"face")
		inner.set_border_width_all(maxi(1, int(1.5 * u)))
		inner.set_corner_radius_all(int(10 * u))
		draw_style_box(inner, Rect2(Vector2.ZERO, size).grow(-2 * u))
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
	_next_tag(art, CardFaceArt.flat(&"back"), CardFaceArt.flat(&"pink"), 10.0)
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
		_gain(Vector2(14, 182), 150, 11, CardFaceArt.flat(&"text"), CardFaceArt.flat(&"pink"))
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
		_gun(icon, art.get_center(), art.size - Vector2(4, 4) * u, 1.0)
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
		_gun(icon, r.position + Vector2(26, 25) * u, Vector2(46, 34) * u, 1.0)
		var f := UiTheme.font()
		var s := int(roundf(15 * u))
		draw_string(f, Vector2(52 * u, 8 * u + f.get_ascent(s)), title, HORIZONTAL_ALIGNMENT_LEFT, -1, s, CardFaceArt.flat(&"text"))
		draw_string(f, Vector2(52 * u, 28 * u + f.get_ascent(int(11 * u))), "rank %d" % rank, HORIZONTAL_ALIGNMENT_LEFT,
				-1, int(11 * u), CardFaceArt.flat(&"gold"))


## M50.7: a give / replace step's choice. A hand card (MINI_HAND's strip at MINI_CHOICE) with its
## key chip top right and its verb ("replace", or the kept partner's "keep"); the focus is a gold
## ring outside the card; the recipe partner (`link`) a mint edge and the socket with its note; the
## locked partner (`lock`) dimmed under a lock, never lit. The chip (style &"chip"): Keep your hand
## or Back, its key on the left.
func _draw_choice() -> void:
	var px := pixel()
	var gold := CardFaceArt.px(&"gold") if px else CardFaceArt.flat(&"gold")
	var ink := CardFaceArt.px(&"ink")
	var mint := CardFaceArt.px(&"mint")
	var r := Rect2(Vector2.ZERO, size)
	var u := size.y / 50.0
	if lit:
		draw_rect(r.grow(7), ink)
		draw_rect(r.grow(5), gold)
	var key := String(face.get("foot", ""))
	if face.get("style") == &"chip":
		if px:
			draw_rect(r, ink)
			draw_rect(r.grow(-3), CardFaceArt.px(&"paper_lo") if lit else CardFaceArt.px(&"cell"))
		else:
			var sb := StyleBoxFlat.new()
			sb.bg_color = CardFaceArt.flat(&"face")
			sb.border_color = CardFaceArt.flat(&"edge")
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(int(size.y * 0.5))
			draw_style_box(sb, r)
		var f := UiTheme.pixel_font(true) if px else UiTheme.font()
		var s := UiTheme.pixel_size(17) if px else 17
		var x := 12.0
		if key != "":
			x += _key_chip(Vector2(x, (size.y - 26) * 0.5), key) + 10.0
		var tc := ink if px and lit else (CardFaceArt.px(&"paper") if px else CardFaceArt.flat(&"text"))
		draw_string(f, Vector2(x, size.y * 0.5 + f.get_ascent(s) * 0.4), String(face.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT,
				size.x - x - 8, s, tc)
		return
	_draw_hand()
	var linked := bool(face.get("link", false))
	var locked := bool(face.get("lock", false))
	if linked:
		draw_rect(r.grow(-1), mint, false, 3.0)
	if key != "":
		_key_chip(Vector2(size.x - 8 - _key_w(key), 6), key)
	var f2 := UiTheme.pixel_font(true) if px else UiTheme.font()
	var s2 := UiTheme.pixel_size(int(roundf(11 * u))) if px else int(roundf(11 * u))
	var verb := String(face.get("verb", "")).to_upper()
	var note := String(face.get("note", ""))
	var vx := 57.0 * u + 56.0 * u
	var vy := 28.0 * u + f2.get_ascent(s2)
	if linked:   # M50.7 review: the mint word on an ink chip (mint on the cream card was faint)
		var vw := f2.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, s2).x
		draw_rect(Rect2(Vector2(vx - 4, vy - f2.get_ascent(s2) - 2), Vector2(vw + 8, f2.get_height(s2) + 4)), ink)
	draw_string(f2, Vector2(vx, vy), verb, HORIZONTAL_ALIGNMENT_LEFT, -1, s2,
			mint if linked else (ink if px else CardFaceArt.flat(&"dim")))
	if note != "":
		var sock := Vector2(size.x - 18, size.y - 14)
		_socket(sock, 2 if not locked else 1, 6.0)
		# Under the card, clear of the focus ring (inside, "links with the Laser" was cut short).
		var ns := s2 - 1
		draw_string(f2, Vector2(-20, size.y + 10 + f2.get_ascent(ns)), note, HORIZONTAL_ALIGNMENT_CENTER, size.x + 40, ns,
				mint if linked else (gold if px else CardFaceArt.flat(&"dim")))
	if locked:
		draw_rect(r, Color(ink, 0.45))
		var c := Vector2(size.x - 26, size.y * 0.5 + 4)
		draw_arc(c + Vector2(0, -7), 6.0, PI, TAU, 10, gold, 3.0)
		draw_rect(Rect2(c + Vector2(-9, -6), Vector2(18, 14)), gold)
		draw_rect(Rect2(c + Vector2(-2, -2), Vector2(4, 6)), ink)


## M50.7: a chip's width for `title` and `key` (its key chip, the gap, the text, the margins),
## at least MINI_CHIP's: "Back to the pack" no longer cut short.
static func chip_width(title: String, key: String) -> float:
	var f := UiTheme.pixel_font(true) if pixel() else UiTheme.font()
	var s := UiTheme.pixel_size(17) if pixel() else 17
	var kw := 0.0
	if key != "":
		kw = maxf(26.0, f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 12.0) + 10.0
	return maxf(MINI_CHIP.x, ceilf(12.0 + kw + f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x + 16.0))


func _key_w(key: String) -> float:
	var f := UiTheme.pixel_font(true) if pixel() else UiTheme.font()
	return maxf(26.0, f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 12.0)


## M50.7: the key chip (an ink block, the key in gold); returns its width.
func _key_chip(at: Vector2, key: String) -> float:
	var f := UiTheme.pixel_font(true) if pixel() else UiTheme.font()
	var w := _key_w(key)
	var kr := Rect2(at, Vector2(w, 26))
	draw_rect(kr, CardFaceArt.px(&"ink"))
	draw_rect(Rect2(kr.position, Vector2(kr.size.x, 2)), CardFaceArt.px(&"gold_lo"))
	draw_string(f, Vector2(kr.position.x, kr.position.y + 5 + f.get_ascent(15)), key, HORIZONTAL_ALIGNMENT_CENTER, w, 15,
			CardFaceArt.px(&"gold"))
	return w


## M50.7: the hand preview's link socket (face.link 1 dim, 2 ready: gold and "fuse ready").
func _draw_socket() -> void:
	var state := int(face.get("link", 0))
	if state <= 0:
		return
	_socket(Vector2(size.x * 0.5, size.y * 0.4), state, 9.0)
	if state == 2:
		if pixel():   # M50.7 review: block capitals (Pixelify at 11 px read "Pueeready")
			var w := RailArt.digits_width("READY", 2.0)
			draw_rect(Rect2(Vector2((size.x - w) * 0.5 - 3.0, size.y - 19.0), Vector2(w + 6.0, 18.0)), CardFaceArt.px(&"ink"))
			RailArt.draw_digits(self, Vector2(roundf((size.x - w) * 0.5), size.y - 17.0), "READY", 2.0, CardFaceArt.px(&"gold"))
			return
		var f := UiTheme.font()
		draw_string(f, Vector2(-20, size.y - 2), "fuse ready", HORIZONTAL_ALIGNMENT_CENTER, size.x + 40, 11, CardFaceArt.px(&"gold"))


## The socket: two half rings joined by a bar (dim plum, or gold when ready).
func _socket(c: Vector2, state: int, rad: float) -> void:
	var col := CardFaceArt.px(&"gold") if state == 2 else CardFaceArt.px(&"gem")
	draw_circle(c, rad + 3, CardFaceArt.px(&"ink"))
	draw_arc(c + Vector2(-rad * 0.45, 0), rad * 0.55, PI * 0.5, PI * 1.5, 8, col, 3.0)
	draw_arc(c + Vector2(rad * 0.45, 0), rad * 0.55, -PI * 0.5, PI * 0.5, 8, col, 3.0)
	draw_line(c - Vector2(rad * 0.5, 0), c + Vector2(rad * 0.5, 0), col, 3.0)
	if state == 1:
		var f := UiTheme.pixel_font(true) if pixel() else UiTheme.font()
		draw_string(f, c + Vector2(-rad, rad + 14), str(BoosterPack.FUSE_RANK), HORIZONTAL_ALIGNMENT_CENTER, rad * 2, 12, col)


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
		_gun(icon, art.get_center(), art.size - Vector2(6, 6) * u, 1.0)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = CardFaceArt.flat(&"face")
		sb.border_color = CardFaceArt.flat(&"edge")
		if style == &"card_rare":
			sb.border_color = Palette.color(&"card_rare")
		elif style == &"card_epic":
			sb.border_color = Palette.color(&"card_epic")
		sb.set_border_width_all(int(3 * u) if style in [&"card_rare", &"card_epic"] else 2)
		sb.set_corner_radius_all(int(8 * u))
		draw_style_box(sb, card)
		draw_rect(Rect2(card.position + Vector2(14, 8) * u, Vector2(14, 3) * u), CardFaceArt.band(icon)[0])
		_gun(icon, card.position + Vector2(card.size.x * 0.5, 38 * u), Vector2(card.size.x - 16 * u, 36 * u), 1.0)
	var digits := str(int(face.get("rank", 1)))
	var cellpx := maxf(1.0, roundf(2 * u))
	var bw := RailArt.digits_width(digits, cellpx) + 8 * u
	var badge := Rect2(Vector2(card.position.x + (card.size.x - bw) * 0.5, card.end.y - 24 * u), Vector2(bw, 18 * u))
	draw_rect(badge, CardFaceArt.px(&"ink"))
	RailArt.draw_digits(self, (badge.position + Vector2(4 * u, (badge.size.y - 7 * cellpx) * 0.5)).round(), digits, cellpx,
			CardFaceArt.px(&"gold"))
