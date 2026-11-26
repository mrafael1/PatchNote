class_name WeaponGlyph
extends RefCounted
## A weapon's small drawn picture (M47.2, owner G14a: "real cards"), from its WeaponDef.icon
## shape key, in plain shapes. Shared: Arsenal's hand, weapon pickups (with a look), and
## later the pick panel and M51's HUD styles. Keys only, never weapon ids (the mutation lint).
## M48a: with a look on, the picture is the look's player shot sprite for that key
## (`shot_<key>_player`), so the card, the pickup and the shot itself show one picture.

const KEYS: Array[StringName] = [&"dot", &"fan", &"line", &"ball", &"ring", &"burst", &"hole",
		&"prism", &"misfuse", &"cylinder", &"minigun", &"bomb", &"cluster"]   ## M50.1b: Prism, the misfuse (each has a pixel shot; `link` draws too); M47.6d1: the revolver; M50.4c1: Minigun; M50.3a: the launcher's bomb, Cluster

## M50.4b (Auto depth design 7): the passive items' and the two fillers' keys. With a look on
## they draw the M50.4m sheet's grids (CardArt), else plain shapes below.
const ITEM_KEYS: Array[StringName] = [&"haste", &"area", &"might", &"duration", &"amount", &"speed",
		&"attract", &"hp", &"boost"]

static var skin_draws := 0   ## pictures drawn from a look's sprite (tests)


