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


## Bakes every sprite and tile of an art script (its constants PALETTE, SPRITES, TILES).
static func bake(art: Script, p_name: StringName) -> ArtSkin:
	var s := ArtSkin.new()
	s.name = p_name
	var c := art.get_script_constant_map()
	s._palette = c.get("PALETTE", {})
	s._wall_rim = c.get("WALL_RIM", {})
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


## A stable hash of every baked image (two bakes of one art script must match).
func digest() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var keys := _images.keys()
	keys.sort()
	for id: StringName in keys:
		ctx.update(String(id).to_utf8_buffer())
		for img: Image in _images[id]:
			ctx.update(var_to_bytes(img.get_size()))
			ctx.update(img.get_data())
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
