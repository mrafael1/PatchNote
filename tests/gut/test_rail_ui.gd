extends GutTest
## M48.5a: the version rail, the Pixel look's UI style (owner pick 3A). Its layout (the game
## 16:9 and nothing over it at any window), the raw UI untouched while the look's `ui` group is
## off, the swap both ways (rows, labels and the HUD / mascot corners kept), S9's manual reveal
## and the stage card, the ship versions from the campaign data, the modules gated by the
## basics and following the game's state, the chat's slips and the reply box's pills, reduce
## flashing, tool hosts and the font. Hosts here are tool hosts (never live, no window change).
##
## M48.6a: the frame a host builds is now the cabinet (ui/cabinet/, test_cabinet_ui.gd), a
## RailFrame that lays these same pieces out in its own layout; the rail's version track and
## the caption under the game are gone. RailLayout itself is still tested here (its cells and
## text sizes are what the docked pieces use); everything else below runs inside the cabinet.
##
## M48.6c: the cabinet has its own chat (test_cabinet_chat.gd): the rail's paper log and its
## reply box are not built any more. What is still alive of them is tested here: the rail
## chat's marking of the rows (hotfix, patch, hidden choices, the answer's text), which the
## cabinet's dresser inherits, and the reply box's reading of the open question
## (RailFrame.Reply.state_of), which the cabinet's pills use.

const S1 := &"s1_01_move"
const S4 := &"s1_04_level"
const S8 := &"s2_02_day_one"
const TEST_LOG := "user://m48_5a_test/t.jsonl"

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
	Skins.use(_was)
	Skins.reset_reveal(false)
	SaveGame.set_setting("reduce_flashing", false)
	RunState.clear_pauses()
	CampaignDB.active = false
	CampaignDB.jumped = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null


func _hosted(id: StringName, path := &"", view := Vector2i.ZERO) -> GameHost:
	SaveGame.go_inert()
	if path != &"":
		assert_true(CampaignDB.answer_fork(&"fork_path", path))
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var g: Main = load("res://main.tscn").instantiate()
	var h := GameHost.host_for_tools(g, view)
	add_child_autofree(h)
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	RunState.invincible = true
	h.skip_handoff()
	if path != &"":
		for b: StringName in [&"cards", &"levelups", &"pickups"]:
			RunState.add_basic(b)   # the path's growth (S8 adds it on its timeline)
		await wait_physics_frames(2)
	return h


func _pixel(h: GameHost) -> RailFrame:
	Skins.use(Skins.pixel())
	_engine_note()
	assert_not_null(h.rail, "the rail is built on the look's ui group")
	h.rail.refresh()
	return h.rail


## The look turns physics interpolation on; the engine warns once per process that the game's
## camera moves to physics processing (the look's own known note, test_pixel_skin).
func _engine_note() -> void:
	for e in get_errors():
		if e.contains_text("Camera2D overridden to physics process mode"):
			e.handled = true


# --- Layout ------------------------------------------------------------------------------------

func test_the_game_is_16_9_and_nothing_overlaps_it_at_any_window() -> void:
	for win: Vector2 in [Vector2(1600, 900), Vector2(1920, 1080), Vector2(1760, 720), Vector2(1280, 720)]:
		var l := RailLayout.layout_for(win)
		var game: Rect2 = l.game
		assert_almost_eq(game.size.x / game.size.y, 16.0 / 9.0, 0.01, "%s: the game is 16:9" % win)
		assert_almost_eq(float(l.k), game.size.y / 720.0, 0.0001)
		var parts := {"track": l.track, "log": l.log, "reply": l.reply}
		for k: StringName in l.cells:
			parts[k] = l.cells[k]
		var window := Rect2(Vector2.ZERO, win)
		assert_true(window.encloses(game), "%s: the game inside the window" % win)
		for n: String in parts:
			var r: Rect2 = parts[n]
			assert_true(window.encloses(r), "%s: %s inside the window" % [win, n])
			assert_false(r.intersects(game), "%s: %s off the game view" % [win, n])
		assert_false((l.blob as Rect2).intersects(game), "%s: the AI on the rail, off the game" % win)
		for a: String in ["track", "log", "reply", &"kills", &"hp", &"dash", &"path"]:
			for b: String in ["track", "log", "reply", &"kills", &"hp", &"dash", &"path"]:
				if a < b:
					assert_false((parts[a] as Rect2).intersects(parts[b]), "%s: %s / %s" % [win, a, b])
		assert_gte((l.log as Rect2).size.x, 300.0, "%s: the chat stays readable" % win)
	var base := RailLayout.layout_for(Vector2(1600, 900))
	assert_eq(base.game, Rect2(32, 24, 1056, 594), "the mockup's own rect at 1600x900")
	assert_eq(int(base.font), 16)


