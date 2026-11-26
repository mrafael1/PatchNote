class_name RailArt
extends RefCounted
## M48.5a: the version rail's colours and icons (the Pixel look's UI style, owner pick 3A
## "the version rail"). Pure data and drawing helpers, drawn in code: no image file. Kept out
## of grids.gd on purpose: ArtSkin.digest() hashes grids.gd's sprites and roles, and the
## rail is not part of the arena's atlas.
##
## Every colour of ui/rail/ comes from here (systems/skins/ is the colour lint's home), so
## the rail's scripts carry no Color literal. Grid letters: . transparent, then the keys of
## each grid's own legend.

const HEX := {
	&"ink": "#1e1424", &"base": "#3a2a4f", &"check": "#33254a", &"cell": "#4e3866",
	&"hi": "#6a5290", &"lo": "#33254a", &"sunk": "#2a1d3a",
	&"paper": "#f3e2b8", &"paper_hi": "#fff4d6", &"paper_lo": "#d9c08a", &"slip": "#fff8ec",
	&"gold": "#ffd84a", &"gold_lo": "#c98a2e", &"gold_hi": "#fff0a0",
	&"text": "#f3e2b8", &"dim": "#d9c9e8", &"mute": "#a08cb8",
	&"body": "#2a1d3a", &"who": "#c0503c", &"you": "#2f7a64", &"note_dim": "#6a5290",
	&"mint": "#6cf0c2", &"mint_lo": "#3f8f78", &"mint_hi": "#c8ffe9",
	&"warn": "#ff9a6b", &"warn_lo": "#e0664f", &"heart": "#ff6b5a", &"hp": "#ff8f7a",
	&"heart_hi": "#fff0e0", &"pink": "#ff6b8a", &"pink_hi": "#ffc0d0",
	&"key": "#f3e2b8", &"key_lo": "#c9b48a", &"pill": "#fff4d6", &"pill_lo": "#e2cc98",
	&"pip_off": "#e2cc98", &"pip_off_lo": "#b59a68", &"passive": "#ffd8c4", &"passive_lo": "#f0b090",
	&"passive_ink": "#9a3048", &"lv_ink": "#7a4a10", &"metal": "#bfa9d9", &"crate": "#c98a2e",
	&"crate_hi": "#ffb35a",
}

static var _cache := {}


## A rail colour by role (MAGENTA for a typo, as Palette does).
static func c(role: StringName) -> Color:
	if _cache.is_empty():
		for k: StringName in HEX:
			_cache[k] = Color.html(HEX[k])
	return _cache.get(role, Color.MAGENTA)


## The chat's terminal tokens on paper (TerminalPanel.colors while the rail dresses it).
static func chat_colors() -> Dictionary:
	return {&"bg": c(&"paper"), &"rule": c(&"ink"), &"text": c(&"body"), &"dim": c(&"note_dim"),
			&"cmd": c(&"note_dim"), &"note": c(&"body"), &"choice": c(&"ink"), &"you": c(&"you"),
			&"err": c(&"who")}


# --- Icons (the mockup's grids) --------------------------------------------------------------

const HEART := [".KK.KK.", "KWRKRRK", "KRRRRRK", ".KRRRK.", "..KKK..", "...K..."]
const HEART_LEGEND := {"K": &"ink", "R": &"heart", "W": &"heart_hi"}
const HEART_EMPTY_LEGEND := {"K": &"ink", "R": &"lo", "W": &"lo"}
const SKULL := [".KKKKK.", "KWWWWWK", "KWKWKWK", "KWKWKWK", "KWWKWWK", ".KWKWK.", ".KKKKK."]
const SKULL_LEGEND := {"K": &"ink", "W": &"slip"}
const ARROW := [".....LM....", ".....LMM...", ".....MMMM..", "DDDDDMMMMM.", "DDDDDMMMMMM",
		"DDDDDMMMMM.", ".....MMMM..", ".....MMM...", ".....MM...."]