## Draws `icon` centred at `centre` in a box of `size` on `ci`.
static func draw(ci: CanvasItem, icon: StringName, centre: Vector2, size: float, color: Color) -> void:
	if icon in ITEM_KEYS and Skins.current != null and CardArt.draw(ci, icon, centre, size):
		skin_draws += 1
		return
	if _draw_skin(ci, icon, centre, size, color):
		return
	var r := size * 0.5
	var w := maxf(1.5, size * 0.07)
	match icon:
		&"haste":   # M50.4b: a lightning bolt
			ci.draw_polyline(PackedVector2Array([centre + Vector2(r * 0.35, -r * 0.9), centre + Vector2(-r * 0.3, 0),
					centre + Vector2(r * 0.3, 0), centre + Vector2(-r * 0.35, r * 0.9)]), color, w * 1.6, true)
		&"area":   # a ring around a dot
			ci.draw_arc(centre, r * 0.8, 0.0, TAU, 28, color, w * 1.4, true)
			ci.draw_circle(centre, r * 0.28, color)
		&"might":   # an up arrow
			ci.draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -r * 0.95), centre + Vector2(r * 0.8, -r * 0.1),
					centre + Vector2(-r * 0.8, -r * 0.1)]), color)
			ci.draw_rect(Rect2(centre + Vector2(-r * 0.3, -r * 0.15), Vector2(r * 0.6, r * 1.05)), color)
		&"duration":   # an hourglass
			ci.draw_colored_polygon(PackedVector2Array([centre + Vector2(-r * 0.7, -r * 0.9), centre + Vector2(r * 0.7, -r * 0.9),
					centre]), color)
			ci.draw_colored_polygon(PackedVector2Array([centre, centre + Vector2(r * 0.7, r * 0.9),
					centre + Vector2(-r * 0.7, r * 0.9)]), Color(color, 0.6))
		&"amount":   # three dots
			for i in 3:
				ci.draw_circle(centre + Vector2(r * (-0.65 + 0.65 * i), 0), r * 0.24, color)
		&"speed":   # a double chevron
			for k in 2:
				var x := -r * 0.55 + r * 0.6 * k
				ci.draw_polyline(PackedVector2Array([centre + Vector2(x, -r * 0.6), centre + Vector2(x + r * 0.45, 0),
						centre + Vector2(x, r * 0.6)]), color, w * 1.4, true)
		&"attract":   # a horseshoe
			ci.draw_arc(centre + Vector2(0, r * 0.1), r * 0.6, 0.0, PI, 16, color, w * 2.0, true)
			ci.draw_line(centre + Vector2(-r * 0.6, r * 0.1), centre + Vector2(-r * 0.6, -r * 0.8), color, w * 2.0, true)
			ci.draw_line(centre + Vector2(r * 0.6, r * 0.1), centre + Vector2(r * 0.6, -r * 0.8), color, w * 2.0, true)
		&"hp":   # a heart
			ci.draw_circle(centre + Vector2(-r * 0.32, -r * 0.2), r * 0.38, color)
			ci.draw_circle(centre + Vector2(r * 0.32, -r * 0.2), r * 0.38, color)
			ci.draw_colored_polygon(PackedVector2Array([centre + Vector2(-r * 0.68, -r * 0.05), centre + Vector2(r * 0.68, -r * 0.05),
					centre + Vector2(0, r * 0.8)]), color)
		&"boost":   # a plus
			ci.draw_rect(Rect2(centre + Vector2(-r * 0.2, -r * 0.75), Vector2(r * 0.4, r * 1.5)), color)
			ci.draw_rect(Rect2(centre + Vector2(-r * 0.75, -r * 0.2), Vector2(r * 1.5, r * 0.4)), color)
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
		&"prism":   # M50.1b: a fan of three thin beams out of one point
			for i in 3:
				var d := Vector2.RIGHT.rotated(deg_to_rad(-18.0 + 18.0 * i))
				ci.draw_line(centre + Vector2(-r * 0.8, 0), centre + Vector2(-r * 0.8, 0) + d * r * 1.7,
						Color(color, 0.5 + 0.25 * i), w, true)
		&"misfuse":   # M50.1b: a pistol, a second one crossed over it
			for k in 2:
				var c2 := centre + Vector2(-r * 0.15 + r * 0.3 * k, -r * 0.1 + r * 0.2 * k)
				ci.draw_rect(Rect2(c2 + Vector2(-r * 0.6, -r * 0.2), Vector2(r * 1.2, r * 0.3)), Color(color, 0.6 + 0.4 * k))
				ci.draw_rect(Rect2(c2 + Vector2(-r * 0.6, -r * 0.2), Vector2(r * 0.3, r * 0.7)), Color(color, 0.6 + 0.4 * k))
		&"cylinder":   # M47.6d1: the revolver: a cylinder of six chambers, a heavy round out of it
			ci.draw_circle(centre + Vector2(-r * 0.35, 0), r * 0.5, color)
			for i in 6:
				var d := Vector2.RIGHT.rotated(TAU * i / 6.0)
				ci.draw_circle(centre + Vector2(-r * 0.35, 0) + d * r * 0.28, r * 0.09, Palette.OUTLINE)
			ci.draw_circle(centre + Vector2(r * 0.6, 0), r * 0.26, color)
		&"minigun":   # M50.4c1: a drum and a bundle of three barrels
			ci.draw_rect(Rect2(centre + Vector2(-r * 0.9, -r * 0.45), Vector2(r * 0.6, r * 0.9)), color)
			for k in 3:
				ci.draw_rect(Rect2(centre + Vector2(-r * 0.3, -r * 0.42 + r * 0.3 * k), Vector2(r * 1.25, r * 0.2)),
						Color(color, 1.0 - 0.2 * k))
			ci.draw_rect(Rect2(centre + Vector2(r * 0.05, -r * 0.5), Vector2(r * 0.14, r * 1.0)), color)
		&"supernova":   # M50.4c2: an eight-ray star inside its shockwave ring
			ci.draw_arc(centre, r * 0.92, 0.0, TAU, 28, Color(color, 0.7), w, true)
			for i in 8:
				var d := Vector2.RIGHT.rotated(TAU * i / 8.0)
				ci.draw_line(centre + d * r * 0.15, centre + d * r * (0.7 if i % 2 == 0 else 0.45), color, w * 1.3, true)
			ci.draw_circle(centre, r * 0.2, color)
		&"thunderclap":   # M50.4c2: a short fan and the clap's blast ahead of it
			for i in 3:
				var d := Vector2.RIGHT.rotated(deg_to_rad(-17.0 + 17.0 * i))
				ci.draw_line(centre + Vector2(-r * 0.9, 0), centre + Vector2(-r * 0.9, 0) + d * r * 0.8, color, w, true)
			ci.draw_arc(centre + Vector2(r * 0.45, 0), r * 0.45, 0.0, TAU, 20, color, w * 1.3, true)
			ci.draw_circle(centre + Vector2(r * 0.45, 0), r * 0.16, color)
		&"bomb":   # M50.3a: the launcher: a squat bomb with a fuse
			ci.draw_rect(Rect2(centre + Vector2(-r * 0.3, -r * 0.45), Vector2(r * 0.95, r * 0.9)), color)
			ci.draw_line(centre + Vector2(-r * 0.3, -r * 0.35), centre + Vector2(-r * 0.8, -r * 0.8), color, w, true)
			ci.draw_circle(centre + Vector2(-r * 0.85, -r * 0.85), r * 0.14, color)
		&"cluster":   # M50.3a: Cluster: a shell ringed by five bomblets
			ci.draw_circle(centre, r * 0.36, color)
			for i in 5:
				ci.draw_circle(centre + Vector2.UP.rotated(TAU * i / 5.0) * r * 0.75, r * 0.15, color)
		&"link":   # M50.1b: two rings chained
			ci.draw_arc(centre - Vector2(r * 0.3, 0), r * 0.42, 0.0, TAU, 18, color, w, true)
			ci.draw_arc(centre + Vector2(r * 0.3, 0), r * 0.42, 0.0, TAU, 18, color, w, true)
		&"hole":   # concentric arcs
			for i in 3:
				ci.draw_arc(centre, r * (0.3 + 0.3 * i), 0.4 * i, 0.4 * i + TAU * 0.75, 18, color, w, true)
			ci.draw_circle(centre, r * 0.12, color)
		_:
			ci.draw_rect(Rect2(centre - Vector2(r, r) * 0.6, Vector2(r, r) * 1.2), color, false, w)
			ci.draw_string(ThemeDB.fallback_font, centre + Vector2(-r * 0.25, r * 0.3), "?",
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(size * 0.5), color)


