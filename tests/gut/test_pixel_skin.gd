extends GutTest
## The Pixel look (PLAN 1.7, the preview then M48a): the art bakes the same twice, every id
## of .check/pixel_art/ids.md resolves, each body finds its sprite from the node that owns
## it, and turning the look off restores the null path (Skins.current == null). M48a adds
## Palette (every role resolves; tier 0 is today's colours; no hard-coded colour left), the
## 3 lints, the no-image-files check, the UI panel, the mascot's pixel style and the live
## swap. The hash gates (run_gates.sh) prove the look is visual only.

const REQUIRED: Array[StringName] = [
	&"player", &"chaser", &"tank", &"bomber", &"lancer", &"shooter", &"splitter",
	&"splitter_mini", &"hunter", &"elite", &"orbit_shard",
	&"shot_dot_player", &"shot_fan_player", &"shot_line_player", &"shot_ball_player",
	&"shot_dot_enemy", &"gem", &"ammo", &"heal", &"battery", &"weapon", &"crate", &"gate",
	&"blast", &"pop", &"particle", &"aim_arrow", &"aim_arrow_diag", &"ui_panel", &"ui_panel_lit"]
const TILES: Array[StringName] = [&"floor_a", &"floor_b", &"wall", &"standable"]
const OPTIONAL: Array[StringName] = [
	&"shot_ring_player", &"shot_burst_player", &"shot_hole_player", &"shot_fan_enemy",
	&"shot_line_enemy", &"shot_ball_enemy", &"shot_ring_enemy", &"shot_burst_enemy",
	&"shot_hole_enemy"]

var _was: ArtSkin


func before_each() -> void:
	_was = Skins.current


func after_each() -> void:
	Skins.use(_was)


func _art() -> Script:
	return load(Skins.PIXEL_ART) as Script


func test_two_bakes_are_byte_identical_and_clean() -> void:
	var a := ArtSkin.bake(_art(), &"a")
	var b := ArtSkin.bake(_art(), &"b")
	assert_eq(a.problems, [] as Array[String], "the grids parse")
	assert_eq(a.digest(), b.digest())
	assert_eq(a.digest().length(), 64)
	assert_eq(Skins.pixel().digest(), a.digest(), "the cached skin is the same bake")


func test_every_id_resolves_with_its_frames() -> void:
	var skin := Skins.pixel()
	for id in REQUIRED + OPTIONAL + TILES:
		assert_true(skin.has(id), "%s resolves" % id)
		assert_gt(skin.frame_count(id), 0, id)
		assert_not_null(skin.texture(id, 0), id)
		assert_gt(skin.size_of(id).x, 0.0, id)
	for id in TILES:
		assert_true(skin.is_tile(id), id)
		assert_eq(skin.size_of(id), Vector2(Tuning.TILE, Tuning.TILE), "%s is one 48 px tile" % id)
	assert_eq(skin.frame_count(&"player"), 2, "a 2-frame idle")
	assert_gt(skin.frame_count(&"blast"), 1, "the blast animates")


func test_idle_and_life_frames() -> void:
	var skin := Skins.pixel()
	assert_eq(skin.idle_frame(&"player", 0.0), 0)
	assert_eq(skin.idle_frame(&"player", 0.21), 1, "5 Hz")
	assert_eq(skin.idle_frame(&"player", 0.41), 0)
	assert_eq(skin.life_frame(&"blast", 0.0), 0)
	assert_eq(skin.life_frame(&"blast", 1.0), skin.frame_count(&"blast") - 1)
	assert_eq(skin.scale_for(&"chaser", 30.0), 2.0, "native size: 2x")
	assert_eq(skin.scale_for(&"splitter_mini", 15.0), 2.0)
	assert_eq(skin.scale_for(&"chaser", 45.0), 3.0, "a bigger copy: the nearest whole scale")
	assert_eq(skin.scale_for(&"shot_line_player", 21.0), 2.0)


