class_name CabinetCard
extends RefCounted
## M48.6d: a pack card's face in the cabinet (PLAN 0.9.2 "Packs and cards"; the mockup's aCard /
## pxCardEl), 72x109 art px. The tier is the frame and its ribbon: common (plum), rare (gold, a
## crown), epic (holo, arched, a star), fuse (prism stripes, cut corners, a PERMANENT tag). On
## it: the rank chip, the gun's splash art in the art window with nothing over it but small tags
## in its corner (NEW, NEW TRICK), the name plate, two or three lines of text INSIDE the paper
## box, the rank segments (lit, then the ones this card adds, blinking) and the key cap.
##
## The paper box holds three rows of about 14 letters, so a card says the short form of its
## line (the first of its `opts` that fits: the full gain, else the trick's name, else "+damage");
## the full line is the spec's `detail`, which the pack stage prints under the focused card.
##
## A spec is plain data (spec_of / fuse_spec / hand_spec), so tests read what a card shows;
## draw() paints one from ArcadePaint's textures plus the two texts in the pixel font. No rays,
## no halo, no banner over a card. What moves by itself (the foil's shimmer, the twinkles, the
## muzzle flash, the blinking segments) is still under reduce flashing.
## Presentation only: no RNG, no Tuning, no rules.

const W := ArcadePaint.CARD_W
const H := ArcadePaint.CARD_H
const TIERS: Array[StringName] = [&"common", &"rare", &"epic", &"fuse"]
const TICK_MS := 125     ## the art's own clock (8 steps a second)
const ROWS := 3          ## the most text rows in the paper box


## The tier a pack card wears: its weapon's rarity (BoosterPack: common, rare, epic).
static func tier_of(c: Dictionary) -> StringName:
	var t: StringName = c.get("rarity", BoosterPack.COMMON)
	return t if t in TIERS else &"common"


static func _parents(id: StringName) -> Array:
	var w := WeaponDB.get_weapon(id)
	return Array(w.parents) if w != null and not ArcadePaint.has_splash(id) else []


static func _pair(a: StringName, b: StringName) -> Array:
	var wa := WeaponDB.get_weapon(a)
	var wb := WeaponDB.get_weapon(b)
	var ta := String(wa.title) if wa != null else "?"
	var tb := String(wb.title) if wb != null else "?"
	return ["%s + %s" % [ta, tb], "%s. + %s" % [ta.left(4), tb], "%s + %s" % [ta.left(4), tb.left(4)]]


## The face of pack card `c` (BoosterPack.card's dict) with its key label ("1"; "" none).
## `replaces`: the hand is full and this NEW card will ask which card goes out.
static func spec_of(c: Dictionary, key := "", replaces := false) -> Dictionary:
	var id: StringName = c.get("id", &"")
	var w := WeaponDB.get_weapon(id)
	var tier := tier_of(c)
	var rank := int(c.get("rank", 1))
	var from := int(c.get("from", 0))
	var kind: StringName = c.get("kind", &"new")
	var face := CardFace.face_of(c)
	var tags: Array = []
	var text: Array = []
	if kind == &"upgrade":
		var trick := String(face.get("mech_name", ""))
		var opts: Array = [String(face.gain)]
		if trick != "":
			tags.append(["NEW TRICK", ArcadePaint.MINT, ArcadePaint.INK])
			opts.append(trick)
		opts.append("+damage")
		text.append({"opts": opts, "c": &"ink"})
		var nxt := String(face.get("next", ""))
		text.append({"opts": ["next: %s" % nxt, "> %s" % nxt] if nxt != "" else ["held: rank %d" % from], "c": &"pitch"})
	else:
		tags.append(["NEW", ArcadePaint.MINT, ArcadePaint.INK])
		var gain := String(c.get("gain", ""))
		var have := gain.get_slice(": ", 1) if gain.contains(": ") else (String(w.pitch) if w != null else "")
		if BoosterPack.is_epic(c):
			text.append({"opts": ["Fusion. " + have, "Fusion."], "c": &"ink"})
			if w != null and w.parents.size() == 2:
				text.append({"opts": _pair(w.parents[0], w.parents[1]), "c": &"pitch", "rows": 2})
		else:
			text.append({"opts": ["New. " + have, "New. " + have.get_slice(". ", 0).trim_suffix(".") + ".", "New."], "c": &"ink"})
			if not replaces:
				text.append({"opts": ["free slot"], "c": &"pitch"})
		if replaces:
			text.append({"opts": ["swaps a card"], "c": &"warn"})
	return {"tier": tier, "id": id, "fuse": false, "name": (String(w.title) if w != null else String(id)).to_upper(),
			"rank": rank, "key": key, "pips": [mini(from, 6), mini(rank, 6)], "recipe": "", "tags": tags, "text": text,
			"sparks": tier != &"common", "parents": _parents(id), "detail": String(c.get("text", c.get("title", "")))}


