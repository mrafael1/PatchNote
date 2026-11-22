extends GutTest
## Scene smoke matrix (PLAN 11, v3 section 8): each big slot value (none, then every
## big patch) x a fixed sample of the legal subsets of the small patches (AI-tier
## patches are not small, PLAN v4 1.1, and never enter the stack), in the real arena with
## the bot
## playing. Apply, simulate, check, revert everything, simulate, check again. Error
## lines in the log are caught by tools/check.ps1.

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
	# Tier 0: no hit stop, so the time scale in the state snapshot is the rules' alone.
	Look.use({"tier": 0, "take": ""})
	RunState.invincible = true
	game.player.set_bot(true)
	game.director.enabled = false   # the matrix applies patches itself


func after_each() -> void:
	Look.use(Unlocks.FULL_LOOK)
	for key: String in _saved:
		Tuning.set(key, _saved[key])
	RunState.reset(0)
	RunState.world = null


func test_every_legal_subset_runs_and_reverts_cleanly() -> void:
	await _matrix(null)


func test_every_legal_subset_runs_under_each_big_patch() -> void:
	var bigs := MutationDB.all.filter(func(m: Mutation) -> bool: return m.is_big)
	assert_gt(bigs.size(), 0)
	for big: Mutation in bigs:
		RunState.swap_big(big)
		await wait_physics_frames(2)
		if not await _matrix(big):
			return


## The parked AI layer's gravity (alone, then with its reversal) over every small
## patch, under no big patch and each big patch it fits. Outside the pinned counts.
func test_the_full_stack_runs_under_ai_gravity() -> void:
	var smalls := MutationDB.all.filter(func(m: Mutation) -> bool: return not m.is_big and not m.is_ai_tier())
	var layers: Array = [[&"gravity_on"], [&"gravity_on", &"gravity_reversed"]]
	var slots: Array = [null]
	slots.append_array(MutationDB.all.filter(func(m: Mutation) -> bool: return m.is_big))
	var runs := 0
	for big: Mutation in slots:
		if big != null:
			RunState.swap_big(big)
			await wait_physics_frames(2)
		for ids: Array in layers:
			var label := "big %s, ai %s" % [String(big.id) if big else "none", ids]
			if not RunState.can_add_ai_list(ids, big, RunState.stack):
				continue
			runs += 1
			var rng := RandomNumberGenerator.new()
			rng.seed = runs
			_spawn_wave(rng)
			await wait_physics_frames(2)
			for id: StringName in ids:
				RunState.add_ai(MutationDB.get_mutation(id), &"stage")
			for m: Mutation in smalls:
				if not RunState.apply(m):
					fail_test("%s: %s did not apply" % [label, m.id])
					return
			await wait_physics_frames(FRAMES_ON)
			var problem := _world_problem()
			if problem != "":
				fail_test("%s, patches on: %s" % [label, problem])
				return
			RunState.remove_ai(MutationDB.get_mutation(ids[0]), &"rollback")
			while not RunState.stack.is_empty():
				RunState.revert(RunState.stack[0])
			await wait_physics_frames(FRAMES_OFF)
			problem = _world_problem()
			if problem == "":
				problem = _leftovers(big)
			if problem != "":
				fail_test("%s, after removal: %s" % [label, problem])
				return
			_clear_world()
			await wait_physics_frames(1)
	assert_eq(runs, 2, "no big patch, with gravity and with gravity reversed (the parked B2 refuses gravity)")


## Runs every legal small subset with `big` in the slot (already swapped in). Returns
## false after the first failure.
func _matrix(big: Mutation) -> bool:
	var all := MutationDB.all.filter(func(m: Mutation) -> bool: return not m.is_big and not m.is_ai_tier())
	var rng := RandomNumberGenerator.new()
	var subsets := 0
	var most_enemies := 0
	var big_label := String(big.id) if big else "none"
	var masks := sample_masks(all.size())
	var covered := {}
	for mask: int in masks:
		var subset: Array[Mutation] = []
		for i in all.size():
			if mask & (1 << i):
				subset.append(all[i])
		if not _legal(subset, big):
			continue
		subsets += 1
		for m in subset:
			covered[m.id] = true
		rng.seed = mask
		var label := "big %s, subset %s" % [big_label, subset.map(func(m: Mutation) -> String: return String(m.id))]

		_spawn_wave(rng)
		await wait_physics_frames(2)
		# Apply in a random legal order.
		var todo := subset.duplicate()
		while not todo.is_empty():
			var ready := todo.filter(func(m: Mutation) -> bool: return RunState.can_apply(m))
			if ready.is_empty():
				fail_test("%s: nothing left can be applied" % label)
				return false
			var pick: Mutation = ready[rng.randi_range(0, ready.size() - 1)]
			RunState.apply(pick)
			todo.erase(pick)
		await wait_physics_frames(FRAMES_ON)
		most_enemies = maxi(most_enemies, RunState.count(&"enemy"))
		var problem := _world_problem()
		if problem != "":
			fail_test("%s, patches on: %s" % [label, problem])
			return false

		# Invariant: the derived state equals a clean rebuild of the same stack.
		var order: Array[Mutation] = RunState.stack.duplicate()
		var reached := _derived()
		for i in range(order.size() - 1, -1, -1):
			RunState.revert(order[i])
		for m in order:
			RunState.apply(m)
		if _derived() != reached:
			fail_test("%s: rebuilt state differs" % label)
			return false

		# Revert from the bottom of the stack, so cascades are exercised.
		while not RunState.stack.is_empty():
			RunState.revert(RunState.stack[0])
		await wait_physics_frames(FRAMES_OFF)
		problem = _world_problem()
		if problem == "":
			problem = _leftovers(big)
		if problem != "":
			fail_test("%s, after revert: %s" % [label, problem])
			return false
		_clear_world()
		await wait_physics_frames(1)
	assert_eq(subsets, _expected_subsets(all, masks, big), "legal sampled subsets under big %s" % big_label)
	for m in all:
		if _legal([m] as Array[Mutation], big):
			assert_true(covered.has(m.id), "%s runs in at least one subset under big %s" % [m.id, big_label])
	if RunState.big != big:
		fail_test("big %s: the slot changed during the matrix" % big_label)
		return false
	pass_test("big %s: %d subsets, up to %d enemies alive" % [big_label, subsets, most_enemies])
	return true


