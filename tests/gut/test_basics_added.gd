extends GutTest
## PLAN v8 M39.2 (owner: "nothing by default"): the campaign's `health` and `hits`
## basics, added live by a session's cue ("at 11: add health"); the session corner shows
## only what the AI has added.

const CHASER := preload("res://entities/enemy_chaser.tscn")
const PROJECTILE := preload("res://entities/projectile.tscn")


func before_each() -> void:
	SaveGame.go_inert()


func after_each() -> void:
	SaveGame.go_inert()
	CampaignDB.active = false
	RunState.session = null
	RunState.session_added.clear()
	RunState.invincible = false


func _game(id: StringName) -> Main:
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	return game


## Only what the test does happens: no spawner, no cues.
func _still(game: Main) -> void:
	game.spawner.enabled = false
	game.session_runner.set_physics_process(false)


## A chaser that stays where it is put (its contact still runs).
func _chaser_at(pos: Vector2) -> Node2D:
	var e := RunState.spawn(CHASER, pos) as Node2D
	await wait_physics_frames(1)
	(e.get_node("Mover") as Node).set_physics_process(false)
	e.global_position = pos
	return e


func _hp(node: Node) -> float:
	return (Component.find(node, Health) as Health).hp()


# --- health -----------------------------------------------------------------------

func test_before_health_enemies_reach_you_and_nothing_happens() -> void:
	var game := await _game(&"s1_02_enemies")
	_still(game)
	assert_true(game.player.damage_locked)
	assert_eq(game.hud._label.text, "", "the corner is empty")
	watch_signals(EventBus)
	var e := await _chaser_at(game.player.global_position + Vector2(10, 0))
	await wait_physics_frames(10)
	assert_eq(_hp(game.player), Tuning.player_max_hp, "no damage")
	assert_signal_not_emitted(EventBus, "player_hit")
	assert_eq(e.visual.rim, 0.0, "no red warning: it cannot hurt")
	assert_true(game.session_runner.touched, "it tried")
	assert_false(RunState.run_log.any(func(ev: Dictionary) -> bool: return ev.get("event") == &"player_hit"),
			"no telemetry hit either")


func test_a_harmless_chaser_stops_at_the_player_instead_of_burying_it() -> void:
	var game := await _game(&"s1_02_enemies")
	_still(game)
	var e := RunState.spawn(CHASER, game.player.global_position + Vector2(200, 0)) as Node2D
	await wait_physics_frames(150)
	var d: float = e.global_position.distance_to(game.player.global_position)
	assert_gt(d, e.contact_reach() * 0.6, "it rings the square, not sits on it")
	assert_lt(d, e.contact_reach() + 20.0, "but it did come all the way")


func test_the_cue_adds_health_live_with_its_hp_and_a_grace() -> void:
	var game := await _game(&"s1_02_enemies")
	game.spawner.enabled = false
	game.run_loop.goal_clock = 11.1
	await wait_physics_frames(2)
	assert_true(&"health" in RunState.session_added)
	assert_true(Unlocks.has_basic(&"health"))
	assert_false(game.player.damage_locked)
	assert_true(RunState.in_grace(), "the rims light before the first bite")
	assert_almost_eq(RunState._grace_until - RunState.game_time, Tuning.health_added_grace, 0.1)
	await wait_physics_frames(1)
	await wait_process_frames(2)   # the corner label is set in Hud._process, not on a physics frame
	assert_eq(game.hud._label.text, "HP %d" % int(Tuning.player_max_hp))
	assert_true(RunState.run_log.any(func(ev: Dictionary) -> bool: return ev.get("event") == &"basic_added"))


func test_once_health_is_added_contact_hurts_after_the_grace() -> void:
	var game := await _game(&"s1_02_enemies")
	_still(game)
	RunState.add_basic(&"health")
	var e := await _chaser_at(game.player.global_position + Vector2(10, 0))
	await wait_physics_frames(3)
	assert_eq(_hp(game.player), Tuning.player_max_hp, "the grace")
	assert_gt(e.visual.rim, 0.0, "the red rim warns now")
	RunState.game_time += Tuning.health_added_grace + 0.1
	await wait_physics_frames(3)
	assert_lt(_hp(game.player), Tuning.player_max_hp, "it bites")


