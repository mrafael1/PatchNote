extends GutTest
## M48.6a: the cabinet frame, the Pixel look's UI (PLAN 0.9.2). Its layout (the plan's rects,
## the view 16:9 at every window, nothing overlapping, the scale snapped to whole art pixels),
## when it shows (only once the look's `ui` group is on: S9's `skin ui`; never under
## --skins=off, never with a chapter card), the host's side (the window base, the mouse into
## the view, the 1280x720 sim), the marquee's texts, the rail's pieces alive inside it, and
## the art kit's data. Hosts here are tool hosts (never live, no window change).

const S4 := &"s1_04_level"
const S8 := &"s2_02_day_one"
const S9 := &"s2_03_paint"
const TEST_LOG := "user://m48_6a_test/t.jsonl"
const WINDOWS: Array[Vector2] = [Vector2(1600, 900), Vector2(1920, 1080), Vector2(2560, 1440), Vector2(3840, 2160),
		Vector2(1760, 720), Vector2(1280, 720), Vector2(1024, 768)]

var _was: ArtSkin


## Records the mouse motion events that reach the game (inside the SubViewport).
class MotionProbe:
	extends Node
	var seen: Array[Vector2] = []
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			seen.append((event as InputEventMouseMotion).position)


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
	_engine_note()
	assert_not_null(h.rail, "the frame is built on the look's ui group")
	assert_true(h.rail is CabinetFrame, "and it is the cabinet, not the version rail")
	h.rail.refresh()
	return h.rail as CabinetFrame


## The look turns physics interpolation on; the engine warns once per process (test_pixel_skin).
func _engine_note() -> void:
	for e in get_errors():
		if e.contains_text("Camera2D overridden to physics process mode"):
			e.handled = true


# --- Layout ------------------------------------------------------------------------------------

func test_the_plan_rects_at_the_design_size() -> void:
	var l := CabinetLayout.layout_for(Vector2(1600, 900))
	assert_eq(l.frame, Rect2(12, 12, 1196, 876), "cabinet")
	assert_eq(l.marquee, Rect2(34, 24, 1152, 42), "marquee")
	assert_eq(l.view, Rect2(34, 78, 1152, 648), "view")
	assert_eq(l.deck, Rect2(34, 748, 1152, 128), "deck")
	assert_eq(l.chat, Rect2(1218, 12, 370, 876), "chat")
	assert_eq(l.game, l.view, "the game is the view")
	assert_almost_eq(float(l.k), 648.0 / 720.0, 0.0001)
	assert_eq(float(l.s), 1.0)
	assert_eq(float(l.art), 3.0, "3 screen px per art px at the design size")
	assert_eq(CabinetLayout.BASE, Vector2i(1600, 900), "the window base")
	assert_true(l.get("cabinet", false) and l.get("rail", false), "the rail's pieces read the same layout")
	assert_false(l.has("track"), "the version track is gone")
	assert_false(l.has("caption"), "and the caption under the game (the marquee carries it)")


