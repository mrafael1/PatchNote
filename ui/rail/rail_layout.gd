class_name RailLayout
extends RefCounted
## M48.5a: the version rail's layout (owner pick 3A, Pixel_A mockup). Pure: a window size in,
## rects out. The design canvas is the mockup's own 1600x900 (16:9), scaled by
## s = min(W / 1600, H / 900) and centred; spare margins are the plum checker. The game view
## is 1056x594 design px (16:9, so the 1280x720 sim stretches evenly), the rail runs under
## it and on to the chat, the module row hangs under the rail, the chat log sits right of the
## game and the reply box under the rail on the right.
##
## Modules hang in ship order, left to right (the rail is a timeline): KILLS v0.2, HP v0.3,
## DASH v0.4, then the path slot (Arsenal HAND + PACK, Auto ITEMS, Survival AMMO).

const DESIGN := Vector2(1600, 900)
const BASE := Vector2i(1600, 900)    ## the windowed size while the rail shows

const SHAPE := Rect2(8, 8, 1584, 884)
const BEZEL := Rect2(12, 12, 1096, 622)
const GAME := Rect2(32, 24, 1056, 594)
const CAPTION := Vector2(32, 621)
const TRACK := Rect2(12, 638, 1576, 32)
const ROW_Y := 674.0
const ROW_H := 214.0
const GAP := 4.0
const LOG := Rect2(1112, 12, 476, 622)
const REPLY := Rect2(1112, 674, 476, 214)
const BLOB := Rect2(1488, 570, 84, 72)
## Review: the log's rows end above the body on the rail (its top, 570, less 6), so the newest
## line and the scrollbar never run under it.
const LOG_BOTTOM_PAD := LOG.end.y - BLOB.position.y + 6.0
const SPINE_X := 20.0                 ## the chat spine's x inside the log
const HEADER_H := 40.0                ## the chat log's header bar
## The module cells (design px): id -> width, in order. The path slot is 568 wide.
const CELLS := [[&"kills", 124.0], [&"hp", 172.0], [&"dash", 220.0], [&"path", 568.0]]
const HAND_W := 350.0                 ## Arsenal splits the path slot: HAND 350 + PACK 214


## The layout for a window of `window` px: GameHost's keys (k, game, terminal, font) plus the
## rail's own (s, origin, and every rect in window px).
static func layout_for(window: Vector2) -> Dictionary:
	var s := maxf(0.05, minf(window.x / DESIGN.x, window.y / DESIGN.y))
	var origin := ((window - DESIGN * s) * 0.5).round()
	var out := {"rail": true, "s": s, "origin": origin, "px": art_px(s)}
	out.shape = map(SHAPE, s, origin)
	out.bezel = map(BEZEL, s, origin)
	out.game = map(GAME, s, origin)
	out.k = out.game.size.y / 720.0
	out.caption = (origin + CAPTION * s).round()
	out.track = map(TRACK, s, origin)
	out.terminal = map(LOG, s, origin)
	out.log = out.terminal
	out.reply = map(REPLY, s, origin)
	out.blob = map(BLOB, s, origin)
	out.font = font_px(s)
	var cells := {}
	var x := TRACK.position.x
	for pair: Array in CELLS:
		var w: float = pair[1]
		cells[pair[0]] = map(Rect2(x, ROW_Y, w, ROW_H), s, origin)
		x += w + GAP
	var path_x := TRACK.position.x + 124.0 + 172.0 + 220.0 + GAP * 3.0
	cells[&"hand"] = map(Rect2(path_x, ROW_Y, HAND_W, ROW_H), s, origin)
	cells[&"pack"] = map(Rect2(path_x + HAND_W + GAP, ROW_Y, 568.0 - HAND_W - GAP, ROW_H), s, origin)
	out.cells = cells
	out.spine_x = roundf(origin.x + (LOG.position.x + SPINE_X) * s)
	return out


## A design rect in window px, snapped to whole pixels.
static func map(r: Rect2, s: float, origin: Vector2) -> Rect2:
	var p := (origin + r.position * s).round()
	var e := (origin + r.end * s).round()
	return Rect2(p, e - p)


## One "art pixel" (the outlines' and bevels' unit): 2 px at s = 1, never under 1.
static func art_px(s: float) -> float:
	return maxf(1.0, roundf(2.0 * s))


## The body font size: 16 at s = 1 and below (the pixel font smears under it), in steps of 8
## (its grid) above.
static func font_px(s: float) -> int:
	return maxi(16, int(roundf(16.0 * s / 8.0)) * 8)


## A text size for design px `d` (12, 16, 24...) at scale s, never under 12 (or `d` itself).
static func text_px(d: float, s: float) -> int:
	return maxi(roundi(d * s), mini(int(d), 12))
