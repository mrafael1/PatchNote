extends GutTest
## PLAN v8 M40: the rule book. RuleEdit and RuleDB, the new WorldRules fields and their
## readers, the 9 edits (each reversible), RuleBook (warning, landing, expiry, clear),
## the edit cue, S4's edit, F2.

const Fx := preload("res://tests/gut/fixtures.gd")
const CHASER := preload("res://entities/enemy_chaser.tscn")
const SHOOTER := preload("res://entities/enemy_shooter.tscn")
const PROJECTILE := preload("res://entities/projectile.tscn")
const ALL := [&"edit_big_enemies", &"edit_bouncy_walls", &"edit_enemy_speed", &"edit_gift_explode", &"edit_gravity_down",
		&"edit_gravity_left", &"edit_gravity_up", &"edit_inverted", &"edit_slowmo", &"edit_tiny_enemies"]
const TICKS := 60


func before_each() -> void:
	SaveGame.go_inert()


func after_each() -> void:
	SaveGame.go_inert()
	CampaignDB.active = false
	RunState.session = null
	RunState.invincible = false
	Engine.time_scale = 1.0


func _game(id := &"s1_04_level") -> Main:
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	return game


## S4 with nothing happening on its own: no spawner, no cues, no reactions.
func _still_game() -> Main:
	var game := await _game()
	game.spawner.enabled = false
	game.session_runner.set_physics_process(false)
	game.reactions.set_physics_process(false)
	RunState.invincible = true
	return game


func _edit(id: StringName) -> RuleEdit:
	return RuleDB.get_edit(id)


# --- RuleEdit and RuleDB --------------------------------------------------------------

func test_the_ten_edits_load_and_are_fine() -> void:
	var ids: Array = RuleDB.all().map(func(e: RuleEdit) -> StringName: return e.id)
	assert_eq(ids, ALL)
	for e in RuleDB.all():
		assert_eq(RuleDB.problems(e), [] as Array[String], String(e.id))
		assert_true(e.is_ai_tier(), String(e.id))
		assert_null(MutationDB.get_mutation(e.id), "not a patch: %s" % e.id)


func test_edit_problems_are_reported() -> void:
	var e := RuleEdit.new()
	e.id = &"bad"
	e.target = &"sky"
	e.point_at = &"moon"
	e.duration = -1.0
	e.conflicts = [&"edit_nope"]
	e.warn_line = "happy:"
	var text := "\n".join(RuleDB.problems(e))
	for expected in ["starts with edit_", "unknown target sky", "unknown point_at moon", "must be >= 0",
			"unknown edit edit_nope", "empty line"]:
		assert_string_contains(text, expected)


func test_expire_ai_takes_a_reason() -> void:
	var e := _edit(&"edit_slowmo")
	assert_true(RunState.add_ai(e, &"edit"))
	RunState.expire_ai(&"edit", &"cleared")
	var last: Dictionary = RunState.run_log.back()
	assert_eq([last.event, last.reason], [&"ai_remove", &"cleared"])
	RunState.reset(1)


# --- each edit does what it says and goes back exactly --------------------------------

func _capture(game: Main) -> Dictionary:
	var enemies: Array = []
	for n in get_tree().get_nodes_in_group(&"enemy"):
		var cs := n.get_node("CollisionShape2D") as Node2D
		var health := Component.find(n, Health) as Health
		enemies.append([cs.scale, (n.get_node("Visual") as Node2D).scale, n.call(&"body_half") if n.has_method(&"body_half") else 0.0,
				snappedf((n.get_node("Mover") as Mover).speed, 0.001), health.max_hp(), health.hp()])
	var rules := RunState.rules.to_dict()
	return {"rules": JSON.stringify(rules), "enemies": enemies, "time": Engine.time_scale,
			"patch_state": RunState.patch_state.keys(), "ai": RunState.ai.size(),
			"player_speed": snappedf(game.player.mover.speed, 0.001)}


