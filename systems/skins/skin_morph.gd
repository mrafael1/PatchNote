class_name SkinMorph
extends RefCounted
## M48b (PLAN 1.7.1): how a revealed id turns from today's placeholder into its sprite,
## drawn by the node that wears it (visual only; the clock is Skins' per-id morph state on
## RunState.real_time()). Four equal steps over the morph: the placeholder rect, a 4x4
## mosaic of the sprite's colours, the outline only, then the full sprite with a small
## sparkle that fades out. Four steps in 1 s change the picture 3 times (<= 3 flashes/s).
## Reduce flashing: each step crossfades into the next, no sparkle.

const STEPS := 4
const PLACEHOLDER := 0
const MOSAIC := 1
const OUTLINE := 2
const SPRITE := 3


## The step (0..3) at progress u (0..1).
static func step(u: float) -> int:
	return clampi(int(floor(clampf(u, 0.0, 0.9999) * STEPS)), 0, STEPS - 1)


## How far into its step u is (0..1): reduce flashing's crossfade weight toward the next.
static func blend(u: float) -> float:
	var x := clampf(u, 0.0, 0.9999) * STEPS
	return x - floor(x)


## The sparkle's alpha at u (the last step, fading from 1 to 0); 0 under reduce flashing.
static func sparkle(u: float, reduce: bool) -> float:
	if reduce or step(u) != SPRITE:
		return 0.0
	return 1.0 - blend(u)


## Draws `id` at progress u on `ci`, centred at `at`: `fill` and `rect_size` are the
## placeholder (today's rect), `scale` and `frame` the sprite's. A white `tint.a` fades
## everything (a fading node).
static func draw(ci: CanvasItem, skin: ArtSkin, id: StringName, at: Vector2, scale: float,
		frame: int, u: float, fill: Color, rect_size: Vector2, reduce: bool, alpha := 1.0) -> void:
	var k := step(u)
	if not reduce:
		_draw_step(ci, skin, id, at, scale, frame, k, fill, rect_size, alpha)
		var a := sparkle(u, false)
		if a > 0.0:
			_draw_sparkle(ci, skin, id, at, scale, a * alpha)
		return
	for layer: Array in layers(u):
		_draw_step(ci, skin, id, at, scale, frame, int(layer[0]), fill, rect_size, alpha * float(layer[1]))


## Reduce flashing's layers at u, bottom first: [step, alpha]. No step is drawn twice (M48b
## review: two partial layers of one step composite below full and the sprite pulsed). The
## outgoing step stays opaque where the incoming one covers it (the outline under the
## sprite); it fades out only where the shapes differ (placeholder -> mosaic -> outline).
## The last step is the sprite alone, at full.
static func layers(u: float) -> Array:
	var k := step(u)
	if k + 1 >= STEPS:
		return [[k, 1.0]]
	var b := blend(u)
	var out_a := 1.0 if k + 1 == SPRITE else 1.0 - b
	return [[k, out_a], [k + 1, b]]


static func _draw_step(ci: CanvasItem, skin: ArtSkin, id: StringName, at: Vector2, scale: float,
		frame: int, k: int, fill: Color, rect_size: Vector2, alpha: float) -> void:
	if alpha <= 0.0:
		return
	match k:
		PLACEHOLDER:
			ci.draw_rect(Rect2(at - rect_size * 0.5, rect_size), Color(fill, fill.a * alpha))
		MOSAIC:
			skin.draw_morph(ci, &"mosaic", id, at, scale, Color(1, 1, 1, alpha))
		OUTLINE:
			skin.draw_morph(ci, &"outline", id, at, scale, Color(1, 1, 1, alpha))
		_:
			skin.draw(ci, id, at, scale, frame, Color(1, 1, 1, alpha))


## A small 4-point star at the sprite's top-right corner (white, fading).
static func _draw_sparkle(ci: CanvasItem, skin: ArtSkin, id: StringName, at: Vector2, scale: float,
		alpha: float) -> void:
	var half := skin.size_of(id) * scale * 0.5
	var c := at + Vector2(half.x, -half.y) * 0.8
	var arm := maxf(3.0, scale * 3.0)
	var w := maxf(1.0, scale)
	var white := Color(1, 1, 1, alpha)
	ci.draw_rect(Rect2(c.x - arm, c.y - w * 0.5, arm * 2.0, w), white)
	ci.draw_rect(Rect2(c.x - w * 0.5, c.y - arm, w, arm * 2.0), white)
	ci.draw_rect(Rect2(c.x - w, c.y - w, w * 2.0, w * 2.0), white)
