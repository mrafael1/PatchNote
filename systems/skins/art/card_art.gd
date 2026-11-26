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

## M50.4c2: the Supernova (a star with a white core inside its shockwave ring) and the
## Thunderclap (the sheet's shotgun with the clap's blast ahead of the barrel). The sheet has
## no picture for either: drawn in its style (warm, clean outline, the same colours).
const GUN_SUPERNOVA := ["......OOOOO......", "....OO.....OO....", "...O....Y....O...", "..O.Y...Y...Y.O..",
		".O...Y..Y..Y...O.", ".O....Y.Y.Y....O.", "O......YHY......O", "O..YYYYHHHYYYY..O",
		"O.YYYYHHWHHYYYY.O", "O..YYYYHHHYYYY..O", "O......YHY......O", ".O....Y.Y.Y....O.",
		".O...Y..Y..Y...O.", "..O.Y...Y...Y.O..", "...O....Y....O...", "....OO.....OO....", "......OOOOO......"]
const GUN_SUPERNOVA_LEGEND := {"O": &"ring", "Y": &"core", "H": &"bolt_hi", "W": &"tip"}
const GUN_THUNDERCLAP := ["...................O...O..", "...............L....OYO...",
		"....mmmmmmmmmmmL.O.YYHYY.O", "bbbbMMMMMMMMMMML..OYHWHYO.", "yyyyMMM..bbbb..L.O.YYHYY.O",
		"ddddMMM..ydyy.......OYO...", ".....L.............O...O.."]
const GUN_THUNDERCLAP_LEGEND := {"L": &"metal_lo", "M": &"metal", "b": &"crate_hi", "d": &"crate_lo",
		"m": &"metal_hi", "y": &"gold_lo", "O": &"ring", "Y": &"core", "H": &"bolt_hi", "W": &"tip"}

## M50.5a (Arcade's cards, the Arcade_Cards sheet): the Prism (the sheet's `ac-px-prism`: the
## shotgun's stock and body, the laser's pink core, the split prism head) and Cluster (the
## launcher's tube, its shell ahead with five bomblets round it; the sheet has no picture: drawn
## in its style).
const GUN_PRISM := ["...................RR.........", "...................RpRR.......", "...................RpRRRR.....",
		"...................RpRpRR.....", "mmmmmmmmmmmmmmmmmmmRRRRRRRR...", "MMMMMMRRRRRPPPPPPMMRRRRRRRR...",
		"MMMMMMRRRRRPPPPPPMMPppppppPP..", "RRRRRMMMMMMMMMMMMMMPPPPPPPP...", "RRRRRLLLLLLLLLLLLLLPPPPPPPP...",
		"RRRRR...CCC........PPPPPP.....", "RRRRR...CCC........PPPPPP.....", "RRRRR...CCC........PPPP.......",
		"rrrrr...CCC........PP.........", "........CCC..................."]
const GUN_PRISM_LEGEND := {"C": &"cell", "L": &"metal_lo", "M": &"metal", "P": &"pink", "R": &"might",
		"m": &"metal_hi", "p": &"pink_hi", "r": &"warn_dk"}
const GUN_CLUSTER := [".......LLL.................", ".......LLY.........hY..hY..", "MMM....LLL.........YY..YY..",
		"LLwwwYYwwwwwYYw............", "LLWWWYYWWWWWYYhYh...OOO....", "LLWWWYYWWWWWYYWYY...OHO..hY",
		"LLWWWYYWWWWWYYWYY...OHO..YY", "LLWWWYYWWWWWYYWYY...OOO....", "LLDDDYYDDDDDYYDyy..........",
		"LL.....bby.............hY..", ".......bbyK........hY..YY..", ".......bby.........YY......",
		".......bby................."]
const GUN_CLUSTER_LEGEND := {"D": &"warn_dk", "H": &"bolt_hi", "K": &"ink", "L": &"metal_lo", "M": &"metal",
		"O": &"ring", "W": &"warn", "Y": &"gold", "b": &"crate_hi", "h": &"gold_hi", "w": &"warn_hi", "y": &"gold_lo"}

