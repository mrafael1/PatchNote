class_name StageCard
extends CanvasLayer
## The stage card (PLAN v9 1.2, 2): before a new stage's first session, a black screen,
## "Stage 2", then its title typed at the mascot's speed, with the mascot under it (its
## body, the current look) saying one line. 3 s; any key after 0.5 s closes it.
##
## It is not a session: no telemetry, no version bump. It pauses the game through
## RunState.set_pause(&"stage_card"), like the debrief and the panels, so the intro and
## the cues wait. It counts frame time (deterministic under --fixed-fps). skip() always
## closes it (the bot calls it on the first frame); the 0.5 s gate is only for keys.
##
## Cooking mode (M43.2, G13b; setup() with cooking lines): the cooking screen's card. The
## AI is still building the stage's first session: "Building v0.8.0", a working
## indicator, its progress lines typed one by one with a bar that stalls short of full,
## then "To be continued". It never closes itself: after 0.5 s a key jumps to the end,
## the next key closes it.
##
## Beat mode (M47, D2; setup_beat() before setup()): the session's cook_beat first, a short
## beat of the AI cooking it ("Building v0.8.0", a spinner, its lines one by one, the bar to
## full), then the card as usual (title, mascot line, 3 s). After 0.5 s a key ends the beat,
## the next closes the card; skip() closes it at once. Never the cooking branches.
##
## Door mode (M47.4, PLAN 3.2; setup_door() before setup_beat()): S7's front door first, the
## DoorBeat (<= 12 s: the raw start column, the glitch wipe, the logo, the menu, Options, the
## pause chip, the mascot on the right saying its lines), then the cook beat, re-timed from
## the door's end. After 0.5 s a key ends the door (the cook beat starts); skip() closes all.
## front_door_seen is set and written when the door starts. The beat and cooking boxes sit in
## a framed build window (polish, v9.1); title, mascot line and timings are unchanged.

signal closed

const DURATION := 3.0
const SKIP_AFTER := 0.5
const TITLE_DELAY := 0.3   ## the stage number first, then the title types
const LINE := "Okay. Now we make it a real game."
const LAYER := 95
## Cooking mode (M43.2).
const COOK_LINE := "Give me a minute. I'm cooking."
const END_LINE := "Next time. Promise."
const TO_BE_CONTINUED := "To be continued"
const LINES_FROM := 1.5     ## the first progress line, after the title
const LINE_EVERY := 1.6     ## then one every this many seconds
const BAR_MAX := 0.8        ## the bar stalls here: it is not ready
const SPIN := ["|", "/", "-", "\\"]
const SPIN_HZ := 6.0
const DOTS := [".", "..", "..."]
const DOTS_HZ := 1.5
## Beat mode (M47).
const BEAT_FIRST := 0.5
const BEAT_EVERY := 0.6
const BEAT_FRAME_H := 260.0   ## M47.4: the beat's build window (centred)
const BELOW_FRAME := 16.0     ## M47.4: the mascot's gap under it after the door

var stage := 2
var title := ""
var elapsed := 0.0
var mascot: Mascot
## Cooking mode: the progress lines and the version being built ("" = no label).
var cooking_lines := PackedStringArray()
var building := ""
var ended := false          ## cooking: "To be continued" is up
var shown_lines := 0        ## cooking: progress lines on screen
var gentle := false         ## reduce flashing: dots instead of the spinner
## Beat mode (M47): the beat's lines, and how many are up; beat_done once the card shows.
var beat_lines := PackedStringArray()
var beat_shown := 0
var beat_done := true
var _beat_end := 0.0        ## when the card's own part starts (0: no beat)
var _beat_box: VBoxContainer
var _beat_spinner: Label
var _beat_bar: ProgressBar
var _beat_list: VBoxContainer
## Door mode (M47.4): the door beat's lines; door_done once the cook beat (or the card) is on.
var door_lines: Array[Line] = []
var door_done := true
var door: DoorBeat
var _door_end := 0.0        ## when the door ended (the cook beat's timing starts there)

var _open := false
var _stage_label: Label
var _title_label: Label
var _building_label: Label
var _spinner: Label
var _bar: ProgressBar
var _lines_box: VBoxContainer
var _end_label: Label


