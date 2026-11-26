class_name CardArt
extends RefCounted
## M50.4b (Auto depth design 7, the M50.4m sheet `Auto_Choices`): the level-up cards' Pixel
## art: the item glyphs (Haste, Area, Might wired; Duration, Amount, Speed, Magnet for later),
## the two filler glyphs and the card colours, drawn in code from grids (no image file). Like
## RailArt, kept out of grids.gd on purpose: ArtSkin.digest() hashes grids.gd, and these are UI
## pictures, not the arena's atlas (Arcade moves that digest in parallel).
##
## Colours are RailArt's (the version rail's plum-and-paper set, the mockup's), plus the few
## below. Grid letters: . transparent, then each grid's legend; every grid is drawn with a
## 1-cell ink outline (RailArt.draw_grid's outline).

const HEX := {&"bolt": "#ffd84a", &"bolt_hi": "#fff0a0", &"bolt_lo": "#ff9a6b",
		&"ring": "#ff9a6b", &"ring_lo": "#e0664f", &"core": "#ffd84a",
		&"might": "#ff6b5a", &"might_hi": "#ffc0b0", &"glass": "#bfa9d9", &"sand": "#ffd84a",
		&"dot": "#6cf0c2", &"dot_hi": "#c8ffe9", &"chev": "#6cf0c2", &"chev_lo": "#3f8f78",
		&"magnet": "#ff6b5a", &"tip": "#fff8ec", &"boost": "#ffd84a", &"boost_lo": "#c98a2e",
		&"metal_hi": "#efe4ff", &"metal_lo": "#7a6a9a", &"metal_mid": "#9a8ab8", &"crate_lo": "#8a5a1e",
		&"warn_hi": "#ffc8a0", &"warn_dk": "#c95a3a"}

const HASTE := [".....YYYY.", "....YHYY..", "...YHYY...", "..YHYY....", ".YYYYYYYY.", ".YYYYYYYO.",
		".....YYO..", "....YYO...", "...YYO....", "...YO.....", "..YO......", "..O......."]
const HASTE_LEGEND := {"Y": &"bolt", "H": &"bolt_hi", "O": &"bolt_lo"}
const AREA := ["....OOOO....", "..OOOOOOOO..", ".OOL....LOO.", ".OL......LO.", "OO...YY...OO",
		"OO..YYYY..OO", "OO..YYYY..OO", "OO...YY...OO", ".OL......LO.", ".OOL....LOO.",
		"..OOOOOOOO..", "....OOOO...."]
const AREA_LEGEND := {"O": &"ring", "L": &"ring_lo", "Y": &"core"}
const MIGHT := [".....RR.....", "....RHRR....", "...RHRRRR...", "..RHRRRRRR..", ".RHRRRRRRRR.",
		"RRRRRRRRRRRR", "....RHRR....", "....RHRR....", "....RHRR....", "....RHRR....",
		"....RHRR....", "....RRRR...."]
const MIGHT_LEGEND := {"R": &"might", "H": &"might_hi"}
const DURATION := ["GGGGGGGGGG", ".G......G.", ".GSSSSSSG.", "..GSSSSG..", "...GSSG...", "....GG....",
		"...G..G...", "..G.SS.G..", ".G.SSSS.G.", ".GSSSSSSG.", "GGGGGGGGGG"]
const DURATION_LEGEND := {"G": &"glass", "S": &"sand"}
const AMOUNT := ["DDD.DDD.DDD", "DHD.DHD.DHD", "DDD.DDD.DDD"]
const AMOUNT_LEGEND := {"D": &"dot", "H": &"dot_hi"}
const SPEED := ["CC....CC....", ".CC....CC...", "..CC....CC..", "...CL....CL.", "..CC....CC..",
		".CC....CC...", "CC....CC...."]
const SPEED_LEGEND := {"C": &"chev", "L": &"chev_lo"}
const ATTRACT := ["WW....WW", "WW....WW", "RR....RR", "RR....RR", "RR....RR", "RRR..RRR", ".RRRRRR.",
		"..RRRR.."]
