extends SceneTree
## Screenshots of the mascot in the game (PLAN v8 M38, G13a). M47.6b: the body pick moved to
## S2's end, so two parts. S2: its debrief at the body fork's cards, then after the pick. S3
## (played by the bot with the body in the corner and a line in its bubble): its debrief at the
## dash fork, then where the dash goes, then the notes. The save stays inert (in memory). Needs
## a real window:
##
##   godot --path . -s tools/campaign_shots.gd -- [body, default blob]
##
## Writes .check/shot_fork_body.png, shot_pick.png, shot_corner.png, shot_fork_dash.png,
## shot_fork_dash_aim.png, shot_notes.png. Not part of the game.

const OUT := "res://.check/shot_%s.png"
const BODY_SESSION := &"s1_02_enemies"
const SESSION := &"s1_03_shooting"
## Loaded at run time: a class name here would compile Line before the autoloads exist
## (it reads InputSetup), and the tool would fail to load.
const CHANGE_PATH := "res://devsession/change.gd"
const LINE_PATH := "res://campaign/line.gd"


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
	var run_state := root.get_node("RunState")
	db.active = true
	# S2: the body fork
	db.jump_to(BODY_SESSION)
	var game := await _game()
	run_state.invincible = true
	game.call(&"_on_report_ready", &"stop")
	await _fork(game, &"fork_mascot")
	await _shot("fork_body")
	if not game.debrief.pick(load(CHANGE_PATH).MASCOTS.find(body)):
		print("[shots] FAILED: could not pick the body %s" % body)
		quit(1)
		return
	for i in 60:
		await process_frame
	await _shot("pick")
	game.queue_free()
	await process_frame
	# S3: the body in the corner, then the dash and where it goes
	db.jump_to(SESSION)
	game = await _game()
	run_state.invincible = true
	game.player.set_bot(true)
	game.mascot.setup(true, body)
	for i in 150:
		await physics_frame
	game.mascot.say(load(LINE_PATH).make("Oh. That works. Keep going!", &"happy"), 3)
	for i in 50:
		await physics_frame
	await _shot("corner")
	game.run_loop.goal_clock = 200.0
	await _fork(game, &"fork_dash")
	await _shot("fork_dash")
	game.debrief.pick(0)
	await _fork(game, &"fork_dash_aim")
	await _shot("fork_dash_aim")
	game.debrief.pick(0)
	for i in 60:
		await process_frame
	game.debrief.finish_lines()
	for i in 20:
		await process_frame
	await _shot("notes")
	quit()


func _game() -> Node:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	return game


## Waits for the debrief to show `id`'s cards; quits 1 when another fork shows.
func _fork(game: Node, id: StringName) -> void:
	for i in 60 * 60:
		if game.debrief.is_open():
			game.debrief.finish_lines()
			var f: Variant = game.debrief.fork()
			if f != null and f.id == id:
				break
		await physics_frame
	for i in 20:
		await process_frame
	var f: Variant = game.debrief.fork()
	if f == null or f.id != id:
		print("[shots] FAILED: expected %s, got %s" % [id, f.id if f != null else "no fork"])
		quit(1)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := OUT % name
	var err := image.save_png(path)
	print("[shots] %s -> %s (%s)" % [name, ProjectSettings.globalize_path(path), error_string(err)])
