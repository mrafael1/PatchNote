class_name ArtSkin
## (Not `Skin`: Godot has a built-in class of that name, the 3D skeleton skin.)
extends RefCounted
## One look's art, baked (PLAN 1.7, the quick Pixel preview): every grid of an art script
## (systems/skins/art/*.gd: PALETTE, SPRITES, TILES) turned into textures once, in code, at
## load time. No image file is read or written. Pure: no RNG, no clock, no scene access,
## so two bakes of one art script are byte-identical (`digest`).
##
## Bodies are drawn at BODY_SCALE (a node bigger or smaller than its id's NATIVE size gets
## the nearest whole multiple), tiles are pre-scaled to TILE_SCALE or their own "scale" key
## (one grid = one 48 px tile, so they tile with draw_texture_rect). Nearest filtering lives on each texture (a
## CanvasTexture), so the node that draws it keeps its own filter and the HUD stays smooth.

const LETTERS := ".KPSHAEW"
const BODY_SCALE := 2
const TILE_SCALE := 3
const IDLE_HZ := 5.0   ## a 2-frame idle flips 5 times a second (real time)
const UI_SCALE := 3    ## M48a: the UI panel's 9-slice is drawn at 3x, its margins 2 cells
const UI_MARGIN_CELLS := 2

## Today's flat-shape width of each id (world px): drawn at BODY_SCALE at this width.
const NATIVE := {
	&"player": 34.0, &"chaser": 30.0, &"tank": 44.0, &"bomber": 28.0, &"lancer": 30.0,
	&"shooter": 26.0, &"splitter": 30.0, &"splitter_mini": 15.0, &"hunter": 40.0,
	&"orbit_shard": 14.0, &"shot_line_player": 21.0, &"shot_ball_player": 22.0,
	&"shot_line_enemy": 21.0, &"shot_ball_enemy": 22.0,
}
const NATIVE_SHOT := 14.0

var name: StringName
var problems: Array[String] = []
var _images := {}     ## id -> Array[Image], 1 px per grid cell (tiles: pre-scaled)
var _tex := {}        ## id -> Array[CanvasTexture]
var _white := {}      ## id -> Array[CanvasTexture]: the same frames as a white silhouette
var _size := {}       ## id -> Vector2 (1 px per cell; tiles: pre-scaled)
var _palette := {}
var _tiles: Array[StringName] = []
var _wall_rim := {}   ## the art's WALL_RIM (outline, lit), {} without one
var _roles := {}      ## M48a: role -> Color, the art's ROLES (Palette.color reads it)
var _ramps := {}      ## M48a: id -> the ramp's main colour P (effects take a body's colour)
var _panels := {}     ## M48a: lit (bool) -> StyleBoxTexture, built on first use
var _particle: CanvasTexture   ## M48a: the neutral particle sprite, built on first use
var _morph_tex := {}  ## M48b: [id, kind] -> CanvasTexture (SkinMorph's mosaic and outline)


## Bakes every sprite and tile of an art script (its constants PALETTE, SPRITES, TILES).
static func bake(art: Script, p_name: StringName) -> ArtSkin:
	var s := ArtSkin.new()
	s.name = p_name
	var c := art.get_script_constant_map()
	s._palette = c.get("PALETTE", {})
	s._wall_rim = c.get("WALL_RIM", {})
	var roles: Dictionary = c.get("ROLES", {})
	for r: String in roles:
		if Color.html_is_valid(String(roles[r])):
			s._roles[StringName(r)] = Color.html(String(roles[r]))
		else:
			s.problems.append("role %s: bad colour %s" % [r, roles[r]])
	var sprites: Dictionary = c.get("SPRITES", {})
	var tiles: Dictionary = c.get("TILES", {})
	for id: String in sprites:
		s._bake_id(StringName(id), sprites[id], 1)
	for id: String in tiles:
		s._tiles.append(StringName(id))
		s._bake_id(StringName(id), tiles[id], int((tiles[id] as Dictionary).get("scale", TILE_SCALE)))
	return s


func has(id: StringName) -> bool:
	return _tex.has(id)


## M48a: this look's colour for a Palette role, or null (Palette then uses tier 0).
func role(r: StringName) -> Variant:
	return _roles.get(r)


