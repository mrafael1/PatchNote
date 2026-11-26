extends GutTest
## M47.6c2 (PLAN v9.4 0.8, design 2.7): no reload between Stage 1 sessions. The next session is
## a fresh instance, but the player starts where it stood (GameHost.capture_start, snapped to
## 0.01 px, through Main.next_start), the swap shows no glitch, the room empties during the
## beat and HP refills. A death, a retry, Restart, the title, Stage 2 or a blocked spot start
## cold at player_start, and next_start never outlives the run it was meant for.

const S3 := &"s1_03_shooting"
const S4 := &"s1_04_level"
const S5 := &"s1_05_wrong"
const S6 := &"s1_06_playground"
const S7 := &"s2_01_tryout"
const TEST_LOG := "user://m47_6c2_test/t.jsonl"

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
	SaveGame.set_setting("reduce_flashing", false)
	RunState.clear_pauses()
	CampaignDB.active = false
	CampaignDB.jumped = false
	GameHost.auto_beats = true
	GameHost.auto_play = false
	SaveGame.go_inert()
	RunState.invincible = false
	RunState.reset(0)
	RunState.world = null


## A live host (the current scene) on session `id`. With auto_beats off (a bot chain's host)
## nothing holds and the debrief never takes its own way on.
func _live(id: StringName) -> GameHost:
	Telemetry.log_path = TEST_LOG
	SaveGame.go_inert()
	CampaignDB.answer_fork(&"fork_enemy", &"enemy_tank")
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
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	RunState.invincible = true
	return h


## The game scene on session `id`, unhosted, started at `start` (Main.NO_START: cold).
func _game(id: StringName, start := Main.NO_START) -> Main:
	SaveGame.go_inert()
	CampaignDB.answer_fork(&"fork_enemy", &"enemy_tank")
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	Main.next_start = start
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	if game.stage_card != null:
		game.stage_card.skip()
	await wait_physics_frames(1)
	return game


func _mine(g: Main, group: StringName) -> Array:
	return get_tree().get_nodes_in_group(group).filter(func(n: Node) -> bool:
		return g.is_ancestor_of(n) and not n.is_queued_for_deletion())


# --- The rule -------------------------------------------------------------------------------

func test_only_a_next_in_stage_1_or_2_without_a_death_carries() -> void:
	var s3 := CampaignDB.get_session(S3)
	var s4 := CampaignDB.get_session(S4)
	assert_true(GameHost.carry_ok(s3, s4, &"won"))
	assert_true(GameHost.carry_ok(s3, s4, &"stopped"))
	assert_false(GameHost.carry_ok(s3, s4, &"died"), "a death reloads at player_start")
	assert_false(GameHost.carry_ok(CampaignDB.get_session(S6), CampaignDB.get_session(S7), &"won"),
			"Stage 2 starts on a chapter (the stage card): cold")
	# M47.6d2 (design 2.7): the carry reaches Stage 2: S7 -> S8, but never into S9 (fresh_start).
	var s7 := CampaignDB.get_session(S7)
	var s8 := CampaignDB.get_session(&"s2_02_day_one")
	var s9 := CampaignDB.get_session(&"s2_03_paint")
	assert_true(GameHost.carry_ok(s7, s8, &"stopped"), "S7 -> S8 carries")
	assert_true(GameHost.carry_ok(s7, s8, &"won"))
	assert_false(GameHost.carry_ok(s7, s8, &"died"), "a death still reloads")
	assert_false(GameHost.carry_ok(s8, s9, &"won"), "S9 is fresh_start: its specimen is placed from player_start")
	var s9_carried := s9.duplicate() as SessionDef
	s9_carried.fresh_start = false
	assert_true(GameHost.carry_ok(s8, s9_carried, &"won"), "only fresh_start keeps S9 cold")
	assert_false(GameHost.carry_ok(CampaignDB.get_session(S6), s8, &"won"), "never across stages")
	assert_false(GameHost.carry_ok(null, s4, &"won"))
	var other := s4.duplicate() as SessionDef
	other.arena = ArenaDef.new()
	assert_false(GameHost.carry_ok(s3, other, &"won"), "another arena reloads")


func test_capture_snaps_to_a_hundredth_and_refuses_what_does_not_carry() -> void:
	# The capture reads back exactly as its printed text does (run_hash --start parses it).
	var odd := Vector2(1939.3149, 291.4951)
	var p := GameHost.printed_start(odd)
	assert_eq(p, Vector2(("%.2f" % p.x).to_float(), ("%.2f" % p.y).to_float()), "a fixed point")
	assert_eq(p, Vector2("1939.31".to_float(), "291.50".to_float()))
	var g := await _game(S4)
	g.player.global_position = Vector2(1600.123456, 700.987654)
	g.debrief.open(RunState.session, &"win", 0)
	assert_eq(GameHost.capture_start(g, CampaignDB.get_session(S5)), Vector2(1600.12, 700.99))
	g.debrief.close()
	g.debrief.open(RunState.session, &"lose", 0)
	assert_eq(GameHost.capture_start(g, CampaignDB.get_session(S5)), Main.NO_START, "died")
	assert_eq(GameHost.capture_start(null, CampaignDB.get_session(S5)), Main.NO_START)