func test_the_view_is_16_9_and_no_piece_overlaps_at_any_window() -> void:
	for win in WINDOWS:
		var l := CabinetLayout.layout_for(win)
		var view: Rect2 = l.view
		assert_eq(view.size.x * 9.0, view.size.y * 16.0, "%s: the view is exactly 16:9" % win)
		assert_almost_eq(float(l.k), view.size.y / 720.0, 0.0001)
		var window := Rect2(Vector2.ZERO, win)
		var parts := {"marquee": l.marquee, "view": l.view, "deck": l.deck, "chat": l.chat}
		for a: String in parts:
			assert_true(window.encloses(parts[a]), "%s: %s inside the window" % [win, a])
			for b: String in parts:
				if a < b:
					assert_false((parts[a] as Rect2).intersects(parts[b]), "%s: %s / %s" % [win, a, b])
		var frame: Rect2 = l.frame
		for a: String in ["marquee", "view", "deck"]:
			assert_true(frame.encloses(parts[a]), "%s: %s inside the cabinet" % [win, a])
		assert_false(frame.intersects(l.chat), "%s: the chat stands beside the cabinet" % win)
		# The rail's pieces, alive inside: the body and the modules in the deck.
		var deck: Rect2 = l.deck
		assert_true(deck.encloses(l.host), "%s: the camera box in the deck" % win)
		assert_true((l.host as Rect2).encloses(l.blob), "%s: the body in the camera box" % win)
		assert_true(deck.encloses(l.modules), "%s: the modules in the deck" % win)
		assert_false((l.host as Rect2).intersects(l.modules), "%s: beside the camera" % win)
		for id: StringName in l.cells:
			assert_true((l.modules as Rect2).grow(1.0).encloses(l.cells[id]), "%s: %s in the module strip" % [win, id])
		# M48.6b: KILLS / HP / DASH have no cell in the deck; the caption sits between the camera
		# and the path's modules; the corner plate starts inside the view.
		for gone: StringName in [&"kills", &"hp", &"dash"]:
			assert_false(l.cells.has(gone), "%s: no %s cell in the deck" % [win, gone])
		assert_true(l.cells.has(&"path"), "%s: the path's slot stays" % win)
		for gone: StringName in [&"hand", &"pack"]:   # M48.6d: the Arcade dock stands there
			assert_false(l.cells.has(gone), "%s: no %s cell in the deck" % [win, gone])
		var cap: Rect2 = l.cap
		assert_true(deck.encloses(cap), "%s: the caption in the deck" % win)
		assert_false(cap.intersects(l.host), "%s: caption / camera" % win)
		assert_false(cap.intersects(l.modules), "%s: caption / modules" % win)
		assert_gt(cap.position.x, (l.host as Rect2).end.x, "%s: the caption is right of the camera" % win)
		assert_lt(cap.end.x, (l.modules as Rect2).position.x + 1.0, "%s: the modules are right of the caption" % win)
		assert_true(deck.has_point(l.mood), "%s: the mood plate in the deck" % win)
		assert_true(view.has_point(l.plate), "%s: the corner plate inside the view" % win)
		var chat: Rect2 = l.chat
		# M48.6c: the chat column is one dev-chat (test_cabinet_chat.gd); the terminal's rect is
		# its messages area.
		assert_true(chat.encloses(l.terminal), "%s: the messages in the chat column" % win)
		assert_eq(l.terminal, l.log, "the terminal's rows are the messages")
		assert_false(l.has("reply"), "%s: no reply box" % win)


## M48.6b (owner): the cabinet fills the window as the rail did, s = min(W / 1600, H / 900); it
## snaps to a whole number of screen px per art px only when that costs less than 4 % of the size.
func test_the_scale_fills_the_window_and_snaps_only_when_cheap() -> void:
	assert_eq(CabinetLayout.scale_for(Vector2(1600, 900)), 1.0, "the design size is exact")
	assert_almost_eq(CabinetLayout.scale_for(Vector2(1920, 1080)), 1.2, 0.0001, "1080p fills at 1.2 (a snap would lose 17 %)")
	assert_almost_eq(CabinetLayout.scale_for(Vector2(1280, 720)), 0.8, 0.0001, "720p fills at 0.8")
	assert_almost_eq(CabinetLayout.scale_for(Vector2(2560, 1440)), 1.6, 0.0001, "1440p fills at 1.6")
	assert_almost_eq(CabinetLayout.scale_for(Vector2(3840, 2160)), 7.0 / 3.0, 0.0001, "4K snaps to 7 px (2.8 % lost)")
	assert_almost_eq(CabinetLayout.scale_for(Vector2(1640, 920)), 1.0, 0.0001, "a few px over the design size snaps back to it")
	assert_almost_eq(CabinetLayout.scale_for(Vector2(1700, 950)), 950.0 / 900.0, 0.0001, "5 % over: the fit, no snap")
	assert_almost_eq(CabinetLayout.scale_for(Vector2(1760, 720)), 0.8, 0.0001, "a wide window fits its height")
	# What each window gets: the art px (whole only when snapped) and a view that fills the fit.
	var want := {Vector2(1600, 900): 3.0, Vector2(1920, 1080): 3.6, Vector2(1280, 720): 2.4, Vector2(3840, 2160): 7.0}
	for win: Vector2 in want:
		var l := CabinetLayout.layout_for(win)
		assert_almost_eq(float(l.art), float(want[win]), 0.0001, "%s: art px" % win)
		assert_almost_eq(float(l.s), float(want[win]) / 3.0, 0.0001, "%s: s is art / 3" % win)
		var view: Rect2 = l.view
		assert_eq(view.size.x * 9.0, view.size.y * 16.0, "%s: the view is exactly 16:9" % win)
		assert_almost_eq(view.size.x, 1152.0 * float(l.s), 16.0, "%s: the view is 1152 design px wide" % win)
		assert_lte(float(l.s), minf(win.x / 1600.0, win.y / 900.0) + 0.0001, "%s: never over the fit" % win)
	assert_eq((CabinetLayout.layout_for(Vector2(1600, 900)).view as Rect2).size, Vector2(1152, 648))
	assert_eq((CabinetLayout.layout_for(Vector2(1920, 1080)).view as Rect2).size, Vector2(1376, 774), "1080p: 16 x 86 by 9 x 86")
	assert_eq((CabinetLayout.layout_for(Vector2(3840, 2160)).view as Rect2).size, Vector2(384, 216) * 7.0)
	# A window too small for one art px keeps the plain fit (no snap), still 16:9 and inside.
	var tiny := CabinetLayout.layout_for(Vector2(400, 225))
	assert_almost_eq(float(tiny.s), 0.25, 0.0001)
	assert_true(Rect2(Vector2.ZERO, Vector2(400, 225)).encloses(tiny.view))


