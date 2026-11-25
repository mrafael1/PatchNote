class_name WeaponGlyph
extends RefCounted
## A weapon's small drawn picture (M47.2, owner G14a: "real cards"), from its WeaponDef.icon
## shape key, in plain shapes. Shared: Arsenal's hand, weapon pickups (with a look), and
## later the pick panel and M51's HUD styles. Keys only, never weapon ids (the mutation lint).
## M48a: with a look on, the picture is the look's player shot sprite for that key
## (`shot_<key>_player`), so the card, the pickup and the shot itself show one picture.

const KEYS: Array[StringName] = [&"dot", &"fan", &"line", &"ball", &"ring", &"burst", &"hole"]

static var skin_draws := 0   ## pictures drawn from a look's sprite (tests)


## Draws `icon` centred at `centre` in a box of `size` on `ci`.
static func draw(ci: CanvasItem, icon: StringName, centre: Vector2, size: float, color: Color) -> void:
	if _draw_skin(ci, icon, centre, size, color):
		return
	var r := size * 0.5
	var w := maxf(1.5, size * 0.07)
	match icon:
		&"dot":   # a round leaving a barrel stub
			ci.draw_rect(Rect2(centre + Vector2(-r * 0.9, -r * 0.18), Vector2(r * 0.8, r * 0.36)), color)
			ci.draw_circle(centre + Vector2(r * 0.35, 0), r * 0.32, color)
		&"fan":   # five short rays
			for i in 5:
				var a := deg_to_rad(-28.0 + 14.0 * i)
				var d := Vector2.RIGHT.rotated(a)
				ci.draw_line(centre + Vector2(-r * 0.8, 0) + d * r * 0.4, centre + Vector2(-r * 0.8, 0) + d * r * 1.6, color, w, true)
		&"line":   # a long beam with a bright core
			ci.draw_line(centre - Vector2(r, 0), centre + Vector2(r, 0), Color(color, 0.45), w * 3.0, true)
			ci.draw_line(centre - Vector2(r, 0), centre + Vector2(r, 0), Color.WHITE.lerp(color, 0.3), w, true)
		&"ball":   # a ball with six blast ticks
			ci.draw_circle(centre, r * 0.42, color)
			for i in 6:
				var d := Vector2.RIGHT.rotated(TAU * i / 6.0)
				ci.draw_line(centre + d * r * 0.6, centre + d * r * 0.95, color, w, true)
		&"ring":   # a ring with two orbiting dots
			ci.draw_arc(centre, r * 0.7, 0.0, TAU, 24, color, w, true)
			ci.draw_circle(centre + Vector2(r * 0.7, 0), r * 0.2, color)
			ci.draw_circle(centre - Vector2(r * 0.7, 0), r * 0.2, color)
		&"burst":   # an eight-ray star
			for i in 8:
				var d := Vector2.RIGHT.rotated(TAU * i / 8.0)
				ci.draw_line(centre + d * r * 0.2, centre + d * r * (0.95 if i % 2 == 0 else 0.6), color, w, true)
		&"hole":   # concentric arcs
			for i in 3:
				ci.draw_arc(centre, r * (0.3 + 0.3 * i), 0.4 * i, 0.4 * i + TAU * 0.75, 18, color, w, true)
			ci.draw_circle(centre, r * 0.12, color)
		_:
			ci.draw_rect(Rect2(centre - Vector2(r, r) * 0.6, Vector2(r, r) * 1.2), color, false, w)
			ci.draw_string(ThemeDB.fallback_font, centre + Vector2(-r * 0.25, r * 0.3), "?",
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(size * 0.5), color)


## The look's sprite for `icon` at the largest whole scale that fits `size` (pixels stay
## square), dimmed with the card's ink (its brightness) and faded with its alpha.
static func _draw_skin(ci: CanvasItem, icon: StringName, centre: Vector2, size: float, color: Color) -> bool:
	var id := StringName("shot_%s_player" % icon)
	var skin := Skins.on(id)   # M48b: once revealed
	if skin == null or not skin.has(id):
		return false
	var cells := skin.size_of(id)
	var s := maxf(1.0, floorf(size / maxf(cells.x, cells.y)))
	var v := maxf(color.r, maxf(color.g, color.b))
	skin.draw(ci, id, centre.round(), s, 0, Color(v, v, v, color.a))
	skin_draws += 1
	return true
