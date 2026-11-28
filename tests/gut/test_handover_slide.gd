extends GutTest
## M47.7b (PLAN 0.9.1): the handover slide. SessionRunner remembers the last direction tried
## while the build could not move (8 ways); the session start point carries it into the next
## session (GameHost.capture_tried -> Main.next_tried -> Genre.carried_tried) when the carry
## applies; when `movement` lands on that player it runs that way at 3x its speed, deaf to the
## input, until a wall or the 1.2 s cap; then the AI says its line once and all is as usual.
## A zero direction touches nothing; a death, a retry, a restart or a boot carry none.

const Fx := preload("res://tests/gut/fixtures.gd")
const BotRuns := preload("res://tools/bot_runs.gd")

const S0 := &"s1_00_nothing"
const S1 := &"s1_01_move"
const S4 := &"s1_04_level"
const LINE := "...too fast. fixing."
const TEST_LOG := "user://m47_7b_test/t.jsonl"

var _live_host: GameHost
var _prev_scene: Node


func after_each() -> void:
	Main.leave_hook = Callable()
	Main.clear_start()
	if _live_host != null and is_instance_valid(_live_host):
		get_tree().current_scene = _prev_scene
		_live_host.free()
	_live_host = null
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(TEST_LOG)
	RunState.clear_pauses()
	CampaignDB.active = false
	CampaignDB.jumped = false
	GameHost.auto_beats = true
	GameHost.auto_play = false
	SaveGame.go_inert()
	RunState.invincible = false
	RunState.reset(0)
	RunState.world = null


## A live host (the current scene) on session `id`, as a bot chain's: nothing holds.
func _live(id: StringName) -> GameHost:
	GameHost.auto_beats = false
	Telemetry.log_path = TEST_LOG
	SaveGame.go_inert()
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var g: Main = load("res://main.tscn").instantiate()
	var h := GameHost.host_for_tools(g)
	_live_host = h
	get_tree().root.add_child(h)
	_prev_scene = get_tree().current_scene
	get_tree().current_scene = h
	h.tools = false
	assert_true(h.is_live() and g.is_live_game())
	await wait_physics_frames(2)
	return h


## The game scene on session `id`, unhosted, its start carrying `tried` (and `start`).
func _game(id: StringName, tried := Vector2.ZERO, start := Main.NO_START) -> Main:
	Telemetry.log_path = TEST_LOG
	SaveGame.go_inert()
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	Main.next_seed = 7
	Main.next_start = start
	Main.next_tried = tried
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(1)
	return game


func _scripted(g: Main, move := Vector2.ZERO) -> PlayerInput:
	var input := Fx.ScriptedInput.new()
	g.player.set_input(input)
	input.move = move
	return input


## How many times the session said (or queued) the slide's line.
func _line_count(g: Main) -> int:
	var n := g.session_runner.said.count(LINE)
	for l in g.session_runner.queued_lines():
		if l.text == LINE:
			n += 1
	return n


# --- The tried direction -----------------------------------------------------------------------

func test_the_runner_remembers_the_last_tried_direction_snapped_to_8_ways() -> void:
	var g := await _game(S0)
	var runner := g.session_runner
	assert_true(g.player.movement_locked, "S0 cannot move")
	var input := _scripted(g)
	await wait_physics_frames(2)
	assert_eq(runner.last_tried, Vector2.ZERO, "nothing tried yet")
	input.move = Vector2.LEFT
	await wait_physics_frames(2)
	assert_eq(runner.last_tried, Vector2.LEFT)
	input.move = Vector2.ZERO
	await wait_physics_frames(2)
	assert_eq(runner.last_tried, Vector2.LEFT, "a release keeps the last one")
	input.move = Vector2(0.6, -0.75)
	await wait_physics_frames(2)
	assert_eq(runner.last_tried, Vector2(1, -1).normalized(), "a diagonal snaps to 8 ways")
	assert_almost_eq(runner.last_tried.length(), 1.0, 0.0001, "a unit vector")
	input.move = Vector2(0.97, -0.2)
	await wait_physics_frames(2)
	assert_eq(runner.last_tried, Vector2.RIGHT, "a stick near an axis snaps to it")
	input.move = Vector2(0.1, 0.1)
	await wait_physics_frames(2)
	assert_eq(runner.last_tried, Vector2.RIGHT, "a dead-zone nudge is no try")
	assert_eq(g.player.global_position, g.arena.player_start, "the body never moved")