# --- The start ------------------------------------------------------------------------------

func test_a_cold_start_is_player_start() -> void:
	var g := await _game(S5)
	assert_eq(g.run_loop.start_point, g.arena.player_start, "the record's start")
	assert_eq(Main.next_start, Main.NO_START)


## M47.6d2: a carried spot reaches S8 (Stage 2), but S9 (fresh_start) always starts at
## player_start, even with a start handed to it.
func test_s8_takes_a_carried_spot_and_s9_never_does() -> void:
	var spot := Vector2(1590.25, 660.5)
	var g8 := await _game(&"s2_02_day_one", spot)
	assert_eq(g8.run_loop.start_point, spot, "S8 starts where S7 ended")
	g8.free()
	var g9 := await _game(&"s2_03_paint", spot)
	assert_eq(g9.run_loop.start_point, g9.arena.player_start, "S9 starts cold")
	assert_eq(Main.next_start, Main.NO_START, "still consumed")


func test_a_carried_start_places_the_player_and_is_consumed() -> void:
	var spot := Vector2(1590.25, 660.5)
	var g := await _game(S5, spot)
	assert_eq(g.run_loop.start_point, spot)
	assert_eq(Main.next_start, Main.NO_START, "consumed in _ready, as next_seed")
	assert_eq(g.run_loop.record.get("start", null), null, "the record is written at the end")
	g.run_loop.end(&"win")
	assert_eq(g.run_loop.record["start"], [1590.25, 660.5], "the run record carries it (additive)")


func test_a_blocked_spot_moves_to_a_free_tile_and_outside_falls_back() -> void:
	var probe := await _game(S5)
	assert_false(probe.arena.blocks.is_empty(), "S5 has its walls")
	var block: Rect2 = probe.arena.blocks[0]
	var start := probe.arena.player_start
	probe.free()
	var g := await _game(S5, block.get_center())
	var p := g.run_loop.start_point
	assert_ne(p, start, "a wall-hugging spot does not jump to player_start")
	assert_true(g.arena.distance_to_blocks(p) >= Tuning.TILE * 0.5, "it moves to a clear tile")
	assert_true(g.arena.is_reachable(p))
	assert_true(p.distance_to(block.get_center()) <= Tuning.TILE * 8.0, "nearby")
	assert_eq(p, g.genre.start_for(p), "and that start replays as itself (--start)")
	g.free()
	g = await _game(S5, Vector2(-500, -500))
	assert_eq(g.run_loop.start_point, start, "outside the arena: player_start")


# --- The flow -------------------------------------------------------------------------------

## The host loop (Main._end_session) and the tool loop (run_hash --chain: GameHost.capture_start
## on the open debrief) give the same start for one input; the swap is the seamless one; the
## room is emptied in the beat and HP refilled; the telemetry line has the start.
func test_next_carries_the_spot_into_the_next_session() -> void:
	GameHost.auto_beats = false
	var h := await _live(S4)
	var g := h.game
	var cold_start := g.arena.player_start
	assert_true(g.genre.spawn_archetype(&"chaser", 2))
	await wait_physics_frames(3)
	assert_eq(_mine(g, &"enemy").size(), 2)
	var hp := Component.find(g.player, Health) as Health
	hp.hp_ratio = 0.4
	g.player.global_position = cold_start + Vector2(12.345, -6.789)
	for e in _mine(g, &"enemy"):   # on screen, so each pops (off-view ones only leave)
		(e as Node2D).global_position = g.player.global_position + Vector2(60, 0)
	g.debrief.input_delay = 0.0
	g.run_loop.end(&"win")
	for f in 300:
		if g.debrief.is_open():
			break
		await wait_physics_frames(1)
	assert_true(g.debrief.is_open(), "the report opened the beat")
	assert_eq(h.cleared, 2, "the leftovers pop out in the beat")
	assert_eq(_mine(g, &"enemy").size(), 0)
	assert_true(h.puffs.visible, "one pop per leftover")
	assert_eq(hp.hp_ratio, 1.0, "HP refills in the beat")
	var tool_start := GameHost.capture_start(g, CampaignDB.get_session(S5))
	assert_eq(tool_start, GameHost.printed_start(g.player.global_position))
	assert_ne(tool_start, cold_start)
	g.debrief.finish_lines()
	g._end_session(&"next")
	assert_eq(Main.next_start, tool_start, "the host loop's capture is the tool loop's")
	assert_true(h.seamless, "no glitch for a carried next session")
	assert_false(h._glitch.visible)
	await wait_process_frames(3)
	assert_false(is_instance_valid(g), "a fresh instance")
	assert_eq(RunState.session.id, S5)
	assert_eq(h.game.run_loop.start_point, tool_start, "the player starts where it stood")
	assert_eq(h.game.player.global_position, tool_start)
	assert_eq(Main.next_start, Main.NO_START)
	assert_true(h.terminal.rows().has("$ hot-reload game ... ok"), "the story's row stays in the chat")
	var log_text := FileAccess.get_file_as_string(TEST_LOG)
	assert_true(log_text.contains("\"start\":[%s,%s]" % [cold_start.x, cold_start.y])
			or log_text.contains("\"start\":[%.1f,%.1f]" % [cold_start.x, cold_start.y]),
			"S4's campaign line has its own start")