func test_each_body_finds_its_sprite() -> void:
	Skins.use(Skins.pixel())
	for id in [&"chaser", &"tank", &"bomber", &"lancer", &"shooter"]:
		var e := (load("res://entities/enemy_%s.tscn" % id) as PackedScene).instantiate()
		assert_eq(Skins.id_for(e.get_node("Visual")), id)
		e.free()
	var splitter := (load("res://entities/enemy_chaser.tscn") as PackedScene).instantiate()
	splitter.set(&"variant", &"splitter")
	assert_eq(Skins.id_for(splitter.get_node("Visual")), &"splitter")
	splitter.set(&"variant", &"")
	splitter.set(&"generation", 1)
	assert_eq(Skins.id_for(splitter.get_node("Visual")), &"splitter_mini")
	splitter.free()
	var player := (load("res://entities/player.tscn") as PackedScene).instantiate()
	player.add_to_group(&"player")
	assert_eq(Skins.id_for(player.get_node("Visual")), &"player")
	assert_eq(Skins.id_for(player.get_node("Aim/Tip")), &"aim_arrow", "the aim tip is the arrow")
	player.free()
	var hunter: Node = load("res://mutations/hunter/hunter_body.gd").new()
	assert_eq(Skins.id_for(hunter.get_node("Visual")), &"hunter")
	hunter.free()
	var shards: Node = load("res://mutations/orbit/orbit_shards.gd").new()
	var shard := RectVisual.new()
	shards.add_child(shard)
	assert_eq(Skins.id_for(shard), &"orbit_shard")
	shards.free()
	var shot := (load("res://entities/projectile.tscn") as PackedScene).instantiate()
	assert_eq(Skins.id_for(shot.get_node("Visual")), &"shot_dot_player", "no weapon: dot")
	shot.free()
	for w in [[&"laser", &"player", &"shot_line_player"], [&"shotgun", &"player", &"shot_fan_player"],
			[&"launcher", &"player", &"shot_ball_player"], [&"", &"enemy", &"shot_dot_enemy"]]:
		assert_eq(Skins.shot_id(w[0], w[1]), w[2])


func test_toggle_on_and_off_restores_the_null_path() -> void:
	Skins.use(null)
	var v := Skins.version
	Skins.toggle()
	assert_not_null(Skins.current, "on")
	assert_eq(Skins.current, Skins.pixel())
	assert_eq(Skins.version, v + 1)
	Skins.toggle()
	assert_null(Skins.current, "off: today's flat shapes")
	assert_eq(Skins.version, v + 2)
	Skins.use(null)
	assert_eq(Skins.version, v + 2, "no swap, no bump")
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = Skins.TOGGLE_KEY
	assert_true(Skins.is_toggle(key))
	key.physical_keycode = KEY_F2
	assert_false(Skins.is_toggle(key), "F2 stays the debug console")


## Owner 2026-11-25 "the player sprite is ghosting": the look draws bodies between physics
## ticks (a 240 Hz screen showed a 60 Hz body sliding back 3 frames a tick); off restores
## the project's setting, so today's picture is untouched.
func test_the_look_draws_between_ticks_and_off_restores_the_project_setting() -> void:
	var tree := get_tree()
	var project := bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false))
	Skins.use(null)
	assert_eq(tree.physics_interpolation, project, "off: the project's own setting")
	Skins.use(Skins.pixel())
	assert_true(tree.physics_interpolation, "on: interpolated")
	Skins.use(null)
	assert_eq(tree.physics_interpolation, project, "off again: restored")
	Skins.apply_motion(null)   # no tree (a tool before the loop): no crash
	assert_eq(tree.physics_interpolation, project)


func test_a_rect_visual_draws_its_rect_with_the_look_off() -> void:
	Skins.use(null)
	var vis := RectVisual.new()
	vis.skin_id = &"chaser"
	add_child_autofree(vis)
	await wait_process_frames(2)
	assert_eq(vis.get(&"_skin_version"), -1, "the look off never resolves a sprite")
	Skins.use(Skins.pixel(), vis)
	await wait_process_frames(2)
	assert_eq(vis.get(&"_skin_version"), Skins.version, "on: resolved at this version")
	assert_eq(vis.get(&"_skin_id"), &"chaser")
	Skins.use(null, vis)
	assert_null(Skins.current)


func test_no_image_files_and_no_rng_in_the_skins() -> void:
	for f in DirAccess.get_files_at("res://systems/skins/"):
		assert_false(f.get_extension() in ["png", "jpg", "webp", "svg"], f)
	var rng := RegEx.create_from_string("\\b(randf|randi|randomize|get_instance_id|RandomNumberGenerator|gameplay_rng)\\b")
	for f in ["res://systems/skins/skins.gd", "res://systems/skins/art_skin.gd"]:
		assert_null(rng.search(FileAccess.get_file_as_string(f)), f)


