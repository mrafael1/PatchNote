extends GutTest
## M48.6b: the view's HUD and the host in the cabinet (PLAN 0.9.2). The corner plate (the bugs
## or the time left to the session's goal, counting down; hidden with no count; the bump and
## reduce flashing; mint at zero), the hearts and the dash ring on the player (under the feet on
## Survival), the caption beside the camera (every line the AI says, also under a pick panel;
## no floating bubble in the cabinet), and the flat look left alone. Hosts here are tool hosts.

const S4 := &"s1_04_level"
const S8 := &"s2_02_day_one"
const TEST_LOG := "user://m48_6b_test/t.jsonl"

var _was: ArtSkin


func before_each() -> void:
	_was = Skins.current
	Telemetry.log_path = TEST_LOG


func after_each() -> void:
	await wait_physics_frames(2)   # deferred spawns land before the game is freed
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	if FileAccess.file_exists(TEST_LOG):
		DirAccess.remove_absolute(TEST_LOG)
	RunState.invincible = false
	Skins.disabled = false
	Skins.use(_was)
	Skins.reset_reveal(false)
	SaveGame.set_setting("reduce_flashing", false)
	RunState.clear_pauses()
	CampaignDB.active = false
	CampaignDB.jumped = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null


func _hosted(id: StringName, path := &"") -> GameHost:
	SaveGame.go_inert()
	if path != &"":
		assert_true(CampaignDB.answer_fork(&"fork_path", path))
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var g: Main = load("res://main.tscn").instantiate()
	var h := GameHost.host_for_tools(g)
	add_child_autofree(h)
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	RunState.invincible = true
	h.skip_handoff()
	if path != &"":
		for b: StringName in [&"cards", &"levelups", &"pickups"]:
			RunState.add_basic(b)
		await wait_physics_frames(2)
	return h


func _pixel(h: GameHost) -> CabinetFrame:
	Skins.use(Skins.pixel())
	for e in get_errors():   # the look turns physics interpolation on; the engine warns once
		if e.contains_text("Camera2D overridden to physics process mode"):
			e.handled = true
	assert_true(h.rail is CabinetFrame, "the cabinet is built on the look's ui group")
	h.relayout(Vector2(1600, 900))
	h.rail.refresh()
	return h.rail as CabinetFrame


func _loop(h: GameHost) -> RunLoop:
	return h.game.genre.get(&"run_loop") as RunLoop


# --- The corner plate ---------------------------------------------------------------------------

func test_the_plate_counts_the_fixed_set_down_on_a_clear_session() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var cab := _pixel(h)
	var loop := _loop(h)
	assert_true(loop.has_end(SessionDef.CLEAR), "S8 is a clear session")
	var set_size := loop.enemy_total + RunState.session.cue_spawn_total()
	assert_gt(set_size, 10)
	var c: Dictionary = cab.snap.count
	assert_true(c.on, "a clear session has a count")
	assert_eq(c.kind, &"bugs")
	assert_eq(int(c.n), set_size - RunState.kills, "the fixed set left")
	var plate := cab.plate
	assert_true(plate.shown() and plate.visible, "the plate is on the view")
	assert_eq(plate.icon(), &"skull")
	assert_eq(plate.text(), str(set_size - RunState.kills))
	assert_eq(plate.get_parent(), h, "a child of the host")
	assert_gt(plate.get_index(), cab.glass.get_index(), "over the view's glass")
	assert_eq(plate.position + Vector2(18, 18), Vector2(h.layout.plate), "18 design px inside the view's top left")
	# Reduce flashing: the number changes with no bump.
	SaveGame.set_setting("reduce_flashing", true)
	RunState.kills += 1
	cab.refresh()
	assert_eq(int(cab.snap.count.n), set_size - RunState.kills, "it counts down")
	assert_eq(plate.text(), str(set_size - RunState.kills))
	assert_false(plate.bumping(), "reduce flashing: no bump")
	# Flashing allowed: a change bumps the number.
	SaveGame.set_setting("reduce_flashing", false)
	RunState.kills += 1
	cab.refresh()
	assert_eq(plate.text(), str(set_size - RunState.kills))
	assert_true(plate.bumping(), "the number bumps on a change")
	assert_false(plate.zero())
	plate.queue_redraw()
	await wait_process_frames(2)   # it draws without an engine error


