class_name CardArt
extends RefCounted
## M50.2c: Arcade's card faces (design `.check/arcade_s10/design.md` 2.5, the mockups
## `.check/mockups/cards/Arcade_Cards` and `Arcade_Pack`). A separate baked art script, like
## the rail's rail_art.gd: ArtSkin.digest() of grids.gd (the arena's atlas) never sees it, so
## the atlas digest does not move; this file has its own digest (`digest()`).
##
## Two faces (design D16): tier 0 (S7 / S8, before S9's `skin ui`: the AI has not drawn assets
## yet) is a code-drawn rounded card in FLAT's colours; Pixel (after `skin ui`, or
## `--look=pixel`) wears the 9-slice frames below at FRAME_SCALE, with the PIXEL colours for
## the drawn parts (band, art box, badge, name bar, pips). The rare gold is the look's
## `card_rare` role (Palette.color), read at draw time, so a later ROLES entry needs no rebake.
##
## Pure data and small helpers: no RNG, no Tuning, no RunState. Every colour of ui/card_face.gd
## comes from here or Palette (the colour lint's home is systems/skins/). Grid letters as in
## grids.gd: . clear, K outline, P main, S shade, H highlight, A accent, W white.

const FRAME_SCALE := 3   ## one cell = 3 px (the mockup's "sprites x3")

const PALETTE := {
	"outline": "#1e1424",
	"eye": "#1e1424",
	"white": "#fff8ec",
}

## The frames (each a 9-slice: MARGINS cells on every side, a plain P centre that tiles).
const SPRITES := {
	# A common card: cream paper, a light top-left bevel, a dark lip under it.
	"card_common": {
		"grid": [
			"................",
			".KKKKKKKKKKKKKK.",
			".KHHHHHHHHHHHHK.",
			".KHHPPPPPPPPSSK.",
			".KHPPPPPPPPPPSK.",
			".KHPPPPPPPPPPSK.",
			".KHPPPPPPPPPPSK.",
			".KHPPPPPPPPPPSK.",
			".KHPPPPPPPPPPSK.",
			".KHPPPPPPPPPPSK.",
			".KHPPPPPPPPPPSK.",
			".KHPPPPPPPPPPSK.",
			".KSSSSSSSSSSSSK.",
			".KKKKKKKKKKKKKK.",
			".KKKKKKKKKKKKKK.",
			"..KKKKKKKKKKKK..",
		],
		"ramp": {"P": "#f3e2b8", "S": "#d9c08a", "H": "#fff4d8"},
	},
	# A rare card: gold foil inside a gold-lo / gold-hi inset, a pink outer ring.
	"card_rare": {
		"grid": [
			".AAAAAAAAAAAAAA.",
			"AKKKKKKKKKKKKKKA",
			"AKSSSSSSSSSSSSKA",
			"AKSHHHHHHHHHHSKA",
			"AKSHPPPPPPPPHSKA",
			"AKSHPPPPPPPPHSKA",
			"AKSHPPPPPPPPHSKA",
			"AKSHPPPPPPPPHSKA",
			"AKSHPPPPPPPPHSKA",
			"AKSHPPPPPPPPHSKA",
			"AKSHPPPPPPPPHSKA",
			"AKSHHHHHHHHHHSKA",
			"AKSSSSSSSSSSSSKA",
			"AKKKKKKKKKKKKKKA",
			"AKKKKKKKKKKKKKKA",
			".AAAAAAAAAAAAAA.",
		],
		"ramp": {"P": "#ffd84a", "S": "#c98a2e", "H": "#fff0a0", "A": "#ff8fb0"},
	},
	# FUSE: stepped prism bands (pink, orange, violet) round a cream face.
	"card_fuse": {
		"grid": [
			"................",
			".KKKKKKKKKKKKKK.",
			".KHHHHHHHHHHHHK.",
			".KHSSSSSSSSSSHK.",
			".KHSAAAAAAAASHK.",
			".KHSAPPPPPPASHK.",
			".KHSAPPPPPPASHK.",
			".KHSAPPPPPPASHK.",
			".KHSAPPPPPPASHK.",
			".KHSAPPPPPPASHK.",
			".KHSAPPPPPPASHK.",
			".KHSAAAAAAAASHK.",
			".KHSSSSSSSSSSHK.",
			".KHHHHHHHHHHHHK.",
			".KKKKKKKKKKKKKK.",
			"..KKKKKKKKKKKK..",
		],
		"ramp": {"P": "#fff4d8", "S": "#ffb070", "H": "#ff8ac0", "A": "#c79bff"},
	},
	# The give card ("a gold card"): gold foil, a white sparkle ring instead of the pink.
	"card_give": {
		"grid": [
			".WWWWWWWWWWWWWW.",
			"WKKKKKKKKKKKKKKW",
			"WKSSSSSSSSSSSSKW",
			"WKSHHHHHHHHHHSKW",
			"WKSHPPPPPPPPHSKW",
			"WKSHPPPPPPPPHSKW",
			"WKSHPPPPPPPPHSKW",
			"WKSHPPPPPPPPHSKW",
			"WKSHPPPPPPPPHSKW",
			"WKSHPPPPPPPPHSKW",
			"WKSHPPPPPPPPHSKW",
			"WKSHHHHHHHHHHSKW",
			"WKSSSSSSSSSSSSKW",
			"WKKKKKKKKKKKKKKW",
			"WKKKKKKKKKKKKKKW",
			".WWWWWWWWWWWWWW.",
		],
		"ramp": {"P": "#ffd84a", "S": "#c98a2e", "H": "#fff0a0"},
	},
	# The card's back (face-down before its flip): plum with a gold inner line.
	"card_back": {
		"grid": [
			"................",
			".KKKKKKKKKKKKKK.",
			".KHHHHHHHHHHHHK.",
			".KHPPPPPPPPPPSK.",
			".KHPAAAAAAAAPSK.",
			".KHPAPPPPPPAPSK.",
			".KHPAPPPPPPAPSK.",
			".KHPAPPPPPPAPSK.",
			".KHPAPPPPPPAPSK.",
			".KHPAPPPPPPAPSK.",
			".KHPAPPPPPPAPSK.",
			".KHPAAAAAAAAPSK.",
			".KSSSSSSSSSSSSK.",
			".KKKKKKKKKKKKKK.",
			".KKKKKKKKKKKKKK.",
			"..KKKKKKKKKKKK..",
		],
		"ramp": {"P": "#4e3866", "S": "#33254a", "H": "#6a5290", "A": "#ffd84a"},
	},
	# The NEW / RARE +2 / GOLD CARD ribbon (a 9-slice strip, text drawn over it).
	"ribbon": {
		"grid": [
			"KKKKKKKK",
			"KHHHHHHK",
			"KPPPPPPK",
			"KPPPPPPK",
			"KPPPPPPK",
			"KPPPPPPK",
			"KSSSSSSK",
			"KKKKKKKK",
		],
		"ramp": {"P": "#ff5d8f", "S": "#c23f6e", "H": "#ffa3c0"},
	},
}