func test_text_sizes_sit_on_the_font_grid() -> void:
	assert_eq(CabinetLayout.text_px(2, 1.0), 22, "2 screen px per font pixel at the design size")
	assert_eq(CabinetLayout.text_px(3, 1.0), 33, "one art px per font pixel")
	for s: float in [1.0 / 3.0, 2.0 / 3.0, 1.0, 4.0 / 3.0, 7.0 / 3.0]:
		for n in [2, 3]:
			var size := CabinetLayout.text_px(n, s)
			assert_eq(size % 11, 0, "size %d at s %.2f: the font's design pixel is 1/11 em" % [size, s])
			assert_gte(size, 11)


# --- When it shows -----------------------------------------------------------------------------

func test_the_cabinet_arrives_with_skin_ui_and_hides_under_a_chapter_card() -> void:
	Skins.use(null)
	var h := await _hosted(S8, &"path_survival")
	Skins.use(Skins.pixel())
	_engine_note()
	Skins.reset_reveal(true)   # S9: nothing revealed yet
	h._sync_rail()
	var win := h.get_viewport().get_visible_rect().size
	assert_false(h.rail != null and h.rail.on, "before `skin ui`: today's look")
	assert_eq(h.layout, GameHost.layout_for(win), "the raw layout, untouched")
	assert_true(h.desktop.visible, "the dev desktop")
	assert_false(h.game.mascot.docked(), "the corner body")
	Skins.reveal(&"ui")
	assert_true(h.rail is CabinetFrame, "S9's `skin ui` builds the cabinet")
	var cab := h.rail as CabinetFrame
	assert_true(cab.on and cab.visible)
	assert_true(h.layout.get("cabinet", false))
	assert_eq(h.layout, CabinetLayout.layout_for(win), "the host lays out with the cabinet's layout")
	assert_eq(h.game_rect(), h.layout.view as Rect2, "the game view sits in the cabinet's screen")
	assert_eq(h.viewport.size_2d_override, Vector2i(1280, 720), "the sim size never moves")
	assert_false(h.desktop.visible, "the dev desktop hides under it")
	assert_not_null(cab.glass, "the CRT glass")
	assert_true(cab.glass.visible)
	assert_eq(cab.glass.get_parent(), h as Node)
	assert_eq(cab.glass.get_index(), h.view.get_index() + 1, "right over the game view")
	assert_eq(Rect2(cab.glass.position, cab.glass.size), h.layout.view as Rect2)
	assert_eq(cab.glass.mouse_filter, Control.MOUSE_FILTER_IGNORE, "it never takes the mouse")
	h.chapter = true
	h._sync_rail()
	h.relayout()
	assert_false(cab.on or cab.visible, "a chapter card hides it (the game fills the window)")
	assert_false(cab.glass.visible)
	assert_eq(h.layout, GameHost.layout_for(win, true), "the chapter layout")
	h.chapter = false
	h._sync_rail()
	h.relayout()
	assert_true(cab.on and cab.glass.visible)
	Skins.use(null)
	assert_false(cab.on or cab.visible or cab.glass.visible, "the look off: all of it back")
	assert_eq(h.layout, GameHost.layout_for(win))
	assert_true(h.desktop.visible)


