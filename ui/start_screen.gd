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
##
## PLAN v8 (section 2): the screen starts the campaign. Continue plays the save's next
## session, New game starts over (two clicks once a campaign exists; the settings stay),
## and "Reduce flashing" is asked once before the first session (1.9). The v6 run loop's
## screen above is kept behind --legacy-loop (and `legacy_loop`, for tools and tests).

const GAME_SCENE := "res://main.tscn"
const TITLE_SCENE := "res://ui/start_screen.tscn"
const RESET_LABEL := "Reset save"
const RESET_ARMED := "Click again to erase the save"
const START := "Start"
const START_PENDING := "Dev session"
const CONTINUE := "Continue"
const NEW_GAME := "New game"
const NEW_ARMED := "Click again: start over"
const FLASH_QUESTION := "Reduce flashing and screen shake?"
const OLD_SAVE_LINE := "Your prototype save (the old run loop) is kept aside."

## Tools set this to false before instancing the screen.
static var save_live := true
## The v6 run loop's screen instead of the campaign's (PLAN v8 1.2.7).
static var legacy_loop := "--legacy-loop" in OS.get_cmdline_user_args()

var seed_field: LineEdit
var fullscreen: CheckButton
var volume: HSlider
var start_button: Button
var save_label: Label
var reset_button: Button
var dev_flow: DevSessionFlow
var _reset_armed := false
# The campaign's screen (PLAN v8 2).
var continue_button: Button
var new_button: Button
var flashing: CheckButton
var flash_panel: Control
var _new_armed := false
## M47 (PLAN v9 2, D17): replay-as-path. The row shows once a done session's path is
## `fork:fork_path` (S8).
var replay_row: HBoxContainer
var replay_session: OptionButton
var replay_path: OptionButton
const REPLAY_FORK := &"fork_path"
var _after_question: Callable


func _ready() -> void:
	if uses_real_save():
		SaveGame.use_snapshot(SaveGame.DEFAULT_PATH)
	print("[boot] Patch Notes %s, start screen, game %s, %s, %s" % [Main.BUILD, SaveGame.version().label(),
			"real save" if uses_real_save() else "inert save", Main.answers_text()])
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

	if not legacy_loop:
		_build_campaign(column)
		return

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


# --- The campaign's screen (PLAN v8 2) -----------------------------------------------

func _build_campaign(column: VBoxContainer) -> void:
	SaveGame.end_replay()   # M47: the title after a replay restores the stored save mode
	continue_button = _big_button(CONTINUE, press_continue)
	column.add_child(continue_button)
	new_button = _big_button(NEW_GAME, press_new_game)
	column.add_child(new_button)

	flash_panel = VBoxContainer.new()
	flash_panel.add_theme_constant_override(&"separation", 10)
	flash_panel.visible = false
	var q := Label.new()
	q.text = FLASH_QUESTION
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.add_theme_font_size_override(&"font_size", 22)
	flash_panel.add_child(q)
	var answers := HBoxContainer.new()
	answers.alignment = BoxContainer.ALIGNMENT_CENTER
	answers.add_theme_constant_override(&"separation", 16)
	var yes := Button.new()
	yes.text = "Yes, reduce them"
	yes.pressed.connect(answer_flashing.bind(true))
	answers.add_child(yes)
	var no := Button.new()
	no.text = "No, keep them"
	no.pressed.connect(answer_flashing.bind(false))
	answers.add_child(no)
	flash_panel.add_child(answers)
	column.add_child(flash_panel)

	replay_row = HBoxContainer.new()
	replay_row.name = "ReplayRow"
	replay_row.alignment = BoxContainer.ALIGNMENT_CENTER
	replay_row.add_theme_constant_override(&"separation", 8)
	replay_session = OptionButton.new()
	replay_row.add_child(replay_session)
	replay_path = OptionButton.new()
	for c in _replay_changes():
		replay_path.add_item(String(c.take.title) if c.take != null else String(c.id))
		replay_path.set_item_metadata(replay_path.item_count - 1, c.id)
	replay_row.add_child(replay_path)
	var replay := Button.new()
	replay.text = "Replay"
	replay.pressed.connect(func() -> void: press_replay(_selected(replay_session), _selected(replay_path)))
	replay_row.add_child(replay)
	column.add_child(replay_row)

	seed_field = LineEdit.new()
	seed_field.placeholder_text = "Seed (empty = random)"
	column.add_child(_row("Seed", seed_field))
	flashing = CheckButton.new()
	flashing.toggled.connect(set_reduce_flashing)
	column.add_child(_row("Less flashing", flashing))
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
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(quit)
	refresh_campaign()
	(continue_button if continue_button.visible else new_button).grab_focus.call_deferred()
	if "--autostart" in OS.get_cmdline_user_args():
		start.call_deferred()


func _big_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_font_size_override(&"font_size", 24)
	b.pressed.connect(action)
	return b


