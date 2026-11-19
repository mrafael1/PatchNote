class_name StartScreen
extends Control
## First screen (PLAN 8): Start, a seed field, fullscreen and master volume.
## The two settings act on the window and the audio server directly and last for the
## session; nothing is saved.

const GAME_SCENE := "res://main.tscn"

var seed_field: LineEdit
var fullscreen: CheckButton
var volume: HSlider
var start_button: Button


func _ready() -> void:
	print("[boot] Patch Notes %s, start screen" % Main.BUILD)
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

	start_button = Button.new()
	start_button.text = "Start"
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


func start() -> void:
	Main.next_seed = parse_seed(seed_field.text)
	get_tree().change_scene_to_file(GAME_SCENE)


func set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func set_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(linear))
	AudioServer.set_bus_mute(0, linear <= 0.0)
