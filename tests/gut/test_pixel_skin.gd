extends GutTest
## The Pixel look preview (PLAN 1.7, before M48a): the art bakes the same twice, every id
## of .check/pixel_art/ids.md resolves, each body finds its sprite from the node that owns
## it, and turning the look off restores the null path (Skins.current == null). The hash
## gates prove the look is visual only.

const REQUIRED: Array[StringName] = [
	&"player", &"chaser", &"tank", &"bomber", &"lancer", &"shooter", &"splitter",
	&"splitter_mini", &"hunter", &"elite", &"orbit_shard",
	&"shot_dot_player", &"shot_fan_player", &"shot_line_player", &"shot_ball_player",
	&"shot_dot_enemy", &"gem", &"ammo", &"heal", &"battery", &"weapon", &"crate", &"gate",
	&"blast", &"pop", &"particle", &"aim_arrow", &"aim_arrow_diag"]
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
