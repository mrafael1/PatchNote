class_name CabinetLayout
extends RefCounted
## M48.6a: the cabinet's layout (PLAN 0.9.2, the Pixel look's UI; it takes RailLayout's
## place). Pure: a window size in, rects out. The design canvas is 1600x900, as the rail's;
## one art pixel is 3 design px. The game view is 1152x648 design px (16:9, 384x216 art px);
## spare margins are the backdrop's checker.
##
## M48.6b (owner): the cabinet fills the window as the rail did: s = min(W / 1600, H / 900).
## It snaps down to a whole number of screen px per art px only when that costs less than
## SNAP_LOSS of the size (1600x900 is exact, 4K snaps to 7; 1920x1080 fills at 1.2, where one
## art px is 3.6 screen px). The view is always exactly 16:9 in whole px, so the 1280x720 sim
## stretches evenly.
##
## The deck holds the host's camera box at its left (the AI's body inside), then the mood plate
## and the caption bubble (M48.6b), then the path's modules (the rail's items / ammo cells at
## MODULE_K of their rail size, until M48.6e-f restyle them). KILLS / HP / DASH have no cell
## here: they are on the player and on the view's corner plate. M48.6d: Arcade's HAND and PACK
## have no cell either: the Arcade dock (CabinetDock) stands there.
##
## M48.6c: the chat column is one pixel dev-chat (chat_parts): the header, the 2-line build
## log, the messages, the reply pills (as many rows as they need, none with no pill) and the
## input line, stacked inside the chat's frame. The terminal's own rect is the messages area
## (its rows are the chat's model; CabinetChatView draws them).

const DESIGN := Vector2(1600, 900)
const BASE := Vector2i(1600, 900)    ## the windowed size while the cabinet shows
const ART := 3.0                     ## design px per art px
const SNAP_LOSS := 0.04              ## the most size a whole-px snap may cost

## The plan's table (design px).
const CABINET := Rect2(12, 12, 1196, 876)
const MARQUEE := Rect2(34, 24, 1152, 42)
const VIEW := Rect2(34, 78, 1152, 648)
const DECK := Rect2(34, 748, 1152, 128)
const CHAT := Rect2(1218, 12, 370, 876)

## The deck: the camera box at its left (the mockup's 44x36 art px), the body inside it, the
## caption to its right (the mood plate on the bubble's top edge), the path's modules after.
const HOST := Rect2(46, 758, 132, 108)
const BLOB := Rect2(70, 761, 84, 84)
const CAPTION := Rect2(202, 767, 330, 102)   ## the caption bubble
const MOOD := Vector2(211, 752)              ## the mood plate's top-left (9 art px tall)
const MODULES := Rect2(544, 757, 630, 110)
const MODULE_K := MODULES.size.y / RailLayout.ROW_H   ## the modules' size against the rail's
const PATH_W := 568.0                        ## the rail's path slot (RailLayout.CELLS)
## The view's corner plate: its top-left inside the view.
const PLATE := Vector2(18, 18)
## The chat column's parts, in art px (the mockup's .chat): the frame's ring, the header, the
## build log, a pill, the input line and the gaps around them.
const CHAT_RING := 2
const CHAT_HEAD := 30
const CHAT_LOG := 17
const CHAT_PILL := 11
const CHAT_PILL_GAP := 2
const CHAT_INPUT := 14
const CHAT_PAD := 3


## The scale for a window: the fit; snapped down to a whole number of screen px per art px
## only when that loses less than SNAP_LOSS of the size.
static func scale_for(window: Vector2) -> float:
	var fit := maxf(0.05, minf(window.x / DESIGN.x, window.y / DESIGN.y))
	var px := floorf(ART * fit + 0.0001)
	if px < 1.0:
		return fit
	var snapped := px / ART
	return snapped if (fit - snapped) / fit < SNAP_LOSS else fit


## One art pixel in screen px at scale s: 3 at s = 1, whole when the scale snapped, never
## under 1.
static func art_px(s: float) -> float:
	var a := ART * s
	return maxf(1.0, roundf(a) if absf(a - roundf(a)) < 0.001 else a)


## The largest exactly 16:9 rect in whole px inside `r`, centred.
static func fit_16_9(r: Rect2) -> Rect2:
	var n := floorf(minf(r.size.x / 16.0, r.size.y / 9.0))
	var size := Vector2(16.0 * n, 9.0 * n)
	return Rect2((r.position + (r.size - size) * 0.5).round(), size)