func test_skins_off_keeps_the_flat_look() -> void:
	Skins.use(null)
	Skins.disabled = true   # --skins=off
	var h := await _hosted(S9, &"path_arsenal")
	Skins.use(Skins.pixel())
	Skins.reveal(&"ui")
	h._sync_rail()
	assert_null(Skins.current, "no look for the process")
	assert_null(h.rail, "no cabinet is ever built")
	assert_eq(h.layout, GameHost.layout_for(h.get_viewport().get_visible_rect().size), "today's layout")
	assert_true(h.desktop.visible)
	assert_true(h.game.hud._label.visible, "the HUD corner")
	assert_false(h.game.mascot.docked())
	assert_null(h.terminal.dresser)


func test_tier_0_before_s9_never_builds_it() -> void:
	Skins.use(null)
	var h := await _hosted(S4)
	assert_null(h.rail)
	assert_false(h.layout.has("cabinet"))


## The window takes the cabinet's 16:9 base once, at the reveal (as the rail did).
func test_the_window_takes_the_cabinet_base_once() -> void:
	var base := Settings._base_size
	Skins.use(null)
	var h := await _hosted(S8, &"path_survival")
	Skins.use(Skins.pixel())
	_engine_note()
	Skins.reset_reveal(true)
	h._sync_rail()
	h._window_set = true   # as a live, windowed host (no real window here: Settings skips it)
	h.rail_base_set = false
	Settings.set_window_base(GameHost.BASE)
	Skins.reveal(&"ui")
	assert_true(h.rail.on)
	assert_eq(Settings._base_size, CabinetLayout.BASE, "the reveal: the cabinet's base")
	assert_true(h.rail_base_set)
	Settings._scale_applied = 1.0
	h.chapter = true
	h._sync_rail()
	h.chapter = false
	h._sync_rail()
	assert_eq(Settings._base_size, CabinetLayout.BASE, "a stage card keeps the window")
	assert_eq(Settings._scale_applied, 1.0, "no re-apply")
	h._window_set = false   # never run the live exit on a tool host
	Settings.set_window_base(base)


# --- The mouse ---------------------------------------------------------------------------------

func test_the_mouse_maps_into_the_view() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	_pixel(h)
	RunState.set_pause(&"debrief", true)   # the camera holds still; the container still forwards
	var gut_layer := get_tree().root.get_node_or_null(^"GutRunner/GutLayer") as CanvasLayer
	if gut_layer != null:
		gut_layer.visible = false
	var probe := MotionProbe.new()
	probe.process_mode = Node.PROCESS_MODE_ALWAYS
	h.game.add_child(probe)
	var world: Array[Vector2] = []
	for window: Vector2 in [Vector2(1600, 900), Vector2(1280, 720)]:
		h.relayout(window)
		await wait_process_frames(1)
		var r := h.game_rect()
		assert_eq(r, CabinetLayout.layout_for(window).view as Rect2)
		var k := r.size.x / 1280.0
		_motion(r.position + Vector2(640, 200) * k)
		await wait_process_frames(1)
		assert_false(probe.seen.is_empty(), "the motion reached the game")
		if not probe.seen.is_empty():
			assert_almost_eq(probe.seen.back().x, 640.0, 1.5, "event x in the game at k %.2f" % k)
			assert_almost_eq(probe.seen.back().y, 200.0, 1.5, "event y in the game at k %.2f" % k)
		var canvas := h.viewport.get_mouse_position()
		assert_almost_eq(canvas.x, 640.0, 1.5, "canvas x at k %.2f" % k)
		assert_almost_eq(canvas.y, 200.0, 1.5, "canvas y at k %.2f" % k)
		world.append(h.game.get_global_mouse_position())
	assert_almost_eq(world[0].x, world[1].x, 2.0, "same world x at both windows")
	assert_almost_eq(world[0].y, world[1].y, 2.0, "same world y")
	# Over the chat column: the aim does not freeze, the motion reaches the game clamped to the
	# view's right edge.
	h.relayout(Vector2(1600, 900))
	await wait_process_frames(1)
	probe.seen.clear()
	_motion(Vector2(1400, 78 + 324))
	await wait_process_frames(1)
	assert_eq(probe.seen.size(), 1, "one motion reaches the game (the host's push)")
	if not probe.seen.is_empty():
		assert_almost_eq(probe.seen.back().x, 1279.0, 1.5, "clamped to the view's right edge")
		assert_almost_eq(probe.seen.back().y, 360.0, 1.5)
	RunState.set_pause(&"debrief", false)
	if gut_layer != null:
		gut_layer.visible = true


