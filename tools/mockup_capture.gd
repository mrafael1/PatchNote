extends SceneTree
## Captures the stills of a mockup fork's options (PLAN v5 4.3, v6 1.1, M30): for each
## take, the same seeded fight is played with that take's look, and the frame with the
## most effects on screen is saved as the take's still. Needs a real window (the
## headless renderer draws nothing):
##
##   godot --path . -s tools/mockup_capture.gd -- [mockup fork id, default look_1]
##
## Writes res://devsession/stills/<fork>_<take>.png (480x270), one per option. Run
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
		var image := await _capture(take.get(&"preset"))
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
