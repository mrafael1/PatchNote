extends GutTest
## M4: the mutation set (PLAN 5) and the transition (PLAN 4), in the real game scene.

const Fx := preload("res://tests/gut/fixtures.gd")
const CHASER := preload("res://entities/enemy_chaser.tscn")
const PROJECTILE := preload("res://entities/projectile.tscn")
const T := 48.0
## Open space with no blocks nearby (row 20 is the lane above the bottom border).
const OPEN := Vector2(34, 20)
const TUNING_KEYS: Array[String] = ["transition_long", "transition_short"]

var game: Node
var player: CharacterBody2D
var input: Fx.ScriptedInput
var _saved := {}
var _explosions := 0


func before_each() -> void:
	for key in TUNING_KEYS:
		_saved[key] = Tuning.get(key)
	Tuning.transition_long = 0.0
	Tuning.transition_short = 0.0
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	await wait_physics_frames(2)
	RunState.invincible = true
	player = game.player
	input = Fx.ScriptedInput.new()
	player.set_input(input)
	_explosions = 0
	game.world.child_entered_tree.connect(_count_explosion)


func after_each() -> void:
	for key: String in _saved:
		Tuning.set(key, _saved[key])
	RunState.reset(0)
	RunState.world = null


func _count_explosion(node: Node) -> void:
	if node is Explosion:
		_explosions += 1


func _mut(id: StringName) -> Mutation:
	return MutationDB.get_mutation(id)


func _place(tile: Vector2) -> void:
	player.global_position = tile * T
	player.velocity = Vector2.ZERO


func _spawn_frozen_chaser(tile: Vector2) -> CharacterBody2D:
	var e := RunState.spawn(CHASER, tile * T) as CharacterBody2D
	await wait_physics_frames(2)
	(e.get_node("Mover") as Node).set_physics_process(false)
	return e


func _player_hp() -> float:
	return (Component.find(player, Health) as Health).hp()


func _hp(e: Node) -> float:
	return (Component.find(e, Health) as Health).hp()


func _kill(e: Node) -> void:
	(Component.find(e, Health) as Health).take(DamageInfo.make(999.0, &"projectile", &"player"))


## Small / medium / big split (PLAN v4 1.1): the gravity pair is medium since v4.
func test_seven_offerable_smalls_and_three_parked_patches_are_registered() -> void:
	var ids: Array[String] = []
	var parked: Array[String] = []
	for m in MutationDB.all:
		if m.parked:
			parked.append(String(m.id))
		else:
			ids.append(String(m.id))
			assert_false(m.is_big or m.is_ai_tier(), "%s: only small patches are offerable in v5" % m.id)
		assert_false(m.boss_only, "%s: no boss-only patch" % m.id)
		assert_eq(MutationDB.problems(m), [] as Array[String])
	assert_eq(ids, ["auto_attack", "bouncing_projectiles", "echo", "elite", "enemies_split", "explode_on_hit",
			"horde_mode", "hunter", "jump_button", "magnet", "motion_time", "orbit", "well"])
	assert_eq(parked, ["gravity_on", "gravity_reversed", "turn_mode"], "PLAN v5 1.3")
	var offerable: Array[String] = []
	for m in MutationDB.offerable():
		offerable.append(String(m.id))
	assert_eq(offerable, ids)
	var bigs := MutationDB.all.filter(func(m: Mutation) -> bool: return m.is_big)
	assert_eq(bigs.size(), 1, "turn_mode is the only big patch left, parked")
	assert_ne(bigs[0].genre_label, "")


# --- jump_button -----------------------------------------------------------

func test_space_does_nothing_without_a_jump_rule() -> void:
	_place(OPEN)
	input.tap_jump()
	await wait_physics_frames(5)
	assert_eq(player.mover.height, 0.0)


