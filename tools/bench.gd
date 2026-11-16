extends SceneTree
## Performance smoke test in a real window (vsync off):
##
##   godot --path . -s tools/bench.gd -- [mutation_id ...]
##
## Holds 75 enemies and 100 projectiles alive with the bot playing, measures for
## 600 frames and prints frames per second and physics time. Not part of the game.

const ENEMIES := 75
const PROJECTILES := 100
const WARMUP := 120
const MEASURE := 600
# Loaded at run time: preloading here would compile game scripts before the autoloads exist.
var PROJECTILE: PackedScene
var SCENES: Array[PackedScene] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	PROJECTILE = load("res://entities/projectile.tscn")
	for path: String in ["res://entities/enemy_chaser.tscn", "res://entities/enemy_chaser.tscn",
			"res://entities/enemy_shooter.tscn", "res://entities/enemy_tank.tscn"]:
		SCENES.append(load(path))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	await physics_frame
	var run_state := root.get_node("RunState")
	var db := root.get_node("MutationDB")
	run_state.invincible = true
	game.spawner.enabled = false
	game.director.enabled = false
	game.player.set_bot(true)
	var applied: Array[String] = []
	for id in OS.get_cmdline_user_args():
		var m: Resource = db.get_mutation(StringName(id))
		if m and run_state.apply(m, true):
			applied.append(id)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var points: Array = game.arena.spawn_points
	var physics_ms: Array[float] = []
	var frames := 0
	var started := 0
	for i in WARMUP + MEASURE:
		# Top up to the target counts every tick, since the bot keeps killing things.
		for n in maxi(0, ENEMIES - run_state.count(&"enemy") - 2):
			var p: Vector2 = points[rng.randi_range(0, points.size() - 1)]
			run_state.spawn(SCENES[rng.randi_range(0, SCENES.size() - 1)], p + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)))
			if n > 6:
				break
		for n in maxi(0, PROJECTILES - run_state.count(&"player_projectile")):
			var from: Vector2 = points[rng.randi_range(0, points.size() - 1)]
			run_state.spawn(PROJECTILE, from, {&"velocity": Vector2.RIGHT.rotated(rng.randf_range(0, TAU)) * 500.0})
			if n > 10:
				break
		await physics_frame
		if i == WARMUP:
			started = Time.get_ticks_usec()
			frames = Engine.get_process_frames()
		if i >= WARMUP:
			physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)

	var seconds := (Time.get_ticks_usec() - started) / 1000000.0
	var fps := (Engine.get_process_frames() - frames) / seconds
	physics_ms.sort()
	var total := 0.0
	for v in physics_ms:
		total += v
	print("[bench] patches=%s enemies=%d projectiles=%d" % [applied, run_state.count(&"enemy"),
			run_state.count(&"player_projectile") + run_state.count(&"enemy_projectile")])
	print("[bench] fps=%.0f physics avg=%.2f ms p95=%.2f ms max=%.2f ms (budget 16.67 ms)" % [
			fps, total / physics_ms.size(), physics_ms[int(physics_ms.size() * 0.95)], physics_ms[-1]])
	quit()
