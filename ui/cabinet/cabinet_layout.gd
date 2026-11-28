class_name CabinetLayout
extends RefCounted
## M48.6a: the cabinet's layout (PLAN 0.9.2, the Pixel look's UI; it takes RailLayout's
## place). Pure: a window size in, rects out. The design canvas is 1600x900, as the rail's;
## one art pixel is 3 design px. The fit scale s = min(W / 1600, H / 900) snaps down so one
## art pixel is a whole number of screen px (1920x1080 keeps 3, 2560x1440 takes 4); spare
## margins are the backdrop's checker. The game view is 1152x648 design px (16:9, 384x216 art
## px), so the 1280x720 sim stretches evenly at every scale.
##
## M48.6a keeps the rail's pieces alive inside it (they are restyled in M48.6b-f): the HUD
## modules dock in the deck at MODULE_K of their rail size, the AI's body sits in the deck's
## camera box, the chat log and the reply box share the chat column.

const DESIGN := Vector2(1600, 900)
const BASE := Vector2i(1600, 900)    ## the windowed size while the cabinet shows
const ART := 3.0                     ## design px per art px

## The plan's table (design px).
const CABINET := Rect2(12, 12, 1196, 876)
const MARQUEE := Rect2(34, 24, 1152, 42)
const VIEW := Rect2(34, 78, 1152, 648)
const DECK := Rect2(34, 748, 1152, 128)
const CHAT := Rect2(1218, 12, 370, 876)

## The deck: the camera box at its left (the mockup's 44x36 art px), the body inside it, the
## rail's modules after it.
const HOST := Rect2(46, 758, 132, 108)
const BLOB := Rect2(70, 761, 84, 84)
const MODULES := Rect2(190, 757, 984, 110)
const MODULE_K := MODULES.size.y / RailLayout.ROW_H   ## the modules' size against the rail's
## The chat column: the rail's log over its reply box.
const REPLY_H := 214.0
const LOG := Rect2(1218, 12, 370, 876 - REPLY_H - 6)
const REPLY := Rect2(1218, 888 - REPLY_H, 370, REPLY_H)
const LOG_BOTTOM_PAD := 10.0          ## no body sits on the log here


## The scale for a window: the fit, snapped down to a whole number of screen px per art px
## (when the window holds at least one).
static func scale_for(window: Vector2) -> float:
	var fit := maxf(0.05, minf(window.x / DESIGN.x, window.y / DESIGN.y))
	var px := floorf(ART * fit + 0.0001)
	return px / ART if px >= 1.0 else fit


## One art pixel in screen px at scale s: 3 at s = 1, never under 1.
static func art_px(s: float) -> float:
	return maxf(1.0, roundf(ART * s))


## The layout for a window of `window` px: GameHost's keys (k, game, terminal, font), the keys
## the rail's pieces read (rail, s, px, origin, log, reply, blob, cells, spine_x) and the
## cabinet's own (cabinet, art, frame, marquee, view, deck, chat, host, modules, module_s).
static func layout_for(window: Vector2) -> Dictionary:
	var s := scale_for(window)
	var origin := ((window - DESIGN * s) * 0.5).round()
	# `px` is the rail pieces' own art pixel (2 design px, RailLayout); `art` the cabinet's.
	var out := {"rail": true, "cabinet": true, "s": s, "origin": origin, "px": RailLayout.art_px(s),
			"art": art_px(s)}
	out.frame = RailLayout.map(CABINET, s, origin)
	out.marquee = RailLayout.map(MARQUEE, s, origin)
	out.view = RailLayout.map(VIEW, s, origin)
	out.deck = RailLayout.map(DECK, s, origin)
	out.chat = RailLayout.map(CHAT, s, origin)
	out.game = out.view
	out.k = out.game.size.y / 720.0
	out.host = RailLayout.map(HOST, s, origin)
	out.blob = RailLayout.map(BLOB, s, origin)
	out.modules = RailLayout.map(MODULES, s, origin)
	out.module_s = s * MODULE_K
	out.terminal = RailLayout.map(LOG, s, origin)
	out.log = out.terminal
	out.reply = RailLayout.map(REPLY, s, origin)
	out.font = RailLayout.font_px(s)
	out.log_bottom_pad = LOG_BOTTOM_PAD
	var cells := {}
	var x := MODULES.position.x
	var gap := RailLayout.GAP * MODULE_K
	for pair: Array in RailLayout.CELLS:
		var w: float = float(pair[1]) * MODULE_K
		cells[pair[0]] = RailLayout.map(Rect2(x, MODULES.position.y, w, MODULES.size.y), s, origin)
		x += w + gap
	var path_x := MODULES.position.x + (124.0 + 172.0 + 220.0) * MODULE_K + gap * 3.0
	var hand_w := RailLayout.HAND_W * MODULE_K
	cells[&"hand"] = RailLayout.map(Rect2(path_x, MODULES.position.y, hand_w, MODULES.size.y), s, origin)
	cells[&"pack"] = RailLayout.map(Rect2(path_x + hand_w + gap, MODULES.position.y,
			(568.0 - RailLayout.HAND_W) * MODULE_K - gap, MODULES.size.y), s, origin)
	out.cells = cells
	out.spine_x = roundf(origin.x + (LOG.position.x + RailLayout.SPINE_X) * s)
	return out


## A text size on the pixel font's grid (its design pixel is 1/11 em): `n` screen px per font
## pixel at s = 1, a whole number of screen px at every scale, never under 1.
static func text_px(n: int, s: float) -> int:
	return 11 * maxi(1, roundi(n * s))
