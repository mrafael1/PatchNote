class_name CabinetArt
extends RefCounted
## M48.6a: the cabinet's art kit (PLAN 0.9.2, the Pixel look's UI): the owner-approved pixel
## mockup's "frames" kit ported grid for grid: its palette, its 9-slices (NINE) and its
## ornaments (ORN), as data, plus the drawing helpers. Drawn in code: no image file. One art
## pixel is `px` screen pixels (3 at the 1600x900 design size).
##
## The kit's rectangular frames came from one small generator (a silhouette, then rings counted
## inward); they are stored here as the grids it made, so the port cannot drift. The kit's
## cards, hand slots and fuse link are builders, not grids: they arrive with the dock (M48.6d).
##
## Every colour of ui/cabinet/ comes from here (systems/skins/ is the colour lint's home), so
## the cabinet's scripts carry no Color literal. Kept out of grids.gd on purpose, as RailArt:
## ArtSkin.digest() hashes grids.gd's sprites and roles, and the cabinet is not part of the
## arena's atlas. Presentation only: no RNG, no Tuning, no rules.

static var _colors := {}
static var _tiles := {}


## A kit colour by its palette role (MAGENTA for a typo, as Palette does).
static func c(role: StringName) -> Color:
	if PAL.has(role):
		return hex(PAL[role])
	return hex(HUD_PAL[role]) if HUD_PAL.has(role) else Color.MAGENTA


## A "#rrggbb" / "#rrggbbaa" colour, cached.
static func hex(h: String) -> Color:
	var v: Variant = _colors.get(h)
	if v == null:
		v = Color.html(h)
		_colors[h] = v
	return v


## The size of a grid in art px.
static func grid_size(grid: Array) -> Vector2i:
	return Vector2i(String(grid[0]).length(), grid.size())


## An ornament's size in art px.
static func orn_size(orn_name: StringName) -> Vector2i:
	return grid_size(ORN[orn_name].grid)


static func mirror(grid: Array) -> Array:
	var out := []
	for row: String in grid:
		out.append(row.reverse())
	return out


static func flip_v(grid: Array) -> Array:
	var out := grid.duplicate()
	out.reverse()
	return out


## Draws `grid` with its top-left at `at` (screen px), one cell = `px` screen px. '.' and chars
## the ramp does not know are skipped. Runs of one colour in a row are one rect.
static func draw(ci: CanvasItem, grid: Array, ramp: Dictionary, at: Vector2, px: float) -> void:
	var size := grid_size(grid)
	_blit(ci, grid, ramp, 0, 0, size.x, size.y, at, px)


## An ornament by name.
static func orn(ci: CanvasItem, orn_name: StringName, at: Vector2, px: float) -> void:
	var o: Dictionary = ORN[orn_name]
	draw(ci, o.grid, o.ramp, at, px)


## The cells [sx, sx + sw) x [sy, sy + sh) of `grid`, their top-left at `at`.
static func _blit(ci: CanvasItem, grid: Array, ramp: Dictionary, sx: int, sy: int, sw: int, sh: int,
		at: Vector2, px: float) -> void:
	for y in sh:
		var row: String = grid[sy + y]
		var x := 0
		while x < sw:
			var ch := row[sx + x]
			var run := 1
			while x + run < sw and row[sx + x + run] == ch:
				run += 1
			if ch != "." and ramp.has(ch):
				ci.draw_rect(Rect2(at + Vector2(x, y) * px, Vector2(run, 1) * px), hex(ramp[ch]))
			x += run


## The kit's draw9: the 9-slice `slice` at `w` x `h` art px, its top-left at `at` (screen px).
## The corners are drawn as they are, the edges and the centre tile; the drop shadow (the
## slice's outset) is drawn outside the asked size. An edge whose rows (or columns) are one
## colour across is one rect per row (or column).
static func draw9(ci: CanvasItem, slice: StringName, at: Vector2, w: int, h: int, px: float) -> void:
	var sp: Dictionary = NINE[slice]
	var g: Array = sp.grid
	var gs := grid_size(g)
	var i4: Array = sp.inset
	var full_w := w + int(sp.outset[0])
	var full_h := h + int(sp.outset[1])
	var sxs := [0, int(i4[0]), gs.x - int(i4[2]), gs.x]
	var dxs := [0, int(i4[0]), full_w - int(i4[2]), full_w]
	var sys := [0, int(i4[1]), gs.y - int(i4[3]), gs.y]
	var dys := [0, int(i4[1]), full_h - int(i4[3]), full_h]
	for j in 3:
		for i in 3:
			var sw: int = sxs[i + 1] - sxs[i]
			var sh: int = sys[j + 1] - sys[j]
			var dw: int = dxs[i + 1] - dxs[i]
			var dh: int = dys[j + 1] - dys[j]
			if sw <= 0 or sh <= 0 or dw <= 0 or dh <= 0:
				continue
			var to := at + Vector2(dxs[i], dys[j]) * px
			if i == 1 and _rows_plain(g, sxs[i], sys[j], sw, sh):
				for ty in dh:   # each row one colour: a rect across
					var ch: String = g[sys[j] + ty % sh][sxs[i]]
					if ch != "." and sp.ramp.has(ch):
						ci.draw_rect(Rect2(to + Vector2(0, ty) * px, Vector2(dw, 1) * px), hex(sp.ramp[ch]))
				continue
			if j == 1 and _cols_plain(g, sxs[i], sys[j], sw, sh):
				for tx in dw:
					var ch2: String = g[sys[j]][sxs[i] + tx % sw]
					if ch2 != "." and sp.ramp.has(ch2):
						ci.draw_rect(Rect2(to + Vector2(tx, 0) * px, Vector2(1, dh) * px), hex(sp.ramp[ch2]))
				continue
			var ty2 := 0
			while ty2 < dh:
				var tx2 := 0
				while tx2 < dw:
					_blit(ci, g, sp.ramp, sxs[i], sys[j], mini(sw, dw - tx2), mini(sh, dh - ty2),
							to + Vector2(tx2, ty2) * px, px)
					tx2 += sw
				ty2 += sh


## draw9 over a rect in screen px (its size in whole art px, rounded).
static func draw9_rect(ci: CanvasItem, slice: StringName, r: Rect2, px: float) -> void:
	draw9(ci, slice, r.position, roundi(r.size.x / px), roundi(r.size.y / px), px)


static func _rows_plain(g: Array, sx: int, sy: int, sw: int, sh: int) -> bool:
	for y in sh:
		var row: String = g[sy + y]
		for x in range(1, sw):
			if row[sx + x] != row[sx]:
				return false
	return true