## Owner G14a (2026-11-25): walls at body density (24x24 art at 2x in one 48 px cell),
## a pattern whose period divides the tile, so blocks of any size tile with no seam.
func test_wall_tiles_tile_seamlessly_at_body_density() -> void:
	var skin := Skins.pixel()
	for id in [&"wall", &"standable"]:
		var img := skin.image(id)
		assert_eq(img.get_size(), Vector2i(Tuning.TILE, Tuning.TILE), "%s is one cell" % id)
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				assert_eq(img.get_pixel(x + 1, y + 1), img.get_pixel(x, y), "%s is 2x" % id)
	var wall := skin.image(&"wall")
	var period := 16   # one brick (8 art px) wide, two courses (8 art px) tall
	var bad := 0
	for y in wall.get_height():
		for x in wall.get_width():
			var c := wall.get_pixel(x, y)
			if c != wall.get_pixel((x + period) % wall.get_width(), y) or c != wall.get_pixel(x, (y + period) % wall.get_height()):
				bad += 1
	assert_eq(bad, 0, "the brick bond wraps across the cell edges")
	var rim := skin.wall_rim()
	assert_true(rim.has("outline") and rim.has("lit"), "the wall rim colours resolve")


func test_aim_arrow_frames_are_the_same_wedge() -> void:
	var skin := Skins.pixel()
	assert_eq(skin.size_of(&"aim_arrow"), Vector2(8, 9))
	assert_eq(skin.size_of(&"aim_arrow_diag"), Vector2(8, 8))
	for id in [&"aim_arrow", &"aim_arrow_diag"]:
		var s := skin.size_of(id) * ArtSkin.BODY_SCALE
		assert_eq(fmod(s.x, 2.0) + fmod(s.y, 2.0), 0.0, "%s centres on a whole pixel at 2x" % id)


# --- M48a ---------------------------------------------------------------------------------

## Game scripts: everything but the addons, tests, tools and capture folders.
func _game_scripts(dir := "res://") -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == "gd":
			out.append(dir + f)
	for sub in DirAccess.get_directories_at(dir):
		if sub in ["addons", "tests", "tools", ".godot", ".check", "builds"]:
			continue
		out.append_array(_game_scripts(dir + sub + "/"))
	return out


func test_every_role_resolves_and_tier_0_is_the_role_table() -> void:
	Skins.use(null)
	for role: StringName in Palette.TIER_0:
		assert_eq(Palette.color(role), Palette.TIER_0[role], "%s: tier 0" % role)
	for role in Palette.CORE:
		assert_true(Palette.has(role), "%s is a role" % role)
	assert_eq(Palette.BG, Color(0.09, 0.1, 0.13), "today's background")
	assert_eq(Palette.color(&"no_such_role"), Color.MAGENTA, "a typo shows")
	var skin := Skins.pixel()
	for role in Palette.CORE:
		assert_not_null(skin.role(role), "Pixel names %s" % role)
	for role in skin.roles():
		assert_true(Palette.has(role), "Pixel's %s is a Palette role" % role)
	Skins.use(skin)
	assert_eq(Palette.color(&"bg"), Color.html("#3a2a4f"), "on: the look's colour")
	assert_eq(Palette.color(&"mascot_ink"), Palette.MASCOT_INK, "a role the look leaves: tier 0")
	Skins.use(null)
	assert_eq(Palette.color(&"bg"), Palette.BG, "off again: tier 0")


## Every Palette.color(&"role") in the game names a role (a typo would draw magenta).
func test_every_role_used_in_code_exists() -> void:
	var re := RegEx.create_from_string("Palette\\.color\\(&\"([a-z_0-9]+)\"\\)")
	var used := 0
	for path in _game_scripts():
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			used += 1
			assert_true(Palette.has(StringName(m.get_string(1))), "%s: %s" % [path, m.get_string(1)])
	assert_gt(used, 20)