func setup(p_stage: int, p_title: String, p_cooking := PackedStringArray(), p_building := "") -> void:
	stage = p_stage
	title = p_title
	cooking_lines = p_cooking
	if p_building != "" or beat_lines.is_empty():   # M47: setup_beat's label stays
		building = p_building


func is_cooking() -> bool:
	return not cooking_lines.is_empty()


## Beat mode (M47): call before setup(). `p_building` is the version label being built.
func setup_beat(lines: PackedStringArray, p_building: String) -> void:
	beat_lines = lines
	building = p_building
	beat_done = lines.is_empty()
	_beat_end = BEAT_FIRST + BEAT_EVERY * lines.size() if not lines.is_empty() else 0.0


func in_beat() -> bool:
	return not beat_done


## Door mode (M47.4): call before setup_beat(). The lines are said at DoorBeat.LINE_AT.
func setup_door(lines: Array[Line]) -> void:
	door_lines = lines
	door_done = lines.is_empty()


func in_door() -> bool:
	return not door_done


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	gentle = SaveGame.reduce_flashing()
	var back := ColorRect.new()
	back.color = Palette.CURTAIN
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(back)
	UiTheme.apply(back)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.offset_top = -110.0
	box.offset_bottom = 10.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	UiTheme.apply(box)
	_stage_label = _label("Stage %d" % stage, 28, Palette.UI_DIM)
	box.add_child(_stage_label)
	_title_label = _label(title, 56, Color.WHITE)
	_title_label.visible_characters = 0
	box.add_child(_title_label)
	if is_cooking():
		_build_cooking()
	elif in_beat():
		_build_beat()
		_stage_label.visible = false
		_title_label.visible = false
	mascot = Mascot.new()
	mascot.name = "CardMascot"
	add_child(mascot)
	mascot.layer = LAYER + 1
	mascot.setup(true, SaveGame.mascot())
	_place_mascot(in_door())
	if in_door():
		_build_door()
	elif not in_beat():
		mascot.say(Line.make(LINE, &"happy"), SessionRunner.PRIORITY)
	if is_cooking():
		mascot.say(Line.make(COOK_LINE, &"thinking"), SessionRunner.PRIORITY)
	_open = true
	RunState.set_pause(&"stage_card", true)


func _build_cooking() -> void:
	_frame(Control.PRESET_CENTER_BOTTOM, Rect2(-290.0, -280.0, 580.0, 260.0))
	var box := VBoxContainer.new()
	box.name = "Cooking"
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_left = -260.0
	box.offset_right = 260.0
	box.offset_bottom = -40.0
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override(&"separation", 6)
	add_child(box)
	UiTheme.apply(box)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(head)
	_building_label = _label("Building %s" % building if building != "" else "Building", 22, Palette.UI_SOFT)
	head.add_child(_building_label)
	_spinner = _label(spinner_text(), 22, Palette.SPINNER)
	_spinner.custom_minimum_size = Vector2(36.0, 0.0)
	head.add_child(_spinner)
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(520.0, 10.0)
	box.add_child(_bar)
	_lines_box = VBoxContainer.new()
	_lines_box.custom_minimum_size = Vector2(520.0, 4 * 24.0)
	box.add_child(_lines_box)
	_end_label = _label(TO_BE_CONTINUED, 30, Color.WHITE)
	_end_label.visible = false
	box.add_child(_end_label)


func _build_beat() -> void:
	var frame := _frame(Control.PRESET_CENTER, Rect2(-290.0, -BEAT_FRAME_H * 0.5, 580.0, BEAT_FRAME_H))
	frame.name = "BeatFrame"
	_beat_box = VBoxContainer.new()
	_beat_box.name = "Beat"
	_beat_box.set_anchors_preset(Control.PRESET_CENTER)
	_beat_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_beat_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_beat_box.offset_left = -260.0
	_beat_box.offset_right = 260.0
	_beat_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_beat_box.add_theme_constant_override(&"separation", 6)
	add_child(_beat_box)
	UiTheme.apply(_beat_box)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	_beat_box.add_child(head)
	head.add_child(_label("Building %s" % building if building != "" else "Building", 22, Palette.UI_SOFT))
	_beat_spinner = _label(spinner_text(), 22, Palette.SPINNER)
	_beat_spinner.custom_minimum_size = Vector2(36.0, 0.0)
	head.add_child(_beat_spinner)
	_beat_bar = ProgressBar.new()
	_beat_bar.min_value = 0.0
	_beat_bar.max_value = 1.0
	_beat_bar.show_percentage = false
	_beat_bar.custom_minimum_size = Vector2(520.0, 10.0)
	_beat_box.add_child(_beat_bar)
	_beat_list = VBoxContainer.new()
	_beat_box.add_child(_beat_list)


