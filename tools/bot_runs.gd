extends SceneTree
## End-to-end bot runs (M6 gate): full-length runs with the real tuning, started from
## the start screen and chained through the report's "New build" button.
##
##   godot --headless --path . --fixed-fps 60 -s tools/bot_runs.gd -- 1 2 3 4i 5i
##
## Each argument is a seed; a trailing "i" makes that run invincible, so the win path
## is played too. The bot plays, cards are picked at random from the seed, and runs on
## odd seeds roll one patch back after the third prompt. Telemetry goes to
## user://playtest/bot_runs.jsonl, never to the playtest file.
## Prints one "[botrun]" line per run and exits 1 if any run did not reach its report.

const MAX_FRAMES := 60 * 60 * 15      # 15 minutes of game time per run
const LOG := "user://playtest/bot_runs.jsonl"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var specs := OS.get_cmdline_user_args()
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
			game.report.new_build(int(_seed_of(specs[i + 1])))

	var added := _line_count() - lines_before
	var parsed := 0
	var text := FileAccess.get_file_as_string(LOG).strip_edges().split("\n")
	for line in text.slice(maxi(0, text.size() - added)):
		if JSON.parse_string(line) is Dictionary:
			parsed += 1
	if added != specs.size() or parsed != added:
		print("[botrun] telemetry: expected %d new lines, found %d (%d valid JSON)" % [specs.size(), added, parsed])
		failures += 1
	print("[botrun] summary: %d runs, %d failures, %d telemetry lines, %.1f s wall" % [
		specs.size(), failures, added, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failures > 0 else 0)


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
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var revert_planned := run_seed % 2 == 1
	for frame in MAX_FRAMES:
		if game.report.is_open():
			var rec: Dictionary = game.run_loop.record
			var picks: Array = (rec.prompts as Array).map(func(p: Dictionary) -> String: return p.pick)
			return "[botrun] seed=%d%s outcome=%s time=%.1fs version=%s kills=%d prompts=%s reverts=%d rc=%s" % [
				run_seed, " (invincible)" if invincible else "", rec.outcome, rec.duration, rec.version,
				rec.kills, picks, rec.reverts_used, rec.reached_release_candidate]
		if game.prompt_panel.can_choose():
			game.prompt_panel.choose(rng.randi_range(0, game.prompt_panel.offer.cards.size() - 1))
		elif revert_planned and game.director.prompt_index >= 3 and game.director.pending == null \
				and not run_state.stack.is_empty() and not paused:
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
