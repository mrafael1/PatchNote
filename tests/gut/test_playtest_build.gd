extends GutTest
## M12 (PLAN v3): what the retune and the playtest build rely on. Real run time and
## hits per genre in the telemetry record, hits an invincible bot would have taken,
## and the boot line that marks big patches for the export check.

var player: Node2D
var health: Health


func before_each() -> void:
	RunState.reset(12)
	player = Node2D.new()
	player.add_to_group(&"player")
	add_child_autofree(player)
	health = Component.attach(player, Health) as Health
	health.base_max_hp = 5.0
	health.scales_with_enemy_rule = false
	health.invuln_time = 0.8


func after_each() -> void:
	RunState.reset(0)


func _hit() -> bool:
	return health.take(DamageInfo.make(1.0, &"contact", &"enemy"))


func _hits_logged() -> Array:
	return RunState.run_log.filter(func(e: Dictionary) -> bool: return e.event == &"player_hit")


func test_a_real_hit_is_logged_and_costs_hp() -> void:
	assert_true(_hit())
	assert_almost_eq(health.hp(), 4.0, 0.001)
	assert_eq(_hits_logged().size(), 1)
	assert_false(_hits_logged()[0].blocked)


func test_an_invincible_hit_is_logged_with_i_frames_and_costs_nothing() -> void:
	RunState.invincible = true
	assert_false(_hit(), "invincible: no damage applied")
	assert_almost_eq(health.hp(), 5.0, 0.001)
	assert_true(health.is_invulnerable(), "same i-frames as a real hit")
	assert_false(_hit(), "inside the i-frames")
	assert_eq(_hits_logged().size(), 1, "one would-be hit, not two")
	assert_true(_hits_logged()[0].blocked)
	RunState.game_time += 1.0
	_hit()
	assert_eq(_hits_logged().size(), 2, "after the i-frames the next would-be hit counts")


func test_grace_blocks_hits_without_logging_them() -> void:
	RunState.start_grace(1.0)
	assert_false(_hit())
	RunState.invincible = true
	assert_false(_hit())
	assert_eq(_hits_logged().size(), 0)


func test_genre_hits_follow_the_big_swaps() -> void:
	RunState.log_event(&"player_hit", {"amount": 1.0, "blocked": false})
	RunState.log_event(&"big_swap", {"from": "", "to": "motion_time", "dropped": []})
	RunState.log_event(&"player_hit", {"amount": 1.0, "blocked": true})
	RunState.log_event(&"player_hit", {"amount": 1.0, "blocked": false})
	RunState.log_event(&"big_swap", {"from": "motion_time", "to": "turn_mode", "dropped": []})
	assert_eq(Telemetry.genre_hits(), {"base": 1, "motion_time": 2, "turn_mode": 0})
	var rec := Telemetry.build_record(&"lose")
	assert_eq(rec.genre_hits, {"base": 1, "motion_time": 2, "turn_mode": 0})
	assert_eq(Telemetry.genre_hits().keys(), Telemetry.genre_seconds().keys(),
			"same keys, same order as genre_seconds")


func test_real_duration_counts_paused_frames_and_game_time_does_not() -> void:
	RunState.reset(12)
	await wait_physics_frames(10)
	RunState.set_pause(&"prompt", true)
	var game_before := RunState.game_time
	var frames_before := RunState.real_frames
	await wait_physics_frames(30)
	RunState.set_pause(&"prompt", false)
	assert_eq(RunState.game_time, game_before, "paused: no game time")
	assert_between(RunState.real_frames - frames_before, 29, 31, "paused frames still count")
	assert_almost_eq(RunState.real_time(), RunState.real_frames / float(Engine.physics_ticks_per_second), 0.0001)
	var rec := Telemetry.build_record(&"lose")
	assert_almost_eq(float(rec.real_duration), RunState.real_time(), 0.01)
	assert_gt(float(rec.real_duration), float(rec.duration))
	RunState.reset(13)
	assert_eq(RunState.real_frames, 0, "reset starts the count again")


func test_boot_line_lists_every_mutation_and_marks_big_patches() -> void:
	var line := MutationDB.summary_line()
	assert_string_starts_with(line, "[mutations] %d: " % MutationDB.all.size())
	var bigs := 0
	for m in MutationDB.all:
		if m.is_big:
			bigs += 1
			assert_string_contains(line, "%s (BIG)" % m.id)
		else:
			assert_string_contains(line, String(m.id))
			assert_false(line.contains("%s (BIG)" % m.id), "%s is small" % m.id)
	assert_eq(line.count("(BIG)"), bigs)
	assert_eq(bigs, 2, "v3 ships B1 and B2")


## Same seed, same run: bot sweeps compare configs seed by seed, and a playtest seed
## must replay. Gameplay draws only from RunState's seeded generators. Presentation
## (camera shake, the glitch shader) and the start screen's random seed are exempt.
func test_gameplay_has_no_unseeded_randomness() -> void:
	const EXEMPT := ["res://systems/camera_rig.gd", "res://systems/transition.gd", "res://main.gd",
			"res://core/run_state.gd", "res://systems/telemetry.gd"]
	var regex := RegEx.create_from_string(
			r"get_instance_id\(|(?<![\w.])(randf|randi|randf_range|randi_range|randfn|randomize)\(|\.(pick_random|shuffle)\(")
	var offenders: Array[String] = []
	for path in _scripts("res://"):
		if path in EXEMPT:
			continue
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if regex.search(line) and not line.strip_edges().begins_with("#"):
				offenders.append("%s: %s" % [path, line.strip_edges()])
	assert_eq(offenders, [] as Array[String])


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for entry in DirAccess.get_directories_at(dir):
		if entry.begins_with(".") or entry in ["addons", "tests", "builds", "tools"]:
			continue
		out.append_array(_scripts(dir.path_join(entry)))
	for entry in DirAccess.get_files_at(dir):
		if entry.ends_with(".gd"):
			out.append(dir.path_join(entry))
	return out
