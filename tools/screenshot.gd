extends SceneTree
## Runs the game in a real window for a moment and saves a screenshot, so the builder
## can look at what a milestone actually renders.
##
##   godot --path . -s tools/screenshot.gd -- [out.png] [mutation_id ...]
##
## Spawns a debug wave, lets the bot play for a second and a half, applies any listed
## mutations, then captures. Not part of the game.

const FRAMES_BEFORE := 60
const FRAMES_AFTER := 70


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "res://.check/shot.png"
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	await physics_frame
	var run_state := root.get_node("RunState")
	var db := root.get_node("MutationDB")
	run_state.invincible = true
	game.player.set_bot(true)
	game.director.enabled = false
	game.spawn_wave(10)
	for i in FRAMES_BEFORE:
		await physics_frame
	var applied: Array[String] = []
	for i in range(1, args.size()):
		var m: Resource = db.get_mutation(StringName(args[i]))
		if m and _force(run_state, m):
			applied.append(args[i])
		else:
			push_warning("[shot] not applied: %s" % args[i])
	for i in FRAMES_AFTER:
		await physics_frame
	await process_frame
	var image := root.get_texture().get_image()
	var err := image.save_png(out)
	print("[shot] %s (%d) patches=%s" % [ProjectSettings.globalize_path(out), err, applied])
	quit()


## The F2 console's routes: a big patch is swapped in, an AI-tier one added as a stage
## patch, a small one applied, all ignoring requires/conflicts.
func _force(run_state: Node, m: Resource) -> bool:
	if m.is_big:
		run_state.swap_big(m)
		return run_state.big == m
	if m.is_ai_tier():
		return run_state.add_ai(m, &"stage", true)
	return run_state.apply(m, true)