## 1.7: every hard-coded colour is routed through Palette. Left: white tints (alpha only:
## Color(1, 1, 1, a), and Color.WHITE as a modulate or a lerp target).
func test_no_hard_coded_colour_outside_palette() -> void:
	var literal := RegEx.create_from_string("Color\\(\\s*-?[0-9.]+\\s*,|Color\\.html|Color8|Color\\.from_|Color\\.[A-Z_]+\\b")
	var allowed := RegEx.create_from_string("^(Color\\(1, 1, 1, |Color\\.WHITE\\b|Color\\.MAGENTA\\b)")
	var checked := 0
	for path in _game_scripts():
		if path == "res://systems/palette.gd" or path.begins_with("res://systems/skins/"):
			continue
		checked += 1
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var code := _code_of(lines[i])
			for m in literal.search_all(code):
				if allowed.search(code.substr(m.get_start())) != null:
					continue
				fail_test("%s:%d hard-codes a colour: %s" % [path, i + 1, lines[i].strip_edges()])
	assert_gt(checked, 100)


## A line without its comment (a '#' outside a string ends the code).
func _code_of(line: String) -> String:
	var quote := ""
	for i in line.length():
		var ch := line[i]
		if quote != "":
			if ch == quote and (i == 0 or line[i - 1] != "\\"):
				quote = ""
		elif ch == "\"" or ch == "'":
			quote = ch
		elif ch == "#":
			return line.substr(0, i)
	return line


## A script's code, comments stripped.
func _code_text(path: String) -> String:
	var out := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		out.append(_code_of(line))
	return "\n".join(out)


## Lint 1 (1.7): LOOK_READERS gains palette.gd and skins.gd (test_readability.gd).
func test_look_readers_lint_lists_palette_and_skins() -> void:
	var text := FileAccess.get_file_as_string("res://tests/gut/test_readability.gd")
	assert_true(text.contains("\"res://systems/palette.gd\""))
	assert_true(text.contains("\"res://systems/skins/skins.gd\""))


## Lint 2 (1.7): gameplay scripts read neither Palette nor Skins.
func test_gameplay_scripts_read_no_palette_or_skins() -> void:
	var files: Array[String] = ["res://entities/enemy_walker.gd", "res://entities/enemy_common.gd",
		"res://entities/enemy_lancer.gd", "res://entities/enemy_bomber.gd",
		"res://entities/enemy_shooter.gd", "res://systems/spawner.gd",
		"res://paths/survival/drops.gd"]
	for dir in ["res://components/", "res://enemies/"]:
		for f in DirAccess.get_files_at(dir):
			if f.get_extension() == "gd":
				files.append(dir + f)
	assert_true("res://components/loadout.gd" in files and "res://components/health.gd" in files)
	var re := RegEx.create_from_string("\\b(Palette|Skins|ArtSkin)\\b")
	for path in files:
		assert_true(FileAccess.file_exists(path), path)
		assert_null(re.search(_code_text(path)), "%s reads the look" % path)


## Lint 3 (1.7): systems/skins/ (and Palette) read no gameplay RNG, Tuning or WorldRules.
func test_skins_read_no_gameplay_rng_tuning_or_world_rules() -> void:
	var re := RegEx.create_from_string("\\b(Tuning|WorldRules|director_rng|gameplay_rng|loot_rng|pick_rng|randf|randi|randomize|RandomNumberGenerator|get_instance_id)\\b|RunState\\.rules")
	var files: Array[String] = ["res://systems/palette.gd"]
	for dir in ["res://systems/skins/", "res://systems/skins/art/"]:
		for f in DirAccess.get_files_at(dir):
			if f.get_extension() == "gd":
				files.append(dir + f)
	assert_gte(files.size(), 4)
	for path in files:
		assert_null(re.search(_code_text(path)), path)


## 1.7's cost rule: no image file under a game folder. Exempt: addons/ (GUT's icons),
## .check/, .godot/, builds/, and the six v6 dev-session stills (devsession/stills/,
## mockups of the legacy loop, older than the rule).
func test_no_image_files_under_game_folders() -> void:
	var legacy := ["look_1_arcade.png", "look_1_clean.png", "look_1_punchy.png",
		"stages_breakout.png", "stages_gauntlet.png", "stages_shifting.png"]
	var found: Array[String] = []
	_images_under("res://", found)
	for path in found:
		if path.begins_with("res://devsession/stills/") and path.get_file() in legacy:
			continue
		fail_test("%s is an image file" % path)
	pass_test("%d images, all legacy stills" % found.size())


