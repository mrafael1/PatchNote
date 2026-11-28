class_name ArcadePaint
extends RefCounted
## M48.6d: the painter for ArcadeArt's grids (PLAN 0.9.2): it bakes each piece once into a small
## texture, one texel per art pixel, and the cabinet draws those scaled to its art px with no
## filtering. Pieces: a card's frame (per tier and shimmer phase), its art window (the backdrop
## shape, the gun's splash, the muzzle flash; a FUSE card adds the lightning behind the gun), its
## overlay (rank chip, key cap, tags, pips or the recipe line), the card back, a hand slot and
## the gun's barrel half on its screen, the fuse link, the dock's pack with its badge and gauge,
## the flying pack's frames, the small flying card and the fx sheets' frames.
##
## The 3x5 capitals (PF) are the mockup page's own small font, used only for plates baked into
## the art (tags, tabs, the badge). Colours are the kits' hexes, through CabinetArt.hex.
## Presentation only: no RNG, no Tuning, no rules. No image file.

const INK := "#1e1424"
const MINT := "#6cf0c2"
const GOLD := "#ffd84a"
const PINK := "#ff6b8a"
const SLIP := "#fff8ec"
const TEXT_INK := "#2a1d3a"     ## a card's text row, on the paper
const WARN_INK := "#c0302a"     ## what goes out, what a fuse loses
const KEEP_INK := "#2f7a64"     ## what a fuse keeps
const EPIC_FLASH := "#e3cbff"   ## the dither flash under an epic card
const DOCK_LINE := "#d9c9e8"    ## the dock: "n kills to next"
const DOCK_QUEUE := "#ffc0d0"   ## the dock: "n waiting"
const DOCK_OFF := "#a08cb8"     ## the dock: the call while no pack waits
const ART_W := 58
const ART_H := 34
const CARD_W := 72
const CARD_H := 109
const MINI_W := 24
const MINI_H := 30
## A tier's fx ramp (bursts, rings, sparks).
const TIER_FX := {&"common": &"white", &"rare": &"gold", &"epic": &"epic", &"fuse": &"fuse"}
## The small flying card's colours per tier: [main, light, shade].
const MINI := {&"common": ["#6a5290", "#8a76a8", "#4e3866"], &"rare": ["#ffd84a", "#fff0a0", "#c98a2e"],
		&"epic": ["#c79bff", "#ecdcff", "#7a4fd0"], &"fuse": ["#ff6b8a", "#ffc0d0", "#c23f6e"]}
const SEG_HOT := {"H": "#fff8ec", "P": "#ffc0d0", "S": "#ff6b8a"}
## Where a card's twinkles sit (art px, the mockup's five points).
const SPARKS: Array[Vector2i] = [Vector2i(2, 22), Vector2i(65, 50), Vector2i(4, 96), Vector2i(60, 6), Vector2i(66, 88)]
const PF := {
	"A": ".#./#.#/###/#.#/#.#", "B": "##./#.#/##./#.#/##.", "C": ".##/#../#../#../.##", "D": "##./#.#/#.#/#.#/##.",
	"E": "###/#../##./#../###", "F": "###/#../##./#../#..", "G": ".##/#../#.#/#.#/.##", "H": "#.#/#.#/###/#.#/#.#",
	"I": "###/.#./.#./.#./###", "J": "..#/..#/..#/#.#/.#.", "K": "#.#/#.#/##./#.#/#.#", "L": "#../#../#../#../###",
	"M": "#...#/##.##/#.#.#/#...#/#...#", "N": "#..#/##.#/#.##/#..#/#..#", "O": ".#./#.#/#.#/#.#/.#.",
	"P": "##./#.#/##./#../#..", "Q": ".#./#.#/#.#/.#./..#", "R": "##./#.#/##./#.#/#.#", "S": ".##/#../.#./..#/##.",
	"T": "###/.#./.#./.#./.#.", "U": "#.#/#.#/#.#/#.#/###", "V": "#.#/#.#/#.#/#.#/.#.",
	"W": "#...#/#...#/#.#.#/##.##/#...#", "X": "#.#/#.#/.#./#.#/#.#", "Y": "#.#/#.#/.#./.#./.#.",
	"Z": "###/..#/.#./#../###",
	"0": "###/#.#/#.#/#.#/###", "1": ".#./##./.#./.#./###", "2": "##./..#/.#./#../###", "3": "##./..#/.#./..#/##.",
	"4": "#.#/#.#/###/..#/..#", "5": "###/#../##./..#/##.", "6": ".##/#../###/#.#/###", "7": "###/..#/.#./.#./.#.",
	"8": "###/#.#/###/#.#/###", "9": "###/#.#/###/..#/##.",
	" ": "../../../../..", "+": ".../.#./###/.#./...", "-": ".../.../###/.../...", ".": "././././#",
	":": "./#/./#/.", "!": "#/#/#/./#", "?": "##./..#/.#./.../.#.", "/": "..#/..#/.#./#../#..",
	">": "#../.#./..#/.#./#..", "<": "..#/.#./#../.#./..#", "[": "##/#./#./#./##", "]": "##/.#/.#/.#/##",
}