func test_a_session_that_can_move_remembers_no_try() -> void:
	var g := await _game(S1)
	_scripted(g, Vector2.LEFT)
	await wait_physics_frames(5)
	assert_eq(g.session_runner.last_tried, Vector2.ZERO)
	assert_eq(g.session_runner.tried, 0)


# --- The carry ---------------------------------------------------------------------------------

func test_the_capture_carries_the_direction_only_with_the_start() -> void:
	var g := await _game(S0)
	g.session_runner.last_tried = Vector2.LEFT
	var s1 := CampaignDB.get_session(S1)
	g.debrief.open(RunState.session, &"stop", 0)
	assert_true(GameHost.capture_start(g, s1).is_finite(), "S0 -> S1 carries")
	assert_eq(GameHost.capture_tried(g, s1), Vector2.LEFT)
	assert_eq(GameHost.capture_tried(g, CampaignDB.get_session(&"s2_01_tryout")), Vector2.ZERO, "another stage")
	g.debrief.close()
	g.debrief.open(RunState.session, &"lose", 0)
	assert_eq(GameHost.capture_tried(g, s1), Vector2.ZERO, "a death carries nothing")
	assert_eq(GameHost.capture_tried(null, s1), Vector2.ZERO)


func test_restart_retry_the_title_and_a_boot_carry_no_direction() -> void:
	var g := await _game(S0, Vector2.LEFT)
	assert_eq(Main.next_tried, Vector2.ZERO, "consumed in _ready, as next_start")
	assert_eq(g.run_loop.start_tried, Vector2.LEFT, "the start has it")
	assert_false(g.player.is_sliding(), "no movement granted: no slide")
	Main.next_tried = Vector2.LEFT
	g.menu_restart()
	assert_eq(Main.next_tried, Vector2.ZERO, "the pause menu's Restart")
	Main.next_tried = Vector2.LEFT
	g.start_new_build(5)
	assert_eq(Main.next_tried, Vector2.ZERO, "Restart / F5")
	Main.next_tried = Vector2.LEFT
	Main.leave_hook = func(_p: String) -> void: pass
	g._leave_to(StartScreen.TITLE_SCENE)
	assert_eq(Main.next_tried, Vector2.ZERO, "the title")
	g.free()
	# A boot or a resume into S1: nothing was captured, so nothing slides.
	var boot := await _game(S1)
	assert_eq(boot.run_loop.start_tried, Vector2.ZERO)
	assert_false(boot.player.is_sliding())


func test_a_retry_from_the_debrief_carries_no_direction() -> void:
	var h := await _live(S0)
	var g := h.game
	_scripted(g, Vector2.LEFT)
	await wait_physics_frames(3)
	assert_eq(g.session_runner.last_tried, Vector2.LEFT)
	g.debrief.input_delay = 0.0
	g._on_report_ready(&"lose")
	g.debrief.finish_lines()
	g._end_session(&"retry")
	assert_eq(Main.next_tried, Vector2.ZERO)
	await wait_process_frames(3)
	assert_eq(RunState.session.id, S0)
	assert_eq(h.game.run_loop.start_tried, Vector2.ZERO)


# --- The slide ---------------------------------------------------------------------------------

