extends GutTest
## M47.3 (PLAN v9.1 1.16): Settings, additive in save schema 2, the audio buses and the
## settings' consumers. Every live save here is the scratch TEST_PATH.

const TEST_PATH := "user://m47_3_test/save.json"
const OWNER_FIXTURE := "res://tests/gut/save_m43_owner_shape.json"
const M42_FIXTURE := "res://tests/gut/save_m42_2_stage1_end.json"


func before_each() -> void:
	_delete_files()


func after_each() -> void:
	assert_ne(SaveGame.save_path if SaveGame.persist else "", SaveGame.DEFAULT_PATH,
			"no test may leave the real save live")
	SaveGame.go_inert()
	_delete_files()
	Settings.apply()


func _delete_files() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", "user://m47_3_test/save.bad.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _write(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_PATH.get_base_dir())
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _with_settings(extra: Dictionary) -> String:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(M42_FIXTURE))
	(d.settings as Dictionary).merge(extra, true)
	return JSON.stringify(d)


# --- Save schema 2, additive -----------------------------------------------------

func test_a_new_save_keeps_exactly_the_two_old_keys() -> void:
	assert_eq(SaveGame.new_state().settings, {"reduce_flashing": false, "asked": false},
			"sparse: a new key is written only once it is changed")


func test_m47_2_shaped_saves_load_without_quarantine_and_settings_unchanged() -> void:
	for path in [OWNER_FIXTURE, M42_FIXTURE]:
		var text := FileAccess.get_file_as_string(path)
		var raw: Dictionary = JSON.parse_string(text)
		_write(text)
		SaveGame.go_live(TEST_PATH)
		assert_eq(SaveGame.last_load, SaveGame.LOADED, path)
		var want := {"reduce_flashing": false, "asked": false}
		for k: String in want:
			if (raw.get("settings", {}) as Dictionary).has(k):
				want[k] = raw.settings[k]
		assert_eq(SaveGame.state().settings, want, path)
		assert_false(FileAccess.file_exists("user://m47_3_test/save.bad.json"), path)
		SaveGame.go_inert()


func test_a_wrong_new_key_reads_its_default_and_never_quarantines() -> void:
	var bad := {"vol_master": "loud", "vol_sfx": 3.0, "mute_unfocused": 1, "window_mode": 7,
			"vsync": "yes", "fps_cap": 75, "window_scale": 3.0, "shake": -0.5, "text_speed": 46,
			"key_hints": null, "chatter": [], "front_door_seen": "no"}
	_write(_with_settings(bad))
	SaveGame.go_live(TEST_PATH)
	assert_eq(SaveGame.last_load, SaveGame.LOADED)
	for key: String in bad:
		assert_false((SaveGame.state().settings as Dictionary).has(key), key + " dropped")
		assert_eq(Settings.get_value(key), Settings.default_of(key), key + " reads its default")


func test_an_old_key_of_the_wrong_type_still_quarantines() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(M42_FIXTURE))
	d.settings["reduce_flashing"] = 1
	assert_null(SaveGame.parse(d), "a non-bool reduce_flashing is still corrupt")
	_write(JSON.stringify(d))
	SaveGame.go_live(TEST_PATH)
	assert_eq(SaveGame.last_load, SaveGame.CORRUPT)


func test_unknown_settings_keys_are_still_dropped() -> void:
	_write(_with_settings({"volume_of_doom": 11}))
	SaveGame.go_live(TEST_PATH)
	assert_false((SaveGame.state().settings as Dictionary).has("volume_of_doom"))


func test_every_key_round_trips_through_write_and_load() -> void:
	SaveGame.go_live(TEST_PATH, true)
	var values := {"vol_master": 0.35, "vol_sfx": 0.0, "vol_ui": 0.5, "vol_voice": 1.0,
			"mute_unfocused": true, "window_mode": 2, "vsync": false, "fps_cap": 144,
			"window_scale": 1.5, "shake": 0.25, "text_speed": 0, "key_hints": false,
			"chatter": false, "front_door_seen": true}
	assert_eq(values.size(), Settings.SPEC.size(), "every SPEC key")
	for key: String in values:
		Settings.set_value(key, values[key])
	Settings.commit()
	var written: Dictionary = (SaveGame.state().settings as Dictionary).duplicate(true)
	SaveGame.go_inert()
	SaveGame.go_live(TEST_PATH)
	assert_eq(SaveGame.last_load, SaveGame.LOADED)
	for key: String in values:
		assert_eq(Settings.get_value(key), values[key], key)
	assert_eq(SaveGame.state().settings, written, "the written block round-trips equal")