func roles() -> Array[StringName]:
	var out: Array[StringName] = []
	for r: StringName in _roles:
		out.append(r)
	return out


## M48a: an id's main colour (its ramp's P), so a death puff or a pop matches the sprite;
## `fallback` for an id without one.
func main_color(id: StringName, fallback: Color) -> Color:
	return _ramps.get(id, fallback)


## M48a: the particle sprite (feedback.burst's texture), null without one. CPUParticles2D
## multiplies it by the burst's colour, so this is the `particle` grid made neutral (review):
## each pixel's luminance over its ramp P's, as grey (P white, S and K darker), and the hue is
## the burst's role colour alone (a cyan dash burst stays cyan). The art grid is unchanged.
func particle_texture() -> Texture2D:
	if _particle == null and has(&"particle"):
		_particle = _canvas(particle_image())
	return _particle


## The neutral particle image particle_texture() shows (null without a `particle` grid).
func particle_image() -> Image:
	return neutral(image(&"particle"), _ramps.get(&"particle", Color.WHITE)) if has(&"particle") else null


## `src` as grey: each pixel's luminance over `ref`'s (clamped to 1), alpha kept.
static func neutral(src: Image, ref: Color) -> Image:
	var img := src.duplicate() as Image
	var l0 := maxf(ref.get_luminance(), 0.001)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var v := clampf(c.get_luminance() / l0, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, c.a))
	return img


## M48a: the UI panel, a 9-slice of the `ui_panel` (or `ui_panel_lit`) grid pre-scaled to
## UI_SCALE so its margins draw 1:1 (crisp under any filter) and its plain centre tiles.
## Shared and cached: a caller that changes it (modulate) takes a duplicate().
func ui_panel(lit := false) -> StyleBoxTexture:
	if _panels.has(lit):
		return _panels[lit]
	var id := &"ui_panel_lit" if lit and has(&"ui_panel_lit") else &"ui_panel"
	var src := image(id)
	if src == null:
		return null
	var img := src.duplicate() as Image
	img.resize(img.get_width() * UI_SCALE, img.get_height() * UI_SCALE, Image.INTERPOLATE_NEAREST)
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(img)
	var m := float(UI_MARGIN_CELLS * UI_SCALE)
	box.texture_margin_left = m
	box.texture_margin_top = m
	box.texture_margin_right = m
	box.texture_margin_bottom = m
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.content_margin_left = m + 6.0
	box.content_margin_right = m + 6.0
	box.content_margin_top = m + 4.0
	box.content_margin_bottom = m + 4.0
	_panels[lit] = box
	return box


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _tex:
		out.append(id)
	return out


## The wall rim colours {"outline": Color, "lit": Color}; {} when the art has none.
func wall_rim() -> Dictionary:
	if not (_wall_rim.has("outline") and _wall_rim.has("lit")):
		return {}
	return {"outline": Color.html(String(_wall_rim["outline"])), "lit": Color.html(String(_wall_rim["lit"]))}


func is_tile(id: StringName) -> bool:
	return id in _tiles


func frame_count(id: StringName) -> int:
	return (_tex[id] as Array).size() if _tex.has(id) else 0


## The grid size of an id, 1 px per cell (a tile: already at TILE_SCALE).
func size_of(id: StringName) -> Vector2:
	return _size.get(id, Vector2.ZERO)


func image(id: StringName, frame := 0) -> Image:
	var fr: Array = _images.get(id, [])
	return fr[clampi(frame, 0, fr.size() - 1)] if fr.size() > 0 else null


func texture(id: StringName, frame := 0) -> Texture2D:
	var fr: Array = _tex.get(id, [])
	return fr[posmod(frame, fr.size())] if fr.size() > 0 else null


## The 2-frame idle at IDLE_HZ on a real-time clock (seconds); 0 for a 1-frame id.
func idle_frame(id: StringName, t: float) -> int:
	var n := frame_count(id)
	return 0 if n < 2 else posmod(int(floor(t * IDLE_HZ)), n)