static func _cols_plain(g: Array, sx: int, sy: int, sw: int, sh: int) -> bool:
	for x in sw:
		for y in range(1, sh):
			if g[sy + y][sx + x] != g[sy][sx + x]:
				return false
	return true


## A grid as a texture at `px` screen px per cell, for tiling (draw_texture_rect, tile on):
## the backdrop's checker, the cabinet's grain, the screen's scanlines. Made in code, cached.
static func tile(key: StringName, grid: Array, ramp: Dictionary, px: float) -> ImageTexture:
	var p := maxi(1, roundi(px))
	var id := "%s|%d" % [key, p]
	if _tiles.has(id):
		return _tiles[id]
	var size := grid_size(grid)
	var img := Image.create(size.x * p, size.y * p, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for y in size.y:
		var row: String = grid[y]
		for x in size.x:
			if row[x] != "." and ramp.has(row[x]):
				img.fill_rect(Rect2i(x * p, y * p, p, p), hex(ramp[row[x]]))
	var tex := ImageTexture.create_from_image(img)
	_tiles[id] = tex
	return tex


## An ornament as a tiling texture.
static func orn_tile(orn_name: StringName, px: float) -> ImageTexture:
	var o: Dictionary = ORN[orn_name]
	return tile(orn_name, o.grid, o.ramp, px)


## The backdrop behind the cabinet: the mockup's night checker, 6 art px squares.
const BACKDROP := ["aaaaaabbbbbb", "aaaaaabbbbbb", "aaaaaabbbbbb", "aaaaaabbbbbb", "aaaaaabbbbbb", "aaaaaabbbbbb",
		"bbbbbbaaaaaa", "bbbbbbaaaaaa", "bbbbbbaaaaaa", "bbbbbbaaaaaa", "bbbbbbaaaaaa", "bbbbbbaaaaaa"]
const BACKDROP_RAMP := {"a": "#140e1c", "b": "#1a1224"}


static func backdrop(px: float) -> ImageTexture:
	return tile(&"backdrop", BACKDROP, BACKDROP_RAMP, px)


## Text in the kit's 3x5 pixel letters (DIGITS: 0-9, + and the capitals it has), its top-left
## at `at`, one cell = `px` screen px, a 1-cell gap between letters. Returns the width in px.
static func draw_digits(ci: CanvasItem, text: String, at: Vector2, px: float, color: Color) -> float:
	var x := 0
	for ch in text:
		var g: Array = DIGITS.get(ch, [])
		if g.is_empty():
			x += 4
			continue
		for y in g.size():
			var row: String = g[y]
			for cx in row.length():
				if row[cx] != ".":
					ci.draw_rect(Rect2(at + Vector2(x + cx, y) * px, Vector2(px, px)), color)
		x += String(g[0]).length() + 1
	return maxf(0.0, x - 1) * px


# --- M48.6b: the view's HUD (the mockup page's own grids, not the frames kit) ---------------------

## Colours the mockup page uses outside the kit's palette: the clock's face, an idle caption.
const HUD_PAL := {&"clock": "#ffb35a", &"cap_idle": "#8a7a9a"}

## The hearts on the player (full, empty) and the corner plate's clock (the skull is ORN's).
const HUD := {
	&"heart": {"ramp": {"K": "#1e1424", "R": "#ff6b5a", "r": "#ffc0b0"},
		"grid": [".KK.KK.", "KRRKRRK", "KRrRRRK", "KRRRRRK", ".KRRRK.", "..KRK..", "...K..."]},
	&"heart_empty": {"ramp": {"K": "#1e1424", "D": "#4e3866"},
		"grid": [".KK.KK.", "KDDKDDK", "KDDDDDK", "KDDDDDK", ".KDDDK.", "..KDK..", "...K..."]},
	&"clock": {"ramp": {"K": "#1e1424", "O": "#ffb35a"},
		"grid": [".KKKKK.", "KOOKOOK", "KOOKOOK", "KOOKKOK", "KOOOOOK", ".KKKKK."]},
}

static var _rings := {}


## A HUD grid by name.
static func hud(ci: CanvasItem, hud_name: StringName, at: Vector2, px: float) -> void:
	var o: Dictionary = HUD[hud_name]
	draw(ci, o.grid, o.ramp, at, px)


## The cells of a 1-cell-thick pixel ring of radius `r` (the mockup's ringPts): [dx, dy, angle],
## the angle clockwise from the top in 0..TAU.
static func ring_cells(r: int) -> Array:
	if not _rings.has(r):
		var out := []
		for dy in range(-r - 1, r + 2):
			for dx in range(-r - 1, r + 2):
				var d := sqrt(float(dx * dx + dy * dy))
				if d >= r - 0.5 and d < r + 0.5:
					out.append([dx, dy, fposmod(atan2(dy, dx) + PI / 2.0, TAU)])
		_rings[r] = out
	return _rings[r]


## A pixel ring centred on the cell at `centre`; `frac` < 1 draws only its first part, clockwise
## from the top.
static func draw_ring(ci: CanvasItem, centre: Vector2, r: int, px: float, color: Color, frac := 1.0) -> void:
	for cell: Array in ring_cells(r):
		if frac < 1.0 and float(cell[2]) > frac * TAU:
			continue
		ci.draw_rect(Rect2(centre + Vector2(cell[0], cell[1]) * px, Vector2(px, px)), color)


# --- The kit's data (frames.js, generated from it: do not hand-edit a grid) ---------------------

## The kit's palette (frames.js C). The 8-digit ones are flat overlays (scanlines, glare, the
## vignette), never ramps.
const PAL := {
	&"ink": "#1e1424", &"night": "#140e1c", &"sunk": "#241a30", &"plum_d": "#2a1d3a", &"check": "#33254a",
	&"base": "#3a2a4f", &"deck": "#45305c", &"cell": "#4e3866", &"cell_t": "#5a4176", &"hi": "#6a5290",
	&"hi2": "#7d66a6", &"metal_lo": "#8a76a8", &"metal": "#bfa9d9", &"metal_hi": "#ece0ff", &"gold_dd": "#8a5a1a",
	&"gold_lo": "#c98a2e", &"gold": "#ffd84a", &"gold_hi": "#fff0a0", &"gold_foil": "#ffe680",
	&"paper_lo": "#d9c08a", &"paper": "#f3e2b8", &"paper_hi": "#fff4d6", &"slip": "#fff8ec",
	&"slip_lo": "#e6d3a8", &"lip": "#b59a68", &"mint_lo": "#3f8f78", &"mint": "#6cf0c2", &"mint_hi": "#c8ffe9",
	&"mint_pale": "#a8f5dc", &"pink_lo": "#c43d63", &"pink": "#ff6b8a", &"pink_hi": "#ffc0d0",
	&"pink_rim": "#ff8fb0", &"tape": "#ffd6e0", &"red": "#ff3a64", &"red_d": "#5a1a2c", &"coral": "#ff6b5a",
	&"orange": "#ff9a6b", &"orange_lo": "#c0603a", &"rust": "#c0503c", &"lilac_d": "#5a3a90",
	&"violet": "#8c5fd0", &"epic": "#7a4fd0", &"lilac": "#c79bff", &"lilac_hi": "#e2c8ff",
	&"lilac_pale": "#f0e4ff", &"prism_p": "#ff8ac0", &"prism_o": "#ffb070", &"c_bg": "#1a1636",
	&"c_ring": "#5b4a9a", &"c_ring_hi": "#7a68c0", &"c_ring_lo": "#463c7e", &"c_hd": "#221c44",
	&"c_hd_hi": "#2e2658", &"c_rule": "#3a3070", &"c_av": "#2b2550", &"c_bord": "#463c7e", &"c_log": "#0e0b1e",
	&"c_you": "#7457e8", &"c_you_hi": "#a48cff", &"c_you_lo": "#5a3fc4", &"c_pc": "#251f4d", &"c_pill": "#221d42",
	&"c_pill_b": "#5a4ca0", &"c_lit": "#6d4fe0", &"c_in": "#120f26", &"c_in_sh": "#0a0818", &"c_text": "#ece8ff",
	&"t_add": "#1f4a3c", &"t_add_b": "#2f6a56", &"t_chg": "#1c3a4a", &"t_chg_b": "#2c5a70", &"t_fix": "#4a3a1c",
	&"t_fix_b": "#6e5a2c", &"scan": "#00000018", &"glare": "#ffffff1c", &"glare2": "#ffffff0e",
	&"vig": "#140a1e99",
}

## The 9-slices (frames.js N): grid, ramp (char -> hex), inset [l, t, r, b] in art px (the drop
## shadow included), outset [r, b] (the drop shadow, drawn outside the asked rect).
const NINE := {
	&"cab": {"inset": [6, 6, 6, 8], "outset": [0, 3],
		"ramp": {"K": "#1e1424", "H": "#6a5290", "T": "#5a4176", "P": "#4e3866", "S": "#33254a", "D": "#1e1424"},
		"grid": [
			"...KKKKKKKK...", ".KKHHHHHHHHKK.", ".KHHTTTTTTHSK.", "KHHTTTTTTTTTSK", "KHTTTTTTTTTTSK", "KHPPPPPPPPPPSK",
			"KHPPPPPPPPPPSK", "KHPPPPPPPPPPSK", "KHPPPPPPPPPPSK", "KHPPPPPPPPPSSK", "KPSSSSSSSSSSSK", ".KSSSSSSSSSSK.",
			"..KKKKKKKKKK..", "..DDDDDDDDDD..", "..DDDDDDDDDD..", "...DDDDDDDD..."]},
	&"trim": {"inset": [0, 3, 0, 3], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "H": "#fff0a0", "W": "#fff8ec", "P": "#ffd84a", "S": "#c98a2e"},
		"grid": [
			".KKKK.", "KHWPSK", "KHPPSK", "KHPPSK", "KHPPSK", "KSSSSK", ".KKKK."]},
	&"marq": {"inset": [6, 6, 6, 6], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "H": "#4e3866", "P": "#2a1d3a", "Q": "#251a33", "R": "#201628"},
		"grid": [
			".KKKKKKKKKKKK.", "KHHHHHHHHHHHHK", "KHPPPPPPPPPPRK", "KHPPPPPPPPPPRK", "KPPPPPPPPPPPRK", "KPPPPPPPPPPPRK",
			"KQQQQQQQQQQQRK", "KQQQQQQQQQQQRK", "KQQQQQQQQQQQRK", "KQQQQQQQQQQQRK", "KRRRRRRRRRRRRK", "KRRRRRRRRRRRRK",
			"KRRRRRRRRRRRRK", ".KKKKKKKKKKKK."]},
	&"scr": {"inset": [5, 5, 5, 5], "outset": [0, 0],
		"ramp": {"H": "#6a5290", "L": "#4e3866", "K": "#1e1424", "U": "#2e2240", "B": "#241a30", "d": "#1a1224"},
		"grid": [
			"..HHHHHHHHHHH...", ".HKKKKKKKKKKKKL.", "HKUUUUUUUUUUUUKL", "HKUBBBBBBBBBBdKL", "HKUBBKKKKKKBBdKL",
			"HKUBK......KBdKL", "HKUBK......KBdKL", "HKUBK......KBdKL", "HKUBK......KBdKL", "HKUBK......KBdKL",
			"HKUBK......KBdKL", "HKUBBKKKKKKBBdKL", "HKUBBBBBBBBBBdKL", "HKUdddddddddddKL", ".HKKKKKKKKKKKKL.",
			"..LLLLLLLLLLLL.."]},
	&"deck": {"inset": [5, 5, 5, 5], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "H": "#6a5290", "P": "#45305c", "S": "#2a1d3a"},
		"grid": [
			"...KKKKKK...", ".KKHHHHHHKK.", ".KHPPPPPPHK.", "KHPPPPPPPPHK", "KHPPPPPPPPSK", "KHPPPPPPPPSK", "KHPPPPPPPPSK",
			"KHPPPPPPPPSK", "KSPPPPPPPPSK", ".KSPPPPPPSK.", ".KKSSSSSSKK.", "...KKKKKK..."]},
	&"host": {"inset": [2, 2, 2, 2], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "R": "#6a5290", "Q": "#4e3866", "P": "#2a1d3a"},
		"grid": [
			"KKKKKK", "KRRRRK", "KRPPQK", "KRPPQK", "KQQQQK", "KKKKKK"]},
	&"host_talk": {"inset": [3, 3, 3, 3], "outset": [0, 0],
		"ramp": {"Y": "#ffd84a", "y": "#c98a2e", "K": "#1e1424", "P": "#2a1d3a"},
		"grid": [
			"YYYYYYYY", "YKKKKKKY", "YKYYYYKY", "YKYPPyKY", "YKYPPyKY", "YKyyyyKY", "YKKKKKKY", "YYYYYYYY"]},
	&"cap_gold": {"inset": [2, 2, 3, 3], "outset": [1, 1],
		"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e", "D": "#1e1424"},
		"grid": [
			"KKKKKK.", "KHHHHKD", "KHPPSKD", "KHPPSKD", "KSSSSKD", "KKKKKKD", ".DDDDDD"]},
	&"cap_ink": {"inset": [2, 2, 3, 3], "outset": [1, 1],
		"ramp": {"K": "#1e1424", "h": "#3a2a4f", "P": "#241a30", "D": "#1e1424"},
		"grid": [
			"KKKKKK.", "KhhhhKD", "KhPPPKD", "KhPPPKD", "KPPPPKD", "KKKKKKD", ".DDDDDD"]},
	&"plate_gold": {"inset": [3, 3, 3, 4], "outset": [0, 1],
		"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e", "D": "#1e1424"},
		"grid": [
			".KKKKKK.", "KHHHHHHK", "KHPPPPSK", "KHPPPPSK", "KHPPPPSK", "KHPPPPSK", "KSSSSSSK", "DKKKKKKD", ".DDDDDD."]},
	&"bubble": {"inset": [3, 3, 5, 5], "outset": [2, 2],
		"ramp": {"K": "#1e1424", "C": "#fff8ec", "E": "#e6d3a8", "D": "#1e1424"},
		"grid": [
			".KKKKKK...", "KCCCCCCK..", "KCCCCCEKD.", "KCCCCCEKDD", "KCCCCCEKDD", "KCCCCCEKDD", "KEEEEEEKDD", ".KKKKKKDDD",
			"..DDDDDDDD", "...DDDDDD."]},
	&"chat": {"inset": [2, 2, 5, 5], "outset": [3, 3],
		"ramp": {"K": "#1e1424", "H": "#7a68c0", "S": "#5b4a9a", "P": "#1a1636", "D": "#1e1424"},
		"grid": [
			"KKKKKK...", "KHHHHK...", "KHPPSK...", "KHPPSKDDD", "KSSSSKDDD", "KKKKKKDDD", "...DDDDDD", "...DDDDDD",
			"...DDDDDD"]},
	&"chat_head": {"inset": [0, 1, 0, 1], "outset": [0, 0],
		"ramp": {"h": "#2e2658", "P": "#221c44", "r": "#3a3070"},
		"grid": [
			"hhh", "PPP", "PPP", "rrr"]},
	&"chat_avatar": {"inset": [2, 2, 2, 2], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "H": "#7a68c0", "S": "#5b4a9a", "P": "#2b2550"},
		"grid": [
			"KKKKKK", "KHHHHK", "KHPPSK", "KHPPSK", "KSSSSK", "KKKKKK"]},
	&"chat_log": {"inset": [0, 0, 0, 1], "outset": [0, 0],
		"ramp": {"P": "#0e0b1e", "r": "#3a3070"},
		"grid": [
			"PPP", "PPP", "PPP", "rrr"]},
	&"bub_ai": {"inset": [2, 2, 3, 3], "outset": [1, 1],
		"ramp": {"O": "#463c7e", "B": "#2b2550", "D": "#0e0b1e"},
		"grid": [
			".OOOO..", "OBBBBO.", "OBBBBOD", "OBBBBOD", "OBBBBOD", ".OOOODD", "..DDDD."]},
	&"bub_you": {"inset": [3, 3, 4, 4], "outset": [1, 1],
		"ramp": {"O": "#a48cff", "h": "#8f76f2", "B": "#7457e8", "D": "#0e0b1e"},
		"grid": [
			".OOOOOO..", "OhhhhhhO.", "OhBBBBBOD", "OhBBBBBOD", "OhBBBBBOD", "OhBBBBBOD", "OBBBBBBOD", ".OOOOOODD",
			"..DDDDDD."]},
	&"patch_card": {"inset": [2, 2, 3, 3], "outset": [1, 1],
		"ramp": {"K": "#1e1424", "H": "#7a68c0", "S": "#5b4a9a", "P": "#251f4d", "D": "#0e0b1e"},
		"grid": [
			"KKKKKK.", "KHHHHKD", "KHPPSKD", "KHPPSKD", "KSSSSKD", "KKKKKKD", ".DDDDDD"]},
	&"hotfix": {"inset": [2, 2, 3, 3], "outset": [1, 1],
		"ramp": {"K": "#1e1424", "H": "#fff8ec", "P": "#fff0a0", "S": "#ffd84a", "D": "#c98a2e"},
		"grid": [
			"KKKKKK.", "KHHHHKD", "KHPPSKD", "KHPPSKD", "KSSSSKD", "KKKKKKD", ".DDDDDD"]},
	&"tag_add": {"inset": [1, 1, 1, 1], "outset": [0, 0],
		"ramp": {"B": "#2f6a56", "P": "#1f4a3c"},
		"grid": [
			"BBB", "BPB", "BBB"]},
	&"tag_chg": {"inset": [1, 1, 1, 1], "outset": [0, 0],
		"ramp": {"B": "#2c5a70", "P": "#1c3a4a"},
		"grid": [
			"BBB", "BPB", "BBB"]},
	&"tag_fix": {"inset": [1, 1, 1, 1], "outset": [0, 0],
		"ramp": {"B": "#6e5a2c", "P": "#4a3a1c"},
		"grid": [
			"BBB", "BPB", "BBB"]},
	&"pill": {"inset": [3, 3, 3, 3], "outset": [0, 0],
		"ramp": {"O": "#5a4ca0", "h": "#2c2654", "P": "#221d42"},
		"grid": [
			".OOOOOO.", "OhhhhhhO", "OhPPPPPO", "OhPPPPPO", "OhPPPPPO", "OhPPPPPO", "OPPPPPPO", ".OOOOOO."]},
	&"pill_lit": {"inset": [3, 3, 3, 3], "outset": [0, 0],
		"ramp": {"O": "#a48cff", "h": "#8a70f0", "P": "#6d4fe0"},
		"grid": [
			".OOOOOO.", "OhhhhhhO", "OhPPPPPO", "OhPPPPPO", "OhPPPPPO", "OhPPPPPO", "OPPPPPPO", ".OOOOOO."]},
	&"input": {"inset": [2, 2, 2, 2], "outset": [0, 0],
		"ramp": {"O": "#5b4a9a", "s": "#0a0818", "P": "#120f26"},
		"grid": [
			"OOOOOO", "OssssO", "OsPPPO", "OsPPPO", "OPPPPO", "OOOOOO"]},
	&"send": {"inset": [2, 2, 2, 2], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "H": "#a48cff", "S": "#5a3fc4", "P": "#7457e8"},
		"grid": [
			"KKKKKK", "KHHHHK", "KHPPSK", "KHPPSK", "KSSSSK", "KKKKKK"]},
	&"kill_plate": {"inset": [4, 4, 4, 5], "outset": [0, 1],
		"ramp": {"K": "#1e1424", "h": "#3a2a4f", "P": "#241a30", "D": "#1e1424"},
		"grid": [
			"..KKKKKK..", ".KhhhhhhK.", "KhPPPPPPhK", "KhPPPPPPPK", "KhPPPPPPPK", "KhPPPPPPPK", "KhPPPPPPPK", "KPPPPPPPPK",
			"DKPPPPPPKD", ".DKKKKKKD.", "..DDDDDD.."]},
	&"corner_plate": {"inset": [3, 3, 4, 4], "outset": [1, 1],
		"ramp": {"K": "#1e1424", "R": "#6a5290", "P": "#241a30", "D": "#1e1424"},
		"grid": [
			".KKKKKK..", "KRRRRRRK.", "KRPPPPRKD", "KRPPPPRKD", "KRPPPPRKD", "KRPPPPRKD", "KRRRRRRKD", ".KKKKKKDD",
			"..DDDDDD."]},
	&"num_box": {"inset": [2, 2, 2, 2], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "A": "#ff6b5a", "P": "#1e1424"},
		"grid": [
			"KKKKKK", "KAAAAK", "KAPPAK", "KAPPAK", "KAAAAK", "KKKKKK"]},
	&"num_box_zero": {"inset": [2, 2, 2, 2], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "A": "#6cf0c2", "P": "#1e1424"},
		"grid": [
			"KKKKKK", "KAAAAK", "KAPPAK", "KAPPAK", "KAAAAK", "KKKKKK"]},
	&"num_box_sv": {"inset": [2, 2, 2, 2], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "A": "#ff9a6b", "P": "#1e1424"},
		"grid": [
			"KKKKKK", "KAAAAK", "KAPPAK", "KAPPAK", "KAAAAK", "KKKKKK"]},
	&"gauge": {"inset": [2, 2, 2, 2], "outset": [0, 0],
		"ramp": {"R": "#4e3866", "K": "#1e1424", "P": "#1e1424"},
		"grid": [
			"RRRRRR", "RKKKKR", "RKPPKR", "RKPPKR", "RKKKKR", "RRRRRR"]},
	&"toast_head": {"inset": [2, 2, 4, 4], "outset": [2, 2],
		"ramp": {"K": "#1e1424", "H": "#c8ffe9", "P": "#6cf0c2", "S": "#3f8f78", "D": "#1e1424"},
		"grid": [
			"KKKKKK..", "KHHHHK..", "KHPPSKDD", "KHPPSKDD", "KSSSSKDD", "KKKKKKDD", "..DDDDDD", "..DDDDDD"]},
	&"toast_hot": {"inset": [2, 2, 4, 4], "outset": [2, 2],
		"ramp": {"K": "#1e1424", "H": "#fff8ec", "P": "#fff0a0", "S": "#ffd84a", "D": "#1e1424"},
		"grid": [
			"KKKKKK..", "KHHHHK..", "KHPPSKDD", "KHPPSKDD", "KSSSSKDD", "KKKKKKDD", "..DDDDDD", "..DDDDDD"]},
	&"toast_body": {"inset": [2, 2, 4, 4], "outset": [2, 2],
		"ramp": {"K": "#1e1424", "h": "#33254a", "P": "#1e1424", "D": "#0e0a12"},
		"grid": [
			"KKKKKK..", "KhhhhK..", "KhPPPKDD", "KhPPPKDD", "KPPPPKDD", "KKKKKKDD", "..DDDDDD", "..DDDDDD"]},
	&"session": {"inset": [7, 7, 9, 9], "outset": [2, 2],
		"ramp": {"K": "#1e1424", "Y": "#ffd84a", "H": "#4e3866", "S": "#33254a", "P": "#2a1d3a", "D": "#140e1c"},
		"grid": [
			"...KKKKKKKKKK.....", ".KKYYYYYYYYYYKK...", ".KYKKKKKKKKKKYK...", "KYKHHHHHHHHHHKYKD.", "KYKHPPPPPPPPSKYKD.",
			"KYKHPPPPPPPPSKYKDD", "KYKHPPPPPPPPSKYKDD", "KYKHPPPPPPPPSKYKDD", "KYKHPPPPPPPPSKYKDD", "KYKHPPPPPPPPSKYKDD",
			"KYKHPPPPPPPPSKYKDD", "KYKHPPPPPPPPSKYKDD", "KYKSSSSSSSSSSKYKDD", ".KYKKKKKKKKKKYKDDD", ".KKYYYYYYYYYYKKDDD",
			"...KKKKKKKKKKDDDD.", "...DDDDDDDDDDDDDD.", ".....DDDDDDDDDD..."]},
	&"build_bar": {"inset": [2, 2, 2, 2], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "s": "#140e1c", "P": "#2a1d3a"},
		"grid": [
			"KKKKKK", "KssssK", "KsPPPK", "KsPPPK", "KPPPPK", "KKKKKK"]},
	&"chip_mint": {"inset": [2, 2, 2, 2], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "H": "#c8ffe9", "P": "#6cf0c2", "S": "#3f8f78"},
		"grid": [
			"KKKKKK", "KHHHHK", "KHPPSK", "KHPPSK", "KSSSSK", "KKKKKK"]},
	&"cta": {"inset": [3, 3, 4, 4], "outset": [1, 1],
		"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e", "D": "#1e1424"},
		"grid": [
			".KKKKKK..", "KHHHHHHK.", "KHPPPPSKD", "KHPPPPSKD", "KHPPPPSKD", "KHPPPPSKD", "KSSSSSSKD", ".KKKKKKDD",
			"..DDDDDD."]},
	&"cta_press": {"inset": [3, 3, 3, 3], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e"},
		"grid": [
			".KKKKKK.", "KSSSSSSK", "KSPPPPHK", "KSPPPPHK", "KSPPPPHK", "KSPPPPHK", "KHHHHHHK", ".KKKKKK."]},
	&"cta_live": {"inset": [4, 4, 5, 5], "outset": [1, 1],
		"ramp": {"K": "#1e1424", "H": "#fff8ec", "W": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e", "D": "#1e1424"},
		"grid": [
			".KKKKKKKK..", "KHHHHHHHHK.", "KHWWWWWWSKD", "KHWPPPPPSKD", "KHWPPPPPSKD", "KHWPPPPPSKD", "KHWPPPPPSKD",
			"KHPPPPPPSKD", "KSSSSSSSSKD", ".KKKKKKKKDD", "..DDDDDDDD."]},
	&"cta_off": {"inset": [3, 3, 3, 3], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "H": "#5a4176", "P": "#4e3866", "S": "#3a2a4f"},
		"grid": [
			".KKKKKK.", "KHHHHHHK", "KHPPPPSK", "KHPPPPSK", "KHPPPPSK", "KHPPPPSK", "KSSSSSSK", ".KKKKKK."]},
	&"rib_common": {"inset": [2, 2, 2, 2], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "P": "#bfa9d9", "H": "#ece0ff", "S": "#8a76a8"},
		"grid": [
			"KKKKKK", "KHHHHK", "KHPPSK", "KHPPSK", "KSSSSK", "KKKKKK"]},
	&"rib_rare": {"inset": [2, 2, 2, 2], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "P": "#ff6b8a", "H": "#ffc0d0", "S": "#c43d63"},
		"grid": [
			"KKKKKK", "KHHHHK", "KHPPSK", "KHPPSK", "KSSSSK", "KKKKKK"]},
	&"rib_epic": {"inset": [2, 2, 2, 2], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "P": "#6cf0c2", "H": "#c8ffe9", "S": "#3f8f78"},
		"grid": [
			"KKKKKK", "KHHHHK", "KHPPSK", "KHPPSK", "KSSSSK", "KKKKKK"]},
	&"rib_fuse": {"inset": [2, 2, 2, 2], "outset": [0, 0],
		"ramp": {"K": "#1e1424", "P": "#ffd84a", "H": "#fff0a0", "S": "#c98a2e"},
		"grid": [
			"KKKKKK", "KHHHHK", "KHPPSK", "KHPPSK", "KSSSSK", "KKKKKK"]},
	&"hand_bay": {"inset": [5, 5, 5, 5], "outset": [0, 0],
		"ramp": {"d": "#2a1d3a", "H": "#6a5290", "K": "#1e1424", "s": "#140e1c", "P": "#241a30"},
		"grid": [
			"..dddddddd..", ".dKKKKKKKKd.", "dKssssssssKd", "dKsPPPPPPPKH", "dKsPPPPPPPKH", "dKsPPPPPPPKH", "dKsPPPPPPPKH",
			"dKsPPPPPPPKH", "dKsPPPPPPPKH", "HKPPPPPPPPKH", ".HKKKKKKKKH.", "..HHHHHHHH.."]},
}