## Review (M48.5a): the body on the rail sat over the log's bottom right, so the rows and the
## scrollbar ended above it (RailLayout.LOG_BOTTOM_PAD, still the rail layout's own rule).
## M48.6a: the cabinet seats the body in the deck's camera box, off the log.
## M48.6c: the log is the chat's messages area (the terminal's rect), inside the chat column.
func test_the_log_rows_end_inside_the_log_and_the_body_is_off_it() -> void:
	assert_eq(RailLayout.LOG_BOTTOM_PAD, RailLayout.LOG.end.y - RailLayout.BLOB.position.y + 6.0, "the rail's rule")
	assert_true(RailLayout.BLOB.intersects(RailLayout.LOG), "on the rail the body overlapped the log's corner")
	var h := await _hosted(S8, &"path_arsenal")
	var rail := _pixel(h)
	for win: Vector2 in [Vector2(1600, 900), Vector2(1920, 1080), Vector2(1280, 720)]:
		h.relayout(win)
		await wait_process_frames(2)
		var blob: Rect2 = h.layout.blob
		var t := h.terminal
		var lg: Rect2 = h.layout.log
		assert_false(blob.intersects(lg), "%s: the body is off the log (the deck's camera box)" % win)
		assert_eq(Rect2(t.position, t.size), lg, "%s: the terminal is the chat's messages area" % win)
		assert_true((h.layout.chat as Rect2).encloses(lg), "%s: inside the chat column" % win)
	assert_not_null(rail.blob)


# --- Raw stays raw; the swap both ways -----------------------------------------------------------

func test_no_look_keeps_the_raw_terminal_and_hud_exactly() -> void:
	Skins.use(null)
	var h := await _hosted(S8, &"path_arsenal")
	assert_null(h.rail, "no rail without the look")
	assert_null(h.terminal.dresser)
	# M48.5b: a save past S2 opens on the dev-chat (M47.6b), on the dev desktop.
	assert_eq(h.terminal.style, TerminalPanel.CHAT)
	assert_true(h.terminal.chat.visible, "the dev-chat, not the rail's log")
	assert_true(h.desktop.visible, "the dev desktop")
	assert_eq(h.layout, GameHost.layout_for(h.get_viewport().get_visible_rect().size), "the raw layout")
	assert_true(h.game.hud._label.visible, "the HUD corner")
	assert_true(h.game.hud.path_widget.visible, "the hand")
	assert_false(h.game.mascot.docked(), "the corner body")
	assert_eq(h.terminal.input_row().get_parent(), h.terminal.chat.input_slot, "the input in the chat")


func test_the_look_turns_the_rail_on_and_off_and_the_rows_stay() -> void:
	Skins.use(null)
	var h := await _hosted(S8, &"path_arsenal")
	var t := h.terminal
	var typing := t.say_row("still typing", &"happy")
	t.cmd_open("hot-reload game")
	t.finish()
	var before := t.rows()
	var rail := _pixel(h)
	assert_true(rail.on and rail.visible)
	assert_eq(t.dresser, rail.chat, "the terminal is dressed, not replaced")
	assert_eq(t.palette_name, &"rail")
	assert_false(t._title.visible, "the raw title row hides (the chat header)")
	assert_false(t.chat.visible, "M48.5b: the dev-chat hides under the rail's log")
	assert_false(h.desktop.visible, "M48.5b: so does the dev desktop")
	assert_eq(t.input_row().get_parent(), (rail as CabinetFrame).chat_view, "M48.6c: the input sits in the chat's input line")
	assert_true(h.layout.get("rail", false))
	assert_eq(h.game_rect(), h.layout.game as Rect2, "the game view sits in the rail's frame")
	assert_eq(h.viewport.size_2d_override, Vector2i(1280, 720), "the sim size never moves")
	assert_false(h.game.hud._label.visible, "the HUD corner docks into the modules")
	assert_false(h.game.hud.path_widget.visible, "so does the hand")
	assert_true(h.game.mascot.docked(), "the AI sits on the rail")
	assert_eq(t.rows(), before, "the same rows")
	assert_true(is_instance_valid(typing), "a caller's label stays valid")
	t.close_cmd("ok")
	Skins.use(null)
	assert_false(rail.on or rail.visible)
	assert_null(t.dresser)
	assert_eq(t.palette_name, &"raw")
	assert_true(t.chat.visible, "the dev-chat back")
	assert_true(h.desktop.visible)
	assert_eq(t.input_row().get_parent(), t.chat.input_slot, "the input back in the chat")
	assert_true(h.game.hud._label.visible and h.game.hud.path_widget.visible)
	assert_false(h.game.mascot.docked())
	assert_eq(h.layout, GameHost.layout_for(h.get_viewport().get_visible_rect().size))
	var after := t.rows()
	assert_eq(after.slice(0, before.size() - 1), before.slice(0, before.size() - 1))
	assert_eq(after[before.size() - 1], "$ hot-reload game ... ok", "the open command closed on its label")
	for r in t.row_nodes():
		assert_true((r as Control).visible, "every row visible again")
		assert_eq((r as Control).self_modulate, Color.WHITE)