func test_the_plate_per_goal_kind_and_hidden_with_no_count() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var cab := _pixel(h)
	var loop := _loop(h)
	var plate := cab.plate
	var none: Array[StringName] = []
	# A kills goal: the goal less the kills, mint at zero.
	loop.set_goal(SessionDef.KILLS, 20.0)
	loop.set_endings(none)
	RunState.kills = 7
	cab.refresh()
	assert_eq(cab.snap.count, {"on": true, "kind": &"bugs", "n": 13}, "a kills goal counts goal minus kills")
	assert_eq(plate.icon(), &"skull")
	assert_eq(plate.text(), "13")
	assert_false(plate.zero())
	RunState.kills = 20
	cab.refresh()
	assert_eq(plate.text(), "0")
	assert_true(plate.zero(), "mint at zero")
	RunState.kills = 7
	# A survive goal: a clock and m:ss left.
	loop.set_goal(SessionDef.SURVIVE, 90.0)
	loop.goal_clock = 17.5
	cab.refresh()
	assert_eq(cab.snap.count.kind, &"clock")
	assert_eq(int(cab.snap.count.n), 73)
	assert_eq(plate.icon(), &"clock")
	assert_eq(plate.text(), "1:13")
	assert_false(plate.bumping(), "a change of kind is not a bump")
	# Goals with no count: the plate hides.
	for kind: StringName in [SessionDef.SCRIPT, SessionDef.STOP, SessionDef.OVERRUN]:
		loop.set_goal(kind, 30.0)
		cab.refresh()
		assert_false(cab.snap.count.on, "%s has no count" % kind)
		assert_false(plate.shown(), "%s: the plate hides" % kind)
		assert_false(plate.visible)
		assert_eq(plate.text(), "")
	# No session at all (the reading with no game).
	assert_false(RailState.read(null, {}).count.on)
	assert_eq(RailState.count_text({"kind": &"clock", "n": 72}), "1:12")
	assert_eq(RailState.count_text({"kind": &"clock", "n": 5}), "0:05")
	assert_eq(RailState.count_text({"kind": &"bugs", "n": 41}), "41")
	loop.set_goal(SessionDef.SURVIVE, 9000.0)   # the session runs on quietly until the test ends


func test_survival_shows_a_clock_and_the_hearts_under_the_feet() -> void:
	var h := await _hosted(S8, &"path_survival")
	var cab := _pixel(h)
	var loop := _loop(h)
	assert_eq(cab.snap.path.kind, &"ammo", "the Survival path")
	assert_gt(loop.time_limit, 0.0)
	assert_eq(cab.snap.count.kind, &"clock", "Survival: the clock")
	assert_eq(int(cab.snap.count.n), ceili(loop.time_limit - loop.goal_clock - 0.0001), "the time left")
	assert_eq(cab.plate.icon(), &"clock")
	assert_true(cab.plate.text().contains(":"), "m:ss")
	var hud := cab.player_hud
	assert_not_null(hud)
	assert_true(hud.hearts_under(), "the rounds are over the head")
	assert_gt(hud.hearts_at().y, 0, "the hearts sit under the feet")
	assert_gt(hud.hearts_at().y, hud.RING_R + 1, "clear of the dash ring")


func test_the_hearts_and_the_dash_ring_ride_the_player() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var cab := _pixel(h)
	var player := h.game.player
	var hud := cab.player_hud
	assert_not_null(hud, "the cabinet adds the HUD")
	assert_eq(hud.get_parent(), player, "on the live player")
	assert_false(hud.hearts_under())
	assert_lt(hud.hearts_at().y + 7, -(hud.RING_R + 1), "the hearts sit above the ring")
	var health := Component.find(player, Health) as Health
	var most := ceili(health.max_hp() - 0.001)
	assert_eq(hud.hearts().size(), most, "one heart per max HP")
	assert_eq(hud.hearts().count(true), most, "all full")
	assert_eq(hud.hearts_at().x, -((most * hud.HEART_STEP - 1) / 2), "the row is centred on the player")
	health.hp_ratio = 2.0 / most
	cab.refresh()
	assert_eq(hud.hearts().size(), most, "the row keeps its length")
	assert_eq(hud.hearts().count(true), 2, "the hearts follow the HP (the rail's own reading)")
	assert_eq(hud.hearts().count(true), int(cab.snap.hp.hp))
	assert_true(hud.hearts()[0] and hud.hearts()[1] and not hud.hearts()[2], "full ones first")
	health.hp_ratio = 1.0
	# The dash ring: the cooldown's fill, then ready.
	var dasher := Component.find(player, Dasher) as Dasher
	dasher._cooldown_left = 0.6
	cab.refresh()
	dasher._cooldown_left = 0.3
	cab.refresh()
	var ring: Dictionary = hud.ring()
	assert_true(ring.on, "the dash is live")
	assert_false(ring.ready)
	assert_almost_eq(float(ring.frac), 0.5, 0.01, "half the cooldown done")
	assert_eq(float(ring.frac), float(cab.snap.dash.frac), "the rail's own reading")
	dasher._cooldown_left = 0.0
	cab.refresh()
	assert_true(hud.ring().ready)
	assert_eq(float(hud.ring().frac), 1.0)
	hud.queue_redraw()
	await wait_process_frames(2)   # it draws without an engine error
	# The look off: the HUD leaves the player, the flat HUD is back.
	Skins.use(null)
	await wait_process_frames(2)
	assert_null(player.get_node_or_null("CabinetPlayerHud"), "gone with the cabinet")