## A kept mechanic's line as two or three words ("centre beam burns 1 s" > "centre beam burns").
static func short_trait(t: String) -> String:
	var out := PackedStringArray()
	for word in t.get_slice(":", 0).split(" ", false):
		var digit := false
		for i in word.length():
			if word[i] >= "0" and word[i] <= "9":
				digit = true
		if digit:
			break
		out.append(word)
	return " ".join(out) if not out.is_empty() else t


## The FUSE choice's face (BoosterPack.fuse_option's dict): the fused weapon on the prism frame,
## what it keeps and what it loses in the paper box, its parents as the last line.
static func fuse_spec(f: Dictionary, key := "") -> Dictionary:
	var id: StringName = f.get("id", &"")
	var fw := WeaponDB.get_weapon(id)
	var text: Array = []
	var keeps: Array = f.get("keeps", [])
	if not keeps.is_empty():
		var short := PackedStringArray()
		for k: String in keeps:
			short.append(short_trait(k))
		text.append({"opts": ["Keeps " + ", ".join(short), "Keeps %d trick%s" % [keeps.size(), "" if keeps.size() == 1 else "s"]], "c": &"keep",
				"rows": 2})
	var loses: Array = f.get("loses", [])
	if not loses.is_empty():
		text.append({"opts": ["Loses " + ", ".join(loses), "Loses %d trick%s" % [loses.size(), "" if loses.size() == 1 else "s"]], "c": &"warn"})
	# The two parents by name where a row holds them; else that it takes both (the dock shows which).
	text.append({"opts": [_pair(f.get("a", &""), f.get("b", &""))[0], "takes both cards", "takes both"], "c": &"pitch"})
	return {"tier": &"fuse", "id": id, "fuse": true, "name": (String(fw.title) if fw != null else "FUSE").to_upper(),
			"rank": int(f.get("rank", 0)), "key": key, "pips": [], "recipe": "RANK %d" % int(f.get("rank", 0)),
			"tags": [["PERMANENT", ArcadePaint.GOLD, ArcadePaint.INK]], "text": text, "sparks": true,
			"parents": _parents(id), "detail": String(f.get("text", f.get("title", ""))).replace("\n", " · ")}


## A held card's face ({id, title, rank}): the fuse moment's two parents.
static func hand_spec(h: Dictionary) -> Dictionary:
	var id: StringName = h.get("id", &"")
	var w := WeaponDB.get_weapon(id)
	var tier: StringName = w.rarity if w != null and w.rarity in TIERS else &"common"
	var rank := int(h.get("rank", 1))
	return {"tier": tier, "id": id, "fuse": false, "name": String(h.get("title", id)).to_upper(), "rank": rank, "key": "",
			"pips": [mini(rank, 6), mini(rank, 6)], "recipe": "", "tags": [], "sparks": false, "parents": _parents(id),
			"text": [{"opts": ["in your hand"], "c": &"pitch"}], "detail": ""}


## The fused card as it slams in (the fuse moment's result).
static func fused_spec(id: StringName, rank: int) -> Dictionary:
	var w := WeaponDB.get_weapon(id)
	var text: Array = [{"opts": ["Fused."], "c": &"ink"}]
	if w != null and w.parents.size() == 2:
		text.append({"opts": _pair(w.parents[0], w.parents[1]), "c": &"pitch", "rows": 2})
	return {"tier": &"fuse", "id": id, "fuse": true, "name": (String(w.title) if w != null else String(id)).to_upper(),
			"rank": rank, "key": "", "pips": [], "recipe": "RANK %d" % rank,
			"tags": [["PERMANENT", ArcadePaint.GOLD, ArcadePaint.INK]], "sparks": true, "parents": _parents(id),
			"text": text, "detail": ""}


# --- Text -----------------------------------------------------------------------------------------