const ATTRACT_LEGEND := {"R": &"magnet", "W": &"tip"}
const BOOST := ["....BB....", "...BBBB...", "..BBBBBB..", ".BBBBBBBB.", "...BBBB...", "...BBBB...",
		"...BBBB...", "...LLLL..."]
const BOOST_LEGEND := {"B": &"boost", "L": &"boost_lo"}

## Glyph key -> [grid, legend]. `hp` is RailArt's heart.
const GLYPHS := {
	&"haste": [HASTE, HASTE_LEGEND], &"area": [AREA, AREA_LEGEND], &"might": [MIGHT, MIGHT_LEGEND],
	&"duration": [DURATION, DURATION_LEGEND], &"amount": [AMOUNT, AMOUNT_LEGEND],
	&"speed": [SPEED, SPEED_LEGEND], &"attract": [ATTRACT, ATTRACT_LEGEND], &"boost": [BOOST, BOOST_LEGEND],
	&"hp": [RailArt.HEART, RailArt.HEART_LEGEND],
}

## M50.4b review: the guns of the sheet (Auto_Choices' rail slots and the Launcher card),
## one picture per weapon so two weapon cards never show the same pellet. Keyed by the
## weapon's icon; weapons without a row (nova, well, orbit, fusions) keep WeaponGlyph's.
const GUN_PISTOL := ["..........L..", "mmmmmmmmmmmm.", "MMNNNNNMMMMMY", "LLLLLLLLLLLL.", ".byyLLL......",
		".byy.KL......", ".byy.........", ".byy.........", ".byd........."]
const GUN_PISTOL_LEGEND := {"K": &"ink", "L": &"metal_lo", "M": &"metal", "N": &"metal_mid", "Y": &"gold",
		"b": &"crate_hi", "d": &"crate_lo", "m": &"metal_hi", "y": &"gold_lo"}
const GUN_SHOTGUN := ["...............L", "....mmmmmmmmmmmL", "bbbbMMMMMMMMMMML", "yyyyMMM..bbbb..L",
		"ddddMMM..ydyy...", ".....L.........."]
const GUN_SHOTGUN_LEGEND := {"L": &"metal_lo", "M": &"metal", "b": &"crate_hi", "d": &"crate_lo",
		"m": &"metal_hi", "y": &"gold_lo"}
const GUN_LASER := ["..mmmmmmmm....", "LLMMMMMMMMhhh.", "LLMMpPPPMMYYYP", "LLMMMMMMMMyyy.", "..LLLLLLLL....",
		"...by.........", "...by.........", "...by........."]
const GUN_LASER_LEGEND := {"L": &"metal_lo", "M": &"metal", "P": &"pink", "Y": &"gold", "b": &"crate_hi",
		"h": &"gold_hi", "m": &"metal_hi", "p": &"pink_hi", "y": &"gold_lo"}
const GUN_LAUNCHER := ["...........LLLL..............", "...........LLLY..............",
		"MMM........LLLL..............", "LLLwwwwYYwwwwwwwwwYYwwww.....", "LLLwwwwYYwwwwwwwwwYYwwwwhh...",
		"LLLWWWWYYWWWWWWWWWYYWWWWYYYY.", "LLLWWWWYYWWWWWWWWWYYWWWWYYYYy", "LLLWWWWYYWWWWWWWWWYYWWWWYYYYy",
		"LLLWWWWYYWWWWWWWWWYYWWWWYYYY.", "LLLWWWWYYWWWWWWWWWYYWWWWYY...", "LLLDDDDYYDDDDDDDDDYYDDDD.....",
		"LLL.......byy.K..............", "..........byy.K..............", "..........byy................",
		"..........byy................", "..........byy................"]
const GUN_LAUNCHER_LEGEND := {"D": &"warn_dk", "K": &"ink", "L": &"metal_lo", "M": &"metal", "W": &"warn",
		"Y": &"gold", "b": &"crate_hi", "h": &"gold_hi", "w": &"warn_hi", "y": &"gold_lo"}

