extends GutTest
## PLAN v8 M38: the mascot's bodies, its speech queue, fork_mascot and its telemetry.

const TEST_PATH := "user://save_mascot_test/save.json"


func before_each() -> void:
	SaveGame.go_live(TEST_PATH, true)


func after_each() -> void:
	SaveGame.go_inert()
	CampaignDB.active = false
	RunState.session = null


func _line(text: String, expression := &"idle") -> Line:
	return Line.make(text, expression)


func _mascot(face := true, body := &"blob") -> Mascot:
	var m := Mascot.new()
	m.setup(face, body)
	add_child_autofree(m)
	m.set_process(false)   # the test steps it
	return m


# --- Bodies -----------------------------------------------------------------------

func test_every_body_draws_every_expression() -> void:
	for id in MascotBody.IDS + [MascotBody.CARET]:
		var b := MascotBody.make(id)
		b.frozen = true
		add_child_autofree(b)
		assert_eq(b.id, id)
		for e in Line.EXPRESSIONS:
			b.set_expression(e)
			assert_eq(b.expression, e)
			b.advance(0.3)
			b.say_start()
			b.advance(0.2)
			b.say_end()
		b.point_at(b.position + Vector2(100, 0), 1.0)
		assert_true(b.pointing())
		b.glitch(0.5)
		assert_true(b.glitching())
		b.advance(1.1)
		assert_false(b.pointing(), "a point lasts its seconds")
		assert_false(b.glitching())
	await wait_process_frames(2)   # the draws ran without an error


func test_an_unknown_body_or_expression_falls_back() -> void:
	var b := MascotBody.make(&"teapot")
	add_child_autofree(b)
	assert_eq(b.id, MascotBody.DEFAULT)
	b.set_expression(&"smug")
	assert_eq(b.expression, &"idle")


func test_the_bodies_are_the_mascot_changes_bodies() -> void:
	assert_eq(MascotBody.IDS, Change.MASCOTS)
	for id in Change.MASCOTS:
		var c := ChangeDB.get_change(StringName("mascot_" + id))
		assert_not_null(c, "a change per body")
		assert_eq(c.kind, &"mascot")
		assert_eq(c.take.id, id)
		assert_eq(ChangeDB.problems(c), [] as Array[String])


# --- M51a: the creatures ------------------------------------------------------------

const FACE_LETTERS := "EGRC."


## Each pickable body is a creature and draws every mood the game uses, in the flat look
## and the pixel look, still, talking, blinking and pointing.
func test_each_creature_draws_every_mood_in_both_looks() -> void:
	for id in Change.MASCOTS:
		for px: bool in [false, true]:
			var b := MascotBody.make(id) as CreatureBody
			assert_not_null(b, "%s is a creature" % id)
			b.frozen = true
			b.pixel = px
			b.scale = Vector2.ONE * 0.373
			add_child_autofree(b)
			for e in Line.EXPRESSIONS:
				b.set_expression(e)
				assert_true(CreatureBody.FACES.has(e), "%s has a face" % e)
				for step: float in [0.0, 0.5, 2.25]:
					b.advance(step)
					var rows := b.face_grid()
					assert_eq(rows.size(), 6)
					for r: String in rows:
						assert_eq(r.length(), 10, "%s %s: %s" % [id, e, r])
						for ch in r:
							assert_true(ch in FACE_LETTERS, "%s: %s" % [e, ch])
					assert_gt(b.flat_face().size(), 2, "%s %s: a flat face" % [id, e])
				b.say_start()
				b.advance(0.07)
				b.say_end()
			b.point_at(b.position + Vector2(-80, 40), 1.0)
			b.advance(0.1)
			for r: String in b.grid():
				assert_eq(r.length(), (b.grid()[0] as String).length(), "%s: one width" % id)
			await wait_process_frames(1)   # the draws ran without an error