func test_s9_manual_reveal_and_the_stage_card() -> void:
	Skins.use(null)
	var h := await _hosted(S8, &"path_survival")
	Skins.use(Skins.pixel())
	Skins.reset_reveal(true)   # S9: nothing revealed yet
	h._sync_rail()
	assert_false(h.rail.on, "before 55 s the raw terminal stays")
	assert_null(h.terminal.dresser)
	Skins.reveal(&"ui")
	assert_true(h.rail.on, "S9's `skin ui` turns the rail on")
	h.chapter = true
	h._sync_rail()
	assert_false(h.rail.on, "a stage card hides it (the game fills the window)")
	h.chapter = false
	h._sync_rail()
	assert_true(h.rail.on)


## Review: in a live windowed host the window took the rail's base on every on / off (the S9
## reveal, each retry, every stage card). It takes it once; nothing after moves it.
func test_the_window_takes_the_rail_base_once_and_never_flips_back() -> void:
	var base := Settings._base_size
	Skins.use(null)
	var h := await _hosted(S8, &"path_survival")
	Skins.use(Skins.pixel())
	Skins.reset_reveal(true)   # S9: nothing revealed yet
	h._sync_rail()
	assert_false(h.rail != null and h.rail.on)
	h._window_set = true   # as a live, windowed host (no real window here: Settings skips it)
	h.rail_base_set = false
	Settings.set_window_base(GameHost.BASE)
	assert_eq(Settings._base_size, GameHost.BASE, "raw before the reveal")
	Skins.reveal(&"ui")
	assert_true(h.rail.on)
	assert_eq(Settings._base_size, CabinetLayout.BASE, "the reveal: the rail's 16:9 base")
	assert_true(h.rail_base_set)
	Settings._scale_applied = 1.0   # as applied
	h.chapter = true
	h._sync_rail()
	assert_false(h.rail.on)
	assert_eq(Settings._base_size, CabinetLayout.BASE, "a stage card keeps the window")
	assert_eq(Settings._scale_applied, 1.0, "no re-apply (no resize, no re-centre)")
	h.chapter = false
	h._sync_rail()
	Skins.reset_reveal(true)   # an S9 retry: the raw terminal again until 55 s
	assert_false(h.rail.on)
	assert_eq(Settings._base_size, CabinetLayout.BASE, "a retry keeps the window")
	Skins.reveal(&"ui")
	assert_true(h.rail.on)
	assert_eq(Settings._scale_applied, 1.0, "and its second reveal does not resize either")
	h._window_set = false   # never run the live exit on a tool host
	Settings.set_window_base(base)


# --- Versions and gating ---------------------------------------------------------------------

func test_ship_versions_come_from_the_campaign_data() -> void:
	assert_eq(RailModel.ship_label(&"kills"), "v0.2", "enemies: s1_02")
	assert_eq(RailModel.ship_label(&"hp"), "v0.3", "health: s1_03")
	assert_eq(RailModel.ship_label(&"dash"), "v0.4", "dash: s1_04")
	assert_eq(RailModel.ship_label(&"version"), "v0.6")
	assert_eq(RailModel.ship_label(&"path"), "v0.7", "the tryout's path")
	assert_eq(RailModel.ship_label(&"pack"), "v0.8", "the first chosen path")
	var v := GameVersion.make(0, 4, 0)
	assert_true(RailModel.shipped(&"dash", v))
	assert_false(RailModel.shipped(&"path", v))
	assert_eq(RailModel.minors(GameVersion.make(0, 8, 1)).size(), 8, "v0.1 .. v0.8")


