extends GutTest
## M48.6c: the cabinet's dev-chat (PLAN 0.9.2 "The chat"). The chat column's parts (header,
## build log, messages, pills, input: stacked, never overlapping, at every window), what is
## built and what is not (no "terminal (legacy)" tab, no rail reply box, no paper log; the
## flat look keeps its chat and its tab), each terminal row as its item (an AI row with its
## name and mood, a reply, a divider, a PATCH card with its tags, a HOTFIX slip, the build
## log's two rows, the thinking dots), the play gate (the pill, the ghost, typing, focus), an
## ask answered from the pills or from an option, wrapping, scroll-back, and reduce flashing.
## Hosts here are tool hosts (never live, no window change).

const S4 := &"s1_04_level"
const S8 := &"s2_02_day_one"
const TEST_LOG := "user://m48_6c_test/t.jsonl"
const WINDOWS: Array[Vector2] = [Vector2(1600, 900), Vector2(1920, 1080), Vector2(1280, 720), Vector2(2560, 1440)]
const LONG := "This is a rather long line that the AI says in one breath, with a_very_long_unbroken_identifier_that_no_row_can_hold_whole in it."

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
	for e in get_errors():   # the look's own known engine note (test_pixel_skin)
		if e.contains_text("Camera2D overridden to physics process mode"):
			e.handled = true
	assert_not_null(h.rail, "the frame is built on the look's ui group")
	assert_true(h.rail is CabinetFrame)
	h.rail.refresh()
	h.relayout(Vector2(1600, 900))
	RunState.set_pause(&"m48_6c_test", true)   # no line from the running game lands between the asserts
	return h.rail as CabinetFrame