func test_every_edit_is_reversible() -> void:
	for id: StringName in ALL:
		var game := await _still_game()
		var p: Vector2 = game.player.global_position
		RunState.spawn(CHASER, p + Vector2(400, 0))
		RunState.spawn(SHOOTER, p + Vector2(-400, 0))
		await wait_physics_frames(2)
		var before := _capture(game)
		var e := _edit(id)
		assert_true(RunState.add_ai(e, &"edit"), String(id))
		await wait_physics_frames(2)
		RunState.spawn(CHASER, p + Vector2(0, 300))   # one born under the edit
		await wait_physics_frames(2)
		if id != &"edit_gift_explode":   # the gift listens; it changes no rule
			assert_ne(JSON.stringify(RunState.rules.to_dict()), before.rules, "%s changes a rule" % id)
		RunState.remove_ai(e, &"expired")
		for n in get_tree().get_nodes_in_group(&"enemy"):
			if n.global_position.distance_to(p + Vector2(0, 300)) < 200.0:
				n.queue_free()   # compare the same enemies as before
		await wait_physics_frames(2)
		var after := _capture(game)
		for key: String in before:
			assert_eq(after[key], before[key], "%s: %s back" % [id, key])
		game.queue_free()
		await wait_physics_frames(2)


func test_big_and_tiny_enemies_change_size_speed_and_hp() -> void:
	var game := await _still_game()
	var e := RunState.spawn(CHASER, game.player.global_position + Vector2(500, 0)) as Node2D
	await wait_physics_frames(2)
	var health := Component.find(e, Health) as Health
	var base_hp := health.max_hp()
	var base_half: float = e.body_half()
	var mover := Component.find(e, Mover) as Mover
	var shooter := RunState.spawn(SHOOTER, game.player.global_position + Vector2(-500, 0))
	await wait_physics_frames(2)
	var shooter_mover := Component.find(shooter, Mover) as Mover
	var base_speed := mover.speed
	var base_shooter_speed := shooter_mover.speed
	RunState.add_ai(_edit(&"edit_big_enemies"), &"edit")
	await wait_physics_frames(2)
	assert_almost_eq(mover.speed, base_speed * 0.7, 0.01, "big: slower")
	assert_almost_eq(shooter_mover.speed, base_shooter_speed * 0.7, 0.01, "shooters too")
	assert_almost_eq(e.body_half(), base_half * 1.8, 0.01)
	assert_eq((e.get_node("Visual") as Node2D).scale, Vector2.ONE * 1.8)
	assert_almost_eq(health.max_hp(), base_hp + 1.0, 0.001)
	assert_almost_eq(e.contact_reach(), Tuning.contact_range + base_half * 1.8 - 15.0, 0.01)
	assert_false(RunState.can_add_ai(_edit(&"edit_tiny_enemies")), "big and tiny conflict")
	RunState.remove_ai(_edit(&"edit_big_enemies"), &"expired")
	RunState.add_ai(_edit(&"edit_tiny_enemies"), &"edit")
	await wait_physics_frames(2)
	assert_almost_eq(e.body_half(), base_half * 0.5, 0.01)
	assert_almost_eq(mover.speed, base_speed * 1.4, 0.01, "tiny: faster")
	assert_eq(health.max_hp(), 1.0, "one hit each")


func test_inverted_turns_the_movement_not_the_aim() -> void:
	var game := await _still_game()
	var input := Fx.ScriptedInput.new()
	game.player.set_input(input)
	input.move = Vector2.RIGHT
	input.aim_dir = Vector2.RIGHT
	await wait_physics_frames(2)
	assert_eq(game.player.mover.wish, Vector2.RIGHT)
	RunState.add_ai(_edit(&"edit_inverted"), &"edit")
	await wait_physics_frames(2)
	assert_almost_eq(game.player.mover.wish.x, -1.0, 0.0001)
	assert_almost_eq(game.player.mover.wish.y, 0.0, 0.0001)
	var aim := game.player.get_node("Aim") as Node2D
	assert_almost_eq(aim.rotation, 0.0, 0.001, "aim is the player's own: still right")
	input.fire = true
	await wait_physics_frames(3)
	var shots := get_tree().get_nodes_in_group(&"player_projectile")
	assert_gt(shots.size(), 0)
	for s in shots:
		assert_gt((s as Node2D).global_position.x, game.player.global_position.x, "the shot goes right")


func test_slowmo_slows_time_and_gives_it_back() -> void:
	var game := await _still_game()
	RunState.add_ai(_edit(&"edit_slowmo"), &"edit")
	assert_almost_eq(Engine.time_scale, 0.6, 0.001)
	RunState.remove_ai(_edit(&"edit_slowmo"), &"expired")
	assert_almost_eq(Engine.time_scale, 1.0, 0.001)
	assert_not_null(game)