func test_a_late_first_touch_says_nothing() -> void:
	var game := await _game(&"s1_02_enemies")
	game.spawner.enabled = false
	game.run_loop.goal_clock = 5.5   # past the touch cue's deadline
	await wait_physics_frames(2)
	EventBus.player_touched.emit()
	await wait_physics_frames(2)
	var lines := game.session_runner.said + game.session_runner.queued_lines().map(func(l: Line) -> String: return l.text)
	assert_false("...?" in lines, "the AI has moved on")


func test_the_touch_cue_says_its_line_once_something_tried() -> void:
	var game := await _game(&"s1_02_enemies")
	game.spawner.enabled = false
	var before := game.session_runner.line_count()
	EventBus.player_touched.emit()
	await wait_physics_frames(2)
	assert_eq(game.session_runner.line_count(), before + 1)
	var lines := game.session_runner.said + game.session_runner.queued_lines().map(func(l: Line) -> String: return l.text)
	assert_true("...?" in lines)


func test_a_retry_plays_the_session_without_what_was_added() -> void:
	var game := await _game(&"s1_02_enemies")
	RunState.add_basic(&"health")
	assert_true(Unlocks.has_basic(&"health"))
	RunState.reset(7)
	RunState.session = CampaignDB.get_session(&"s1_02_enemies")
	assert_false(Unlocks.has_basic(&"health"), "reset clears what the cue added")
	assert_false(&"health" in CampaignDB.get_session(&"s1_02_enemies").basics, "the SessionDef is never changed")


func test_outside_a_session_health_and_hits_are_always_on() -> void:
	RunState.session = null
	assert_true(Unlocks.has_basic(&"health"))
	assert_true(Unlocks.has_basic(&"hits"))


# --- hits -------------------------------------------------------------------------

func test_before_hits_shots_pass_through_enemies_and_then_they_hit() -> void:
	var game := await _game(&"s1_03_shooting")
	_still(game)
	assert_false(Unlocks.has_basic(&"hits"))
	var start: Vector2 = game.player.global_position + Vector2(60, 0)
	var e := await _chaser_at(start + Vector2(120, 0))
	e.set_physics_process(false)   # no contact, no steering: a target
	var hp := _hp(e)
	RunState.spawn(PROJECTILE, start, {&"velocity": Vector2(900, 0)})
	await wait_physics_frames(20)
	assert_eq(_hp(e), hp, "through it")
	RunState.add_basic(&"hits")
	RunState.spawn(PROJECTILE, start, {&"velocity": Vector2(900, 0)})
	await wait_physics_frames(20)
	assert_lt(_hp(e), hp, "now it hits")


func test_s3_says_nothing_before_its_first_kill_and_keeps_no_stale_warning() -> void:
	var game := await _game(&"s1_03_shooting")
	_still(game)
	game.reactions._defs.assign(CampaignDB.reactions.filter(func(r: ReactionDef) -> bool: return r.id in [&"hp_last", &"first_kill"]))
	game.reactions._busy_until = -1.0
	(Component.find(game.player, Health) as Health).hp_ratio = 1.0 / Tuning.player_max_hp   # 1 HP
	RunState.game_time += 30.0
	game.reactions._physics_process(1.0 / 60.0)
	assert_eq(game.reactions.fired.size(), 0, "quiet before the gun works")
	assert_gt(game.reactions._last_slot, -1, "but it followed (the low HP is seen)")
	RunState.kills = 1
	game.reactions._on_enemy_killed(null, null)
	RunState.game_time += 1.0
	game.reactions._busy_until = -1.0
	game.reactions._physics_process(1.0 / 60.0)
	var ids: Array = game.reactions.fired.map(func(f: Dictionary) -> String: return String(f.id))
	assert_false("hp_last" in ids, "no stale low-HP line at the first kill")
	assert_true("first_kill" in ids, "reactions are back after it")