# --- The host ----------------------------------------------------------------------------------

func test_the_caption_shows_a_line_said_under_a_pick_panel_and_no_bubble_floats() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var cab := _pixel(h)
	var mascot := h.game.mascot
	var cap := cab.cap_box
	assert_not_null(cap, "the caption is in the deck")
	assert_true(mascot.captioned(), "the cabinet captions the lines")
	# A pick panel opens (a pack), then the AI speaks.
	var panel := h.game.ensure_path_runner().panel
	var offer := PickOffer.new()
	offer.cards.append({"id": &"shotgun", "rank": 1, "kind": &"new", "text": "Shotgun"})
	offer.cards.append({"id": &"smg", "rank": 1, "kind": &"new", "text": "SMG"})
	panel.input_delay = 0.0
	assert_true(panel.open(offer))
	assert_true(panel.is_open(), "a pick is open")
	mascot.say(Line.make("Pick one. I will wait.", &"happy"), 3, true)
	mascot.step(0.05)
	assert_eq(mascot.current_text(), "Pick one. I will wait.")
	assert_eq(cap.text, "Pick one. I will wait.", "the caption shows the line during the pick")
	assert_true("Pick one. I will wait." in cap.shown)
	assert_true(cap.talking(), "it types")
	assert_false(mascot.bubble_shown(), "no floating bubble")
	cap.step(30.0)
	assert_false(cap.talking())
	assert_eq(" ".join(cap.rows()), "Pick one. I will wait.", "typed whole")
	assert_false(cap.idle(), "lit for its read time")
	cap.step(30.0)
	assert_true(cap.idle(), "then it dims")
	panel.choose(0)
	await wait_physics_frames(2)
	assert_false(panel.is_open())
	# With no panel: still the caption, never the bubble.
	mascot.say(Line.make("Back to work.", &"proud"), 3, true)
	mascot.step(0.05)
	assert_eq(cap.text, "Back to work.")
	assert_eq(cap.mood, &"proud" if h.terminal.has_face else &"")
	assert_false(mascot.bubble_shown(), "no floating bubble in the cabinet")
	# Between sessions the chat types the lines (a gate, a beat): the caption shows them too.
	h.terminal.say_row("Next one. Type play.", &"happy")
	assert_eq(cap.text, "Next one. Type play.", "every line the AI says")
	assert_eq(cap.host_name(), h.terminal.header_name().to_upper(), "the mood plate names the AI")
	cap.queue_redraw()
	cab.track.queue_redraw()
	await wait_process_frames(2)   # the caption and the lit camera draw without an engine error
	# The look off: the bubble is back.
	Skins.use(null)
	assert_false(mascot.captioned())
	mascot.say(Line.make("Flat again.", &"happy"), 3, true)
	mascot.step(0.05)
	assert_true(mascot.bubble_shown(), "the flat look keeps the floating bubble")


func test_a_long_line_wraps_and_scrolls_in_the_caption() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var cab := _pixel(h)
	var cap := cab.cap_box
	assert_eq(cap.text_size(), 22, "the pixel font on its grid: 2 screen px per font pixel")
	assert_eq(cap.max_rows(), 3, "three rows at the design size")
	var width: float = cap.text_width()
	assert_almost_eq(width, 315.0, 1.0, "about 330 design px wide")
	var short: PackedStringArray = cap.wrap_rows("Look at you go.", 22, width)
	assert_eq(short.size(), 1)
	var long := "One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen " \
			+ "seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three."
	var rows: PackedStringArray = cap.wrap_rows(long, 22, width)
	assert_gt(rows.size(), 3, "a long line needs more rows than the bubble has")
	for row in rows:
		assert_lte(RailFrame.text_w(row, 22), width, "no row is wider than the bubble")
	assert_eq(" ".join(rows), long, "no word is lost")
	cap.say(long, &"happy")
	cap.step(0.2)
	assert_eq(cap.rows().size(), 1, "it starts on the first row")
	cap.step(60.0)
	var seen: PackedStringArray = cap.rows()
	assert_eq(seen.size(), 3, "never more rows than the bubble holds")
	assert_eq(seen[2], rows[rows.size() - 1], "the last rows typed are the ones shown")


