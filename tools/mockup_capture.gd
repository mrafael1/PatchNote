extends SceneTree
## Captures the stills of a mockup fork's options (PLAN v5 4.3, v6 1.1, M30): for each
## take, the same seeded fight is played with that take's look, and the frame with the
## most effects on screen is saved as the take's still. Needs a real window (the
## headless renderer draws nothing):
##
##   godot --path . -s tools/mockup_capture.gd -- [mockup fork id, default look_1]
##
## Writes res://devsession/stills/<fork>_<take>.png (480x270), one per option. A
## Stages take (its preset a StageSet, M35) gets a stage still instead: its three
## stages as whole-arena frames mid-fight, the first large on top, the other two below
## (Breakout's with the exit gate open). Run
## `godot --headless --path . --import` after it, then commit the PNGs. The change's
## .tres points at these files. Not part of the game.

const SEED := 7
const WAVES := 3
const WAVE_SIZE := 12
const FRAMES_WARM := 240     ## the bot fights before the capture window opens
const FRAMES_WINDOW := 240   ## the busiest frame in this window is kept
const ZOOM := 2.0            ## the still is the screen around the player, this much closer
const STILL_SIZE := Vector2i(480, 270)
const OUT_DIR := "res://devsession/stills/"
## Explosions on hit, so a still shows bursts and (in looks that have it) the flash.
const SHOT_PATCH := &"explode_on_hit"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("[capture] FAILED: needs a window, run without --headless")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var fork_id := StringName(args[0]) if args.size() > 0 else &"look_1"
	var fork: Resource = root.get_node("ChangeDB").get_fork(fork_id)
	if fork == null or not fork.get(&"mockup"):
		print("[capture] FAILED: %s is not a mockup fork" % fork_id)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var failures := 0
	for option: Resource in fork.call(&"changes"):
		var take: Resource = option.get(&"take")
		var path := OUT_DIR + "%s_%s.png" % [fork_id, take.get(&"id")]
		var preset: Resource = take.get(&"preset")
		var image: Image
		if preset.get_script() and preset.get_script().get_global_name() == &"StageSet":
			image = await _capture_stages(preset)
		else:
			image = await _capture(preset)
		var err := image.save_png(path)
		if err != OK:
			failures += 1
		print("[capture] %s -> %s (%s)" % [take.get(&"id"), ProjectSettings.globalize_path(path), error_string(err)])
	quit(1 if failures > 0 else 0)


## Plays the seeded fight with `preset` as the look; returns the busiest frame.
func _capture(preset: Resource) -> Image:
	var look: GDScript = load("res://systems/look.gd")
	var main_script: GDScript = load("res://main.gd")
	main_script.set(&"next_seed", SEED)
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	await physics_frame
	look.set(&"preset", preset)   # after main.gd applied the save's look: the take under test
	for child in game.get_children():
		if child is CanvasLayer and child.get_script() and child.get_script().get_global_name() == &"Hud":
			child.visible = false   # a still shows the game, not the save's version
	var run_state := root.get_node("RunState")
	run_state.invincible = true
	game.player.set_bot(true)
	game.director.enabled = false
	var m: Resource = root.get_node("MutationDB").get_mutation(SHOT_PATCH)
	if m:
		run_state.apply(m, true)
	var best: Image = null
	var best_score := -1
	for f in FRAMES_WARM + FRAMES_WINDOW:
		if f % (FRAMES_WARM / WAVES) == 0 and f < FRAMES_WARM:
			game.spawn_wave(WAVE_SIZE)
		await physics_frame
		if f < FRAMES_WARM:
			continue
		await process_frame
		var score := _score(game)
		if score > best_score:
			best_score = score
			best = _crop(game)
	print("[capture] %s:%s busiest frame: score %d" % [preset.get(&"tier"), preset.get(&"take"), best_score])
	game.queue_free()
	current_scene = null
	await process_frame
	run_state.reset(0)
	return best


## What a still around the player would show: bursts and projectiles count 1, kill
## pops 3. A frame where the player blinks (just hit) is worth nothing.
func _score(game: Node) -> int:
	var player: Node2D = game.player
	if player.modulate.a < 1.0:
		return -1
	var view := root.get_visible_rect().size / ZOOM
	var zoom: Vector2 = game.camera.zoom
	var half := Vector2(view.x, view.x * STILL_SIZE.y / STILL_SIZE.x) / 2.0 / zoom
	var area := Rect2(player.global_position - half, half * 2.0)
	var n := 0
	for child in game.get(&"world").get_children():
		if not child is Node2D or not area.has_point((child as Node2D).global_position):
			continue
		var script: Script = child.get_script()
		var name := script.get_global_name() if script else &""
		if name == &"KillPop":
			n += 3
		elif child is CPUParticles2D or child.get(&"faction") == &"player":
			n += 1
	return n


