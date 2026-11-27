extends GutTest
## M51b (title mockup v2, concept B): the version odometer title. The boot roll ticks through
## the save's real versions and modules and lands on its version; each card rolls the wheels to
## where it leads (Continue "?", New game v0.0.0, Replay an old build, Options / Quit stay);
## the mascot walks to the wheel; reduce flashing: no roll, no spin, no sparks.
##
## Scratch saves only (user://m51b_test/); the fixtures are never written.

const DIR := "user://m51b_test/"
const TEST_PATH := DIR + "save.json"
const OWNER_COPY := DIR + "owner.json"
const OWNER := "res://tests/gut/save_m43_owner_shape.json"   ## v0.8.0, S0..S7 done
const S8 := &"s2_02_day_one"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_delete_files()
	StartScreen.save_live = false
	StartScreen.legacy_loop = false
	CampaignDB.jumped = false


func after_each() -> void:
	CampaignDB.jumped = false
	CampaignDB.active = false
	Skins.use_named(&"off")
	RunState.clear_pauses()
	SaveGame.go_inert()
	_delete_files()


func _delete_files() -> void:
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)


func _owner_live(reduce := false) -> void:
	var f := FileAccess.open(OWNER_COPY, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(OWNER))
	f.close()
	SaveGame.go_live(OWNER_COPY)
	Settings.set_value("front_door_seen", true)
	SaveGame.set_setting("reduce_flashing", reduce)


func _title() -> TitleScreen:
	var screen: StartScreen = load("res://ui/start_screen.tscn").instantiate()
	add_child_autofree(screen)
	await wait_process_frames(2)
	assert_not_null(screen.title, "the title (S7 on)")
	return screen.title


