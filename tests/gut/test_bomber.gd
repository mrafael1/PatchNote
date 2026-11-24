extends GutTest
## M29: the bomber (PLAN v5 3), the enemy the enemy_bomber change ships: it walks in,
## stops near the player, telegraphs, then its blast hurts the player and other enemies,
## and it is gone.

const BOMBER := preload("res://entities/enemy_bomber.tscn")
const CHASER := preload("res://entities/enemy_chaser.tscn")
const T := 48.0
const OPEN := Vector2(34, 20)

var game: Main
var player: CharacterBody2D


func before_each() -> void:
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	game.spawner.enabled = false
	game.director.enabled = false
	await wait_physics_frames(2)
	for e in get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()
	await wait_physics_frames(1)
	player = game.player
	player.set_input(load("res://tests/gut/fixtures.gd").ScriptedInput.new())
	player.global_position = OPEN * T
	player.velocity = Vector2.ZERO


func after_each() -> void:
	RunState.session = null
	RunState.invincible = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null


func _spawn(scene: PackedScene, tile: Vector2) -> Node2D:
	var e := RunState.spawn(scene, tile * T) as Node2D
	await wait_physics_frames(2)
	return e


func _player_hp() -> float:
	return (Component.find(player, Health) as Health).hp()


func test_a_bomber_telegraphs_then_blows_up_hurting_the_player_and_enemies() -> void:
	var neighbour := await _spawn(CHASER, OPEN + Vector2(1.6, 1.0))
	(neighbour.get_node("Mover") as Node).set_physics_process(false)
	var near_death := await _spawn(CHASER, OPEN + Vector2(1.2, -0.9))
	(near_death.get_node("Mover") as Node).set_physics_process(false)
	near_death.health.take(DamageInfo.make(near_death.health.hp() - 0.5, &"projectile", &"player"))
	var neighbour_hp: float = neighbour.health.hp()
	var director_kills: int = game.director.get(&"_kills_since_prompt")
	var bomber := await _spawn(BOMBER, OPEN + Vector2(1.2, 0))
	var hp_before := _player_hp()
	var kills_before := RunState.kills
	await wait_physics_frames(3)
	assert_true(bomber.is_fuse_lit(), "in range: the fuse is lit")
	assert_eq(bomber.fuses, 1)
	assert_eq(bomber.mover.wish, Vector2.ZERO, "it stops to telegraph")
	await wait_seconds(Tuning.bomber_windup * 0.5)
	assert_true(is_instance_valid(bomber), "not before the windup ends")
	assert_gt(bomber.visual.telegraph, 0.0, "it grows and flashes")
	await wait_seconds(Tuning.bomber_windup * 0.5 + 0.15)
	assert_false(is_instance_valid(bomber) and not bomber.is_queued_for_deletion(), "gone after its blast")
	assert_eq(_player_hp(), hp_before - Tuning.bomber_blast_damage, "the blast hurts the player")
	assert_lt(neighbour.health.hp(), neighbour_hp, "and enemies in range")
	assert_false(is_instance_valid(near_death) and not near_death.is_queued_for_deletion(), "the blast killed one")
	assert_eq(RunState.kills, kills_before, "neither its own death nor its victims are the player's kills")
	assert_eq(game.director.get(&"_kills_since_prompt"), director_kills, "nor do they pace the prompts")


## The fuse lights inside the blast's reach: a player who stands still is hit.
func test_a_bomber_walking_in_hits_a_player_who_stands_still() -> void:
	assert_lt(Tuning.bomber_trigger_range, Tuning.bomber_blast_radius + Explosion.BODY_MARGIN)
	var bomber := await _spawn(BOMBER, OPEN + Vector2(5, 0))
	var hp_before := _player_hp()
	for i in 240:
		await wait_physics_frames(1)
		if not is_instance_valid(bomber) or bomber.is_queued_for_deletion():
			break
	assert_false(is_instance_valid(bomber) and not bomber.is_queued_for_deletion(), "it walked in and blew up")
	assert_eq(_player_hp(), hp_before - Tuning.bomber_blast_damage)


func test_a_bomber_far_away_walks_in_and_has_no_contact_damage_or_rim() -> void:
	var bomber := await _spawn(BOMBER, OPEN + Vector2(8, 0))
	await wait_physics_frames(10)
	assert_false(bomber.is_fuse_lit())
	assert_gt(bomber.mover.wish.length(), 0.5, "it walks toward the player")
	assert_eq(bomber.get(&"_contact_damage"), 0.0, "it hurts by its blast only")
	# Held inside a chaser's rim range but outside its own trigger range: no rim.
	(bomber.get_node("Mover") as Node).set_physics_process(false)
	bomber.global_position = player.global_position + Vector2(1.7 * T, 0)
	assert_gt(EnemyCommon.contact_warning(1.7 * T - bomber.contact_reach()), 0.0,
			"a chaser here would show its rim")
	await wait_physics_frames(2)
	assert_false(bomber.is_fuse_lit())
	assert_eq(bomber.visual.rim, 0.0, "its telegraph is the fuse, not the contact rim")


