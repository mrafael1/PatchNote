extends SceneTree
## Same-run hash (PLAN v5 M26 gate): plays invincible bot runs and hashes the world once
## per second of game time, so a refactor that must not change play can be checked
## against a recording made before it.
##
##   godot --headless --path . --fixed-fps 60 -s tools/run_hash.gd -- --out=<file> [--seconds=120] 1 2 3 4
##   godot --headless --path . --fixed-fps 60 -s tools/run_hash.gd -- --compare=<file> 1 2 3 4
##   ... --stages=gauntlet   every run plays that stage set (PLAN v6 M34: the 3-stage hash)
##
## Each second hashes: the player position (to 0.01 px), every live entity's group
## kind and position (sorted), kills, the build number and the stack ids. Cards are
## picked by a generator seeded with the run seed, as in tools/bot_runs.gd. With
## --compare the run fails at the first second that differs and names it.
##
## Campaign sessions (PLAN v9, before M43: the m42.2 reference):
##   ... --campaign [--session=<id>[,<id>...]] [--out=<file> | --compare=<file>] 1 2 3 4
## Each seed plays each session once, jumped to on an inert save, invincible, from its
## start to its debrief (at most --seconds, default 300 here). Every fork is answered by
## the tool itself before the jump (mascot, dash, dash aim, enemy, all picked from the
## seed), so a later change to how a jump answers forks cannot move the hash. Without
## --session it plays s1_03_shooting, s1_04_level, s1_05_wrong and s1_06_playground. One
## line per session and seed: {"session", "seed", "hashes"}.
##
## M47 (PLAN v9 5, C2.8): --frames=<n> hashes every n unpaused game ticks instead of once
## per second (ticks under an open pick panel or card never count), the loop then bounded
## by game_time < --seconds. --answer=<fork>=<change> (repeatable) overrides the seed's
## answer, after the Stage 1 ones; a fork:fork_path session with no --answer gets option 0
## (Arsenal). In path sessions only (a tryout or a session with a path), open pick panels
## are chosen as bot_runs' _choose_pick does (pick_card on pick_rng), and the hash adds the
## live path, Loadout.summary(), the pick log and the pickups (count and positions);
## Stage 1 hashes are unchanged (G3/G4 refs stay valid).

var seconds := 120
var out_path := ""
var compare_path := ""
var campaign := false
var seconds_set := false
var session_ids: Array[StringName] = []
var frames_every := 0                ## --frames (M47): 0 = once per second
var answers := {}                    ## --answer (M47): fork id -> change id
const CAMPAIGN_SESSIONS: Array[StringName] = [&"s1_03_shooting", &"s1_04_level", &"s1_05_wrong",
		&"s1_06_playground"]
const CAMPAIGN_SECONDS := 300


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var seeds: Array[int] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--compare="):
			compare_path = arg.trim_prefix("--compare=")
		elif arg.begins_with("--stages="):
			load("res://levels/stage_set.gd").call(&"use_override", StringName(arg.trim_prefix("--stages=")))
		elif arg.begins_with("--seconds="):
			seconds = int(arg.trim_prefix("--seconds="))
			seconds_set = true
		elif arg == "--campaign":
			campaign = true
		elif arg.begins_with("--session="):
			for id in arg.trim_prefix("--session=").split(",", false):
				session_ids.append(StringName(id))
		elif arg.begins_with("--frames="):
			frames_every = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--look=") or arg == "--skins=off":
			pass   # read by main at boot (Skins.read_args: the Pixel preview / M48b's off switch, visual only)
		elif arg.begins_with("--answer="):
			var pair := arg.trim_prefix("--answer=").split("=")
			if pair.size() == 2:
				answers[StringName(pair[0])] = StringName(pair[1])
		else:
			seeds.append(int(arg))
	if seeds.is_empty():
		seeds = [1, 2, 3, 4]
	if campaign:
		await _run_campaign(seeds)
		return
	var expected := {}
	if compare_path != "":
		for line in FileAccess.get_file_as_string(compare_path).strip_edges().split("\n"):
			var d: Variant = JSON.parse_string(line)
			if d is Dictionary:
				expected[int(d.seed)] = d.hashes
	# Never the real playtest log or the real save: the runs are inert, as in M25.
	var telemetry: GDScript = load("res://systems/telemetry.gd")
	telemetry.log_path = "user://playtest/run_hash.jsonl"
	var start_script: GDScript = load("res://ui/start_screen.gd")
	start_script.save_live = false
	start_script.legacy_loop = true   # the v6 run loop (PLAN v8 1.2.7)
	load("res://core/save_game.gd").call(&"go_inert")
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
	if game.run_loop.stages != null and game.run_loop.stages.size() > 1:
		parts.append("s%d" % game.run_loop.stage_index)   # absent on one-stage runs: M33 hashes hold
	for m: Resource in run_state.stack:
		parts.append(String(m.id))
	return "|".join(parts).md5_text()