## A one-shot animation (a blast, a pop): frame for progress u in 0..1.
func life_frame(id: StringName, u: float) -> int:
	var n := frame_count(id)
	return clampi(int(floor(clampf(u, 0.0, 0.999) * n)), 0, maxi(n - 1, 0))


## The draw scale for a node `width` px wide: BODY_SCALE at the id's NATIVE width, else
## the nearest whole multiple (at least 1), so pixels stay square.
func scale_for(id: StringName, width: float) -> float:
	var native: float = NATIVE.get(id, NATIVE_SHOT if String(id).begins_with("shot_") else 0.0)
	if native <= 0.0:
		return float(BODY_SCALE)
	return maxf(1.0, roundf(BODY_SCALE * width / native))


## Draws frame `frame` of `id` centred at `at`, `scale` screen px per cell.
func draw(ci: CanvasItem, id: StringName, at: Vector2, scale: float, frame := 0,
		tint := Color.WHITE) -> void:
	_draw_from(_tex, ci, id, at, scale, frame, tint)


## The frame's white silhouette (the hit flash, a telegraph's glow), alpha in tint.
func draw_silhouette(ci: CanvasItem, id: StringName, at: Vector2, scale: float, frame := 0,
		tint := Color.WHITE) -> void:
	_draw_from(_white, ci, id, at, scale, frame, tint)


## Tiles a pre-scaled tile over `rect` (from its top-left corner).
func draw_tile(ci: CanvasItem, id: StringName, rect: Rect2, tint := Color.WHITE) -> void:
	var t := texture(id)
	if t != null:
		ci.draw_texture_rect(t, rect, true, tint)


## M48b (SkinMorph): frame 0 of `id` as a mosaic of MOSAIC x MOSAIC cell blocks, each the
## mean colour of its opaque pixels (a block with none stays clear). Same size as the
## sprite. Derived on demand, not part of digest().
const MOSAIC := 4


func mosaic(id: StringName) -> Image:
	var src := image(id)
	if src == null:
		return null
	var img := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for by in range(0, src.get_height(), MOSAIC):
		for bx in range(0, src.get_width(), MOSAIC):
			var sum := Color(0, 0, 0, 0)
			var n := 0
			for y in range(by, mini(by + MOSAIC, src.get_height())):
				for x in range(bx, mini(bx + MOSAIC, src.get_width())):
					var c := src.get_pixel(x, y)
					if c.a > 0.0:
						sum += c
						n += 1
			if n == 0:
				continue
			var mean := Color(sum.r / n, sum.g / n, sum.b / n, 1.0)
			img.fill_rect(Rect2i(bx, by, mini(MOSAIC, src.get_width() - bx), mini(MOSAIC, src.get_height() - by)), mean)
	return img


## M48b (SkinMorph): frame 0's edge only, the opaque pixels next to a clear cell (or the
## grid's border), in the sprite's main colour (its ramp's P). Same size as the sprite.
func outline(id: StringName) -> Image:
	var src := image(id)
	if src == null:
		return null
	var ink: Color = _ramps.get(id, Color.WHITE)
	ink.a = 1.0
	var w := src.get_width()
	var h := src.get_height()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a <= 0.0:
				continue
			var edge := false
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var q := Vector2i(x, y) + d
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or src.get_pixelv(q).a <= 0.0:
					edge = true
					break
			if edge:
				img.set_pixel(x, y, ink)
	return img


## Draws SkinMorph's `kind` (&"mosaic" / &"outline") picture of `id` like draw() does.
func draw_morph(ci: CanvasItem, kind: StringName, id: StringName, at: Vector2, scale: float,
		tint := Color.WHITE) -> void:
	var key := "%s/%s" % [id, kind]
	if not _morph_tex.has(key):
		var img := mosaic(id) if kind == &"mosaic" else outline(id)
		_morph_tex[key] = _canvas(img) if img != null else null
	var tex: CanvasTexture = _morph_tex[key]
	if tex == null:
		return
	var sz: Vector2 = _size[id] * scale
	ci.draw_texture_rect(tex, Rect2(at - sz * 0.5, sz), false, tint)