func test_a_bomber_shot_first_dies_without_a_blast() -> void:
	var bomber := await _spawn(BOMBER, OPEN + Vector2(6, 0))
	(bomber.get_node("Mover") as Node).set_physics_process(false)
	var neighbour := await _spawn(CHASER, OPEN + Vector2(6.8, 0.8))
	(neighbour.get_node("Mover") as Node).set_physics_process(false)
	var neighbour_hp: float = neighbour.health.hp()
	var hp_before := _player_hp()
	var kills_before := RunState.kills
	bomber.health.take(DamageInfo.make(99, &"projectile", &"player"))
	await wait_physics_frames(2)
	assert_false(is_instance_valid(bomber))
	assert_eq(_player_hp(), hp_before)
	assert_eq(neighbour.health.hp(), neighbour_hp, "no blast")
	assert_eq(RunState.kills, kills_before + 1, "shooting it is a kill")


func test_split_halves_of_a_bomber_are_bombers() -> void:
	RunState.apply(MutationDB.get_mutation(&"enemies_split"), true)
	var bomber := await _spawn(BOMBER, OPEN + Vector2(8, 0))
	bomber.health.take(DamageInfo.make(99, &"projectile", &"player"))
	await wait_physics_frames(3)
	var halves := get_tree().get_nodes_in_group(&"enemy")
	assert_eq(halves.size(), 2)
	for h in halves:
		assert_eq(h.get(&"archetype"), &"bomber")
		assert_eq(h.get(&"generation"), 1)


func test_the_spawner_sends_bombers_only_when_unlocked_and_never_on_the_turn_grid() -> void:
	var spawner: Spawner = game.spawner
	spawner.set(&"_elapsed", Tuning.spawn_bomber_delay + 1.0)
	var counts := {}
	for i in 2000:
		var t := spawner.pick_type()
		counts[t] = int(counts.get(t, 0)) + 1
	assert_gt(int(counts.get(&"bomber", 0)), 100, "inert: everything unlocked")
	SaveGame.use_snapshot("", true)
	counts.clear()
	for i in 2000:
		counts[spawner.pick_type()] = true
	assert_false(counts.has(&"bomber"), "a new save has no bomber")
	assert_false(counts.has(&"tank"), "nor a tank")
	SaveGame.go_inert()
	RunState.rules.turn_based = true
	counts.clear()
	for i in 2000:
		counts[spawner.pick_type()] = true
	RunState.rules.turn_based = false
	assert_false(counts.has(&"bomber"), "B2 has no bomber role")


# --- M42.1: the campaign bomber (owner G13) --------------------------------------
# In a campaign session a bomber blows up however it dies: it blinks for
# Tuning.bomber_death_fuse, then blasts at Tuning.bomber_campaign_blast_radius.

const PROJECTILE := preload("res://entities/projectile.tscn")
const BOMBER_SCRIPT := preload("res://entities/enemy_bomber.gd")


func _in_session(id: StringName = &"s1_05_wrong") -> void:
	RunState.session = CampaignDB.get_session(id)
	for n: Node in [game.session_runner, game.reactions]:
		if n != null:
			n.set_physics_process(false)


## An enemy held in place, with its HP set (a blast of damage 1 kills only an HP-1 one).
func _held(scene: PackedScene, tile: Vector2, hp := -1.0) -> Node2D:
	var e := await _spawn(scene, tile)
	(e.get_node("Mover") as Node).set_physics_process(false)
	if hp > 0.0:
		var h: Health = e.health
		h.hp_ratio = hp / h.max_hp()
	return e


func _gone(n: Variant) -> bool:
	return not is_instance_valid(n) or (n as Node).is_queued_for_deletion()


func _player_hits() -> int:
	return RunState.run_log.filter(func(r: Dictionary) -> bool: return r.get("event") == &"player_hit").size()


func test_in_a_session_the_blast_is_bigger_and_the_fuse_still_lights_inside_it() -> void:
	_in_session()
	assert_eq(BOMBER_SCRIPT.blast_radius(), Tuning.bomber_campaign_blast_radius)
	assert_gt(Tuning.bomber_campaign_blast_radius, Tuning.bomber_blast_radius, "a bit bigger (G13)")
	assert_lt(Tuning.bomber_trigger_range, Tuning.bomber_campaign_blast_radius + Explosion.BODY_MARGIN)
	RunState.session = null
	assert_eq(BOMBER_SCRIPT.blast_radius(), Tuning.bomber_blast_radius, "the v6 loop keeps its radius")


