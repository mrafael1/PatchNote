extends SceneTree
## End-to-end bot runs (M6 gate): full-length runs with the real tuning, started from
## the start screen and chained through the report's "New build" button.
##
##   godot --headless --path . --fixed-fps 60 -s tools/bot_runs.gd -- 1 2 3 4i 5i
##
## Each argument is a seed; a trailing "i" makes that run invincible, so the win path
## is played too. Options (any position):
##   --set=<tuning var>=<value>   override a Tuning value for every run (retune sweeps),
##                                e.g. --set=prompt_min_gap=90
##   --set=<mutation id>.<var>=<value>   override a number on that patch's take for the
##                                run's genre (a parked legacy patch: on its resource),
##                                e.g. --set=explode_on_hit.radius=90
##   --big=<mutation id>          start every run with that parked big patch in the slot
##                                (PLAN v5 1.3: the slot is a test seam; nothing swaps it)
##   --apply=<mutation id>        apply that small patch at the start of every run, as if
##                                picked (M33 parity: a piece's own effect, without the
##                                offer pool's draws changing with the pool's size)
##   --log=<path>                 write telemetry there instead (parallel sweeps)
##   --save=<path>                play every run from that save, read-only: each run sees
##                                the same snapshot and nothing is written (PLAN v5 4.6)
##   --keep-save                  with --save: chain the runs through the file (each run's
##                                end is written, as in the real game)
##   --fresh                      start from a new save (v0.0.0) instead of the file, or,
##                                without --save, instead of everything unlocked
##   --rework-chance=<0..1>       in a fork session that offers Rework, rework instead of
##                                picking with this chance (default 0.2, PLAN v6 5); a
##                                REWORK-only session reworks or keeps, 50/50
##   --ship=<id>,<id>             ship these changes into the save before the first run,
##                                e.g. --fresh --ship=basic_movement,basic_world plays the
##                                v0.0.2 run instead of the smoke tests (PLAN v5 4.8)
## Without --save or --fresh the save is inert (everything unlocked, no file), as in tests.
## With a live chain (--keep-save) the report's button opens the dev session (PLAN v5
## 4.6): the bot picks a card at random from the run's seed and presses "Play"; one
## "[botrun] session" line per session.
## The real save file is never used: --save must name another path.
## The bot plays and cards are picked at random from the seed. Rollbacks are parked
## (PLAN v5 1.3): the bot never rolls anything back. Even seeds leave notes on the
## report (keep the first patch,
## cut the second). Telemetry goes to user://playtest/bot_runs.jsonl, never to the
## playtest file.
## Prints one "[botrun]" line per run and exits 1 if any run did not reach its report,
## saw a BIG prompt, or rolled anything back (both are parked in v5).

const MAX_FRAMES := 60 * 60 * 45      # 45 real minutes at 60 physics frames a second (PLAN v4 9.4)
const DEFAULT_LOG := "user://playtest/bot_runs.jsonl"