## M50.4b review: a level-up card's or the Auto rail slot's picture. With a look on, a weapon
## with a gun in CardArt draws that gun (the shot sprites of the Pistol and the Shotgun are
## the same pellet); everything else draws as draw().
static func draw_card(ci: CanvasItem, icon: StringName, centre: Vector2, size: float, color: Color) -> void:
	if Skins.current != null and CardArt.draw_gun(ci, icon, centre, size):
		skin_draws += 1
		return
	draw(ci, icon, centre, size, color)


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


## M50.4f (the sheet's flat half): the flat cards' guns, in rounded blocks and polygons after the
## mockup's flat SVGs (Palette roles only: a grey body, a pink core, a gold muzzle, an orange grip).
const FLAT_GUNS: Array[StringName] = [&"dot", &"fan", &"line", &"bomb", &"minigun"]   # M50.5: the launcher is `bomb` (M50.3a)


## A flat card's picture: the flat gun of `icon` (FLAT_GUNS), the filled Haste bolt, else draw().
static func draw_card_flat(ci: CanvasItem, icon: StringName, centre: Vector2, size: float, color: Color) -> void:
	if icon in FLAT_GUNS:
		draw_gun_flat(ci, icon, centre, size)
		return
	if icon == &"haste":
		var u := size / 32.0
		var bolt := PackedVector2Array()
		for p: Vector2 in [Vector2(4, -13), Vector2(-7, 2), Vector2(0, 2), Vector2(-4, 13), Vector2(8, -3), Vector2(1, -3)]:
			bolt.append(centre + p * u + Vector2(3, 0) * u)
		ci.draw_colored_polygon(bolt, Palette.color(&"card_evolve"))
		for k in 3:   # the speed dashes
			var y := -5.0 + 5.0 * k
			ci.draw_line(centre + Vector2(-13 + 2 * (k % 2), y) * u, centre + Vector2(-4 - k, y) * u, color, maxf(2.0, 2.2 * u), true)
		return
	draw(ci, icon, centre, size, color)