## `t` wrapped to `width` px at `size` (words; a word wider than the row breaks inside).
static func wrap_text(t: String, size: int, width: float, bold := false) -> PackedStringArray:
	var out := PackedStringArray()
	var row := ""
	for word in t.split(" ", false):
		var probe := word if row == "" else row + " " + word
		if RailFrame.text_w(probe, size, bold) <= width:
			row = probe
			continue
		if row != "":
			out.append(row)
		row = word
		while RailFrame.text_w(row, size, bold) > width and row.length() > 1:
			var n := row.length() - 1
			while n > 1 and RailFrame.text_w(row.left(n), size, bold) > width:
				n -= 1
			out.append(row.left(n))
			row = row.substr(n)
	if row != "":
		out.append(row)
	return out


## The paper box's rows for `spec` at `a` screen px per art px and scale `s`: {size, step, rows:
## [{t, c}]}, never more than ROWS, every row inside the box (the text inner rect, 56x24 art px).
## Each paragraph says the longest of its `opts` that leaves the paragraphs after it a row
## each (the rule may take two or three rows; every other paragraph one, or its `rows`); a last
## option still too long is cut and ends with "..".
static func text_rows(spec: Dictionary, a: float, s: float) -> Dictionary:
	var l: Dictionary = ArcadeArt.CARD_LAYOUT[spec.get("tier", &"common")]
	var bw := float(l.textInner[2]) * a
	var bh := float(l.textInner[3]) * a
	var size := CabinetLayout.text_px(2, s)
	var step := roundf(size * 10.0 / 11.0)
	var most := clampi(floori((bh + step - size) / step), 1, ROWS)
	var paras: Array = spec.get("text", [])
	var rows: Array = []
	for i in paras.size():
		var para: Dictionary = paras[i]
		var room := most - rows.size() - (paras.size() - 1 - i)
		if room <= 0:
			break
		var opts: Array = para.opts
		if para.c != &"ink":   # a last line (the pitch, a warning, keeps / loses) wants one row
			room = mini(room, int(para.get("rows", 1)))
		var got := PackedStringArray()
		for k in opts.size():
			got = wrap_text(String(opts[k]), size, bw)
			if got.size() <= room:
				break
		if got.size() > room:
			got.resize(room)
			var cut := got[room - 1]
			while cut.length() > 1 and RailFrame.text_w(cut + "..", size) > bw:
				cut = cut.left(cut.length() - 1)
			got[room - 1] = cut + ".."
		for row in got:
			rows.append({"t": row, "c": para.c})
	return {"size": size, "step": step, "rows": rows}


## The rect the text rows take inside a card whose top-left is at `at` (screen px): for tests
## and captures ("the text is inside the paper box").
static func text_rect(spec: Dictionary, at: Vector2, a: float, s: float) -> Rect2:
	var l: Dictionary = ArcadeArt.CARD_LAYOUT[spec.get("tier", &"common")]
	var rows := text_rows(spec, a, s)
	var w := 0.0
	for r: Dictionary in rows.rows:
		w = maxf(w, RailFrame.text_w(String(r.t), int(rows.size)))
	var n: int = (rows.rows as Array).size()
	var h := 0.0 if n == 0 else (n - 1) * float(rows.step) + float(rows.size) * 9.0 / 11.0
	return Rect2(at + Vector2(l.textInner[0], l.textInner[1]) * a, Vector2(w, h))


## The paper box (the text's inner rect) of a card at `at`.
static func paper_rect(spec: Dictionary, at: Vector2, a: float) -> Rect2:
	var l: Dictionary = ArcadeArt.CARD_LAYOUT[spec.get("tier", &"common")]
	return Rect2(at + Vector2(l.textInner[0], l.textInner[1]) * a, Vector2(l.textInner[2], l.textInner[3]) * a)


static func tick() -> int:
	return int(Time.get_ticks_msec() / float(TICK_MS))


# --- Drawing --------------------------------------------------------------------------------------

