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

signal closed

const DURATION := 3.0
const SKIP_AFTER := 0.5
const TITLE_DELAY := 0.3   ## the stage number first, then the title types
const LINE := "Okay. Now we make it a real game."
const LAYER := 95

var stage := 2
var title := ""
var elapsed := 0.0
var mascot: Mascot

var _open := false
var _stage_label: Label
var _title_label: Label


func setup(p_stage: int, p_title: String) -> void:
	stage = p_stage
	title = p_title


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(back)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.offset_top = -110.0
	box.offset_bottom = 10.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	_stage_label = _label("Stage %d" % stage, 28, Color(0.75, 0.75, 0.8))
	box.add_child(_stage_label)
	_title_label = _label(title, 56, Color.WHITE)
	_title_label.visible_characters = 0
	box.add_child(_title_label)
	mascot = Mascot.new()
	mascot.name = "CardMascot"
	add_child(mascot)
	mascot.layer = LAYER + 1
	mascot.setup(true, SaveGame.mascot())
	_place_mascot()
	mascot.say(Line.make(LINE, &"happy"), SessionRunner.PRIORITY)
	_open = true
	RunState.set_pause(&"stage_card", true)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	return l


## The mascot sits in the top-right corner of its own layer: shift the layer so the body
## and its bubble (which grows to the left) are centred under the title.
func _place_mascot() -> void:
	var view := get_viewport().get_visible_rect().size
	var group := Mascot.bubble_width(LINE) + 10.0 + Mascot.SIZE
	mascot.offset = Vector2(view.x * 0.5 + group * 0.5 - (view.x - Mascot.MARGIN),
			view.y * 0.5 + 40.0 - Mascot.TOP)


func _process(delta: float) -> void:
	if not _open:
		return
	elapsed += delta
	_title_label.visible_characters = int(maxf(0.0, elapsed - TITLE_DELAY) * Mascot.TYPE_CPS)
	if elapsed >= DURATION:
		close()


func _input(event: InputEvent) -> void:
	if not _open or elapsed < SKIP_AFTER:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed)
	if pressed:
		get_viewport().set_input_as_handled()
		close()


## Closes the card now, whatever its age (the bot, tests).
func skip() -> void:
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