func _click(view: Control, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	view._gui_input(e)


func _of_kind(view: Control, kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it: Dictionary in view.lay():
		if it.kind == kind:
			out.append(it)
	return out


# --- The column ----------------------------------------------------------------------------------

func test_the_chat_parts_stack_in_the_column_without_overlap() -> void:
	for win in WINDOWS:
		var l := CabinetLayout.layout_for(win)
		var chat: Rect2 = l.chat
		for rows in [0, 1, 2, 3]:
			var p := CabinetLayout.chat_parts(chat, float(l.art), rows)
			var order: Array[String] = ["header", "log", "messages", "pills", "input"]
			for i in order.size():
				var r: Rect2 = p[order[i]]
				assert_true(chat.encloses(r), "%s, %d pill rows: %s inside the chat" % [win, rows, order[i]])
				if i > 0:
					assert_gte(r.position.y, (p[order[i - 1]] as Rect2).end.y - 0.01,
							"%s, %d pill rows: %s under %s" % [win, rows, order[i], order[i - 1]])
			assert_gt((p.messages as Rect2).size.y, 200.0 * float(l.s), "%s: the messages keep most of the column" % win)
			assert_eq((p.pills as Rect2).size.y > 0.0, rows > 0, "%s: a pills row only with pills" % win)
			assert_eq((p.log as Rect2).position.y, (p.header as Rect2).end.y, "%s: the log right under the header" % win)
		assert_eq(l.terminal, CabinetLayout.chat_parts(chat, float(l.art), 0).messages, "%s: the terminal's rect is the messages area" % win)
		assert_false(l.has("reply"), "%s: no reply box in the layout" % win)
		assert_eq(int(l.font) % 11, 0, "%s: the chat's text on the pixel font's grid" % win)


func test_the_chat_fills_the_column_and_the_rail_chat_is_not_built() -> void:
	Skins.use(null)
	var h := await _hosted(S8, &"path_arsenal")
	var t := h.terminal
	# The flat look keeps the dev-chat and its legacy tab.
	var tab := t.chat.find_child("LegacyTab", true, false) as Control
	assert_not_null(tab)
	assert_true(tab.is_visible_in_tree(), "flat look: the terminal (legacy) tab stays")
	assert_null(h.rail)
	var before := t.rows()
	var cab := _pixel(h)
	await wait_process_frames(2)
	var view: Control = cab.chat_view
	assert_not_null(view, "the cabinet builds its chat")
	assert_eq(Rect2(view.position, view.size), h.layout.chat as Rect2, "it fills the chat column")
	assert_false(tab.is_visible_in_tree(), "no terminal (legacy) tab in the cabinet")
	assert_false(t.chat.visible, "nor the flat dev-chat")
	assert_null(cab.reply, "the rail's reply box is not built")
	assert_null(cab.chat_layer, "nor the paper log's layer")
	for c in cab.get_children():
		assert_ne(c.get_script(), RailFrame.Reply, "no reply box node in the cabinet")
	assert_eq(t.dresser, cab.chat)
	assert_true(cab.chat.draws_rows())
	assert_false(t._scroll.visible, "the terminal's own rows are not drawn (the chat draws them)")
	assert_eq(t.mouse_filter, Control.MOUSE_FILTER_IGNORE, "clicks reach the chat under the terminal")
	assert_eq(t.rows(), before, "the same rows")
	assert_eq(t.input_row().get_parent(), view, "the input sits in the chat's input line")
	# The parts on screen: stacked, the messages control on the messages rect, the input row
	# inside the input line, left of the send key.
	var p: Dictionary = view.parts()
	assert_eq(Rect2(view.messages.position, view.messages.size), p.messages as Rect2)
	var row := t.input_row()
	assert_true((p.input as Rect2).encloses(Rect2(row.position, row.size)), "the input row in the input line")
	assert_lte(row.position.x + row.size.x, (view.send_rect() as Rect2).position.x, "left of the send key")
	assert_true((p.input as Rect2).encloses(view.send_rect()))
	assert_true((p.header as Rect2).encloses(view.avatar_rect()), "the AI's body box in the header")
	assert_not_null(view.avatar.body, "the AI's small body")
	assert_eq(t.chat_input.placeholder_text, "Talk to %s..." % t.header_name())
	# It draws (frame, header, log, messages, pills, input) without an engine error.
	t.say_row("hello", &"happy")
	t.finish()
	view.queue_redraw()
	await wait_process_frames(3)
	# The look off: the flat chat, its tab and its input are back as they were.
	Skins.use(null)
	assert_true(tab.is_visible_in_tree(), "the tab back with the flat look")
	assert_eq(t.input_row().get_parent(), t.chat.input_slot)
	assert_eq(t.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_null(t.dresser)


# --- Rows as items -------------------------------------------------------------------------------

func test_each_row_kind_is_its_item() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var cab := _pixel(h)
	var view: Control = cab.chat_view
	var t := h.terminal
	t.sys("--- session 8 · Day one · v0.8.0 ---")
	t.say_row("Cards come in packs now.", &"proud")
	t.say_row("Six kills, one pack.", &"proud")
	t.cmd("patch apply v0.8.2 --hot")
	t.notes({"Added": ["Packs stack"], "Changed": ["F opens all of them"], "Fixed": ["Cards fusing sideways"]})
	t.you_said("nice. keep going")
	cab.mark_nerf("$ nerf minigun", "Balance: Minigun 30 > 15 shots/s.")
	t.cmd("nerf minigun", "ok")
	t.finish()
	cab.chat.step()
	var items: Array[Dictionary] = view.items()
	var kinds: Array[StringName] = view.kinds()
	assert_eq(kinds, [&"divider", &"ai", &"ai", &"patch", &"you", &"hotfix"] as Array[StringName], "one item per message")
	assert_eq(String(items[0].text), "session 8 · Day one · v0.8.0", "a divider without its dashes")
	assert_eq(String(items[1].text), "Cards come in packs now.")
	assert_eq(String(items[1].who), t.speaker, "the first bubble of a run names the AI")
	assert_eq(String(items[1].mood), "proud", "and its mood")
	assert_eq(String(items[2].who), "", "the next bubble of the run has no second name row")
	assert_eq(String(items[3].version), "v0.8.2")
	var card_rows: Array[String] = []
	for pair: Array in items[3].rows:
		card_rows.append("%s|%s" % [pair[0], pair[1]])
	assert_eq(card_rows, ["Added|Packs stack", "Changed|F opens all of them", "Fixed|Cards fusing sideways"] as Array[String],
			"the patch card's rows, tagged")
	assert_eq(String(items[4].text), "nice. keep going", "the player's reply")
	assert_eq(String(items[5].label), CabinetFrame.hotfix_label(cab.marquee_version(), 1), "the hotfix slip's version")
	assert_eq(String(items[5].text), "Balance: Minigun 30 > 15 shots/s.", "and its note")
	# The tags the card draws: ADD / CHANGE / FIX.
	var patch: Dictionary = _of_kind(view, &"patch")[0]
	var tags: Array[String] = []
	for e: Dictionary in patch.entries:
		tags.append(String(e.tag[1]))
	assert_eq(tags, ["ADD", "CHANGE", "FIX"] as Array[String])
	# The build log: the last two `$` rows, without the sigil.
	assert_eq(view.log_rows(), ["patch apply v0.8.2 --hot", "nerf minigun ... ok"] as Array[String])
	t.cmd("run s2_02_day_one")
	t.finish()
	assert_eq(view.log_rows(), ["nerf minigun ... ok", "run s2_02_day_one"] as Array[String], "only the last two")
	# A reply sits right, an AI bubble left, each inside the messages area.
	var w: float = view.messages.size.x
	var ai: Rect2 = _of_kind(view, &"ai")[0].box
	var you: Rect2 = _of_kind(view, &"you")[0].box
	assert_lt(ai.position.x, w * 0.25, "the AI's bubble on the left")
	assert_gt(you.end.x, w * 0.9, "the reply on the right")
	assert_lte(you.end.x, w)
	# The thinking dots show only while the AI thinks.
	t.think(30.0)
	await wait_process_frames(3)
	assert_eq(view.kinds().back(), &"think", "the dots while it thinks")
	t.finish()
	assert_false(&"think" in view.kinds(), "gone once it is done")
	# A row typing itself shows as many characters as its label.
	var l := t.say_row("Typing this one.", &"happy")
	assert_eq(int(view.items().back().chars), 0, "nothing typed yet")
	l.visible_characters = 6
	assert_eq(int(view.items().back().chars), 6)
	l.visible_characters = -1
	assert_eq(int(view.items().back().chars), -1, "whole")
	view.messages.queue_redraw()
	await wait_process_frames(2)


func test_a_changelog_row_reads_back_as_its_tag_and_text() -> void:
	var view: GDScript = load("res://ui/cabinet/cabinet_chat_view.gd")
	assert_eq(view.note_parts(TerminalPanel.note_text("Added", "Shooting")), ["Added", "Shooting"] as Array[String])
	assert_eq(view.note_parts(TerminalPanel.note_text("Changed", "F opens all")), ["Changed", "F opens all"] as Array[String])
	assert_eq(view.note_parts(TerminalPanel.note_text("Fixed", "A leak")), ["Fixed", "A leak"] as Array[String])
	assert_eq(view.head_parts("[14:02] blob@patchnotes (happy)"), ["blob", "happy"] as Array[String])
	assert_eq(view.head_parts("[14:02] ai@patchnotes"), ["ai", ""] as Array[String], "no face: no mood")


# --- The gate, the asks --------------------------------------------------------------------------

func test_the_play_gate_shows_the_pill_and_the_ghost() -> void:
	var h := await _hosted(S4)
	var cab := _pixel(h)
	var view: Control = cab.chat_view
	var t := h.terminal
	assert_eq(view.pill_labels().size(), 0, "no gate, no ask: no pill")
	assert_eq(view.pill_rows(), 0)
	var free_h: float = view.messages.size.y
	h.hold()   # a real gate (GameHost._open_gate)
	t.finish()
	await wait_process_frames(2)
	assert_true(h.gate and t.chat_input.gate)
	assert_eq(view.pill_labels(), ["play"] as Array[String], "one play pill")
	assert_eq(view.pill_rects().size(), 1)
	assert_true((view.parts().pills as Rect2).encloses(view.pill_rects()[0]), "in the pills row")
	assert_lt(view.messages.size.y, free_h, "the messages give the pills their row")
	assert_eq(t.chat_input.placeholder_text, ChatInput.GHOST, "the ghost `play` in the input")
	assert_true(t.chat_input.editable)
	assert_eq(t.input_row().modulate.a, 1.0, "the input shows")
	# The gate's line is an AI bubble in the chat.
	var gate_line := GameHost.gate_lines(RunState.session, true)[0].text
	var texts: Array[String] = []
	for it: Dictionary in view.items():
		if it.kind == &"ai":
			texts.append(String(it.text))
	assert_true(gate_line in texts, "the before_play line is in the chat")
	# Focus: the chat's input holds the keys (GameView lets none through to the game).
	t.chat_input.take_focus()
	assert_true(h.view.chat_has_focus())
	var key := InputEventKey.new()
	key.keycode = KEY_K
	key.pressed = true
	assert_false(h.view._propagate_input_event(key), "a key typed in the chat stays in the chat")
	# Typed text shows in the input and comes back as a reply bubble.
	t.chat_input.text = "hello"
	assert_eq(t.chat_input.text, "hello")
	t.chat_input.submit(true)
	t.finish()
	assert_true(h.held, "anything but play keeps the gate")
	var replies := _of_kind(view, &"you")
	assert_eq(String(replies.back().text), "hello", "what was typed is the player's bubble")
	# The pill gives play, and the gate's pill and ghost go.
	_click(view, (view.pill_rects()[0] as Rect2).get_center())
	assert_false(h.held, "the pill gives play")
	assert_eq(String(_of_kind(view, &"you").back().text), "play")
	assert_eq(view.pill_labels().size(), 0)
	assert_eq(t.chat_input.placeholder_text, "Talk to %s..." % t.header_name())
	assert_false(t.chat_input.has_focus(), "the keys are the game's again")


func test_a_fork_is_answered_from_the_pills() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var cab := _pixel(h)
	var view: Control = cab.chat_view
	var t := h.terminal
	var picked: Array[int] = []
	t.chosen.connect(func(i: int) -> void: picked.append(i))
	t.say_row("Which body do you want?", &"thinking")
	var options: Array[String] = ["tank  Something slow that soaks hits.", "blob  Soft. Round.", "cursor  A plain arrow."]
	t.ask(options)
	t.finish()
	cab.chat.step()
	await wait_process_frames(2)
	assert_eq(view.pill_labels(), ["[1] tank", "[2] blob", "[3] cursor"] as Array[String], "a short pill per option")
	var pills: Array[Rect2] = view.pill_rects()
	assert_eq(pills.size(), 3)
	var area: Rect2 = view.parts().pills
	for i in pills.size():
		assert_true(area.encloses(pills[i]), "pill %d in the pills area" % i)
		for j in i:
			assert_false(pills[i].intersects(pills[j]), "pills %d / %d apart" % [i, j])
	# The options in full are in the messages (a pill is never the only place a description shows).
	var opts := _of_kind(view, &"option")
	assert_eq(opts.size(), 3)
	assert_eq(String(opts[1].head), "[2] blob")
	assert_eq(String(opts[1].text), "Soft. Round.")
	assert_eq(_hint(view), "press 1 2 3", "the input line names the keys")
	_click(view, pills[1].get_center())
	assert_eq(picked, [1] as Array[int], "a click on a pill chooses")
	# A click on an option's card chooses it too.
	view.messages.queue_redraw()
	await wait_process_frames(2)
	var card: Rect2 = _of_kind(view, &"option")[2].box
	_click(view, view.messages.position + Vector2(0, view.content_y()) + card.get_center())
	assert_eq(picked, [1, 2] as Array[int], "a click on an option chooses")
	t.answer("2")
	cab.chat.step()
	assert_eq(view.pill_labels().size(), 0, "answered: the pills go")
	assert_eq(_of_kind(view, &"option").size(), 0, "and the options")
	assert_eq(String(_of_kind(view, &"you").back().text), "blob", "the reply names the choice")
	# The death ask: plain choices are pills only.
	t.say_row("Want another go, or should I just patch it?", &"sad")
	t.ask(["again", "move on (I'll take this one)"] as Array[String])
	t.finish()
	cab.chat.step()
	assert_eq(view.pill_labels(), ["[1] again", "[2] move on (I'll take this one)"] as Array[String])
	assert_eq(_of_kind(view, &"option").size(), 0, "no description, no card")
	assert_true(view.state().prompt)
	_click(view, (view.pill_rects()[0] as Rect2).get_center())
	assert_eq(picked.back(), 0)
	t.answer("1")
	assert_eq(String(_of_kind(view, &"you").back().text), "again")


func _hint(view: Control) -> String:
	return RailFrame.Reply.well_hint(view.state())


# --- Wrapping, scroll-back, reduce flashing ------------------------------------------------------

func test_long_lines_wrap_inside_their_bubble_at_every_window() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var cab := _pixel(h)
	var view: Control = cab.chat_view
	var t := h.terminal
	t.say_row(LONG, &"happy")
	t.you_said(LONG)
	t.cmd("patch apply v0.9.0")
	t.notes({"Added": [LONG], "Fixed": ["Short"]})
	cab.mark_nerf("$ nerf", "Balance: " + LONG)
	t.cmd("nerf", "ok")
	t.sys("--- " + LONG + " ---")
	t.ask(["tank  " + LONG, "blob  Soft."] as Array[String])
	t.finish()
	cab.chat.step()
	for win: Vector2 in [Vector2(1600, 900), Vector2(1920, 1080), Vector2(1280, 720)]:
		h.relayout(win)
		await wait_process_frames(2)
		var a: float = cab.art()
		var w: float = view.messages.size.x
		var last_end := 0.0
		var seen := {}
		for it: Dictionary in view.lay():
			seen[it.kind] = true
			var slot: Rect2 = it.rect
			assert_gte(slot.position.y, last_end, "%s: %s under the row before it" % [win, it.kind])
			last_end = slot.end.y
			if it.has("box"):
				var box: Rect2 = it.box
				assert_true(box.position.x >= 0.0 and box.end.x <= w, "%s: the %s box inside the messages" % [win, it.kind])
				assert_true(box.position.y >= slot.position.y - 0.01 and box.end.y <= slot.end.y + 0.01,
						"%s: the %s box inside its slot" % [win, it.kind])
			if it.has("lines"):
				var room := (it.box as Rect2).size.x - 2.0 * 4.0 * a if it.has("box") else w
				var lines: PackedStringArray = it.lines
				for i in lines.size():
					var bold: bool = it.kind == &"option" and i < int(it.get("head_rows", 0))
					assert_lte(view.text_w(lines[i], bold), room + 0.5, "%s: a %s row fits its box: '%s'" % [win, it.kind, lines[i]])
				if it.kind in [&"ai", &"you", &"hotfix"]:
					assert_gt(lines.size(), 2, "%s: the long %s line wraps" % [win, it.kind])
					assert_gte((it.box as Rect2).size.y, lines.size() * 7.0 * a, "%s: the %s box holds every row" % [win, it.kind])
			if it.kind == &"patch":
				var box: Rect2 = it.box
				for e: Dictionary in it.entries:
					for line: String in e.lines:
						assert_lte(float(e.x) + view.text_w(line), box.size.x - 2.0 * a, "%s: a patch row fits the card" % win)
					assert_lte(float(e.y) + (e.lines as PackedStringArray).size() * 7.0 * a, box.size.y, "%s: inside the card" % win)
		for kind: StringName in [&"ai", &"you", &"patch", &"hotfix", &"divider", &"option"]:
			assert_true(seen.has(kind), "%s: a %s row is laid out" % [win, kind])
		# The pills: a long name is cut to the row, never past the column.
		for r: Rect2 in view.pill_rects():
			assert_true((view.parts().pills as Rect2).grow(0.5).encloses(r), "%s: a pill inside the pills area" % win)
		view.queue_redraw()
		view.messages.queue_redraw()
		await wait_process_frames(2)


func test_the_wheel_scrolls_back_and_a_new_row_snaps_to_the_end() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var cab := _pixel(h)
	var view: Control = cab.chat_view
	var t := h.terminal
	for i in 30:
		t.say_row("Line number %d of a long talk." % i, &"happy" if i % 2 == 0 else &"proud")
	t.finish()
	await wait_process_frames(3)
	assert_gt(view.max_scroll(), 0.0, "more rows than the area holds")
	assert_eq(view.scroll, 0.0, "at the newest row")
	var newest: float = view.content_y() + view.total_height()
	assert_almost_eq(newest, view.messages.size.y, 1.0, "the newest row ends at the area's bottom")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = (view.messages.position + view.messages.size * 0.5)
	view._gui_input(wheel)
	assert_gt(view.scroll, 0.0, "the wheel scrolls back")
	var back: float = view.scroll
	await wait_process_frames(2)
	assert_eq(view.scroll, back, "and stays there while nothing new is said")
	for i in 200:
		view._gui_input(wheel)
	assert_eq(view.scroll, view.max_scroll(), "never past the oldest row")
	assert_almost_eq(view.content_y(), 0.0, 1.0, "the oldest row at the top")
	t.say_row("Something new.", &"happy")
	t.finish()
	await wait_process_frames(3)
	assert_eq(view.scroll, 0.0, "a new row brings the chat back to the end")


func test_reduce_flashing_stills_the_dots_and_the_hop() -> void:
	var h := await _hosted(S8, &"path_arsenal")
	var cab := _pixel(h)
	var view: Control = cab.chat_view
	var t := h.terminal
	t.say_row("Already here.", &"happy")
	t.finish()
	await wait_process_frames(2)
	var old: Dictionary = view.lay().back()
	assert_false(view.popping(old.id), "a row laid out a while ago does not hop")
	t.say_row("New one.", &"proud")
	t.finish()
	var fresh: Dictionary = view.lay().back()
	assert_true(view.popping(fresh.id), "a new row hops")
	SaveGame.set_setting("reduce_flashing", true)
	assert_false(view.popping(fresh.id), "not under reduce flashing")
	for i in 3:
		assert_true(view._blink(0.7), "the status dot is steady")
		OS.delay_msec(250)
	t.think(30.0)
	await wait_process_frames(3)
	assert_eq(view.kinds().back(), &"think")
	view.messages.queue_redraw()   # the dots draw (all lit, still)
	await wait_process_frames(2)
	t.finish()
	SaveGame.set_setting("reduce_flashing", false)
	OS.delay_msec(int(view.POP_S * 1000.0) + 50)
	assert_false(view.popping(fresh.id), "the hop is over")


func test_the_chat_scripts_are_presentation_only() -> void:
	for path: String in ["res://ui/cabinet/cabinet_chat.gd", "res://ui/cabinet/cabinet_chat_view.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_ne(src, "", path)
		for word: String in ["gameplay_rng", "director_rng", "loot_rng", "pick_rng", "randf", "randi", "Tuning.", "RunState.rules",
				"WorldRules", "Engine.time_scale"]:
			assert_false(src.contains(word), "%s reads no %s" % [path, word])
		assert_false(src.contains("Color(\"") or src.contains("Color.html"), "%s: colours come from the art tables" % path)