static var _tex := {}
static var _glyphs := {}


static func hex(h: String) -> Color:
	return CabinetArt.hex(h)


## A tier's fx ramp ({K, W, H, P, S, D, A} hexes).
static func fx_ramp(ramp: StringName) -> Dictionary:
	return ArcadeArt.FX_RAMPS.get(ramp, ArcadeArt.FX_RAMPS[&"gold"])


static func tier_ramp(tier: StringName) -> StringName:
	return TIER_FX.get(tier, &"white")


# --- The compositor -------------------------------------------------------------------------------

static func canvas(w: int, h: int) -> Image:
	return Image.create_empty(w, h, false, Image.FORMAT_RGBA8)


## Paints `grid` on `img` at (x, y), clipped to the image; "." and letters the ramp lacks are
## skipped, as are the letters in `skip`.
static func blit(img: Image, grid: Array, ramp: Dictionary, x: int, y: int, skip := "") -> void:
	var w := img.get_width()
	var h := img.get_height()
	var colors := {}
	for j in grid.size():
		var py := y + j
		if py < 0 or py >= h:
			continue
		var row: String = grid[j]
		for i in row.length():
			var px := x + i
			if px < 0 or px >= w:
				continue
			var ch := row[i]
			if ch == "." or skip.contains(ch):
				continue
			var col: Variant = colors.get(ch)
			if col == null:
				var hx: Variant = ramp.get(ch)
				if hx == null:
					continue
				col = hex(hx)
				colors[ch] = col
			img.set_pixel(px, py, col)


## A filled rect, clipped to the image.
static func box(img: Image, x: int, y: int, w: int, h: int, col: String) -> void:
	var r := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if r.size.x > 0 and r.size.y > 0:
		img.fill_rect(r, hex(col))


static func _glyph(ch: String) -> PackedStringArray:
	if not _glyphs.has(ch):
		_glyphs[ch] = String(PF.get(ch, PF["?"])).split("/")
	return _glyphs[ch]


## The width of `t` in the 3x5 capitals (art px).
static func text_w(t: String, gap := 1) -> int:
	var w := 0
	for ch in t.to_upper():
		w += _glyph(ch)[0].length() + gap
	return maxi(0, w - gap)


## `t` in the 3x5 capitals with its top-left at (x, y); `align` 1 centres on x, 2 ends at x.
static func text(img: Image, t: String, x: int, y: int, col: String, align := 0, gap := 1) -> void:
	t = t.to_upper()
	var w := text_w(t, gap)
	if align == 1:
		x -= w >> 1
	elif align == 2:
		x -= w
	var c := hex(col)
	var iw := img.get_width()
	var ih := img.get_height()
	for ch in t:
		var g := _glyph(ch)
		for j in g.size():
			for i in g[j].length():
				if g[j][i] == "#" and x + i >= 0 and x + i < iw and y + j >= 0 and y + j < ih:
					img.set_pixel(x + i, y + j, c)
		x += g[0].length() + gap


## A cached texture: `make` returns its Image the first time `key` is asked.
static func texture(key: String, make: Callable) -> ImageTexture:
	var t: Variant = _tex.get(key)
	if t == null:
		if _tex.size() > 600:
			_tex.clear()
		t = ImageTexture.create_from_image(make.call())
		_tex[key] = t
	return t


