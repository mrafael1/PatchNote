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
##
## M45b, Auto at scale (PLAN v9 4 "Perf bench", 6.6). WINDOWED, never headless:
##
##   godot --path . -s tools/bench.gd -- --inert-save --auto[=<enemies>] [--passives=<id,id>]
##
## --auto plays Auto (session_path auto, the PathRunner frozen then begun: auto_all, 4 slots,
## the crowd overlay) with pistol/shotgun/laser/launcher at rank 3 and the passives
## (default nova,well) at rank 3. Enemies are held at <enemies> (default 57: the S8 draft's
## final-wave cap, "Auto at its enemy cap"), gems at 60, and synthetic player shots fill up
## to 116 minus the real weapons' live shots (never over 100), so the real weapons keep
## firing. One "[bench] auto" line. --weapons=all:<r> rides the orbit passive in every
## segment (picked by id, so M44's segment numbers stay comparable).
##
## M50.4c2 (Auto depth design 10, "Perf"): --auto --evolved swaps that loadout for the three
## built evolutions at their launch numbers (Minigun, Thunderclap, Supernova: 3 shared slots)
## with Haste 6 and Might 6; --evolved=minigun keeps only the Minigun (c1's bench).

const ENEMIES := 75
const PROJECTILES := 100
const WARMUP := 120
const MEASURE := 600
# Loaded at run time: preloading here would compile game scripts before the autoloads exist.
var PROJECTILE: PackedScene
var PICKUP: PackedScene
var SCENES: Array[PackedScene] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	PROJECTILE = load("res://entities/projectile.tscn")
	PICKUP = load("res://entities/pickup.tscn")
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
	var auto_enemies := -1
	var passive_ids: Array[StringName] = [&"nova", &"well"]
	var evolved: Array[StringName] = []
	for arg in OS.get_cmdline_user_args():
		if arg == "--evolved":
			evolved = [&"minigun", &"thunderclap", &"supernova"]
		elif arg.begins_with("--evolved="):
			for id in arg.trim_prefix("--evolved=").split(",", false):
				evolved.append(StringName(id))
		elif arg == "--auto":
			auto_enemies = 57
		elif arg.begins_with("--auto="):
			auto_enemies = int(arg.trim_prefix("--auto="))
		elif arg.begins_with("--passives="):
			passive_ids.clear()
			for id in arg.trim_prefix("--passives=").split(",", false):
				passive_ids.append(StringName(id))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--weapon="):
			var pair := arg.trim_prefix("--weapon=")
			segments.append([[StringName(pair.get_slice(":", 0)), int(pair.get_slice(":", 1)) if ":" in pair else 1], &""])
		elif arg.begins_with("--weapons=all:"):
			var r := int(arg.trim_prefix("--weapons=all:"))
			var passive := &"orbit"   # M45b: by id (no longer "the last passive")
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
	if auto_enemies > 0:
		await _auto(run_state, game, rng, points, auto_enemies, passive_ids, evolved)
		quit()
		return
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


## M45b: Auto at its cap (header). One "[bench] auto" line.
func _auto(run_state: Node, game: Node, rng: RandomNumberGenerator, points: Array, enemies: int,
		passive_ids: Array[StringName], evolved: Array[StringName] = []) -> void:
	run_state.session_path = &"auto"
	var runner: Node = game.call(&"ensure_path_runner")
	runner.call(&"freeze")   # before begin: no gems node, no meter, no pick panel
	runner.call(&"begin")
	var loadout: Node = game.player.get_node_or_null(^"Loadout")
	for id: StringName in [&"pistol", &"shotgun", &"laser", &"launcher"]:
		loadout.set_weapon(id, 3)
	for id in passive_ids:
		loadout.set_weapon(id, 3)
	if not evolved.is_empty():
		_evolved(loadout, evolved)
	var stats := {"weapon_shots": 0, "synthetic": 0, "pickups": 0, "enemy_shots": 0, "fields": 0, "most_fields": 0, "frames": 0}
	var r: Array = await _segment(run_state, game, rng, points, enemies, stats)
	var n := maxi(1, int(stats.frames))
	print("[bench] auto enemies=%d cap_s8=49/57 shots=%d/%d weapon_shots=%.1f synthetic=%.1f pickups=%.1f enemy_shots=%.1f fields=%.1f/%d kills=%d game_t=%.1f loadout=%s path=%s enemy_shots_refused=%d player_shots_refused=%d %s" % [
			run_state.count(&"enemy"), run_state.count(&"player_projectile"), run_state.count(&"enemy_projectile"),
			float(stats.weapon_shots) / n, float(stats.synthetic) / n, float(stats.pickups) / n,
			float(stats.enemy_shots) / n, float(stats.fields) / n, int(stats.most_fields), int(run_state.get(&"kills")), float(run_state.get(&"game_time")),
			loadout.call(&"summary"), run_state.call(&"live_path"),
			_counter(run_state, &"enemy_shots_refused"), _counter(run_state, &"player_shots_refused"),
			_stats(r[0], int(r[1]) / float(r[2]))])