static func draw_gun_flat(ci: CanvasItem, icon: StringName, centre: Vector2, size: float) -> void:
	var u := size / 34.0
	var body := Palette.color(&"dust")
	var dark := Palette.color(&"wall")
	var core := Palette.color(&"hit")
	var gold := Palette.color(&"card_evolve")
	var grip := Palette.color(&"card_item")
	match icon:
		&"line":   # the laser: a rear block, the body with its pink core, the barrel, a gold muzzle
			_poly(ci, centre, u, [Vector2(-9, 5), Vector2(-4, 5), Vector2(-5, 12), Vector2(-10, 12)], grip)
			_rr(ci, centre, u, Rect2(-16, -3, 6, 7), dark, 1.5)
			_rr(ci, centre, u, Rect2(-7, -8, 8, 3), dark, 1.0)
			_rr(ci, centre, u, Rect2(-11, -5, 15, 10), body, 3.0)
			_rr(ci, centre, u, Rect2(-8, -1.5, 8, 3), core, 1.5)
			_rr(ci, centre, u, Rect2(4, -2.5, 8, 5), dark.lerp(body, 0.5), 1.0)
			_rr(ci, centre, u, Rect2(12, -4.5, 3, 9), gold, 1.0)
			_rr(ci, centre, u, Rect2(15, -1, 3, 2), core, 0.5)
		&"dot":   # the pistol: a slide, a gold sight, an orange grip
			_poly(ci, centre, u, [Vector2(-8, 1), Vector2(-2, 1), Vector2(-4, 11), Vector2(-10, 11)], grip)
			_rr(ci, centre, u, Rect2(-11, -5, 22, 7), body, 2.0)
			_rr(ci, centre, u, Rect2(-11, 0, 22, 2), dark, 1.0)
			_rr(ci, centre, u, Rect2(11, -4, 2, 3), gold, 0.5)
			_rr(ci, centre, u, Rect2(-1, 2, 4, 3), dark, 1.0)
		&"fan":   # the shotgun: an orange stock, a dark receiver, a long barrel and its pump
			_poly(ci, centre, u, [Vector2(-17, -1), Vector2(-9, -3), Vector2(-9, 3), Vector2(-17, 5)], grip)
			_rr(ci, centre, u, Rect2(-10, -3, 10, 6), dark, 1.0)
			_rr(ci, centre, u, Rect2(0, -3, 17, 2.5), body, 1.0)
			_rr(ci, centre, u, Rect2(0, 0, 13, 2), dark, 1.0)
			_rr(ci, centre, u, Rect2(3, -0.5, 6, 3), grip, 1.0)
		&"bomb":   # the launcher: an orange tube with a gold nose (M50.5: its icon is `bomb` since M50.3a)
			_rr(ci, centre, u, Rect2(-17, -5, 3, 10), dark, 1.0)
			_rr(ci, centre, u, Rect2(-5, -8, 3, 3), dark, 0.5)
			_rr(ci, centre, u, Rect2(-6, 4, 3, 7), dark, 1.0)
			_rr(ci, centre, u, Rect2(-14, -5, 24, 9), grip, 3.0)
			_rr(ci, centre, u, Rect2(-8, -5, 2, 9), gold, 0.5)
			_poly(ci, centre, u, [Vector2(10, -5), Vector2(17, -0.5), Vector2(10, 4)], gold)
		&"minigun":   # an orange drum, three grey barrels, two gold bands
			_rr(ci, centre, u, Rect2(-16, -8, 11, 15), grip, 3.0)
			_rr(ci, centre, u, Rect2(-14, -3, 7, 1.5), grip.darkened(0.3), 0.5)
			_rr(ci, centre, u, Rect2(-14, 1, 7, 1.5), grip.darkened(0.3), 0.5)
			for k in 3:
				_rr(ci, centre, u, Rect2(-5, -6 + 4 * k, 19, 3), body if k != 1 else dark.lerp(body, 0.6), 1.5)
			_rr(ci, centre, u, Rect2(-2, -7, 2.5, 13), gold, 0.5)
			_rr(ci, centre, u, Rect2(7, -7, 2.5, 13), gold, 0.5)
			_poly(ci, centre, u, [Vector2(15, -3), Vector2(18, -0.5), Vector2(15, 2)], gold)


static func _rr(ci: CanvasItem, centre: Vector2, u: float, r: Rect2, color: Color, radius: float) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(maxi(0, roundi(radius * u)))
	box.anti_aliasing = true
	ci.draw_style_box(box, Rect2(centre + r.position * u, r.size * u))


static func _poly(ci: CanvasItem, centre: Vector2, u: float, pts: Array, color: Color) -> void:
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		out.append(centre + p * u)
	ci.draw_colored_polygon(out, color)