static func grid_tex(key: String, grid: Array, ramp: Dictionary) -> ImageTexture:
	return texture(key, func() -> Image:
		var img := canvas(String(grid[0]).length(), grid.size())
		blit(img, grid, ramp, 0, 0)
		return img)


# --- Cards ----------------------------------------------------------------------------------------

## A tier's frame at shimmer phase `phase` (0 the still one; common has one).
static func frame_tex(tier: StringName, phase: int) -> ImageTexture:
	var c: Dictionary = ArcadeArt.CARD.get(tier, ArcadeArt.CARD[&"common"])
	var frames: Array = c.frames
	var p := posmod(phase, frames.size())
	return grid_tex("frame:%s:%d" % [tier, p], frames[p], c.ramp)


## The card back (the pack kit's, with the logo), on the card's 72x109 grid with its hard drop.
static func back_tex() -> ImageTexture:
	return texture("back", func() -> Image:
		var img := canvas(CARD_W, CARD_H)
		var all := {}
		for k: String in ArcadeArt.PACK_RAMP:
			all[k] = INK
		blit(img, ArcadeArt.CARD_BACK, all, 1, 8)
		blit(img, ArcadeArt.CARD_BACK, ArcadeArt.PACK_RAMP, 1, 6)
		return img)


## The flat backdrop shape behind a splash (the mockup's backdropCv), on a 58x34 image.
static func _backdrop(img: Image, spec: Array) -> void:
	var kind := String(spec[0])
	var ca := hex(spec[1])
	var cb := hex(spec[2])
	for j in ART_H:
		for i in ART_W:
			var dx := i - 29
			var dy := j - 16
			var r := sqrt(float(dx * dx + dy * dy))
			var col := 0   # 0 none, 1 A, 2 B
			match kind:
				"disc":
					col = 2 if r < 9.5 else (1 if r < 14.5 else 0)
				"burst":
					var ax := absi(dx)
					var ay := absi(dy)
					var spike := ax < 2 or ay < 2 or absi(ax - ay) < 2
					col = 2 if r < 8.5 else (1 if r < (16.5 if spike else 11.5) else 0)
				"band":
					var d := absi(dx + dy * 2)
					col = 2 if d < 7 else (1 if d < 15 else 0)
				"rings":
					col = 1 if (r >= 13.0 and r < 15.5) or (r >= 7.5 and r < 9.5) else (2 if r < 4.5 else 0)
				"tri":
					var h := dy + 14
					if h >= 0 and h < 28 and absi(dx) <= h:
						col = 2 if h > 9 and h < 25 and absi(dx) <= h - 9 else 1
				"lines":
					if j % 6 == 2 and i > 4 + (j * 7) % 13 and i < 52 - (j * 5) % 11:
						col = 1
					elif j % 6 == 5 and i > 14 + (j * 3) % 9 and i < 42 + (j * 7) % 10:
						col = 2
			if col > 0:
				img.set_pixel(i, j, ca if col == 1 else cb)


static func _muzzle(img: Image, fx: int, fy: int, f: int) -> void:
	if f == 0:
		for p: Vector2i in [Vector2i(fx, fy - 2), Vector2i(fx + 4, fy - 2), Vector2i(fx, fy + 2), Vector2i(fx + 4, fy + 2)]:
			box(img, p.x, p.y, 1, 1, "#ff8a1c")
		box(img, fx - 1, fy, 8, 1, GOLD)
		box(img, fx + 2, fy - 3, 1, 7, GOLD)
		box(img, fx + 1, fy - 1, 3, 3, SLIP)
	else:
		box(img, fx, fy, 5, 1, GOLD)
		box(img, fx + 2, fy - 2, 1, 5, GOLD)
		box(img, fx + 1, fy, 3, 1, SLIP)


## The art a card or a slot shows for weapon `id`: its own splash, or for a weapon the kit has
## no splash for, nothing (the callers fall back to the parents' icons).
static func has_splash(id: StringName) -> bool:
	return ArcadeArt.SPLASH.has(id)