func test_in_a_session_a_shot_bomber_blinks_then_blows_at_the_bigger_radius() -> void:
	_in_session()
	var a := OPEN + Vector2(6, 0)
	var bomber := await _held(BOMBER, a)
	var inside := await _held(CHASER, a + Vector2(1.9, 0))
	var outside := await _held(CHASER, a + Vector2(-2.6, 0))
	var inside_hp: float = inside.health.hp()
	var outside_hp: float = outside.health.hp()
	watch_signals(EventBus)
	bomber.health.take(DamageInfo.make(99, &"projectile", &"player"))
	await wait_physics_frames(15)   # 0.25 s
	assert_eq(get_signal_emit_count(EventBus, "explosion"), 0, "no blast before the death fuse ends")
	assert_false(_gone(bomber), "it is still there, blinking")
	assert_gt(bomber.visual.telegraph, 0.0, "with the fuse's blink")
	assert_false(bomber.is_in_group(&"enemy"), "a dead bomber is no longer an enemy")
	await wait_physics_frames(6)    # 0.35 s
	assert_eq(get_signal_emit_count(EventBus, "explosion"), 1, "then one blast")
	var params: Array = get_signal_parameters(EventBus, "explosion")
	assert_eq(params[1], Tuning.bomber_campaign_blast_radius)
	assert_true(_gone(bomber))
	assert_lt(inside.health.hp(), inside_hp, "1.9 tiles away is inside the bigger blast")
	assert_eq(outside.health.hp(), outside_hp, "2.6 tiles away is not")


## The death fuse is there so a close kill can be walked away from (critic #1).
func _step_out(moving: bool) -> Array:
	_in_session()
	var bomber := await _held(BOMBER, OPEN + Vector2(70.0 / T, 0))
	await wait_physics_frames(1)
	assert_false(bomber.is_fuse_lit(), "70 px is outside the trigger range")
	var start: Vector2 = bomber.global_position
	var hp_before := _player_hp()
	bomber.health.take(DamageInfo.make(99, &"projectile", &"player"))
	var input: PlayerInput = player.get(&"input")
	if moving:
		input.move = Vector2.LEFT
	await wait_physics_frames(30)
	input.move = Vector2.ZERO
	assert_true(_gone(bomber), "it blew")
	return [hp_before, player.global_position.distance_to(start)]


func test_the_player_can_step_out_of_a_death_blast() -> void:
	var r: Array = await _step_out(true)
	assert_gt(r[1], Tuning.bomber_campaign_blast_radius + Explosion.BODY_MARGIN, "the player got out of reach")
	assert_eq(_player_hp(), r[0], "stepping away during the blink avoids the blast")


func test_a_player_who_stands_by_a_death_blast_is_hit() -> void:
	var r: Array = await _step_out(false)
	assert_eq(_player_hp(), r[0] - Tuning.bomber_blast_damage, "standing still is hit")


func test_in_a_session_its_victims_are_the_players_kills_when_the_player_shot_it() -> void:
	_in_session()
	var a := OPEN + Vector2(6, 0)
	var bomber := await _held(BOMBER, a)
	var victim := await _held(CHASER, a + Vector2(1.9, 0), 1.0)
	var kills_before := RunState.kills
	bomber.health.take(DamageInfo.make(99, &"projectile", &"player"))
	await wait_physics_frames(24)
	assert_true(_gone(victim), "the death blast killed it")
	assert_eq(RunState.kills, kills_before + 2, "the bomber and its victim are the player's kills")


func test_a_fuse_blast_in_a_session_still_gives_no_kills() -> void:
	_in_session()
	var neighbour := await _held(CHASER, OPEN + Vector2(3.1, 0))
	var near_death := await _held(CHASER, OPEN + Vector2(1.2, -0.9), 1.0)
	var neighbour_hp: float = neighbour.health.hp()
	var director_kills: int = game.director.get(&"_kills_since_prompt")
	var bomber := await _spawn(BOMBER, OPEN + Vector2(1.2, 0))
	var hp_before := _player_hp()
	var kills_before := RunState.kills
	await wait_physics_frames(3)
	assert_true(bomber.is_fuse_lit())
	await wait_seconds(Tuning.bomber_windup + 0.15)
	assert_true(_gone(bomber), "gone after its blast")
	assert_eq(_player_hp(), hp_before - Tuning.bomber_blast_damage, "the blast hurts the player")
	assert_lt(neighbour.health.hp(), neighbour_hp, "1.9 tiles away is inside the bigger fuse blast too")
	assert_true(_gone(near_death), "the blast killed one")
	assert_eq(RunState.kills, kills_before, "a fuse blast's victims are nobody's kills")
	assert_eq(game.director.get(&"_kills_since_prompt"), director_kills, "nor do they pace the prompts")