func test_bouncy_walls_send_a_body_back_off_a_wall() -> void:
	for bouncy: bool in [false, true]:
		var game := await _still_game()
		if bouncy:
			RunState.add_ai(_edit(&"edit_bouncy_walls"), &"edit")
			assert_eq(RunState.rules.projectile_max_bounces, RunState.base_rules.projectile_max_bounces + 2)
		var player := game.player
		player.movement_locked = true
		player.global_position = Vector2(game.arena.bounds.position.x + Tuning.TILE + 40.0, player.global_position.y)
		player.velocity = Vector2(-500, 0)
		var bounced := false
		for i in 20:
			await wait_physics_frames(1)
			if player.velocity.x > 0.0:
				bounced = true
		assert_eq(bounced, bouncy, "bounce %s" % bouncy)
		game.queue_free()
		await wait_physics_frames(2)


func test_the_gift_makes_shots_explode_until_it_goes() -> void:
	var game := await _still_game()
	watch_signals(EventBus)
	var p: Vector2 = game.player.global_position
	RunState.add_ai(_edit(&"edit_gift_explode"), &"edit")
	RunState.spawn(PROJECTILE, p, {&"velocity": Vector2(0, -1200)})
	await wait_physics_frames(40)
	assert_signal_emitted(EventBus, "explosion", "a shot into the wall explodes")
	RunState.remove_ai(_edit(&"edit_gift_explode"), &"expired")
	watch_signals(EventBus)
	var count: int = get_signal_emit_count(EventBus, "explosion")
	RunState.spawn(PROJECTILE, p, {&"velocity": Vector2(0, -1200)})
	await wait_physics_frames(40)
	assert_eq(get_signal_emit_count(EventBus, "explosion"), count, "no more after it goes")


func test_gravity_edits_pull_one_way_give_a_jump_and_conflict() -> void:
	var game := await _still_game()
	var book := game.rule_book
	assert_true(book.request(&"edit_gravity_left", &"event", -1.0, false))
	assert_false(book.request(&"edit_gravity_up", &"event", -1.0, false), "conflicts with the pending left")
	await wait_physics_frames(2)
	assert_true(book.is_live(&"edit_gravity_left"))
	assert_eq(RunState.rules.gravity_dir, Vector2.LEFT)
	assert_eq(RunState.rules.jumps, 1)
	assert_true(RunState.in_grace(), "a flip comes with a grace")
	var x0: float = game.player.global_position.x
	await wait_physics_frames(20)
	assert_lt(game.player.global_position.x, x0, "the player falls left")
	assert_false(book.request(&"edit_gravity_up", &"event", -1.0, false), "one gravity at a time")
	assert_true(book.remove(&"edit_gravity_left", &"event"))
	assert_false(RunState.rules.gravity_enabled)


# --- RuleBook -------------------------------------------------------------------------

func test_a_request_warns_then_lands_then_expires_with_its_done_line() -> void:
	var game := await _still_game()
	var book := game.rule_book
	var e := _edit(&"edit_bouncy_walls")
	assert_true(book.request(e.id, &"cue", 2.0))
	assert_true(book.is_pending(e.id))
	assert_false(RunState.rules.wall_bounce, "not before the warning ends")
	assert_true(book.said.has(e.warn().text), "the AI says it first")
	assert_eq(game.mascot.current_text() == "" and game.mascot.queued() == 0, false, "to the mascot")
	assert_true(book._marker.is_showing(), "the marker shows")
	assert_true(game.mascot.body.pointing(), "and it points")
	await wait_physics_frames(roundi(e.warn_seconds * TICKS) - 3)
	assert_false(RunState.rules.wall_bounce)
	await wait_physics_frames(5)
	assert_true(RunState.rules.wall_bounce, "it lands after warn_seconds")
	assert_false(book._marker.is_showing())
	assert_eq(book.landed.size(), 1)
	assert_false(book.request(e.id), "already live")
	await wait_physics_frames(2 * TICKS + 5)
	assert_false(RunState.rules.wall_bounce, "the 2 s override ran out")
	assert_true(book.said.has(e.done().text), "and the AI says so")


