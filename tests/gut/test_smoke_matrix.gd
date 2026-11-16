extends GutTest
## Scene smoke matrix (PLAN 11): every legal subset of the mutation set, in the real
## arena with the bot playing. Apply, simulate, check, revert everything, simulate,
## check again. Error lines in the log are caught by tools/check.ps1.

const SCENES: Array[String] = [
	"res://entities/enemy_chaser.tscn", "res://entities/enemy_chaser.tscn",
	"res://entities/enemy_chaser.tscn", "res://entities/enemy_shooter.tscn",
	"res://entities/enemy_tank.tscn", "res://entities/enemy_chaser.tscn",
]
const FRAMES_ON := 120
const FRAMES_OFF := 60
const TUNING_KEYS: Array[String] = ["spawn_interval_start", "spawn_interval_end"]

var game: Node
var _saved := {}


func before_each() -> void:
	for key in TUNING_KEYS:
		_saved[key] = Tuning.get(key)
	# Fast spawner so every subset sees spawns under its own rules.
	Tuning.spawn_interval_start = 0.25
	Tuning.spawn_interval_end = 0.25
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	RunState.invincible = true
	game.player.set_bot(true)


func after_each() -> void:
	for key: String in _saved:
		Tuning.set(key, _saved[key])
	RunState.reset(0)
	RunState.world = null


func test_every_legal_subset_runs_and_reverts_cleanly() -> void:
	var all := MutationDB.all
	var rng := RandomNumberGenerator.new()
	var subsets := 0
	var most_enemies := 0
	for mask in range(1, 1 << all.size()):
		var subset: Array[Mutation] = []
		for i in all.size():
			if mask & (1 << i):
				subset.append(all[i])
		if not _legal(subset):
			continue
		subsets += 1
		rng.seed = mask
		var label := "subset %s" % [subset.map(func(m: Mutation) -> String: return String(m.id))]

		_spawn_wave(rng)
		await wait_physics_frames(2)
		# Apply in a random legal order.
		var todo := subset.duplicate()
		while not todo.is_empty():
			var ready := todo.filter(func(m: Mutation) -> bool: return RunState.can_apply(m))
			if ready.is_empty():
				fail_test("%s: nothing left can be applied" % label)
				return
			var pick: Mutation = ready[rng.randi_range(0, ready.size() - 1)]
			RunState.apply(pick)
			todo.erase(pick)
		await wait_physics_frames(FRAMES_ON)
		most_enemies = maxi(most_enemies, RunState.count(&"enemy"))
		var problem := _world_problem()
		if problem != "":
			fail_test("%s, patches on: %s" % [label, problem])
			return

		# Invariant: the derived state equals a clean rebuild of the same stack.
		var order: Array[Mutation] = RunState.stack.duplicate()
		var reached := _derived()
		for i in range(order.size() - 1, -1, -1):
			RunState.revert(order[i])
		for m in order:
			RunState.apply(m)
		if _derived() != reached:
			fail_test("%s: rebuilt state differs" % label)
			return

		# Revert from the bottom of the stack, so cascades are exercised.
		while not RunState.stack.is_empty():
			RunState.revert(RunState.stack[0])
		await wait_physics_frames(FRAMES_OFF)
		problem = _world_problem()
		if problem == "":
			problem = _leftovers()
		if problem != "":
			fail_test("%s, after revert: %s" % [label, problem])
			return
		_clear_world()
		await wait_physics_frames(1)
	assert_eq(subsets, 191, "8 mutations, one dependency: 3 * 2^6 - 1 non-empty legal subsets")
	pass_test("%d subsets, up to %d enemies alive" % [subsets, most_enemies])


func _legal(subset: Array[Mutation]) -> bool:
	var ids := subset.map(func(m: Mutation) -> StringName: return m.id)
	for m in subset:
		for req in m.requires:
			if not req in ids:
				return false
		for c in m.conflicts:
			if c in ids:
				return false
	return true


func _spawn_wave(rng: RandomNumberGenerator) -> void:
	var points: Array[Vector2] = game.arena.spawn_points
	for path in SCENES:
		var p := points[rng.randi_range(0, points.size() - 1)]
		RunState.spawn(load(path), p + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)),
				{&"from_spawner": true})


func _derived() -> String:
	var snap := RunState.snapshot()
	return JSON.stringify([snap.stack, snap.rules, snap.entities, snap.connections, snap.time_scale])


## Empty string if every entity is somewhere sane and the counts respect the caps.
func _world_problem() -> String:
	for e in RunState.live_entities():
		var pos: Vector2 = (e as Node2D).global_position
		if not (is_finite(pos.x) and is_finite(pos.y)):
			return "%s has a non-finite position" % e.name
		if not game.arena.bounds.grow(1.0).has_point(pos):
			return "%s is outside the arena at %s" % [e.name, pos]
		if e is CharacterBody2D and game.arena.distance_to_blocks(pos) < 2.0:
			return "%s is inside a block at %s" % [e.name, pos]
	if RunState.count(&"enemy") > Tuning.hard_max_enemies:
		return "enemy cap exceeded"
	if RunState.count(&"player_projectile") + RunState.count(&"enemy_projectile") > Tuning.hard_max_projectiles:
		return "projectile cap exceeded"
	if get_tree().paused:
		return "tree left paused"
	return ""


func _leftovers() -> String:
	if JSON.stringify(RunState.rules.to_dict()) != JSON.stringify(RunState.base_rules.to_dict()):
		return "rules differ from base"
	var snap := RunState.snapshot()
	if not (snap.connections as Dictionary).is_empty():
		return "mutation listeners left: %s" % [snap.connections]
	for path: String in snap.entities:
		if not (snap.entities[path] as Array).is_empty():
			return "patch components left on %s" % path
	if not RunState.patch_state.is_empty():
		return "patch_state not cleared"
	return ""


func _clear_world() -> void:
	for e in RunState.live_entities():
		if not e.is_in_group(&"player"):
			e.queue_free()
	game.player.global_position = game.arena.player_start
	game.player.velocity = Vector2.ZERO