## "Stage 1 · Session 2 · v0.2.0" (S0 is the first), "New campaign", or the end so far. A newer
## build's file and an old prototype save say so.
static func campaign_line() -> String:
	if SaveGame.read_only:
		return "Save from a newer build (read-only)"
	var line := ""
	if CampaignDB.is_done():
		line = "%s · to be continued" % SaveGame.version().label()
	elif CampaignDB.started():
		var s := CampaignDB.current()
		line = "Stage %d · Session %d · %s" % [s.stage, CampaignDB.current_index(),
				SaveGame.version().label()]
	else:
		line = "New campaign"
	if SaveGame.last_load == SaveGame.OLD:
		line += "\n" + OLD_SAVE_LINE
	return line


func refresh_campaign() -> void:
	save_label.text = campaign_line()
	continue_button.visible = CampaignDB.started() and (not CampaignDB.is_done() or CampaignDB.cooking() != null)
	continue_button.disabled = SaveGame.read_only
	new_button.disabled = SaveGame.read_only
	new_button.text = NEW_ARMED if _new_armed else NEW_GAME
	flashing.set_block_signals(true)
	flashing.button_pressed = bool(SaveGame.setting("reduce_flashing"))
	flashing.set_block_signals(false)
	_refresh_replay()


# --- Replay as path (M47, PLAN v9 2, D17) ----------------------------------------------

## The done sessions whose path is the path fork (S8), in campaign order.
static func replay_sessions() -> Array[SessionDef]:
	var out: Array[SessionDef] = []
	for s in CampaignDB.campaign.sessions:
		if s != null and String(s.path) == "fork:%s" % REPLAY_FORK and String(s.id) in (SaveGame.campaign().done as Array):
			out.append(s)
	return out


static func _replay_changes() -> Array[Change]:
	var f := ChangeDB.get_fork(REPLAY_FORK)
	return f.changes() if f != null else ([] as Array[Change])


func _refresh_replay() -> void:
	if replay_row == null:
		return
	var sessions := replay_sessions()
	replay_row.visible = not sessions.is_empty() and not SaveGame.read_only
	replay_session.clear()
	for s in sessions:
		replay_session.add_item(s.title)
		replay_session.set_item_metadata(replay_session.item_count - 1, s.id)


static func _selected(b: OptionButton) -> StringName:
	return StringName(b.get_item_metadata(b.selected)) if b.selected >= 0 else &""


## Plays session `id` again as path change `change_id`, on an in-memory copy of the save
## (never written; the title after it restores the save exactly).
func press_replay(id: StringName, change_id: StringName) -> bool:
	if id == &"" or change_id == &"" or SaveGame.read_only:
		return false
	_go_live()
	SaveGame.begin_replay(REPLAY_FORK, change_id)
	if not CampaignDB.jump_to(id):
		SaveGame.end_replay()
		return false
	_start_campaign()
	return true


func press_continue() -> void:
	if not continue_button.visible or continue_button.disabled:
		return
	_ask_then(_start_campaign)


## Starts over: two clicks once a campaign exists (the first arms). Settings stay.
func press_new_game() -> void:
	if new_button.disabled:
		return
	if CampaignDB.started() and not _new_armed:
		_new_armed = true
		refresh_campaign()
		return
	_new_armed = false
	_ask_then(_new_campaign)


func _new_campaign() -> void:
	_go_live()
	var settings: Dictionary = (SaveGame.state().settings as Dictionary).duplicate()
	SaveGame.reset()
	SaveGame.state().settings = settings
	SaveGame.write()
	_start_campaign()


## The first-launch question (PLAN v8 1.9) comes once, before the first session.
func _ask_then(action: Callable) -> void:
	_go_live()
	if bool(SaveGame.setting("asked")) or "--autostart" in OS.get_cmdline_user_args():
		action.call()
		return
	_after_question = action
	flash_panel.visible = true
	continue_button.visible = false
	new_button.visible = false


func answer_flashing(reduce: bool) -> void:
	SaveGame.set_setting("reduce_flashing", reduce)
	SaveGame.set_setting("asked", true)
	flash_panel.visible = false
	new_button.visible = true
	refresh_campaign()
	if _after_question.is_valid():
		var action := _after_question
		_after_question = Callable()
		action.call()


func set_reduce_flashing(on: bool) -> void:
	_go_live()
	SaveGame.set_setting("reduce_flashing", on)


func _start_campaign() -> void:
	CampaignDB.active = true
	Main.next_seed = parse_seed(seed_field.text)
	get_tree().change_scene_to_file(continue_target())


## Where the campaign goes on (M43.2): the game, or the cooking screen once nothing
## playable is left and the next session is still cooking.
static func continue_target() -> String:
	if CampaignDB.is_done() and CampaignDB.cooking() != null:
		return CookingScreen.SCENE
	return GAME_SCENE


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
		var asked := ChangeDB.forks.filter(func(f: Fork) -> bool: return not f.campaign).size()
		line += " · %d/%d forks" % [answered, asked]   # the campaign's forks are not the loop's
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
## The campaign's screen: Continue, else a new campaign (no question; --autostart, bots).
func start() -> void:
	if not legacy_loop:
		_go_live()
		_start_campaign()
		return
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