func test_the_session_end_clears_every_edit_without_lines() -> void:
	var game := await _still_game()
	var book := game.rule_book
	book.request(&"edit_slowmo", &"cue", -1.0, false)
	await wait_physics_frames(2)
	assert_almost_eq(Engine.time_scale, 0.6, 0.001)
	book.request(&"edit_big_enemies")   # pending when the session ends
	var said := book.said.size()
	game.run_loop.end(&"lose")
	await wait_physics_frames(3)
	assert_true(RunState.ai.is_empty())
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "the debrief runs at full speed")
	assert_true(RunState.run_log.any(func(ev: Dictionary) -> bool:
			return ev.get("event") == &"ai_remove" and ev.get("reason") == &"cleared"))
	await wait_physics_frames(roundi(2.0 * TICKS))
	assert_true(RunState.ai.is_empty(), "the pending one never lands")
	assert_eq(book.said.size(), said, "no done lines")


func test_muted_the_edit_still_lands_with_its_marker() -> void:
	var game := await _still_game()
	var book := game.rule_book
	book.muted = true
	assert_true(book.request(&"edit_inverted"))
	assert_true(book.said.is_empty())
	assert_true(book._marker.is_showing())
	await wait_physics_frames(roundi(1.5 * TICKS) + 3)
	assert_true(book.is_live(&"edit_inverted"))


func test_s4_bends_its_walls_at_12_s_for_10_s() -> void:
	var game := await _game()
	game.spawner.enabled = false
	RunState.invincible = true
	var cue := game.session_runner._cues.filter(func(c: Cue) -> bool: return c.action == &"edit")
	assert_eq(cue.size(), 1)
	assert_eq([cue[0].value, cue[0].target, cue[0].seconds], [12.0, &"edit_bouncy_walls", 10.0])
	game.run_loop.goal_clock = 12.0
	await wait_physics_frames(2)
	assert_true(game.rule_book.is_pending(&"edit_bouncy_walls"))
	await wait_physics_frames(roundi(1.5 * TICKS) + 2)
	assert_true(game.rule_book.is_live(&"edit_bouncy_walls"))
	assert_almost_eq(game.rule_book.seconds_left(&"edit_bouncy_walls"), 10.0, 0.1)


func test_the_bot_can_drop_and_inject_cues() -> void:
	var game := await _game()
	var runner := game.session_runner
	runner.drop_cues(&"edit")
	assert_true(runner._cues.all(func(c: Cue) -> bool: return c.action != &"edit"))
	assert_eq(CampaignDB.get_session(&"s1_04_level").cue_list().size(), 1, "the session's own cues are untouched")
	assert_eq(runner.inject("at 3: edit edit_slowmo").problem, "")
	assert_eq(runner._cues.size(), runner._fired.size())


func test_f2_requests_and_takes_back_an_edit() -> void:
	var game := await _still_game()
	game.debug.toggle_edit(&"edit_tiny_enemies")
	assert_true(game.rule_book.is_pending(&"edit_tiny_enemies"), "with its warning")
	await wait_physics_frames(roundi(1.5 * TICKS) + 3)
	assert_true(game.rule_book.is_live(&"edit_tiny_enemies"))
	game.debug.toggle_edit(&"edit_tiny_enemies")
	assert_false(game.rule_book.is_live(&"edit_tiny_enemies"))
	assert_true(RunState.ai.is_empty())


func test_edits_land_in_the_telemetry() -> void:
	var game := await _still_game()
	game.rule_book.request(&"edit_inverted", &"cue", -1.0, false)
	await wait_physics_frames(2)
	var rec := CampaignDB.telemetry_record(RunState.session, {}, &"won", 0, &"next", "M40", null, [],
			game.rule_book.landed)
	assert_eq(rec.edits.size(), 1)
	assert_eq(rec.edits[0].id, "edit_inverted")


# --- the edit cue ---------------------------------------------------------------------

func test_the_edit_cue_takes_an_optional_duration() -> void:
	var c := Cue.parse("at 12: edit edit_bouncy_walls 10")
	assert_eq([c.problem, c.target, c.seconds], ["", &"edit_bouncy_walls", 10.0])
	c = Cue.parse("at 12: edit edit_bouncy_walls")
	assert_eq([c.problem, c.seconds], ["", -1.0])
	for bad in ["at 5: edit x 0", "at 5: edit x y", "at 5: edit", "at 5: add health 3"]:
		assert_ne(Cue.parse(bad).problem, "", bad)