const ARROW_LEGEND := {"D": &"mint_lo", "M": &"mint", "L": &"mint_hi"}
const ARROW_WARN_LEGEND := {"D": &"warn_lo", "M": &"warn", "L": &"heart_hi"}
const PACK := ["P.P.P.P.P.", "PHPPPPPPPP", "PHPPPPPPPP", "GGGGGGGGGG", "PPPPPPPPPP", "PPPPYYPPPP",
		"PPPYYYYPPP", "PPPYYYYPPP", "PPPPYYPPPP", "PPPPPPPPPP", "GGGGGGGGGG", "PPPPPPPPPP",
		"PPPPPPPPPP", "P..P..P..P"]
const PACK_LEGEND := {"P": &"pink", "H": &"pink_hi", "G": &"gold", "Y": &"gold_hi"}
const CRATE := ["KKKKKKKK", "KHHHHHHK", "KBBKKBBK", "KBBBBBBK", "KBBBBBBK", "KKKKKKKK"]
const CRATE_LEGEND := {"K": &"ink", "H": &"crate_hi", "B": &"crate"}
const INFINITY := [".KK...KK.", "K..K.K..K", "K...K...K", "K..K.K..K", ".KK...KK."]
const INFINITY_LEGEND := {"K": &"gold"}


## The big numbers' 5x7 pixel digits (the mockup's chunky numerals; the body font's 5 reads
## as an S at display sizes).
const DIGITS := {
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
	"/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
	"%": ["##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##"],
	"+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	# M50.6a: the other capitals, for short labels the body font cannot hold at small sizes (the
	# card ribbons: Pixelify's C closed into a D or an O there, "DOMMON", "EPID").
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".####", "#....", "#....", "#.###", "#...#", "#...#", ".###."],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "##..#", "#.#.#", "#..##", "#..##", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	" ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
}


## Draws `text` in the pixel digits, top-left at `at`, one cell = `cell` px (a char is 5
## cells wide plus a 1-cell gap, 7 tall). Unknown chars draw as a space.
static func draw_digits(ci: CanvasItem, at: Vector2, text: String, cell: float, color: Color) -> void:
	var x := at.x
	for ch in text:
		var g: Array = DIGITS.get(ch, DIGITS[" "])
		for y in 7:
			var row: String = g[y]
			for cx in 5:
				if row[cx] == "#":
					ci.draw_rect(Rect2(Vector2(x + cx * cell, at.y + y * cell), Vector2(cell, cell)), color)
		x += 6.0 * cell


static func digits_width(text: String, cell: float) -> float:
	return maxf(0.0, text.length() * 6.0 - 1.0) * cell


## M48.5b: the small text's digits. The body font (Pixelify Sans) draws its 1 px design grid
## on 1.1-1.5 screen px at the rail's 12-16 px sizes, so its 2 reads as an 8 (and 5 as S,
## 0 as 8); the rail's text draws 0-9 from DIGITS instead, stretched to the font's digit
## height: the bars (rows 0, 3, 6) and the outer columns are `t` px (the font's stroke at that
## size), the other rows and columns share what is left, so every stroke is whole pixels.
static var _small := {}


## The glyph's height in px at a font `size` (Pixelify's digits are 0.64 em tall).
static func small_digit_h(size: int, bold := false) -> int:
	var t := small_digit_t(size, bold)
	return maxi(3 * t + 4, roundi(size * 0.64))


## The stroke in px: Pixelify's design pixel is 0.091 em (wght 500: about 0.11 em).
static func small_digit_t(size: int, bold := false) -> int:
	return maxi(1, roundi(size * (0.11 if bold else 0.091)))


## The glyph's width: the outer columns `t`, the three inner ones one even width each (an
## uneven one would thicken the 1's stem and the 7's slope).
static func small_digit_w(size: int, bold := false) -> int:
	var t := small_digit_t(size, bold)
	var want := roundi(small_digit_h(size, bold) * 0.72)
	return 2 * t + 3 * maxi(1, (want - 2 * t) / 3)


