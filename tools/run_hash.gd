extends SceneTree
## Same-run hash (PLAN v5 M26 gate): plays invincible bot runs and hashes the world once
## per second of game time, so a refactor that must not change play can be checked
## against a recording made before it.
##
##   godot --headless --path . --fixed-fps 60 -s tools/run_hash.gd -- --out=<file> [--seconds=120] 1 2 3 4
##   godot --headless --path . --fixed-fps 60 -s tools/run_hash.gd -- --compare=<file> 1 2 3 4
##
## Each second hashes: the player position (to 0.01 px), every live entity's group
## kind and position (sorted), kills, the build number and the stack ids. Cards are
## picked by a generator seeded with the run seed, as in tools/bot_runs.gd. With
## --compare the run fails at the first second that differs and names it.

var seconds := 120
var out_path := ""
var compare_path := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var seeds: Array[int] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--compare="):
			compare_path = arg.trim_prefix("--compare=")
		elif arg.begins_with("--seconds="):
			seconds = int(arg.trim_prefix("--seconds="))
		else:
			seeds.append(int(arg))
	if seeds.is_empty():
		seeds = [1, 2, 3, 4]
	var expected := {}
	if compare_path != "":
		for line in FileAccess.get_file_as_string(compare_path).strip_edges().split("\n"):
			var d: Variant = JSON.parse_string(line)
			if d is Dictionary:
				expected[int(d.seed)] = d.hashes
	var start: Node = load("res://ui/start_screen.tscn").instantiate()
	root.add_child(start)
	current_scene = start
	await process_frame
	start.seed_field.text = str(seeds[0])
	start.start()
	var lines: Array[String] = []
	var failures := 0
	for i in seeds.size():
		var game := await _wait_for_game(null if i == 0 else current_scene)
		if game == null:
			print("[runhash] seed=%d FAILED: no game" % seeds[i])
			quit(1)
			return
		var hashes := await _play(game, seeds[i])
		lines.append(JSON.stringify({"seed": seeds[i], "hashes": hashes}))
		if compare_path != "":
			var want: Array = expected.get(seeds[i], [])
			var diverged := -1
			for s in mini(want.size(), hashes.size()):
				if String(want[s]) != hashes[s]:
					diverged = s
					break
			if diverged < 0 and want.size() != hashes.size():
				diverged = mini(want.size(), hashes.size())
			if diverged >= 0:
				failures += 1
				print("[runhash] seed=%d FAILED: diverges at second %d" % [seeds[i], diverged + 1])
			else:
				print("[runhash] seed=%d same run over %d s" % [seeds[i], hashes.size()])
		else:
			print("[runhash] seed=%d recorded %d s" % [seeds[i], hashes.size()])
		if i + 1 < seeds.size():
			game.start_new_build(seeds[i + 1])
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("[runhash] summary: %d runs, %d failures" % [seeds.size(), failures])
	quit(1 if failures > 0 else 0)


func _wait_for_game(previous: Node) -> Node:
	for f in 300:
		await process_frame
		var scene := current_scene
		if scene != null and scene != previous and scene.get(&"run_loop") != null:
			await physics_frame
			return scene
	return null


func _play(game: Node, run_seed: int) -> Array[String]:
	var run_state := root.get_node("RunState")
	run_state.invincible = true
	game.player.set_bot(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var hashes: Array[String] = []
	var next_second := 1.0
	while hashes.size() < seconds and not game.report.is_open():
		if game.prompt_panel.can_choose():
			game.prompt_panel.choose(rng.randi_range(0, game.prompt_panel.offer.cards.size() - 1))
		if run_state.game_time >= next_second:
			next_second += 1.0
			hashes.append(_hash(game, run_state))
		await physics_frame
	return hashes


func _hash(game: Node, run_state: Node) -> String:
	var parts: Array[String] = []
	var p: Vector2 = game.player.global_position
	parts.append("p%.2f,%.2f" % [p.x, p.y])
	var ents: Array[String] = []
	for e: Node in run_state.live_entities():
		var pos: Vector2 = (e as Node2D).global_position
		var kind := "?"
		for g in [&"player", &"enemy", &"enemy_projectile", &"player_projectile"]:
			if e.is_in_group(g):
				kind = String(g)
		ents.append("%s%.2f,%.2f" % [kind, pos.x, pos.y])
	ents.sort()
	parts.append_array(ents)
	parts.append("k%d b%d" % [run_state.kills, run_state.build_number])
	for m: Resource in run_state.stack:
		parts.append(String(m.id))
	return "|".join(parts).md5_text()