## A card's art window (58x34) for weapon `id`: the backdrop shape, the splash where its ink box
## centres, and at `anim` 1 or 2 the muzzle flash's two frames (0: none). A FUSE card (`fuse`)
## sits on the fuse band with lightning behind the gun (`anim` 0..3 picks its frames; -1 none).
## `parents`: the two icons side by side when the kit has no splash for `id`.
static func art_tex(id: StringName, fuse := false, anim := 0, parents: Array = []) -> ImageTexture:
	return texture("art:%s:%s:%d:%s" % [id, fuse, anim, parents], func() -> Image:
		var img := canvas(ART_W, ART_H)
		var bk: Variant = ArcadeArt.BACKDROP.get(&"fuse" if fuse else id)
		if bk != null:
			_backdrop(img, bk)
		if fuse and anim >= 0:
			var bolt: Array = ArcadeArt.FX[&"lightning"].frames
			blit(img, bolt[anim % bolt.size()], fx_ramp(&"cool"), 9, 1)
			blit(img, bolt[(anim + 2) % bolt.size()], fx_ramp(&"fuse"), 9, 20)
		if has_splash(id):
			var m: Dictionary = ArcadeArt.SPLASH_META[id]
			blit(img, ArcadeArt.SPLASH[id], ArcadeArt.GUN_RAMP, int(m.ox), int(m.oy))
			if not fuse and anim > 0 and bool(m.muz):
				_muzzle(img, int(m.ox) + int(m.mx) + 2, int(m.oy) + int(m.my), anim - 1)
		else:
			var x := 29 - parents.size() * 11
			for p: StringName in parents:
				if ArcadeArt.ICON.has(p):
					blit(img, ArcadeArt.ICON[p], ArcadeArt.GUN_RAMP, x, 10, "z")
				x += 22
		return img)


## A 7x9 key cap with `label` (one 3x5 glyph), mint when `lit`.
static func _keycap(img: Image, x: int, y: int, label: String, lit := false) -> void:
	var r: Dictionary = CabinetArt.ORN[&"keycap_lit" if lit else &"keycap"].ramp
	box(img, x + 1, y, 5, 9, INK)
	box(img, x, y + 1, 7, 7, INK)
	box(img, x + 1, y + 1, 5, 7, r.P)
	box(img, x + 1, y + 1, 5, 1, r.H)
	box(img, x + 1, y + 7, 5, 1, r.L)
	text(img, label.left(1), x + 2, y + 2, INK)


static func _tag(img: Image, t: String, x: int, y: int, bg: String, fg: String) -> int:
	var w := text_w(t) + 4
	box(img, x, y, w, 9, INK)
	box(img, x + 1, y + 1, w - 2, 7, bg)
	text(img, t, x + 2, y + 2, fg)
	return w


static func _rank_chip(img: Image, x: int, y: int, rank: int) -> void:
	var two := str(rank).length() > 1
	var chip: Dictionary = CabinetArt.ORN[&"rank_chip2" if two else &"rank_chip"]
	blit(img, chip.grid, chip.ramp, x, y)
	text(img, str(rank), x + 2, y + 2, INK)