# --- Campaign sessions (PLAN v9: the m42.2 campaign hash) -----------------------------

func _run_campaign(seeds: Array[int]) -> void:
	if session_ids.is_empty():
		session_ids = CAMPAIGN_SESSIONS.duplicate()
	if not seconds_set:
		seconds = CAMPAIGN_SECONDS
	var expected := {}   ## "<session>:<seed>" -> hashes
	if compare_path != "":
		for line in FileAccess.get_file_as_string(compare_path).strip_edges().split("\n"):
			var d: Variant = JSON.parse_string(line)
			if d is Dictionary:
				expected["%s:%d" % [d.session, int(d.seed)]] = d.hashes
	var telemetry: GDScript = load("res://systems/telemetry.gd")
	telemetry.log_path = "user://playtest/run_hash.jsonl"
	var save: GDScript = load("res://core/save_game.gd")
	var db: Node = root.get_node("CampaignDB")
	db.set(&"_arg_read", true)   # this tool jumps itself; the game's own --session= reader stays off
	var main_script: GDScript = load("res://main.gd")
	var run_state := root.get_node("RunState")
	var lines: Array[String] = []
	var failures := 0
	var runs := 0
	for id in session_ids:
		if db.call(&"get_session", id) == null:
			print("[runhash] FAILED: no session %s" % id)
			quit(1)
			return
		for run_seed in seeds:
			save.call(&"go_inert")
			_answer_forks(save, run_seed)
			_answer_more(save, db.call(&"get_session", id))
			db.set(&"active", true)
			db.call(&"jump_to", id)
			main_script.set(&"next_seed", run_seed)
			var game: Node = load("res://main.tscn").instantiate()
			root.add_child(game)
			current_scene = game
			await physics_frame
			var card: Node = game.get(&"stage_card")   # PLAN v9 2: a stage card pauses the tree
			if card != null and card.call(&"is_open"):
				card.call(&"skip")
			if run_state.session == null or run_state.session.id != id:
				print("[runhash] session=%s seed=%d FAILED: the game runs another session" % [id, run_seed])
				quit(1)
				return
			var hashes := await _play_session(game, run_state)
			runs += 1
			lines.append(JSON.stringify({"session": String(id), "seed": run_seed, "hashes": hashes}))
			var tag := "session=%s seed=%d" % [id, run_seed]
			if compare_path != "":
				var want: Array = expected.get("%s:%d" % [id, run_seed], [])
				var diverged := -1
				for s in mini(want.size(), hashes.size()):
					if String(want[s]) != hashes[s]:
						diverged = s
						break
				if diverged < 0 and want.size() != hashes.size():
					diverged = mini(want.size(), hashes.size())
				if diverged >= 0:
					failures += 1
					print("[runhash] %s FAILED: diverges at second %d (%d recorded, %d now)" % [tag,
							diverged + 1, want.size(), hashes.size()])
				else:
					print("[runhash] %s same run over %d s" % [tag, hashes.size()])
			else:
				print("[runhash] %s recorded %d s kills=%d" % [tag, hashes.size(), run_state.kills])
			if game.debrief.is_open():
				game.debrief.close()
			root.remove_child(game)
			game.free()
			await process_frame
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("[runhash] summary: campaign, %d runs, %d failures" % [runs, failures])
	quit(1 if failures > 0 else 0)