## M50.4c1: the Minigun of the sheet's EVOLVE card (a drum, a barrel bundle with two gold
## bands, an ammo belt hanging off the drum).
const GUN_MINIGUN := ["...LLLLLLL.....................", "...L.....L.....................",
		"...L.....L.....................", "...L.....L.....................", ".bbbbbbbbbb...hY.......YY......",
		".bbbbbbbbbbmmmhYmmmmmmmYYmmm...", ".yyyyyyyyyymmmhYmmmmmmmYYmmm.Y.", ".yyyyyyyyyyCCChYCCCCCCCYYCCC.Y.",
		".yyddddddyymmmhYmmmmmmmYYmmmmYh", ".yyyyyyyyyyMMMhYMMMMMMMYYMMMMYh", ".yyyyyyyyyyMMMhYMMMMMMMYYMMMMYh",
		".yyddddddyyCCChYCCCCCCCYYCCC.Y.", ".yyyyyyyyyyLLLhYLLLLLLLYYLLL.Y.", ".yyyyyyyyyyLLLhYLLLLLLLYYLLL...",
		".yyyyyyyyyy...hY.......yy......", ".dddddddddd....................", "...YYYY.yyy....................",
		"...yyyy.yyy....................", "..YYYY..yyy....................", "..yyyy..yyy....................",
		".YYYY..........................", ".yyyy..........................", "YYYY..........................."]
const GUN_MINIGUN_LEGEND := {"C": &"cell", "L": &"metal_lo", "M": &"metal", "Y": &"gold", "b": &"crate_hi",
		"d": &"crate_lo", "h": &"gold_hi", "m": &"metal_hi", "y": &"gold_lo"}

## Weapon icon -> [grid, legend].
const GUNS := {
	&"dot": [GUN_PISTOL, GUN_PISTOL_LEGEND], &"fan": [GUN_SHOTGUN, GUN_SHOTGUN_LEGEND],
	&"line": [GUN_LASER, GUN_LASER_LEGEND], &"ball": [GUN_LAUNCHER, GUN_LAUNCHER_LEGEND],
	&"minigun": [GUN_MINIGUN, GUN_MINIGUN_LEGEND],
}

static var _cache := {}


## A card colour by role: this file's, else RailArt's (MAGENTA for a typo).
static func c(role: StringName) -> Color:
	if _cache.is_empty():
		for k: StringName in HEX:
			_cache[k] = Color.html(HEX[k])
	if _cache.has(role):
		return _cache[role]
	return RailArt.c(role)


static func has(key: StringName) -> bool:
	return GLYPHS.has(key)


## Draws glyph `key` centred at `centre` at the largest whole cell size that fits `size`
## (outline included). False for a key it has no grid for.
static func draw(ci: CanvasItem, key: StringName, centre: Vector2, size: float) -> bool:
	if not GLYPHS.has(key):
		return false
	_draw_grid(ci, GLYPHS[key][0], GLYPHS[key][1], centre, size)
	return true


## M50.4b review: the gun of weapon icon `icon` (GUNS), like draw(). False without a row.
static func draw_gun(ci: CanvasItem, icon: StringName, centre: Vector2, size: float) -> bool:
	if not GUNS.has(icon):
		return false
	_draw_grid(ci, GUNS[icon][0], GUNS[icon][1], centre, size)
	return true


static func _draw_grid(ci: CanvasItem, grid: Array, legend: Dictionary, centre: Vector2, size: float) -> void:
	var cells := Vector2(String(grid[0]).length() + 2, grid.size() + 2)
	var px := maxf(1.0, floorf(size / maxf(cells.x, cells.y)))
	var at := (centre - Vector2(String(grid[0]).length(), grid.size()) * px * 0.5).round()
	for y in grid.size():
		var row: String = grid[y]
		for x in row.length():
			if row[x] != ".":
				ci.draw_rect(Rect2(at + Vector2(x - 1, y - 1) * px, Vector2(px * 3.0, px * 3.0)), c(&"ink"))
	for y in grid.size():
		var row: String = grid[y]
		for x in row.length():
			if row[x] != ".":
				ci.draw_rect(Rect2(at + Vector2(x, y) * px, Vector2(px, px)), c(legend.get(row[x], &"ink")))