func test_jump_button_hops_on_the_height_axis_and_slams_on_landing() -> void:
	_place(OPEN)
	var chaser := await _spawn_frozen_chaser(OPEN + Vector2(1.5, 0))
	chaser.set_physics_process(false)
	RunState.apply(_mut(&"jump_button"))
	assert_eq(RunState.rules.jumps, 1)
	watch_signals(EventBus)
	input.tap_jump()
	await wait_physics_frames(8)
	assert_gt(player.mover.height, 10.0, "up in the air mid-hop")
	assert_almost_eq(player.global_position, OPEN * T, Vector2(1, 1), "a hop does not move the body")
	assert_signal_emitted(EventBus, "player_jumped")
	await wait_physics_frames(20)
	assert_eq(player.mover.height, 0.0, "back on the ground after about 0.35 s")
	assert_signal_emit_count(EventBus, "player_landed", 1)
	assert_almost_eq(_hp(chaser), 2.0, 0.01, "the slam hit the chaser next to the landing point")
	assert_eq(RunState.damage_by_source.get(&"jump_button"), 1.0, "damage is attributed to the patch")


func test_airborne_player_is_over_contact_damage_and_ground_projectiles() -> void:
	_place(OPEN)
	var chaser := await _spawn_frozen_chaser(OPEN + Vector2(8, 0))
	RunState.apply(_mut(&"jump_button"))
	RunState.invincible = false
	input.tap_jump()
	await wait_physics_frames(3)
	assert_true(player.mover.is_airborne())
	chaser.global_position = player.global_position + Vector2(10, 0)
	var shot := RunState.spawn(PROJECTILE, (OPEN - Vector2(2, 0)) * T, {
		&"kind": &"enemy_projectile", &"faction": &"enemy", &"velocity": Vector2(900, 0)}) as Node2D
	await wait_physics_frames(12)
	assert_true(player.mover.is_airborne(), "still mid-hop")
	assert_eq(_player_hp(), 5.0, "nothing on the ground can reach the player")
	assert_true(is_instance_valid(shot) and not shot.is_queued_for_deletion(), "the shot was not consumed")
	assert_gt(shot.global_position.x, player.global_position.x, "it passed underneath")
	await wait_physics_frames(30)
	assert_lt(_player_hp(), 5.0, "landed next to the chaser: contact damage is back")


func test_jump_button_with_gravity_is_a_double_jump_and_reverts_cleanly() -> void:
	RunState.add_ai(_mut(&"gravity_on"), &"stage")
	RunState.apply(_mut(&"jump_button"))
	assert_eq(RunState.rules.jumps, 2)
	var slams := 0
	for c in player.get_children():
		if c is Component and c.source_patch == &"jump_button":
			slams += 1
	assert_eq(slams, 1)
	RunState.revert(_mut(&"jump_button"))
	for c in player.get_children():
		assert_false(c is Component and c.source_patch == &"jump_button", "slam component removed")
	var listeners := 0
	for conn: Dictionary in EventBus.player_landed.get_connections():
		if (conn.callable as Callable).get_object() is Component:
			listeners += 1
	assert_eq(listeners, 0, "the component disconnected itself")


# --- auto_attack -----------------------------------------------------------

func test_auto_attack_fires_at_the_nearest_enemy_at_the_normal_rate() -> void:
	_place(OPEN)
	var chaser := await _spawn_frozen_chaser(OPEN + Vector2(6, 0))
	chaser.set_physics_process(false)
	watch_signals(EventBus)
	input.aim_dir = Vector2.LEFT   # the mouse points away; auto attack must not care
	await wait_physics_frames(20)
	assert_signal_emit_count(EventBus, "projectile_fired", 0, "nothing fires without the rule")
	RunState.apply(_mut(&"auto_attack"))
	await wait_physics_frames(60)
	var shots: int = get_signal_emit_count(EventBus, "projectile_fired")
	assert_between(shots, 3, 7, "same cooldown as manual fire, until the target dies")
	assert_eq(RunState.kills, 1, "the shots went at the enemy")


func test_auto_attack_needs_line_of_sight_and_yields_to_manual_fire() -> void:
	# The chunk at columns 20-21, rows 19-20 stands between them.
	_place(Vector2(18, 20))
	var chaser := await _spawn_frozen_chaser(Vector2(23.5, 20))
	chaser.set_physics_process(false)
	RunState.apply(_mut(&"auto_attack"))
	watch_signals(EventBus)
	await wait_physics_frames(30)
	assert_signal_emit_count(EventBus, "projectile_fired", 0, "no shot through a wall")
	input.aim_dir = Vector2.LEFT
	input.fire = true
	await wait_physics_frames(60)
	input.fire = false
	assert_between(get_signal_emit_count(EventBus, "projectile_fired"), 5, 7, "fire rate never doubles")
	assert_eq(_hp(chaser), 3.0)