## M50.4c2: the built evolutions `ids` at their launch numbers, each from its base at rank 6,
## with Haste 6 and Might 6 held (Loadout.evolve does not ask for the catalyst).
func _evolved(loadout: Node, ids: Array[StringName]) -> void:
	var wdb: GDScript = load("res://weapons/weapon_db.gd")
	loadout.call(&"clear")
	for id in ids:
		loadout.set_weapon(wdb.call(&"get_weapon", id).get(&"base"), 6)
	for item: StringName in [&"haste", &"might"]:
		loadout.add_item(item)
		for k in 5:
			loadout.level_item(item)
	for id in ids:
		var def: Resource = wdb.call(&"get_weapon", id)
		if not loadout.evolve(def.get(&"base"), id):
			push_warning("[bench] could not evolve %s" % id)
			continue
		var w: RefCounted = loadout.held(id)
		w.set(&"launch", (def.get(&"launch_values") as Dictionary).duplicate())
		loadout.reread(w)


func _counter(run_state: Node, key: StringName) -> int:
	var v: Variant = run_state.get(key)
	return int(v) if v != null else -1


## One measured segment: [physics ms per frame, process frames, seconds]. `auto` (the --auto
## run's stats) switches to its top-ups: enemies to `enemies`, gems to 60, synthetic shots
## after the real weapons' share.
func _segment(run_state: Node, game: Node, rng: RandomNumberGenerator, points: Array,
		enemies := ENEMIES, auto: Variant = null) -> Array:
	var physics_ms: Array[float] = []
	var frames := 0
	var started := 0
	for i in WARMUP + MEASURE:
		# Top up to the target counts every tick, since the bot keeps killing things.
		for n in maxi(0, enemies - run_state.count(&"enemy") - 2):
			var p: Vector2 = points[rng.randi_range(0, points.size() - 1)]
			run_state.spawn(SCENES[rng.randi_range(0, SCENES.size() - 1)], p + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)))
			if n > 6:
				break
		if auto != null:
			_auto_top_up(run_state, rng, points, auto, i >= WARMUP)
		else:
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


## --auto's per-tick top-ups: gems to 60 at the spawn points, then synthetic player shots
## (marked bench_synth) to 116 minus the real weapons' live shots, at most 100, so the player
## total sits near 140 with room for the next tick's weapon shots.
func _auto_top_up(run_state: Node, rng: RandomNumberGenerator, points: Array, stats: Dictionary,
		measured: bool) -> void:
	for n in maxi(0, 60 - run_state.count(&"pickup") - int(run_state.call(&"pending_count", &"pickup"))):
		var p: Vector2 = points[rng.randi_range(0, points.size() - 1)]
		run_state.spawn(PICKUP, p + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60)),
				{&"pickup_kind": &"gem", &"value": 1})
		if n > 10:
			break
	var weapon_shots := 0
	var synthetic := 0
	for s in get_nodes_in_group(&"player_projectile"):
		if s.is_queued_for_deletion():
			continue
		if s.has_meta(&"bench_synth"):
			synthetic += 1
		else:
			weapon_shots += 1
	if measured:
		stats.weapon_shots += weapon_shots
		stats.synthetic += synthetic
		stats.pickups += run_state.count(&"pickup")
		stats.enemy_shots += run_state.count(&"enemy_projectile")
		var fields := 0   # the well weapon's live pull fields (world children with its script)
		for c in run_state.world.get_children():
			var sc: Script = c.get_script()
			if sc != null and sc.resource_path.ends_with("well_weapon_field.gd") and not c.is_queued_for_deletion():
				fields += 1
		stats.fields += fields
		stats.most_fields = maxi(int(stats.most_fields), fields)
		stats.frames += 1
	var want := clampi(116 - weapon_shots, 0, 100) - synthetic
	for n in maxi(0, want):
		var from: Vector2 = points[rng.randi_range(0, points.size() - 1)]
		var shot: Node = run_state.spawn(PROJECTILE, from, {&"velocity": Vector2.RIGHT.rotated(rng.randf_range(0, TAU)) * 500.0})
		if shot != null:
			shot.set_meta(&"bench_synth", true)
		if n > 10:
			break


## The F2 console's routes: a big patch is swapped in, an AI-tier one added as a stage
## patch, a small one applied, all ignoring requires/conflicts.
func _force(run_state: Node, m: Resource) -> bool:
	if m.is_big:
		run_state.swap_big(m)
		return run_state.big == m
	if m.is_ai_tier():
		return run_state.add_ai(m, &"stage", true)
	return run_state.apply(m, true)