## The filled rects of digit `ch` at a font `size`, top-left at (0, 0); cached.
static func small_digit(ch: String, size: int, bold := false) -> Array[Rect2]:
	var key := "%s|%d|%s" % [ch, size, bold]
	if _small.has(key):
		return _small[key]
	var out: Array[Rect2] = []
	var g: Array = DIGITS.get(ch, [])
	if not g.is_empty():
		var t := small_digit_t(size, bold)
		var h := small_digit_h(size, bold)
		var w := small_digit_w(size, bold)
		var rows := _spans(7, h, t, [0, 3, 6], [1, 4, 2, 5])
		var cols := _spans(5, w, t, [0, 4], [2, 1, 3])
		for y in 7:
			var row: String = g[y]
			for x in 5:
				if row[x] == "#":
					out.append(Rect2(Vector2(cols[x].x, rows[y].x), Vector2(cols[x].y, rows[y].y)))
	_small[key] = out
	return out


## `n` spans over `total` px: the `fixed` ones `t` each, the `share` ones (in that order of
## priority) split what is left (at least 1 px). Returns [start, length] per span.
static func _spans(n: int, total: int, t: int, fixed: Array, share: Array) -> Array[Vector2]:
	var lens := []
	lens.resize(n)
	lens.fill(t)
	var left := total - t * fixed.size()
	var each := maxi(1, left / share.size())
	for i in share:
		lens[i] = each
	var extra := left - each * share.size()
	var k := 0
	while extra > 0 and k < share.size():
		lens[share[k]] += 1
		extra -= 1
		k += 1
	var out: Array[Vector2] = []
	var at := 0
	for i in n:
		out.append(Vector2(at, lens[i]))
		at += lens[i]
	return out


## Draws digit `ch` with its bottom-left at `bottom_left` (the text's baseline), whole pixels.
static func draw_small_digit(ci: CanvasItem, ch: String, bottom_left: Vector2, size: int, bold: bool, color: Color) -> void:
	var at := Vector2(roundf(bottom_left.x), roundf(bottom_left.y) - small_digit_h(size, bold))
	for r in small_digit(ch, size, bold):
		ci.draw_rect(Rect2(at + r.position, r.size), color)


## Draws `grid` with its top-left at `at`, one cell = `px` screen pixels. outline: a 1-cell
## ink outline around every filled cell first (the mockup's drop-shadow outline).
static func draw_grid(ci: CanvasItem, grid: Array, legend: Dictionary, at: Vector2, px: float, outline := false) -> void:
	if outline:
		for y in grid.size():
			var row: String = grid[y]
			for x in row.length():
				if row[x] != ".":
					ci.draw_rect(Rect2(at + Vector2(x - 1, y - 1) * px, Vector2(px * 3.0, px * 3.0)), c(&"ink"))
	for y in grid.size():
		var row: String = grid[y]
		for x in row.length():
			var ch := row[x]
			if ch == ".":
				continue
			ci.draw_rect(Rect2(at + Vector2(x, y) * px, Vector2(px, px)), c(legend.get(ch, &"ink")))


static func grid_size(grid: Array, px: float) -> Vector2:
	return Vector2(String(grid[0]).length(), grid.size()) * px


# --- Shapes (the mockup's bevels, outlines and lips) -------------------------------------------

## A bevelled cell: fill, a `w` px light edge top-left and dark edge bottom-right.
static func bevel(ci: CanvasItem, r: Rect2, fill: Color, hi: Color, lo: Color, w: float) -> void:
	ci.draw_rect(r, fill)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, w)), hi)
	ci.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), hi)
	ci.draw_rect(Rect2(Vector2(r.position.x, r.end.y - w), Vector2(r.size.x, w)), lo)
	ci.draw_rect(Rect2(Vector2(r.end.x - w, r.position.y), Vector2(w, r.size.y)), lo)


## An outlined block: `w` px of ink around `r`, the fill inside, an optional bottom lip.
static func block(ci: CanvasItem, r: Rect2, fill: Color, w: float, lip := 0.0, lip_color := Color.WHITE) -> void:
	if w > 0.0:
		ci.draw_rect(r.grow(w), c(&"ink"))
	ci.draw_rect(r, fill)
	if lip > 0.0:
		ci.draw_rect(Rect2(Vector2(r.position.x, r.end.y - lip), Vector2(r.size.x, lip)), lip_color)