## M47.4 (v9.1 polish): the framed build window behind the beat or cooking box (a sibling
## placed first, so nothing moves): the chat window's frame and a "patchnotes · build" bar.
func _frame(preset: Control.LayoutPreset, rect: Rect2) -> Panel:
	var frame := Panel.new()
	frame.name = "Frame"
	frame.set_anchors_preset(preset)
	frame.offset_left = rect.position.x
	frame.offset_top = rect.position.y
	frame.offset_right = rect.end.x
	frame.offset_bottom = rect.end.y
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(frame)
	frame.add_theme_stylebox_override(&"panel", UiTheme.window_style())
	var bar := Label.new()
	bar.name = "Bar"
	bar.text = "patchnotes · build · %s" % (building if building != "" else "next")
	bar.theme_type_variation = UiTheme.CHAT_BAR
	bar.position = Vector2(12, 6)
	frame.add_child(bar)
	add_child(frame)
	return frame


## Door mode (M47.4): the DoorBeat over the card; its lines go to the card's mascot.
func _build_door() -> void:
	if _beat_box != null:
		_beat_box.visible = false
	for n in get_children():
		if n.name == &"BeatFrame":
			(n as Control).visible = false
	door = DoorBeat.new()
	door.name = "Door"
	door.setup(door_lines, false, gentle)
	door.say.connect(func(l: Line) -> void: mascot.say(SessionRunner.with_keys(l), SessionRunner.PRIORITY, true))
	door.finished.connect(_end_door)
	add_child(door)
	Settings.set_value("front_door_seen", true)
	Settings.commit()


## The door is over (its end, a key, skip()): the cook beat from now, or the card.
func _end_door() -> void:
	if door_done:
		return
	door_done = true
	_door_end = elapsed
	door.visible = false
	_place_mascot()
	if not beat_lines.is_empty() and not beat_done:
		# The door's last line is still up: the mascot waits under the build window (tidy).
		mascot.offset.y = get_viewport().get_visible_rect().size.y * 0.5 + BEAT_FRAME_H * 0.5 \
				+ BELOW_FRAME - Mascot.TOP
		_beat_end += _door_end
		_beat_box.visible = true
		for n in get_children():
			if n.name == &"BeatFrame":
				(n as Control).visible = true
	else:
		_beat_end = _door_end
		_stage_label.visible = true
		_title_label.visible = true
		mascot.say(Line.make(LINE, &"happy"), SessionRunner.PRIORITY, true)


## The beat's bar (tests): 0..1, full once every line is up.
func beat_bar() -> float:
	return _beat_bar.value if _beat_bar != null else 1.0


func _beat() -> void:
	var due := clampi(floori((elapsed - _door_end - BEAT_FIRST) / BEAT_EVERY) + 1, 0, beat_lines.size())
	while beat_shown < due:
		_beat_list.add_child(_label(beat_lines[beat_shown], 18, Palette.BEAT_TEXT))
		beat_shown += 1
	_beat_bar.value = float(beat_shown) / float(beat_lines.size())
	_beat_spinner.text = spinner_text()
	if elapsed >= _beat_end:
		_end_beat()


## The beat is over (or skipped by a key): every line up, the bar full, then the card.
func _end_beat() -> void:
	if beat_done:
		return
	while beat_shown < beat_lines.size():
		_beat_list.add_child(_label(beat_lines[beat_shown], 18, Palette.BEAT_TEXT))
		beat_shown += 1
	_beat_bar.value = 1.0
	beat_done = true
	_beat_end = elapsed
	_beat_box.visible = false
	for n in get_children():
		if n.name == &"BeatFrame":
			(n as Control).visible = false
	if not door_lines.is_empty():
		_place_mascot()   # back under the title (it waited under the build window)
	_stage_label.visible = true
	_title_label.visible = true
	mascot.say(Line.make(LINE, &"happy"), SessionRunner.PRIORITY)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	return l