# --- explode_on_hit --------------------------------------------------------

func test_explosion_on_wall_hit_damages_nearby_enemies_only() -> void:
	_place(OPEN - Vector2(1.2, 0))
	var chaser := await _spawn_frozen_chaser(OPEN)
	chaser.set_physics_process(false)
	RunState.apply(_mut(&"explode_on_hit"))
	RunState.invincible = false
	# Straight down into the floor beside the chaser.
	RunState.spawn(PROJECTILE, (OPEN + Vector2(0.8, 0)) * T, {&"velocity": Vector2(0, 900)})
	await wait_physics_frames(6)
	assert_eq(_explosions, 1)
	assert_almost_eq(_hp(chaser), 2.0, 0.01, "caught in the blast")
	assert_eq(RunState.damage_by_source.get(&"explode_on_hit"), 1.0)
	assert_eq(_player_hp(), 5.0, "the player is pushed, not hurt")


func test_enemy_projectiles_do_not_explode() -> void:
	RunState.apply(_mut(&"explode_on_hit"))
	RunState.spawn(PROJECTILE, OPEN * T, {
		&"kind": &"enemy_projectile", &"faction": &"enemy", &"velocity": Vector2(0, 900)})
	await wait_physics_frames(8)
	assert_eq(_explosions, 0)


# --- enemies_split ---------------------------------------------------------

func test_killed_enemy_splits_once_and_children_survive_the_revert() -> void:
	_place(OPEN - Vector2(12, 0))
	var chaser := await _spawn_frozen_chaser(OPEN)
	RunState.apply(_mut(&"enemies_split"))
	_kill(chaser)
	await wait_physics_frames(3)
	var children := get_tree().get_nodes_in_group(&"enemy")
	assert_eq(children.size(), 2, "two copies replace the parent")
	for c in children:
		assert_eq(c.get("generation"), 1)
		assert_almost_eq(float(c.get("size_mult")), 0.65, 0.001)
		assert_almost_eq((Component.find(c, Health) as Health).max_hp(), 1.2, 0.001, "weaker")
		assert_false(c.get("from_spawner"), "copies do not count toward the Director")
		assert_lt((c.get_node("Visual") as RectVisual).size.x, 30.0, "smaller")
	_kill(children[0])
	await wait_physics_frames(3)
	assert_eq(RunState.count(&"enemy"), 1, "a copy does not split again")
	RunState.revert(_mut(&"enemies_split"))
	await wait_physics_frames(3)
	assert_eq(RunState.count(&"enemy"), 1, "copies already in the world stay after the revert")


# --- gravity_reversed ------------------------------------------------------

func test_gravity_reversed_needs_gravity_and_makes_things_fall_up() -> void:
	var reversed := _mut(&"gravity_reversed")
	assert_false(RunState.can_add_ai(reversed), "requires gravity_on")
	RunState.add_ai(_mut(&"gravity_on"), &"stage")
	assert_true(RunState.can_add_ai(reversed))
	_place(Vector2(10, 14))
	RunState.add_ai(reversed, &"stage")
	assert_eq(RunState.rules.gravity_dir, Vector2(0, -1))
	var landed := false
	for i in 180:
		await wait_physics_frames(1)
		if player.is_on_floor():
			landed = true
			break
	assert_true(landed, "landed on a ceiling-side surface")
	assert_lt(player.global_position.y, 14 * T - 20.0, "it fell upward")
	assert_eq(player.up_direction, Vector2(0, 1))
	var build := RunState.build_number
	var removed := RunState.remove_ai(_mut(&"gravity_on"), &"rollback")
	assert_eq(removed.size(), 2, "rolling back gravity takes the reversal with it")
	assert_eq(RunState.build_number, build + 1)
	assert_false(RunState.rules.gravity_enabled)


# --- Section 5 acceptance --------------------------------------------------