func test_whole_json_floats_count_as_ints() -> void:
	assert_true(Settings.valid("fps_cap", 60.0))
	assert_false(Settings.valid("fps_cap", 60.5))
	assert_eq(Settings.parse({"fps_cap": 60.0}).fps_cap, 60)
	assert_typeof(Settings.parse({"fps_cap": 60.0}).fps_cap, TYPE_INT)


func test_set_value_emits_changed_and_never_writes() -> void:
	SaveGame.go_live(TEST_PATH, true)
	watch_signals(Settings.hub)
	Settings.set_value("shake", 0.5)
	assert_signal_emitted_with_parameters(Settings.hub, "changed", ["shake"])
	assert_false(FileAccess.file_exists(TEST_PATH), "set_value never writes; commit does")
	Settings.commit()
	assert_true(FileAccess.file_exists(TEST_PATH))


func test_an_invalid_value_is_refused() -> void:
	Settings.set_value("text_speed", 50)
	assert_eq(Settings.get_value("text_speed"), 45)


# --- Window and frame settings: not here -----------------------------------------

func test_window_settings_are_ignored_in_tools_and_headless() -> void:
	assert_true("-s" in OS.get_cmdline_args(), "GUT runs as a -s tool (--fixed-fps is not visible to scripts)")
	assert_false(Settings.window_applies())
	var max_fps := Engine.max_fps
	var mode := DisplayServer.window_get_mode()
	Settings.set_value("fps_cap", 30)
	Settings.set_value("window_mode", 1)
	Settings.apply()
	assert_eq(Engine.max_fps, max_fps, "fps_cap ignored")
	assert_eq(DisplayServer.window_get_mode(), mode, "window_mode ignored")


## M47.3 review 1: apply() runs on every go-live (Start, volume, fullscreen), so it must not
## re-apply an unchanged window_scale (that snapped a moved or resized window back to centre).
func test_window_scale_is_applied_once_not_on_every_apply() -> void:
	Settings.test_window_mode = DisplayServer.WINDOW_MODE_WINDOWED
	Settings._scale_applied = -1.0
	var before := Settings.scale_applies
	Settings.apply(true)
	assert_eq(Settings.scale_applies, before + 1, "boot applies the scale once")
	Settings.apply(true)
	Settings.apply(true)
	assert_eq(Settings.scale_applies, before + 1, "a later go-live leaves the window alone")
	Settings._apply_window("window_scale")
	assert_eq(Settings.scale_applies, before + 1, "an unchanged scale is not re-applied")
	Settings.set_value("window_scale", 1.5)
	Settings._apply_window("window_scale")
	assert_eq(Settings.scale_applies, before + 2, "a changed scale is applied")
	Settings.test_window_mode = -1
	Settings._scale_applied = -1.0


## M47.3 review 2: a scale picked while fullscreen (or borderless) lands when the window
## goes back to windowed, not only after a restart.
func test_window_scale_picked_in_fullscreen_lands_on_windowed() -> void:
	Settings._scale_applied = -1.0
	Settings.test_window_mode = DisplayServer.WINDOW_MODE_WINDOWED
	Settings._apply_window("window_scale")
	var before := Settings.scale_applies
	Settings.test_window_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	Settings.set_value("window_mode", 1)
	Settings.set_value("window_scale", 2.0)
	Settings._apply_window("window_scale")
	assert_eq(Settings.scale_applies, before, "no resize while fullscreen")
	Settings.set_value("window_mode", 0)
	Settings.test_window_mode = DisplayServer.WINDOW_MODE_WINDOWED
	Settings._apply_window("window_mode")
	assert_eq(Settings.scale_applies, before + 1, "the 2x scale lands on the way back to windowed")
	assert_eq(Settings._scale_applied, 2.0)
	Settings.test_window_mode = -1
	Settings._scale_applied = -1.0


