extends GutTest
## M47.2 (owner G14a: "mascot on the right hide UI => put UI to the top right"; "cards should
## have a card hand on bottom left"): in a campaign session nothing the player needs is under
## the mascot, for every body, path and canvas size. The top-right band (Hud.BAND_TOP..
## BAND_BOTTOM) holds the corner text and, left of it, the path widget; the mascot sits under
## it (Mascot.TOP) and never rises into it (MascotBody.top_limit); Arsenal's hand is bottom
## left. Every rect is a pure function of the canvas size, so one headless boot checks them
## all. With stretch canvas_items + expand, a window maps to a canvas of at least 1280 x 720.

const TEST_LOG := "user://save_hud_layout_test/runs.jsonl"
const HandWidget := preload("res://paths/arsenal/hand_widget.gd")
const VIEWS: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 960), Vector2(1706, 720)]
const BODIES: Array[StringName] = [&"caret", &"cursor", &"window", &"blob"]
const S8 := &"s2_02_day_one"

var game: Main


func before_each() -> void:
	Telemetry.log_path = TEST_LOG


func after_each() -> void:
	await wait_physics_frames(2)   # deferred spawns land before the game is freed (no orphan)
	assert_false(FileAccess.file_exists(TEST_LOG), "no telemetry written, not even to the scratch log")
	Telemetry.log_path = Telemetry.DEFAULT_PATH
	RunState.invincible = false
	CampaignDB.active = false
	SaveGame.go_inert()
	RunState.reset(0)
	RunState.world = null


## Session `id` (on path `p` when given), jumped to on an inert save, invincible.
func _boot(id: StringName, p := &"") -> Main:
	SaveGame.go_inert()
	if p != &"":
		assert_true(CampaignDB.answer_fork(&"fork_path", StringName("path_%s" % p)))
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(id))
	var g: Main = load("res://main.tscn").instantiate()
	add_child_autofree(g)
	if g.stage_card != null:
		g.stage_card.skip()
	await wait_physics_frames(2)
	game = g
	RunState.invincible = true
	return g


func _at(seconds: float) -> void:
	game.run_loop.goal_clock = seconds - 0.01
	await wait_physics_frames(3)


func _lo() -> Loadout:
	return Component.find(game.player, Loadout) as Loadout


## Each path's widget at its widest: Arsenal 3 cards at rank 3; Auto 3 slots and 2 passives
## at rank 3, level 10; Survival the launcher at rank 3, full, with the sidearm.
func _fill(p: StringName) -> void:
	var lo := _lo()
	match p:
		&"arsenal":
			for w: StringName in [&"pistol", &"shotgun", &"laser"]:
				lo.set_weapon(w, Loadout.MAX_RANK)
		&"auto":
			for w in WeaponDB.all():
				lo.set_weapon(w.id, Loadout.MAX_RANK)
			game.path_runner.meter().set(&"level", 10)
		&"survival":
			lo.set_weapon(&"launcher", Loadout.MAX_RANK)
			assert_true(lo.select(&"launcher"))
	await wait_physics_frames(2)


## The rects the player needs on a canvas of size `view`: the corner text, the goal and the
## path widget (the band widget where Hud puts it at that size, or the hand and its cards).
func _hud_rects(view: Vector2) -> Dictionary:
	var out := {"corner": Hud.corner_rect(view), "goal": Hud.goal_rect(view)}
	var w := game.hud.path_widget
	if w == null:
		return out
	if w.has_method(&"hand_rect"):
		out["hand"] = w.hand_rect(view)
		out["meter"] = w.meter_rect(view)
		for i in w.card_count():
			out["card %d" % i] = w.card_rect(i, view)
	else:
		game.hud.layout_path_widget(view)
		out["band widget"] = _widget_rect(w)
		game.hud.layout_path_widget(game.get_viewport().get_visible_rect().size)
	return out


## Everything a band widget draws: its own minimum size and each child's (labels, bars), so
## a widget that only lays out children (no minimum size of its own) is still measured.
func _widget_rect(w: Control) -> Rect2:
	var r := Rect2(w.position, w.get_combined_minimum_size())
	for c in w.get_children():
		if c is Control and (c as Control).visible:
			var cc := c as Control
			var size := Vector2(maxf(cc.size.x, cc.get_combined_minimum_size().x), maxf(cc.size.y, cc.get_combined_minimum_size().y))
			r = r.merge(Rect2(w.position + cc.position, size))
	return r