var LOG := DEFAULT_LOG
## core/save_game.gd, loaded in _run: naming SaveGame (or loading it this early) would
## compile it before the autoloads exist.
var save: GDScript
var start_big := &""
var start_apply := &""
var save_arg := ""
var keep_save := false
var fresh := false
var ship_ids := PackedStringArray()
var rework_chance := 0.2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var specs := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--set="):
			if not _override(arg.trim_prefix("--set=")):
				print("[botrun] FAILED: bad override %s" % arg)
				quit(1)
				return
		elif arg.begins_with("--big="):
			start_big = StringName(arg.trim_prefix("--big="))
			# Untyped: naming class Mutation here would compile it before the autoloads exist.
			var big: Resource = root.get_node("MutationDB").get_mutation(start_big)
			if big == null or not big.get(&"is_big"):
				print("[botrun] FAILED: no big patch %s" % start_big)
				quit(1)
				return
		elif arg.begins_with("--apply="):
			start_apply = StringName(arg.trim_prefix("--apply="))
			var small: Resource = root.get_node("MutationDB").get_mutation(start_apply)
			if small == null or small.get(&"is_big") or small.get(&"parked"):
				print("[botrun] FAILED: no small patch %s" % start_apply)
				quit(1)
				return
		elif arg.begins_with("--log="):
			LOG = arg.trim_prefix("--log=")
		elif arg.begins_with("--save="):
			save_arg = arg.trim_prefix("--save=")
		elif arg == "--keep-save":
			keep_save = true
		elif arg == "--fresh":
			fresh = true
		elif arg.begins_with("--rework-chance="):
			rework_chance = float(arg.trim_prefix("--rework-chance="))
		elif arg.begins_with("--ship="):
			ship_ids = arg.trim_prefix("--ship=").split(",", false)
		else:
			specs.append(arg)
	if specs.is_empty():
		specs = PackedStringArray(["1", "2", "3", "4i", "5i"])
	var telemetry: GDScript = load("res://systems/telemetry.gd")
	telemetry.log_path = LOG
	if not _set_up_save():
		quit(1)
		return
	var lines_before := _line_count()
	var failures := 0
	var started := Time.get_ticks_msec()

	var start: Node = load("res://ui/start_screen.tscn").instantiate()
	root.add_child(start)
	current_scene = start
	await process_frame
	start.seed_field.text = _seed_of(specs[0])
	start.start()
	var pending_sessions := 0
	if start.dev_flow.is_open():   # the save had a pending session (PLAN v5 1.5)
		pending_sessions = 1
		print(await _answer_session(start.dev_flow, int(_seed_of(specs[0]))))

	for i in specs.size():
		var spec := specs[i]
		var game := await _wait_for_game(null if i == 0 else current_scene)
		if game == null:
			print("[botrun] seed=%s FAILED: game scene never loaded" % spec)
			failures += 1
			break
		var run_seed := int(_seed_of(spec))
		var result := await _play(game, run_seed, spec.ends_with("i"))
		if result == "" or result.contains(" FAILED"):
			failures += 1
		print(result if result != "" else "[botrun] seed=%d FAILED: no report after %d frames" % [run_seed, MAX_FRAMES])
		if i + 1 < specs.size():
			if not game.report.is_open():
				game.report.open(&"lose", {})   # keep the chain going after a failure
			if run_seed % 2 == 0:
				var ids: Array = game.report.rateable_ids(game.run_loop.record)
				for k in mini(2, ids.size()):
					game.report.rate(ids[k], 1 if k == 0 else -1)
			game.report.new_build(int(_seed_of(specs[i + 1])))
			if game.dev_flow.is_open():
				var line := await _answer_session(game.dev_flow, run_seed)
				print(line)
				if line.contains(" FAILED"):
					failures += 1

	var added := _line_count() - lines_before
	var runs := 0
	var notes := 0
	var sessions := 0
	var text := FileAccess.get_file_as_string(LOG).strip_edges().split("\n")
	for line in text.slice(maxi(0, text.size() - added)):
		var d: Variant = JSON.parse_string(line)
		if d is Dictionary:
			if d.get("type") == "run":
				runs += 1
			elif d.get("type") == "notes":
				notes += 1
			elif d.get("type") == "session":
				sessions += 1
	# One run line per run; one notes line per "New build" (every run but the last).
	# A live chain plays one dev session after every run but the last.
	var sessions_expected := specs.size() - 1 + pending_sessions if save.call(&"is_live") else 0
	if sessions != sessions_expected:
		print("[botrun] telemetry: expected %d session lines, found %d" % [sessions_expected, sessions])
		failures += 1
	if runs != specs.size() or notes != specs.size() - 1:
		print("[botrun] telemetry: expected %d run and %d notes lines, found %d and %d (%d lines)" % [
			specs.size(), specs.size() - 1, runs, notes, added])
		failures += 1
	if keep_save:
		var state: Dictionary = save.call(&"state")
		print("[botrun] save: %s runs=%d wins=%d version=%s genres=%s shipped=%s look=%s sessions=%d forks=%s" % [
			save_arg, state.runs, state.wins, save.call(&"version").label(), state.genres, state.shipped,
			state.look, (state.sessions as Array).size(), load("res://devsession/dev_session.gd").call(&"answers")])
	print("[botrun] summary: %d runs, %d failures, %d telemetry lines, %.1f s wall" % [
		specs.size(), failures, added, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failures > 0 else 0)


## "name=value" onto the Tuning autoload; value is parsed as a Godot literal.
func _override(pair: String) -> bool:
	var at := pair.find("=")
	if at <= 0:
		return false
	var tuning: Object = root.get_node("Tuning")
	var key := pair.left(at)
	if key.contains("."):   # <mutation id>.<var>: on its take for the run's genre (PLAN v5 1.2)
		# Untyped: naming Mutation here would compile it before the autoloads exist.
		var m: Object = root.get_node("MutationDB").get_mutation(StringName(key.get_slice(".", 0)))
		key = key.get_slice(".", 1)
		if m == null:
			return false
		var take: Object = m.call(&"take_for", root.get_node("RunState").genre)
		tuning = take if take != null else m
	var value: Variant = str_to_var(pair.substr(at + 1))
	if not key in tuning or value == null:
		return false
	var current: Variant = tuning.get(key)
	if current is Array and value is Array:
		(current as Array).assign(value)
	elif current is float and (value is int or value is float):
		tuning.set(key, float(value))
	elif typeof(current) == typeof(value):
		tuning.set(key, value)
	else:
		return false
	print("[botrun] tuning %s = %s" % [pair.left(at), tuning.get(key)])
	return true


func _seed_of(spec: String) -> String:
	return spec.trim_suffix("i")


func _wait_for_game(previous: Node) -> Node:
	for f in 300:
		await process_frame
		var scene := current_scene
		if scene != null and scene != previous and scene.get(&"run_loop") != null:
			await physics_frame
			return scene
	return null


## Plays one run to its report. Returns the summary line, or "" on timeout.
func _play(game: Node, run_seed: int, invincible: bool) -> String:
	var run_state := root.get_node("RunState")
	if run_state.run_seed != run_seed:
		return "[botrun] seed=%d FAILED: game started with seed %d" % [run_seed, run_state.run_seed]
	run_state.invincible = invincible
	game.player.set_bot(true)
	if start_big != &"":
		run_state.swap_big(root.get_node("MutationDB").get_mutation(start_big))
	if start_apply != &"":
		run_state.apply(root.get_node("MutationDB").get_mutation(start_apply))
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	for frame in MAX_FRAMES:
		if game.report.is_open():
			var rec: Dictionary = game.run_loop.record
			var picks: Array = (rec.prompts as Array).map(func(p: Dictionary) -> String: return p.pick)
			var big_prompts := (rec.big_offers as Array).size()
			var fail := " FAILED: %d BIG prompts" % big_prompts if big_prompts > 0 else ""
			if rec.reverts_used > 0:
				fail += " FAILED: %d rollbacks" % rec.reverts_used
			return "[botrun] seed=%d%s%s outcome=%s time=%.1fs real=%.1fs genre=%s version=%s build=%s %s kills=%d prompts=%s big=%s genres=%s hits=%s kinds=%s reverts=%d ai=%s rc=%s agenda=%d first_offer_%s" % [
				run_seed, " (invincible)" if invincible else "", fail, rec.outcome, rec.duration, rec.real_duration,
				rec.genre, rec.game_version, rec.version, load("res://core/unlocks.gd").call(&"summary"), rec.kills, picks, rec.final_big if rec.final_big != "" else "-", rec.genre_seconds,
				rec.genre_hits, rec.genre_hits_by_kind, rec.reverts_used, _ai_line(rec), rec.reached_release_candidate,
				rec.agenda_cards, _first_line(game)]
		if game.prompt_panel.can_choose():
			game.prompt_panel.choose(rng.randi_range(0, game.prompt_panel.offer.cards.size() - 1))
		await physics_frame
	return ""


## Answers a dev session (PLAN v5 4.6, v6 5): a card at random from the seed, or, where
## Rework is offered, a random swap (--rework-chance; 50/50 against "Keep it as it is"
## in a REWORK-only session); then "Play" on the patch notes (or on a session with
## nothing to ship). Returns the summary line.
func _answer_session(flow: Node, run_seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 7919 + 17
	var session: RefCounted = flow.session
	var rework_only: bool = session.shape == &"rework"
	for f in 600:
		if flow.screen.can_pick():
			if flow.screen.has_rework_card() and rng.randf() < rework_chance:
				flow.screen.open_rework()
			else:
				flow.screen.pick(rng.randi_range(0, (session.cards as Array).size() - 1))
		elif flow.screen.list_ready():
			var targets: Array = flow.screen.rework_targets()
			if rework_only and rng.randf() < 0.5:
				flow.screen.press_list_button()   # keep it as it is
				return _session_line(session)
			var t: Array = targets[rng.randi_range(0, targets.size() - 1)]
			flow.screen.rework(t[0], t[1])
		elif flow.screen.is_open() and (session.cards as Array).is_empty() and not rework_only:
			flow.screen.play()
			return _session_line(session)
		elif flow.notes.is_open():
			var line := _session_line(session)
			flow.notes.play()
			return line
		await process_frame
	return "[botrun] session FAILED: never finished (%s)" % [session.shape if session else "no session"]


func _session_line(session: RefCounted) -> String:
	var e: Dictionary = session.log_entry()
	return "[botrun] session=%d after_run=%d kind=%s fork=%s cards=%s pick=%s shelved=%s agenda=%s ai_ship=%s ai_fork=%s rework=%s kept=%s version=%s->%s" % [
		session.number, session.after_run, e.shape, e.fork if e.fork != "" else "-", e.cards,
		e.pick if e.pick != "" else "-", e.shelved, e.agenda if e.agenda != "" else "-",
		e.ai_ship if e.ai_ship != "" else "-", e.ai_fork if e.ai_fork != "" else "-",
		e.rework if e.rework != "" else "-", e.kept,
		session.version_before.label(), session.version_after().label()]


## "id+@time,id-rollback@time" from the record's ai_events; "-" when there are none.
func _ai_line(rec: Dictionary) -> String:
	var parts: Array[String] = []
	for e: Dictionary in rec.get("ai_events", []):
		parts.append("%s%s@%.0f" % [e.id, "+" if e.op == "add" else "-" + String(e.reason), e.time])
	return ",".join(parts) if not parts.is_empty() else "-"


## The save the runs play from (see the header). The start screen is told not to make
## the real save live. Returns false (and says why) on a bad combination.
func _set_up_save() -> bool:
	save = load("res://core/save_game.gd")
	var start_script: GDScript = load("res://ui/start_screen.gd")
	start_script.save_live = false
	if save_arg != "" and save_arg == save.DEFAULT_PATH:
		print("[botrun] FAILED: --save must not be the real save (%s)" % save_arg)
		return false
	if keep_save:
		if save_arg == "":
			print("[botrun] FAILED: --keep-save needs --save=<path>")
			return false
		save.call(&"go_live", save_arg, fresh)
	elif save_arg != "" or fresh:
		save.call(&"use_snapshot", save_arg, fresh)
	else:
		save.call(&"go_inert")
	if save.read_only:
		print("[botrun] FAILED: %s is from a newer build" % save_arg)
		return false
	for id in ship_ids:
		var c: Resource = root.get_node("ChangeDB").get_change(StringName(id))
		if c == null or save.unlock_all:
			print("[botrun] FAILED: cannot ship %s (%s)" % [id, "inert save" if c else "no such change"])
			return false
		save.call(&"ship", c.id, c.bump)
	print("[botrun] save: %s" % ("inert" if save.unlock_all else "%s%s%s" % [
		save_arg if save_arg != "" else "in memory", " (fresh)" if fresh else "",
		", chained" if keep_save else ", read-only"]))
	return true


func _line_count() -> int:
	if not FileAccess.file_exists(LOG):
		return 0
	var text := FileAccess.get_file_as_string(LOG).strip_edges()
	return 0 if text == "" else text.split("\n").size()


func _first_line(game: Node) -> String:
	for e: Dictionary in root.get_node("RunState").run_log:
		if e.event == &"prompt":
			return "agenda=%s" % [e.get("agenda", [])]
	return ""