func test_modules_exist_only_once_their_basic_is_live() -> void:
	var h := await _hosted(S1)
	var rail := _pixel(h)
	assert_false(rail.snap.kills.on or rail.snap.hp.on or rail.snap.dash.on, "S1: movement only")
	assert_eq(rail.modules.shown_modules(), [] as Array[StringName])
	assert_eq(rail.snap.path.kind, &"", "no path in Stage 1")
	Skins.use(null)
	var h4 := await _hosted(S4)
	var rail4 := _pixel(h4)
	assert_true(rail4.snap.kills.on and rail4.snap.hp.on and rail4.snap.dash.on, "S4: all three are read")
	# M48.6b: the cabinet gives them no module (they are on the player and the corner plate);
	# on the rail's own layout they are modules as before.
	assert_eq(rail4.modules.shown_modules(), [] as Array[StringName], "none in the cabinet's deck")
	rail4.layout = RailLayout.layout_for(Vector2(1600, 900))
	assert_eq(rail4.modules.shown_modules(), [&"kills", &"hp", &"dash"] as Array[StringName])
	rail4.layout = h4.layout


# --- Module values follow the game -------------------------------------------------------------

func test_hp_kills_and_dash_follow_the_game() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var rail := _pixel(h)
	var health := Component.find(h.game.player, Health) as Health
	var top := ceili(health.max_hp() - 0.001)
	health.hp_ratio = (top - 2.0) / health.max_hp()
	h.game.session_runner.hits = 2
	RunState.kills = 41
	rail.refresh()
	assert_eq(int(rail.snap.hp.hp), top - 2, "HP after two hits")
	assert_eq(int(rail.snap.hp.max), top)
	assert_eq(int(rail.snap.hp.hits), 2)
	assert_eq(int(rail.snap.kills.n), 41)
	assert_true(rail.snap.dash.ready)
	var dasher := Component.find(h.game.player, Dasher) as Dasher
	assert_true(dasher.use(Vector2.RIGHT))
	rail.refresh()
	assert_false(rail.snap.dash.ready, "RECHARGING")
	await wait_physics_frames(12)
	rail.refresh()
	var f: float = rail.snap.dash.frac
	assert_true(f > 0.0 and f < 1.0, "the fill grows: %s" % f)
	assert_almost_eq(float(rail.snap.dash.total), Tuning.dash_cooldown, 0.001, "the move's cooldown")
	await wait_seconds(Tuning.dash_cooldown + 0.1)
	rail.refresh()
	assert_true(rail.snap.dash.ready, "READY again")
	assert_eq(rail.snap.dash.frac, 1.0)


func test_the_hand_and_the_pack_follow_the_loadout() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var rail := _pixel(h)
	var lo := h.game.path_runner.loadout()
	lo.give(&"shotgun", 4)
	lo.set_weapon(&"pistol", 12)
	rail.refresh()
	var hand: Dictionary = rail.snap.path.hand
	assert_eq(rail.snap.path.kind, &"hand")
	assert_eq((hand.cards as Array).size(), 2, "a hand of 2")
	assert_eq(int(hand.max), 2)
	var ranks := {}
	for c: Dictionary in hand.cards:
		ranks[c.title] = c.rank
	assert_eq(int(ranks.get("Pistol", 0)), 12, "no rank cap: 8 pips then +4")
	assert_eq(int(ranks.get("Shotgun", 0)), 4)
	assert_true(hand.cards[lo.active].active)
	var meter: RefCounted = h.game.path_runner.meter()
	meter.set(&"kills", int(meter.get(&"cards")) * 6 + 4)
	rail.refresh()
	assert_true(rail.snap.path.pack.on)
	assert_eq(int(rail.snap.path.pack.x), 4, "4/6")
	assert_eq(int(rail.snap.path.pack.every), 6)
	assert_eq(int(rail.snap.path.pack.left), 2)


