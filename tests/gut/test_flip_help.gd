extends GutTest
## M43.2 (G13b): S6's flip is explained. At kill 27 one warning ("your controls flip. I'll
## slow time down.") announces both edits: inverted lands, slow-mo lands quietly right
## after (a quiet edit cue), both for 10 s. While the flip is new, arrows around the player
## show where each input goes now (RuleEdit.landed_hint): gentle under reduce flashing,
## never outside the campaign.

const TICKS := 60
const HINT := preload("res://rules/edit_inverted/inverted_hint.gd")


func before_each() -> void:
	SaveGame.go_inert()


func after_each() -> void:
	SaveGame.go_inert()
	CampaignDB.active = false
	RunState.session = null
	RunState.invincible = false
	RunState.reset(0)
	RunState.world = null
	Engine.time_scale = 1.0


func _game(id := &"s1_06_playground") -> Main:
	await wait_physics_frames(1)
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.spawner.enabled = false
	RunState.invincible = true
	return game


func _hints(game: Main) -> Array:
	return game.player.get_children().filter(func(n: Node) -> bool:
			return n.get_script() == HINT and not n.is_queued_for_deletion())


## Lands edit_inverted now (no warning) and waits for it.
func _flip(game: Main) -> void:
	assert_true(game.rule_book.request(&"edit_inverted", &"console", -1.0, false))
	await wait_physics_frames(2)
	assert_true(game.rule_book.is_live(&"edit_inverted"))


# --- S6's data: one warning, two edits ---------------------------------------------------

func test_s6_flips_and_slows_together_at_kill_27() -> void:
	var game := await _game()
	game.session_runner.drop_cues(&"say")
	var book := game.rule_book
	RunState.kills = 26   # big enemies (14) warns and lands first
	for f in 120:
		await wait_physics_frames(1)
		if book.is_live(&"edit_big_enemies"):
			break
	assert_true(book.is_live(&"edit_big_enemies"))
	assert_false(book.is_pending(&"edit_inverted"))
	RunState.kills = 27
	for f in 10:
		await wait_physics_frames(1)
		if book.is_pending(&"edit_inverted"):
			break
	assert_true(book.is_pending(&"edit_inverted"), "the flip warns at 27")
	assert_false(book.is_pending(&"edit_slowmo"), "slow-mo waits for the warning")
	var warn := RuleDB.get_edit(&"edit_inverted").warn()
	assert_string_contains(warn.text, "controls flip")
	assert_string_contains(warn.text, "slow time")
	assert_lt(warn.text.length() / Mascot.TYPE_CPS, RuleDB.get_edit(&"edit_inverted").warn_seconds,
			"the line is typed before the flip lands")
	var flip_tick := -1
	var slow_tick := -1
	for f in roundi(2.0 * TICKS):
		await wait_physics_frames(1)
		if flip_tick < 0 and book.is_live(&"edit_inverted"):
			flip_tick = f
		if slow_tick < 0 and book.is_live(&"edit_slowmo"):
			slow_tick = f
		if slow_tick >= 0:
			break
	assert_gte(flip_tick, 0, "the flip landed")
	assert_between(slow_tick - flip_tick, 0, 3, "slow-mo lands right after the flip")
	assert_eq(book.said.count(RuleDB.get_edit(&"edit_slowmo").warn().text), 0, "quiet: no line of its own")
	assert_almost_eq(Engine.time_scale, 0.6, 0.001)
	assert_almost_eq(book.seconds_left(&"edit_slowmo"), book.seconds_left(&"edit_inverted"), 0.06,
			"both end together (10 s)")
	assert_eq(_requests(&"edit_slowmo"), 1)
	assert_eq(_hints(game).size(), 1, "the arrows came with the flip")


func test_every_warned_s6_edit_is_typed_before_it_lands() -> void:
	var s := CampaignDB.get_session(&"s1_06_playground")
	var warned := 0
	for c in s.cue_list():
		if c.action != &"edit" or c.quiet:
			continue
		var e := RuleDB.get_edit(c.target)
		assert_not_null(e.warn(), String(e.id))
		assert_lt(e.warn().text.length() / Mascot.TYPE_CPS, e.warn_seconds, String(e.id))
		warned += 1
	assert_eq(warned, 3)
	assert_false(s.cue_list().any(func(c: Cue) -> bool: return c.when == &"hp"), "no hp 2 cue any more")


func _requests(id: StringName) -> int:
	return RunState.run_log.filter(func(ev: Dictionary) -> bool:
			return ev.get("event") == &"edit_requested" and ev.get("id") == String(id)).size()


# --- the arrows ---------------------------------------------------------------------------