func test_bounce_explode_gravity_gives_arcing_explosive_ricochets() -> void:
	RunState.add_ai(_mut(&"gravity_on"), &"stage")
	RunState.apply(_mut(&"bouncing_projectiles"))
	RunState.apply(_mut(&"explode_on_hit"))
	_place(OPEN)
	await wait_physics_frames(30)
	input.aim_dir = Vector2(1, -0.35).normalized()
	input.fire = true
	var most_bounces := 0
	var arced := false
	for i in 600:   # 10 seconds
		await wait_physics_frames(1)
		for p in get_tree().get_nodes_in_group(&"player_projectile"):
			most_bounces = maxi(most_bounces, int(p.get("bounces_used")))
			if (p.get("velocity") as Vector2).y > 50.0:
				arced = true
	input.fire = false
	assert_true(arced, "shots fired upward come back down")
	assert_gte(most_bounces, 2, "a projectile bounced at least twice")
	assert_gte(_explosions, 3, "explosions within 10 seconds")


## A mutation is added by adding its folder. Nothing outside that folder may name it.
func test_no_mutation_id_is_referenced_outside_its_own_folder() -> void:
	# M44 (D1): res://weapons/ is skipped: the weapon ids orbit (and later well) are PLAN v9
	# 1.4's names, and the orbit weapon reuses the v6 shard script. test_weapons.gd keeps
	# weapons/ off RunState.apply / add_ai / MutationDB instead.
	var files := _source_files("res://", ["res://addons/", "res://tests/", "res://tools/",
			"res://.godot/", "res://.check/", "res://weapons/"])
	assert_gt(files.size(), 30)
	for m in MutationDB.all:
		var own := "res://mutations/%s/" % m.id
		for path in files:
			if path.begins_with(own):
				continue
			var text := FileAccess.get_file_as_string(path)
			if text.contains("\"%s\"" % m.id) or text.contains("mutations/%s" % m.id):
				# requires/conflicts on another mutation's resource are the allowed form, and
				# so is a change's unlocks field (PLAN v5 1.2).
				if path.begins_with("res://mutations/") and path.ends_with(".tres"):
					continue
				if path.begins_with(ChangeDB.DIR) and path.ends_with(".tres") and _only_in_unlocks(text, String(m.id)):
					continue
				fail_test("%s names mutation '%s'" % [path, m.id])
	pass_test("%d files checked" % files.size())


## Every line of a change resource that names id is its unlocks field.
func _only_in_unlocks(text: String, id: String) -> bool:
	for line in text.split("\n"):
		var names := line.contains("\"%s\"" % id) or line.contains("mutations/%s" % id)
		if names and not line.begins_with("unlocks = "):
			return false
	return true


func _source_files(dir: String, skip: Array) -> Array[String]:
	var out: Array[String] = []
	if dir in skip:
		return out
	for entry in DirAccess.get_files_at(dir):
		if entry.get_extension() in ["gd", "tscn", "tres"]:
			out.append(dir + entry)
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_source_files(dir + sub + "/", skip))
	return out


# --- Transition ------------------------------------------------------------

func test_gravity_change_runs_the_sequence_and_grants_grace() -> void:
	Tuning.transition_long = 0.12
	_place(OPEN)
	var chaser := await _spawn_frozen_chaser(OPEN + Vector2(8, 0))
	RunState.invincible = false
	var transition: Transition = game.transition
	assert_true(transition.request_ai_add(_mut(&"gravity_on"), &"stage"))
	assert_true(transition.busy)
	assert_true(get_tree().paused, "the world is frozen")
	assert_true(RunState.is_paused_for(&"transition"))
	assert_false(RunState.has_patch(&"gravity_on"), "the patch lands after the terminal text")
	assert_false(transition.request_apply(_mut(&"horde_mode")), "one at a time")
	await wait_for_signal(transition.finished, 2.0)
	assert_true(RunState.has_patch(&"gravity_on"))
	assert_false(get_tree().paused)
	assert_false(transition.busy)
	assert_true(RunState.in_grace())
	chaser.global_position = player.global_position + Vector2(10, 0)
	await wait_physics_frames(30)
	assert_eq(_player_hp(), 5.0, "enemies deal no damage during the grace period")
	chaser.global_position = player.global_position + Vector2(10, 0)
	await wait_physics_frames(int(Tuning.grace_time * 60.0) + 10)
	assert_lt(_player_hp(), 5.0, "and they do again afterwards")