## Review fix: a leftover outside the view is cleared but draws no pop, so no ring lands over
## the chat, the title bar or the taskbar (Puffs does not clip its draw).
func test_off_screen_leftovers_are_cleared_without_a_pop() -> void:
	GameHost.auto_beats = false
	var h := await _live(S4)
	var g := h.game
	assert_true(g.genre.spawn_archetype(&"chaser", 2))
	await wait_physics_frames(3)
	var foes := _mine(g, &"enemy")
	assert_eq(foes.size(), 2)
	(foes[0] as Node2D).global_position = g.player.global_position + Vector2(20, 0)
	(foes[1] as Node2D).global_position = g.player.global_position + Vector2(GameHost.GAME_SIZE.x * 2.0, 0)
	h.clear_field(g)
	assert_eq(h.cleared, 2, "both leftovers leave the room")
	assert_eq(h.puffs.points.size(), 1, "only the one on screen pops")
	var game_rect := Rect2(h.view.position, h.view.size)
	for p in h.puffs.points:
		assert_true(game_rect.has_point(p), "every pop is inside the game window: %s" % p)


## A live next session's swap without a carry glitches as before; with one it does not.
func test_the_glitch_only_plays_when_nothing_carries() -> void:
	var h := await _live(S4)
	Main.next_start = Vector2(1600, 700)
	h.next_session()
	assert_true(h.seamless)
	assert_false(h._glitch.visible, "seamless: no glitch")
	await wait_process_frames(3)
	assert_eq(h.swaps, 1, "on the next frame, not after the glitch's timer")
	Main.clear_start()
	h.next_session()
	assert_false(h.seamless)
	assert_true(h._glitch.visible, "a visible reload glitches")
	h.next_session("restart s1_04_level (try 2)")   # queued: ignored, the flag stays the swap's


## A death ends with a visible reload at player_start, even on Move on.
func test_a_death_does_not_carry_and_does_not_empty_the_room() -> void:
	GameHost.auto_beats = false
	var h := await _live(S4)
	var g := h.game
	assert_true(g.genre.spawn_archetype(&"chaser", 1))
	await wait_physics_frames(3)
	g.player.global_position = g.arena.player_start + Vector2(30, 0)
	g.debrief.input_delay = 0.0
	g._on_report_ready(&"lose")
	assert_eq(h.cleared, 0)
	assert_eq(_mine(g, &"enemy").size(), 1, "the room stays as it was")
	g.debrief.finish_lines()
	g._end_session(&"move_on")
	assert_eq(Main.next_start, Main.NO_START)
	assert_false(h.seamless)
	await wait_process_frames(3)
	assert_eq(h.game.run_loop.start_point, h.game.arena.player_start)


# --- next_start never leaks ------------------------------------------------------------------

func test_retry_restart_and_the_title_clear_next_start() -> void:
	var g := await _game(S4)
	Main.next_start = Vector2(1, 2)
	g.menu_restart()
	assert_eq(Main.next_start, Main.NO_START, "the pause menu's Restart")
	Main.next_start = Vector2(1, 2)
	g.start_new_build(5)
	assert_eq(Main.next_start, Main.NO_START, "Restart / F5")
	Main.next_start = Vector2(1, 2)
	Main.leave_hook = func(_p: String) -> void: pass
	g._leave_to(StartScreen.TITLE_SCENE)
	assert_eq(Main.next_start, Main.NO_START, "the title")
	Main.next_start = Vector2(1, 2)
	Main.next_lead = Vector2(3, 4)
	Main.clear_start()
	assert_eq(Main.next_lead, Vector2.ZERO)


func test_a_retry_from_the_debrief_starts_cold() -> void:
	GameHost.auto_beats = false
	var h := await _live(S4)
	var g := h.game
	g.player.global_position = g.arena.player_start + Vector2(40, 0)
	Main.next_start = Vector2(1, 2)   # stale: the retry must not use it
	g.debrief.input_delay = 0.0
	g._on_report_ready(&"lose")
	g.debrief.finish_lines()
	g._end_session(&"retry")
	assert_eq(Main.next_start, Main.NO_START)
	await wait_process_frames(3)
	assert_eq(RunState.session.id, S4)
	assert_eq(h.game.run_loop.start_point, h.game.arena.player_start)