# --- Buses ------------------------------------------------------------------------

func test_the_buses_exist_and_sounds_route_to_them() -> void:
	AudioBuses.ensure()
	AudioBuses.ensure()
	for bus: StringName in [&"Master", &"SFX", &"UI", &"Voice"]:
		assert_gte(AudioServer.get_bus_index(bus), 0, bus)
	var count := 0
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == "SFX":
			count += 1
	assert_eq(count, 1, "ensure() is idempotent")
	var sound := Sound.new()
	add_child_autofree(sound)
	for key: StringName in sound.streams:
		var p: AudioStreamPlayer = sound._players[key]
		var want := &"SFX"
		if key in [&"compile", &"glitch", &"edit_warn"]:
			want = &"Voice"
		elif key in [&"click", &"prompt", &"release_candidate", &"pack_tear", &"card_flip", &"card_slot", &"fuse_chime"]:
			want = &"UI"
		assert_eq(p.bus, want, String(key))
		assert_eq(p.volume_db, -6.0, String(key) + " stays at -6 dB")


func test_volumes_reach_the_buses() -> void:
	Settings.set_value("vol_sfx", 0.5)
	assert_almost_eq(AudioBuses.volume(&"SFX"), 0.5, 0.001)
	Settings.set_value("vol_ui", 0.0)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"UI")), "0 mutes")
	Settings.set_value("vol_master", 0.8)
	assert_almost_eq(AudioBuses.volume(&"Master"), 0.8, 0.001)


# --- Consumers --------------------------------------------------------------------

func test_shake_multiplier_defaults_to_today() -> void:
	assert_eq(Settings.shake_mult(), 1.0)
	SaveGame.state().settings.reduce_flashing = true
	assert_eq(Settings.shake_mult(), 0.5, "reduce flashing: today's half")
	Settings.set_value("shake", 0.3)
	assert_almost_eq(Settings.shake_mult(), 0.3, 0.0001, "below the cap: as set")
	SaveGame.state().settings.reduce_flashing = false
	Settings.set_value("shake", 0.0)
	assert_eq(Settings.shake_mult(), 0.0)


func test_text_speed_drives_the_mascot_typing() -> void:
	var m := Mascot.new()
	add_child_autofree(m)
	var line := Line.new()
	line.text = "x".repeat(90)
	m.say(line)
	m.step(1.0)
	assert_eq(m._label.visible_characters, 45, "45 cps by default")
	Settings.set_value("text_speed", 0)
	m.step(0.01)
	assert_eq(m._label.visible_characters, 90, "instant")


func test_chatter_off_drops_reactions_and_keeps_the_script() -> void:
	var m := Mascot.new()
	add_child_autofree(m)
	Settings.set_value("chatter", false)
	var r := Line.new()
	r.text = "a reaction"
	m.say(r, 1)
	assert_eq(m.shown.size(), 0, "priority 1 dropped")
	var s := Line.new()
	s.text = "the script"
	m.say(s, SessionRunner.PRIORITY)
	assert_eq(m.shown, ["the script"] as Array[String])


func test_key_hints_off_drops_the_pick_card_key() -> void:
	var offer := PickOffer.new()
	offer.cards.append({"id": &"shotgun", "rank": 1, "kind": &"new", "text": "Shotgun"})
	assert_eq(PickPanel.card_text(offer, 0, func(k: int) -> int: return k), "[1]  Shotgun")
	assert_eq(PickPanel.card_text(offer, 0, Callable(), false), "Shotgun")


func test_the_mascot_body_rereads_reduce_flashing_on_change() -> void:
	var m := Mascot.new()
	add_child_autofree(m)
	assert_false(m.body.gentle)
	Settings.set_value("reduce_flashing", true)
	assert_true(m.body.gentle)
	Settings.set_value("reduce_flashing", false)
	assert_false(m.body.gentle)