func test_s3_sends_no_crowd_before_the_gun_can_hit() -> void:
	var game := await _game(&"s1_03_shooting")
	assert_false(game.spawner.enabled, "only the AI's two chasers")
	RunState.add_basic(&"hits")
	assert_true(game.spawner.enabled)
	var s2 := await _game(&"s1_02_enemies")
	assert_true(s2.spawner.enabled, "no gun at all in S2: the overrun runs")


# --- cues and checks -----------------------------------------------------------------

func test_add_and_touch_cues_parse() -> void:
	var add := Cue.parse("at 11: add health")
	assert_eq(add.problem, "")
	assert_eq(add.action, &"add")
	assert_eq(add.target, &"health")
	var touch := Cue.parse("touch: say surprised: ...?")
	assert_eq(touch.problem, "")
	assert_true(touch.due({"touched": true}))
	assert_false(touch.due({"touched": false}))
	var soon := Cue.parse("touch 5: say x")
	assert_eq(soon.problem, "", "touch takes a deadline")
	assert_true(soon.due({"touched": true, "clock": 4.9}))
	assert_false(soon.due({"touched": true, "clock": 5.0}), "too late")
	assert_true(soon.expired({"clock": 5.0}))
	assert_false(touch.expired({"clock": 99.0}), "no deadline, never too late")
	assert_ne(Cue.parse("touch x: say x").problem, "")
	assert_ne(Cue.parse("hit 3: say x").problem, "", "hit takes no number")
	assert_ne(Cue.parse("at 3: add").problem, "", "add what?")


func test_a_session_cannot_add_an_unknown_basic_or_one_it_has() -> void:
	var s := SessionDef.new()
	s.id = &"test_add"
	s.basics = [&"movement"]
	s.cues = PackedStringArray(["at 1: add wings", "at 2: add movement", "at 3: add health"])
	var problems := " ".join(s.problems())
	assert_string_contains(problems, "unknown basic wings")
	assert_string_contains(problems, "already has movement")
	assert_false("health" in problems)


func test_a_basic_a_session_adds_stays_in_the_next_session() -> void:
	var a := CampaignDB.get_session(&"s1_02_enemies").duplicate() as SessionDef
	var b := CampaignDB.get_session(&"s1_03_shooting").duplicate() as SessionDef
	b.basics = [&"movement", &"shooting", &"enemies"]
	var c := CampaignDef.new()
	c.sessions = [a, b]
	assert_string_contains(" ".join(CampaignDB.problems(c)), "adds health but s1_03_shooting does not have it")
	assert_eq(CampaignDB.problems(), [] as Array[String], "the real campaign is fine")


# --- the corner and the leftovers ---------------------------------------------------------

func test_the_corner_shows_only_what_the_ai_added() -> void:
	var game := await _game(&"s1_00_nothing")
	await wait_physics_frames(1)
	assert_eq(game.hud._label.text, "")
	assert_false("Kills" in Hud.session_text(5, ""))
	assert_false("v0." in Hud.session_text(5, "dash ready"))


## M42: the `version` basic, added live, shows the version only (no "build N"), and
## adding it leaves a spawner something else turned off alone (only the basics
## _spawner_wanted() reads touch it).
func test_adding_version_shows_the_stamp_and_leaves_the_spawner_alone() -> void:
	var game := await _game(&"s1_04_level")
	game.spawner.enabled = false
	assert_false("v0." in Hud.session_text(5, ""))
	RunState.add_basic(&"version")
	await wait_physics_frames(1)
	assert_false(game.spawner.enabled, "add version does not re-enable the spawner")
	var text := Hud.session_text(5, "")
	assert_string_contains(text, SaveGame.version().label())
	assert_false("build" in text, "no build N in the campaign stamp")
	assert_eq(text, "HP 5   %s" % SaveGame.version().label())
	await wait_process_frames(2)   # the corner label is set in Hud._process, not on a physics frame
	assert_string_contains(game.hud._label.text, SaveGame.version().label())


