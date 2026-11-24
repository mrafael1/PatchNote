extends RefCounted
## M44 (PLAN v9 M44, "path = '' leaves every WorldRules field at its value"): the one
## procedure that dumps a Stage 1 session's live rules, shared by the fixture recorder
## (.check/ref_m43.3/dump_rules.gd, run once on the m43.3 tree) and test_weapons.gd, so
## the two cannot drift. Inert save, every Stage 1 fork answered from seed 1 as
## tools/run_hash.gd does, jump, seed 1, the stage card skipped, 2 physics frames.

const STAGE1: Array[StringName] = [&"s1_00_nothing", &"s1_01_move", &"s1_02_enemies", &"s1_03_shooting",
		&"s1_04_level", &"s1_05_wrong", &"s1_06_playground"]
const FIXTURE := "res://tests/gut/rules_stage1_m43_3.json"
const SEED := 1


## Every script property of `rules`, as var_to_str.
static func fields(rules: Resource) -> Dictionary:
	var d := {}
	for p: Dictionary in rules.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			d[p.name] = var_to_str(rules.get(p.name))
	return d


## Boots session `id` under `parent` and returns the game (the caller frees it).
static func boot(tree: SceneTree, parent: Node, id: StringName) -> Node:
	var root := tree.root
	var save: GDScript = load("res://core/save_game.gd")
	var db: Node = root.get_node("CampaignDB")
	save.call(&"go_inert")
	_answer_forks(root, save)
	db.set(&"active", true)
	db.call(&"jump_to", id)
	load("res://main.gd").set(&"next_seed", SEED)
	var game: Node = load("res://main.tscn").instantiate()
	parent.add_child(game)
	await tree.physics_frame
	var card: Variant = game.get(&"stage_card")
	if card != null and card.call(&"is_open"):
		card.call(&"skip")
	await tree.physics_frame
	await tree.physics_frame
	return game


## {"rules": fields, "base_rules": fields, "path": session path, "session": id} of the
## game booted for `id`. `inspect` (optional) is called with the game before it is freed.
static func dump(tree: SceneTree, parent: Node, id: StringName, inspect := Callable()) -> Dictionary:
	var game: Node = await boot(tree, parent, id)
	var run_state: Node = tree.root.get_node("RunState")
	var session: Resource = run_state.get(&"session")
	var out := {
		"session": String(session.get(&"id")) if session != null else "",
		"path": String(session.get(&"path")) if session != null else "<none>",
		"rules": fields(run_state.get(&"rules")),
		"base_rules": fields(run_state.get(&"base_rules")),
	}
	if inspect.is_valid():
		inspect.call(game)
	var debrief: Variant = game.get(&"debrief")
	if debrief != null and debrief.call(&"is_open"):
		debrief.call(&"close")
	parent.remove_child(game)
	game.free()
	await tree.process_frame
	return out


## The legacy loop's rules: a plain reset.
static func legacy(tree: SceneTree) -> Dictionary:
	var run_state: Node = tree.root.get_node("RunState")
	run_state.call(&"reset", SEED)
	return {"rules": fields(run_state.get(&"rules")), "base_rules": fields(run_state.get(&"base_rules"))}


static func _answer_forks(root: Node, save: GDScript) -> void:
	var change_db: Node = root.get_node("ChangeDB")
	var picks := {&"fork_mascot": SEED + 2, &"fork_dash": SEED, &"fork_dash_aim": SEED, &"fork_enemy": SEED + 1}
	for fork_id: StringName in picks:
		var f: Resource = change_db.call(&"get_fork", fork_id)
		var opts: Array = f.call(&"changes")
		var pick: Resource = opts[posmod(int(picks[fork_id]), opts.size())]
		save.call(&"ship", pick.get(&"id"), &"patch")
		if fork_id == &"fork_mascot":
			save.call(&"set_mascot", pick.get(&"take").get(&"id"))