## The whole way: a "left" try in S0, Next, and S1 starts with the slide: left at 3x, deaf to
## the input, to the left wall; then the line once, and speed and input are the usual ones.
func test_a_left_try_in_s0_slides_s1_to_the_left_wall() -> void:
	var h := await _live(S0)
	var g := h.game
	_scripted(g, Vector2.LEFT)
	await wait_physics_frames(3)
	assert_eq(g.session_runner.last_tried, Vector2.LEFT)
	var wall_x: float = Tuning.TILE
	g.player.global_position = Vector2(wall_x + 400.0, g.arena.player_start.y)
	g.debrief.input_delay = 0.0
	g.run_loop.end(&"stop")
	for f in 300:
		if g.debrief.is_open():
			break
		await wait_physics_frames(1)
	assert_true(g.debrief.is_open())
	g.debrief.finish_lines()
	g._end_session(&"next")
	assert_eq(Main.next_tried, Vector2.LEFT, "the start point carries the direction")
	await wait_process_frames(3)
	assert_false(is_instance_valid(g), "a fresh instance")
	g = h.game
	assert_eq(RunState.session.id, S1)
	assert_eq(Main.next_tried, Vector2.ZERO, "consumed")
	assert_eq(g.run_loop.start_tried, Vector2.LEFT)
	var p := g.player
	assert_true(p.is_sliding(), "movement landed on a start with a tried direction")
	assert_false(p.slid)
	var input := _scripted(g, Vector2.RIGHT)   # the player pushes the other way: ignored
	var normal: float = Tuning.player_speed * RunState.rules.player_speed_mult
	var peak := 0.0
	var ticks := 0
	var last_x := p.global_position.x
	var start_y := p.global_position.y
	while p.is_sliding() and ticks < 200:
		await wait_physics_frames(1)
		if p.is_sliding():
			# 0.1: the wall's own push-out on the contact tick.
			assert_lte(p.global_position.x, last_x + 0.1, "never to the right while it slides")
			peak = maxf(peak, -p.velocity.x)
		last_x = p.global_position.x
		ticks += 1
	assert_almost_eq(peak, normal * Tuning.handover_slide_mult, 1.0, "3x the normal speed")
	assert_true(p.slid, "over")
	assert_lt(float(ticks) / 60.0, Tuning.handover_slide_cap, "the wall ended it, not the cap")
	assert_lt(p.global_position.x, wall_x + 40.0, "at the left wall")
	assert_gt(p.global_position.x, wall_x)
	assert_almost_eq(p.global_position.y, start_y, 0.01, "straight left")
	assert_lte(p.velocity.length(), normal + 0.01, "the wall stopped it: no speed left over")
	await wait_physics_frames(3)
	assert_eq(_line_count(g), 1, "the AI says it")
	# Speed and input are the usual ones again.
	var from_x := p.global_position.x
	var fastest := 0.0
	for f in 40:
		await wait_physics_frames(1)
		fastest = maxf(fastest, p.velocity.length())
	assert_gt(p.global_position.x, from_x + 100.0, "the input moves it again")
	assert_almost_eq(fastest, normal, 1.0, "at the normal speed")
	input.move = Vector2.ZERO
	await wait_physics_frames(30)
	assert_eq(_line_count(g), 1, "once")
	assert_false(p.is_sliding())


## In the open (the wall is 32 tiles away) the cap ends it: 1.2 s of game time.
func test_in_an_open_arena_the_cap_ends_the_slide() -> void:
	var g := await _game(S1, Vector2.LEFT)
	var p := g.player
	assert_true(p.is_sliding())
	var input := _scripted(g, Vector2.DOWN)
	var from := p.global_position
	var t0 := RunState.game_time
	var ticks := 0
	while p.is_sliding() and ticks < 200:
		await wait_physics_frames(1)
		ticks += 1
	assert_true(p.slid)
	assert_almost_eq(RunState.game_time - t0, Tuning.handover_slide_cap, 0.05, "the cap, in game time")
	assert_gt(p.global_position.x, Tuning.TILE * 3.0, "no wall reached")
	assert_lt(p.global_position.x, from.x - 800.0, "a long way left")
	assert_almost_eq(p.global_position.y, from.y, 1.0, "the held key did nothing meanwhile")
	assert_lte(p.velocity.length(), Tuning.player_speed + 0.01, "the normal speed at once")
	input.move = Vector2.ZERO
	await wait_physics_frames(40)
	assert_eq(p.velocity, Vector2.ZERO, "it comes to rest")
	assert_eq(_line_count(g), 1)


func test_a_diagonal_slide_ends_at_the_first_wall() -> void:
	var g := await _game(S1, Vector2(1, 1).normalized())
	var p := g.player
	_scripted(g)
	var from := p.global_position
	var ticks := 0
	while p.is_sliding() and ticks < 200:
		await wait_physics_frames(1)
		ticks += 1
	assert_true(p.slid)
	assert_lt(float(ticks) / 60.0, Tuning.handover_slide_cap, "the bottom wall, before the cap")
	assert_gt(p.global_position.x, from.x + 100.0)
	assert_gt(p.global_position.y, from.y + 100.0)
	assert_almost_eq(p.global_position.x - from.x, p.global_position.y - from.y, 20.0, "along the diagonal")
	var rest := p.global_position
	await wait_physics_frames(10)
	assert_almost_eq(p.global_position.x, rest.x, 1.0, "stopped at the first wall: no run along it")