## What sits on a card's frame and art and does not move: the rank chip, the key cap, the tags
## at the art window's bottom right, the rank segments (`pips` [from, to]: lit below `from`, the
## ones this card adds after) or the FUSE recipe line. `spec`: CabinetCard's.
static func overlay_tex(spec: Dictionary) -> ImageTexture:
	var tier: StringName = spec.get("tier", &"common")
	var key := "over:%s:%s:%s:%s:%s:%s" % [tier, spec.get("rank", 0), spec.get("key", ""), spec.get("tags", []),
			spec.get("pips", []), spec.get("recipe", "")]
	return texture(key, func() -> Image:
		var img := canvas(CARD_W, CARD_H)
		var l: Dictionary = ArcadeArt.CARD_LAYOUT[tier]
		if int(spec.get("rank", 0)) > 0:
			_rank_chip(img, int(l.body[0]) + 2, int(l.body[1]) + 1, int(spec.rank))
		var cap := String(spec.get("key", ""))
		if cap != "":
			_keycap(img, int(l.key[0]), int(l.key[1]) - 1, cap)
		var recipe := String(spec.get("recipe", ""))
		if recipe != "":
			text(img, recipe, int(l.recipe[0]) + (int(l.recipe[2]) >> 1) + 1, int(l.recipe[1]) + 1, GOLD, 1)
		var ai: Array = l.artInner
		var tx := int(ai[0]) + int(ai[2]) - 1
		for tg: Array in spec.get("tags", []):
			tx -= text_w(String(tg[0])) + 4
			_tag(img, String(tg[0]), tx, int(ai[1]) + int(ai[3]) - 10, String(tg[1]), String(tg[2]))
			tx -= 1
		var pips: Array = spec.get("pips", [])
		if pips.size() == 2:
			var on: Dictionary = CabinetArt.ORN[&"seg_on"]
			var nxt: Dictionary = CabinetArt.ORN[&"seg_next"]
			for i in 6:
				var o: Dictionary = on if i < int(pips[0]) else nxt
				if i < int(pips[1]):
					blit(img, o.grid, o.ramp, int(l.pips[0]) + i * int(l.pipStep), int(l.pips[1]))
		return img)


## The white-hot blink of the segments a card adds (drawn over the overlay half of the time).
static func pips_hot_tex(tier: StringName, pips: Array) -> ImageTexture:
	return texture("hot:%s:%s" % [tier, pips], func() -> Image:
		var img := canvas(CARD_W, CARD_H)
		var l: Dictionary = ArcadeArt.CARD_LAYOUT[tier]
		var nxt: Dictionary = CabinetArt.ORN[&"seg_next"]
		for i in range(int(pips[0]), mini(6, int(pips[1]))):
			blit(img, nxt.grid, SEG_HOT, int(l.pips[0]) + i * int(l.pipStep), int(l.pips[1]))
		return img)


## The frames kit's 7x7 twinkle, frame 0..3.
static func spark_tex(frame: int) -> ImageTexture:
	var sp: Dictionary = CabinetArt.ORN[&"spark"]
	var frames: Array = sp.get("frames", CabinetArt.SPARK_FRAMES)
	return grid_tex("spark:%d" % (frame % frames.size()), frames[frame % frames.size()], sp.ramp)


## The small flying card (24x30): never a scaled-down big card.
static func mini_tex(id: StringName, tier: StringName) -> ImageTexture:
	return texture("mini:%s:%s" % [id, tier], func() -> Image:
		var img := canvas(MINI_W, MINI_H)
		var c: Array = MINI.get(tier, MINI[&"common"])
		box(img, 1, 0, 22, 30, INK)
		box(img, 0, 1, 24, 28, INK)
		box(img, 1, 1, 22, 28, c[0])
		box(img, 1, 1, 22, 1, c[1])
		box(img, 1, 1, 1, 28, c[1])
		box(img, 1, 28, 22, 1, c[2])
		box(img, 22, 1, 1, 28, c[2])
		box(img, 2, 3, 20, 16, INK)
		box(img, 3, 4, 18, 14, "#2a1d3a")
		if ArcadeArt.ICON.has(id):
			var icon := canvas(18, 14)
			blit(icon, ArcadeArt.ICON[id], ArcadeArt.GUN_RAMP, -1, 0, "z")
			img.blend_rect(icon, Rect2i(0, 0, 18, 14), Vector2i(3, 4))
		box(img, 2, 21, 20, 6, INK)
		box(img, 4, 23, 10, 1, SLIP)
		box(img, 4, 25, 6, 1, c[1])
		return img)


## The pack kit's small face-down card (the one that shoots out of a pack).
static func mini_back_tex() -> ImageTexture:
	return grid_tex("mini_back", ArcadeArt.CARD_MINI, ArcadeArt.PACK_RAMP)


# --- The hand -------------------------------------------------------------------------------------

## A hand slot (47x42): `tier` common / rare / epic, `state` idle / active / empty; `frame` bobs
## the active arrow.
static func slot_tex(tier: StringName, state: StringName, frame := 0) -> ImageTexture:
	var id: StringName = &"empty" if state == &"empty" else StringName("%s_%s" % [tier, state])
	var s: Dictionary = ArcadeArt.SLOT.get(id, ArcadeArt.SLOT[&"empty"])
	var frames: Array = s.frames
	var f := posmod(frame, frames.size())
	return grid_tex("slot:%s:%d" % [id, f], frames[f], s.ramp)