func test_auto_items_follow_the_loadout() -> void:
	var h := await _hosted(S8, &"path_auto")
	var rail := _pixel(h)
	assert_eq(rail.snap.path.kind, &"items")
	var items: Dictionary = rail.snap.path.items
	assert_eq(int(items.slots), 3, "auto.tres max_slots (M50.4a: 3 shared)")
	assert_eq(int(items.passive_slots), 2, "M50.4a: the 2 item slots (max_items)")
	assert_eq(int(items.cap), 6, "M50.4a: Auto ranks to 6")
	assert_eq((items.weapons as Array).size(), h.game.path_runner.loadout().weapon_count())
	assert_eq(int(items.level), h.game.path_runner.level())


func test_survival_ammo_follows_the_loadout() -> void:
	var hs := await _hosted(S8, &"path_survival")
	var rail2 := _pixel(hs)
	assert_eq(rail2.snap.path.kind, &"ammo")
	var lo := hs.game.path_runner.loadout()
	var ammo: Dictionary = rail2.snap.path.ammo
	assert_eq(String(ammo.sidearm), "Revolver", "M47.6d1: the revolver is the sidearm, it never runs dry")
	assert_true(lo.on_sidearm(), "Survival starts on the sidearm")
	assert_eq(int(ammo.total), -1, "on the sidearm: no shells to count")
	# M48.5b: the revolver's load and its reload.
	var rev := lo.current()
	assert_eq(int(ammo.magazine), 6, "six rounds (revolver.tres)")
	assert_eq(int(ammo.mag), 6)
	assert_lt(float(ammo.reload), 0.0, "not reloading")
	rev.spend_round()
	rail2.refresh()
	assert_eq(int(rail2.snap.path.ammo.mag), 5, "it follows every shot")
	while rev.mag_left > 0:
		rev.spend_round()
	rail2.refresh()
	assert_true(rev.reloading())
	assert_between(float(rail2.snap.path.ammo.reload), 0.0, 1.0, "the reload's fill")
	rev.tick_reload(99.0)
	rail2.refresh()
	assert_eq(int(rail2.snap.path.ammo.mag), 6, "full again")
	# Review: a crate's shotgun, the AMMO module counts its shells.
	assert_true(lo.give(&"shotgun", 2))
	assert_false(lo.on_sidearm(), "the shotgun is in hand")
	var w := lo.current()
	assert_gt(w.def.ammo, 0)
	w.ammo_left = 18
	rail2.refresh()
	ammo = rail2.snap.path.ammo
	assert_eq(int(ammo.left), 18)
	assert_eq(int(ammo.total), w.def.ammo, "24 shells (shotgun.tres)")
	assert_eq(String(ammo.title), w.label())
	assert_eq(int(ammo.rank), 2)
	assert_false(bool(ammo.on_sidearm))
	w.ammo_left = 7
	rail2.refresh()
	assert_eq(int(rail2.snap.path.ammo.left), 7, "it follows every shot")
	# Dry: the sidearm again, nothing to count.
	lo.to_sidearm()
	rail2.refresh()
	ammo = rail2.snap.path.ammo
	assert_true(bool(ammo.on_sidearm))
	assert_eq(int(ammo.total), -1)
	assert_eq(String(ammo.title), lo.sidearm.label())


# --- The chat's rows and the open question -------------------------------------------------------

func test_patch_and_hotfix_slips_and_choices_in_the_reply_box() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var rail := _pixel(h)
	var t := h.terminal
	t.cmd("patch apply v0.9.0")
	t.notes({"Added": ["A thing"], "Changed": ["Another"]})
	rail.chat.mark_hotfix("$ set dash.cooldown", "v0.8.0+1")
	t.cmd("set dash.cooldown 0.6", "ok")
	t.finish()
	rail.chat.step()
	var patch_row: Control = null
	var hot_row: Control = null
	for r in t.row_nodes():
		var text := RailFrame.Chat.label_text(r)
		if text == "$ patch apply v0.9.0":
			patch_row = r
		elif text.begins_with("$ set dash.cooldown"):
			hot_row = r
	assert_not_null(patch_row)
	assert_eq(patch_row.self_modulate.a, 0.0, "the slip's strip stands in for the command row")
	assert_eq(String(hot_row.get_meta(&"hotfix", "")), "v0.8.0+1", "a live edit is a hotfix slip")
	assert_eq(RailFrame.module_named("set dash.cooldown 0.6"), &"dash", "a hotfix naming the dash tags it")
	assert_eq(RailFrame.module_named("set enemy.speed 1.15"), &"")
	var picked: Array[int] = []
	t.chosen.connect(func(i: int) -> void: picked.append(i))
	t.ask(["again", "move on"] as Array[String])
	t.finish()
	rail.chat.step()
	var st: Dictionary = RailFrame.Reply.state_of(t)
	assert_eq(st.choices, ["again", "move on"] as Array[String], "the choices are pills")
	assert_true(st.prompt)
	for r in t.row_nodes():
		if int(r.get_meta(&"kind", -1)) == TerminalPanel.Row.CHOICE:
			assert_false((r as Control).visible, "not in the log")
	# M48.6c: the pills are the cabinet chat's.
	var view: Control = (rail as CabinetFrame).chat_view
	var pills: Array[Rect2] = view.pill_rects()
	assert_eq(pills.size(), 2)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pills[1].get_center()
	view._gui_input(e)
	assert_eq(picked, [1] as Array[int], "a click on a pill chooses, as on the raw row")
	t.answer("2")
	rail.chat.step()
	assert_false(RailFrame.Reply.state_of(t).prompt)
	var last: Control = t.row_nodes().back()
	assert_true(last.visible, "the answer is a 'you' message in the log")
	assert_eq(rail.chat._answer_text(t.row_nodes(), t.row_nodes().size() - 1), "move on")