func test_the_marker_sits_on_the_edge_towards_its_target() -> void:
	var view := Vector2(1280, 720)
	var right := EditMarker.edge_position(Vector2(5000, 360), view)
	assert_almost_eq(right.x, view.x - EditMarker.INSET, 0.5)
	var centre := EditMarker.edge_position(view * 0.5, view)
	assert_almost_eq(centre.x, view.x * 0.5, 0.5)
	assert_lt(centre.y, view.y * 0.5, "at the top, under the HUD")


# --- determinism ----------------------------------------------------------------------

## The same seed and the same edits replay the same S4, frame for frame, edit log
## included (PLAN v8 1.4: the rule book counts its own ticks).
func test_same_seed_same_edits_same_session() -> void:
	var traces: Array[Array] = []
	var logs: Array[String] = []
	for run in 2:
		await wait_physics_frames(1)   # a physics frame boundary, as test_stages does
		Main.next_seed = 4343
		var game := await _game()
		RunState.invincible = true
		game.player.set_bot(true)
		game.session_runner.drop_cues(&"edit")
		game.session_runner.inject("at 2: edit edit_bouncy_walls 3")
		game.session_runner.inject("at 6: edit edit_big_enemies 3")
		var trace: Array[int] = []
		for f in 660:
			if f % 10 == 0:
				trace.append(_world_hash(game))
			await wait_physics_frames(1)
		assert_eq(game.rule_book.landed.size(), 2, "both landed")
		var ai_log := RunState.run_log.filter(func(ev: Dictionary) -> bool:
				return String(ev.get("event", "")) in ["ai_apply", "ai_remove", "edit_landed", "edit_requested"])
		logs.append(JSON.stringify(ai_log))
		traces.append(trace)
		game.queue_free()
		await wait_physics_frames(1)
		RunState.reset(0)
		RunState.world = null
	assert_eq(logs[0], logs[1], "the same edits on the same frames")
	for i in mini(traces[0].size(), traces[1].size()):
		if traces[0][i] != traces[1][i]:
			fail_test("diverges at frame %d" % (i * 10))
			break
	assert_eq(hash(traces[0]), hash(traces[1]))


## M42: S6 the same way, with the gift, a kill-cued edit and the HP cue really landing
## (600 frames of S6 as shipped would land none of them).
func test_same_seed_same_s6() -> void:
	var traces: Array[Array] = []
	var logs: Array[String] = []
	for run in 2:
		await wait_physics_frames(1)
		Main.next_seed = 4343
		var game := await _game(&"s1_06_playground")
		RunState.invincible = true
		game.player.set_bot(true)
		game.session_runner.drop_cues(&"edit")
		game.session_runner.inject("at 2: edit edit_gift_explode")
		game.session_runner.inject("kills 1: edit edit_big_enemies 3")
		game.session_runner.inject("hp 4: edit edit_slowmo")
		var h := Component.find(game.player, Health) as Health
		var trace: Array[int] = []
		for f in 700:
			if f == 300:
				h.hp_ratio = 4.0 / h.max_hp()   # a scripted hit
			if f % 10 == 0:
				trace.append(_world_hash(game))
			await wait_physics_frames(1)
		var ids: Array = game.rule_book.landed.map(func(l: Dictionary) -> String: return l.id)
		ids.sort()
		assert_eq(ids, ["edit_big_enemies", "edit_gift_explode", "edit_slowmo"], "all three landed")
		var ai_log := RunState.run_log.filter(func(ev: Dictionary) -> bool:
				return String(ev.get("event", "")) in ["ai_apply", "ai_remove", "edit_landed", "edit_requested"])
		logs.append(JSON.stringify(ai_log))
		traces.append(trace)
		game.queue_free()
		await wait_physics_frames(1)
		RunState.reset(0)
		RunState.world = null
		Engine.time_scale = 1.0
	assert_eq(logs[0], logs[1], "the same edits on the same frames")
	for i in mini(traces[0].size(), traces[1].size()):
		if traces[0][i] != traces[1][i]:
			fail_test("diverges at frame %d" % (i * 10))
			break
	assert_eq(hash(traces[0]), hash(traces[1]))