## The gun on a slot's screen (31x14): the barrel half of its splash art (a gun with no muzzle:
## its middle), as the mockup's slotArt. Icons side by side for a weapon with no splash.
static func slot_art_tex(id: StringName, parents: Array = []) -> ImageTexture:
	return texture("slot_art:%s:%s" % [id, parents], func() -> Image:
		var wd := 31
		var ht := 14
		var img := canvas(wd, ht)
		if not has_splash(id):
			var x := 15 - parents.size() * 8
			for p: StringName in parents:
				if ArcadeArt.ICON.has(p):
					blit(img, ArcadeArt.ICON[p], ArcadeArt.GUN_RAMP, x - 2, 0, "z")
				x += 16
			return img
		var m: Dictionary = ArcadeArt.SPLASH_META[id]
		var g: Array = ArcadeArt.SPLASH[id]
		var sx := int(m.mx) - wd + 2 if bool(m.muz) else int(m.cx) - (wd >> 1)
		var sy := int(m.my) - (ht >> 1) if bool(m.muz) else int(m.cy) - (ht >> 1)
		sy = clampi(sy, 0, g.size() - ht)
		sx = clampi(sx, 0, String(g[0]).length() - wd)
		blit(img, g, ArcadeArt.GUN_RAMP, -sx, -sy, "z")
		return img)


## A 7x9 key cap alone (the slot's top-left corner).
static func keycap_tex(label: String, lit: bool, empty := false) -> ImageTexture:
	return texture("key:%s:%s:%s" % [label, lit, empty], func() -> Image:
		var img := canvas(7, 9)
		_keycap(img, 0, 0, label, lit)
		if empty:   # the kit's dim cap on a free slot
			box(img, 1, 1, 5, 7, "#6a5290")
			box(img, 1, 1, 5, 1, "#7d66a6")
			box(img, 1, 7, 5, 1, "#3a2a4f")
			text(img, label.left(1), 2, 2, INK)
		return img)


## The gold rank chip (7x10, or 11 wide for two digits).
static func rank_tex(rank: int) -> ImageTexture:
	return texture("rank:%d" % rank, func() -> Image:
		var two := str(rank).length() > 1
		var img := canvas(11 if two else 7, 10)
		_rank_chip(img, 0, 0, rank)
		return img)


## A label tab (7 art px tall): an ink plate with mint letters when `lit` (pink when `warn`),
## else plum with pale letters. (The kit's ink letters on a mint tab did not read at 3x5: the
## slot's mint frame runs behind the tab.)
static func tab_tex(t: String, lit: bool, warn := false) -> ImageTexture:
	return texture("tab:%s:%s:%s" % [t, lit, warn], func() -> Image:
		var bright := lit or warn
		var w := text_w(t) + (6 if bright else 4)
		var img := canvas(w, 7)
		box(img, 0, 0, w, 7, INK)
		if not bright:
			box(img, 1, 1, w - 2, 5, "#4e3866")
		text(img, t, 3 if bright else 2, 1, PINK if warn else (MINT if lit else "#d9c9e8"))
		return img)


## The fuse link (17x19): idle, or charged at frame 0..3 (frame 0 alone under reduce flashing).
static func link_tex(charged: bool, frame := 0) -> ImageTexture:
	if not charged:
		return grid_tex("link:idle", ArcadeArt.LINK.idle, ArcadeArt.LINK.ramp)
	var frames: Array = ArcadeArt.LINK.charged
	var f := posmod(frame, frames.size())
	return grid_tex("link:%d" % f, frames[f], ArcadeArt.LINK.ramp)


# --- The pack -------------------------------------------------------------------------------------