## Draws the card with its top-left at `at` (screen px), `a` screen px per art px, texts at
## scale `s`. `o`: back (face-down), sx (the flip's width 0..1 about the card's middle), shade
## (0..1: a row waiting behind), cell (art px override: a smaller waiting card), t (the art
## clock), still (reduce flashing: nothing on the card moves), alpha.
static func draw(ci: CanvasItem, spec: Dictionary, at: Vector2, a: float, s: float, o := {}) -> void:
	var cell := float(o.get("cell", a))
	var sx := clampf(float(o.get("sx", 1.0)), 0.0, 1.0)
	var shade := clampf(float(o.get("shade", 0.0)), 0.0, 1.0)
	var alpha := clampf(float(o.get("alpha", 1.0)), 0.0, 1.0)
	var still := bool(o.get("still", false))
	var t := 0 if still else int(o.get("t", tick()))
	var v := 1.0 - shade
	var tint := Color(v, v, v, alpha)
	var size := Vector2(W, H) * cell
	var mid := at.x + size.x * 0.5
	var r := Rect2(Vector2(mid - size.x * 0.5 * sx, at.y), Vector2(size.x * sx, size.y))
	if bool(o.get("back", false)) or sx < 0.05:
		ci.draw_texture_rect(ArcadePaint.back_tex(), r, false, tint)
		return
	var tier: StringName = spec.get("tier", &"common")
	var l: Dictionary = ArcadeArt.CARD_LAYOUT[tier]
	ci.draw_texture_rect(ArcadePaint.frame_tex(tier, t % 4), r, false, tint)
	# The art window: the gun, its muzzle flash two steps in seven; a FUSE card's lightning.
	var fuse := bool(spec.get("fuse", false))
	var anim := 0
	if fuse:
		anim = -1 if still else t % 4
	elif not still and t % 7 < 2:
		anim = 1 + t % 7
	var ai: Array = l.artInner
	var art := Rect2(Vector2(r.position.x + ai[0] * cell * sx, at.y + ai[1] * cell), Vector2(ai[2] * cell * sx, ai[3] * cell))
	ci.draw_texture_rect(ArcadePaint.art_tex(spec.get("id", &""), fuse, anim, spec.get("parents", [])), art, false, tint)
	ci.draw_texture_rect(ArcadePaint.overlay_tex(spec), r, false, tint)
	var pips: Array = spec.get("pips", [])
	if not still and pips.size() == 2 and int(pips[1]) > int(pips[0]) and t % 4 < 2:
		ci.draw_texture_rect(ArcadePaint.pips_hot_tex(tier, pips), r, false, tint)
	if bool(spec.get("sparks", false)) and not still:
		for k in ArcadePaint.SPARKS.size():
			var f := (t + k * 3) % 10
			if f < 4:
				var p: Vector2 = ArcadePaint.SPARKS[k]
				ci.draw_texture_rect(ArcadePaint.spark_tex(f), Rect2(Vector2(r.position.x + p.x * cell * sx, at.y + p.y * cell),
						Vector2(5 * cell * sx, 5 * cell)), false, tint)
	if sx < 0.9 or cell < a - 0.01:
		return   # mid flip, or a small waiting card: no text
	# The name on its plate and the rows in the paper box, in the pixel font on its grid.
	var label := String(spec.get("name", ""))
	var name_size := RailFrame.fit(label, CabinetLayout.text_px(2, s), l.nameText[2] * a, false, 11)
	var font := UiTheme.pixel_font()
	var cap_h := name_size * 7.0 / 11.0
	var ny := roundf(at.y + l.nameText[1] * a + (l.nameText[3] * a - cap_h) * 0.5 - (font.get_ascent(name_size) - cap_h))
	RailFrame.text(ci, Vector2(at.x + l.nameText[0] * a, ny), label, name_size, Color(CabinetArt.c(&"gold_hi"), alpha), false,
			HORIZONTAL_ALIGNMENT_CENTER, l.nameText[2] * a)
	var rows := text_rows(spec, a, s)
	var fs := int(rows.size)
	var ty := roundf(at.y + l.textInner[1] * a - (font.get_ascent(fs) - fs * 9.0 / 11.0))
	for row: Dictionary in rows.rows:
		RailFrame.text(ci, Vector2(roundf(at.x + l.textInner[0] * a), ty), String(row.t), fs, Color(text_color(row.c), alpha))
		ty += float(rows.step)


## A text row's colour by its role: ink (the rule), pitch (the dim last line), warn (what goes
## out, what a fuse loses), keep (what a fuse keeps).
static func text_color(role: StringName) -> Color:
	match role:
		&"pitch":
			return CabinetArt.c(&"hi")
		&"warn":
			return CabinetArt.hex(ArcadePaint.WARN_INK)
		&"keep":
			return CabinetArt.hex(ArcadePaint.KEEP_INK)
	return CabinetArt.hex(ArcadePaint.TEXT_INK)
