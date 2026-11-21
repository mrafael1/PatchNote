extends GutTest
## M26: the genre interface and per-genre takes (PLAN v5 1.1 and 1.2).

const Fx := preload("res://tests/gut/fixtures.gd")
const SHELL_PATHS: Array[String] = ["res://main.gd", "res://ui/", "res://director/",
		"res://devsession/", "res://core/"]

var _fx_genre: GenreDef


func after_each() -> void:
	if _fx_genre:
		GenreDB.unregister(_fx_genre)
		_fx_genre = null
	Main.next_genre = &""
	RunState.reset(0)
	RunState.world = null


func _register_fx_genre() -> StringName:
	_fx_genre = Fx.make_genre()
	GenreDB.register(_fx_genre)
	return _fx_genre.id


# --- GenreDB and RunState.genre -----------------------------------------------

func test_the_first_genre_is_topdown_and_valid() -> void:
	var g := GenreDB.get_genre(&"topdown")
	assert_not_null(g)
	assert_true(g.playable)
	assert_eq(g.title, "Top-down shooter")
	assert_eq(g.genre_script, TopdownGenre)
	assert_eq(GenreDB.default_id(), &"topdown")
	assert_eq(GenreDB.playable_ids(), [&"topdown"] as Array[StringName])
	for each in GenreDB.all:
		assert_eq(GenreDB.problems(each), [] as Array[String], String(each.id))
	assert_string_contains(GenreDB.summary_line(), "[genres] 1: topdown")


func test_reset_sets_the_genre_or_falls_back_to_the_default() -> void:
	RunState.reset(3)
	assert_eq(RunState.genre, &"topdown")
	RunState.reset(3, &"no_such_genre")
	assert_eq(RunState.genre, &"topdown")
	var fx := _register_fx_genre()
	assert_eq(GenreDB.default_id(), &"topdown", "a non-Playable genre is never the default")
	RunState.reset(3, fx)
	assert_eq(RunState.genre, fx)


## PLAN v5 1.1: the shell never branches on a genre id.
func test_the_shell_never_names_a_genre() -> void:
	var files: Array[String] = []
	for path in SHELL_PATHS:
		if path.ends_with("/"):
			files.append_array(_scripts(path))
		elif FileAccess.file_exists(path):
			files.append(path)
	assert_gt(files.size(), 20)
	for g in GenreDB.all:
		var regex := RegEx.create_from_string("(?i)\\b" + String(g.id))
		for path in files:
			if path == "res://core/genre_db.gd":
				continue
			if regex.search(FileAccess.get_file_as_string(path)):
				fail_test("%s names genre '%s'" % [path, g.id])
	pass_test("%d shell files checked" % files.size())


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for entry in DirAccess.get_files_at(dir):
		if entry.get_extension() in ["gd", "tscn", "tres"]:
			out.append(dir + entry)
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + sub + "/"))
	return out


# --- Takes -------------------------------------------------------------------

func test_every_offerable_patch_is_a_card_with_a_take_per_playable_genre() -> void:
	var offerable := MutationDB.offerable()
	assert_eq(offerable.size(), 7)
	for m in offerable:
		assert_false(m.is_legacy(), "%s is a plain card" % m.id)
		assert_eq(m.get_script(), Mutation)
		for g in GenreDB.playable_ids():
			var take := m.take_for(g)
			assert_not_null(take, "%s has a %s take" % [m.id, g])
			if take == null:
				continue
			assert_true(take is PatchTake)
			assert_eq(take.patch, m)
			assert_eq(take.id, m.id)
			assert_eq(take.genre, g)
			assert_eq(take.get_script().resource_path, "res://mutations/%s/%s.gd" % [m.id, g])
			assert_true(m.has_take(g))
		assert_eq(MutationDB.problems(m), [] as Array[String], String(m.id))


func test_parked_patches_keep_their_own_scripts() -> void:
	for m in MutationDB.all:
		if m.parked:
			assert_true(m.is_legacy(), "%s still runs its own script" % m.id)
			assert_true(m.takes.is_empty())
			assert_eq(MutationDB.problems(m), [] as Array[String], String(m.id))