## The dock's small pack (22x28); `dim` while none waits.
static func dock_pack_tex(dim: bool) -> ImageTexture:
	return texture("dock:%s" % dim, func() -> Image:
		var img := canvas(22, 28)
		var ramp: Dictionary = ArcadeArt.PACK_RAMP
		if dim:
			ramp = {}
			for k: String in ArcadeArt.PACK_RAMP:
				ramp[k] = "#33254a"
			ramp["K"] = INK
			ramp["Q"] = "#3a2a4f"
			ramp["P"] = "#3a2a4f"
		blit(img, ArcadeArt.PACK.dock, ramp, 0, 0)
		return img)


## The red badge ("x3"), stretched to its text; grey with `zero`.
static func badge_tex(t: String, zero := false) -> ImageTexture:
	return texture("badge:%s:%s" % [t, zero], func() -> Image:
		var tw := text_w(t)
		var img := canvas(tw + 6, 9)
		var rows := []
		for r: String in (ArcadeArt.BADGE_ZERO if zero else ArcadeArt.BADGE):
			rows.append(r.left(3) + r[3].repeat(tw) + r.right(3))
		blit(img, rows, ArcadeArt.PACK_RAMP, 0, 0)
		text(img, t, 3, 2, "#a08cb8" if zero else SLIP)
		return img)


## The kills gauge (23x7, six segments) with `lit` of them on.
static func gauge_tex(lit: int) -> ImageTexture:
	var n := clampi(lit, 0, 6)
	return texture("gauge:%d" % n, func() -> Image:
		var img := canvas(23, 7)
		blit(img, ArcadeArt.GAUGE, ArcadeArt.PACK_RAMP, 0, 0)
		var slots: Array = ArcadeArt.PACK_META.gauge_slots
		for s in n:
			blit(img, ArcadeArt.SEG, ArcadeArt.PACK_RAMP, int(slots[s][0]), int(slots[s][1]))
		return img)


## The flying pack: &"full" (30x42), &"open" (30x35, draw 7 lower), &"strip" (the torn strip),
## &"tear" i (0..2; 30x45, draw 3 higher) or &"peek" i (0..4; 30x61, draw 19 higher).
static func pack_tex(kind: StringName, i := 0) -> ImageTexture:
	var g: Array
	match kind:
		&"open":
			g = ArcadeArt.PACK.open
		&"strip":
			g = ArcadeArt.PACK.strip_off
		&"tear":
			g = ArcadeArt.PACK.tear[clampi(i, 0, 2)]
		&"peek":
			g = ArcadeArt.PACK.peek[clampi(i, 0, 4)]
		_:
			g = ArcadeArt.PACK.full
	return grid_tex("pack:%s:%d" % [kind, i], g, ArcadeArt.PACK_RAMP)


# --- The fx sheets --------------------------------------------------------------------------------

static func fx_frames(sheet: StringName) -> int:
	return (ArcadeArt.FX[sheet].frames as Array).size() if ArcadeArt.FX.has(sheet) else 0


## Frame `i` of an fx sheet in ramp `ramp` (&"": the sheet's own).
static func fx_tex(sheet: StringName, i: int, ramp: StringName = &"") -> ImageTexture:
	var s: Dictionary = ArcadeArt.FX[sheet]
	var frames: Array = s.frames
	var r: StringName = ramp if ramp != &"" else StringName(s.ramp)
	var f := posmod(i, frames.size())
	return grid_tex("fx:%s:%d:%s" % [sheet, f, r], frames[f], fx_ramp(r))


## A 4x4 ordered-dither tile at `level` 0..16 (16 = solid) in colour `col`, to tile over a rect:
## the screen flash and a slot's flash.
static func dither_tex(level: int, col: String) -> ImageTexture:
	var frames: Array = ArcadeArt.FX[&"flash_dither"].frames
	var l := clampi(level, 0, frames.size() - 1)
	return grid_tex("dither:%d:%s" % [l, col], frames[l], {"W": col})


## The rare slot's crown (9x5), on the slot's top edge with head-room (the mockup's CROWN9).
static func crown_tex() -> ImageTexture:
	return grid_tex("crown", [".K..K..K.", "KhKKhKKsK", "KhhghggsK", "KhgAgAgsK", "KKKKKKKKK"],
			{"K": INK, "h": "#fff0a0", "g": GOLD, "s": "#c98a2e", "A": PINK})