## The eight moods have eight different faces, in the grids and in the flat look.
func test_the_faces_differ() -> void:
	assert_eq(CreatureBody.FACES.size(), Line.EXPRESSIONS.size())
	var b := MascotBody.make(&"blob") as CreatureBody
	b.frozen = true
	add_child_autofree(b)
	var grids := {}
	var flats := {}
	for e in Line.EXPRESSIONS:
		b.set_expression(e)
		b.t = 1.0   # eyes open (not a blink), mouth shut
		assert_false(b.blinking())
		grids["|".join(PackedStringArray(b.face_grid()))] = e
		flats[var_to_str(b.flat_face())] = e
	assert_eq(grids.size(), Line.EXPRESSIONS.size(), "every grid face is its own")
	assert_eq(flats.size(), Line.EXPRESSIONS.size(), "every flat face is its own")
	b.set_expression(&"idle")
	var open := b.face_grid()
	b.t = 2.25   # fmod(2.25 + 0.7, 2.9) < 0.17: a blink
	assert_true(b.blinking())
	assert_ne(b.face_grid(), open, "a blink shuts the eyes")
	b.pixel = true
	b.say_start()
	b.t = 0.0
	assert_ne(b.face_grid(), open, "talking opens the mouth")


## The feet stay planted while the body moves; reduce_flashing drops the shivers.
func test_the_feet_stay_planted_and_gentle_drops_the_shakes() -> void:
	for px: bool in [false, true]:
		var b := MascotBody.make(&"cursor") as CreatureBody
		b.pixel = px
		add_child_autofree(b)
		b.set_expression(&"happy")
		var moved := false
		for i in 40:
			b.t = i * 0.05
			moved = moved or b.motion() != Vector2.ZERO
			assert_eq(b.pose()["offset"], Vector2.ZERO, "the feet never move with a mood")
		assert_true(moved, "happy hops")
		b.set_expression(&"worried")
		var shook := false
		for i in 40:
			b.t = i * 0.05
			shook = shook or b.motion().x != 0.0
		assert_true(shook, "worried shivers")
		b.gentle = true
		for e: StringName in [&"worried", &"panic"]:
			b.set_expression(e)
			for i in 40:
				b.t = i * 0.05
				assert_eq(b.motion().x, 0.0, "gentle: no shake (%s)" % e)


## The pixel look draws whole viewport pixels per cell, never larger than the flat cell, and
## a small holder gets finer pixels so a cell still covers one.
func test_the_pixel_look_draws_whole_cells() -> void:
	for s: float in [0.35, 0.62, 1.12, 3.0]:
		var b := MascotBody.make(&"window") as CreatureBody
		var v := PixelBodyView.wrap(b, s)
		add_child_autofree(v)
		await wait_process_frames(1)
		assert_true(b.pixel)
		var n := b._cu() * b.scale.x
		assert_almost_eq(n, roundf(n), 0.001, "scale %s: whole pixels" % s)
		assert_gte(roundf(n), 1.0)
		assert_lte(b._cu(), CreatureBody.C + 0.001)
		assert_eq(v.shown_rect().size, Vector2(v._vp.size) * v.pixel)
	var expect := {Mascot.SIZE / 100.0: PixelBodyView.PIXEL, 0.62: 2, 0.35: 1}
	for s: float in expect:
		var body := MascotBody.make(&"blob")
		var v := PixelBodyView.wrap(body, s)
		assert_eq(v.pixel, expect[s], "scale %s" % s)
		body.free()
		v.free()
	var caret := MascotBody.make(&"caret")
	var cv := PixelBodyView.wrap(caret, 0.35)
	assert_eq(cv.pixel, PixelBodyView.PIXEL, "no grid: 3x")
	caret.free()
	cv.free()


# --- The corner ---------------------------------------------------------------------

func test_before_the_face_it_is_a_caret() -> void:
	var m := _mascot(false, &"window")
	assert_eq(m.body.id, MascotBody.CARET)
	var w := _mascot(true, &"window")
	assert_eq(w.body.id, &"window")
	var d := _mascot(true, &"")
	assert_eq(d.body.id, MascotBody.DEFAULT, "no pick yet: the default body")


