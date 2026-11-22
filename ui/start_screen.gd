class_name StartScreen
extends Control
## First screen (PLAN 8): Start, a seed field, fullscreen and master volume, and the
## save (PLAN v5 1.5): its version line and "Reset save". The two settings act on the
## window and the audio server directly and last for the session; they are not saved.
##
## Opening this screen only reads the save (a snapshot, never a write or a rename) to
## show its line. Start and "Reset save" make it live (SaveGame.go_live), as v4 1.7
## has it: the save turns on when the screen starts a game. Nothing touches the save
## with --autostart (the export's smoke boot) or --inert-save (check.ps1's boot), or
## when a tool cleared save_live first (bot_runs.gd and run_hash.gd choose their own).
##
## A pending dev session (the game closed between a run's end and its session, PLAN v5
## 1.5) comes first: the screen says so, and Start opens that session; its "Play"
## starts the game.

const GAME_SCENE := "res://main.tscn"
const RESET_LABEL := "Reset save"
const RESET_ARMED := "Click again to erase the save"
const START := "Start"
const START_PENDING := "Dev session"

## Tools set this to false before instancing the screen.
static var save_live := true

var seed_field: LineEdit
var fullscreen: CheckButton
var volume: HSlider
var start_button: Button
var save_label: Label
var reset_button: Button
var dev_flow: DevSessionFlow
var _reset_armed := false


func _ready() -> void:
	if uses_real_save():
		SaveGame.use_snapshot(SaveGame.DEFAULT_PATH)
	print("[boot] Patch Notes %s, start screen, game %s, %s" % [Main.BUILD, SaveGame.version().label(),
			"real save" if uses_real_save() else "inert save"])
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(420, 0)
	column.add_theme_constant_override(&"separation", 16)
	center.add_child(column)

	var title := Label.new()
	title.text = "PATCH NOTES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 44)
	title.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.65))
	column.add_child(title)
	var sub := Label.new()
	sub.text = "prototype build %s" % Main.BUILD
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.5))
	column.add_child(sub)
	save_label = Label.new()
	save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_label.add_theme_font_size_override(&"font_size", 20)
	column.add_child(save_label)

	start_button = Button.new()
	start_button.text = START
	start_button.custom_minimum_size = Vector2(0, 54)
	start_button.add_theme_font_size_override(&"font_size", 24)
	start_button.pressed.connect(start)
	column.add_child(start_button)

	seed_field = LineEdit.new()
	seed_field.placeholder_text = "Seed (empty = random)"
	seed_field.text_submitted.connect(func(_t: String) -> void: start())
	column.add_child(_row("Seed", seed_field))

	fullscreen = CheckButton.new()
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.toggled.connect(set_fullscreen)
	column.add_child(_row("Fullscreen", fullscreen))

	volume = HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume.value_changed.connect(set_volume)
	column.add_child(_row("Volume", volume))

	reset_button = Button.new()
	reset_button.text = RESET_LABEL
	reset_button.pressed.connect(press_reset)
	column.add_child(reset_button)
	dev_flow = DevSessionFlow.new()
	dev_flow.name = "DevSession"
	add_child(dev_flow)
	dev_flow.play_requested.connect(_start_game)
	dev_flow.session_done.connect(_on_session_done)
	refresh_save()

	start_button.grab_focus.call_deferred()
	# "-- --autostart" skips this screen (release builds cannot be given a scene path).
	if "--autostart" in OS.get_cmdline_user_args():
		start.call_deferred()


func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


## Empty -> -1 (random). A number is used as is; any other text is hashed, so a
## word works as a seed too.
static func parse_seed(text: String) -> int:
	var t := text.strip_edges()
	if t == "":
		return -1
	if t.is_valid_int():
		return absi(t.to_int()) % 1000000000
	return absi(hash(t)) % 1000000


## "v0.1.2 · 4 runs", or why the save cannot be used. A pending session says so.
static func save_line() -> String:
	if SaveGame.read_only:
		return "Save from a newer build (read-only)"
	var runs := int(SaveGame.state().runs)
	var line := "%s · %d run%s" % [SaveGame.version().label(), runs, "" if runs == 1 else "s"]
	var answered := DevSession.answers().size()
	if answered > 0:   # PLAN v6 2: "· 2/3 forks"
		line += " · %d/%d forks" % [answered, ChangeDB.forks.size()]
	if session_pending():
		line += "\n" + DevSession.PENDING_LINE
	return line


## The save holds a run whose dev session never happened.
static func session_pending() -> bool:
	return not SaveGame.read_only and bool(SaveGame.state().pending_session)


## False for tools and smoke boots: the screen then leaves the save as it is.
static func uses_real_save() -> bool:
	var args := OS.get_cmdline_user_args()
	return save_live and not "--autostart" in args and not "--inert-save" in args


func refresh_save() -> void:
	save_label.text = save_line()
	reset_button.disabled = not ((uses_real_save() or SaveGame.persist) and SaveGame.can_reset())
	if reset_button.disabled:
		_reset_armed = false
	reset_button.text = RESET_ARMED if _reset_armed else RESET_LABEL
	start_button.text = START_PENDING if session_pending() else START


## Two clicks: the first arms, the second erases the save (a new v0.0.0 save, written).
func press_reset() -> void:
	if reset_button.disabled:
		return
	if not _reset_armed:
		_reset_armed = true
	else:
		_reset_armed = false
		_go_live()
		SaveGame.reset()
	refresh_save()


## The real save goes live here, unless a save is live already (a test's or a tool's
## scratch save stays the one in use).
func _go_live() -> void:
	if uses_real_save() and not SaveGame.persist:
		SaveGame.go_live()


## Start: the pending dev session first, if the (now live) save has one; else the game.
func start() -> void:
	if dev_flow.is_open():
		return
	_go_live()
	Main.next_seed = parse_seed(seed_field.text)
	if SaveGame.is_live() and session_pending():
		dev_flow.start(DevSession.plan(int(SaveGame.state().runs), {"pending": true}))
		return
	_start_game()


## A pending session is a session like any other: one telemetry line (PLAN v5 4.5).
func _on_session_done(session: DevSession) -> void:
	if SaveGame.is_live():
		Telemetry.append(session.telemetry_record(0))


func _start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func set_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(linear))
	AudioServer.set_bus_mute(0, linear <= 0.0)