# --- What stays ----------------------------------------------------------------------------------

func test_the_flat_look_and_stage_1_get_none_of_it() -> void:
	Skins.use(null)
	var h := await _hosted(S4)
	assert_null(h.rail, "no cabinet before S9")
	assert_null(h.game.player.get_node_or_null("CabinetPlayerHud"), "no hearts on the player")
	assert_null(h.get_node_or_null("CabinetPlate"), "no corner plate")
	assert_false(h.game.mascot.captioned())
	h.game.mascot.say(Line.make("Hello.", &"idle"), 3, true)
	h.game.mascot.step(0.05)
	assert_true(h.game.mascot.bubble_shown(), "the floating bubble as before")
	Skins.disabled = true   # --skins=off
	Skins.use(Skins.pixel())
	await wait_process_frames(2)
	assert_null(h.rail, "--skins=off never builds it")
	assert_null(h.game.player.get_node_or_null("CabinetPlayerHud"))
	assert_true(h.game.hud._label.visible, "the flat HUD corner")


func test_the_rail_keeps_its_kills_hp_and_dash_modules() -> void:
	var rail := RailLayout.layout_for(Vector2(1600, 900))
	for m: StringName in [&"kills", &"hp", &"dash", &"path"]:
		assert_true(rail.cells.has(m), "the rail's layout still has the %s cell" % m)
	var h := await _hosted(S8, &"path_arsenal")
	var cab := _pixel(h)
	for m: StringName in [&"kills", &"hp", &"dash"]:
		assert_true(cab.snap[m].on, "%s is read" % m)
		assert_false(m in cab.modules.shown_modules(), "%s: no module in the cabinet's deck" % m)
	# The same modules on the rail's own layout (the rail code that remains until M48.6f).
	cab.layout = rail
	var shown: Array[StringName] = cab.modules.shown_modules()
	for m: StringName in [&"kills", &"hp", &"dash", &"path"]:
		assert_true(m in shown, "%s is a module on the rail's layout" % m)
		assert_gt(cab.modules.cell_rect(m).size.x, 0.0)
	cab.layout = h.layout


func test_the_hud_grids_are_whole() -> void:
	var hex := RegEx.create_from_string("^#[0-9a-f]{6}$")
	for id: StringName in CabinetArt.HUD:
		var e: Dictionary = CabinetArt.HUD[id]
		var w := String(e.grid[0]).length()
		for row: String in e.grid:
			assert_eq(row.length(), w, "%s: a ragged row" % id)
			for ch in row:
				if ch != ".":
					assert_true(e.ramp.has(ch), "%s: letter %s has no colour" % [id, ch])
		for ch: String in e.ramp:
			assert_not_null(hex.search(e.ramp[ch]), "%s: colour %s" % [id, ch])
	for id: StringName in [&"heart", &"heart_empty", &"clock"]:
		assert_true(CabinetArt.HUD.has(id))
	assert_eq(CabinetArt.grid_size(CabinetArt.HUD[&"heart"].grid), Vector2i(7, 7))
	assert_ne(CabinetArt.c(&"clock"), Color.MAGENTA)
	assert_ne(CabinetArt.c(&"cap_idle"), Color.MAGENTA)
	assert_true(CabinetArt.ORN.has(&"skull") and CabinetArt.NINE.has(&"kill_plate"))
	for id: StringName in [&"bubble", &"cap_gold", &"cap_ink", &"host_talk"]:
		assert_true(CabinetArt.NINE.has(id), "the host's 9-slice %s" % id)
	# The pixel ring: one cell thick, on every side, its angles clockwise from the top.
	var cells := CabinetArt.ring_cells(10)
	assert_gt(cells.size(), 40)
	var has := {}
	for c: Array in cells:
		has[Vector2i(c[0], c[1])] = float(c[2])
		assert_almost_eq(Vector2(c[0], c[1]).length(), 10.0, 0.51)
	for side: Vector2i in [Vector2i(0, -10), Vector2i(10, 0), Vector2i(0, 10), Vector2i(-10, 0)]:
		assert_true(has.has(side), "the ring passes %s" % side)
	assert_almost_eq(float(has[Vector2i(0, -10)]), 0.0, 0.001, "the top is where the fill starts")
	assert_almost_eq(float(has[Vector2i(10, 0)]), PI / 2.0, 0.001, "then the right: clockwise")
