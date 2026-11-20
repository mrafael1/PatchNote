extends SceneTree
## End-to-end bot runs (M6 gate): full-length runs with the real tuning, started from
## the start screen and chained through the report's "New build" button.
##
##   godot --headless --path . --fixed-fps 60 -s tools/bot_runs.gd -- 1 2 3 4i 5i
##
## Each argument is a seed; a trailing "i" makes that run invincible, so the win path
## is played too. Options (any position):
##   --set=<tuning var>=<value>   override a Tuning value for every run (retune sweeps),
##                                e.g. --set=prompt_min_gap=90 --set=big_prompt_after=[1,3]
##   --set=<mutation id>.<var>=<value>   override a number on a mutation resource,
##                                e.g. --set=turn_mode.turn_duration=0.2
##   --big=<mutation id>          start every run in that big patch (with
##                                --set=big_prompt_after=[] it stays: one genre per run)
##   --log=<path>                 write telemetry there instead (parallel sweeps)
## The bot plays, cards are picked at random from the seed, and runs on
## odd seeds roll one patch back after the third prompt; even seeds leave notes on the
## report (keep the first patch, cut the second). Telemetry goes to
## user://playtest/bot_runs.jsonl, never to the playtest file.
## Prints one "[botrun]" line per run and exits 1 if any run did not reach its report.

const MAX_FRAMES := 60 * 60 * 25      # 25 minutes at 60 physics frames a second per run
const DEFAULT_LOG := "user://playtest/bot_runs.jsonl"

var LOG := DEFAULT_LOG
var start_big := &""


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
		elif arg.begins_with("--log="):
			LOG = arg.trim_prefix("--log=")
		else:
			specs.append(arg)
	if specs.is_empty():
		specs = PackedStringArray(["1", "2", "3", "4i", "5i"])
	var telemetry: GDScript = load("res://systems/telemetry.gd")
	telemetry.log_path = LOG
	var lines_before := _line_count()
	var failures := 0
	var started := Time.get_ticks_msec()

	var start: Node = load("res://ui/start_screen.tscn").instantiate()
	root.add_child(start)
	current_scene = start
	await process_frame
	start.seed_field.text = _seed_of(specs[0])
	start.start()

	for i in specs.size():
		var spec := specs[i]
		var game := await _wait_for_game(null if i == 0 else current_scene)
		if game == null:
			print("[botrun] seed=%s FAILED: game scene never loaded" % spec)
			failures += 1
			break
		var run_seed := int(_seed_of(spec))
		var result := await _play(game, run_seed, spec.ends_with("i"))
		if result == "":
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

	var added := _line_count() - lines_before
	var runs := 0
	var notes := 0
	var text := FileAccess.get_file_as_string(LOG).strip_edges().split("\n")
	for line in text.slice(maxi(0, text.size() - added)):
		var d: Variant = JSON.parse_string(line)
		if d is Dictionary:
			if d.get("type") == "run":
				runs += 1
			elif d.get("type") == "notes":
				notes += 1
	# One run line per run; one notes line per "New build" (every run but the last).
	if runs != specs.size() or notes != specs.size() - 1:
		print("[botrun] telemetry: expected %d run and %d notes lines, found %d and %d (%d lines)" % [
			specs.size(), specs.size() - 1, runs, notes, added])
		failures += 1
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
	if key.contains("."):   # <mutation id>.<var>
		tuning = root.get_node("MutationDB").get_mutation(StringName(key.get_slice(".", 0)))
		key = key.get_slice(".", 1)
		if tuning == null:
			return false
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
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var revert_planned := run_seed % 2 == 1
	for frame in MAX_FRAMES:
		if game.report.is_open():
			var rec: Dictionary = game.run_loop.record
			var picks: Array = (rec.prompts as Array).map(func(p: Dictionary) -> String: return p.pick)
			var bigs: Array = (rec.big_offers as Array).map(func(p: Dictionary) -> String: return p.pick if p.pick != "" else "-")
			return "[botrun] seed=%d%s outcome=%s time=%.1fs real=%.1fs version=%s kills=%d prompts=%s big=%s genres=%s hits=%s kinds=%s reverts=%d rc=%s agenda=%d first_offer_%s" % [
				run_seed, " (invincible)" if invincible else "", rec.outcome, rec.duration, rec.real_duration,
				rec.version, rec.kills, picks, bigs, rec.genre_seconds, rec.genre_hits, rec.genre_hits_by_kind, rec.reverts_used,
				rec.reached_release_candidate,
				rec.agenda_cards, _first_line(game)]
		if game.prompt_panel.can_choose():
			game.prompt_panel.choose(rng.randi_range(0, game.prompt_panel.offer.cards.size() - 1))
		elif revert_planned and game.director.prompt_index >= 3 and game.director.pending == null \
				and not run_state.stack.is_empty() and not run_state.is_paused_except(&"turn"):
			if game.patch_history.open():
				var target: StringName = run_state.stack[rng.randi_range(0, run_state.stack.size() - 1)].id
				game.patch_history.press_revert(target)
				game.patch_history.press_revert(target)
				revert_planned = false
		await physics_frame
	return ""


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