func test_a_line_is_typed_then_held_then_the_next_comes() -> void:
	var m := _mascot()
	m.say(_line("Hello there.", &"happy"))
	m.say(_line("Second."))
	assert_eq(m.current_text(), "Hello there.")
	assert_eq(m.body.expression, &"happy")
	assert_true(m.body.talking, "it talks while it types")
	m.step(12.0 / Mascot.TYPE_CPS + 0.01)
	assert_false(m.body.talking, "typed")
	m.step(SessionRunner.read_seconds("Hello there.") - 0.1)
	assert_eq(m.current_text(), "Hello there.", "still held")
	m.step(0.2)
	assert_eq(m.current_text(), "Second.")
	assert_eq(m.shown, ["Hello there.", "Second."])


func test_a_higher_priority_cuts_in_after_a_moment() -> void:
	var m := _mascot()
	m.say(_line("Just chatting about nothing much."), 1)
	m.say(_line("Watch out!", &"panic"), 3)
	assert_eq(m.current_text(), "Just chatting about nothing much.", "not in its first 0.4 s")
	m.step(Mascot.MIN_SHOWN)
	assert_eq(m.current_text(), "Watch out!")
	assert_eq(m.body.expression, &"panic")
	m.say(_line("Equal waits."), 3)
	m.say(_line("Lower waits more."), 1)
	m.say(_line("Higher, but it waits its turn."), 3)
	assert_eq(m.current_text(), "Watch out!", "equal priority waits")
	assert_eq(m.queued(), 3)


func test_silence_hides_it_and_drops_the_queue() -> void:
	var m := _mascot()
	m.say(_line("One."))
	m.say(_line("Two."))
	m.silence()
	assert_false(m.visible)
	assert_false(m.is_speaking())
	assert_eq(m.queued(), 0)


# --- fork_mascot --------------------------------------------------------------------

func test_fork_mascot_is_for_the_campaign_only() -> void:
	var f := ChangeDB.get_fork(&"fork_mascot")
	assert_not_null(f)
	assert_true(f.campaign)
	assert_eq(ChangeDB.fork_problems(f), [] as Array[String])
	assert_false(f in DevSession.ready_forks(), "the v6 dev session never offers it")
	assert_eq(CampaignDB.get_session(&"s1_02_enemies").fork, &"fork_mascot", "M47.6b: S2's pick")


func test_a_session_with_a_pick_logs_the_fork_and_the_mascot() -> void:
	var s := CampaignDB.get_session(&"s1_02_enemies")
	var pick := ChangeDB.get_change(&"mascot_window")
	var rec := CampaignDB.telemetry_record(s, {}, &"won", 0, &"next", "test", pick)
	assert_eq(rec.fork, {"id": "fork_mascot", "pick": "mascot_window", "shelved": ["mascot_cursor", "mascot_blob"]})
	assert_eq(rec.mascot, "window")
	assert_null(CampaignDB.telemetry_record(s, {}, &"won", 0, &"next").fork)


func test_completing_with_a_mascot_pick_sets_the_body() -> void:
	var s := CampaignDB.get_session(&"s1_02_enemies")
	CampaignDB.complete(s, ChangeDB.get_change(&"mascot_cursor"))
	assert_eq(SaveGame.mascot(), &"cursor")
	assert_true(SaveGame.has_shipped(&"mascot_cursor"))
	assert_eq(DebriefScreen.body_for(s), MascotBody.CARET, "S2 itself has no face")
	assert_eq(DebriefScreen.body_for(CampaignDB.get_session(&"s1_03_shooting")), &"cursor", "M47.6b: S3 has it")
	var with_face := SessionDef.new()
	with_face.face = true
	assert_eq(DebriefScreen.body_for(with_face), &"cursor")


func test_the_campaign_game_speaks_through_the_mascot() -> void:
	CampaignDB.active = true
	assert_true(CampaignDB.jump_to(&"s1_01_move"))
	var game: Main = load("res://main.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	assert_not_null(game.mascot)
	assert_eq(game.mascot.body.id, MascotBody.CARET)
	await wait_seconds(0.1)
	assert_eq(game.mascot.shown, ["there. it moves."], "the intro's first line is in the bubble")