func test_the_flip_adds_one_hint_that_goes_after_its_seconds() -> void:
	var game := await _game()
	await _flip(game)
	assert_eq(_hints(game).size(), 1)
	var hint: Node2D = game.rule_book.hint_of(&"edit_inverted")
	assert_not_null(hint)
	assert_eq(hint.get_parent(), game.player)
	await wait_physics_frames(HINT.HINT_TICKS - 10)
	assert_eq(_hints(game).size(), 1, "still up at 3.3 s")
	await wait_physics_frames(15)
	assert_eq(_hints(game).size(), 0, "gone after 3.5 s")
	assert_true(game.rule_book.is_live(&"edit_inverted"), "the flip itself stays")


func test_the_hint_goes_with_the_edit() -> void:
	var game := await _game()
	await _flip(game)
	assert_true(game.rule_book.remove(&"edit_inverted"))
	await wait_physics_frames(1)
	assert_eq(_hints(game).size(), 0, "removed early")
	await _flip(game)
	assert_eq(_hints(game).size(), 1)
	game.rule_book.clear()
	await wait_physics_frames(1)
	assert_eq(_hints(game).size(), 0, "cleared (the session ends)")


func test_the_arrows_point_where_each_input_goes_now() -> void:
	var game := await _game()
	await _flip(game)
	var hint: Node2D = game.rule_book.hint_of(&"edit_inverted")
	var arrows: Array = hint.call(&"arrows")
	assert_eq(arrows.size(), 4)
	var up: Dictionary = arrows[0]
	assert_eq(up.from, Vector2.UP * HINT.RADIUS, "the up input's arrow sits above the player")
	assert_true((up.dir as Vector2).is_equal_approx(Vector2.DOWN), "and points down: the flip")
	var left: Dictionary = arrows[2]
	assert_true((left.dir as Vector2).is_equal_approx(Vector2.RIGHT))
	assert_eq(up.label, OS.get_keycode_string(HINT.layout_label(KEY_W)), "the label is the bound key")


## The move keys are bound by position: the label names the key printed there on the
## player's layout (AZERTY: Z above, Q left), not the QWERTY name of the position.
func test_the_labels_follow_the_keyboard_layout() -> void:
	var azerty := func(physical: Key) -> Key:
		return {KEY_W: KEY_Z, KEY_A: KEY_Q, KEY_Q: KEY_A, KEY_Z: KEY_W}.get(physical, physical)
	assert_eq(HINT.key_label(&"move_up", azerty), "Z")
	assert_eq(HINT.key_label(&"move_left", azerty), "Q")
	assert_eq(HINT.key_label(&"move_down", azerty), "S")
	assert_eq(HINT.key_label(&"move_right", azerty), "D")
	var qwerty := func(physical: Key) -> Key: return physical
	assert_eq(HINT.key_label(&"move_up", qwerty), "W")
	assert_eq(HINT.key_label(&"move_left", qwerty), "A")


func test_the_hint_pulses_or_only_fades_with_reduce_flashing() -> void:
	var game := await _game()
	await _flip(game)
	var hint: Node2D = game.rule_book.hint_of(&"edit_inverted")
	assert_false(hint.get(&"gentle"))
	var alphas := {}
	for f in 60:
		await wait_physics_frames(1)
		alphas[snappedf(hint.modulate.a, 0.05)] = true
	assert_gt(alphas.size(), 3, "it pulses")
	game.rule_book.remove(&"edit_inverted")
	await wait_physics_frames(1)
	SaveGame.set_setting("reduce_flashing", true)
	await _flip(game)
	var gentle: Node2D = game.rule_book.hint_of(&"edit_inverted")
	assert_true(gentle.get(&"gentle"))
	var steady := {}
	for f in 60:
		await wait_physics_frames(1)
		steady[snappedf(gentle.modulate.a, 0.001)] = true
	assert_eq(steady.size(), 1, "steady before the fade")
	gentle.set(&"ticks", HINT.HINT_TICKS - 5)
	assert_lt(gentle.call(&"alpha"), 0.85, "it fades at the end")


func test_the_hint_counts_ticks_not_slowed_time() -> void:
	var game := await _game()
	await _flip(game)
	assert_true(game.rule_book.request(&"edit_slowmo", &"console", -1.0, false))
	await wait_physics_frames(2)
	assert_almost_eq(Engine.time_scale, 0.6, 0.001)
	var hint: Node2D = game.rule_book.hint_of(&"edit_inverted")
	var t0: int = hint.get(&"ticks")
	await wait_physics_frames(60)
	assert_between(int(hint.get(&"ticks")) - t0, 59, 61, "one per physics tick, slow motion or not")


func test_no_hint_outside_the_campaign_or_for_other_edits() -> void:
	var player := Node2D.new()
	add_child_autofree(player)
	RunState.session = null
	assert_null(RuleDB.get_edit(&"edit_inverted").landed_hint(player), "the run loop: no arrows")
	RunState.session = CampaignDB.get_session(&"s1_06_playground")
	var hint := RuleDB.get_edit(&"edit_inverted").landed_hint(player)
	assert_not_null(hint)
	hint.free()
	for e in RuleDB.all():
		if e.id != &"edit_inverted":
			assert_null(e.landed_hint(player), String(e.id))
	RunState.session = null