func test_a_blast_killing_a_hurt_bomber_sets_it_off() -> void:
	_in_session()
	var a := OPEN + Vector2(6, 0)
	var first := await _held(BOMBER, a)
	var second := await _held(BOMBER, a + Vector2(1.5, 0), 1.0)
	var far := await _held(CHASER, a + Vector2(3.4, 0), 1.0)
	var full := await _held(BOMBER, a + Vector2(-1.5, 0))
	var kills_before := RunState.kills
	watch_signals(EventBus)
	first.health.take(DamageInfo.make(99, &"projectile", &"player"))
	await wait_physics_frames(21)   # 0.35 s
	assert_eq(get_signal_emit_count(EventBus, "explosion"), 1, "the first one blew")
	assert_false(_gone(second), "the hurt one is blinking, not gone yet")
	assert_true(second.get(&"_dying"), "the blast set it off")
	assert_false(_gone(far), "out of the first blast's reach")
	assert_false(full.get(&"_dying"), "damage 1 does not kill a full-HP bomber: no chain there")
	await wait_physics_frames(18)   # 0.65 s
	assert_eq(get_signal_emit_count(EventBus, "explosion"), 2, "0.3 s later the second blew")
	assert_true(_gone(second))
	assert_true(_gone(far), "and its blast killed what was near it")
	assert_eq(RunState.kills, kills_before + 3, "all of the chain is the player's")


func test_a_bomber_blows_once() -> void:
	_in_session()
	RunState.invincible = true
	var bomber := await _spawn(BOMBER, OPEN + Vector2(1.2, 0))
	await wait_physics_frames(3)
	assert_true(bomber.is_fuse_lit())
	watch_signals(EventBus)
	await wait_physics_frames(24)   # about 0.15 s of the 0.6 s windup left
	var left: float = bomber.get(&"_fuse_left")
	assert_lt(left, Tuning.bomber_death_fuse, "less windup left than a death fuse")
	bomber.health.take(DamageInfo.make(99, &"projectile", &"player"))
	await wait_physics_frames(int(ceil(left * 60.0)) + 2)
	assert_eq(get_signal_emit_count(EventBus, "explosion"), 1, "it blew at the earlier time")
	await wait_physics_frames(40)
	assert_eq(get_signal_emit_count(EventBus, "explosion"), 1, "and only once")


func test_a_dying_bomber_takes_no_shots() -> void:
	_in_session()
	var bomber := await _held(BOMBER, OPEN + Vector2(4, 0))
	var behind := await _held(CHASER, OPEN + Vector2(5.5, 0))
	var behind_hp: float = behind.health.hp()
	bomber.health.take(DamageInfo.make(99, &"projectile", &"player"))
	await wait_physics_frames(1)
	RunState.spawn(PROJECTILE, player.global_position + Vector2(T, 0), {&"velocity": Vector2(1200, 0)})
	await wait_physics_frames(10)
	assert_false(_gone(bomber), "still blinking")
	assert_eq(behind.health.hp(), behind_hp - 1.0, "the shot went through the dead bomber into what is behind it")


func test_an_explosive_shot_sets_a_bomber_off() -> void:
	_in_session()
	var gift := RuleDB.get_edit(&"edit_gift_explode")
	RunState.add_ai(gift, &"edit")
	var bomber := await _held(BOMBER, OPEN + Vector2(5, 0), 1.0)
	watch_signals(EventBus)
	RunState.spawn(PROJECTILE, player.global_position + Vector2(T, 0), {&"velocity": Vector2(1200, 0)})
	await wait_physics_frames(40)
	RunState.remove_ai(gift, &"expired")
	assert_true(_gone(bomber))
	assert_eq(get_signal_emit_count(EventBus, "explosion"), 2, "the shot's blast, then the bomber's")


func test_the_last_kill_s_blast_keeps_the_win() -> void:
	_in_session(&"s1_06_playground")
	var loop: RunLoop = game.run_loop
	loop.set_goal(SessionDef.KILLS, RunState.kills + 1)
	var bomber := await _held(BOMBER, OPEN + Vector2(1.5, 0))
	assert_false(bomber.is_fuse_lit(), "1.5 tiles is outside the trigger range")
	var hp_before := _player_hp()
	var hits := _player_hits()
	bomber.health.take(DamageInfo.make(99, &"projectile", &"player"))
	await wait_physics_frames(30)
	assert_true(_gone(bomber), "it blew next to the player")
	assert_eq(loop.outcome, &"win", "the kill won the run")
	assert_eq(_player_hp(), hp_before, "and its blast does not hurt after the win")
	assert_eq(_player_hits(), hits, "no hit recorded")