## The 9-slice margin (cells) of each frame.
const MARGINS := {
	&"card_common": 5, &"card_rare": 5, &"card_fuse": 5, &"card_give": 5, &"card_back": 5, &"ribbon": 2,
}

## The Pixel face's drawn parts (the mockup's ramp).
const PIXEL := {
	&"ink": "#1e1424", &"paper": "#f3e2b8", &"paper_lo": "#d9c08a", &"paper_hi": "#fff4d8",
	&"cell": "#4e3866", &"check": "#553f70", &"cell_lo": "#3a2a4f",
	&"gold": "#ffd84a", &"gold_lo": "#c98a2e", &"gold_hi": "#fff0a0",
	&"pink": "#ff5d8f", &"red": "#c23f2e", &"text": "#1e1424", &"foot": "#6a5290",
	&"rare_foot": "#8a4f12", &"gem": "#b9a6d1", &"name": "#f3e2b8", &"mint": "#6cf0c2",
}

## The tier-0 face (S7 / S8): the mockup's flat half, plain colours.
const FLAT := {
	&"face": "#2c2538", &"face_hi": "#352d44", &"edge": "#4a4060", &"art": "#241e2e",
	&"text": "#ece6f3", &"dim": "#8a809e", &"gold": "#e8c15a", &"pink": "#ff6b8a",
	&"pip": "#3a3248", &"ink": "#1e1424", &"back": "#2a2236", &"fuse": "#ff8ac0",
	&"give": "#ffd84a", &"red": "#ff6b5a",
}

## A card's top band by its weapon's icon key (keys, never weapon ids): [main, shade].
const BAND := {
	&"dot": ["#ffb35a", "#c98a2e"], &"fan": ["#ff6b5a", "#c0503c"], &"line": ["#ff6b8a", "#c23f6e"],
	&"prism": ["#c79bff", "#8c5fd0"], &"ball": ["#ff9a6b", "#e0664f"], &"ring": ["#6cf0c2", "#3f8f78"],
	&"burst": ["#ffd84a", "#c98a2e"], &"hole": ["#b84ee0", "#7a2ea0"], &"misfuse": ["#bfa9d9", "#6a5290"],
	## M50.3a: the launcher's key is now `bomb` (keeps the old `ball` pair); `cluster` for M50.3b.
	&"bomb": ["#ff9a6b", "#e0664f"], &"cluster": ["#ff8a4a", "#c95a2e"],
}

static var _skin: ArtSkin
static var _frames := {}
static var _cache := {}


## The baked frames (one bake per process; pure, so two bakes match: digest()).
static func skin() -> ArtSkin:
	if _skin == null:
		_skin = ArtSkin.bake(load("res://systems/skins/art/card_art.gd"), &"cards")
	return _skin


## This art's own digest (the frames' images); the arena atlas's is ArtSkin.digest() of grids.gd.
static func digest() -> String:
	return skin().digest()


## A frame as a 9-slice StyleBoxTexture at FRAME_SCALE (cached; take a duplicate() to change it).
static func frame(id: StringName) -> StyleBoxTexture:
	if _frames.has(id):
		return _frames[id]
	var src := skin().image(id)
	if src == null:
		return null
	var img := src.duplicate() as Image
	img.resize(img.get_width() * FRAME_SCALE, img.get_height() * FRAME_SCALE, Image.INTERPOLATE_NEAREST)
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(img)
	var m := float(int(MARGINS.get(id, 2)) * FRAME_SCALE)
	box.texture_margin_left = m
	box.texture_margin_top = m
	box.texture_margin_right = m
	box.texture_margin_bottom = m
	_frames[id] = box
	return box


## A Pixel colour by name (MAGENTA for a typo, as Palette does).
static func px(name: StringName) -> Color:
	return _col(&"p", name, PIXEL)


## A tier-0 colour by name.
static func flat(name: StringName) -> Color:
	return _col(&"f", name, FLAT)


## The band [main, shade] for an icon key (a plain lilac for an unknown key).
static func band(icon: StringName) -> Array[Color]:
	var pair: Array = BAND.get(icon, BAND[&"misfuse"])
	return [Color.html(String(pair[0])), Color.html(String(pair[1]))]


static func _col(table: StringName, name: StringName, src: Dictionary) -> Color:
	var key := String(table) + ":" + String(name)
	if not _cache.has(key):
		_cache[key] = Color.html(String(src[name])) if src.has(name) else Color.MAGENTA
	return _cache[key]