func test_movement_added_later_starts_the_slide_then() -> void:
	var g := await _game(S0, Vector2.UP)
	var p := g.player
	_scripted(g)
	await wait_physics_frames(5)
	assert_false(p.is_sliding(), "S0 cannot move yet")
	assert_eq(p.global_position, g.arena.player_start)
	RunState.add_basic(&"movement")
	assert_true(p.is_sliding(), "movement granted: it goes")
	await wait_physics_frames(10)
	assert_lt(p.global_position.y, g.arena.player_start.y - 10.0)
	RunState.add_basic(&"movement")
	var ticks := 0
	while p.is_sliding() and ticks < 200:
		await wait_physics_frames(1)
		ticks += 1
	assert_true(p.slid)
	assert_false(p.is_sliding(), "one slide per start")


# --- Zero is a no-op ---------------------------------------------------------------------------

## The same scripted input on two S1 games: with a zero direction the body is the plain one
## (no slide state, the normal speed, no line), tick by tick the same as a second zero run;
## with a direction the same ticks differ (so the comparison would catch a leak).
func test_a_zero_direction_changes_nothing() -> void:
	var runs: Array = []
	for tried: Vector2 in [Vector2.ZERO, Vector2.ZERO, Vector2.LEFT]:
		var g := await _game(S1, tried)
		var p := g.player
		var input := _scripted(g)
		var normal: float = Tuning.player_speed * RunState.rules.player_speed_mult
		var trace: Array[Vector2] = []
		for f in 90:
			input.move = Vector2.RIGHT if f < 30 else (Vector2.UP if f < 60 else Vector2.ZERO)
			await wait_physics_frames(1)
			trace.append(p.global_position)
			if tried == Vector2.ZERO:
				assert_false(p.is_sliding())
				assert_eq(p.mover.speed, normal, "the normal speed, every tick")
				assert_lte(p.velocity.length(), normal + 0.01)
		if tried == Vector2.ZERO:
			assert_false(p.slid)
			assert_eq(p.slide_dir(), Vector2.ZERO)
			assert_eq(_line_count(g), 0, "no line without a slide")
			assert_gt(trace[29].x, g.arena.player_start.x + 50.0, "the input moved it")
			p.start_slide(Vector2.ZERO)
			assert_false(p.is_sliding(), "a zero slide is nothing")
		runs.append(trace)
		g.free()
		await wait_physics_frames(1)
	assert_eq(runs[0], runs[1], "zero: the same body tick by tick")
	assert_ne(runs[0], runs[2], "a direction: another run")


# --- The line, the lean, the tools -------------------------------------------------------------

func test_the_slid_cue_is_s1s_and_parses_bare() -> void:
	var c := Cue.parse("slid: say guilty: %s" % LINE)
	assert_eq(c.problem, "")
	assert_eq(c.when, &"slid")
	assert_false(c.due({}))
	assert_false(c.due({"slid": false}))
	assert_true(c.due({"slid": true}))
	assert_ne(Cue.parse("slid 2: say guilty: x.").problem, "", "it takes no number")
	var s1 := CampaignDB.get_session(S1)
	var mine := s1.cue_list().filter(func(x: Cue) -> bool: return x.when == &"slid")
	assert_eq(mine.size(), 1)
	assert_eq(mine[0].line.text, LINE)
	assert_eq(s1.cue_list().back(), mine[0], "appended last: the older cues keep their index")
	assert_eq(s1.problems(), [] as Array[String])


func test_the_square_leans_the_way_it_slides() -> void:
	var g := await _game(S1, Vector2.LEFT)
	var strain := g.player.get_node(^"StrainFX") as StrainFX
	assert_eq(strain.wanted(), Vector2.LEFT, "pending or running: the lean is the slide's way")
	var ticks := 0
	while g.player.is_sliding() and ticks < 200:
		await wait_physics_frames(1)
		ticks += 1
	assert_eq(strain.wanted(), Vector2.ZERO, "over: no lean")
	var plain := await _game(S1)
	assert_eq((plain.player.get_node(^"StrainFX") as StrainFX).wanted(), Vector2.ZERO)


func test_the_bot_line_prints_the_direction_only_when_there_is_one() -> void:
	var g := await _game(S1, Vector2(-1, 1).normalized(), Vector2(1500.5, 600.25))
	assert_true(BotRuns.end_text(g).ends_with(" start=1500.50,600.25,-1,1"), BotRuns.end_text(g))
	g.free()
	var cold := await _game(S1)
	assert_true(BotRuns.end_text(cold).ends_with(" start=1584.00,672.00"), BotRuns.end_text(cold))