## The screen around the player, ZOOM times closer, at STILL_SIZE.
func _crop(game: Node) -> Image:
	var image := root.get_texture().get_image()
	var screen := Vector2(image.get_size())
	var at: Vector2 = game.player.get_global_transform_with_canvas().origin * screen / root.get_visible_rect().size
	var size := Vector2(screen.x / ZOOM, screen.x / ZOOM * STILL_SIZE.y / STILL_SIZE.x)
	var corner := (at - size / 2.0).clamp(Vector2.ZERO, screen - size)
	var out := image.get_region(Rect2i(Vector2i(corner), Vector2i(size)))
	out.resize(STILL_SIZE.x, STILL_SIZE.y, Image.INTERPOLATE_LANCZOS)
	return out


# --- Stage stills (M35) -----------------------------------------------------------

const STAGE_FRAMES_WARM := 200
const STAGE_FRAMES_WINDOW := 90
## Where each stage goes in the 480x270 still: the first large, the other two below.
const STAGE_SLOTS: Array[Rect2i] = [Rect2i(0, 6, 480, 160), Rect2i(4, 182, 234, 78), Rect2i(242, 182, 234, 78)]
const STILL_BACKGROUND := Color(0.05, 0.055, 0.07)


## Plays the take's stage set: each stage seeded with the same fight, the camera pulled
## back over the whole arena; returns the composite of the busiest frame of each.
func _capture_stages(stage_set: Resource) -> Image:
	var set_script: GDScript = load("res://levels/stage_set.gd")
	var main_script: GDScript = load("res://main.gd")
	set_script.set(&"override", stage_set)
	main_script.set(&"next_seed", SEED)
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	await physics_frame
	for child in game.get_children():
		if child is CanvasLayer:
			child.visible = false   # the game only: no HUD, no AI line
	var run_state := root.get_node("RunState")
	run_state.invincible = true
	game.player.set_bot(true)
	game.director.enabled = false
	var run_loop: Node = game.genre.get(&"run_loop")
	var out := Image.create(STILL_SIZE.x, STILL_SIZE.y, false, Image.FORMAT_RGBA8)
	out.fill(STILL_BACKGROUND)
	for i in stage_set.call(&"size"):
		if i > 0:
			run_loop.call(&"_start_stage", i)
			await physics_frame
		var best: Image = null
		var best_score := -1
		for f in STAGE_FRAMES_WARM + STAGE_FRAMES_WINDOW:
			if f % (STAGE_FRAMES_WARM / WAVES) == 0 and f < STAGE_FRAMES_WARM:
				game.spawn_wave(WAVE_SIZE)
			if f == STAGE_FRAMES_WARM / 2 and stage_set.call(&"stage", i).get(&"goal") == &"exit":
				run_loop.call(&"_open_exit")
			await physics_frame
			if f < STAGE_FRAMES_WARM:
				continue
			_frame_arena(game)
			await process_frame
			var score := 0
			for child in game.get(&"world").get_children():
				if child is CPUParticles2D or child.is_in_group(&"enemy"):
					score += 1
			if score > best_score:
				best_score = score
				best = _crop_arena(game)
		var slot := STAGE_SLOTS[mini(i, STAGE_SLOTS.size() - 1)]
		best.resize(slot.size.x, slot.size.y, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(best, Rect2i(Vector2i.ZERO, slot.size), slot.position)
		print("[capture] %s stage %d busiest frame: score %d" % [stage_set.get(&"id"), i, best_score])
	set_script.set(&"override", null)
	game.queue_free()
	current_scene = null
	await process_frame
	run_state.reset(0)
	return out


## The camera over the whole arena (it stops following and zooming for the still).
func _frame_arena(game: Node) -> void:
	var cam: Camera2D = game.camera
	cam.set_process(false)
	cam.position_smoothing_enabled = false
	cam.limit_left = -100000
	cam.limit_top = -100000
	cam.limit_right = 100000
	cam.limit_bottom = 100000
	cam.offset = Vector2.ZERO
	var bounds: Rect2 = game.genre.get(&"arena").bounds
	var view := root.get_visible_rect().size
	var z := minf(view.x / bounds.size.x, view.y / bounds.size.y)
	cam.zoom = Vector2(z, z)
	cam.global_position = bounds.get_center()


func _crop_arena(game: Node) -> Image:
	var image := root.get_texture().get_image()
	var bounds: Rect2 = game.genre.get(&"arena").bounds
	var screen := Vector2(image.get_size()) / root.get_visible_rect().size
	var xf := root.get_canvas_transform()
	var r := Rect2(xf * bounds.position * screen, bounds.size * xf.get_scale() * screen)
	var rect := Rect2i(r).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return image.get_region(rect)