func _world_hash(game: Main) -> int:
	var parts: Array[String] = []
	var p := game.player.global_position
	parts.append("p%.2f,%.2f" % [p.x, p.y])
	var ents: Array[String] = []
	for e: Node in RunState.live_entities():
		var pos := (e as Node2D).global_position
		ents.append("%s%.2f,%.2f" % [e.get(&"kind"), pos.x, pos.y])
	ents.sort()
	parts.append_array(ents)
	parts.append("k%d b%d" % [RunState.kills, RunState.build_number])
	return hash("|".join(parts))


# --- review fixes ---------------------------------------------------------------------

func test_cancelling_one_warning_keeps_the_others_marker() -> void:
	var game := await _still_game()
	var book := game.rule_book
	assert_true(book.request(&"edit_big_enemies"))
	assert_true(book.request(&"edit_bouncy_walls"))
	assert_true(book.remove(&"edit_bouncy_walls"))
	assert_true(book._marker.is_showing(), "big enemies is still warning")
	assert_eq(book._marker.target, &"enemies")
	assert_true(book.remove(&"edit_big_enemies"))
	assert_false(book._marker.is_showing())


## A cue fired inside a frame still gets its whole warning (90 frames at 1.5 s).
func test_a_cue_edit_lands_exactly_warn_seconds_after_the_cue() -> void:
	var game := await _still_game()
	game.session_runner.set_physics_process(true)
	game.session_runner.drop_cues(&"say")
	game.session_runner.inject("at 0.1: edit edit_inverted 5")
	for f in 400:
		await wait_physics_frames(1)
		if game.rule_book.is_live(&"edit_inverted"):
			assert_eq(int(game.rule_book._live[&"edit_inverted"].warned_frames), 90, "never a frame early")
			return
	fail_test("never landed")

func test_the_marker_never_sits_on_the_hud_or_the_mascot() -> void:
	var view := Vector2(1280, 720)
	var up_right := EditMarker.edge_position(Vector2(1200, 40), view)
	assert_gte(up_right.y, EditMarker.TOP_FREE)


func test_a_bounce_keeps_the_speed_along_the_wall() -> void:
	var game := await _still_game()
	RunState.add_ai(_edit(&"edit_bouncy_walls"), &"edit")
	var player := game.player
	player.movement_locked = true
	player.global_position = Vector2(game.arena.bounds.position.x + Tuning.TILE + 30.0, player.global_position.y)
	player.velocity = Vector2(-500, 200)
	for i in 10:
		await wait_physics_frames(1)
		if player.velocity.x > 0.0:
			break
	assert_gt(player.velocity.x, 0.0, "bounced")
	assert_gt(player.velocity.y, 100.0, "still moving down along the wall")


# --- M42: the hp cue in S6 ---------------------------------------------------------------

## S6 with only the given cues, invincible, no spawner.
func _s6_game(cues: Array[String]) -> Main:
	var game := await _game(&"s1_06_playground")
	game.spawner.enabled = false
	RunState.invincible = true
	game.session_runner.drop_cues(&"edit")
	for c in cues:
		game.session_runner.inject(c)
	return game


func _requests(id: String) -> int:
	return RunState.run_log.filter(func(ev: Dictionary) -> bool:
			return ev.get("event") == &"edit_requested" and ev.get("id") == id).size()


func test_s6_slowmo_lands_when_hp_drops() -> void:
	var game := await _s6_game(["hp 2: edit edit_slowmo"] as Array[String])
	var book := game.rule_book
	var h := Component.find(game.player, Health) as Health
	await wait_physics_frames(5)
	assert_false(book.is_pending(&"edit_slowmo"), "not at full HP")
	h.hp_ratio = 3.0 / h.max_hp()
	await wait_physics_frames(3)
	assert_false(book.is_pending(&"edit_slowmo"), "not at 3")
	h.hp_ratio = 2.0 / h.max_hp()
	await wait_physics_frames(2)
	assert_true(book.is_pending(&"edit_slowmo"), "at 2 it warns")
	assert_true(book.said.has(_edit(&"edit_slowmo").warn().text))
	assert_eq(_edit(&"edit_slowmo").warn().expression, &"happy", "D7: not idle")
	await wait_physics_frames(roundi(1.5 * TICKS) + 2)
	assert_true(book.is_live(&"edit_slowmo"))
	assert_almost_eq(Engine.time_scale, 0.6, 0.001)
	# Once: it runs out, HP climbs and drops to 2 again, and nothing is asked.
	await wait_physics_frames(roundi(8.0 * TICKS) + 5)
	assert_false(book.is_live(&"edit_slowmo"), "8 s on the book's own ticks")
	h.hp_ratio = 1.0
	await wait_physics_frames(2)
	h.hp_ratio = 1.0 / h.max_hp()
	await wait_physics_frames(5)
	assert_false(book.is_pending(&"edit_slowmo"))
	assert_eq(_requests("edit_slowmo"), 1, "a cue fires once")
	assert_eq(book.landed.filter(func(l: Dictionary) -> bool: return l.id == "edit_slowmo").size(), 1)