func _images_under(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in ["png", "webp", "svg", "jpg", "jpeg"]:
			out.append(dir + f)
	for sub in DirAccess.get_directories_at(dir):
		if sub in ["addons", ".godot", ".check", "builds"]:
			continue
		_images_under(dir + sub + "/", out)


func test_ui_panel_is_a_crisp_nine_slice() -> void:
	var skin := Skins.pixel()
	var box := skin.ui_panel()
	assert_not_null(box)
	assert_eq(box.texture.get_size(), Vector2(24, 24), "8x8 cells at 3x")
	assert_eq(box.texture_margin_left, 6.0, "2-cell margins drawn 1:1")
	assert_eq(skin.ui_panel(), box, "cached")
	assert_ne(skin.ui_panel(true), box, "the lit panel is its own")
	var b := Button.new()
	Skins.use(null)
	Skins.dress_button(b)
	assert_false(b.has_theme_stylebox_override(&"normal"), "no look: today's theme")
	Skins.use(skin)
	Skins.dress_button(b)
	assert_eq(b.get_theme_stylebox(&"normal"), box)
	assert_eq(b.get_theme_stylebox(&"focus"), skin.ui_panel(true))
	b.free()


func test_particles_and_glyphs_use_the_look() -> void:
	var skin := Skins.pixel()
	assert_not_null(skin.particle_texture())
	assert_eq(skin.main_color(&"chaser", Color.WHITE), Color.html("#f2402e"), "a puff takes the sprite's colour")
	assert_eq(skin.main_color(&"nothing", Color.RED), Color.RED)
	for key in WeaponGlyph.KEYS:
		assert_true(skin.has(StringName("shot_%s_player" % key)), "%s has a pixel picture" % key)
	# M48a review: feedback.burst really takes the look's particle sprite (none with no look).
	var world := Node2D.new()
	add_child_autofree(world)
	var fb := Feedback.new()
	fb.effects_parent = world
	add_child_autofree(fb)
	Skins.use(null)
	fb.burst(Vector2.ZERO, Color.WHITE, 4, 10.0, 20.0, 0.1, 6.0)
	assert_null((world.get_child(0) as CPUParticles2D).texture, "no look: today's square particles")
	Skins.use(skin)
	fb.burst(Vector2.ZERO, Color.WHITE, 4, 10.0, 20.0, 0.1, 6.0)
	var p := world.get_child(1) as CPUParticles2D
	assert_eq(p.texture, skin.particle_texture(), "a look: its particle sprite")
	assert_eq([p.scale_amount_min, p.scale_amount_max], [2.0, 2.0], "one whole scale per burst")


## M48a review: CPUParticles2D multiplies the sprite by the burst's colour, so the particle
## sprite is neutral grey (its brightest cell white): a cyan dash burst stays cyan.
func test_the_particle_sprite_is_neutral_so_bursts_keep_their_colour() -> void:
	var img := Skins.pixel().particle_image()
	assert_not_null(img)
	var brightest := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			assert_almost_eq(c.r, c.g, 0.01, "grey at %d,%d: %s" % [x, y, c])
			assert_almost_eq(c.g, c.b, 0.01, "grey at %d,%d: %s" % [x, y, c])
			brightest = maxf(brightest, c.r)
	assert_almost_eq(brightest, 1.0, 0.01, "the main cell carries the burst's colour as is")


class GlyphProbe:
	extends Node2D
	func _draw() -> void:
		for key in WeaponGlyph.KEYS:
			WeaponGlyph.draw(self, key, Vector2(40, 40), 26.0, Color.WHITE)


## M48a review: WeaponGlyph.draw (the hand, weapon pickups) shows the look's shot sprite for
## every key, and today's shapes with no look.
func test_weapon_glyphs_draw_the_look_pictures() -> void:
	var probe := GlyphProbe.new()
	add_child_autofree(probe)
	Skins.use(null)
	var n0 := WeaponGlyph.skin_draws
	probe.queue_redraw()
	await wait_process_frames(2)
	assert_eq(WeaponGlyph.skin_draws, n0, "no look: plain shapes")
	Skins.use(Skins.pixel())
	probe.queue_redraw()
	await wait_process_frames(2)
	assert_eq(WeaponGlyph.skin_draws, n0 + WeaponGlyph.KEYS.size(), "a look: every key from its sprite")


## M48a review: the silhouette gates are hard numbers (1.7: masks run headless): every enemy
## pair's IoU < 0.70, the player against each enemy < 0.60 (render_sheet.gd's measure).
func test_silhouettes_stay_apart() -> void:
	var skin := Skins.pixel()
	var enemies: Array[StringName] = [&"chaser", &"tank", &"bomber", &"lancer", &"shooter",
			&"splitter", &"splitter_mini", &"hunter"]
	for i in enemies.size():
		for j in range(i + 1, enemies.size()):
			var v := _iou(skin, enemies[i], enemies[j])
			assert_between(v, 0.0, 0.6999, "%s / %s IoU %.3f" % [enemies[i], enemies[j], v])
	for e in enemies:
		var v := _iou(skin, &"player", e)
		assert_between(v, 0.0, 0.5999, "player / %s IoU %.3f" % [e, v])


## Frame 0 masks (alpha > 0.5) centred on a shared canvas: intersection over union; -1 for a
## missing id.
static func _iou(skin: ArtSkin, a: StringName, b: StringName) -> float:
	var ia := skin.image(a)
	var ib := skin.image(b)
	if ia == null or ib == null:
		return -1.0
	var canvas := Vector2i(maxi(ia.get_width(), ib.get_width()), maxi(ia.get_height(), ib.get_height()))
	var ma := _mask(ia, canvas)
	var mb := _mask(ib, canvas)
	var inter := 0
	var uni := 0
	for i in ma.size():
		if ma[i] == 1 and mb[i] == 1:
			inter += 1
		if ma[i] == 1 or mb[i] == 1:
			uni += 1
	return float(inter) / uni if uni > 0 else 0.0


static func _mask(img: Image, canvas: Vector2i) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(canvas.x * canvas.y)
	var off := (canvas - img.get_size()) / 2
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				m[(y + off.y) * canvas.x + x + off.x] = 1
	return m


## M48a review: Arsenal's pixel cards keep tier 0's join flash (brighter while a card joins),
## none under reduce flashing (join_flash is 0 there).
func test_the_pixel_hand_keeps_the_join_flash() -> void:
	var hand: Script = load("res://paths/arsenal/hand_widget.gd")
	var dim: Color = hand.call(&"panel_modulate", false, 1.0, 0.0)
	assert_eq(dim, Color(Palette.UI_DIM, 1.0))
	assert_eq(hand.call(&"panel_modulate", true, 0.4, 0.0), Color(1, 1, 1, 0.4))
	var flash: Color = hand.call(&"panel_modulate", false, 0.5, 0.6)
	assert_gt(flash.r, dim.r, "a joining card flashes brighter")
	assert_almost_eq(flash.a, 0.5, 0.0001, "and still fades in")


## M48a review: the mascot keeps what it was doing across a live look swap.
func test_a_look_swap_keeps_the_mascot_talking_pointing_and_glitch() -> void:
	Skins.use(null)
	var m := Mascot.new()
	add_child_autofree(m)
	m.setup(true, &"cursor")
	await wait_process_frames(1)
	m.say(Line.make("A rather long line to keep typing for a while.", &"happy"), 3)
	m.step(0.01)
	m.point_at_screen(Vector2(200, 300), 2.0)
	m.glitch(1.0)
	assert_true(m.body.talking)
	for look: ArtSkin in [Skins.pixel(), null]:
		Skins.use(look)
		var on := Skins.current_name()
		assert_true(m.body.talking, "still talking (%s)" % on)
		assert_true(m.body.pointing(), "still pointing (%s)" % on)
		assert_true(m.body.glitching(), "still glitching (%s)" % on)
		assert_eq(m.body.expression, &"happy")


## M48a review: the debrief re-dresses itself on a live swap (F10 works while it is open):
## the big body and the mascot cards' previews in the look's body style, the cards' and the
## buttons' panels on and off again.
func test_the_debrief_follows_a_live_look_swap() -> void:
	SaveGame.go_inert()
	Skins.use(null)
	var d := DebriefScreen.new()
	add_child_autofree(d)
	d.input_delay = 0.0
	var s := SessionDef.new()
	s.id = &"swap_fixture"
	s.title = "swap"
	s.fork = &"fork_mascot"
	s.face = true
	d.open(s, &"win", 0)
	d.finish_lines()
	assert_eq(d.phase, DebriefScreen.FORK, "the mascot cards are up")
	assert_null(d._big_view)
	assert_false(_has_pixel_view(d._cards), "off: plain previews")
	d.big_body.say_start()
	var skin := Skins.pixel()
	Skins.use(skin)
	assert_not_null(d._big_view, "on: the big body in the pixel style")
	assert_eq(d.big_body.get_parent().get_class(), "SubViewport")
	assert_true(d.big_body.talking, "the swap keeps it talking")
	assert_true(_has_pixel_view(d._cards), "on: the previews too")
	var card := d._cards.get_child(0) as Button
	assert_eq(card.get_theme_stylebox(&"normal"), skin.ui_panel(false), "on: the cards wear the panel")
	Skins.use(null)
	assert_null(d._big_view, "off again: the plain body")
	assert_false(_has_pixel_view(d._cards))
	card = d._cards.get_child(0) as Button
	assert_false(card.has_theme_stylebox_override(&"normal"), "off again: today's theme")
	assert_true(d.pick(0))
	d.finish_lines()
	assert_eq(d.phase, DebriefScreen.DONE)
	var b := d._buttons.get_child(0) as Button
	assert_false(b.has_theme_stylebox_override(&"normal"))
	Skins.use(skin)
	assert_eq(b.get_theme_stylebox(&"normal"), skin.ui_panel(false), "on: the way on wears the panel")
	assert_eq(b.get_theme_stylebox(&"focus"), skin.ui_panel(true))
	Skins.use(null)
	assert_false(b.has_theme_stylebox_override(&"normal"), "off: today's theme again")
	d.close()
	SaveGame.go_inert()


func _has_pixel_view(node: Node) -> bool:
	for child in node.get_children():
		if child is PixelBodyView or _has_pixel_view(child):
			return true
	return false


## The mascot's pixel style: the body draws into a small viewport shown at 3x, over a rect
## that holds everything the body can ever draw (keep_out holds), re-rendering on a new
## expression and at a stepped rate, never every frame. Off: the body as it is.
func test_the_mascot_wears_the_pixel_style_and_swaps_live() -> void:
	Skins.use(null)
	var m := Mascot.new()
	add_child_autofree(m)
	m.setup(true, &"cursor")
	await wait_process_frames(1)
	assert_eq(m.body.get_parent().get_class(), "Control", "off: the body sits in the corner")
	var keep_off := m.keep_out(Vector2(1280, 720))
	Skins.use(Skins.pixel())
	await wait_process_frames(1)
	var view := m.body.get_parent().get_parent() as PixelBodyView
	assert_not_null(view, "on: the body is in a pixel view")
	assert_eq(m.body.get_parent().get_class(), "SubViewport")
	assert_almost_eq(m.body.scale.x, (Mascot.SIZE / 100.0) / PixelBodyView.PIXEL, 0.0001)
	assert_eq(m.keep_out(Vector2(1280, 720)), keep_off, "keep_out does not move")
	var shown := view.shown_rect()
	var worst := m.body.worst_bounds()
	var s := Mascot.SIZE / 100.0
	var worst_corner := Rect2(view.position + worst.position * s, worst.size * s)
	assert_true(shown.encloses(worst_corner), "the view covers every pose: %s in %s" % [worst_corner, shown])
	m.body.frozen = true
	var r0 := view.renders
	for i in 10:
		await wait_process_frames(1)
	assert_eq(view.renders, r0, "a still body never re-renders")
	m.show_expression(&"happy")
	await wait_process_frames(1)
	assert_eq(view.renders, r0 + 1, "a new expression re-renders once")
	m.body.advance(1.0)
	await wait_process_frames(1)
	assert_eq(view.renders, r0 + 2, "time moves: one stepped render")
	Skins.use(null)
	await wait_process_frames(1)
	assert_eq(m.body.get_parent().get_class(), "Control", "off again: the plain body")
	assert_eq(m.body.expression, &"happy", "the swap keeps the face")


## Live swap: every skinned node redraws and re-reads its id at the new version.
func test_live_swap_reaches_every_skinned_node() -> void:
	Skins.use(null)
	var vis := RectVisual.new()
	vis.skin_id = &"tank"
	add_child_autofree(vis)
	var line := LanceLine.new()
	add_child_autofree(line)
	await wait_process_frames(1)
	assert_true(vis.is_in_group(Skins.SKINNED))
	line.strength = 0.5
	assert_eq(line.default_color, Color(1.0, 0.3, 0.9, 0.25 + 0.55 * 0.5), "tier 0: M47.2's colour")
	var got: Array = []
	var on_change := func(skin: ArtSkin) -> void: got.append(skin)
	Skins.hub.skin_changed.connect(on_change)
	Skins.use(Skins.pixel())
	await wait_process_frames(2)
	assert_eq(vis.get(&"_skin_version"), Skins.version, "re-read at the new version")
	line.strength = 0.5
	assert_eq(Color(line.default_color, 1.0), Color.html("#e63fc4"), "the look's lancer line")
	Skins.use(null)
	Skins.hub.skin_changed.disconnect(on_change)
	assert_eq(got.size(), 2, "one signal per swap")
	Skins.use_named(&"pixel")
	assert_eq(Skins.current_name(), &"pixel")
	Skins.use_named(&"off")
	assert_null(Skins.current)


func test_the_bake_is_fast_enough() -> void:
	var t0 := Time.get_ticks_usec()
	var skin := ArtSkin.bake(_art(), &"timed")
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	assert_lt(ms, 150.0, "bake %.1f ms (1.7: <= 150 ms)" % ms)
	gut.p("pixel bake %.1f ms, %d ids, digest %s" % [ms, skin.ids().size(), skin.digest()])


# --- M48b (PLAN 1.7.1) -------------------------------------------------------------------

## The approved art never moved: M48a's atlas, hashed in String order (M48b: M48a's
## f8bf9165... sorted the ids as StringNames, i.e. by interning order, so it moved whenever
## other code named an id first; M48a's grids give this value under the stable order). The
## morph's mosaic and outline are derived on demand, outside digest().
func test_the_atlas_hash_is_m48as() -> void:
	var skin := Skins.pixel()
	assert_not_null(skin.mosaic(&"chaser"))
	assert_not_null(skin.outline(&"chaser"))
	# M50.1b: + shot_prism_player and shot_misfuse_player (d07379b4...). M50.4c1: + shot_minigun_player.
	assert_eq(skin.digest(), "95eb8f0bfc4f43ceabdb3d119c6af3cddfe4b89f1849b79aac7ced22e39f3759")


## A CLI / F10 / console swap reveals everything (M48a's behaviour); a manual reveal state
## puts every hook and Palette on tier 0 until its id is revealed.
func test_use_reveals_all_and_role_on_drives_palette() -> void:
	Skins.use(Skins.pixel())
	assert_true(Skins.all_on())
	for id: StringName in [&"player", &"chaser", &"floor_a", &"ui_panel", &"mascot", &"particle"]:
		assert_true(Skins.is_on(id), String(id))
	assert_eq(Palette.color(&"bg"), Color.html("#3a2a4f"))
	Skins.reset_reveal(true)
	assert_false(Skins.is_on(&"player"))
	assert_eq(Palette.color(&"bg"), Palette.tier_0(&"bg"), "manual: tier 0 until the arena")
	assert_eq(Palette.color(&"enemy"), Palette.tier_0(&"enemy"))
	Skins.reveal(&"arena")
	assert_eq(Palette.color(&"bg"), Color.html("#3a2a4f"), "the arena's roles follow its reveal")
	assert_eq(Palette.color(&"enemy"), Palette.tier_0(&"enemy"))
	Skins.reveal(&"chaser")
	assert_eq(Palette.color(&"enemy"), Color.html("#f2402e"))
	Skins.use(null)
	Skins.use(Skins.pixel())
	assert_true(Skins.all_on() and Skins.is_on(&"player"), "a swap reveals all again")
	Skins.use(null)
	assert_false(Skins.is_on(&"player"))
	assert_eq(Palette.color(&"bg"), Palette.tier_0(&"bg"))