## A stable hash of every baked image (two bakes of one art script must match).
func digest() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	# M48b: sorted as Strings. A StringName sort follows interning order (pointers), so the
	# M48a digest moved whenever other code named an id first; the images did not.
	var keys := _images.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id: StringName in keys:
		ctx.update(String(id).to_utf8_buffer())
		for img: Image in _images[id]:
			ctx.update(var_to_bytes(img.get_size()))
			ctx.update(img.get_data())
	var rk := _roles.keys()
	rk.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for r: StringName in rk:   # M48a: the roles are part of the look
		ctx.update(("%s=%s" % [r, (_roles[r] as Color).to_html()]).to_utf8_buffer())
	return ctx.finish().hex_encode()


# --- baking --------------------------------------------------------------------------

func _draw_from(table: Dictionary, ci: CanvasItem, id: StringName, at: Vector2, scale: float,
		frame: int, tint: Color) -> void:
	var fr: Array = table.get(id, [])
	if fr.is_empty():
		return
	var sz: Vector2 = _size[id] * scale
	ci.draw_texture_rect(fr[posmod(frame, fr.size())], Rect2(at - sz * 0.5, sz), false, tint)


func _bake_id(id: StringName, entry: Dictionary, pre_scale: int) -> void:
	var ramp: Dictionary = entry.get("ramp", {})
	if ramp.has("P") and Color.html_is_valid(String(ramp["P"])):
		_ramps[id] = Color.html(String(ramp["P"]))
	var images: Array[Image] = []
	for g in _grids_of(entry):
		var img := _grid_image(id, g, ramp)
		if img == null:
			continue
		if images.size() > 0 and img.get_size() != images[0].get_size():
			problems.append("%s: frame size %s != %s" % [id, img.get_size(), images[0].get_size()])
			continue
		if pre_scale != 1:
			img.resize(img.get_width() * pre_scale, img.get_height() * pre_scale, Image.INTERPOLATE_NEAREST)
		images.append(img)
	if images.is_empty():
		return
	var tex: Array[CanvasTexture] = []
	var white: Array[CanvasTexture] = []
	for img in images:
		tex.append(_canvas(img))
		white.append(_canvas(_silhouette(img)))
	_images[id] = images
	_tex[id] = tex
	_white[id] = white
	_size[id] = Vector2(images[0].get_size())


static func _grids_of(entry: Dictionary) -> Array:
	var out: Array = [entry.get("grid", [])]
	if entry.has("frames"):
		var f: Variant = entry["frames"]
		if f is Array and (f as Array).size() > 0 and f[0] is String:
			out.append(f)   # one extra frame, written as a plain grid
		elif f is Array:
			for g in f:
				out.append(g)
	return out


func _grid_image(id: StringName, grid: Variant, ramp: Dictionary) -> Image:
	var rows := PackedStringArray(grid)
	if rows.is_empty():
		problems.append("%s: empty grid" % id)
		return null
	var w := rows[0].length()
	var img := Image.create(w, rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		if rows[y].length() != w:
			problems.append("%s: row %d is %d wide, not %d" % [id, y, rows[y].length(), w])
			return null
		for x in w:
			var ch := rows[y][x]
			if ch == ".":
				continue
			if not LETTERS.contains(ch):
				problems.append("%s: unknown letter %s" % [id, ch])
				continue
			img.set_pixel(x, y, _letter_color(id, ch, ramp))
	return img


func _letter_color(id: StringName, ch: String, ramp: Dictionary) -> Color:
	var key := ch
	match ch:
		"K": key = "outline"
		"E": key = "eye"
		"W": key = "white"
	var v: Variant = ramp.get(ch) if ramp.has(ch) and key == ch else _palette.get(key)
	if v == null or not Color.html_is_valid(String(v)):
		problems.append("%s: no colour for %s" % [id, ch])
		return Color.MAGENTA
	return Color.html(String(v))


static func _silhouette(src: Image) -> Image:
	var img := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in src.get_height():
		for x in src.get_width():
			if src.get_pixel(x, y).a > 0.0:
				img.set_pixel(x, y, Color.WHITE)
	return img


static func _canvas(img: Image) -> CanvasTexture:
	var ct := CanvasTexture.new()
	ct.diffuse_texture = ImageTexture.create_from_image(img)
	ct.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ct.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	return ct