## The ornaments (frames.js O): hand-drawn grids and their ramps.
const ORN := {
	&"rivet": {"ramp": {"K": "#1e1424", "H": "#ece0ff", "M": "#bfa9d9", "S": "#8a76a8"},
		"grid": [
			".KK.", "KHMK", "KMSK", ".KK."]},
	&"screw": {"ramp": {"K": "#1e1424", "H": "#ece0ff", "M": "#bfa9d9", "S": "#8a76a8"},
		"grid": [
			".KKK.", "KHMKK", "KMKSK", "KKSSK", ".KKK."]},
	&"screw_s": {"ramp": {"K": "#1e1424", "H": "#ece0ff", "M": "#bfa9d9", "S": "#8a76a8"},
		"grid": [
			".K.", "KMK", ".K."]},
	&"cab_grain": {"ramp": {"P": "#4e3866", "g": "#533d6e"},
		"grid": [
			"PPPPPPPg", "PPPPPPgP", "PPPPPPPP", "PPPPPPPP", "PPPgPPPP", "PPgPPPPP", "PPPPPPPP", "PPPPPPPP"]},
	&"bracket_tl": {"ramp": {"Y": "#ffd84a", "H": "#fff0a0", "K": "#1e1424"},
		"grid": [
			"HYYYY.", "YKKKKK", "YK....", "YK....", "YK....", ".K...."]},
	&"bracket_tr": {"ramp": {"Y": "#ffd84a", "H": "#fff0a0", "K": "#1e1424"},
		"grid": [
			"YYYYH.", ".KKKYK", "....YK", "....YK", "....YK", ".....K"]},
	&"bracket_bl": {"ramp": {"Y": "#ffd84a", "H": "#fff0a0", "K": "#1e1424"},
		"grid": [
			"Y.....", "YK....", "YK....", "YK....", "HYYYY.", ".KKKKK"]},
	&"bracket_br": {"ramp": {"Y": "#ffd84a", "H": "#fff0a0", "K": "#1e1424"},
		"grid": [
			"....Y.", "....YK", "....YK", "....YK", "YYYYYK", ".KKKKK"]},
	&"rec_dot": {"ramp": {"K": "#1e1424", "H": "#ffc0d0", "R": "#ff3a64", "S": "#c43d63"},
		"grid": [
			".KKK.", "KHRRK", "KRRSK", "KRSSK", ".KKK."]},
	&"rec_off": {"ramp": {"K": "#1e1424", "R": "#5a1a2c"},
		"grid": [
			".KKK.", "KRRRK", "KRRRK", "KRRRK", ".KKK."]},
	&"host_floor": {"ramp": {"l": "#7d66a6", "L": "#6a5290"},
		"grid": [
			".........lllllllll.........", ".....llllLLLLLLLLLllll.....", "...llLLLLLLLLLLLLLLLLLll...",
			"..lLLLLLLLLLLLLLLLLLLLLLl..", ".lLLLLLLLLLLLLLLLLLLLLLLLl."]},
	&"marq_cap_l": {"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e", "W": "#fff8ec", "A": "#ff6b8a", "a": "#c43d63", "D": "#1e1424"},
		"grid": [
			"..KKK", ".KHHK", "KHWPK", "KHPSK", "KHPSK", "KHPSK", "KHPSK", "KHPSK", "KHPSK", "KHPSK", "KHPSK", "KPSSK",
			".KSSK", "..KKK"]},
	&"marq_cap_r": {"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e", "W": "#fff8ec", "A": "#ff6b8a", "a": "#c43d63", "D": "#1e1424"},
		"grid": [
			"KKK..", "KHHK.", "KHWSK", "KHPSK", "KHPSK", "KHPSK", "KHPSK", "KHPSK", "KHPSK", "KHPSK", "KHPSK", "KPSSK",
			"KSSK.", "KKK.."]},
	&"marq_chev_r": {"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e", "W": "#fff8ec", "A": "#ff6b8a", "a": "#c43d63", "D": "#1e1424"},
		"grid": [
			"KK..KK...", "KHK.KHK..", ".KPK.KPK.", "..KPK.KPK", ".KSK.KSK.", "KSK.KSK..", "KK..KK..."]},
	&"marq_chev_l": {"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e", "W": "#fff8ec", "A": "#ff6b8a", "a": "#c43d63", "D": "#1e1424"},
		"grid": [
			"...KK..KK", "..KHK.KHK", ".KPK.KPK.", "KPK.KPK..", ".KSK.KSK.", "..KSK.KSK", "...KK..KK"]},
	&"bub_tail_l": {"ramp": {"K": "#1e1424", "C": "#fff8ec", "E": "#e6d3a8", "D": "#1e1424"},
		"grid": [
			"......K", "....KKC", "..KKCCC", "KKCCCCC", ".DKKCCC", "..DDKKE", "....DDK"]},
	&"tail_ai": {"ramp": {"O": "#463c7e", "B": "#2b2550", "D": "#0e0b1e"},
		"grid": [
			"OBBO..", "OBOD..", "OOD...", ".D...."]},
	&"tail_you": {"ramp": {"O": "#a48cff", "B": "#7457e8", "D": "#0e0b1e"},
		"grid": [
			"..OBBO.", "...OBOD", "....OOD", ".....D."]},
	&"pc_tab": {"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e", "W": "#fff8ec", "A": "#ff6b8a", "a": "#c43d63", "D": "#1e1424"},
		"grid": [
			"KKKKK", "KHPSK", "KHPSK", "KHPSK", "KHPSK", "KHKSK", "KK.KK"]},
	&"tape": {"ramp": {"T": "#ffc0d0", "t": "#ffd6e0"},
		"grid": [
			"TTTTTTTTTT.", ".TtttttttTT", "TTtttttttT.", ".TTTTTTTTTT"]},
	&"send_arrow": {"ramp": {"W": "#fff8ec"},
		"grid": [
			"..W..", "...W.", "WWWWW", "...W.", "..W.."]},
	&"skull": {"ramp": {"K": "#1e1424", "W": "#fff8ec", "S": "#e6d3a8"},
		"grid": [
			".KKKKKK.", "KWWWWWSK", "KWKKWKSK", "KWKKWKSK", "KWWKKWSK", ".KWSWSK.", ".KWKWKK.", "..KKKK.."]},
	&"dv_rule": {"ramp": {"r": "#3a3070"},
		"grid": [
			"r"]},
	&"gauge_fill": {"ramp": {"P": "#ff6b8a", "S": "#c43d63"},
		"grid": [
			"PPS"]},
	&"gauge_fill_sv": {"ramp": {"P": "#ff9a6b", "S": "#c0603a"},
		"grid": [
			"PPS"]},
	&"build_fill": {"ramp": {"H": "#c8ffe9", "M": "#6cf0c2", "L": "#3f8f78", "l": "#3f8f78"},
		"grid": [
			"HHHHHl", "MMMMMl", "MMMMMl", "MMMMMl", "LLLLLl"]},
	&"bs_corner": {"ramp": {"Y": "#ffd84a", "H": "#fff0a0", "K": "#1e1424"},
		"grid": [
			"HYYY.", "YK...", "YKY..", "Y....", "....."]},
	&"scr_glare": {"ramp": {"g": "#ffffff1c", "h": "#ffffff0e"},
		"grid": [
			"............ggggg...hh........", "...........ggggg...hh.........", "..........ggggg...hh..........",
			".........ggggg...hh...........", "........ggggg...hh............", ".......ggggg...hh.............",
			"......ggggg...hh..............", ".....ggggg...hh...............", "....ggggg...hh................",
			"...ggggg...hh.................", "..ggggg...hh..................", ".ggggg...hh...................",
			"ggggg...hh....................", "gggg...hh....................."]},
	&"crt_scan": {"ramp": {"s": "#00000018"},
		"grid": [
			"s", ".", "."]},
	&"vignette": {"ramp": {"v": "#140a1e99"},
		"grid": [
			"vvv.v.v.v.v.v.", ".v.v.v........", "v.v.v.v.v.v...", ".v.v..........", "v.v.v.v.v.....", ".v...v........",
			"v.v.v.v.......", "..............", "v.v.v.v.v.....", "..............", "..v...........", "..............",
			"v.............", ".............."]},
	&"crown": {"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e", "W": "#fff8ec", "A": "#ff6b8a", "a": "#c43d63", "D": "#1e1424"},
		"grid": [
			"K.....K.....K", "KK...KHK...KK", "KHK.KHPSK.KSK", "KHPKHPPPSKPSK", "KHPPPPAPPPPSK", "KHAPPPPPPPASK",
			"KSSSSSSSSSSSK", "KKKKKKKKKKKKK"]},
	&"crown_s": {"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e", "W": "#fff8ec", "A": "#ff6b8a", "a": "#c43d63", "D": "#1e1424"},
		"grid": [
			"K..K..K", "KHKHKSK", "KHPAPSK", "KKKKKKK"]},
	&"star": {"ramp": {"K": "#1e1424", "W": "#fff8ec", "M": "#6cf0c2", "S": "#3f8f78"},
		"grid": [
			"...K...", "..KWK..", "KKWMMKK", "KWMMMSK", "KKMMSKK", "..KSK..", "...K..."]},
	&"star_s": {"ramp": {"K": "#1e1424", "W": "#fff8ec", "M": "#6cf0c2", "S": "#3f8f78"},
		"grid": [
			"..K..", ".KWK.", "KWMSK", ".KSK.", "..K.."]},
	&"bolt": {"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e", "W": "#fff8ec", "A": "#ff6b8a", "a": "#c43d63", "D": "#1e1424"},
		"grid": [
			"...KKKK", "..KHPK.", ".KHPK..", "KHPPKKK", "KKKPPSK", "..KPSK.", ".KPSK..", ".KSK...", ".KK...."]},
	&"bolt_l": {"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e", "W": "#fff8ec", "A": "#ff6b8a", "a": "#c43d63", "D": "#1e1424"},
		"grid": [
			"....KKKKK", "...KHPPK.", "..KHPPK..", ".KHPPK...", "KHPPPKKKK", "KKKKPPPSK", "...KPPSK.", "..KPPSK..",
			".KPPSK...", ".KPSK....", ".KSK.....", ".KK......"]},
	&"seg_off": {"ramp": {"d": "#140e1c", "e": "#2a1d3a"},
		"grid": [
			"ddddd", "deeee", "deeee", "deeee"]},
	&"seg_on": {"ramp": {"H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e"},
		"grid": [
			"HPPPP", "PPPPS", "PPPPS", "PSSSS"]},
	&"seg_next": {"ramp": {"H": "#ffc0d0", "P": "#ff6b8a", "S": "#c43d63"},
		"grid": [
			"HPPPP", "PPPPS", "PPPPS", "PSSSS"]},
	&"bolt_s": {"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e", "W": "#fff8ec", "A": "#ff6b8a", "a": "#c43d63", "D": "#1e1424"},
		"grid": [
			"...KK", "..KPK", ".KPK.", "KPPPK", ".KPK.", "KPK..", "KK..."]},
	&"gem_common": {"ramp": {"K": "#1e1424", "P": "#bfa9d9", "H": "#ece0ff", "S": "#8a76a8"},
		"grid": [
			"...K...", "..KHK..", ".KHPSK.", "KHPPPSK", ".KPPSK.", "..KSK..", "...K..."]},
	&"gem_rare": {"ramp": {"K": "#1e1424", "P": "#ff6b8a", "H": "#ffc0d0", "S": "#c43d63"},
		"grid": [
			"...K...", "..KHK..", ".KHPSK.", "KHPPPSK", ".KPPSK.", "..KSK..", "...K..."]},
	&"gem_epic": {"ramp": {"K": "#1e1424", "P": "#6cf0c2", "H": "#c8ffe9", "S": "#3f8f78"},
		"grid": [
			"...K...", "..KHK..", ".KHPSK.", "KHPPPSK", ".KPPSK.", "..KSK..", "...K..."]},
	&"gem_fuse": {"ramp": {"K": "#1e1424", "P": "#ffd84a", "H": "#fff0a0", "S": "#c98a2e"},
		"grid": [
			"...K...", "..KHK..", ".KHPSK.", "KHPPPSK", ".KPPSK.", "..KSK..", "...K..."]},
	&"pip_off": {"ramp": {"K": "#1e1424", "d": "#2a1d3a", "e": "#33254a"},
		"grid": [
			".KKK.", "KeddK", "KdddK", "KdddK", ".KKK."]},
	&"pip_on": {"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e"},
		"grid": [
			".KKK.", "KHPPK", "KPPSK", "KPSSK", ".KKK."]},
	&"pip_next": {"ramp": {"K": "#1e1424", "H": "#ffc0d0", "P": "#ff6b8a", "S": "#c43d63"},
		"grid": [
			".KKK.", "KHPPK", "KPPSK", "KPSSK", ".KKK."]},
	&"pip_max": {"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e"},
		"grid": [
			".KKK.", "KHPPK", "KPPPK", "KPPSK", "KPPSK", "KPSSK", ".KKK."]},
	&"keycap": {"ramp": {"K": "#1e1424", "H": "#fff4d6", "P": "#f3e2b8", "S": "#d9c08a", "L": "#b59a68"},
		"grid": [
			".KKKKK.", "KHPPPSK", "KHPPPSK", "KHPPPSK", "KHPPPSK", "KHPPPSK", "KLLLLLK", ".KKKKK."]},
	&"keycap_lit": {"ramp": {"K": "#1e1424", "H": "#c8ffe9", "P": "#6cf0c2", "S": "#3f8f78", "L": "#2f6a5a"},
		"grid": [
			".KKKKK.", "KHPPPSK", "KHPPPSK", "KHPPPSK", "KHPPPSK", "KHPPPSK", "KLLLLLK", ".KKKKK."]},
	&"rank_chip": {"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e"},
		"grid": [
			".KKKKK.", "KHHHHHK", "KHPPPSK", "KHPPPSK", "KHPPPSK", "KHPPPSK", "KHPPPSK", "KSSSSSK", "KKKKKKK", ".KKKKK."]},
	&"rank_chip2": {"ramp": {"K": "#1e1424", "H": "#fff0a0", "P": "#ffd84a", "S": "#c98a2e"},
		"grid": [
			".KKKKKKKKK.", "KHHHHHHHHHK", "KHPPPPPPPSK", "KHPPPPPPPSK", "KHPPPPPPPSK", "KHPPPPPPPSK", "KHPPPPPPPSK",
			"KSSSSSSSSSK", "KKKKKKKKKKK", ".KKKKKKKKK."]},
	&"active_arrow": {"ramp": {"K": "#1e1424", "W": "#c8ffe9", "M": "#6cf0c2", "L": "#3f8f78"},
		"grid": [
			"...K...", "..KWK..", ".KMMLK.", "KMMMLLK", "KKKKKKK"]},
	&"spark": {"ramp": {"W": "#fff8ec", "Y": "#ffd84a"},
		"grid": [
			"..W..", "..Y..", "WYWYW", "..Y..", "..W.."]},
}