## Every require is met and nothing conflicts, the big patch in the slot included.
func _legal(subset: Array[Mutation], big: Mutation) -> bool:
	var present: Array[Mutation] = subset.duplicate()
	if big != null:
		present.append(big)
	var ids := present.map(func(m: Mutation) -> StringName: return m.id)
	for m in present:
		for req in m.requires:
			if not req in ids:
				return false
		for c in m.conflicts:
			if c in ids:
				return false
	return true


## The subsets tried (M33): with 7 smalls every subset was tried (127); with 13 that is
## 8191 per slot, so the matrix now tries every single patch, every pair (each two-patch
## interaction), the full stack, and SAMPLED seeded random larger subsets: about as many
## runs as before. Bit i of a mask is small patch i.
const SAMPLED := 40


static func sample_masks(n: int) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		out.append(1 << i)
	for i in n:
		for j in range(i + 1, n):
			out.append((1 << i) | (1 << j))
	var full := (1 << n) - 1
	if not full in out:
		out.append(full)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var tries := 0
	while out.size() < n + n * (n - 1) / 2 + 1 + SAMPLED and tries < 10000:
		tries += 1
		var mask := rng.randi_range(1, full)
		var bits := 0
		for i in n:
			bits += (mask >> i) & 1
		if bits >= 3 and not mask in out:
			out.append(mask)
	return out


## The sample's legal subsets, counted on their own: every small is legal alone and in
## pairs with an empty slot (no requires or conflicts among them); under turn_mode, B1
## (motion_time) conflicts with the slot, so every mask holding it drops out.
func _expected_subsets(all: Array, masks: Array[int], big: Mutation) -> int:
	if big == null or big.id != &"turn_mode":
		return masks.size()
	var b1 := all.map(func(m: Mutation) -> StringName: return m.id).find(&"motion_time")
	return masks.filter(func(mask: int) -> bool: return mask & (1 << b1) == 0).size()


func _spawn_wave(rng: RandomNumberGenerator) -> void:
	var points: Array[Vector2] = game.arena.spawn_points
	for path in SCENES:
		var p := points[rng.randi_range(0, points.size() - 1)]
		RunState.spawn(load(path), p + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)),
				{&"from_spawner": true})


## Under motion time (time_follows_motion) the time scale is left out: B1's factor is
## smoothed over the last ticks of player motion, so a rebuild restarts it at 1 and the
## next tick brings it back. Not a pure function of the layers by design; the old full
## matrix only passed because its seeds caught the bot at full speed (found in M33).
func _derived() -> String:
	var snap := RunState.snapshot()
	var time_scale: Variant = null if RunState.rules.time_follows_motion else snap.time_scale
	return JSON.stringify([snap.stack, snap.rules, snap.entities, snap.connections, time_scale])


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
	if RunState.is_paused_except(&"turn"):
		return "tree left paused"
	return ""


## What the small patches left behind. With a big patch in the slot, its own rules,
## listeners, components and state are expected and ignored.
func _leftovers(big: Mutation) -> String:
	var expected := RunState.preview_rules([] as Array[Mutation], big)
	if JSON.stringify(RunState.rules.to_dict()) != JSON.stringify(expected.to_dict()):
		return "rules differ from base + big"
	var snap := RunState.snapshot()
	for sig: StringName in snap.connections:
		for owner: String in snap.connections[sig]:
			if big == null or not owner.begins_with(String(big.id) + "."):
				return "mutation listeners left: %s" % [snap.connections]
	for path: String in snap.entities:
		for comp: String in snap.entities[path]:
			if big == null or not comp.ends_with("@" + String(big.id)):
				return "patch components left on %s" % path
	for id: StringName in RunState.patch_state:
		if big == null or id != big.id:
			return "patch_state not cleared"
	return ""


func _clear_world() -> void:
	for e in RunState.live_entities():
		if not e.is_in_group(&"player"):
			e.queue_free()
	game.player.global_position = game.arena.player_start
	game.player.velocity = Vector2.ZERO