func _assert_clear_of_the_mascot(where: String) -> void:
	for body in BODIES:
		game.mascot.setup(body != &"caret", body)
		for view in VIEWS:
			var keep: Rect2 = game.mascot.keep_out(view)
			var rects := _hud_rects(view)
			for k: String in rects:
				assert_false(keep.intersects(rects[k]), "%s, %s, %s: the mascot %s covers the %s %s"
						% [where, body, view, keep, k, rects[k]])


func test_nothing_under_the_mascot_for_every_body_path_and_size() -> void:
	for id: StringName in [&"s1_04_level", &"s1_06_playground", &"s2_01_tryout"]:
		await _boot(id)
		_assert_clear_of_the_mascot(String(id))
		game.free()
	for p: StringName in [&"arsenal", &"auto", &"survival"]:
		await _boot(S8, p)
		await _at(31.0)
		assert_not_null(game.hud.path_widget, "%s: its widget by 31 s" % p)
		await _fill(p)
		_assert_clear_of_the_mascot("S8 " + p)
		game.free()


## At rest the mascot is under the band; a hop, pop or pointing lean never rises into it.
func test_the_mascot_never_rises_into_the_band() -> void:
	await _boot(&"s1_06_playground")
	for body in BODIES:
		game.mascot.setup(body != &"caret", body)
		for view in VIEWS:
			assert_gt(game.mascot.keep_out(view).position.y, Hud.BAND_BOTTOM, "%s at %s" % [body, view])
	var stage_card_like := Mascot.new()
	stage_card_like.offset = Vector2(-400, 200)
	add_child_autofree(stage_card_like)
	assert_eq(stage_card_like.corner_top_limit(), -INF, "a shifted mascot (the stage card) keeps its whole pose")


## The live corner text fits its reserved rect at the widest it gets in a session.
func test_the_corner_text_fits_its_reserved_rect() -> void:
	await _boot(&"s1_06_playground")
	var label: Label = game.hud._label
	var view := game.get_viewport().get_visible_rect().size
	label.text = Hud.CORNER_WIDEST[0] + "\n" + Hud.CORNER_WIDEST[1]
	await wait_process_frames(1)
	var r := Rect2(Vector2(view.x - Hud.CORNER_RIGHT - label.get_combined_minimum_size().x, 8.0), label.get_combined_minimum_size())
	assert_true(Hud.corner_rect(view).encloses(r), "%s in %s" % [r, Hud.corner_rect(view)])


func test_the_band_widget_stays_left_of_the_corner_text_and_right_of_the_goal() -> void:
	for p: StringName in [&"auto", &"survival"]:
		await _boot(S8, p)
		await _at(31.0)
		await _fill(p)
		var w := game.hud.path_widget
		for view in VIEWS:
			var r: Rect2 = _hud_rects(view)["band widget"]
			assert_true(Hud.band_rect(view).encloses(r), "%s at %s: %s in the band %s" % [p, view, r, Hud.band_rect(view)])
			assert_false(r.intersects(Hud.corner_rect(view)), "%s: left of the corner text" % p)
			assert_false(r.intersects(Hud.goal_rect(view)), "%s: right of the goal" % p)
			assert_lte(r.size.x, Hud.PATH_MAX_W)
		# Placed against the reserved corner width, not the live text: it never jitters.
		var view := game.get_viewport().get_visible_rect().size
		game.hud.layout_path_widget(view)
		var x := w.position.x
		for t: String in ["HP 9", "HP 100   v0.8.1\nteleport ready", "HP 9   v0.8.1\ndash ..."]:
			game.hud._label.text = t
			game.hud.layout_path_widget(view)
			assert_eq(w.position.x, x, "%s: the same x with the corner text '%s'" % [p, t])
		game.free()


## Every line the AI can say in a bubble (all 9 sessions and every reaction) misses the HUD.
func test_every_line_bubble_misses_the_hud() -> void:
	var lines: Array[Line] = []
	for s in CampaignDB.campaign.sessions:
		lines.append_array(s.intro_lines())
		lines.append_array(s.debrief_lines())
		for c in s.cue_list():
			if c.line != null:
				lines.append(c.line)
	for r in CampaignDB.reactions:
		lines.append_array(r.line_list())
	assert_gt(lines.size(), 100)
	for view in VIEWS:
		var hud := [Hud.corner_rect(view), Hud.goal_rect(view), Hud.band_rect(view), HandWidget.hand_rect(view)]
		for l in lines:
			var b := Mascot.bubble_rect(InputSetup.expand_keys(l.text), view)
			for r: Rect2 in hud:
				assert_false(b.intersects(r), "%s: '%s' %s meets %s" % [view, l.text, b, r])