## A motion at `at` in the root's canvas pixels (the host's coordinates), sent in window pixels.
func _motion(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = get_tree().root.get_final_transform() * at
	e.global_position = e.position
	Input.parse_input_event(e)
	Input.flush_buffered_events()


# --- The marquee and the pieces inside -----------------------------------------------------------

func test_the_marquee_names_the_stage_the_session_the_path_and_the_version() -> void:
	var h := await _hosted(S9, &"path_arsenal")
	var cab := _pixel(h)
	assert_eq(cab.marquee_session(), ["STAGE 2 · ", "S9 · FRESH PAINT"] as Array[String])
	assert_eq(cab.marquee_path(), "ARCADE", "the path's title as the player reads it")
	assert_eq(cab.marquee_version(), SaveGame.version().label())
	cab.snap.parts = {"part": 2, "of": 3, "door": true}
	assert_eq(cab.marquee_session()[1], "S9 · FRESH PAINT · PART 2/3 · DOOR OPEN", "a level in parts (the rail's caption)")
	cab.snap.path = {"id": &""}
	assert_eq(cab.marquee_path(), "", "no path: the centre stays empty")
	cab.snap.stage = 0
	assert_eq(cab.marquee_session(), ["", ""] as Array[String], "outside a campaign session")
	cab.refresh()   # the real reading back before the next draw


func test_the_rail_pieces_live_on_inside_the_cabinet() -> void:
	Skins.use(null)
	var h := await _hosted(S8, &"path_arsenal")
	var t := h.terminal
	var before := t.rows()
	var cab := _pixel(h)
	h.relayout(Vector2(1600, 900))
	await wait_process_frames(2)
	var l := h.layout
	assert_eq(t.dresser, cab.chat, "the terminal is dressed as the chat")
	assert_eq(t.rows(), before, "the same rows")
	assert_eq(Rect2(t.position, t.size), l.log as Rect2, "the terminal over the chat's messages")
	# M48.6c: the chat column is the cabinet's own chat; the rail's reply box is not built.
	assert_eq(t.input_row().get_parent(), cab.chat_view, "the input in the chat's input line")
	assert_eq(Rect2(cab.chat_view.position, cab.chat_view.size), l.chat as Rect2)
	assert_null(cab.reply)
	assert_true(h.game.mascot.docked(), "the corner body docks")
	assert_not_null(cab.blob)
	assert_eq(Rect2(cab.blob.position, cab.blob.size), l.blob as Rect2, "the body in the deck's camera box")
	assert_false(h.game.hud._label.visible, "the HUD corner docks into the modules")
	# M48.6b: only the path's modules dock in the deck; the reading still carries the others.
	# M48.6d: on Arcade the hand and the packs are the Arcade dock's (test_cabinet_arcade.gd), not
	# the docked HAND / PACK modules.
	var shown: Array[StringName] = cab.modules.shown_modules()
	assert_false(&"path" in shown, "Arcade's hand has no docked module")
	assert_true(cab.dock.shown(), "the Arcade dock shows it")
	assert_true((l.deck as Rect2).grow(1.0).encloses(cab.dock.rect()), "and stands in the deck")
	assert_true(cab.snap.path.kind == &"hand", "the hand is still read (RailState)")
	for m: StringName in [&"kills", &"hp", &"dash"]:
		assert_false(m in shown, "%s has no module in the cabinet" % m)
		assert_eq(cab.modules.cell_rect(m), Rect2(), "%s has no cell" % m)
		assert_true(cab.snap[m].on, "%s is still read (RailState)" % m)
	assert_lt(cab.ms(), cab.s(), "the modules draw smaller than on the rail")
	assert_almost_eq(cab.ms(), CabinetLayout.MODULE_K, 0.0001)
	assert_eq(cab.mpx(), 1.0)
	# The frame draws (chrome, marquee, glass, modules) without an engine error.
	cab.chrome.queue_redraw()
	cab.track.queue_redraw()
	cab.glass.queue_redraw()
	cab.modules.queue_redraw()
	await wait_process_frames(3)
	Skins.use(null)
	assert_eq(t.input_row().get_parent(), t.chat.input_slot, "the look off: the input back in the chat")
	assert_false(h.game.mascot.docked())
	assert_true(h.game.hud._label.visible)


# --- The art kit --------------------------------------------------------------------------------

func test_the_kit_grids_are_whole_and_every_colour_is_known() -> void:
	var hex := RegEx.create_from_string("^#[0-9a-f]{6}([0-9a-f]{2})?$")
	for role: StringName in CabinetArt.PAL:
		assert_not_null(hex.search(CabinetArt.PAL[role]), "palette %s" % role)
	for table: Dictionary in [CabinetArt.NINE, CabinetArt.ORN]:
		for id: StringName in table:
			var e: Dictionary = table[id]
			var grid: Array = e.grid
			var w := String(grid[0]).length()
			for row: String in grid:
				assert_eq(row.length(), w, "%s: a ragged row" % id)
				for ch in row:
					if ch != ".":
						assert_true(e.ramp.has(ch), "%s: letter %s has no colour" % [id, ch])
			for ch: String in e.ramp:
				assert_not_null(hex.search(e.ramp[ch]), "%s: colour %s" % [id, ch])
	for id: StringName in CabinetArt.NINE:
		var e: Dictionary = CabinetArt.NINE[id]
		var size := CabinetArt.grid_size(e.grid)
		assert_lte(int(e.inset[0]) + int(e.inset[2]), size.x, "%s: insets fit across" % id)
		assert_lte(int(e.inset[1]) + int(e.inset[3]), size.y, "%s: insets fit down" % id)
	for id: StringName in [&"cab", &"trim", &"marq", &"scr", &"deck", &"host", &"plate_gold"]:
		assert_true(CabinetArt.NINE.has(id), "the chrome's 9-slice %s" % id)
	for id: StringName in [&"rivet", &"cab_grain", &"marq_cap_l", &"marq_cap_r", &"marq_chev_l", &"marq_chev_r",
			&"host_floor", &"bracket_tl", &"bracket_tr", &"rec_dot", &"rec_off", &"crt_scan", &"scr_glare", &"vignette"]:
		assert_true(CabinetArt.ORN.has(id), "the chrome's ornament %s" % id)
	assert_eq(CabinetArt.c(&"no_such_role"), Color.MAGENTA, "a typo shows")
	assert_eq(CabinetArt.mirror(["ab.", "c.."]), [".ba", "..c"])
	assert_eq(CabinetArt.flip_v(["a", "b"]), ["b", "a"])
	var tex := CabinetArt.orn_tile(&"crt_scan", 3.0)
	assert_eq(tex.get_size(), Vector2(3, 9), "a tile is the grid at whole screen px")
	assert_eq(CabinetArt.backdrop(3.0).get_size(), Vector2(36, 36))


## Presentation only: the cabinet reads no RNG, no Tuning, no rules, and holds no image file.
func test_the_cabinet_is_presentation_only() -> void:
	var banned := RegEx.create_from_string("\\b(Tuning|WorldRules|gameplay_rng|director_rng|loot_rng|pick_rng|randf|randi|randomize)\\b|RunState\\.rules")
	for path: String in ["res://ui/cabinet/cabinet_frame.gd", "res://ui/cabinet/cabinet_layout.gd",
			"res://ui/cabinet/cabinet_caption.gd", "res://ui/cabinet/cabinet_plate.gd",
			"res://ui/cabinet/cabinet_player_hud.gd", "res://ui/cabinet/cabinet_chat.gd",
			"res://ui/cabinet/cabinet_chat_view.gd", "res://systems/skins/art/cabinet_art.gd",
			"res://ui/cabinet/cabinet_dock.gd", "res://ui/cabinet/cabinet_packs.gd", "res://ui/cabinet/cabinet_card.gd",
			"res://systems/skins/art/arcade_art.gd", "res://systems/skins/art/arcade_paint.gd"]:
		var code := PackedStringArray()
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var cut := line.find("#")
			code.append(line if cut < 0 or line.count("\"", 0, cut) % 2 == 1 else line.substr(0, cut))
		var m := banned.search("\n".join(code))
		assert_null(m, "%s reads %s" % [path, m.get_string() if m != null else ""])
	var dir := DirAccess.open("res://ui/cabinet")
	for f in dir.get_files():
		assert_true(f.ends_with(".gd") or f.ends_with(".gd.uid"), "ui/cabinet/%s: scripts only, no image file" % f)