func test_other_patches_apply_at_once_without_pause_or_grace() -> void:
	Tuning.transition_short = 0.5
	var transition: Transition = game.transition
	assert_true(transition.request_apply(_mut(&"horde_mode")))
	assert_true(RunState.has_patch(&"horde_mode"))
	assert_false(get_tree().paused)
	assert_false(RunState.in_grace())
	assert_false(transition.busy)
	assert_true(transition.request_revert(_mut(&"horde_mode")))
	assert_false(RunState.has_patch(&"horde_mode"))


func test_transition_refuses_illegal_requests() -> void:
	var transition: Transition = game.transition
	assert_false(transition.request_apply(_mut(&"gravity_on")), "an AI-tier patch never enters the stack")
	assert_false(transition.request_apply(_mut(&"gravity_on"), true), "not even forced")
	assert_false(transition.request_ai_add(_mut(&"horde_mode"), &"stage"), "a small is not AI-tier")
	assert_false(transition.request_ai_add(_mut(&"gravity_reversed"), &"stage"), "requirement not met")
	assert_false(transition.request_ai_remove(_mut(&"gravity_on"), &"rollback"), "not in the layer")
	assert_true(transition.request_apply(_mut(&"horde_mode")))
	assert_false(transition.request_ai_remove(_mut(&"horde_mode"), &"rollback"), "a stack patch is not a target")
	assert_true(transition.request_ai_add(_mut(&"gravity_on"), &"stage"))
	assert_false(transition.request_ai_add(_mut(&"gravity_on"), &"stage"), "already live")
	assert_false(transition.request_revert(_mut(&"gravity_on")), "not in the stack")


func test_cascading_ai_rollback_is_one_transition_and_one_build() -> void:
	var transition: Transition = game.transition
	transition.request_ai_add(_mut(&"gravity_on"), &"stage")
	transition.request_ai_add(_mut(&"gravity_reversed"), &"stage")
	assert_eq(RunState.ai.size(), 2)
	watch_signals(transition)
	var build := RunState.build_number
	assert_true(transition.request_ai_remove(_mut(&"gravity_on"), &"rollback"))
	assert_signal_emit_count(transition, "finished", 1)
	assert_eq(RunState.ai.size(), 0)
	assert_eq(RunState.build_number, build + 1)
	assert_true(RunState.in_grace(), "an AI gravity change gets the grace")
	assert_eq(RunState.run_log[-1].event, &"ai_remove")
	assert_eq(RunState.run_log[-1].reason, &"rollback")


## Previews pass the AI layer as it will be after the operation (PLAN v4 1.2): a
## small patch under live gravity changes no gravity (no grace); a rollback of the
## reversal alone keeps gravity but flips it back (the safety sequence and its grace).
func test_previews_see_the_ai_layer() -> void:
	var transition: Transition = game.transition
	RunState.add_ai(_mut(&"gravity_on"), &"stage")
	RunState.add_ai(_mut(&"gravity_reversed"), &"stage")
	assert_true(transition.request_apply(_mut(&"horde_mode")))
	assert_false(RunState.in_grace(), "gravity stays as it is: no safety sequence")
	assert_true(transition.request_ai_remove(_mut(&"gravity_reversed"), &"rollback"))
	assert_true(RunState.in_grace(), "gravity flips back down: the safety sequence")
	assert_eq(RunState.ai, [_mut(&"gravity_on")] as Array[Mutation])
	assert_true(RunState.rules.gravity_enabled)
	assert_eq(RunState.rules.gravity_dir, Vector2(0, 1))


func test_gravity_change_clears_speed_along_the_gravity_axis() -> void:
	RunState.add_ai(_mut(&"gravity_on"), &"stage")
	_place(Vector2(10, 8))
	await wait_physics_frames(12)
	assert_gt(player.velocity.y, 100.0, "falling")
	game.transition.request_ai_remove(_mut(&"gravity_on"), &"rollback")
	await wait_physics_frames(2)
	assert_almost_eq(player.velocity.y, 0.0, 1.0, "the fall does not carry into top-down")