func test_problems_name_missing_takes_and_genre_id_clashes() -> void:
	var card := Mutation.new()
	card.id = &"fx_card"
	assert_has(MutationDB.problems(card), "Mutation 'fx_card' has no take for the playable genre 'topdown'")
	card.parked = true
	assert_eq(MutationDB.problems(card), [] as Array[String], "a parked card may have no take")
	var clash := Mutation.new()
	clash.id = &"topdown"
	clash.parked = true
	assert_has(MutationDB.problems(clash), "Mutation id 'topdown' is also a genre id")
	var legacy := Fx.make(Fx.FxRules, &"fx_rules")
	assert_true(legacy.is_legacy())
	assert_true(legacy.has_take(&"any_genre"), "a legacy script runs in every genre")
	assert_eq(MutationDB.problems(legacy), [] as Array[String], "only a legacy card on disk must be parked")


func test_hooks_forward_to_the_take_and_revert_strips_it() -> void:
	RunState.reset(5)
	var b1 := MutationDB.get_mutation(&"motion_time")
	var take := b1.take_for(&"topdown")
	assert_true(RunState.apply(b1))
	assert_true(RunState.rules.time_follows_motion, "apply_rules forwarded")
	assert_gt(take.connection_count(), 0, "enable forwarded")
	var owners: Array = []
	for list: Array in RunState.snapshot().connections.values():
		owners.append_array(list)
	assert_true(owners.any(func(o: String) -> bool: return o.begins_with("motion_time/topdown.")),
			"the snapshot counts take connections: %s" % [owners])
	RunState.revert(b1)
	assert_eq(take.connection_count(), 0, "disable forwarded")
	assert_false(RunState.rules.time_follows_motion)
	assert_eq(RunState.snapshot().connections, {})


func test_a_patch_with_no_take_does_nothing_and_is_never_offered() -> void:
	var fx := _register_fx_genre()
	RunState.reset(5, fx)
	var before := RunState.snapshot()
	var b1 := MutationDB.get_mutation(&"motion_time")
	assert_false(b1.has_take(fx))
	assert_true(RunState.apply(b1, true))
	var after := RunState.snapshot()
	assert_eq(after.rules, before.rules)
	assert_eq(after.connections, before.connections)
	assert_eq(b1.take_for(&"topdown").connection_count(), 0)
	RunState.revert(b1)

	var director := AiDirector.new()
	add_child_autofree(director)
	director.set_physics_process(false)
	var offer := director.get_offer({})
	for m in offer.cards:
		assert_true(m.has_take(fx), "%s offered without a take" % m.id)
	assert_eq(offer.cards.size(), 0, "no disk patch has a take for the test genre")


# --- The shell -----------------------------------------------------------------

func test_main_forwards_to_the_topdown_genre() -> void:
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	assert_true(game.genre is TopdownGenre)
	assert_eq(game.genre.def, GenreDB.get_genre(&"topdown"))
	var genre := game.genre as TopdownGenre
	assert_eq(game.arena, genre.arena)
	assert_eq(game.spawner, genre.spawner)
	assert_eq(game.run_loop, genre.run_loop)
	assert_eq(game.turn_clock, genre.turn_clock)
	assert_eq(game.player, genre.player)
	assert_eq(game.camera, genre.camera)
	assert_eq(game.world, RunState.world)
	assert_eq(game.get_node("Genre/Arena"), game.arena)
	assert_eq(game.run_loop.director, game.director)


## PLAN v5 8 q4: the shell starts and ends a run of a genre it knows nothing about.
func test_the_shell_runs_a_genre_it_knows_nothing_about() -> void:
	var fx := _register_fx_genre()
	Main.next_genre = fx
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(3)
	assert_eq(RunState.genre, fx)
	assert_eq(Main.next_genre, &"", "the choice is used once")
	assert_true(game.genre is Fx.FxGenre)
	assert_true(game.genre.began, "begin_run was called")
	assert_null(game.arena)
	assert_null(game.player)
	assert_null(game.run_loop)
	assert_null(game.camera)
	assert_eq(game.world, RunState.world)
	game.spawn_wave()   # a genre without one: nothing happens
	assert_false(game.report.is_open())
	(game.genre as Fx.FxGenre).finish(&"win")
	await wait_physics_frames(2)
	assert_true(game.report.is_open(), "run_ended opens the report")
	assert_true(game.genre.is_over())