## M48.5b: the rail dresses a terminal past the chat upgrade: new rows are raw rows the rail
## draws, rows() keeps every row in order, and undressing brings the chat back.
func test_rows_made_under_the_rail_keep_their_order_in_the_chat() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var t := h.terminal
	assert_true(t.is_chat())
	t.say_row("before the rail")
	t.finish()
	var rail := _pixel(h)
	assert_eq(t.row_nodes().size(), 0, "the rail's log starts at its reveal")
	var l := t.say_row("under the rail", &"happy")
	t.cmd("patch apply v0.9.0")
	t.finish()
	assert_false(t.chat.is_ancestor_of(l), "a raw row the rail draws")
	assert_gt(t.row_nodes().size(), 0)
	var rows := t.rows()
	var a := rows.find("  before the rail")
	var b := rows.find("  under the rail")
	assert_true(a >= 0 and b > a, "in order: %s" % [rows])
	assert_eq(rows.back(), "$ patch apply v0.9.0")
	var n := t.row_count()
	assert_eq(n, rows.size(), "row_count counts each row once")
	Skins.use(null)
	assert_false(rail.on)
	t.say_row("after the rail")
	t.finish()
	assert_eq(t.rows().back(), "  after the rail", "back in the chat")
	assert_eq(t.rows().size(), n + 2, "header and line")


## M48.5b (the play gate, M47.6a): under the rail the gate is typed in the reply box's well,
## and its one `play` pill gives play as the chat's pill does. M48.6c: the well is the cabinet
## chat's input line, the pill its pill.
func test_the_play_gate_in_the_reply_box() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var rail := _pixel(h)
	var t := h.terminal
	var played: Array[bool] = []
	t.chat_input.play_given.connect(func() -> void: played.append(true))
	t.chat_input.gentle = true
	t.chat_input.open_gate()
	var view: Control = (rail as CabinetFrame).chat_view
	var st: Dictionary = RailFrame.Reply.state_of(t)
	assert_true(bool(st.gate))
	assert_eq(RailFrame.Reply.pills_of(st), ["play"] as Array[String], "one play pill")
	assert_eq(RailFrame.Reply.well_hint(st), "", "the input's own ghost shows")
	assert_eq(RailFrame.Reply.key_of(st, 0), "", "review: no key chip on the gate pill (1 only types '1')")
	assert_eq(RailFrame.Reply.key_of({"choices": ["a", "b"], "gate": false}, 1), "2", "open choices keep their keys")
	var well: Rect2 = view.parts().input
	var row := t.input_row()
	assert_true(well.encloses(Rect2(row.position, row.size)), "the input in the well")
	t.chat_input.text = "play"
	t.chat_input.submit(true)
	assert_eq(played.size(), 1, "typed play")
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = (view.pill_rects()[0] as Rect2).get_center()
	view._gui_input(e)
	assert_eq(played.size(), 2, "the pill gives play")
	t.chat_input.close_gate()
	assert_eq(RailFrame.Reply.pills_of(RailFrame.Reply.state_of(t)).size(), 0)