## The 4-frame twinkle (frames.js O.spark.frames; ORN.spark is frame 1). Hidden under reduce flashing.
const SPARK_FRAMES := [
	[".....", "..W..", ".WYW.", "..W..", "....."],
	["..W..", "..Y..", "WYWYW", "..Y..", "..W.."],
	["W...W", ".Y.Y.", "..W..", ".Y.Y.", "W...W"],
	[".....", "..Y..", ".Y.Y.", "..Y..", "....."],
]

## The 3x5 pixel letters (frames.js DIG; N is 4 wide, M 5).
const DIGITS := {
	"0": ["KKK", "K.K", "K.K", "K.K", "KKK"],
	"1": [".K.", "KK.", ".K.", ".K.", "KKK"],
	"2": ["KKK", "..K", "KKK", "K..", "KKK"],
	"3": ["KKK", "..K", ".KK", "..K", "KKK"],
	"4": ["K.K", "K.K", "KKK", "..K", "..K"],
	"5": ["KKK", "K..", "KKK", "..K", "KKK"],
	"6": ["KKK", "K..", "KKK", "K.K", "KKK"],
	"7": ["KKK", "..K", "..K", ".K.", ".K."],
	"8": ["KKK", "K.K", "KKK", "K.K", "KKK"],
	"9": ["KKK", "K.K", "KKK", "..K", "KKK"],
	"+": ["...", ".K.", "KKK", ".K.", "..."],
	"C": ["KKK", "K..", "K..", "K..", "KKK"],
	"O": ["KKK", "K.K", "K.K", "K.K", "KKK"],
	"M": ["K...K", "KK.KK", "K.K.K", "K...K", "K...K"],
	"N": ["K..K", "KK.K", "K.KK", "K..K", "K..K"],
	"R": ["KK.", "K.K", "KK.", "K.K", "K.K"],
	"A": ["KKK", "K.K", "KKK", "K.K", "K.K"],
	"E": ["KKK", "K..", "KK.", "K..", "KKK"],
	"P": ["KKK", "K.K", "KKK", "K..", "K.."],
	"I": ["KKK", ".K.", ".K.", ".K.", "KKK"],
	"F": ["KKK", "K..", "KK.", "K..", "K.."],
	"U": ["K.K", "K.K", "K.K", "K.K", "KKK"],
	"S": ["KKK", "K..", "KKK", "..K", "KKK"],
}