## Weapon icon -> [grid, legend].
const GUNS := {
	&"dot": [GUN_PISTOL, GUN_PISTOL_LEGEND], &"fan": [GUN_SHOTGUN, GUN_SHOTGUN_LEGEND],
	&"line": [GUN_LASER, GUN_LASER_LEGEND], &"bomb": [GUN_LAUNCHER, GUN_LAUNCHER_LEGEND],   # M50.5: Arcade renamed the launcher icon ball -> bomb
	&"minigun": [GUN_MINIGUN, GUN_MINIGUN_LEGEND],
	&"supernova": [GUN_SUPERNOVA, GUN_SUPERNOVA_LEGEND], &"thunderclap": [GUN_THUNDERCLAP, GUN_THUNDERCLAP_LEGEND],
	&"prism": [GUN_PRISM, GUN_PRISM_LEGEND], &"cluster": [GUN_CLUSTER, GUN_CLUSTER_LEGEND],   # M50.5a: Arcade's fusions
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


## M50.4f (the sheet's effect line): the 8 x 8 mechanic icons drawn left of a card's effect, by
## trait id (Arcade_Cards' vocabulary: heavy round, seeker, chain, burn line, ricochet,
## overcharge, ...). A mechanic without a row draws MECH_SPARK.
const MECH_OVERCHARGE := [".....Y..", "....YYY.", ".....Y..", "HHHHHYHH", "PPPPPYPP", ".....Y..", "....YYY.",
		".....Y.."]
const MECH_HEAVY := ["..YYYY..", ".YHHYYY.", "YHYYYYYO", "YYYYYYYO", "YYYYYYYO", "YYYYYYOO", ".YYYYOO.", "..OOOO.."]
const MECH_SEEKER := ["...MM...", ".MM..MM.", ".M....M.", "M..PP..M", "M..PP..M", ".M....M.", ".MM..MM.", "...MM..."]
const MECH_CHAIN := ["....YYY.", "...YYY..", "..YYY...", ".YYYYYY.", "...YYY..", "..YYY...", ".YYY....", ".YY....."]
const MECH_BURN := ["...O....", "...OO...", "..OYO...", "..OYYO..", ".OYHYO..", ".OYHHYO.", "OOYYYYOO", "RRRRRRRR"]
const MECH_RICOCHET := ["M.......", "MM....M.", ".M...MM.", ".MM..M..", "..M.MM..", "..MMM...", "...M....", "KKKKKKKK"]
const MECH_CONE := ["......YY", "....YYY.", "..YYY...", "MMYY....", "MMYY....", "..YYY...", "....YYY.", "......YY"]
const MECH_BLANK := ["Y..Y..Y.", ".Y.Y.Y..", "..YYY...", "YYYHYYY.", "..YYY...", ".Y.Y.Y..", "Y..Y..Y.", "........"]
const MECH_SHRAPNEL := ["Y.....Y.", "..O.O...", ".O...O..", "...H....", ".O...O..", "..O.O...", "Y.....Y.", "........"]
const MECH_SWEEP := ["...YYY..", ".YY...Y.", "Y.....Y.", "Y.....YH", "......YH", ".......H", ".....HH.", "........"]
const MECH_SPARK := ["...Y....", "...Y....", "..YHY...", "YYHHHYY.", "..YHY...", "...Y....", "...Y....", "........"]
const MECH_LEGEND := {"Y": &"gold", "H": &"gold_hi", "O": &"gold_lo", "P": &"pink", "M": &"mint", "R": &"warn",
		"K": &"metal"}
const MECH_PINK := {"Y": &"gold", "H": &"pink_hi", "P": &"pink", "O": &"gold_lo", "M": &"mint", "R": &"warn",
		"K": &"metal"}
const MECHS := {
	&"overcharge": [MECH_OVERCHARGE, MECH_PINK], &"overcharge_beam": [MECH_OVERCHARGE, MECH_PINK],
	&"heavy_round": [MECH_HEAVY, MECH_LEGEND], &"seeker": [MECH_SEEKER, MECH_LEGEND], &"chain": [MECH_CHAIN, MECH_LEGEND],
	&"burn_line": [MECH_BURN, MECH_LEGEND], &"burn_line_prism": [MECH_BURN, MECH_LEGEND],
	&"ricochet": [MECH_RICOCHET, MECH_LEGEND], &"knockback_cone": [MECH_CONE, MECH_LEGEND],
	&"point_blank": [MECH_BLANK, MECH_LEGEND], &"shrapnel": [MECH_SHRAPNEL, MECH_LEGEND],
	&"sweep": [MECH_SWEEP, MECH_LEGEND],
}

## The gun's muzzle row (a beam leaves there), per weapon icon; a missing icon has no beam.
const MUZZLE_ROW := {&"line": 2}


## M50.4f: mechanic `trait_id`'s 8 x 8 icon with its top-left at `at`, `px` per cell, outlined.
static func draw_mech(ci: CanvasItem, trait_id: StringName, at: Vector2, px: float) -> void:
	var row: Array = MECHS.get(trait_id, [MECH_SPARK, MECH_LEGEND])
	_draw_grid_px(ci, row[0], row[1], at, px)


## M50.4f (the sheet's card window): the cell size at which a grid of `cols` x `rows` (its
## outline included) fills about 90 % of `box`, clamped to `least`..`most`.
static func card_px(cols: int, rows: int, box: Vector2, least := 2.0, most := 7.0) -> float:
	var fit := minf(floorf(box.y * 0.9 / (rows + 2)), floorf(box.x * 0.9 / (cols + 2)))
	return clampf(fit, least, most)


## M50.4f: the picture of `icon` (its gun, else its item glyph) centred at `centre`, at the
## cell size that fills `box` (card_px). Returns the drawn rect (outline excluded), or an empty
## Rect2 when the icon has no grid.
static func draw_card_art(ci: CanvasItem, icon: StringName, centre: Vector2, box: Vector2, most := 7.0,
		least := 2.0) -> Rect2:
	var row: Array = GUNS.get(icon, GLYPHS.get(icon, []))
	if row.is_empty():
		return Rect2()
	var grid: Array = row[0]
	var cols := String(grid[0]).length()
	var px := card_px(cols, grid.size(), box, least, most)
	var at := (centre - Vector2(cols, grid.size()) * px * 0.5).round()
	_draw_grid_px(ci, grid, row[1], at, px)
	return Rect2(at, Vector2(cols, grid.size()) * px)


static func _draw_grid_px(ci: CanvasItem, grid: Array, legend: Dictionary, at: Vector2, px: float) -> void:
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