## M42: S5 adds the stamp at 15 s (owner: announce in-session); a Retry starts without it.
func test_s5_adds_the_version_stamp_live() -> void:
	var game := await _game(&"s1_05_wrong")
	game.spawner.enabled = false
	RunState.invincible = true
	await wait_physics_frames(1)
	assert_false("v0." in game.hud._label.text, "no stamp at the start")
	assert_false(Unlocks.has_basic(&"version"))
	game.run_loop.goal_clock = 15.0
	await wait_physics_frames(3)
	assert_true(Unlocks.has_basic(&"version"), "added at 15 s")
	await wait_process_frames(2)   # the corner label is set in Hud._process, not on a physics frame
	assert_string_contains(game.hud._label.text, SaveGame.version().label())
	assert_false("build" in game.hud._label.text)
	var texts: Array = game.session_runner.said + game.session_runner.queued_lines().map(func(l: Line) -> String: return l.text)
	assert_true(texts.has("See the number up there? That's my version."), "and says so")
	RunState.reset(7)
	RunState.session = CampaignDB.get_session(&"s1_05_wrong")
	assert_true(RunState.session_added.is_empty())
	assert_false(Unlocks.has_basic(&"version"), "a Retry starts without the stamp")
	assert_false("v0." in Hud.session_text(5, ""))


func test_s6_corner_has_the_version_from_frame_one() -> void:
	var game := await _game(&"s1_06_playground")
	await wait_physics_frames(1)
	assert_true(Unlocks.has_basic(&"version"))
	await wait_process_frames(2)   # the corner label is set in Hud._process, not on a physics frame
	assert_string_contains(game.hud._label.text, SaveGame.version().label())
	assert_string_contains(game.hud._label.text, "HP %d" % int(Tuning.player_max_hp))


## The version cue fires by 20 s of game time and its line waits only behind the intro.
## (Whether the mascot shows it by then cannot be tested headless: the runner paces lines
## by wall-clock reading time, and tests run many times faster than real time.)
func test_s5_version_line_is_queued_by_20_s_behind_the_intro_only() -> void:
	var game := await _game(&"s1_05_wrong")
	RunState.invincible = true
	var line := "See the number up there? That's my version."
	while game.run_loop.goal_clock < 20.0 and not game.run_loop.is_over():
		await wait_physics_frames(1)
	var runner := game.session_runner
	var queued: Array = runner.queued_lines().map(func(l: Line) -> String: return l.text)
	assert_true(runner.said.has(line) or queued.has(line), "the cue fired by 20 s")
	var intro: Array = CampaignDB.get_session(&"s1_05_wrong").intro_lines().map(func(l: Line) -> String: return l.text)
	var ahead: Array = runner.said.duplicate() + queued
	ahead = ahead.slice(0, ahead.find(line))
	assert_eq(ahead, intro, "the intro, then the version line: nothing of the runner's in between")


func test_s4_corner_has_hp_and_the_dash() -> void:
	var game := await _game(&"s1_04_level")
	await wait_physics_frames(1)
	await wait_process_frames(2)   # the corner label is set in Hud._process, not on a physics frame
	assert_eq(game.hud._label.text, "HP %d\ndash ready" % int(Tuning.player_max_hp))


func test_a_stopped_session_plays_no_jingle_and_tab_opens_no_build_log() -> void:
	var game := await _game(&"s1_00_nothing")
	assert_false(game.patch_history.can_open(), "Tab holds the AI's line in a session")
	game.sound._last_ms.clear()
	EventBus.run_ended.emit(&"stopped")
	assert_false(game.sound._last_ms.has(&"lose"))
	assert_false(game.sound._last_ms.has(&"win"))
