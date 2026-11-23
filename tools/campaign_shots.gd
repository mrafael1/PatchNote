extends SceneTree
## Screenshots of the mascot in the game (PLAN v8 M38, G13a): S3 played by the bot with
## a body in the corner and a line in its bubble, then S3's debrief at the fork's cards,
## then after a pick. The save stays inert (in memory). Needs a real window:
##
##   godot --path . -s tools/campaign_shots.gd -- [body, default blob]
##
## Writes .check/shot_corner.png, .check/shot_fork.png, .check/shot_notes.png.
## Not part of the game.

const OUT := "res://.check/shot_%s.png"
const SESSION := &"s1_03_shooting"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("[shots] FAILED: needs a window, run without --headless")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var body := StringName(args[0]) if args.size() > 0 else &"blob"
	var db := root.get_node("CampaignDB")
	db.active = true
	db.jump_to(SESSION)
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	var run_state := root.get_node("RunState")
	run_state.invincible = true
	game.player.set_bot(true)
	game.mascot.setup(true, body)
	for i in 150:
		await physics_frame
	game.mascot.say(Line.make("Oh. That works. Keep going!", &"happy"), 3)
	for i in 50:
		await physics_frame
	await _shot("corner")
	game.run_loop.goal_clock = 200.0
	while not game.debrief.is_open():
		await physics_frame
	game.debrief.finish_lines()
	for i in 20:
		await process_frame
	await _shot("fork")
	game.debrief.pick(Change.MASCOTS.find(body))
	for i in 60:
		await process_frame
	await _shot("pick")
	game.debrief.finish_lines()
	for i in 20:
		await process_frame
	await _shot("notes")
	quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := OUT % name
	var err := image.save_png(path)
	print("[shots] %s -> %s (%s)" % [name, ProjectSettings.globalize_path(path), error_string(err)])