## The mascot sits in the top-right corner of its own layer: shift the layer so the body
## and its bubble (which grows to the left) are centred under the title.
func _place_mascot(at_door := false) -> void:
	var view := get_viewport().get_visible_rect().size
	if at_door:   # M47.4: the door beat's mascot on the right third, by the title's menu
		var body := Vector2(view.x - Mascot.MARGIN - Mascot.SIZE * 0.5, Mascot.TOP + Mascot.SIZE * 0.5)
		mascot.offset = Vector2(view.x * 0.78, view.y * 0.5) - body
		return
	var widest := Mascot.bubble_width(LINE)
	if is_cooking():
		widest = maxf(widest, Mascot.bubble_width(COOK_LINE))
	var group := widest + 10.0 + Mascot.SIZE
	mascot.offset = Vector2(view.x * 0.5 + group * 0.5 - (view.x - Mascot.MARGIN),
			view.y * 0.5 + 40.0 - Mascot.TOP)


func _process(delta: float) -> void:
	if not _open:
		return
	elapsed += delta
	if in_door():
		door.step(delta)
		return
	if in_beat():
		_beat()
		return
	_title_label.visible_characters = int(maxf(0.0, elapsed - _beat_end - TITLE_DELAY) * Mascot.TYPE_CPS)
	if is_cooking():
		_cook()
	elif elapsed - _beat_end >= DURATION:
		close()


## Cooking mode: the lines come one by one, the bar follows them to BAR_MAX, then the end.
func _cook() -> void:
	if ended:
		return
	var due := clampi(floori((elapsed - LINES_FROM) / LINE_EVERY) + 1, 0, cooking_lines.size())
	while shown_lines < due:
		_lines_box.add_child(_label(cooking_lines[shown_lines], 18, Palette.BEAT_TEXT))
		shown_lines += 1
	_bar.value = BAR_MAX * float(shown_lines) / float(cooking_lines.size())
	_spinner.text = spinner_text()
	if elapsed >= LINES_FROM + LINE_EVERY * cooking_lines.size():
		_end()


## The working indicator now: a spinner, or dots with reduce flashing on; "" once ended.
func spinner_text() -> String:
	if ended:
		return ""
	if gentle:
		return DOTS[posmod(floori(elapsed * DOTS_HZ), DOTS.size())]
	return SPIN[posmod(floori(elapsed * SPIN_HZ), SPIN.size())]


## Cooking mode: every line up, the bar stalled, "To be continued".
func _end() -> void:
	if ended or _lines_box == null:
		return
	_title_label.visible_characters = -1
	while shown_lines < cooking_lines.size():
		_lines_box.add_child(_label(cooking_lines[shown_lines], 18, Palette.BEAT_TEXT))
		shown_lines += 1
	ended = true
	_bar.value = BAR_MAX
	_spinner.text = ""
	_end_label.visible = true
	mascot.drop_queued()   # a key jumped here: the cooking line must not follow the promise
	mascot.say(Line.make(END_LINE, &"happy"), SessionRunner.PRIORITY, true)


## What the screen ends on (the bot): "to_be_continued" once a cooking card has ended.
func ending_text() -> String:
	return "to_be_continued" if ended else ""


## The progress lines on screen, in order (tests).
func lines_shown() -> PackedStringArray:
	return cooking_lines.slice(0, shown_lines)


func _input(event: InputEvent) -> void:
	if not _open or elapsed < SKIP_AFTER:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed)
	if pressed:
		get_viewport().set_input_as_handled()
		if in_door():
			mascot.silence()
			door.finish()
		elif is_cooking() and not ended:
			_end()
		elif in_beat():
			# The cook beat gets its own 0.5 s after a door (a double tap must not skip both).
			if door_lines.is_empty() or elapsed - _door_end >= SKIP_AFTER:
				_end_beat()
		elif elapsed - _beat_end >= SKIP_AFTER or _beat_end == 0.0:
			close()


## Closes the card now, whatever its age (the bot, tests). A cooking card ends first.
func skip() -> void:
	if in_door():
		door.finish()
	if is_cooking():
		_end()
	close()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	mascot.silence()
	mascot.visible = false
	RunState.set_pause(&"stage_card", false)
	closed.emit()


func is_open() -> bool:
	return _open


func _exit_tree() -> void:
	if _open:
		_open = false
		RunState.set_pause(&"stage_card", false)