## Review: S8's death asks, then says two more lines, then posts the choices; the box pairs the
## pills with the question, not the last line said.
func test_the_reply_box_shows_the_question_not_the_lines_after_it() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var rail := _pixel(h)
	var t := h.terminal
	t.say_row("Earlier, a question? Not this one.")
	t.ask(["yes", "no"] as Array[String])
	t.finish()
	t.answer("1")
	t.say_row("Day one bugs. Want another go, or should I just patch it?")
	t.say_row("Cards feel good, though.")
	t.say_row("Next time, I'll have something to show you. A drawing. My first.")
	t.ask(["again", "move on (I'll take this one)"] as Array[String])
	t.finish()
	rail.chat.step()
	var st: Dictionary = RailFrame.Reply.state_of(t)
	assert_eq(st.choices, ["again", "move on (I'll take this one)"] as Array[String])
	assert_eq(String(st.question), "Day one bugs. Want another go, or should I just patch it?",
			"the asking line, three rows up")
	t.answer("1")
	t.say_row("Right. Here is the plan.")
	t.ask(["go", "wait"] as Array[String])
	t.finish()
	assert_eq(String(RailFrame.Reply.state_of(t).question), "Right. Here is the plan.",
			"no question since the last answer: the last line said, never an older exchange's")
	t.answer("1")
	t.say_row("Is this a question?")
	t.say_row("Watching now.")
	t.finish()
	assert_eq(String(RailFrame.Reply.state_of(t).question), "Watching now.",
			"no choices open: the latest line, not an older question")


# --- Reduce flashing, tool hosts, the font -------------------------------------------------------

func test_reduce_flashing_holds_every_blink_and_the_reveal_is_instant() -> void:
	Skins.use(null)
	var h := await _hosted(S8, &"path_arsenal")
	SaveGame.set_setting("reduce_flashing", true)   # after the host's inert save
	var rail := _pixel(h)
	assert_eq(rail.modulate.a, 1.0, "no crossfade: an instant swap")
	for i in 3:
		assert_true(rail.blink(1.0), "the current tick and the live dot are steady")
		assert_true(h.terminal.caret_on(Time.get_ticks_usec()), "the caret too")
		await wait_seconds(0.3)
	SaveGame.set_setting("reduce_flashing", false)
	Skins.use(null)
	Skins.use(Skins.pixel())
	_engine_note()
	assert_lt(rail.modulate.a, 1.0, "with flashing on, the reveal crossfades")


func test_a_tool_host_keeps_its_view_size_and_the_window() -> void:
	var base := Settings._base_size
	var h := await _hosted(S8, &"path_arsenal", Vector2i(1560, 878))
	_pixel(h)
	assert_eq(h.viewport.size, Vector2i(1560, 878), "the tool's override holds")
	assert_eq(h.viewport.size_2d_override, Vector2i(1280, 720))
	assert_eq(Settings._base_size, base, "no window change from a tool host")


func test_the_pixel_font_loads_and_covers_the_lines() -> void:
	var f := UiTheme.pixel_font()
	assert_true(f is FontVariation)
	# M48.5b: the digits font first, then Pixelify (its variation) for everything else.
	var base := ((f as FontVariation).fallbacks[0] as FontVariation).base_font
	assert_eq(base.resource_path, UiTheme.PIXEL_FONT)
	assert_true(FileAccess.file_exists("res://ui/rail/font/OFL.txt"), "the OFL licence ships with it")
	for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,:;!?'-+/()[]$%>_":
		assert_true(base.has_char(ch.unicode_at(0)), "Pixelify has %s" % ch)
	var missing: Array[String] = []
	var text := FileAccess.get_file_as_string("res://campaign/lines_stage2.md")
	for i in text.length():
		var c := text.unicode_at(i)
		if c < 32:
			continue
		if not base.has_char(c) and not UiTheme.mono_font().has_char(c) and not missing.has(text[i]):
			missing.append(text[i])
	assert_eq(missing, [] as Array[String], "every line's glyph, in the font or its mono fallback")