## Answers every Stage 1 fork from the seed, the way a debrief pick would (shipped, and
## the mascot's body set), so the jump answers nothing itself.
func _answer_forks(save: GDScript, run_seed: int) -> void:
	var change_db: Node = root.get_node("ChangeDB")
	var picks := {&"fork_mascot": run_seed + 2, &"fork_dash": run_seed, &"fork_dash_aim": run_seed,
			&"fork_enemy": run_seed + 1}
	for fork_id: StringName in picks:
		var f: Resource = change_db.call(&"get_fork", fork_id)
		var opts: Array = f.call(&"changes")
		var pick: Resource = opts[posmod(int(picks[fork_id]), opts.size())]
		save.call(&"ship", pick.get(&"id"), &"patch")
		if fork_id == &"fork_mascot":
			save.call(&"set_mascot", pick.get(&"take").get(&"id"))


## M47: the --answer overrides, then fork_path for a fork:fork_path session (option 0).
func _answer_more(save: GDScript, session: Resource) -> void:
	var change_db: Node = root.get_node("ChangeDB")
	for fork_id: StringName in answers:
		var f: Resource = change_db.call(&"get_fork", fork_id)
		if f == null:
			continue
		for c: Resource in f.call(&"changes"):
			(save.call(&"state").shipped as Array).erase(String(c.get(&"id")))
		save.call(&"ship", answers[fork_id], &"patch")
	if String(session.get(&"path")).begins_with("fork:"):
		var f: Resource = change_db.call(&"get_fork", StringName(String(session.get(&"path")).trim_prefix("fork:")))
		if f != null and f.call(&"answer") == null:
			save.call(&"ship", (f.call(&"changes") as Array)[0].get(&"id"), &"patch")


static func _path_session(run_state: Node) -> bool:
	var s: Resource = run_state.session
	return s != null and (bool(s.get(&"tryout")) or String(s.get(&"path")) != "")


## M47: the path fields of a path session's hash.
func _path_hash(game: Node, run_state: Node) -> String:
	var runner: Node = game.get(&"path_runner")
	var parts: Array[String] = ["path=%s" % run_state.call(&"live_path")]
	var lo: Node = runner.call(&"loadout") if runner != null else null
	parts.append("lo=%s" % (lo.call(&"summary") if lo != null else "-"))
	var picks: Array[String] = []
	for e: Dictionary in run_state.run_log:
		if e.get("event") == &"pick":
			picks.append(String(e.get("pick", "")))
	parts.append("picks=%s" % ",".join(picks))
	var pk: Array[String] = []
	for p: Node in run_state.get_tree().get_nodes_in_group(&"pickup"):
		var pos: Vector2 = (p as Node2D).global_position
		pk.append("%.2f,%.2f" % [pos.x, pos.y])
	pk.sort()
	parts.append("pk%d:%s" % [pk.size(), ";".join(pk)])
	return "|".join(parts)


## One session, invincible bot, a hash per second of game time until the debrief opens.
func _play_session(game: Node, run_state: Node) -> Array[String]:
	run_state.invincible = true
	game.player.set_bot(true)
	if frames_every > 0:
		return await _play_session_frames(game, run_state)
	var hashes: Array[String] = []
	var next_second := 1.0
	var frames := 0
	while hashes.size() < seconds and not game.debrief.is_open() and frames < seconds * 60 * 4:
		if run_state.game_time >= next_second:
			next_second += 1.0
			hashes.append(_hash(game, run_state))
		await physics_frame
		frames += 1
	return hashes


## M47 (--frames): a hash every frames_every unpaused ticks while game_time < seconds; open
## pick panels chosen in path sessions; path fields in the hash there.
func _play_session_frames(game: Node, run_state: Node) -> Array[String]:
	var hashes: Array[String] = []
	var ticks := 0
	var frames := 0
	var path_session := _path_session(run_state)
	var bot: GDScript = load("res://tools/bot_runs.gd")
	while run_state.game_time < seconds and not game.debrief.is_open() and frames < seconds * 60 * 4:
		if path_session:
			var panel: Node = game.get(&"pick_panel")
			if panel != null and panel.call(&"can_choose"):
				var n: int = (panel.get(&"offer").get(&"cards") as Array).size()
				panel.call(&"choose", bot.call(&"pick_card", run_state.get(&"pick_rng"), n, ""))
		await physics_frame
		frames += 1
		if paused:
			continue
		ticks += 1
		if ticks % frames_every == 0:
			var h := _hash(game, run_state)
			if path_session:
				h = (h + "|" + _path_hash(game, run_state)).md5_text()
			hashes.append(h)
	return hashes