## A kill-cued edit asked during slow-mo's warning waits until slow-mo has landed, so
## its own warning is read before it lands (M42 review).
func test_an_edit_cue_waits_for_a_pending_warning() -> void:
	var game := await _s6_game(["hp 2: edit edit_slowmo", "kills 1: edit edit_big_enemies 3"] as Array[String])
	game.session_runner.drop_cues(&"say")
	var book := game.rule_book
	var h := Component.find(game.player, Health) as Health
	h.hp_ratio = 2.0 / h.max_hp()
	for f in 30:
		await wait_physics_frames(1)
		if book.is_pending(&"edit_slowmo"):
			break
	assert_true(book.is_pending(&"edit_slowmo"))
	RunState.kills += 1
	await wait_physics_frames(3)
	assert_false(book.is_pending(&"edit_big_enemies"), "held while slow-mo's warning plays")
	for f in roundi(2.0 * TICKS):
		await wait_physics_frames(1)
		if book.is_pending(&"edit_big_enemies"):
			break
	assert_true(book.is_live(&"edit_slowmo"), "slow-mo landed first")
	assert_true(book.is_pending(&"edit_big_enemies"), "then big enemies was asked")


## D23: an HP drop during inverted's warning waits until the book is free.
func test_hp_cue_during_inverted_warning() -> void:
	# D23 (M42 E-S6c): an "hp N:" cue waits while the rule book is busy (another edit's
	# warning, a timed edit live), then fires if the HP is still that low.
	var game := await _s6_game(["at 2: edit edit_inverted", "hp 2: edit edit_slowmo"] as Array[String])
	game.session_runner.drop_cues(&"say")
	var book := game.rule_book
	var h := Component.find(game.player, Health) as Health
	var inverted_warn := _edit(&"edit_inverted").warn().text
	var slowmo_warn := _edit(&"edit_slowmo").warn().text
	for f in 200:
		await wait_physics_frames(1)
		if book.is_pending(&"edit_inverted"):
			break
	assert_true(book.is_pending(&"edit_inverted"))
	assert_true(book.busy(), "a warning is pending")
	await wait_physics_frames(30)   # 0.5 s into inverted's warning
	assert_eq(game.mascot.current_text(), inverted_warn)
	h.hp_ratio = 2.0 / h.max_hp()
	await wait_physics_frames(2)
	assert_false(book.is_pending(&"edit_slowmo"), "held while inverted's warning plays")
	assert_false(book.said.has(slowmo_warn))
	await wait_physics_frames(roundi(1.5 * TICKS) + 2)
	assert_true(book.is_live(&"edit_inverted"))
	assert_true(book.busy(), "a timed edit is live")
	assert_false(book.is_pending(&"edit_slowmo") or book.is_live(&"edit_slowmo"),
			"held while inverted is live")
	for f in roundi(11.0 * TICKS):
		await wait_physics_frames(1)
		if not book.is_live(&"edit_inverted"):
			break
	assert_false(book.is_live(&"edit_inverted"), "inverted ran its 10 s")
	await wait_physics_frames(2)
	assert_true(book.is_pending(&"edit_slowmo"), "asked once the book is free, HP still 2")
	assert_true(book.said.has(slowmo_warn))
	await wait_physics_frames(roundi(1.5 * TICKS) + 2)
	assert_true(book.is_live(&"edit_slowmo"))
	assert_eq(book.landed.map(func(l: Dictionary) -> String: return l.id), ["edit_inverted", "edit_slowmo"])