## M48.5b (owner nit: the small text's 2 read as an 8): the rail's text draws 0-9 from its
## own pixel digits, every stroke whole pixels inside the glyph's box, and each digit's
## shape distinct from its look-alikes at every size the rail uses.
func test_small_digits_are_whole_pixels_and_distinct() -> void:
	for bold in [false, true]:
		for size in [12, 13, 14, 16, 18, 24, 32]:
			var h := RailArt.small_digit_h(size, bold)
			var w := RailArt.small_digit_w(size, bold)
			var box := Rect2(0, 0, w, h)
			var adv := RailFrame.text_w("0", size, bold)
			assert_lte(float(w), adv, "%d: the digit fits the font's advance" % size)
			var shapes := {}
			for d in "0123456789":
				var rects := RailArt.small_digit(d, size, bold)
				assert_false(rects.is_empty())
				for r in rects:
					assert_eq(r.position, r.position.round(), "whole pixels")
					assert_eq(r.size, r.size.round())
					assert_true(box.encloses(r), "%s at %d inside its box" % [d, size])
				shapes[d] = str(rects)
			for pair: Array in [["2", "8"], ["5", "6"], ["0", "8"], ["1", "7"], ["3", "8"], ["9", "8"]]:
				assert_ne(shapes[pair[0]], shapes[pair[1]], "%s vs %s at %d" % [pair[0], pair[1], size])
	# The rail's font draws them (its Labels, the log, the input too) and keeps Pixelify's widths.
	var f := UiTheme.pixel_font()
	var base := (f as FontVariation).fallbacks[0] as Font
	for size in [12, 16, 24]:
		assert_true((f as FontVariation).base_font.has_char("2".unicode_at(0)), "the digits font has 2")
		assert_false((f as FontVariation).base_font.has_char("S".unicode_at(0)), "letters fall through")
		assert_almost_eq(f.get_string_size("v0.2.0 12", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x,
				base.get_string_size("v0.2.0 12", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, 2.0, "the same width at %d (whole-pixel advances: within 2 px)" % size)
		assert_almost_eq(f.get_height(size), base.get_height(size), 0.5, "the same line height at %d" % size)


## M50.5 (merge): the digits font has caches at whole sizes only, so it must not oversample: in
## the game's SubViewport (Auto's Pixel level-up cards) an oversampled size found no glyph and
## the card's numbers were blank.
func test_the_digits_font_never_oversamples() -> void:
	for bold in [false, true]:
		var f := UiTheme.pixel_font(bold) as FontVariation
		var digits := f.base_font as FontFile
		assert_eq(digits.oversampling, 1.0, "bold=%s: the digit caches are drawn at their own size" % bold)


## M50.5a (owner: "fifty" read "Aifty", "fire rate" "Are rate", "five pellets" "Awe pellets"):
## Pixelify's ligatures joined "fi" (and fl, ff, ffi, st) into one glyph that reads as an A at
## the small sizes. The pixel font shapes every letter on its own: "fi" is two glyphs, as wide
## as its f and its i, in both weights and at every size the chat, cards and rail use.
func test_the_pixel_font_never_joins_letters() -> void:
	var ts := TextServerManager.get_primary_interface()
	for bold in [false, true]:
		var f := UiTheme.pixel_font(bold)
		for size in [10, 11, 12, 13, 14, 16, 18]:
			for word: String in ["fi", "fl", "ff", "ffi", "st", "first", "five pellets", "fire rate", "fifty"]:
				var line := TextLine.new()
				line.add_string(word, f, size)
				assert_eq(ts.shaped_text_get_glyph_count(line.get_rid()), word.length(),
						"bold=%s %d: \"%s\" is one glyph per letter" % [bold, size, word])
			assert_almost_eq(f.get_string_size("fi", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x,
					f.get_string_size("f", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
					+ f.get_string_size("i", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, 1.5,
					"bold=%s %d: fi is an f then an i (kerning: within 1.5 px)" % [bold, size])


## M50.6a: Pixelify closes a capital C into an O or a D at 9, 10 and 13 px ("PACK" read "PAOK"
## on a 1280 px window, where the rail's 16 px labels landed on 13). The rail never draws at
## those sizes, and at a full-size window nothing changes.
func test_the_rail_never_draws_text_at_a_size_that_closes_the_c() -> void:
	assert_eq(RailLayout.text_px(16, 0.8), 12, "1280 px: 16 * 0.8 = 13 steps to 12")
	assert_eq(RailLayout.text_px(16, 1.0), 16, "the design size is itself")
	assert_eq(RailLayout.text_px(12, 0.8), 12)
	assert_eq(UiTheme.pixel_size(10), 11)
	assert_eq(UiTheme.pixel_size(14), 14)
	for d: int in [10, 12, 16, 24]:
		for i in 41:
			var s := 0.5 + i * 0.05
			assert_false(RailLayout.text_px(d, s) in [9, 10, 13], "design %d at scale %.2f" % [d, s])
