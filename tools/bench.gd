extends SceneTree
## Performance smoke test in a real window (vsync off):
##
##   godot --path . -s tools/bench.gd -- [mutation_id ...] [--weapon=<id:rank> ...] [--weapons=all:<rank>] --inert-save
##
## Holds 75 enemies and 100 projectiles alive with the bot playing, measures for
## 600 frames and prints frames per second and physics time. Not part of the game.
## Arguments starting with "--" are never mutation ids.
##
## M44 weapons: the loadout holds 3 aimed weapons at most, so the bench plays ONE SEGMENT
## PER WEAPON (WARMUP + MEASURE frames each): the loadout cleared, that weapon set at the
## rank and active (with --weapons=all, the orbit passive at that rank rides along in
## every aimed segment; a passive alone rides with the pistol). One "[bench] weapon=" line
## per segment, then the overall line.

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
	var segments: Array = []   ## [[id, rank], passive id or ""]
	var wdb: GDScript = load("res://weapons/weapon_db.gd")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--weapon="):
			var pair := arg.trim_prefix("--weapon=")
			segments.append([[StringName(pair.get_slice(":", 0)), int(pair.get_slice(":", 1)) if ":" in pair else 1], &""])
		elif arg.begins_with("--weapons=all:"):
			var r := int(arg.trim_prefix("--weapons=all:"))
			var passive := &""
			for def: Resource in wdb.call(&"all"):
				if def.get(&"mode") == &"passive":
					passive = def.get(&"id")
			for def: Resource in wdb.call(&"all"):
				if def.get(&"mode") == &"aimed":
					segments.append([[def.get(&"id"), r], passive])
	for id in OS.get_cmdline_user_args():
		if id.begins_with("--"):
			continue
		var m: Resource = db.get_mutation(StringName(id))
		if m and _force(run_state, m):
			applied.append(id)
		else:
			push_warning("[bench] not applied: %s" % id)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var points: Array = game.arena.spawn_points
	if segments.is_empty():
		segments = [null]
	var all_ms: Array[float] = []
	var all_frames := 0
	var all_seconds := 0.0
	var loadout: Node = game.player.get_node_or_null(^"Loadout")
	for seg: Variant in segments:
		var label := "-"
		if seg != null and loadout != null:
			loadout.clear()
			loadout.set_weapon(seg[0][0], seg[0][1])
			loadout.select(seg[0][0])
			if seg[1] != &"":
				loadout.set_weapon(seg[1], seg[0][1])
			label = loadout.summary()
		var r: Array = await _segment(run_state, game, rng, points)
		all_ms.append_array(r[0])
		all_frames += int(r[1])
		all_seconds += float(r[2])
		if seg != null:
			print("[bench] weapon=%s:%d loadout=%s %s" % [seg[0][0], seg[0][1], label, _stats(r[0], int(r[1]) / float(r[2]))])
	print("[bench] patches=%s enemies=%d projectiles=%d" % [applied, run_state.count(&"enemy"),
			run_state.count(&"player_projectile") + run_state.count(&"enemy_projectile")])
	print("[bench] %s (budget 16.67 ms)" % _stats(all_ms, all_frames / all_seconds))
	quit()


func _stats(ms: Array[float], fps: float) -> String:
	var sorted := ms.duplicate()
	sorted.sort()
	var total := 0.0
	for v: float in sorted:
		total += v
	return "fps=%.0f physics avg=%.2f ms p95=%.2f ms max=%.2f ms" % [fps, total / sorted.size(),
			sorted[int(sorted.size() * 0.95)], sorted[-1]]


## One measured segment: [physics ms per frame, process frames, seconds].
func _segment(run_state: Node, game: Node, rng: RandomNumberGenerator, points: Array) -> Array:
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
	return [physics_ms, Engine.get_process_frames() - frames, seconds]


## The F2 console's routes: a big patch is swapped in, an AI-tier one added as a stage
## patch, a small one applied, all ignoring requires/conflicts.
func _force(run_state: Node, m: Resource) -> bool:
	if m.is_big:
		run_state.swap_big(m)
		return run_state.big == m
	if m.is_ai_tier():
		return run_state.add_ai(m, &"stage", true)
	return run_state.apply(m, true)
