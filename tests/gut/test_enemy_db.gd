extends GutTest
## M43.1: one enemy list (EnemyDB, PLAN v9 1.3) and the walker split into per-archetype
## scripts. A pure refactor: the hashes prove the behaviour, these tests the shape.

const NAMES: Array[StringName] = [&"chaser", &"shooter", &"tank", &"bomber", &"lancer"]
const FIVE := "&\"chaser\",\\s*&\"shooter\",\\s*&\"tank\",\\s*&\"bomber\",\\s*&\"lancer\""
const THREE := "(&\"(chaser|shooter|tank|bomber|lancer)\",\\s*){2}&\"(chaser|shooter|tank|bomber|lancer)\""
const WALKER := "res://entities/enemy_walker.gd"


func test_the_lists() -> void:
	assert_eq(EnemyDB.BASES, NAMES, "the legacy order")
	assert_eq(EnemyDB.VARIANTS, [&"splitter"] as Array[StringName], "M47: the splitter")
	assert_eq(EnemyDB.base_of(&"splitter"), &"chaser")
	assert_eq(EnemyDB.base_of(&"tank"), &"tank")
	assert_eq(EnemyDB.base_of(&"nope"), &"")
	assert_null(EnemyDB.variant(&"chaser"))
	assert_eq(EnemyDB.variant(&"splitter").problems(), [] as Array[String])
	var all := EnemyDB.all()
	var want: Array[StringName] = EnemyDB.BASES + EnemyDB.VARIANTS
	assert_eq(all, want)
	assert_true(all.is_typed())
	assert_eq(all.get_typed_builtin(), TYPE_STRING_NAME)
	all.append(&"extra")
	assert_eq(EnemyDB.BASES.size(), 5, "all() is a fresh array")
	assert_eq(EnemyDB.all().size(), 6)
	for id in NAMES:
		assert_true(EnemyDB.has(id), id)
	assert_false(EnemyDB.has(&"nope"))
	assert_false(EnemyDB.has(&""))


func test_unlocks_archetypes_is_the_alias() -> void:
	assert_eq(Unlocks.ARCHETYPES, EnemyDB.BASES)


func test_spawner_scenes_come_from_bases() -> void:
	assert_eq(Spawner.SCENES.keys(), Array(EnemyDB.BASES), "keys in BASES order")
	for id in EnemyDB.BASES:
		var scene: Variant = Spawner.SCENES[id]
		assert_true(scene is PackedScene, id)
		assert_eq((scene as PackedScene).resource_path, EnemyDB.scene_path(id), id)
		assert_true(ResourceLoader.exists(EnemyDB.scene_path(id)), id)
	assert_eq(EnemyDB.scene_path(&"nope"), "")


func test_one_list_in_the_code() -> void:
	var five := RegEx.create_from_string(FIVE)
	var three := RegEx.create_from_string(THREE)
	var preload_scene := RegEx.create_from_string("preload\\(\"res://entities/enemy_")
	var lists: Array[String] = []
	var preloads: Array[String] = []
	for path in _scripts("res://"):
		var text := FileAccess.get_file_as_string(path)
		if five.search(text) != null or three.search(text) != null:
			lists.append(path)
		if not path.begins_with("res://enemies/") and preload_scene.search_all(text).size() > 1:
			preloads.append(path)
	assert_eq(lists, ["res://enemies/enemy_db.gd"] as Array[String], "the enemy list lives in EnemyDB only")
	assert_eq(preloads, [] as Array[String], "no second dictionary of enemy scenes")
	assert_false((Cue as GDScript).get_script_constant_map().has("ARCHETYPES"), "cue.gd reads EnemyDB")


func test_cues_and_sessions_read_all() -> void:
	for id in EnemyDB.all():
		assert_eq(Cue.parse("at 5: spawn %s 1" % id).problem, "", id)
	var bad := "at 5: spawn nope 1"
	assert_eq(Cue.parse(bad).problem, "cue '%s': spawn what?" % bad)
	var s := SessionDef.new()
	s.id = &"t"
	s.enemies = [&"nope"] as Array[StringName]
	s.spawn_weights = {"nope": 1.0}
	var problems := s.problems()
	assert_has(problems, "session t: unknown enemy nope")
	assert_has(problems, "session t: spawn_weights: unknown enemy nope")
	s.enemies = EnemyDB.all()
	s.spawn_weights = {}
	for id in EnemyDB.all():
		s.spawn_weights[String(id)] = 1.0
	for p in s.problems():
		assert_false(p.contains("unknown enemy"), p)


func test_the_walker_split() -> void:
	var base: GDScript = load(WALKER)
	assert_eq(base, EnemyWalker)
	for id: StringName in [&"bomber", &"lancer"]:
		var script := _scene_script(id)
		assert_eq(script.resource_path, "res://entities/enemy_%s.gd" % id, id)
		assert_eq(script.get_base_script(), EnemyWalker, id)
	for id: StringName in [&"chaser", &"tank"]:
		assert_eq(_scene_script(id).resource_path, WALKER, id)
	for line in FileAccess.get_file_as_string(WALKER).split("\n"):
		var code := line.get_slice("#", 0)
		assert_false(code.contains("Lance"), line)
		for word in ["bomber", "lancer", "fuse"]:
			assert_false(code.to_lower().contains(word), line)
	for id in [&"chaser", &"tank", &"bomber", &"lancer"]:
		var e: Node = (Spawner.SCENES[id] as PackedScene).instantiate()
		add_child_autofree(e)
		assert_eq(e.get(&"archetype"), id)
		assert_true(e.has_method(&"contact_reach"), id)
		assert_gt(float(e.call(&"contact_reach")), 0.0, id)


func _scene_script(id: StringName) -> GDScript:
	var e: Node = (Spawner.SCENES[id] as PackedScene).instantiate()
	var script: GDScript = e.get_script()
	e.free()
	return script


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