## The layout for a window of `window` px: GameHost's keys (k, game, terminal, font), the keys
## the rail's pieces read (rail, s, px, origin, log, blob, cells) and the cabinet's own
## (cabinet, art, frame, marquee, view, deck, chat, host, cap, mood, plate, modules, module_s).
static func layout_for(window: Vector2) -> Dictionary:
	var s := scale_for(window)
	var origin := ((window - DESIGN * s) * 0.5).round()
	# `px` is the rail pieces' own art pixel (2 design px, RailLayout); `art` the cabinet's.
	var out := {"rail": true, "cabinet": true, "s": s, "origin": origin, "px": RailLayout.art_px(s),
			"art": art_px(s)}
	out.frame = RailLayout.map(CABINET, s, origin)
	out.marquee = RailLayout.map(MARQUEE, s, origin)
	out.view = fit_16_9(RailLayout.map(VIEW, s, origin))
	out.deck = RailLayout.map(DECK, s, origin)
	out.chat = RailLayout.map(CHAT, s, origin)
	out.game = out.view
	out.k = out.game.size.y / 720.0
	out.host = RailLayout.map(HOST, s, origin)
	out.blob = RailLayout.map(BLOB, s, origin)
	out.cap = RailLayout.map(CAPTION, s, origin)
	out.mood = (origin + MOOD * s).round()
	out.plate = (out.view.position + PLATE * s).round()
	out.modules = RailLayout.map(MODULES, s, origin)
	out.module_s = s * MODULE_K
	# M48.6c: the terminal's rect is the chat's messages area (no pill showing); its font is
	# the chat's text size (the docked input draws at it).
	out.terminal = chat_parts(out.chat, out.art, 0).messages
	out.log = out.terminal
	out.font = text_px(2, s)
	# The path's slot only (no kills / hp / dash cell: RailModules skips a cell it is not given).
	# M48.6d: no hand / pack cell: the Arcade dock draws the hand and the package.
	var cells := {}
	var x := MODULES.position.x
	cells[&"path"] = RailLayout.map(Rect2(x, MODULES.position.y, PATH_W * MODULE_K, MODULES.size.y), s, origin)
	out.cells = cells
	return out


## M48.6c: the chat column's parts for the chat rect `chat` (window px) at `art` screen px per
## art px, with `pill_rows` rows of reply pills: {inner, header, log, messages, pills, input},
## stacked top to bottom inside the frame's ring, never overlapping, on whole px. With no pill
## the pills rect is empty and the messages take its room.
static func chat_parts(chat: Rect2, art: float, pill_rows: int) -> Dictionary:
	var a := art
	var inner := chat.grow(-roundf(CHAT_RING * a))
	var out := {"inner": inner}
	out.header = Rect2(inner.position, Vector2(inner.size.x, roundf(CHAT_HEAD * a)))
	out.log = Rect2(Vector2(inner.position.x, out.header.end.y), Vector2(inner.size.x, roundf(CHAT_LOG * a)))
	var input_h := roundf(CHAT_INPUT * a)
	var pad := roundf(CHAT_PAD * a)
	out.input = Rect2(Vector2(inner.position.x + pad, inner.end.y - pad - input_h), Vector2(inner.size.x - 2.0 * pad, input_h))
	var rows := maxi(0, pill_rows)
	var pills_h := 0.0
	if rows > 0:
		pills_h = roundf((rows * CHAT_PILL + (rows - 1) * CHAT_PILL_GAP + 1) * a)
	var pills_y: float = out.input.position.y - roundf(1.0 * a) - pills_h
	out.pills = Rect2(Vector2(inner.position.x + pad, pills_y), Vector2(inner.size.x - 2.0 * pad, pills_h))
	out.messages = Rect2(Vector2(inner.position.x, out.log.end.y), Vector2(inner.size.x, maxf(0.0, pills_y - out.log.end.y)))
	return out


## A text size on the pixel font's grid (its design pixel is 1/11 em): `n` screen px per font
## pixel at s = 1, a whole number of screen px at every scale, never under 1.
static func text_px(n: int, s: float) -> int:
	return 11 * maxi(1, roundi(n * s))