## The hand sits bottom left with its meter, inside the left 30% and bottom 20%, out of the
## centre 70% (PLAN 1.8's M51 test stays satisfiable), its titles and pips on screen.
func test_the_hand_sits_bottom_left_with_its_meter() -> void:
	await _boot(S8, &"arsenal")
	await _at(31.0)
	await _fill(&"arsenal")
	var w := game.hud.path_widget
	assert_true(w.has_method(&"hand_rect"))
	assert_eq(w.card_count(), 3)
	for view in VIEWS:   # a joining card slides up from below: its title and pips still show
		for i in 3:
			for r: Rect2 in [w.title_rect(i, view), w.pips_rect(i, view)]:
				assert_true(Rect2(Vector2.ZERO, view).encloses(r), "card %d's title and pips while it joins" % i)
	w.step(1.0)
	for view in VIEWS:
		var hand: Rect2 = w.hand_rect(view)
		assert_true(Rect2(0, view.y * 0.8, view.x * 0.3, view.y * 0.2).encloses(hand), "%s: %s" % [view, hand])
		assert_true(hand.encloses(w.meter_rect(view)), "the meter sits with the hand")
		assert_false(hand.intersects(Rect2(view * 0.15, view * 0.7)), "out of the centre 70%")
		for i in 3:
			for r: Rect2 in [w.title_rect(i, view), w.pips_rect(i, view), w.card_rect(i, view)]:
				assert_true(Rect2(Vector2.ZERO, view).encloses(r), "card %d on screen at %s" % [i, view])
	var live := game.get_viewport().get_visible_rect().size
	assert_eq(w.position, w.hand_rect(live).position, "Hud places it where hand_rect says")


## The transition toast (bottom wide, y H-120..H-50, centred, font 20) never reaches the
## hand: the toasts a Stage 2 session can show (the stage-set lines; the smoke and dev
## lines are Stage 1 / legacy only).
func test_the_transition_toast_misses_the_hand() -> void:
	var font := ThemeDB.fallback_font
	for line: String in [Dialogue.STAGE_CLEAR % [9, 9], Dialogue.EXIT_OPEN]:
		var size := font.get_string_size("AI: " + line, HORIZONTAL_ALIGNMENT_LEFT, -1, 20) + Vector2(12, 12)
		for view in VIEWS:
			var toast := Rect2(Vector2(view.x * 0.5 - size.x * 0.5, view.y - 50.0 - size.y), size)
			assert_false(toast.intersects(HandWidget.hand_rect(view)), "%s: '%s' %s meets the hand %s"
					% [view, line, toast, HandWidget.hand_rect(view)])


## PLAN 9's default: the mascot stays top-right (its corner's right edge at W - 16).
func test_the_mascot_is_still_top_right() -> void:
	await _boot(&"s1_06_playground")
	var view := game.get_viewport().get_visible_rect().size
	var corner: Control = game.mascot._corner
	assert_almost_eq(corner.get_global_rect().end.x, view.x - Mascot.MARGIN, 0.5)
	assert_lt(corner.get_global_rect().get_center().y, view.y / 3.0)


## The legacy loop's HUD is untouched: no session, the old corner text, no path widget.
func test_the_legacy_hud_is_untouched() -> void:
	SaveGame.go_inert()
	game = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	assert_null(RunState.session)
	assert_null(game.hud.path_widget)
	assert_null(game.mascot, "no mascot in the run loop")
	var label: Label = game.hud._label
	assert_string_starts_with(label.text, "HP ")
	assert_string_contains(label.text, "Kills ")
	assert_eq(label.position.y, 8.0)


## Mascot.TOP (76 since M47.2): every resting pose (no hop, pop or lean) already clears the
## band without the clamp, so top_limit only ever trims the overshoots.
func test_the_resting_mascot_clears_the_band_without_the_clamp() -> void:
	for id in BODIES:
		var b := MascotBody.make(id)
		add_child_autofree(b)
		b.frozen = true
		for e: StringName in [&"idle", &"proud", &"worried", &"guilty", &"thinking", &"panic"]:
			b.set_expression(e)
			for i in 120:
				b.t = i / 60.0
				b.expr_t = 1.0
				var top := Mascot.TOP + Mascot.SIZE * 0.5 + b.posed_bounds().position.y * Mascot.SIZE / 100.0
				assert_gt(top, Hud.BAND_BOTTOM, "%s %s at t %s: top %s" % [id, e, b.t, top])