func _drive(title: TitleScreen, seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		title._process(1.0 / 60.0)


func test_the_history_is_the_campaigns_real_versions_and_modules() -> void:
	var done: Array = []
	var expect: Array = [[[0, 0, 0], ""]]
	var v := GameVersion.make(0, 0, 0)
	for i in CampaignDB.index_of(&"s2_01_tryout") + 1:
		var s := CampaignDB.session(i)
		done.append(String(s.id))
		v.bump(s.bump)
		expect.append([v.to_array(), (String(s.notes[0]) if not s.notes.is_empty() else s.title).trim_suffix(".")])
	var h := TitleOdometer.version_history(done, GameVersion.make(0, 8, 0))
	assert_eq(h.map(func(e: Dictionary) -> Array: return [e.v, e.module]), expect)
	assert_eq(h[1].module, "Movement", "S0 shipped movement")
	assert_eq(h[2].module, "Enemies")
	assert_eq(h.back().v, [0, 8, 0])
	assert_eq(h.back().module, "The shooter, three ways", "S7's first note")
	# A save past the walk (a dev-session patch step) still lands on its own version.
	var extra := TitleOdometer.version_history(done, GameVersion.make(0, 8, 2))
	assert_eq(extra.back().v, [0, 8, 2])
	assert_eq(extra.size(), h.size() + 1)
	assert_eq(TitleOdometer.start_version(S8).to_array(), [0, 8, 0], "S8 started on v0.8.0")


func test_the_boot_rolls_through_the_modules_and_lands_on_the_saves_version() -> void:
	_owner_live()
	var title := await _title()
	var odo := title.odometer
	assert_true(odo.booting())
	assert_eq(odo.history.back().v, SaveGame.version().to_array())
	var seen := {}
	var landed_at := -1.0
	while odo.booting():
		title._process(1.0 / 60.0)
		seen[odo.readout()[1]] = true
		if odo.has_landed() and landed_at < 0.0:
			landed_at = odo.t
		if odo.booting() and odo.has_landed() and odo.t > odo.land_at() + 1.0:
			assert_eq(odo.shown(), "v0.8.0", "the wheels stand on the save's version")
	assert_true(seen.has(TitleOdometer.REWINDING))
	for e: Dictionary in odo.history.slice(1):
		assert_true(seen.has(TitleOdometer.SHIPPED % e.module), "names %s" % e.module)
	assert_almost_eq(landed_at, odo.land_at(), 0.02)
	assert_eq(title.mascot_text(), Line.parse(TitleScreen.FOCUS_LINES[&"continue"]).text,
			"then Continue (focused) speaks")


func test_landing_thunks_with_sparks_and_the_mascot_drops_in() -> void:
	_owner_live()
	var title := await _title()
	var odo := title.odometer
	assert_lt(title.mascot_at().y, 0.0, "the mascot waits above the screen")
	_drive(title, odo.land_at() - odo.t + 0.2)
	assert_true(odo.sparks_on(), "sparks on the landing")
	assert_eq(title.mascot_text(), Line.parse(TitleScreen.LANDED_LINE).text)
	_drive(title, 0.4)
	assert_gt(title.mascot_at().y, 0.0, "on the housing")
	assert_lt(title.mascot_at().y, odo.housing_rect().position.y)


func test_each_card_rolls_the_wheels_to_where_it_leads() -> void:
	SaveGame.go_live(TEST_PATH, true)
	for i in CampaignDB.index_of(S8) + 1:
		CampaignDB.complete(CampaignDB.session(i))
	Settings.set_value("front_door_seen", true)
	var title := await _title()
	var odo := title.odometer
	_drive(title, odo.boot_end() + 0.1)
	assert_false(odo.booting())
	var cur := SaveGame.version().to_array()
	assert_eq(cur, [0, 8, 1])
	assert_eq(title.menu_items().size(), 5)
	title.continue_button.grab_focus()
	_drive(title, 1.0)
	assert_eq(odo.target(), [0, 8, TitleOdometer.SPIN], "Continue: the patch wheel as ?")
	assert_eq(odo.shown(), "v0.8.?")
	var before := odo.wheels[2]
	_drive(title, 0.5)
	assert_ne(odo.wheels[2], before, "it spins")
	assert_eq(odo.readout()[0], "next: v0.8.?")
	title.new_button.grab_focus()
	assert_eq(title.mascot_text(), Line.parse(TitleScreen.FOCUS_LINES[&"new"]).text)
	_drive(title, 2.0)
	assert_eq(odo.shown(), "v0.0.0", "New game rolls back to v0.0.0")
	assert_eq(odo.readout()[0], "roll back to v0.0.0")
	assert_almost_eq(title.mascot_at().x, odo.mascot_x(TitleOdometer.NEW), 1.0, "the mascot walked to the minor wheel")
	title.replay_button.grab_focus()
	_drive(title, 2.0)
	assert_eq(odo.shown(), "v0.8.0", "Replay: the build Day one started on")
	assert_ne(odo.target(), cur, "an old build")
	for b: Button in [title.options_button, title.quit_button]:
		b.grab_focus()
		_drive(title, 2.0)
		assert_eq(odo.shown(), "v0.8.1", "%s keeps the version" % b.text)
	assert_eq(odo.readout()[0], "saved at v0.8.1")
	var subs := title.cards.map(func(c: TitleCard) -> String: return c.sub)
	assert_eq(subs, ["> v0.8.?", "> v0.0.0", "> v0.8.0", "v0.8.1 tune", "keep v0.8.1"])


func test_the_new_game_confirm_still_asks_and_keeps_the_red_roll() -> void:
	_owner_live()
	var title := await _title()
	title.new_button.grab_focus()
	title.confirm_new()
	assert_eq(title.stack.top(), title.confirm_menu)
	assert_eq(title.odometer.target(), [0, 0, 0])
	assert_false(title.odometer.readout_on, "the confirm replaces the readout")
	title.confirm_no.pressed.emit()
	assert_true(title.odometer.readout_on)


func test_reduce_flashing_no_roll_no_spin_no_sparks() -> void:
	_owner_live(true)
	var title := await _title()
	var odo := title.odometer
	assert_false(odo.booting(), "no boot roll")
	assert_eq(odo.wheels.slice(0, 2), [0.0, 8.0], "the wheels stand on the version")
	assert_eq(odo.readout()[0], "next: v0.8.?", "Continue (focused) leads to the next patch")
	title.continue_button.grab_focus()
	var before := odo.wheels.duplicate()
	_drive(title, 1.0)
	assert_eq(odo.wheels, before, "Continue's ? does not spin")
	title.new_button.grab_focus()
	title._process(1.0 / 60.0)
	assert_eq(odo.shown(), "v0.0.0", "a snap, not a roll")
	_drive(title, 2.0)
	assert_eq(odo.spark_frames, 0)
	assert_false(odo.sparks_on())
	assert_eq(odo.max_speed, 0.0, "nothing rolled")
